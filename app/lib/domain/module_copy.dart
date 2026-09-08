import 'catalogue.dart';
import 'compatibility.dart';
import 'fit.dart';

class ModuleCopyPlan {
  ModuleCopyPlan({
    required List<FittedModule> additions,
    required this.remainingEmpty,
    this.reason,
  }) : additions = List.unmodifiable(additions);

  final List<FittedModule> additions;
  final int remainingEmpty;
  final String? reason;
}

/// Plans bounded, independent copies without changing the user's fit. Each
/// candidate sees earlier accepted copies, so group and hardpoint limits also
/// apply to a batch. CPU/PG remain native skill/effect-aware calculations.
ModuleCopyPlan planModuleCopies({
  required Catalogue catalogue,
  required Fit fit,
  required FittedModule source,
  bool fillRemaining = false,
}) {
  final count = (fitLayout(catalogue, fit).slots[source.slot] ?? 0).clamp(0, 8);
  final empty = [
    for (var index = 0; index < count; index++)
      if (fit.at(source.slot, index) == null) index,
  ];
  ModuleCopyPlan refuse(String reason) => ModuleCopyPlan(
      additions: [], remainingEmpty: empty.length, reason: reason);
  final occupants = fit.modules.where(
      (module) => module.slot == source.slot && module.index == source.index);
  if (occupants.length != 1 ||
      occupants.single.typeId != source.typeId ||
      occupants.single.state != source.state ||
      occupants.single.chargeTypeId != source.chargeTypeId) {
    return refuse('原模块已变化，请重新选择后复制');
  }
  if (catalogue.byId[fit.shipTypeId]?.kind != 'ship') {
    return refuse('本地目录缺少当前舰船，暂时无法判断可用槽位');
  }
  final type = catalogue.byId[source.typeId];
  if (type == null || type.kind != 'module') {
    return refuse('本地目录缺少原模块，暂时无法复制');
  }
  if (source.index < 0 || source.index >= count) {
    return refuse('原模块超出当前舰船槽位，请先调整装配');
  }
  if (!supportedModuleStates(type).contains(source.state)) {
    return refuse('原模块不支持当前${source.state.label}状态，请先选择可用状态');
  }
  if (source.chargeTypeId != null) {
    final charge = catalogue.byId[source.chargeTypeId];
    if (charge == null || charge.kind != 'charge') {
      return refuse('原模块的弹药无法识别，请先卸下或更换弹药');
    }
    final issues = chargeCompatibility(type, charge);
    if (issues.isNotEmpty) {
      return refuse('原模块弹药不兼容：${issues.join('；')}');
    }
  }
  final sourceIssues = moduleCompatibility(
      module: type,
      catalogue: catalogue,
      fit: fit,
      slot: source.slot,
      index: source.index);
  if (sourceIssues.isNotEmpty) {
    return refuse('请先调整原模块：${sourceIssues.join('；')}');
  }
  if (source.slot == Slot.subsystem) {
    return refuse('同类子系统只能安装一个，无法复制');
  }
  if (empty.isEmpty) {
    return refuse('当前${source.slot.label}已满，没有可复制的空槽');
  }
  final staged = fit.copy();
  final additions = <FittedModule>[];
  String? firstReason;
  for (final index in empty) {
    final issues = moduleCompatibility(
        module: type,
        catalogue: catalogue,
        fit: staged,
        slot: source.slot,
        index: index);
    if (issues.isNotEmpty) {
      firstReason ??= issues.join('；');
      continue;
    }
    final copy = FittedModule(
        typeId: source.typeId,
        slot: source.slot,
        index: index,
        state: source.state,
        chargeTypeId: source.chargeTypeId);
    additions.add(copy);
    staged.modules.add(copy);
    if (!fillRemaining) break;
  }
  final remaining = empty.length - additions.length;
  return ModuleCopyPlan(
      additions: additions,
      remainingEmpty: remaining,
      reason: additions.isEmpty || (fillRemaining && remaining > 0)
          ? firstReason ?? '没有兼容的空槽'
          : null);
}
