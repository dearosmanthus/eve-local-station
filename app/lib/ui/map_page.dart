import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/universe.dart';
import 'theme.dart';
import 'star_map_canvas.dart';
import 'system_picker.dart';

Color securityColor(SolarSystem system) => system.isHighSecurity
    ? StationColors.cyan
    : system.isLowSecurity
        ? StationColors.amber
        : StationColors.red;

class StarMapPage extends StatefulWidget {
  const StarMapPage({required this.universe, super.key});
  final Universe universe;
  @override
  State<StarMapPage> createState() => _StarMapPageState();
}

class _StarMapPageState extends State<StarMapPage>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  SolarSystem? _origin;
  SolarSystem? _destination;
  SolarSystem? _selected;
  int? _regionId;
  RoutePreference _preference = RoutePreference.shortest;
  final Set<int> _avoided = {};
  final List<int> _recentSystems = [];
  RouteResult? _route;
  late StarMapScene _scene;
  List<SolarSystem> get _visible => _scene.systems;
  Map<int, Offset> get _points => _scene.points;
  late final AnimationController _camera;
  Matrix4Tween? _cameraTween;
  bool _showLabels = true;
  bool _showConnections = true;
  Size _viewport = const Size(500, 500);
  bool _initialFit = false;

  @override
  void initState() {
    super.initState();
    _camera = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() {
        final tween = _cameraTween;
        if (tween != null) {
          _transform.value =
              tween.lerp(Curves.easeOutCubic.transform(_camera.value));
        }
      });
    for (final system in widget.universe.systems) {
      if (system.name == 'Jita') {
        _origin = system;
        break;
      }
    }
    _project();
  }

  @override
  void dispose() {
    _camera.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _project() {
    _scene = StarMapScene(widget.universe, regionId: _regionId);
  }

  void _moveCamera(Matrix4 target, {bool animate = true}) {
    _camera.stop();
    if (!animate || (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _transform.value = target;
      return;
    }
    _cameraTween = Matrix4Tween(begin: _transform.value.clone(), end: target);
    _camera.forward(from: 0);
  }

  void _fitPositions(Iterable<Offset> positions, {bool animate = true}) {
    final points = positions.toList();
    if (points.isEmpty) return;
    var bounds = Rect.fromPoints(points.first, points.first);
    for (final point in points.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    final top = 68.0;
    final bottom = _selected == null ? 30.0 : 142.0;
    final height = math.max(40.0, _viewport.height - top - bottom);
    final width = math.max(40.0, _viewport.width - 48);
    final scale = math
        .min(width / math.max(20, bounds.width),
            height / math.max(20, bounds.height))
        .clamp(0.08, points.length == 1 ? 2.0 : 10.0)
        .toDouble();
    _moveCamera(
        Matrix4.diagonal3Values(scale, scale, 1)
          ..setTranslationRaw(_viewport.width / 2 - bounds.center.dx * scale,
              top + height / 2 - bounds.center.dy * scale, 0),
        animate: animate);
  }

  void _fitView({bool animate = true}) =>
      _fitPositions(_points.values, animate: animate);

  void _showRegion(int? region) {
    setState(() {
      _regionId = region;
      _project();
      if (_selected != null && !_points.containsKey(_selected!.id)) {
        _selected = null;
      }
    });
    _fitView();
  }

  void _focus(SolarSystem system) {
    _camera.stop();
    final changedScene = !_points.containsKey(system.id);
    setState(() {
      if (changedScene) {
        _regionId = system.regionId;
        _project();
      }
      _selected = system;
    });
    final point = _points[system.id];
    if (point == null) return;
    final scale = math
        .max(changedScene ? 1.0 : _transform.value.storage[0].abs(),
            _regionId == null ? 1.8 : 1.0)
        .clamp(0.08, 10.0)
        .toDouble();
    _moveCamera(Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(_viewport.width / 2 - point.dx * scale,
          math.max(88.0, (_viewport.height - 142) / 2) - point.dy * scale, 0));
  }

  void _zoom(double factor) {
    _camera.stop();
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final anchor = _transform.toScene(center);
    final scale = (_transform.value.storage[0].abs() * factor)
        .clamp(0.08, 10.0)
        .toDouble();
    _moveCamera(Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
          center.dx - anchor.dx * scale, center.dy - anchor.dy * scale, 0));
  }

  void _fitRoute() {
    final route = _route;
    if (route == null) return;
    if (route.systemIds.length == 1) {
      _focus(widget.universe.byId[route.systemIds.single]!);
      return;
    }
    setState(() {
      _selected = null;
      if (_regionId != null) {
        _regionId = null;
        _project();
      }
    });
    _fitPositions(route.systemIds.map((id) => _points[id]).whereType<Offset>());
  }

  void _swapEndpoints() {
    if (_origin == null || _destination == null) return;
    setState(() {
      final start = _origin;
      _origin = _destination;
      _destination = start;
      _plan();
    });
  }

  void _copyRoute(RouteResult route) {
    final text =
        route.systemIds.map((id) => widget.universe.byId[id]!.name).join(' → ');
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) notice(context, '已复制英文星系路线，共 ${route.jumps} 跳');
    });
  }

  void _plan() {
    _route = _origin == null || _destination == null
        ? null
        : planRoute(
            widget.universe,
            _origin!.id,
            _destination!.id,
            preference: _preference,
            avoided: _avoided,
          );
  }

  Future<SolarSystem?> _pick(String title) async {
    final selected = await showModalBottomSheet<SolarSystem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: StationColors.panel,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: SystemPicker(
            title: title,
            universe: widget.universe,
            recentIds: List.of(_recentSystems)),
      ),
    );
    if (selected != null && mounted) {
      _recentSystems.remove(selected.id);
      _recentSystems.insert(0, selected.id);
      if (_recentSystems.length > 6) _recentSystems.removeLast();
    }
    return selected;
  }

  Future<void> _chooseEndpoint(bool isOrigin) async {
    final system = await _pick(isOrigin ? '选择起点' : '选择终点');
    if (system == null || !mounted) return;
    setState(() {
      if (isOrigin) {
        _origin = system;
      } else {
        _destination = system;
      }
      _plan();
    });
  }

  Future<void> _search() async {
    final system = await _pick('搜索星系');
    if (system != null && mounted) _focus(system);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 940 ||
              (constraints.maxWidth >= 600 && constraints.maxHeight < 500);
          final controls = _controls(compact: !wide);
          return Padding(
            padding: EdgeInsets.fromLTRB(wide ? 16 : 8, 0, wide ? 16 : 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '星图与路线',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '交换起终点',
                      onPressed: _origin != null && _destination != null
                          ? _swapEndpoints
                          : null,
                      icon: const Icon(Icons.swap_horiz, size: 20),
                    ),
                    IconButton(
                      tooltip: '搜索星系',
                      onPressed: _search,
                      icon: const Icon(Icons.search, color: StationColors.cyan),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '星图设置',
                      icon: const Icon(Icons.tune, size: 20),
                      onSelected: (value) {
                        switch (value) {
                          case 'labels':
                            setState(() => _showLabels = !_showLabels);
                          case 'connections':
                            setState(
                                () => _showConnections = !_showConnections);
                          case 'clear':
                            setState(() {
                              _destination = null;
                              _route = null;
                            });
                          case 'help':
                            showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                      title: const Text('使用星图'),
                                      content: const Text(
                                          '拖动平移，双指缩放，也可用右侧加减按钮。星系点保持小尺寸，点击周围也能选中。\n\n点星系后可设起终点或查看相邻星系；路线栏的方框按钮可查看完整路线。名称和星门连线可按需关闭。\n\n星图只有静态资料，不反映实时战况、临时虫洞或玩家跳桥。'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('知道了'))
                                      ],
                                    ));
                        }
                      },
                      itemBuilder: (context) => [
                        CheckedPopupMenuItem(
                            value: 'labels',
                            checked: _showLabels,
                            child: const Text('星系名称')),
                        CheckedPopupMenuItem(
                            value: 'connections',
                            checked: _showConnections,
                            child: const Text('星门连线')),
                        if (_destination != null)
                          const PopupMenuItem(
                              value: 'clear', child: Text('清除路线')),
                        const PopupMenuItem(value: 'help', child: Text('操作说明')),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 300,
                              child: SingleChildScrollView(child: controls),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _map()),
                          ],
                        )
                      : Column(
                          children: [
                            controls,
                            const SizedBox(height: 6),
                            Expanded(child: _map()),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      );

  Widget _controls({required bool compact}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(compact ? 8 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) const SectionLabel('规划一次跃迁'),
                  if (compact)
                    Row(children: [
                      Expanded(
                          child: _endpoint('起点', _origin, true, compact: true)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: _endpoint('终点', _destination, false,
                              compact: true)),
                    ])
                  else ...[
                    _endpoint('起点', _origin, true),
                    const SizedBox(height: 6),
                    _endpoint('终点', _destination, false),
                  ],
                  const SizedBox(height: 4),
                  SegmentedButton<RoutePreference>(
                    style: SegmentedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'Roboto',
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: RoutePreference.shortest,
                        label: Text('最少跳数'),
                        icon: Icon(Icons.route, size: 16),
                      ),
                      ButtonSegment(
                        value: RoutePreference.preferHighSec,
                        label: Text('高安优先'),
                        icon: Icon(Icons.shield_outlined, size: 16),
                      ),
                    ],
                    selected: {_preference},
                    onSelectionChanged: (selection) => setState(() {
                      _preference = selection.first;
                      _plan();
                    }),
                  ),
                  if (_destination != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _routeSummary(),
                    ),
                  if (!compact) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '高安优先：高安每跳权重 1，低安 26，零安 101。仍可能经过低安或零安；请检查路线。',
                      style:
                          TextStyle(color: StationColors.muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_avoided.isNotEmpty && compact)
            TextButton.icon(
              onPressed: _manageAvoided,
              icon: const Icon(Icons.block, size: 16),
              label: Text('绕开 ${_avoided.length} 个星系 · 管理'),
            ),
          if (_avoided.isNotEmpty && !compact)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final id in _avoided)
                    InputChip(
                      label: Text(
                        '避开 ${widget.universe.byId[id]?.displayName ?? id}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => setState(() {
                        _avoided.remove(id);
                        _plan();
                      }),
                    ),
                ],
              ),
            ),
          if (!compact) ...[
            const SizedBox(height: 22),
            const SectionLabel('离线导航'),
            const Text(
              '拖动平移，双指缩放。点击星系可设置起点、终点或绕行。\n\n星门网络视图隐藏没有静态星门的星系；可通过搜索或星域筛选查看。',
              style: TextStyle(color: StationColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              '本地数据不包含实时战况、临时虫洞或玩家跳桥。',
              style: TextStyle(color: StationColors.amber, fontSize: 11),
            ),
          ],
        ],
      );

  void _manageAvoided() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          children: [
            Row(children: [
              const Expanded(child: SectionLabel('绕开的星系')),
              TextButton(
                  onPressed: _avoided.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _avoided.clear();
                            _plan();
                          });
                          updateSheet(() {});
                        },
                  child: const Text('全部取消')),
            ]),
            if (_avoided.isEmpty) const ListTile(title: Text('没有绕行条件')),
            for (final id in _avoided.toList())
              ListTile(
                dense: true,
                title: Text(widget.universe.byId[id]?.displayName ?? '$id'),
                trailing: IconButton(
                  tooltip: '取消绕行',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _avoided.remove(id);
                      _plan();
                    });
                    updateSheet(() {});
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _endpoint(String label, SolarSystem? system, bool isOrigin,
          {bool compact = false}) =>
      InkWell(
        onTap: () => _chooseEndpoint(isOrigin),
        borderRadius: BorderRadius.circular(5),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: StationColors.background,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: StationColors.border),
          ),
          child: Row(
            children: [
              if (!compact)
                Icon(
                  isOrigin ? Icons.trip_origin : Icons.flag_outlined,
                  size: 16,
                  color: isOrigin ? StationColors.cyan : StationColors.amber,
                ),
              if (!compact) const SizedBox(width: 6),
              Text(
                label,
                style:
                    const TextStyle(color: StationColors.muted, fontSize: 10),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  system?.displayName ?? '选择星系',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (system != null && !compact)
                Text(
                  system.displayedSecurity.toStringAsFixed(1),
                  style: TextStyle(color: securityColor(system), fontSize: 11),
                ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more,
                  size: 16, color: StationColors.muted),
            ],
          ),
        ),
      );

  Widget _routeSummary() {
    if (_origin == null) {
      return const Text(
        '请选择起点',
        style: TextStyle(fontSize: 11, color: StationColors.muted),
      );
    }
    if (_route == null) {
      return Text(
        _avoided.contains(_origin!.id) || _avoided.contains(_destination?.id)
            ? '起点或终点已设为绕行，请先取消对应绕行。'
            : '这两个星系没有可用的静态星门路线。',
        style: const TextStyle(fontSize: 11, color: StationColors.amber),
      );
    }
    final low = _route!.systemIds
        .where((id) => !widget.universe.byId[id]!.isHighSecurity)
        .length;
    return Row(
      children: [
        Text(
          '${_route!.jumps} 跳',
          style: const TextStyle(
            color: StationColors.cyan,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            low == 0 ? '全程高安' : '$low 个低安 / 零安星系',
            style: TextStyle(
              color: low == 0 ? StationColors.muted : StationColors.amber,
              fontSize: 10,
            ),
          ),
        ),
        IconButton(
          tooltip: '查看整条路线',
          onPressed: _fitRoute,
          icon: const Icon(Icons.fit_screen_outlined, size: 20),
        ),
        TextButton(
          onPressed: _routeDetails,
          child: const Text('详情', style: TextStyle(fontSize: 11)),
        ),
      ],
    );
  }

  void _routeDetails() {
    final route = _route;
    if (route == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text('${route.jumps} 跳 · 静态星门路线',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600))),
                IconButton(
                    tooltip: '复制英文路线',
                    onPressed: () => _copyRoute(route),
                    icon: const Icon(Icons.copy, size: 19)),
              ]),
              const Text(
                '仅供离线规划。安全等级并不代表当前航行安全。',
                style: TextStyle(color: StationColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: route.systemIds.length,
                  separatorBuilder: (_, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final system =
                        widget.universe.byId[route.systemIds[index]]!;
                    return ListTile(
                      leading: Text(
                        index.toString().padLeft(2, '0'),
                        style: const TextStyle(color: StationColors.muted),
                      ),
                      title: Text(system.displayName),
                      subtitle: Text(system.regionDisplayName),
                      trailing: Text(
                        system.displayedSecurity.toStringAsFixed(1),
                        style: TextStyle(color: securityColor(system)),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _focus(system);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _map() => Card(
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, constraints) {
          final next = Size(constraints.maxWidth, constraints.maxHeight);
          if (!_initialFit || next != _viewport) {
            final oldSize = _viewport;
            final first = !_initialFit;
            _viewport = next;
            _initialFit = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _viewport != next) return;
              if (first) {
                _fitView(animate: false);
              } else {
                _camera.stop();
                final matrix = _transform.value.clone();
                matrix.setEntry(0, 3,
                    matrix.entry(0, 3) + (next.width - oldSize.width) / 2);
                matrix.setEntry(1, 3,
                    matrix.entry(1, 3) + (next.height - oldSize.height) / 2);
                _transform.value = matrix;
              }
            });
          }
          final regions = widget.universe.regionDisplayNames.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          return Stack(children: [
            Positioned.fill(
                child: StarMapCanvas(
              key: const ValueKey('star-map-canvas'),
              scene: _scene,
              controller: _transform,
              selectedId: _selected?.id,
              originId: _origin?.id,
              destinationId: _destination?.id,
              routeIds: _route?.systemIds ?? const [],
              avoided: Set.unmodifiable(_avoided),
              showLabels: _showLabels,
              showConnections: _showConnections,
              onInteractionStart: (_) => _camera.stop(),
              onSelect: (system) => setState(() => _selected = system),
            )),
            Positioned(
                left: 8,
                top: 8,
                right: 58,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: StationColors.panel.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: StationColors.border)),
                  child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                    key: const ValueKey('map-region-picker'),
                    value: _regionId,
                    isExpanded: true,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Roboto'),
                    hint: const Text('星门网络 · 全部星域',
                        style: TextStyle(fontSize: 11)),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('星门网络 · 全部星域')),
                      for (final region in regions)
                        DropdownMenuItem<int?>(
                            value: region.key,
                            child: Text(region.value,
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _showRegion,
                  )),
                )),
            Positioned(
                right: 4,
                top: 8,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  IconButton.filledTonal(
                      tooltip: '重置星图视角',
                      onPressed: () => _fitView(),
                      icon: const Icon(Icons.center_focus_strong, size: 18)),
                  if (_viewport.height >= 280) ...[
                    const SizedBox(height: 4),
                    IconButton.filledTonal(
                        tooltip: '放大星图',
                        onPressed: () => _zoom(1.6),
                        icon: const Icon(Icons.add, size: 20)),
                    const SizedBox(height: 4),
                    IconButton.filledTonal(
                        tooltip: '缩小星图',
                        onPressed: () => _zoom(1 / 1.6),
                        icon: const Icon(Icons.remove, size: 20)),
                  ],
                ])),
            if (_selected == null)
              Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Row(children: [
                    const _Legend(StationColors.cyan, '高安'),
                    const SizedBox(width: 12),
                    const _Legend(StationColors.amber, '低安'),
                    const SizedBox(width: 12),
                    const _Legend(StationColors.red, '零安'),
                    const Spacer(),
                    Text('${_visible.length} 个星系',
                        style: const TextStyle(
                            fontSize: 9, color: StationColors.muted)),
                  ])),
            if (_selected != null)
              Positioned(left: 8, right: 8, bottom: 8, child: _systemCard()),
            if (_visible.isEmpty) const Center(child: Text('此星域暂无本地星系数据')),
          ]);
        }),
      );

  Widget _systemCard() {
    final system = _selected!;
    return Container(
      key: const ValueKey('map-system-card'),
      padding: const EdgeInsets.fromLTRB(10, 0, 4, 2),
      decoration: BoxDecoration(
          color: StationColors.panel.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: StationColors.border)),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(system.displayedSecurity.toStringAsFixed(1),
                  style: TextStyle(
                      color: securityColor(system),
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(system.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600))),
              IconButton(
                  tooltip: '关闭星系信息',
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.close, size: 18)),
            ]),
            Text(
                '${system.regionDisplayName} · ${widget.universe.neighbors[system.id]?.length ?? 0} 个相邻星系',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 10, color: StationColors.muted)),
            Row(children: [
              TextButton(
                  onPressed: () => setState(() {
                        _origin = system;
                        _plan();
                      }),
                  child: const Text('设为起点', style: TextStyle(fontSize: 11))),
              TextButton(
                  onPressed: () => setState(() {
                        _destination = system;
                        _plan();
                      }),
                  child: const Text('设为终点', style: TextStyle(fontSize: 11))),
              const Spacer(),
              TextButton(
                  onPressed: () => _systemDetails(system),
                  child: const Text('星系详情 ›', style: TextStyle(fontSize: 11))),
            ]),
          ]),
    );
  }

  void _systemDetails(SolarSystem system) {
    final neighbors = (widget.universe.neighbors[system.id] ?? const <int>[])
        .map((id) => widget.universe.byId[id]!)
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => FractionallySizedBox(
              heightFactor: 0.8,
              child: StatefulBuilder(
                  builder: (context, refresh) => ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(system.displayName,
                                    style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w600))),
                            IconButton(
                                tooltip: '关闭详情',
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: const Icon(Icons.close)),
                          ]),
                          if (system.name != system.displayName)
                            Text(system.name,
                                style: const TextStyle(
                                    fontSize: 12, color: StationColors.muted)),
                          const SizedBox(height: 12),
                          _detailLine(
                              '安全等级',
                              '${system.displayedSecurity.toStringAsFixed(1)} · ${system.isHighSecurity ? '高安' : system.isLowSecurity ? '低安' : '零安'}',
                              color: securityColor(system)),
                          _detailLine('所属星域', system.regionDisplayName),
                          if (system.constellationDisplayName.isNotEmpty)
                            _detailLine(
                                '所属星座', system.constellationDisplayName),
                          if (system.planetCount != null)
                            _detailLine('行星数量', '${system.planetCount}'),
                          if (system.starSpectralClass != null)
                            _detailLine('恒星光谱', system.starSpectralClass!),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: system.name));
                                  if (mounted) {
                                    notice(this.context, '已复制 ${system.name}');
                                  }
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('复制英文名',
                                    style: TextStyle(fontSize: 11))),
                            OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _showRegion(system.regionId);
                                },
                                icon: const Icon(Icons.public, size: 16),
                                label: const Text('查看星域',
                                    style: TextStyle(fontSize: 11))),
                            OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    if (!_avoided.remove(system.id)) {
                                      _avoided.add(system.id);
                                    }
                                    _plan();
                                  });
                                  refresh(() {});
                                },
                                icon: const Icon(Icons.block, size: 16),
                                label: Text(
                                    _avoided.contains(system.id)
                                        ? '取消绕行'
                                        : '避开此星系',
                                    style: const TextStyle(fontSize: 11))),
                          ]),
                          const SizedBox(height: 16),
                          SectionLabel('相邻星系（${neighbors.length}）'),
                          const Text('点击相邻星系可在图中定位。',
                              style: TextStyle(
                                  fontSize: 11, color: StationColors.muted)),
                          if (neighbors.isEmpty)
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('没有静态星门连接，无法通过静态星门规划路线。',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: StationColors.muted))),
                          for (final neighbor in neighbors)
                            ListTile(
                              key: ValueKey('map-neighbor-${neighbor.id}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Text(
                                  neighbor.displayedSecurity.toStringAsFixed(1),
                                  style: TextStyle(
                                      color: securityColor(neighbor))),
                              title: Text(neighbor.displayName,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: Text(neighbor.regionDisplayName,
                                  style: const TextStyle(fontSize: 10)),
                              trailing: const Icon(Icons.my_location, size: 18),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _focus(neighbor);
                              },
                            ),
                          const SizedBox(height: 12),
                          const Text('本地静态资料不包含实时战况、临时虫洞或玩家跳桥。',
                              style: TextStyle(
                                  fontSize: 10, color: StationColors.muted)),
                        ],
                      )),
            ));
  }

  Widget _detailLine(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 78,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: StationColors.muted))),
          Expanded(
              child: Text(value, style: TextStyle(fontSize: 12, color: color))),
        ]),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.text);
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: StationColors.muted, fontSize: 9),
          ),
        ],
      );
}
