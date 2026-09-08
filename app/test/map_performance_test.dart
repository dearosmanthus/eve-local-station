import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/ui/star_map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// These are host-side debug measurements, not GPU raster timings or phone FPS.
// No millisecond threshold is asserted: correctness and bounded work are stable
// test contracts, whereas timing depends on the host and concurrent builds.
Map<String, Object> _distribution(List<int> microseconds) {
  final sorted = [...microseconds]..sort();
  return {
    'samples': sorted.length,
    'median_us': sorted[sorted.length ~/ 2],
    'p95_us': sorted[((sorted.length - 1) * 0.95).ceil()],
    'maximum_us': sorted.last,
  };
}

Matrix4 _view(Offset center, double scale, Size viewport) =>
    Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(viewport.width / 2 - center.dx * scale,
          viewport.height / 2 - center.dy * scale, 0);

Rect _worldView(Matrix4 matrix, Size viewport) {
  final inverse = Matrix4.inverted(matrix);
  return Rect.fromPoints(MatrixUtils.transformPoint(inverse, Offset.zero),
      MatrixUtils.transformPoint(inverse, viewport.bottomRight(Offset.zero)));
}

SolarSystem? _nearest(
    StarMapScene scene, Offset screen, Matrix4 matrix, double radius) {
  SolarSystem? best;
  var distance = radius;
  for (final system in scene.systems) {
    final delta =
        (MatrixUtils.transformPoint(matrix, scene.points[system.id]!) - screen)
            .distance;
    if (delta < distance) {
      distance = delta;
      best = system;
    }
  }
  return best;
}

// Independent line-versus-four-sides oracle for the real projected gate data.
bool _intersects(Offset start, Offset end, Rect rect) {
  if (rect.contains(start) || rect.contains(end)) return true;
  final direction = end - start;
  double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
  final corners = [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft
  ];
  for (var index = 0; index < corners.length; index++) {
    final first = corners[index];
    final second = corners[(index + 1) % corners.length];
    final side = second - first;
    final denominator = cross(direction, side);
    if (denominator.abs() < 1e-12) continue;
    final offset = first - start;
    final alongLine = cross(offset, side) / denominator;
    final alongSide = cross(offset, direction) / denominator;
    if (alongLine >= 0 && alongLine <= 1 && alongSide >= 0 && alongSide <= 1) {
      return true;
    }
  }
  return false;
}

