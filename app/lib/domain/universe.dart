import 'dart:convert';

class SolarSystem {
  const SolarSystem({
    required this.id,
    required this.name,
    required this.regionId,
    required this.regionName,
    required this.security,
    required this.x,
    required this.y,
    required this.z,
    this.nameZh,
    this.regionNameZh,
    this.constellationId,
    this.constellationName = '',
    this.constellationNameZh,
    this.securityClass,
    this.wormholeClassId,
    this.constellationWormholeClassId,
    this.planetCount,
    this.starId,
    this.starSpectralClass,
  });

  final int id;
  final String name;
  final int regionId;
  final String regionName;
  final double security;
  final double x;
  final double y;
  final double z;
  final String? nameZh;
  final String? regionNameZh;
  final int? constellationId;
  final String constellationName;
  final String? constellationNameZh;
  final String? securityClass;
  // Raw SDE values, kept separate without guessed inheritance or C1-C6 labels.
  final int? wormholeClassId;
  final int? constellationWormholeClassId;
  final int? planetCount;
  final int? starId;
  final String? starSpectralClass;

  String get displayName =>
      nameZh?.trim().isNotEmpty == true ? nameZh!.trim() : name;
  String get regionDisplayName => regionNameZh?.trim().isNotEmpty == true
      ? regionNameZh!.trim()
      : regionName;
  String get constellationDisplayName =>
      constellationNameZh?.trim().isNotEmpty == true
          ? constellationNameZh!.trim()
          : constellationName;
  List<String> get searchAliases => [
        name,
        displayName,
        regionName,
        regionDisplayName,
        constellationName,
        constellationDisplayName,
        '$id',
      ];

  bool matchesQuery(String query) {
    final text = searchAliases.join('\n').toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  // Tranquility classifies high security using the displayed rounded rating.
  bool get isHighSecurity => security >= 0.45;
  bool get isLowSecurity => !isHighSecurity && security > 0;
  double get displayedSecurity => security.clamp(0, 1).toDouble();

  factory SolarSystem.fromJson(Map<String, dynamic> json) => SolarSystem(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        regionId: (json['region_id'] as num).toInt(),
        regionName: json['region_name'] as String? ?? '',
        security: (json['security'] as num).toDouble(),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        z: (json['z'] as num).toDouble(),
        nameZh: json['name_zh'] as String?,
        regionNameZh: json['region_name_zh'] as String?,
        constellationId: (json['constellation_id'] as num?)?.toInt(),
        constellationName: json['constellation_name'] as String? ?? '',
        constellationNameZh: json['constellation_name_zh'] as String?,
        securityClass: json['security_class'] as String?,
        wormholeClassId: (json['wormhole_class_id'] as num?)?.toInt(),
        constellationWormholeClassId:
            (json['constellation_wormhole_class_id'] as num?)?.toInt(),
        planetCount: (json['planet_count'] as num?)?.toInt(),
        starId: (json['star_id'] as num?)?.toInt(),
        starSpectralClass: json['star_spectral_class'] as String?,
      );
}

class Gate {
  const Gate(this.from, this.to);
  final int from;
  final int to;
}

class Universe {
  Universe(this.systems, this.gates, {this.provenance = const {}}) {
    for (final system in systems) {
      byId[system.id] = system;
      neighbors[system.id] = [];
      regions[system.regionId] = system.regionName;
      regionDisplayNames[system.regionId] = system.regionDisplayName;
    }
    for (final gate in gates) {
      if (byId.containsKey(gate.from) && byId.containsKey(gate.to)) {
        neighbors[gate.from]!.add(gate.to);
        neighbors[gate.to]!.add(gate.from);
      }
    }
    for (final entries in neighbors.values) {
      entries.sort();
    }
  }

  final List<SolarSystem> systems;
  final List<Gate> gates;
  final Map<String, dynamic> provenance;
  final Map<int, SolarSystem> byId = {};
  final Map<int, List<int>> neighbors = {};
  final Map<int, String> regions = {};
  final Map<int, String> regionDisplayNames = {};

  String regionDisplayName(int id) =>
      regionDisplayNames[id] ?? regions[id] ?? '未知星域 #$id';

  factory Universe.decode(String data) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported universe schema');
    }
    return Universe(
      (json['systems'] as List<dynamic>)
          .map((v) => SolarSystem.fromJson(v as Map<String, dynamic>))
          .toList(),
      (json['gates'] as List<dynamic>)
          .map(
            (v) => Gate((v['from'] as num).toInt(), (v['to'] as num).toInt()),
          )
          .toList(),
      provenance: json['provenance'] as Map<String, dynamic>? ?? {},
    );
  }
}

enum RoutePreference { shortest, preferHighSec }

class RouteResult {
  const RouteResult(this.systemIds, this.cost);
  final List<int> systemIds;
  final int cost;
  int get jumps => systemIds.isEmpty ? 0 : systemIds.length - 1;
}

/// Static gate routing. This never models temporary wormholes, player bridges,
/// live gate camps, sovereignty, ship restrictions or dynamic connections.
RouteResult? planRoute(
  Universe universe,
  int start,
  int end, {
  RoutePreference preference = RoutePreference.shortest,
  Set<int> avoided = const {},
}) {
  if (!universe.byId.containsKey(start) ||
      !universe.byId.containsKey(end) ||
      avoided.contains(start) ||
      avoided.contains(end)) {
    return null;
  }
  final costs = <int, int>{start: 0};
  final previous = <int, int>{};
  final queue = _MinHeap()..add(_Visit(start, 0));
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    if (current.cost != costs[current.id]) continue;
    if (current.id == end) {
      final path = <int>[end];
      while (path.last != start) {
        path.add(previous[path.last]!);
      }
      return RouteResult(path.reversed.toList(), current.cost);
    }
    for (final neighbor in universe.neighbors[current.id] ?? <int>[]) {
      if (avoided.contains(neighbor)) continue;
      final system = universe.byId[neighbor]!;
      final weight =
          preference == RoutePreference.shortest || system.isHighSecurity
              ? 1
              : system.isLowSecurity
                  ? 26
                  : 101;
      final cost = current.cost + weight;
      if (cost < (costs[neighbor] ?? 0x7fffffffffffffff)) {
        costs[neighbor] = cost;
        previous[neighbor] = current.id;
        queue.add(_Visit(neighbor, cost));
      }
    }
  }
  return null;
}

class _Visit {
  const _Visit(this.id, this.cost);
  final int id;
  final int cost;
}

class _MinHeap {
  final List<_Visit> _items = [];
  bool get isNotEmpty => _items.isNotEmpty;

  bool _before(_Visit a, _Visit b) =>
      a.cost < b.cost || (a.cost == b.cost && a.id < b.id);

  void add(_Visit entry) {
    _items.add(entry);
    var index = _items.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (!_before(_items[index], _items[parent])) break;
      final swap = _items[parent];
      _items[parent] = _items[index];
      _items[index] = swap;
      index = parent;
    }
  }

  _Visit removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isEmpty) return first;
    _items[0] = last;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _items.length) break;
      final right = left + 1;
      final child =
          right < _items.length && _before(_items[right], _items[left])
              ? right
              : left;
      if (!_before(_items[child], _items[index])) break;
      final swap = _items[index];
      _items[index] = _items[child];
      _items[child] = swap;
      index = child;
    }
    return first;
  }
}
