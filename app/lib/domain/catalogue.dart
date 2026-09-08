import 'dart:convert';

enum Slot {
  high('高槽', 'high'),
  medium('中槽', 'medium'),
  low('低槽', 'low'),
  rig('改装件', 'rig'),
  subsystem('子系统', 'subsystem');

  const Slot(this.label, this.key);
  final String label;
  final String key;

  static Slot? parse(Object? value) {
    for (final slot in values) {
      if (slot.key == value) return slot;
    }
    return null;
  }
}

class EveType {
  EveType({
    required this.id,
    required this.name,
    required this.kind,
    this.group = '',
    this.slot,
    this.slots = const {},
    this.data = const {},
  });

  final int id;
  final String name;
  final String kind;
  final String group;
  final Slot? slot;
  final Map<Slot, int> slots;
  final Map<String, dynamic> data;

  // Canonical English names remain the keys used by EFT and external tools.
  String get displayName => _translation('name_zh') ?? name;
  String get groupDisplayName => _translation('group_name_zh') ?? group;

  String? _translation(String key) {
    final value = data[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  List<String> get searchAliases =>
      [name, displayName, group, groupDisplayName, '$id'];

  bool matchesQuery(String query) {
    final text = searchAliases.join('\n').toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  num? number(String key) => data[key] is num ? data[key] as num : null;
  int? integer(String key) => number(key)?.toInt();
  List<int> integers(String key) => (data[key] as List<dynamic>? ?? [])
      .whereType<num>()
      .map((value) => value.toInt())
      .toList();
  int? get groupId => integer('group_id');
  int? get marketGroupId => integer('market_group_id');

  factory EveType.fromJson(Map<String, dynamic> json, String kind) => EveType(
        id: (json['type_id'] as num).toInt(),
        name: json['name'] as String,
        kind: kind,
        group: json['group_name'] as String? ?? '',
        slot: Slot.parse(json['slot_type']),
        data: json,
        slots: {
          for (final slot in Slot.values)
            slot: ((json['${slot.key}_slots'] as num?) ?? 0).toInt(),
        },
      );
}

class MarketGroup {
  const MarketGroup({
    required this.id,
    this.parentId,
    required this.name,
    this.nameZh,
  });

  final int id;
  final int? parentId;
  final String name;
  final String? nameZh;

  String get displayName =>
      nameZh?.trim().isNotEmpty == true ? nameZh!.trim() : name;

  factory MarketGroup.fromJson(Map<String, dynamic> json) => MarketGroup(
        id: (json['id'] as num).toInt(),
        parentId: (json['parent_id'] as num?)?.toInt(),
        name: json['name'] as String,
        nameZh: json['name_zh'] as String?,
      );
}

class Catalogue {
  Catalogue({
    required this.ships,
    required this.modules,
    required this.charges,
    required this.drones,
    this.provenance = const {},
    this.marketGroups = const {},
  }) {
    for (final type in [...ships, ...modules, ...charges, ...drones]) {
      byId[type.id] = type;
      byName[type.name.toLowerCase()] = type;
    }
  }

  final List<EveType> ships;
  final List<EveType> modules;
  final List<EveType> charges;
  final List<EveType> drones;
  final Map<String, dynamic> provenance;
  final Map<int, MarketGroup> marketGroups;
  final Map<int, EveType> byId = {};
  final Map<String, EveType> byName = {};

  factory Catalogue.decode(String data) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported catalogue schema');
    }
    List<EveType> read(String key, String kind) =>
        (json[key] as List<dynamic>? ?? [])
            .map((v) => EveType.fromJson(v as Map<String, dynamic>, kind))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return Catalogue(
      ships: read('ships', 'ship'),
      modules: read('modules', 'module'),
      charges: read('charges', 'charge'),
      drones: read('drones', 'drone'),
      provenance: json['provenance'] as Map<String, dynamic>? ?? {},
      marketGroups: {
        for (final row in json['market_groups'] as List<dynamic>? ?? [])
          (row['id'] as num).toInt():
              MarketGroup.fromJson(row as Map<String, dynamic>),
      },
    );
  }

  String name(int id) => byId[id]?.name ?? 'Unknown type #$id';
  String displayName(int id) => byId[id]?.displayName ?? '未知物品 #$id';
}
