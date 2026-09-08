import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/universe.dart';
import 'theme.dart';

/// Immutable world geometry. Construct only when universe/region changes.
class StarMapScene {
  StarMapScene(Universe universe,
      {int? regionId, this.canvasSize = standardSize}) {
    final selected = universe.systems
        .where((system) =>
            system.x.isFinite &&
            system.z.isFinite &&
            (regionId == null
                ? (universe.neighbors[system.id]?.isNotEmpty ?? false)
                : system.regionId == regionId))
        .toList();
    systems = List.unmodifiable(selected);
    byId = Map.unmodifiable({for (final system in systems) system.id: system});
    final projected = <int, Offset>{};
    if (systems.isNotEmpty) {
      var minX = systems.first.x;
      var maxX = minX;
      var minZ = systems.first.z;
      var maxZ = minZ;
      for (final system in systems) {
        minX = math.min(minX, system.x);
        maxX = math.max(maxX, system.x);
        minZ = math.min(minZ, system.z);
        maxZ = math.max(maxZ, system.z);
      }
      final scale = math.min(
          math.max(1, canvasSize.width - 90) / math.max(1, maxX - minX),
          math.max(1, canvasSize.height - 90) / math.max(1, maxZ - minZ));
      final centerX = minX + (maxX - minX) / 2;
      final centerZ = minZ + (maxZ - minZ) / 2;
      for (final system in systems) {
        projected[system.id] = Offset(
            canvasSize.width / 2 + (system.x - centerX) * scale,
            canvasSize.height / 2 - (system.z - centerZ) * scale);
      }
    }
    points = Map.unmodifiable(projected);
    edges = List.unmodifiable([
      for (final gate in universe.gates)
        if (points.containsKey(gate.from) && points.containsKey(gate.to))
          StarMapEdge(gate.from, gate.to, points[gate.from]!, points[gate.to]!),
    ]);
    _allEdges = Path();
    for (final edge in edges) {
      _allEdges.addPath(edge._path, Offset.zero);
    }
    final clouds = [<double>[], <double>[], <double>[]];
    for (final system in systems) {
      final color = system.isHighSecurity
          ? 0
          : system.isLowSecurity
              ? 1
              : 2;
      final point = points[system.id]!;
      clouds[color].addAll([point.dx, point.dy]);
    }
    _nodeClouds = [for (final cloud in clouds) Float32List.fromList(cloud)];
    _nodes = _SpatialGrid(canvasSize);
    for (final entry in points.entries) {
      _nodes.insert(
          entry.key, Rect.fromCenter(center: entry.value, width: 0, height: 0));
    }
    _edges = _SpatialGrid(canvasSize);
    for (var index = 0; index < edges.length; index++) {
      _edges.insert(index, edges[index].bounds);
    }
  }

  static const standardSize = Size(1400, 1050);
  final Size canvasSize;
  late final List<SolarSystem> systems;
  late final Map<int, SolarSystem> byId;
  late final Map<int, Offset> points;
  late final List<StarMapEdge> edges;
  late final Path _allEdges;
  late final List<Float32List> _nodeClouds;
  late final _SpatialGrid _nodes;
  late final _SpatialGrid _edges;

  List<SolarSystem> systemsIn(Rect worldRect) => [
        for (final id in _nodes.query(worldRect))
          if (worldRect.contains(points[id]!)) byId[id]!,
      ];

  List<StarMapEdge> edgesIn(Rect worldRect) => [
        for (final index in _edges.query(worldRect))
          if (edges[index].intersects(worldRect)) edges[index],
      ];

  SolarSystem? hitTestScreen(Offset screenPoint, Matrix4 transform,
      {double radius = 20}) {
    if (!radius.isFinite || radius <= 0) return null;
    final inverse = _inverse(transform);
    if (inverse == null) return null;
    final bounds = _transformRect(inverse,
        Rect.fromCircle(center: screenPoint, radius: radius).inflate(0.00001));
    SolarSystem? closest;
    var distanceSquared = radius * radius;
    for (final candidate in systemsIn(bounds)) {
      final screen =
          MatrixUtils.transformPoint(transform, points[candidate.id]!);
      final distance = (screen - screenPoint).distanceSquared;
      if (distance < distanceSquared ||
          (distance == distanceSquared &&
              (closest == null || candidate.id < closest.id))) {
        distanceSquared = distance;
        closest = candidate;
      }
    }
    return closest;
  }
}

class StarMapEdge {
  StarMapEdge(this.from, this.to, this.start, this.end)
      : bounds = Rect.fromPoints(start, end),
        _path = Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
  final int from;
  final int to;
  final Offset start;
  final Offset end;
  final Rect bounds;
  final Path _path;

