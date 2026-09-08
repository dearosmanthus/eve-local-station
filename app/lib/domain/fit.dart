import 'catalogue.dart';

enum ModuleState {
  offline('离线'),
  online('在线'),
  active('激活'),
  overloaded('过载');

  const ModuleState(this.label);
  final String label;
}

List<ModuleState> supportedModuleStates(EveType type) {
  final names = type.data['supported_states'];
  if (names is! List) return ModuleState.values;
  final states =
      ModuleState.values.where((state) => names.contains(state.name)).toList();
  return states.isEmpty ? ModuleState.values : states;
}

ModuleState defaultModuleState(EveType type) {
  final supported = supportedModuleStates(type);
  final requested = type.data['default_state'];
  for (final state in supported) {
    if (state.name == requested) return state;
  }
  if (supported.contains(ModuleState.active)) return ModuleState.active;
  if (supported.contains(ModuleState.online)) return ModuleState.online;
  return supported.first;
}

String moduleStateLabel(EveType? type, ModuleState state) {
  if (type != null &&
      state == ModuleState.offline &&
      supportedModuleStates(type).length == 1) {
    return '被动';
  }
  return state.label;
}

class FittedModule {
  FittedModule({
    required this.typeId,
    required this.slot,
    required this.index,
    this.state = ModuleState.active,
    this.chargeTypeId,
  });

  final int typeId;
  final Slot slot;
  final int index;
  ModuleState state;
  int? chargeTypeId;

  Map<String, dynamic> toJson() => {
        'type_id': typeId,
        'slot': slot.key,
        'index': index,
        'state': state.name,
        if (chargeTypeId != null) 'charge_type_id': chargeTypeId,
      };

  factory FittedModule.fromJson(Map<String, dynamic> json) => FittedModule(
        typeId: _integer(json['type_id'], 'module type_id', minimum: 1),
        slot: Slot.parse(json['slot']) ??
            (throw const FormatException('Unknown stored module slot')),
        index: _integer(json['index'], 'module index'),
        state: ModuleState.values.firstWhere(
          (state) => state.name == json['state'],
          orElse: () =>
              throw const FormatException('Unknown stored module state'),
        ),
        chargeTypeId: json['charge_type_id'] == null
            ? null
            : _integer(json['charge_type_id'], 'charge type_id', minimum: 1),
      );
}

class FittedDrone {
  FittedDrone({required this.typeId, this.quantity = 1, this.active = true});
  final int typeId;
  int quantity;
  bool active;

  Map<String, dynamic> toJson() => {
        'type_id': typeId,
        'quantity': quantity,
        'active': active,
      };

  factory FittedDrone.fromJson(Map<String, dynamic> json) => FittedDrone(
        typeId: _integer(json['type_id'], 'drone type_id', minimum: 1),
        quantity: _integer(json['quantity'], 'drone quantity', minimum: 1),
        active: json['active'] as bool? ?? true,
      );
}

class Fit {
  Fit({
    required this.id,
    required this.name,
    required this.shipTypeId,
    List<FittedModule>? modules,
    List<FittedDrone>? drones,
    this.skillMode = 'all5',
  })  : modules = modules ?? [],
        drones = drones ?? [];

  final String id;
  String name;
  final int shipTypeId;
  final List<FittedModule> modules;
  final List<FittedDrone> drones;
  String skillMode;

  factory Fit.newShip(EveType ship) => Fit(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '${ship.displayName} · 新装配',
        shipTypeId: ship.id,
      );

  FittedModule? at(Slot slot, int index) {
    for (final module in modules) {
      if (module.slot == slot && module.index == index) return module;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ship_type_id': shipTypeId,
        'skill_mode': skillMode,
        'modules': modules.map((module) => module.toJson()).toList(),
        'drones': drones.map((drone) => drone.toJson()).toList(),
      };

  factory Fit.fromJson(Map<String, dynamic> json) => Fit(
        id: json['id'] as String,
        name: json['name'] as String,
        shipTypeId: _integer(json['ship_type_id'], 'ship_type_id', minimum: 1),
        skillMode: json['skill_mode'] as String? ?? 'all5',
        modules: (json['modules'] as List<dynamic>? ?? [])
            .map((m) => FittedModule.fromJson(m as Map<String, dynamic>))
            .toList(),
        drones: (json['drones'] as List<dynamic>? ?? [])
            .map((m) => FittedDrone.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  Fit copy() => Fit.fromJson(toJson());
}

int _integer(Object? value, String field, {int minimum = 0}) {
  if (value is! int || value < minimum) {
    throw FormatException('Invalid stored $field');
  }
  return value;
}
