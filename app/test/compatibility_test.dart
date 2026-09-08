import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/compatibility.dart';
import 'package:eve_local_station/domain/eft.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalogue = Catalogue.decode(
    File('assets/data/catalogue.json').readAsStringSync(),
  );
  EveType named(String name) => catalogue.byName[name.toLowerCase()]!;

  test(
      'real SDE effect states default correctly and EFT never activates passive equipment',
      () {
    final gyro = named('Gyrostabilizer II');
    final rig = named('Small Projectile Burst Aerator I');
    final gun = named('200mm AutoCannon II');
    final subsystem = catalogue.byId[45601]!;
    expect(defaultModuleState(gyro), ModuleState.online);
    expect(
        supportedModuleStates(gyro), [ModuleState.offline, ModuleState.online]);
    expect(defaultModuleState(rig), ModuleState.online);
    expect(defaultModuleState(subsystem), ModuleState.offline);
    expect(moduleStateLabel(subsystem, ModuleState.offline), '被动');
    expect(defaultModuleState(gun), ModuleState.active);
    final fit = importEft(
            '[Rifter, Passive test]\nGyrostabilizer II\n\n200mm AutoCannon II, EMP S\n\nSmall Projectile Burst Aerator I',
            catalogue)
        .fit;
    expect(fit.at(Slot.low, 0)!.state, ModuleState.online);
    expect(fit.at(Slot.rig, 0)!.state, ModuleState.online);
    expect(
        fittingCompatibilityIssues(catalogue, fit)
            .where((issue) => issue.contains('状态')),
        isEmpty);
    fit.at(Slot.low, 0)!.state = ModuleState.overloaded;
    expect(
        fittingCompatibilityIssues(catalogue, fit)
            .any((issue) => issue.contains('不支持当前过载状态')),
        isTrue);
    expect(fit.at(Slot.low, 0)!.state, ModuleState.overloaded,
        reason:
            'An explicitly stored state is diagnosed, never silently rewritten');
  });

  test(
    'real projectile and launcher ammunition follow group and optional size metadata',
    () {
      final gun = named('200mm AutoCannon II');
      expect(chargeCompatibility(gun, named('EMP S')), isEmpty);
      expect(chargeCompatibility(gun, named('EMP M')), contains('弹药尺寸不兼容'));
      expect(
        chargeCompatibility(gun, named('Scourge Heavy Missile')),
        contains('弹药组别不兼容'),
      );
      expect(
        chargeCompatibility(
          named('Heavy Missile Launcher II'),
          named('Scourge Heavy Missile'),
        ),
        isEmpty,
        reason:
            'Missiles legitimately lack charge_size; absence must not become an exclusion',
      );
      expect(
        chargeCompatibility(named('Damage Control II'), named('EMP S')),
        contains('此模块不装载弹药'),
      );
    },
  );

  test(
    'rig size, turret hardpoints and replacement of existing gun use real SDE',
    () {
      final fit = Fit.newShip(named('Rifter'));
      final largeRig = named('Large Trimark Armor Pump I');
      expect(
        moduleCompatibility(
          module: largeRig,
          catalogue: catalogue,
          fit: fit,
          slot: Slot.rig,
          index: 0,
        ),
        contains('改装件尺寸与舰船不符'),
      );
      final gun = named('200mm AutoCannon II');
      final turretCount = named('Rifter').integer('turret_hardpoints')!;
      for (var index = 0; index < turretCount; index++) {
        fit.modules.add(
          FittedModule(typeId: gun.id, slot: Slot.high, index: index),
        );
      }
      expect(
        moduleCompatibility(
          module: gun,
          catalogue: catalogue,
          fit: fit,
          slot: Slot.high,
          index: 0,
        ),
        isNot(contains('没有剩余炮台挂点')),
      );
      expect(
        moduleCompatibility(
          module: gun,
          catalogue: catalogue,
          fit: fit,
          slot: Slot.high,
          index: turretCount,
        ),
        contains('没有剩余炮台挂点'),
      );
    },
  );

  test(
    'static resource sums and missing compatibility metadata never invent exclusions',
    () {
      final ship = EveType(
        id: 1,
        name: 'Test',
        kind: 'ship',
        slots: {Slot.high: 1},
        data: {'base_cpu_output': 1},
      );
      final module = EveType(
        id: 2,
        name: 'Unknown',
        kind: 'module',
        slot: Slot.high,
        data: {'base_cpu': 500},
      );
      final local = Catalogue(
        ships: [ship],
        modules: [module],
        charges: [],
        drones: [],
      );
      expect(
        moduleCompatibility(
          module: module,
          catalogue: local,
          fit: Fit.newShip(ship),
          slot: Slot.high,
          index: 0,
        ),
        isEmpty,
      );
      expect(
        chargeCompatibility(
          module,
          EveType(id: 3, name: 'Unknown charge', kind: 'charge'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'strategic cruiser subsystem families produce slots, preserve EFT and flag overflow after removal',
    () {
      final ship = named('Tengu');
      final offensive = catalogue.byId[45601]!;
      final core = catalogue.byId[45626]!;
      final fit = Fit.newShip(ship)
        ..modules.add(
          FittedModule(typeId: offensive.id, slot: Slot.subsystem, index: 2),
        )
        ..modules.add(
          FittedModule(typeId: core.id, slot: Slot.subsystem, index: 0),
        );
      final layout = fitLayout(catalogue, fit);
      expect(layout.slots[Slot.subsystem], 4);
      expect(layout.slots[Slot.high], greaterThan(0));
      expect(layout.launcherHardpoints, 6);
      final launcher = named('Heavy Missile Launcher II');
      fit.modules.add(
        FittedModule(typeId: launcher.id, slot: Slot.high, index: 0),
      );
      final imported = importEft(exportEft(fit, catalogue), catalogue);
      expect(imported.warnings, isEmpty);
      expect(imported.fit.at(Slot.high, 0)!.typeId, launcher.id);
      expect(imported.fit.at(Slot.subsystem, 2)!.typeId, offensive.id);
      fit.modules.removeWhere((module) => module.typeId == offensive.id);
      expect(
        fittingCompatibilityIssues(
          catalogue,
          fit,
        ).any((issue) => issue.contains('超出当前舰船槽位')),
        isTrue,
      );
      expect(
        fit.modules.any((module) => module.typeId == launcher.id),
        isTrue,
        reason: 'Dynamic slot changes preserve the user module for repair',
      );
    },
  );

  test(
    'ship group and type lists form an OR while required ship type is separate',
    () {
      final ship = EveType(
        id: 10,
        name: 'Ship',
        kind: 'ship',
        slots: {Slot.high: 2},
        data: {'group_id': 20},
      );
      final local = Catalogue(
        ships: [ship],
        modules: [],
        charges: [],
        drones: [],
      );
      EveType module(Map<String, dynamic> data) => EveType(
            id: 30,
            name: 'Module',
            kind: 'module',
            slot: Slot.high,
            data: data,
          );
      final fit = Fit.newShip(ship);
      expect(
        moduleCompatibility(
          module: module({
            'fit_ship_type_ids': [10],
            'fit_ship_group_ids': [99],
          }),
          catalogue: local,
          fit: fit,
          slot: Slot.high,
          index: 0,
        ),
        isEmpty,
      );
      expect(
        moduleCompatibility(
          module: module({
            'fit_ship_type_ids': [99],
            'fit_ship_group_ids': [20],
          }),
          catalogue: local,
          fit: fit,
          slot: Slot.high,
          index: 0,
        ),
        isEmpty,
      );
      expect(
        moduleCompatibility(
          module: module({
            'fit_ship_type_ids': [10],
            'required_ship_type_id': 99,
          }),
          catalogue: local,
          fit: fit,
          slot: Slot.high,
          index: 0,
        ),
        contains('仅适用于另一种舰船'),
      );
    },
  );
}