  /// Liang-Barsky clipping also retains lines crossing the viewport when both
  /// endpoints lie outside it. Touching a viewport boundary is visible.
  bool intersects(Rect rect) {
    var lower = 0.0;
    var upper = 1.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final p = [-dx, dx, -dy, dy];
    final q = [
      start.dx - rect.left,
      rect.right - start.dx,
      start.dy - rect.top,
      rect.bottom - start.dy
    ];
    for (var index = 0; index < 4; index++) {
      if (p[index] == 0) {
        if (q[index] < 0) return false;
      } else {
        final ratio = q[index] / p[index];
        if (p[index] < 0) {
          lower = math.max(lower, ratio);
        } else {
          upper = math.min(upper, ratio);
        }
        if (lower > upper) return false;
      }
    }
    return true;
  }
}

class _SpatialGrid {
  _SpatialGrid(Size size)
      : columns = math.max(1, (size.width / cellSize).ceil()),
        rows = math.max(1, (size.height / cellSize).ceil());
  static const cellSize = 48.0;
  final int columns;
  final int rows;
  final Map<int, List<int>> _buckets = {};
  int _x(double value) => (value / cellSize).floor().clamp(0, columns - 1);
  int _y(double value) => (value / cellSize).floor().clamp(0, rows - 1);

  void insert(int id, Rect bounds) {
    for (var y = _y(bounds.top); y <= _y(bounds.bottom); y++) {
      for (var x = _x(bounds.left); x <= _x(bounds.right); x++) {
        _buckets.putIfAbsent(y * columns + x, () => []).add(id);
      }
    }
  }

  Set<int> query(Rect bounds) {
    if (!bounds.isFinite ||
        bounds.right < 0 ||
        bounds.bottom < 0 ||
        bounds.left > columns * cellSize ||
        bounds.top > rows * cellSize) {
      return const {};
    }
    return {
      for (var y = _y(bounds.top); y <= _y(bounds.bottom); y++)
        for (var x = _x(bounds.left); x <= _x(bounds.right); x++)
          ...?_buckets[y * columns + x],
    };
  }
}

Matrix4? _inverse(Matrix4 value) {
  if (value.storage.any((number) => !number.isFinite)) return null;
  final result = Matrix4.copy(value);
  if (result.invert() == 0) return null;
  return result;
}

Rect _transformRect(Matrix4 matrix, Rect rect) {
  final corners = [
    rect.topLeft,
    rect.topRight,
    rect.bottomLeft,
    rect.bottomRight
  ].map((point) => MatrixUtils.transformPoint(matrix, point)).toList();
  return Rect.fromLTRB(
      corners.map((p) => p.dx).reduce(math.min),
      corners.map((p) => p.dy).reduce(math.min),
      corners.map((p) => p.dx).reduce(math.max),
      corners.map((p) => p.dy).reduce(math.max));
}

/// Owns native paragraph resources; bounded LRU survives gesture repaints.
class StarMapLabelCache {
  StarMapLabelCache({this.maxEntries = 256}) : assert(maxEntries > 0);
  final int maxEntries;
  final _entries = <(String, bool, double), TextPainter>{};
  bool isDisposed = false;
  int disposedLayouts = 0;
  int get length => _entries.length;

  TextPainter layout(String text,
      {bool emphasized = false, double textScale = 1}) {
    if (isDisposed) throw StateError('Star map label cache is disposed');
    final key = (text, emphasized, textScale);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: emphasized ? 11 : 10,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
                color: emphasized
                    ? const Color(0xFFE7ECEF)
                    : StationColors.muted)),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(textScale),
        maxLines: 1,
        ellipsis: '…')
      ..layout(maxWidth: 170);
    _entries[key] = painter;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first)!.dispose();
      disposedLayouts++;
    }
    return painter;
  }

  void clear() {
    for (final painter in _entries.values) {
      painter.dispose();
      disposedLayouts++;
    }
    _entries.clear();
  }

  void dispose() {
    if (isDisposed) return;
    clear();
    isDisposed = true;
  }
}

