import 'dart:io';

import 'package:eve_local_station/domain/universe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Universe universe;
  setUpAll(() {
    universe = Universe.decode(
      File('assets/data/universe.json').readAsStringSync(),
    );
  });

  test('official Jita details join constellation and star without changing IDs',
      () {
    final jita = universe.byId[30000142]!;
    expect(jita.name, 'Jita');
    expect(jita.constellationId, 20000020);
    expect(jita.constellationName, 'Kimotoro');
    expect(jita.constellationDisplayName, '木本呂');
    expect(jita.planetCount, 8);
    expect(jita.starId, 40009076);
    expect(jita.starSpectralClass, 'F1 V');
    expect(jita.securityClass, 'B');
    expect(jita.security, 0.945913);
    expect(jita.matchesQuery('Kimotoro'), isTrue);
    expect(jita.matchesQuery('木本呂'), isTrue);
    expect(universe.neighbors[jita.id], hasLength(7));
  });

  test(
      'system and constellation class IDs stay separate with no inferred label',
      () {
    final sentinel = universe.byId[31000001]!;
    expect(sentinel.wormholeClassId, 14);
    expect(sentinel.constellationWormholeClassId, 1);
    expect(sentinel.securityClass, isNull);
    expect(
        sentinel.security, -0.99); // raw source precision/sign remains intact
    expect(sentinel.planetCount, 7);
    expect(sentinel.starSpectralClass, 'A0IV2');
    final jita = universe.byId[30000142]!;
    expect(jita.wormholeClassId, isNull);
    expect(jita.constellationWormholeClassId, 7);
  });

  test('old const fixtures and absent detail fields remain backward compatible',
      () {
    const original = SolarSystem(
      id: 1,
      name: 'Synthetic system',
      regionId: 2,
      regionName: 'Synthetic region',
      security: -0.2,
      x: 0,
      y: 0,
      z: 0,
    );
    expect(original.constellationId, isNull);
    expect(original.constellationDisplayName, isEmpty);
    expect(original.planetCount, isNull);
    expect(original.starSpectralClass, isNull);
    final decoded = SolarSystem.fromJson({
      'id': 1,
      'name': original.name,
      'region_id': 2,
      'region_name': original.regionName,
      'security': -0.2,
      'x': 0,
      'y': 0,
      'z': 0,
      'constellation_name': 'Synthetic constellation',
      'constellation_name_zh': ' ',
    });
    expect(decoded.constellationDisplayName, 'Synthetic constellation');
    expect(decoded.planetCount, isNull);
    expect(decoded.starId, isNull);
    expect(decoded.security, original.security);
  });
}
