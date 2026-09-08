import 'catalogue.dart';
import 'compatibility.dart';
import 'fit.dart';

class EftImport {
  EftImport(this.fit, this.warnings);
  final Fit fit;
  final List<String> warnings;
}

/// EFT names use the English names from the local Tranquility catalogue.
/// Unsupported or ambiguous lines are reported, never silently interpreted.
EftImport importEft(String text, Catalogue catalogue) {
  final lines = text.replaceAll('\r', '').split('\n');
  final first = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (first < 0) throw const FormatException('装配文本为空');
  final header = RegExp(
    r'^\[([^,]+),\s*(.*)\]$',
  ).firstMatch(lines[first].trim());
  if (header == null) {
    throw const FormatException('首行格式应为 [Ship name, Fit name]');
  }
  final ship = catalogue.byName[header[1]!.trim().toLowerCase()];
  if (ship == null || ship.kind != 'ship') {
    throw FormatException('本地数据中找不到舰船：${header[1]}');
  }
  final fit = Fit.newShip(ship)..name = header[2]!.trim();
  if (fit.name.isEmpty) fit.name = ship.displayName;
  // EFT lists low/high slots before subsystems. Discover subsystem modifiers
  // first so genuine strategic-cruiser modules are not discarded as overflow.
  final preview = fit.copy();
  final families = ship.integers('subsystem_families');
  for (final line in lines.skip(first + 1)) {
    final type = catalogue.byName[line.split(',').first.trim().toLowerCase()];
    if (type?.slot != Slot.subsystem) continue;
    final familyIndex = families.indexOf(
      type!.integer('subsystem_family') ?? -1,
    );
    preview.modules.add(
      FittedModule(
        typeId: type.id,
        slot: Slot.subsystem,
        index: familyIndex >= 0 ? familyIndex : preview.modules.length,
      ),
    );
  }
  final slots = fitLayout(catalogue, preview).slots;
  final warnings = <String>[];
  final cursors = {for (final slot in Slot.values) slot: 0};
  for (var i = first + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final empty = RegExp(
      r'^\[Empty (Low|Med|High|Rig|Subsystem) slot\]$',
      caseSensitive: false,
    ).firstMatch(line);
    if (empty != null) {
      final slot = switch (empty[1]!.toLowerCase()) {
        'low' => Slot.low,
        'med' => Slot.medium,
        'high' => Slot.high,
        'rig' => Slot.rig,
        _ => Slot.subsystem,
      };
      cursors[slot] = cursors[slot]! + 1;
      continue;
    }
    final quantity = RegExp(r'^(.*) x(\d+)$').firstMatch(line);
    if (quantity != null) {
      final type = catalogue.byName[quantity[1]!.trim().toLowerCase()];
      final count = int.parse(quantity[2]!);
      if (type?.kind == 'drone' && count > 0 && count <= 1000) {
        fit.drones.add(FittedDrone(typeId: type!.id, quantity: count));
      } else {
        warnings.add('第 ${i + 1} 行未导入（货舱/未知物品或数量无效）：$line');
      }
      continue;
    }
    final parts = line.split(',');
    final module = catalogue.byName[parts.first.trim().toLowerCase()];
    if (module == null || module.kind != 'module' || module.slot == null) {
      warnings.add('第 ${i + 1} 行未导入：$line');
      continue;
    }
    final slot = module.slot!;
    final familyIndex = slot == Slot.subsystem
        ? families.indexOf(module.integer('subsystem_family') ?? -1)
        : -1;
    final index = familyIndex >= 0 ? familyIndex : cursors[slot]!;
    if (index >= (slots[slot] ?? 0) || fit.at(slot, index) != null) {
      warnings.add('第 ${i + 1} 行超出${slot.label}数量：${module.displayName}');
      continue;
    }
    int? chargeId;
    if (parts.length > 1) {
      final charge =
          catalogue.byName[parts.skip(1).join(',').trim().toLowerCase()];
      if (charge?.kind == 'charge') {
        chargeId = charge!.id;
      } else {
        warnings.add('第 ${i + 1} 行弹药未导入：${parts.skip(1).join(',')}');
      }
    }
    fit.modules.add(
      FittedModule(
        typeId: module.id,
        slot: slot,
        index: index,
        state: defaultModuleState(module),
        chargeTypeId: chargeId,
      ),
    );
    cursors[slot] = index + 1;
  }
  return EftImport(fit, warnings);
}

String exportEft(Fit fit, Catalogue catalogue) {
  final slots = fitLayout(catalogue, fit).slots;
  String safe(String text) => text.replaceAll(RegExp(r'[\r\n\[\]]'), ' ');
  final lines = <String>[
    '[${catalogue.name(fit.shipTypeId)}, ${safe(fit.name)}]',
  ];
  const emptyNames = {
    Slot.low: 'Low',
    Slot.medium: 'Med',
    Slot.high: 'High',
    Slot.rig: 'Rig',
    Slot.subsystem: 'Subsystem',
  };
  for (final slot in [
    Slot.low,
    Slot.medium,
    Slot.high,
    Slot.rig,
    Slot.subsystem,
  ]) {
    for (var i = 0; i < (slots[slot] ?? 0); i++) {
      final module = fit.at(slot, i);
      if (module == null) {
        lines.add('[Empty ${emptyNames[slot]} slot]');
      } else {
        lines.add(
          '${catalogue.name(module.typeId)}'
          '${module.chargeTypeId == null ? '' : ', ${catalogue.name(module.chargeTypeId!)}'}',
        );
      }
    }
    lines.add('');
  }
  for (final drone in fit.drones) {
    lines.add('${catalogue.name(drone.typeId)} x${drone.quantity}');
  }
  return '${lines.join('\n').trimRight()}\n';
}
