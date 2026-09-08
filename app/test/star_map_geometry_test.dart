import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/ui/star_map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

SolarSystem _system(int id, double x, double z, {int region = 1}) =>
    SolarSystem(
        id: id,
        name: 'System $id',
        regionId: region,
        regionName: 'Test',
        security: .8,
        x: x,
        y: 0,
        z: z);

Matrix4 _center(Offset point, double scale,
        {Offset screen = const Offset(32, 32)}) =>
    Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
          screen.dx - point.dx * scale, screen.dy - point.dy * scale, 0);

Future<Uint8List> _pixels(StarMapScene scene, double scale,
    {int? selected, List<int> route = const []}) async {
  final recorder = ui.PictureRecorder();
  final controller =
      TransformationController(_center(const Offset(700, 525), scale));
  final cache = StarMapLabelCache();
  StarMapRenderer(
          scene: scene,
          controller: controller,
          labelCache: cache,
          showLabels: false,
          selectedId: selected,
          routeIds: route)
      .paint(Canvas(recorder), const Size(64, 64));
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  cache.dispose();
  controller.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'scene projection is immutable, bounded and includes isolated regional systems',
      () {
    final universe = Universe([
      _system(1, -500, -300),
      _system(2, 500, 300),
      _system(3, 0, 0, region: 2)
    ], const [
      Gate(1, 2)
    ]);
    final scene = StarMapScene(universe);
    expect(scene.systems.map((system) => system.id), [1, 2]);
    for (final point in scene.points.values) {
      expect((Offset.zero & scene.canvasSize).contains(point), isTrue);
    }
    expect(() => scene.points[99] = Offset.zero, throwsUnsupportedError);
    expect(
        () => scene.systems.add(universe.systems.last), throwsUnsupportedError);
    final isolated = StarMapScene(universe, regionId: 2);
    expect(isolated.points[3], const Offset(700, 525));
    expect(isolated.edges, isEmpty);
  });

  test(
      'edge clipping keeps crossing and touching segments with offscreen endpoints',
      () {
    final scene = StarMapScene(Universe(
        [_system(1, -100, 0), _system(2, 100, 0)], const [Gate(1, 2)]));
    const center = Rect.fromLTWH(690, 515, 20, 20);
    expect(scene.systemsIn(center), isEmpty);
    expect(scene.edgesIn(center).single.from, 1);
    expect(scene.edgesIn(const Rect.fromLTWH(690, 400, 20, 20)), isEmpty);
    final edge = StarMapEdge(1, 2, const Offset(-5, 0), const Offset(5, 0));
    expect(edge.intersects(const Rect.fromLTWH(0, 0, 1, 1)), isTrue);
    expect(edge.intersects(const Rect.fromLTWH(0, 1, 1, 1)), isFalse);
  });

  test(
      '20dp hit radius is independent of zoom and overlapping ties are deterministic',
      () {
    final scene = StarMapScene(Universe(
        [_system(2, 0, 0), _system(1, 0, 0), _system(3, 100, 0)],
        const [Gate(1, 3), Gate(2, 3)]));
    for (final scale in [.25, 1.0, 10.0]) {
      final transform = _center(scene.points[1]!, scale);
      expect(scene.hitTestScreen(const Offset(32, 32), transform)!.id, 1);
      expect(scene.hitTestScreen(const Offset(52, 32), transform)!.id, 1);
      expect(scene.hitTestScreen(const Offset(52.1, 32), transform), isNull);
    }
    expect(scene.hitTestScreen(Offset.zero, Matrix4.zero()), isNull);
  });

  test(
      'selected node and ring occupy identical pixels from overview to 10x zoom',
      () async {
    final scene =
        StarMapScene(Universe([_system(1, 0, 0)], const []), regionId: 1);
    final baseline = await _pixels(scene, 1, selected: 1);
    for (final scale in [.25, 10.0]) {
      final pixels = await _pixels(scene, scale, selected: 1);
      // Crop around the marker; label placement is independently collision-aware.
      for (var y = 24; y < 40; y++) {
        for (var x = 24; x < 40; x++) {
          final offset = (y * 64 + x) * 4;
          expect(pixels.sublist(offset, offset + 4),
              baseline.sublist(offset, offset + 4));
        }
      }
    }
  });

  test('gate and route stroke pixels stay constant below and above unit zoom',
      () async {
    final scene = StarMapScene(Universe(
        [_system(1, -100, 0), _system(2, 100, 0)], const [Gate(1, 2)]));
    for (final route in [
      <int>[],
      [1, 2]
    ]) {
      final baseline = await _pixels(scene, 1, route: route);
      expect(await _pixels(scene, .25, route: route), baseline);
      expect(await _pixels(scene, 10, route: route), baseline);
    }
  });

  test(
      'batched overview keeps marker size while reducing per-node drawing calls',
      () async {
    final scene = StarMapScene(
        Universe([
          _system(1, -1000, -1000),
          _system(2, 1000, 1000),
          _system(3, 0, 0),
          for (var id = 4; id < 604; id++) _system(id, 100, 0),
        ], const []),
        regionId: 1);
    List<int> extent(Uint8List pixels) {
      final xs = <int>[];
      final ys = <int>[];
      for (var y = 24; y < 40; y++) {
        for (var x = 24; x < 40; x++) {
          final offset = (y * 64 + x) * 4;
          if (pixels[offset] > 20 ||
              pixels[offset + 1] > 25 ||
              pixels[offset + 2] > 30) {
            xs.add(x);
            ys.add(y);
          }
        }
      }
      xs.sort();
      ys.sort();
      return [xs.first, xs.last, ys.first, ys.last];
    }

    for (final selected in [null, 3]) {
      final expected = extent(await _pixels(scene, 1, selected: selected));
      expect(extent(await _pixels(scene, .25, selected: selected)), expected);
      expect(extent(await _pixels(scene, 10, selected: selected)), expected);
    }
    final controller =
        TransformationController(_center(const Offset(700, 525), .25));
    final cache = StarMapLabelCache();
    final canvas = _LabelCanvas();
    StarMapRenderer(
            scene: scene,
            controller: controller,
            labelCache: cache,
            selectedId: 3)
        .paint(canvas, const Size(64, 64));
    expect(canvas.rawPointCalls, 3);
    expect(canvas.circleCalls, 2,
        reason: 'Only the selected node and ring need individual circles.');
    cache.dispose();
    controller.dispose();
  });

  test(
      'label rectangles do not collide and layouts have bounded disposal-aware reuse',
      () {
    final universe = Universe(
        [for (var id = 1; id <= 50; id++) _system(id, 0, 0)], const []);
    final scene = StarMapScene(universe, regionId: 1);
    final cache = StarMapLabelCache(maxEntries: 8);
    final controller = TransformationController(
        _center(const Offset(700, 525), 1, screen: const Offset(160, 160)));
    final canvas = _LabelCanvas();
    StarMapRenderer(scene: scene, controller: controller, labelCache: cache)
        .paint(canvas, const Size(320, 320));
    expect(canvas.labels, isNotEmpty);
    for (var a = 0; a < canvas.labels.length; a++) {
      for (var b = a + 1; b < canvas.labels.length; b++) {
        expect(canvas.labels[a].overlaps(canvas.labels[b]), isFalse);
      }
    }
    expect(cache.length, lessThanOrEqualTo(8));
    expect(cache.disposedLayouts, greaterThan(0));
    final retained = cache.layout('Retained');
    expect(cache.layout('Retained'), same(retained));
    final disposals = cache.disposedLayouts + cache.length;
    cache.dispose();
    expect(cache.length, 0);
    expect(cache.disposedLayouts, disposals);
    expect(cache.isDisposed, isTrue);
    cache.dispose();
    expect(cache.disposedLayouts, disposals);
    expect(() => cache.layout('After disposal'), throwsStateError);
    controller.dispose();
  });

  test(
      'overview skips ordinary labels and painter snapshots mutable route/avoid sets',
      () {
    final scene = StarMapScene(
        Universe(
            [for (var id = 1; id <= 120; id++) _system(id, id.toDouble(), 0)],
            const []),
        regionId: 1);
    final controller =
        TransformationController(Matrix4.diagonal3Values(.25, .25, 1));
    final cache = StarMapLabelCache();
    final route = <int>[];
    final avoided = <int>{};
    final old = StarMapRenderer(
        scene: scene,
        controller: controller,
        labelCache: cache,
        routeIds: route,
        avoided: avoided);
    old.paint(_LabelCanvas(), const Size(400, 300));
    expect(cache.length, 0);
    route.addAll([1, 2]);
    avoided.add(1);
    final next = StarMapRenderer(
        scene: scene,
        controller: controller,
        labelCache: cache,
        routeIds: route,
        avoided: avoided);
    expect(next.shouldRepaint(old), isTrue);
    expect(old.routeIds, isEmpty);
    expect(old.avoided, isEmpty);
    expect(
        StarMapRenderer(
                scene: scene,
                controller: controller,
                labelCache: cache,
                routeIds: route,
                avoided: avoided)
            .shouldRepaint(next),
        isFalse);
    cache.dispose();
    controller.dispose();
  });

  testWidgets(
      'transform changes repaint only canvas; screen taps work and resources detach',
      (tester) async {
    final scene =
        StarMapScene(Universe([_system(1, 0, 0)], const []), regionId: 1);
    final controller = _ObservedTransform(
        _center(scene.points[1]!, 1, screen: const Offset(50, 50)));
    var builds = 0;
    SolarSystem? selected;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      builds++;
      return SizedBox(
          width: 200,
          height: 200,
          child: StarMapCanvas(
              scene: scene,
              controller: controller,
              onSelect: (system) => selected = system));
    }))));
    final before = builds;
    final finder = find.byKey(const ValueKey('star-map-viewport'));
    final paint =
        tester.widget<CustomPaint>(finder).painter! as StarMapRenderer;
    final render = tester.renderObject<RenderCustomPaint>(finder);
    expect(tester.getSize(finder), const Size(200, 200));
    expect(controller.hasRegisteredListeners, isTrue);
    controller.value =
        _center(scene.points[1]!, 10, screen: const Offset(50, 50));
    expect(render.debugNeedsPaint, isTrue);
    await tester.pump();
    expect(builds, before);
    await tester.tapAt(tester.getTopLeft(finder) + const Offset(68, 50));
    await tester.pump();
    expect(selected?.id, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(paint.labelCache.isDisposed, isTrue);
    expect(controller.hasRegisteredListeners, isFalse);
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}

class _LabelCanvas implements Canvas {
  final labels = <Rect>[];
  int rawPointCalls = 0;
  int circleCalls = 0;
  @override
  void drawRawPoints(ui.PointMode mode, Float32List points, Paint paint) =>
      rawPointCalls++;
  @override
  void drawCircle(Offset center, double radius, Paint paint) => circleCalls++;
  @override
  void drawRect(Rect rect, Paint paint) => labels.add(rect);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ObservedTransform extends TransformationController {
  _ObservedTransform(super.value);
  bool get hasRegisteredListeners => hasListeners;
}
