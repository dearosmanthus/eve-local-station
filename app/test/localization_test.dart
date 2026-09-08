import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/eft.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/domain/universe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Catalogue catalogue;
  late Universe universe;
  setUpAll(() {
    catalogue = Catalogue.decode(
      File('assets/data/catalogue.json').readAsStringSync(),
    );
    universe = Universe.decode(
      File('assets/data/universe.json').readAsStringSync(),
    );
  });

  test('official Chinese labels preserve English identities and search aliases',
      () {
    final rifter = catalogue.byId[587]!;
    expect(rifter.displayName, '裂谷级');
    expect(rifter.groupDisplayName, '护卫舰');
    expect(rifter.name, 'Rifter');
    expect(rifter.group, 'Frigate');
    expect(catalogue.byName['rifter'], same(rifter));
    expect(catalogue.byName.containsKey('裂谷级'), isFalse);
    expect(catalogue.name(587), 'Rifter');
    expect(catalogue.displayName(587), '裂谷级');
    for (final query in [
      '裂谷',
      'rIFter',
      '护卫舰',
      'Frigate',
      '587',
      '裂谷 Frigate'
    ]) {
      expect(rifter.matchesQuery(query), isTrue, reason: query);
    }
    expect(rifter.matchesQuery('Caracal'), isFalse);
    expect(catalogue.displayName(519), '回转稳定器 II');
  });

  test('official Chinese systems and regions keep canonical English lookup',
      () {
    final jita = universe.byId[30000142]!;
    expect(jita.displayName, '吉他');
    expect(jita.name, 'Jita');
    expect(jita.regionDisplayName, '伏尔戈');
    expect(universe.regions[10000002], 'The Forge');
    expect(universe.regionDisplayNames[10000002], '伏尔戈');
    expect(universe.regionDisplayName(10000002), '伏尔戈');
    for (final query in ['吉他', 'jITA', '伏尔戈', 'The Forge', '30000142']) {
      expect(jita.matchesQuery(query), isTrue, reason: query);
    }
    expect(jita.matchesQuery('Amarr'), isFalse);
  });

  test('missing or blank official translation falls back without invention',
      () {
    // Synthetic missing-translation fixture; no gameplay statistics asserted.
    final type = EveType(
      id: 9000001,
      name: 'Untranslated fixture',
      kind: 'module',
      group: 'Fixture group',
      data: {'name_zh': '  ', 'group_name_zh': ''},
    );
    expect(type.displayName, type.name);
    expect(type.groupDisplayName, type.group);
    final actualMissing = catalogue.byId[84992]!;
    expect(actualMissing.displayName, actualMissing.name);
    const system = SolarSystem(
      id: 9000001,
      name: 'Fixture system',
      regionId: 9000002,
      regionName: 'Fixture region',
      security: 0,
      x: 0,
      y: 0,
      z: 0,
      nameZh: ' ',
    );
    expect(system.displayName, system.name);
    expect(system.regionDisplayName, system.regionName);
  });

  test('Chinese display and fit title retain interoperable English EFT names',
      () {
    final fit = Fit.newShip(catalogue.byId[587]!);
    fit.modules.add(FittedModule(
      typeId: 2889,
      slot: Slot.high,
      index: 0,
      chargeTypeId: 185,
    ));
    final text = exportEft(fit, catalogue);
    expect(fit.name, '裂谷级 · 新装配');
    expect(text, startsWith('[Rifter, 裂谷级 · 新装配]'));
    expect(text, contains('200mm AutoCannon II, EMP S'));
    expect(text, isNot(contains('200mm自动加农炮')));
    final restored = importEft(text, catalogue);
    expect(restored.warnings, isEmpty);
    expect(restored.fit.shipTypeId, 587);
    expect(restored.fit.modules.single.typeId, 2889);
    expect(restored.fit.modules.single.chargeTypeId, 185);
    expect(restored.fit.name, fit.name);
  });
}