int _record(StarMapRenderer painter, Size size) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  final watch = Stopwatch()..start();
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  watch.stop();
  picture.dispose();
  return watch.elapsedMicroseconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Universe universe;
  final report = <String, Object>{
    'schemaVersion': 1,
    'measurement': 'Flutter host debug CPU work and Canvas recording only',
    'limitations': [
      'Not Android device frame times or FPS',
      'Excludes GPU rasterization, compositor and touch input latency',
      'Text uses the Flutter test font; not an Android font-rendering benchmark',
      'No release-mode speedup claim or old-version comparison',
    ],
  };

  setUpAll(() {
    universe =
        Universe.decode(File('assets/data/universe.json').readAsStringSync());
    report['data'] = {
      'build': universe.provenance['buildNumber'] ?? 'unavailable',
      'systems': universe.systems.length,
      'gates': universe.gates.length,
      'runtime': Platform.version,
      'operatingSystem': Platform.operatingSystem,
    };
  });

  test('real SDE projection preserves every eligible system and each region',
      () {
    expect(universe.systems, hasLength(8490));
    expect(universe.gates, hasLength(6989));
    final measurements = <int>[];
    StarMapScene? network;
    for (var sample = 0; sample < 9; sample++) {
      final watch = Stopwatch()..start();
      final scene = StarMapScene(universe);
      watch.stop();
      network = scene;
      if (sample > 0) measurements.add(watch.elapsedMicroseconds);
    }
    final connected = universe.systems
        .where((system) => universe.neighbors[system.id]!.isNotEmpty)
        .map((system) => system.id)
        .toSet();
    expect(connected, hasLength(5268));
    expect(network!.points.keys.toSet(), connected);
    expect(network.systems.map((system) => system.id).toSet(), connected);
    final regionIds = universe.systems.map((system) => system.regionId).toSet();
    final visited = <int>{};
    for (final regionId in regionIds) {
      final region = StarMapScene(universe, regionId: regionId);
      expect(
          region.points.keys.toSet(),
          universe.systems
              .where((system) => system.regionId == regionId)
              .map((system) => system.id)
              .toSet());
      visited.addAll(region.points.keys);
      for (final point in region.points.values) {
        expect(point.dx.isFinite && point.dy.isFinite, isTrue);
        expect((Offset.zero & region.canvasSize).contains(point), isTrue);
      }
    }
    expect(visited, universe.byId.keys.toSet());
    report['networkProjectionAndIndex'] = _distribution(measurements);
    report['coverage'] = {
      'networkSystems': connected.length,
      'allRegions': regionIds.length,
      'projectedAcrossRegions': visited.length,
    };
  });

  test('real SDE viewport culling and screen hit tests agree with a full scan',
      () {
    final scene = StarMapScene(universe);
    final jita =
        universe.systems.singleWhere((system) => system.name == 'Jita');
    const viewport = Size(390, 560);
    final random = math.Random(3494416);
    final cullingTimes = <int>[];
    final hitTimes = <int>[];
    final workloads = <Map<String, Object>>[];
    for (final scale in [0.25, 1.0, 4.0, 10.0]) {
      final matrix = _view(scene.points[jita.id]!, scale, viewport);
      final rect = _worldView(matrix, viewport);
      final expected = scene.points.entries
          .where((entry) => rect.contains(entry.value))
          .map((entry) => entry.key)
          .toSet();
      List<SolarSystem> visible = [];
      List<StarMapEdge> edges = [];
      for (var sample = 0; sample < 36; sample++) {
        final watch = Stopwatch()..start();
        visible = scene.systemsIn(rect);
        edges = scene.edgesIn(rect);
        watch.stop();
        if (sample >= 4) cullingTimes.add(watch.elapsedMicroseconds);
      }
      expect(visible.map((system) => system.id).toSet(), expected);
      expect(
          edges.map((edge) => '${edge.from}:${edge.to}').toSet(),
          scene.edges
              .where((edge) => _intersects(edge.start, edge.end, rect))
              .map((edge) => '${edge.from}:${edge.to}')
              .toSet());
      workloads.add({
        'scale': scale,
        'visibleSystems': visible.length,
        'candidateGates': edges.length,
      });
      for (var sample = 0; sample < 16; sample++) {
        final screen = Offset(random.nextDouble() * viewport.width,
            random.nextDouble() * viewport.height);
        final expectedHit = _nearest(scene, screen, matrix, 20);
        final timer = Stopwatch()..start();
        final actualHit = scene.hitTestScreen(screen, matrix, radius: 20);
        timer.stop();
        hitTimes.add(timer.elapsedMicroseconds);
        expect(actualHit?.id, expectedHit?.id);
      }
    }
    expect(workloads.last['visibleSystems'] as int,
        lessThan(scene.systems.length));
    final longGate = scene.edges.reduce((a, b) =>
        (a.end - a.start).distance > (b.end - b.start).distance ? a : b);
    final crossingView = Rect.fromCenter(
        center: (longGate.start + longGate.end) / 2, width: 2, height: 2);
    expect(crossingView.contains(longGate.start), isFalse);
    expect(crossingView.contains(longGate.end), isFalse);
    expect(scene.edgesIn(crossingView), contains(longGate));
    report['visibleQuery'] = _distribution(cullingTimes);
    report['screenHitTest'] = _distribution(hitTimes);
    report['jitaWorkloads'] = workloads;
  });

  test('real SDE Canvas recording reuses bounded label layouts during a drag',
      () {
    final scene = StarMapScene(universe);
    final jita =
        universe.systems.singleWhere((system) => system.name == 'Jita');
    final amarr =
        universe.systems.singleWhere((system) => system.name == 'Amarr');
    final route = planRoute(universe, jita.id, amarr.id)!;
    const viewport = Size(390, 560);
    final cache = StarMapLabelCache(maxEntries: 256);
    final controller = TransformationController();
    final painter = StarMapRenderer(
      scene: scene,
      controller: controller,
      labelCache: cache,
      selectedId: jita.id,
      originId: jita.id,
      destinationId: amarr.id,
      routeIds: route.systemIds,
      showLabels: true,
    );
    final measurements = <String, Object>{};
    try {
      for (final scale in [0.25, 4.0, 10.0]) {
        controller.value = _view(scene.points[jita.id]!, scale, viewport);
        _record(painter, viewport);
        final layoutsBefore = cache.length;
        final disposalsBefore = cache.disposedLayouts;
        final stationary = <int>[];
        for (var sample = 0; sample < 8; sample++) {
          stationary.add(_record(painter, viewport));
        }
        expect(cache.length, layoutsBefore);
        expect(cache.disposedLayouts, disposalsBefore);
        final moving = <int>[];
        for (var sample = 0; sample < 48; sample++) {
          controller.value = _view(
              scene.points[jita.id]! + Offset(sample * 2.0 / scale, 0),
              scale,
              viewport);
          moving.add(_record(painter, viewport));
          expect(cache.length, lessThanOrEqualTo(256));
        }
        measurements['scale_$scale'] = {
          'stationary': _distribution(stationary),
          'drag': _distribution(moving),
          'cachedLabels': cache.length,
          'disposedLayouts': cache.disposedLayouts,
        };
      }
      report['canvasRecording'] = measurements;
      final output = Platform.environment['ELS_MAP_BENCHMARK'];
      if (output != null) {
        final target = File(output);
        target.parent.createSync(recursive: true);
        target.writeAsStringSync(
            '${const JsonEncoder.withIndent('  ').convert(report)}\n');
      }
      // One compact machine-readable summary also survives normal CI output.
      // ignore: avoid_print
      print('MAP_HOST_BENCHMARK ${jsonEncode(report)}');
    } finally {
      controller.dispose();
      cache.dispose();
    }
    expect(cache.isDisposed, isTrue);
  });
}
