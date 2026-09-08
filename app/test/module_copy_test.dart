import 'dart:convert';
import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/eft.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/domain/module_copy.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Catalogue catalogue;
  setUpAll(() {
    catalogue =
        Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());
  });

  test('real Vexor drone link copies once or fills empty high slots', () {
    final ship = catalogue.byName['vexor']!;
    final type = catalogue.byName['drone link augmentor i']!;
    final fit = Fit.newShip(ship);
    final source = FittedModule(
        typeId: type.id,
        slot: Slot.high,
        index: 0,
        state: defaultModuleState(type));
    fit.modules.add(source);
    final before = jsonEncode(fit.toJson());

    final one =
        planModuleCopies(catalogue: catalogue, fit: fit, source: source);
    expect(one.additions.map((module) => module.index), [1]);
    expect(one.additions.single.typeId, type.id);
    expect(one.additions.single.state, source.state);
    expect(one.additions.single.chargeTypeId, isNull);
    expect(one.reason, isNull);
    expect(one.remainingEmpty, ship.slots[Slot.high]! - 2);

    final fill = planModuleCopies(
        catalogue: catalogue, fit: fit, source: source, fillRemaining: true);
    expect(fill.additions.map((module) => module.index),
        List.generate(ship.slots[Slot.high]! - 1, (index) => index + 1));
    expect(fill.remainingEmpty, 0);
    expect(fill.reason, isNull);
    expect(jsonEncode(fit.toJson()), before);
  });

  test('loaded overloaded gun fills holes with independent module objects', () {
    final fit = Fit.newShip(catalogue.byName['rifter']!);
    final gun = catalogue.byName['200mm autocannon ii']!;
    final ammo = catalogue.byName['emp s']!;
    final source = FittedModule(
        typeId: gun.id,
        slot: Slot.high,
        index: 2,
        state: ModuleState.overloaded,
        chargeTypeId: ammo.id);
    fit.modules.add(source);
    final before = jsonEncode(fit.toJson());
    final plan = planModuleCopies(
        catalogue: catalogue, fit: fit, source: source, fillRemaining: true);
    expect(plan.additions.map((module) => module.index), [0, 1]);
    for (final copy in plan.additions) {
      expect(copy, isNot(same(source)));
      expect(copy.typeId, gun.id);
      expect(copy.slot, Slot.high);
      expect(copy.state, ModuleState.overloaded);
      expect(copy.chargeTypeId, ammo.id);
    }
    expect(plan.additions[0], isNot(same(plan.additions[1])));
    expect(jsonEncode(fit.toJson()), before);
    plan.additions[0].state = ModuleState.offline;
    plan.additions[0].chargeTypeId = null;
    expect(plan.additions[1].state, ModuleState.overloaded);
    expect(plan.additions[1].chargeTypeId, ammo.id);
    expect(source.state, ModuleState.overloaded);
    expect(source.chargeTypeId, ammo.id);
  });

  for (final limit in ['turret', 'group']) {
    test(
        'fill validates progressive $limit limits and keeps valid partial work',
        () {
      final fixture = _syntheticCatalogue(
          slots: 4,
          turretLimit: limit == 'turret' ? 2 : null,
          maxGroup: limit == 'group' ? 2 : null);
      final fit = Fit.newShip(fixture.ships.single);
      final source = _source()..state = ModuleState.online;
      fit.modules.add(source);
      final plan = planModuleCopies(
          catalogue: fixture, fit: fit, source: source, fillRemaining: true);
      expect(plan.additions.map((module) => module.index), [1]);
      expect(plan.remainingEmpty, 2);
      expect(plan.reason, isNotEmpty);
      expect(fit.modules, [source]);
    });
  }

  test('full rack and subsystem copy refuse without replacing existing items',
      () {
    final fixture = _syntheticCatalogue(slots: 2);
    final fit = Fit.newShip(fixture.ships.single);
    final source = _source();
    final second = FittedModule(
        typeId: 2, slot: Slot.high, index: 1, state: ModuleState.online);
    fit.modules.addAll([source, second]);
    final plan = planModuleCopies(
        catalogue: fixture, fit: fit, source: source, fillRemaining: true);
    expect(plan.additions, isEmpty);
    expect(plan.reason, isNotEmpty);
    expect(plan.remainingEmpty, 0);
    expect(fit.modules, [source, second]);

    final tengu = Fit.newShip(catalogue.byName['tengu']!);
    final subsystem = FittedModule(
        typeId: 45626,
        slot: Slot.subsystem,
        index: 0,
        state: ModuleState.offline);
    tengu.modules.add(subsystem);
    final refused =
        planModuleCopies(catalogue: catalogue, fit: tengu, source: subsystem);
    expect(refused.additions, isEmpty);
    expect(refused.reason, isNotEmpty);
    expect(tengu.modules, [subsystem]);
  });

  test(
      'defensive limit never produces a ninth rack index from oversized metadata',
      () {
    final fixture = _syntheticCatalogue(slots: 12);
    final fit = Fit.newShip(fixture.ships.single);
    final source = _source();
    fit.modules.add(source);
    final plan = planModuleCopies(
        catalogue: fixture, fit: fit, source: source, fillRemaining: true);
    expect(plan.additions.length, lessThanOrEqualTo(7));
    expect(
        plan.additions.every((module) => module.index >= 0 && module.index < 8),
        isTrue);
    expect(fit.modules.length, 1);
  });

  test(
      'invalid source state, slot, unknown type and invalid charge are refused',
      () {
    final ship = catalogue.byName['rifter']!;
    final gun = catalogue.byName['200mm autocannon ii']!;
    final gyro = catalogue.byName['gyrostabilizer ii']!;
    final invalid = [
      FittedModule(
          typeId: gyro.id, slot: Slot.low, index: 0, state: ModuleState.active),
      FittedModule(typeId: gun.id, slot: Slot.low, index: 0),
      FittedModule(typeId: 900000001, slot: Slot.high, index: 0),
      FittedModule(
          typeId: gun.id, slot: Slot.high, index: 0, chargeTypeId: 900000002),
      FittedModule(
          typeId: gun.id,
          slot: Slot.high,
          index: 0,
          chargeTypeId: catalogue.byName['scourge heavy missile']!.id),
      FittedModule(typeId: gun.id, slot: Slot.high, index: 8),
    ];
    for (final source in invalid) {
      final fit = Fit.newShip(ship)..modules.add(source);
      final before = jsonEncode(fit.toJson());
      final refused = planModuleCopies(
          catalogue: catalogue, fit: fit, source: source, fillRemaining: true);
      expect(refused.additions, isEmpty, reason: '${source.toJson()}');
      expect(refused.reason, isNotEmpty);
      expect(jsonEncode(fit.toJson()), before);
    }
  });

  test('detached source cannot create copies in a different fitting', () {
    final fixture = _syntheticCatalogue(slots: 4);
    final fit = Fit.newShip(fixture.ships.single);
    final refused =
        planModuleCopies(catalogue: fixture, fit: fit, source: _source());
    expect(refused.additions, isEmpty);
    expect(refused.reason, isNotEmpty);
    expect(fit.modules, isEmpty);
  });

  test('copied modules survive local save and canonical English EFT roundtrip',
      () async {
    final fit = Fit.newShip(catalogue.byName['vexor']!);
    final type = catalogue.byName['drone link augmentor i']!;
    final source = FittedModule(
        typeId: type.id,
        slot: Slot.high,
        index: 0,
        state: defaultModuleState(type));
    fit.modules.add(source);
    final plan = planModuleCopies(
        catalogue: catalogue, fit: fit, source: source, fillRemaining: true);
    fit.modules.addAll(plan.additions);
    final store = MemoryFitStore();
    await store.save([fit]);
    final saved = (await store.load()).single;
    expect(saved.id, fit.id);
    expect(saved.toJson(), fit.toJson());
    final eft = exportEft(saved, catalogue);
    expect(eft, startsWith('[Vexor,'));
    expect(RegExp('Drone Link Augmentor I').allMatches(eft).length,
        fit.modules.length);
    final restored = importEft(eft, catalogue);
    expect(restored.warnings, isEmpty);
    expect(restored.fit.shipTypeId, fit.shipTypeId);
    expect(restored.fit.modules.map((module) => module.toJson()),
        fit.modules.map((module) => module.toJson()));
  });
}

FittedModule _source() => FittedModule(
    typeId: 2, slot: Slot.high, index: 0, state: ModuleState.online);

// Deliberately synthetic fitting restrictions; no gameplay numbers asserted.
Catalogue _syntheticCatalogue(
        {required int slots, int? turretLimit, int? maxGroup}) =>
    Catalogue(
      ships: [
        EveType(id: 1, name: 'Test hull', kind: 'ship', slots: {
          Slot.high: slots
        }, data: {
          'group_id': 10,
          if (turretLimit != null) 'turret_hardpoints': turretLimit,
        })
      ],
      modules: [
        EveType(
            id: 2,
            name: 'Test module',
            kind: 'module',
            slot: Slot.high,
            data: {
              'group_id': 20,
              'supported_states': ['offline', 'online'],
              'default_state': 'online',
              'requires_turret_hardpoint': turretLimit != null,
              if (maxGroup != null) 'max_group_fitted': maxGroup,
              'charge_group_ids': <int>[],
            })
      ],
      charges: [],
      drones: [],
    );
