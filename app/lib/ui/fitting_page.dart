import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/catalogue.dart';
import '../domain/compatibility.dart';
import '../domain/eft.dart';
import '../domain/fit.dart';
import '../domain/module_copy.dart';
import '../services/engine.dart';
import '../services/local_store.dart';
import 'theme.dart';
import 'type_picker.dart';
import 'stat_details.dart';

class FittingPage extends StatefulWidget {
  const FittingPage({
    required this.catalogue,
    required this.store,
    required this.engine,
    super.key,
  });
  final Catalogue catalogue;
  final FitStore store;
  final FittingEngine engine;
  @override
  State<FittingPage> createState() => _FittingPageState();
}

class _FittingPageState extends State<FittingPage> {
  List<Fit> _saved = [];
  Fit? _fit;
  bool _dirty = false;
  bool _loading = true;
  bool _saving = false;
  String? _storageError;
  Calculation? _calculation;
  bool _calculating = false;
  Timer? _debounce;
  int _generation = 0;
  String _rackFilter = 'all';
  final ScrollController _equipmentScroll = ScrollController();
  VoidCallback? _refreshStatsSheet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _equipmentScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fits = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _saved = fits;
        _fit = fits.isEmpty ? null : fits.first.copy();
        _loading = false;
        _storageError = null;
      });
      _scheduleCalculation();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _storageError = '$error';
      });
    }
  }

  void _changed([VoidCallback? change]) {
    setState(() {
      change?.call();
      _dirty = true;
    });
    _scheduleCalculation();
  }

  void _scheduleCalculation() {
    _debounce?.cancel();
    final fit = _fit;
    final generation = ++_generation;
    if (fit == null) return;
    setState(() {
      _calculating = true;
      _calculation = null;
    });
    _refreshStatsSheet?.call();
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final result = await widget.engine.calculate(fit.copy());
      if (!mounted || generation != _generation) return;
      setState(() {
        _calculation = result;
        _calculating = false;
      });
      _refreshStatsSheet?.call();
    });
  }

  Future<bool> _save() async {
    if (_fit == null || _saving) return false;
    if (_storageError != null) {
      notice(context, '装配文件未成功读取，请先修复读取问题，避免覆盖现有文件。');
      return false;
    }
    final snapshot = _fit!.copy();
    final updated = _saved.map((fit) => fit.copy()).toList();
    final index = updated.indexWhere((fit) => fit.id == snapshot.id);
    if (index < 0) {
      updated.insert(0, snapshot);
    } else {
      updated[index] = snapshot;
    }
    setState(() => _saving = true);
    try {
      await widget.store.save(updated);
      if (!mounted) return false;
      setState(() {
        _saved = updated;
        _dirty = false;
        _saving = false;
      });
      notice(context, '已保存到本机');
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _saving = false);
      notice(context, '保存失败：$error');
      return false;
    }
  }

  Future<bool> _leaveFit() async {
    if (!_dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存这份装配？'),
        content: const Text('当前装配有未保存的更改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('放弃更改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (choice == 'save') return _save();
    return choice == 'discard';
  }

  Future<void> _newFit() async {
    if (!await _leaveFit() || !mounted) return;
    final ship = await pickType(
      context,
      title: '选择舰船',
      types: widget.catalogue.ships,
      catalogue: widget.catalogue,
    );
    if (ship == null || !mounted) return;
    setState(() {
      _fit = Fit.newShip(ship);
      _dirty = true;
      _rackFilter = 'all';
    });
    _scheduleCalculation();
  }

  Future<void> _open(Fit fit) async {
    if (!await _leaveFit() || !mounted) return;
    setState(() {
      _fit = fit.copy();
      _dirty = false;
      _rackFilter = 'all';
    });
    _scheduleCalculation();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _fit!.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('装配名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          onSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // The route may animate out after its future completes; retain controller
    // through the end of this frame before disposing it.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (name == null || name.trim().isEmpty || !mounted) return;
    _changed(() => _fit!.name = name.trim());
  }

  Future<void> _delete() async {
    final fit = _fit;
    if (fit == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地装配？'),
        content: Text('“${fit.name}”会从此设备移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving || _storageError != null) {
      return;
    }
    final updated = _saved.where((entry) => entry.id != fit.id).toList();
    setState(() => _saving = true);
    try {
      await widget.store.save(updated);
      if (!mounted) return;
      setState(() {
        _saved = updated;
        _fit = updated.isEmpty ? null : updated.first.copy();
        _dirty = false;
        _saving = false;
      });
      _scheduleCalculation();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      notice(context, '删除失败：$error');
    }
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 EFT 装配'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 7,
            maxLines: 14,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              hintText: '[Rifter, My fit]\n\n200mm AutoCannon II, EMP S',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final text = await Clipboard.getData(Clipboard.kTextPlain);
              if (context.mounted && text?.text != null) {
                controller.text = text!.text!;
              }
            },
            child: const Text('粘贴'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('读取'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (raw == null || !mounted) return;
    try {
      final result = importEft(raw, widget.catalogue);
      if (result.warnings.isNotEmpty) {
        final accept = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('部分内容需要留意'),
            content: SingleChildScrollView(
              child: Text(
                '${result.fit.name}\n已识别 ${result.fit.modules.length} 个模块、${result.fit.drones.length} 组无人机。\n\n${result.warnings.join('\n')}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('导入已识别内容'),
              ),
            ],
          ),
        );
        if (accept != true || !mounted) return;
      }
      if (!await _leaveFit() || !mounted) return;
      setState(() {
        _fit = result.fit;
        _dirty = true;
        _rackFilter = 'all';
      });
      _scheduleCalculation();
    } on FormatException catch (error) {
      if (mounted) notice(context, error.message);
    }
  }

  Future<void> _export() async {
    if (_fit == null) return;
    final text = exportEft(_fit!, widget.catalogue);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) notice(context, 'EFT 已复制。模块状态、技能等级和无人机启用状态不包含在 EFT 格式中。');
  }

  Future<void> _addModule(Slot slot, int index) async {
    final type = await pickType(
      context,
      title: '选择${slot.label}模块',
      catalogue: widget.catalogue,
      types:
          widget.catalogue.modules.where((type) => type.slot == slot).toList(),
      hint: '按舰船限制、改装件尺寸、挂点及模块数量筛选。关闭筛选可查看全部同槽模块。',
      incompatibility: (type) {
        final issues = moduleCompatibility(
          module: type,
          catalogue: widget.catalogue,
          fit: _fit!,
          slot: slot,
          index: index,
        );
        return issues.isEmpty ? null : issues.join(' · ');
      },
    );
    if (type == null || !mounted) return;
    _changed(() {
      _fit!.modules.removeWhere(
        (module) => module.slot == slot && module.index == index,
      );
      _fit!.modules.add(
        FittedModule(
            typeId: type.id,
            slot: slot,
            index: index,
            state: defaultModuleState(type)),
      );
    });
  }

  Future<void> _charge(FittedModule module) async {
    final type = await pickType(
      context,
      title: '选择装载弹药',
      catalogue: widget.catalogue,
      types: widget.catalogue.charges,
      hint: '根据当前模块的弹药组别、尺寸与容量筛选。',
      incompatibility: (type) {
        final equipped = widget.catalogue.byId[module.typeId];
        if (equipped == null) return null;
        final issues = chargeCompatibility(equipped, type);
        return issues.isEmpty ? null : issues.join(' · ');
      },
    );
    if (type == null || !mounted) return;
    _changed(() => module.chargeTypeId = type.id);
  }

  Future<void> _addDrone() async {
    final type = await pickType(
      context,
      title: '添加无人机',
      catalogue: widget.catalogue,
      types: widget.catalogue.drones,
    );
    if (type == null || !mounted) return;
    _changed(() {
      final index = _fit!.drones.indexWhere((drone) => drone.typeId == type.id);
      if (index >= 0) {
        _fit!.drones[index].quantity++;
      } else {
        _fit!.drones.add(FittedDrone(typeId: type.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final fit = _fit;
    if (fit == null) {
      return Column(children: [
        _toolbar(),
        if (_storageError != null) _storageNotice(),
        Expanded(
            child: Center(
                child: SingleChildScrollView(
                    child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('暂无本地装配', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text('选择舰船开始，或导入已有装配。',
                style: TextStyle(fontSize: 12, color: StationColors.muted)),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: _newFit,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建装配')),
            TextButton(onPressed: _import, child: const Text('导入 EFT')),
          ]),
        )))),
      ]);
    }
    final ship = widget.catalogue.byId[fit.shipTypeId];
    final layout = fitLayout(widget.catalogue, fit);
    final hasDrones = (_calculation?.stats['drone_bay_capacity'] ?? 0) > 0 ||
        (ship?.number('drone_capacity') ?? 1) > 0 ||
        (layout.slots[Slot.subsystem] ?? 0) > 0 ||
        fit.drones.isNotEmpty;
    final filters = <String, String>{
      'all': '全部',
      for (final slot in Slot.values)
        if ((layout.slots[slot] ?? 0) > 0 ||
            fit.modules.any((module) => module.slot == slot))
          slot.key: slot == Slot.rig
              ? '改装'
              : slot == Slot.subsystem
                  ? '子系'
                  : slot.label,
      if (hasDrones) 'drones': '无人机',
    };
    final filter = filters.containsKey(_rackFilter) ? _rackFilter : 'all';
    final showFilters =
        layout.slots.values.fold<int>(0, (total, value) => total + value) > 9 ||
            fit.drones.length > 2;
    final issues = <String>{
      ...fittingCompatibilityIssues(widget.catalogue, fit),
      ...?_calculation?.diagnostics
    }.toList();
    return Column(children: [
      _toolbar(),
      _summaryStrip(),
      if (_storageError != null) _storageNotice(),
      if (issues.isNotEmpty)
        SizedBox(
            height: 44,
            child: InkWell(
              onTap: _showStatistics,
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: StationColors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text('${issues.length} 项提示，点此检查',
                            style: const TextStyle(
                                fontSize: 11, color: StationColors.amber),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.chevron_right,
                        size: 16, color: StationColors.muted),
                  ])),
            )),
      if (showFilters)
        SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (final item in filters.entries)
                  TextButton(
                    key: ValueKey('rack-filter-${item.key}'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: filter == item.key
                          ? Theme.of(context).colorScheme.primary
                          : StationColors.muted,
                      backgroundColor: filter == item.key
                          ? StationColors.panel
                          : Colors.transparent,
                      shape: const RoundedRectangleBorder(),
                      textStyle:
                          const TextStyle(fontSize: 12, fontFamily: 'Roboto'),
                    ),
                    onPressed: () {
                      setState(() => _rackFilter = item.key);
                      if (_equipmentScroll.hasClients) {
                        _equipmentScroll.jumpTo(0);
                      }
                    },
                    child: Text(item.value),
                  )
              ],
            )),
      Expanded(
          child: ListView(
        key: const ValueKey('fitting-equipment-scroll'),
        controller: _equipmentScroll,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final slot in Slot.values)
            if ((filter == 'all' || filter == slot.key) &&
                (layout.slots[slot] ?? 0) > 0) ...[
              _rackHeader(slot.label,
                  '${fit.modules.where((module) => module.slot == slot && module.index < (layout.slots[slot] ?? 0)).length}/${layout.slots[slot]}'),
              for (var index = 0; index < layout.slots[slot]!; index++)
                _moduleRow(slot, index),
            ],
          if (fit.modules.any((module) =>
              module.index >= (layout.slots[module.slot] ?? 0) &&
              (filter == 'all' || filter == module.slot.key))) ...[
            _rackHeader('超出当前槽位', '保留待调整'),
            for (final module in fit.modules)
              if (module.index >= (layout.slots[module.slot] ?? 0) &&
                  (filter == 'all' || filter == module.slot.key))
                _moduleRow(module.slot, module.index),
          ],
          if (hasDrones && (filter == 'all' || filter == 'drones')) ...[
            _rackHeader('无人机舱',
                '${fit.drones.fold<int>(0, (sum, drone) => sum + drone.quantity)} 架'),
            for (final drone in fit.drones) _droneRow(drone),
            SizedBox(
                height: 44,
                child: TextButton.icon(
                  onPressed: _saving ? null : _addDrone,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加无人机', style: TextStyle(fontSize: 12)),
                )),
          ],
          if ((layout.slots[Slot.subsystem] ?? 0) > 0 &&
              (filter == 'all' || filter == Slot.subsystem.key))
            const Padding(
                padding: EdgeInsets.all(12),
                child: Text('子系统会改变槽位和挂点；移除后超出的模块仍会保留。',
                    style:
                        TextStyle(fontSize: 11, color: StationColors.muted))),
        ],
      )),
    ]);
  }

  String _displayFitName(Fit fit) {
    final ship = widget.catalogue.byId[fit.shipTypeId];
    if (ship != null && fit.name == '${ship.name} · 新装配') {
      return '${ship.displayName} · 新装配';
    }
    return fit.name;
  }

  Widget _toolbar() {
    final fit = _fit;
    return SizedBox(
        height: 52,
        child: Row(children: [
          Expanded(
              child: InkWell(
            key: const ValueKey('saved-fits-button'),
            onTap: _saving ? null : _showSaved,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 3, 2, 3),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            fit == null
                                ? '本地装配'
                                : widget.catalogue.displayName(fit.shipTypeId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        if (fit != null)
                          Text(
                              '${_dirty ? '未保存 · ' : ''}${_displayFitName(fit)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _dirty
                                      ? StationColors.amber
                                      : StationColors.muted)),
                      ])),
                  const Icon(Icons.arrow_drop_down,
                      size: 18, color: StationColors.muted),
                ])),
          )),
          IconButton(
              tooltip: '新建装配',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: _saving ? null : _newFit,
              icon: const Icon(Icons.add, size: 21)),
          IconButton(
              tooltip: '保存到本机',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: _saving || fit == null ? null : _save,
              icon: Icon(_saving ? Icons.hourglass_empty : Icons.save_outlined,
                  size: 20)),
          PopupMenuButton<String>(
            tooltip: '更多装配操作',
            enabled: !_saving,
            constraints: const BoxConstraints(minWidth: 160),
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _newFit();
                case 'open':
                  _showSaved();
                case 'import':
                  _import();
                case 'export':
                  _export();
                case 'rename':
                  _rename();
                case 'stats':
                  _showStatistics();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('本地装配')),
              const PopupMenuItem(value: 'import', child: Text('导入 EFT')),
              if (fit != null) ...[
                const PopupMenuItem(value: 'export', child: Text('复制 EFT')),
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                const PopupMenuItem(value: 'stats', child: Text('全部属性与技能')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('删除装配')),
              ],
            ],
          ),
        ]));
  }

  Future<void> _showSaved() async {
    final selected = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
          heightFactor: 0.65,
          child: Column(children: [
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text('本地装配（${_saved.length}）',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'new'),
                      child: const Text('新建')),
                ])),
            Expanded(
                child: _saved.isEmpty
                    ? const Center(child: Text('还没有保存的装配'))
                    : ListView.separated(
                        itemCount: _saved.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final fit = _saved[index];
                          return ListTile(
                            dense: true,
                            title: Text(_displayFitName(fit),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                widget.catalogue.displayName(fit.shipTypeId)),
                            trailing: fit.id == _fit?.id
                                ? const Icon(Icons.check, size: 18)
                                : null,
                            onTap: () => Navigator.pop(context, fit),
                          );
                        },
                      )),
          ])),
    );
    if (!mounted) return;
    if (selected is Fit) await _open(selected);
    if (selected == 'new') await _newFit();
  }

  Widget _storageNotice() => SizedBox(
      height: 44,
      child: TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.warning_amber_rounded,
            size: 17, color: StationColors.amber),
        label: const Text('本地装配读取失败，点此重试',
            style: TextStyle(fontSize: 11, color: StationColors.amber)),
      ));

  Widget _summaryStrip() {
    final stats = _calculation?.stats ?? const <String, num>{};
    String number(String key, {int decimals = 1}) {
      final value = stats[key];
      if (value == null) return '—';
      if (value.abs() >= 1000000) {
        return '${(value / 1000000).toStringAsFixed(1)}M';
      }
      if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
      return value.toStringAsFixed(decimals);
    }

    final unavailable = _calculation != null && !_calculation!.available;
    final values = <String, String>{
      'CPU': '${number('cpu_used')}/${number('cpu_output')}',
      '能量栅格': '${number('powergrid_used')}/${number('powergrid_output')}',
      'DPS': number('dps'),
      if (unavailable)
        '计算不可用': '查看原因 ›'
      else
        '有效生命 ›': number('ehp', decimals: 0),
    };
    return Tooltip(
        message: '全部属性与技能',
        child: Semantics(
          label: _calculating ? '正在计算装配属性' : '装配属性摘要，点击查看全部属性',
          button: true,
          child: InkWell(
            key: const ValueKey('fitting-summary'),
            onTap: _showStatistics,
            child: SizedBox(
                height: 52,
                child: Stack(children: [
                  Positioned.fill(
                      child: Row(children: [
                    for (final entry in values.entries)
                      Expanded(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(entry.key,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: StationColors.muted)),
                              const SizedBox(height: 2),
                              Text(entry.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ))
                  ])),
                  if (_calculating)
                    const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(minHeight: 1)),
                  const Positioned(
                      left: 0, right: 0, bottom: 0, child: Divider(height: 1)),
                ])),
          ),
        ));
  }

  Widget _rackHeader(String title, String count) => Container(
        height: 28,
        color: StationColors.panel,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(count,
              style: const TextStyle(fontSize: 10, color: StationColors.muted))
        ]),
      );

  Widget _moduleRow(Slot slot, int index) {
    final module = _fit!.at(slot, index);
    final type = module == null ? null : widget.catalogue.byId[module.typeId];
    final hasCharge = module?.chargeTypeId != null;
    return SizedBox(
      key: ValueKey('fit-slot-${slot.key}-$index'),
      height: hasCharge ? 52 : 44,
      child: DecoratedBox(
        decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: StationColors.border, width: 0.5))),
        child: Row(children: [
          Expanded(
              child: InkWell(
            onTap: _saving
                ? null
                : module == null
                    ? () => _addModule(slot, index)
                    : () => _moduleActions(module),
            child: SizedBox.expand(
                child: Row(children: [
              SizedBox(
                  width: 30,
                  child: Text('${index + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10, color: StationColors.muted))),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              module == null
                                  ? '空槽'
                                  : widget.catalogue.displayName(module.typeId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: module == null
                                      ? StationColors.muted
                                      : null)),
                          if (hasCharge)
                            Text(
                                widget.catalogue
                                    .displayName(module!.chargeTypeId!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 10, color: StationColors.muted)),
                        ],
                      ))),
              if (module == null)
                const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child:
                        Icon(Icons.add, size: 16, color: StationColors.muted)),
            ])),
          )),
          if (module != null) ...[
            SizedBox(
                width: 44,
                height: 44,
                child: PopupMenuButton<ModuleState>(
                  tooltip: '模块状态：${moduleStateLabel(type, module.state)}',
                  enabled: !_saving,
                  onSelected: (state) => _changed(() => module.state = state),
                  itemBuilder: (context) => (type == null
                          ? ModuleState.values
                          : supportedModuleStates(type))
                      .map((state) => PopupMenuItem(
                            value: state,
                            child: Text(moduleStateLabel(type, state)),
                          ))
                      .toList(),
                  child: Center(
                      child: Text(moduleStateLabel(type, module.state),
                          style: TextStyle(
                              fontSize: 10,
                              color: module.state == ModuleState.overloaded
                                  ? StationColors.amber
                                  : module.state == ModuleState.offline
                                      ? StationColors.muted
                                      : Theme.of(context)
                                          .colorScheme
                                          .primary))),
                )),
            IconButton(
                tooltip: '移除模块',
                constraints:
                    const BoxConstraints.tightFor(width: 44, height: 44),
                onPressed: _saving
                    ? null
                    : () => _changed(() => _fit!.modules.remove(module)),
                icon: const Icon(Icons.close, size: 17)),
          ],
        ]),
      ),
    );
  }

  Future<void> _moduleActions(FittedModule module) async {
    final type = widget.catalogue.byId[module.typeId];
    final stats = _calculation?.moduleFor(module.slot, module.index);
    final canCharge = module.chargeTypeId != null ||
        !(type?.data.containsKey('charge_group_ids') ?? false) ||
        (type?.integers('charge_group_ids').isNotEmpty ?? false);
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.catalogue.displayName(module.typeId),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                            if (type != null)
                              Text(type.name,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: StationColors.muted)),
                          ])),
                  _actionTile(context, '更换模块', Icons.swap_horiz, 'replace'),
                  _actionTile(context, '复制一个', Icons.copy_outlined, 'copy'),
                  _actionTile(context, '填满剩余同类槽位', Icons.playlist_add, 'fill'),
                  if (canCharge)
                    _actionTile(
                        context,
                        module.chargeTypeId == null ? '装填弹药' : '更换弹药',
                        Icons.inventory_2_outlined,
                        'charge'),
                  if (module.chargeTypeId != null)
                    _actionTile(
                        context, '卸下弹药', Icons.remove_circle_outline, 'unload'),
                  if (stats != null && stats.stats.isNotEmpty)
                    _actionTile(context, '查看计算属性', Icons.insights, 'stats'),
                  _actionTile(context, '移除模块', Icons.close, 'remove'),
                ],
              ))),
    );
    if (!mounted) return;
    switch (action) {
      case 'replace':
        await _addModule(module.slot, module.index);
      case 'copy':
        _copyModule(module);
      case 'fill':
        _copyModule(module, fillRemaining: true);
      case 'charge':
        await _charge(module);
      case 'unload':
        _changed(() => module.chargeTypeId = null);
      case 'stats':
        if (stats != null) {
          await showModuleStatistics(
              context, widget.catalogue.displayName(module.typeId), stats,
              canonicalName: type?.name);
        }
      case 'remove':
        _changed(() => _fit!.modules.remove(module));
    }
  }

  void _copyModule(FittedModule source, {bool fillRemaining = false}) {
    final fit = _fit;
    if (fit == null || _saving) return;
    final plan = planModuleCopies(
        catalogue: widget.catalogue,
        fit: fit,
        source: source,
        fillRemaining: fillRemaining);
    if (plan.additions.isEmpty) {
      notice(context, plan.reason ?? '没有兼容的空槽');
      return;
    }
    _changed(() => fit.modules.addAll(plan.additions));
    notice(
        context,
        plan.reason == null
            ? '已复制 ${plan.additions.length} 个模块'
            : '已复制 ${plan.additions.length} 个；${plan.reason}');
  }

  Widget _actionTile(
          BuildContext context, String label, IconData icon, String value) =>
      ListTile(
        dense: true,
        minTileHeight: 48,
        leading: Icon(icon, size: 19),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        onTap: () => Navigator.pop(context, value),
      );

  Widget _droneRow(FittedDrone drone) => SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: const BoxDecoration(
            border: Border(
                bottom: BorderSide(color: StationColors.border, width: .5))),
        child: Row(children: [
          SizedBox(
              width: 44,
              height: 44,
              child: Checkbox(
                  value: drone.active,
                  onChanged: _saving
                      ? null
                      : (value) =>
                          _changed(() => drone.active = value ?? false))),
          Expanded(
              child: Text(widget.catalogue.displayName(drone.typeId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12))),
          IconButton(
              tooltip: '减少无人机',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: _saving
                  ? null
                  : () => _changed(() {
                        if (drone.quantity <= 1) {
                          _fit!.drones.remove(drone);
                        } else {
                          drone.quantity--;
                        }
                      }),
              icon: const Icon(Icons.remove, size: 16)),
          SizedBox(
              width: 26,
              child: Text('${drone.quantity}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12))),
          IconButton(
              tooltip: '增加无人机',
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: _saving || drone.quantity >= 1000
                  ? null
                  : () => _changed(() => drone.quantity++),
              icon: const Icon(Icons.add, size: 16)),
        ]),
      ));

  Future<void> _showStatistics() async {
    if (_fit == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
          heightFactor: .9,
          child: StatefulBuilder(builder: (context, refresh) {
            _refreshStatsSheet = () {
              if (context.mounted) refresh(() {});
            };
            return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _statisticsContent());
          })),
    );
    _refreshStatsSheet = null;
  }

  Widget _statisticsContent() {
    final calculation = _calculation;
    final issues = <String>{
      ...fittingCompatibilityIssues(widget.catalogue, _fit!),
      ...?calculation?.diagnostics
    }.toList();
    final ship = widget.catalogue.byId[_fit!.shipTypeId];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.catalogue.displayName(_fit!.shipTypeId)} · 属性',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      if (ship != null)
        Text(ship.name,
            style: const TextStyle(fontSize: 11, color: StationColors.muted)),
      Row(children: [
        const Expanded(child: Text('技能假设', style: TextStyle(fontSize: 12))),
        DropdownButton<String>(
          value: _fit!.skillMode,
          underline: const SizedBox.shrink(),
          style: const TextStyle(fontSize: 12, fontFamily: 'Roboto'),
          items: const [
            DropdownMenuItem(value: 'all5', child: Text('全技能 V')),
            DropdownMenuItem(value: 'custom', child: Text('无技能'))
          ],
          onChanged: _saving
              ? null
              : (value) => _changed(() => _fit!.skillMode = value!),
        ),
      ]),
      if (_calculating)
        const LinearProgressIndicator(minHeight: 2)
      else if (calculation == null || !calculation.available) ...[
        const Text('计算暂不可用',
            style: TextStyle(fontSize: 14, color: StationColors.amber)),
        const SizedBox(height: 8),
        Text(_calculationErrorDescription(calculation),
            style: const TextStyle(fontSize: 12, color: StationColors.muted)),
        if (calculation?.error != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('查看原因', style: TextStyle(fontSize: 12)),
            children: [
              SelectableText(calculation!.error!,
                  style:
                      const TextStyle(fontSize: 11, color: StationColors.muted))
            ],
          ),
      ] else ...[
        for (final field in const [
          StatField('cpu_used', 'CPU 使用量', 'tf'),
          StatField('cpu_output', 'CPU 总量', 'tf'),
          StatField('powergrid_used', '能量栅格使用量', 'MW'),
          StatField('powergrid_output', '能量栅格总量', 'MW'),
          StatField('dps', '理论伤害', 'DPS'),
          StatField('dps_with_reload', '含装填的平均伤害', 'DPS'),
          StatField('alpha', '齐射伤害', 'HP'),
          StatField('ehp', '有效生命值', 'EHP'),
          StatField('speed', '最大速度', 'm/s'),
        ])
          if (calculation.stats.containsKey(field.key))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(
                    child: Text(field.label,
                        style: const TextStyle(
                            fontSize: 12, color: StationColors.muted))),
                Text(field.format(calculation.stats[field.key]!),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
        CalculationDetails(calculation: calculation),
        const Text('基础指标已对照，特殊效果仍待验证',
            style: TextStyle(fontSize: 10, color: StationColors.muted)),
      ],
      if (issues.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('装配提示（${issues.length}）',
            style: const TextStyle(fontSize: 13, color: StationColors.amber)),
        for (final issue in issues)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(issue, style: const TextStyle(fontSize: 11))),
      ],
    ]);
  }

  String _calculationErrorDescription(Calculation? calculation) =>
      switch (calculation?.code) {
        'DEVELOPMENT_ENGINE_PACK_MISSING' => calculation!.error!,
        'INVALID_FIT' => '请调整模块、弹药或无人机后重新计算。装配仍可保存在本机。',
        'UNKNOWN_TYPE' => '装配包含当前本地数据未收录的物品，请更换后重试。',
        'DATA_MISSING' ||
        'DATA_INVALID' ||
        'DATA_VERSION_MISMATCH' =>
          '本地计算数据出现异常。重新打开应用会检查并修复，已保存的装配不受影响。',
        'NATIVE_LIBRARY_UNAVAILABLE' => '此设备暂时无法启动本地计算引擎。装配编辑、保存和 EFT 导出仍可使用。',
        'ENGINE_UNAVAILABLE' => '此开发构建未启用本地计算。装配编辑、保存和 EFT 导出仍可使用。',
        _ => '本次装配计算未完成，请查看原因或调整装配。',
      };
}
