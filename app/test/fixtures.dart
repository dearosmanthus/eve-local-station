import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/universe.dart';

// Deliberately small, synthetic fixtures are test-only, never shipped as assets.
Catalogue testCatalogue() => Catalogue(
      ships: [
        EveType(
          id: 587,
          name: 'Rifter',
          kind: 'ship',
          group: 'Frigate',
          slots: {Slot.high: 3, Slot.medium: 3, Slot.low: 3, Slot.rig: 3},
        ),
      ],
      modules: [
        EveType(
          id: 101,
          name: '200mm AutoCannon II',
          kind: 'module',
          group: 'Projectile Weapon',
          slot: Slot.high,
        ),
        EveType(
          id: 102,
          name: 'Small Shield Booster I',
          kind: 'module',
          slot: Slot.medium,
        ),
        EveType(
            id: 103, name: 'Damage Control II', kind: 'module', slot: Slot.low),
      ],
      charges: [EveType(id: 201, name: 'EMP S', kind: 'charge')],
      drones: [EveType(id: 301, name: 'Hobgoblin II', kind: 'drone')],
    );

Universe testUniverse() => Universe(
      [
        system(1, 'Jita', 0.9, 0, 0),
        system(2, 'LowSec', 0.2, 50, 80),
        system(3, 'Amarr', 1.0, 200, 0),
        system(4, 'HighSec A', 0.8, 40, -70),
        system(5, 'HighSec B', 0.6, 160, -90),
        system(6, 'Isolated', -0.3, 350, 250),
      ],
      const [Gate(1, 2), Gate(2, 3), Gate(1, 4), Gate(4, 5), Gate(5, 3)],
    );

SolarSystem system(int id, String name, double security, double x, double z) =>
    SolarSystem(
      id: id,
      name: name,
      regionId: 10,
      regionName: 'Test Region',
      security: security,
      x: x,
      y: 0,
      z: z,
    );