/// Paints in viewport coordinates. Only cached edge paths are transformed;
/// their stroke width is compensated for zoom. Nodes and text never scale.
class StarMapRenderer extends CustomPainter {
  StarMapRenderer({
    required this.scene,
    required this.controller,
    required this.labelCache,
    this.selectedId,
    this.originId,
    this.destinationId,
    List<int> routeIds = const [],
    Set<int> avoided = const {},
    this.showLabels = true,
    this.showConnections = true,
    this.textScale = 1,
  })  : routeIds = List.unmodifiable(routeIds),
        avoided = Set.unmodifiable(avoided),
        super(repaint: controller) {
    _routeSet = this.routeIds.toSet();
    _routePath = Path();
    for (var index = 1; index < this.routeIds.length; index++) {
      final start = scene.points[this.routeIds[index - 1]];
      final end = scene.points[this.routeIds[index]];
      if (start != null && end != null) {
        _routePath.moveTo(start.dx, start.dy);
        _routePath.lineTo(end.dx, end.dy);
      }
    }
  }

  final StarMapScene scene;
  final TransformationController controller;
  final StarMapLabelCache labelCache;
  final int? selectedId;
  final int? originId;
  final int? destinationId;
  final List<int> routeIds;
  final Set<int> avoided;
  final bool showLabels;
  final bool showConnections;
  final double textScale;
  late final Set<int> _routeSet;
  late final Path _routePath;
  static const ordinaryRadius = 1.0;
  static const selectedRadius = 2.8;
  static const ringRadius = 5.5;
  static const edgeWidth = 0.65;
  static const routeWidth = 1.6;

  bool _focused(int id) =>
      id == selectedId || id == originId || id == destinationId;
  Color _color(SolarSystem system) => avoided.contains(system.id)
      ? StationColors.muted
      : system.isHighSecurity
          ? StationColors.cyan
          : system.isLowSecurity
              ? StationColors.amber
              : StationColors.red;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = Offset.zero & size;
    canvas.save();
    canvas.clipRect(viewport);
    canvas.drawColor(const Color(0xFF0B1017), BlendMode.src);
    final matrix = controller.value;
    final inverse = _inverse(matrix);
    // The inert Z scale remains 1 during a 2D zoom-out; including it would
    // misclassify overview zoom and shrink the supposedly fixed line widths.
    final values = matrix.storage;
    final scale = math.sqrt(math.max(
        values[0] * values[0] + values[1] * values[1],
        values[4] * values[4] + values[5] * values[5]));
    if (inverse == null || !scale.isFinite || scale <= 0) {
      canvas.restore();
      return;
    }
    final worldRect = _transformRect(inverse, viewport.inflate(8));
    final visible = scene.systemsIn(worldRect);
    final batchOverview = scale < 0.7 && visible.length > 500;
    canvas.save();
    canvas.transform(matrix.storage);
    if (showConnections) {
      final paint = Paint()
        ..color = const Color(0xFF344352)
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth / scale;
      if (batchOverview) {
        canvas.drawPath(scene._allEdges, paint);
      } else {
        for (final edge in scene.edgesIn(worldRect)) {
          canvas.drawPath(edge._path, paint);
        }
      }
    }
    if (routeIds.isNotEmpty) {
      canvas.drawPath(
          _routePath,
          Paint()
            ..color = StationColors.cyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = routeWidth / scale);
    }
    if (batchOverview) {
      const colors = [
        StationColors.cyan,
        StationColors.amber,
        StationColors.red
      ];
      for (var index = 0; index < colors.length; index++) {
        canvas.drawRawPoints(
            PointMode.points,
            scene._nodeClouds[index],
            Paint()
              ..color = colors[index]
              ..strokeCap = StrokeCap.round
              ..strokeWidth = ordinaryRadius * 2 / scale);
      }
    }
    canvas.restore();

