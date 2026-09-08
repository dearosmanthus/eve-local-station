import 'dart:convert';
import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/eft.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('Static route planning', () {
    test(
      'shortest and high-security preferences choose different actual gate paths',
      () {
        final universe = testUniverse();
        expect(planRoute(universe, 1, 3)!.systemIds, [1, 2, 3]);
        final safer = planRoute(
          universe,
          1,
          3,
          preference: RoutePreference.preferHighSec,
        )!;
        expect(safer.systemIds, [1, 4, 5, 3]);
        expect(safer.jumps, 3);
        for (var i = 1; i < safer.systemIds.length; i++) {
          expect(
            universe.neighbors[safer.systemIds[i - 1]],
            contains(safer.systemIds[i]),
          );
        }
      },
    );

    test('avoided systems cannot leak into path, including endpoints', () {
      final universe = testUniverse();
      expect(planRoute(universe, 1, 3, avoided: {2})!.systemIds, [1, 4, 5, 3]);
      expect(planRoute(universe, 1, 3, avoided: {2, 4}), isNull);
      expect(planRoute(universe, 1, 3, avoided: {1}), isNull);
      expect(planRoute(universe, 1, 3, avoided: {3}), isNull);
    });

    test(
      'disconnected and invalid systems report no route; same system is zero jumps',
      () {
        final universe = testUniverse();
        expect(planRoute(universe, 1, 6), isNull);
        expect(planRoute(universe, -1, 3), isNull);
        expect(planRoute(universe, 1, 1)!.jumps, 0);
        expect(planRoute(universe, 3, 1)!.systemIds, [3, 2, 1]);
      },
    );
  });

  group('EFT interoperability', () {
    final catalogue = testCatalogue();
    test(
      'round trip preserves explicit empty slots, ammunition and drone quantities',
      () {
        final imported = importEft(
          '[Rifter, Example]\nDamage Control II\n\nSmall Shield Booster I\n\n[Empty High slot]\n200mm AutoCannon II, EMP S\n\nHobgoblin II x5',
          catalogue,
        );
        expect(imported.warnings, isEmpty);
        final second = importEft(
          exportEft(imported.fit, catalogue),
          catalogue,
        ).fit;
        expect(second.shipTypeId, 587);
        expect(second.at(Slot.high, 0), isNull);
        expect(second.at(Slot.high, 1)!.chargeTypeId, 201);
        expect(second.drones.single.quantity, 5);
        expect(second.modules.length, 3);
      },
    );

    test(
      'unknown ships fail and unsupported items/overflow are visible warnings',
      () {
        expect(
          () => importEft('[Not A Ship, X]', catalogue),
          throwsFormatException,
        );
        final result = importEft(
          '[Rifter, X]\nUnknown Item\n200mm AutoCannon II\n200mm AutoCannon II\n200mm AutoCannon II\n200mm AutoCannon II\nEMP S x300',
          catalogue,
        );
        expect(result.fit.modules.length, 3);
        expect(result.warnings.length, 3);
      },
    );

    test('native request uses one slot field and valid in-bay drone state', () {
      final fit = Fit.newShip(catalogue.ships.single)
        ..modules.add(
          FittedModule(
            typeId: 101,
            slot: Slot.high,
            index: 1,
            state: ModuleState.overloaded,
            chargeTypeId: 201,
          ),
        )
        ..drones.add(FittedDrone(typeId: 301, quantity: 5, active: false));
      final request = buildEngineRequest(fit, '/local/engine');
      expect(request['data_path'], '/local/engine');
      final payload = request['fit'] as Map<String, dynamic>;
      expect(payload['skill_mode'], 'all5');
      final module = (payload['modules'] as List).single as Map;
      expect(module['slot_type'], 'high');
      expect(module.containsKey('slot'), isFalse);
      expect(module['state'], 'overloaded');
      expect(((payload['drones'] as List).single as Map)['state'], 'online');
      expect(jsonDecode(jsonEncode(request)), request);
    });

    test(
      'missing engine data produces unavailable state with no invented numbers',
      () {
        final result = decodeCalculation(
          '{"ok":false,"error":{"code":"DATA_MISSING","message":"Local PB2 data missing"}}',
        );
        expect(result.available, isFalse);
        expect(result.code, 'DATA_MISSING');
        expect(result.stats, isEmpty);
        final ok = decodeCalculation(
          '{"ok":true,"result":{"stats":{"cpu_used":17.25},"diagnostics":[]}}',
        );
        expect(ok.stats, {'cpu_used': 17.25});
        expect(ok.stats.containsKey('dps'), isFalse);
      },
    );

    test(
      'corrupt stored module metadata is rejected instead of silently changed',
      () {
        final json = FittedModule(
          typeId: 101,
          slot: Slot.high,
          index: 0,
        ).toJson();
        expect(
          () => FittedModule.fromJson({...json, 'slot': 'future-slot'}),
          throwsFormatException,
        );
        expect(
          () => FittedModule.fromJson({...json, 'state': 'future-state'}),
          throwsFormatException,
        );
        expect(
          () => FittedModule.fromJson({...json, 'index': -1}),
          throwsFormatException,
        );
        expect(
          () => FittedModule.fromJson({...json, 'type_id': 1.5}),
          throwsFormatException,
        );
      },
    );
  });

  test(
    'local file survives reload, preserves states, and rejects incompatible schema',
    () async {
      final directory = await Directory.systemTemp.createTemp('els-test-');
      try {
        final store = LocalFitStore(directory);
        final fit = Fit.newShip(testCatalogue().ships.single)
          ..modules.add(
            FittedModule(
              typeId: 101,
              slot: Slot.high,
              index: 0,
              state: ModuleState.offline,
            ),
          )
          ..drones.add(FittedDrone(typeId: 301, quantity: 2, active: false));
        await store.save([fit]);
        final reloaded = (await LocalFitStore(directory).load()).single;
        expect(reloaded.toJson(), fit.toJson());
        reloaded.name = 'Updated';
        await store.save([reloaded]);
        expect((await store.load()).single.name, 'Updated');
        expect(
          await File('${directory.path}/fits-v1.json.tmp').exists(),
          isFalse,
        );
        await File(
          '${directory.path}/fits-v1.json',
        ).writeAsString('{"schemaVersion":999,"fits":[]}');
        await expectLater(store.load(), throwsFormatException);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