    final overlay = batchOverview
        ? visible
            .where((system) =>
                _focused(system.id) ||
                _routeSet.contains(system.id) ||
                avoided.contains(system.id))
            .toList()
        : visible;
    final positions = <int, Offset>{
      for (final system in overlay)
        system.id: MatrixUtils.transformPoint(matrix, scene.points[system.id]!),
    };
    // Emphasized systems are painted last, so crowded ordinary nodes cannot
    // cover the smaller selection ring or endpoint markers.
    for (final focused in [false, true]) {
      for (final system in overlay) {
        if (_focused(system.id) != focused) continue;
        final point = positions[system.id]!;
        final color = _color(system);
        if (focused) {
          canvas.drawCircle(
              point,
              ringRadius,
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1);
        }
        canvas.drawCircle(
            point,
            focused
                ? selectedRadius
                : _routeSet.contains(system.id)
                    ? 1.8
                    : ordinaryRadius,
            Paint()..color = color);
        if (avoided.contains(system.id)) {
          canvas.drawLine(
              point - const Offset(3, 3),
              point + const Offset(3, 3),
              Paint()
                ..color = StationColors.red
                ..strokeWidth = 1);
        }
      }
    }
    final candidates = overlay
        .where((system) =>
            _focused(system.id) ||
            (showLabels && (scale >= 0.7 || visible.length <= 100)))
        .toList();
    int priority(int id) => id == selectedId
        ? 0
        : id == originId || id == destinationId
            ? 1
            : _routeSet.contains(id)
                ? 2
                : 3;
    candidates.sort((a, b) {
      final rank = priority(a.id).compareTo(priority(b.id));
      if (rank != 0) return rank;
      final distance = (positions[a.id]! - viewport.center)
          .distanceSquared
          .compareTo((positions[b.id]! - viewport.center).distanceSquared);
      return distance != 0 ? distance : a.id.compareTo(b.id);
    });
    final occupied = <Rect>[];
    final budget = (size.width * size.height / 3500).floor().clamp(8, 80);
    for (final system in candidates.take(160)) {
      if (occupied.length >= budget) break;
      final point = positions[system.id]!;
      final text = labelCache.layout(system.displayName,
          emphasized: _focused(system.id), textScale: textScale);
      final width = text.width + 4;
      final height = text.height + 2;
      final places = [
        Offset(point.dx + 8, point.dy - height / 2),
        Offset(point.dx - width - 8, point.dy - height / 2),
        Offset(point.dx - width / 2, point.dy + 8),
        Offset(point.dx - width / 2, point.dy - height - 8),
      ];
      for (final position in places) {
        final rect = position & Size(width, height);
        if (!viewport.contains(rect.topLeft) ||
            !viewport.contains(rect.bottomRight) ||
            occupied.any((placed) => placed.overlaps(rect.inflate(3)))) {
          continue;
        }
        occupied.add(rect);
        canvas.drawRect(rect, Paint()..color = const Color(0xED0B1017));
        text.paint(canvas, position + const Offset(2, 1));
        break;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StarMapRenderer oldDelegate) =>
      scene != oldDelegate.scene ||
      controller != oldDelegate.controller ||
      labelCache != oldDelegate.labelCache ||
      selectedId != oldDelegate.selectedId ||
      originId != oldDelegate.originId ||
      destinationId != oldDelegate.destinationId ||
      showLabels != oldDelegate.showLabels ||
      showConnections != oldDelegate.showConnections ||
      textScale != oldDelegate.textScale ||
      !listEquals(routeIds, oldDelegate.routeIds) ||
      !setEquals(avoided, oldDelegate.avoided);
}

class StarMapCanvas extends StatefulWidget {
  const StarMapCanvas(
      {required this.scene,
      required this.controller,
      required this.onSelect,
      this.selectedId,
      this.originId,
      this.destinationId,
      this.routeIds = const [],
      this.avoided = const {},
      this.showLabels = true,
      this.showConnections = true,
      this.onInteractionStart,
      super.key});
  final StarMapScene scene;
  final TransformationController controller;
  final ValueChanged<SolarSystem> onSelect;
  final int? selectedId;
  final int? originId;
  final int? destinationId;
  final List<int> routeIds;
  final Set<int> avoided;
  final bool showLabels;
  final bool showConnections;
  final void Function(ScaleStartDetails)? onInteractionStart;
  @override
  State<StarMapCanvas> createState() => _StarMapCanvasState();
}

class _StarMapCanvasState extends State<StarMapCanvas> {
  final _labels = StarMapLabelCache();
  @override
  void didUpdateWidget(StarMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene) _labels.clear();
  }

  @override
  void dispose() {
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final system = widget.scene
              .hitTestScreen(details.localPosition, widget.controller.value);
          if (system != null) widget.onSelect(system);
        },
        child: Stack(children: [
          Positioned.fill(
              child: RepaintBoundary(
                  child: CustomPaint(
            key: const ValueKey('star-map-viewport'),
            painter: StarMapRenderer(
                scene: widget.scene,
                controller: widget.controller,
                labelCache: _labels,
                selectedId: widget.selectedId,
                originId: widget.originId,
                destinationId: widget.destinationId,
                routeIds: widget.routeIds,
                avoided: widget.avoided,
                showLabels: widget.showLabels,
                showConnections: widget.showConnections,
                textScale: MediaQuery.textScalerOf(context).scale(11) / 11),
          ))),
          Positioned.fill(
              child: InteractiveViewer(
            transformationController: widget.controller,
            constrained: false,
            minScale: 0.08,
            maxScale: 10,
            boundaryMargin: const EdgeInsets.all(1600),
            onInteractionStart: widget.onInteractionStart,
            child: SizedBox(
                width: widget.scene.canvasSize.width,
                height: widget.scene.canvasSize.height),
          )),
        ]),
      );
}
