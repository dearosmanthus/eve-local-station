import 'dart:io';
import 'dart:ui' as ui;

import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/main.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:eve_local_station/ui/star_map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

var _fontsLoaded = false;
Future<void> _fonts() async {
  if (_fontsLoaded ||
      Platform.environment['ELS_PREVIEW_DIR'] == null ||
      !Platform.isWindows) {
    return;
  }
  _fontsLoaded = true;
  final font = File('C:/Windows/Fonts/msyh.ttc');
  if (font.existsSync()) {
    for (final family in ['Roboto', 'Ahem', 'Segoe UI']) {
      await (FontLoader(family)
            ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync()))))
          .load();
    }
  }
  final material = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf');
  if (material.existsSync()) {
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(material.readAsBytesSync()))))
        .load();
  }
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['ELS_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _search(WidgetTester tester, SolarSystem system) async {
  await tester.tap(find.byTooltip('搜索星系'));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.byKey(const ValueKey('system-picker-search')), system.name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('system-option-${system.id}')));
  await tester.pumpAndSettle();
}

void main() {
  final universe =
      Universe.decode(File('assets/data/universe.json').readAsStringSync());
  final jita = universe.systems.firstWhere((system) => system.name == 'Jita');
  final amarr = universe.systems.firstWhere((system) => system.name == 'Amarr');

  for (final config in [
    (size: const Size(390, 844), scale: 1.0, suffix: ''),
    (size: const Size(360, 720), scale: 1.3, suffix: '-360'),
    (size: const Size(720, 360), scale: 1.0, suffix: '-landscape'),
  ]) {
    testWidgets(
        'real map overview, detail and route render ${config.size} at ${config.scale}',
        (tester) async {
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = config.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _fonts();
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: EveLocalApp(
              catalogue: testCatalogue(),
              universe: universe,
              store: MemoryFitStore(),
              engine: const UnavailableFittingEngine())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('星图与路线').last);
      await tester.pumpAndSettle();
      var map = tester.widget<StarMapCanvas>(find.byType(StarMapCanvas));
      expect(universe.systems.length, 8490);
      expect(map.scene.systems.length, greaterThan(5000));
      expect(
          tester
              .getSize(find.byKey(const ValueKey('star-map-viewport')))
              .height,
          greaterThanOrEqualTo(180));
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary, 'map05-overview${config.suffix}');

      await _search(tester, jita);
      map = tester.widget<StarMapCanvas>(find.byType(StarMapCanvas));
      expect(map.selectedId, jita.id);
      expect(find.byKey(const ValueKey('map-system-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary, 'map05-focused${config.suffix}');
      if (config.suffix.isEmpty) {
        for (var index = 0; index < 4; index++) {
          await tester.tap(find.byTooltip('放大星图'));
          await tester.pumpAndSettle();
        }
        await _search(tester, jita);
        map = tester.widget<StarMapCanvas>(find.byType(StarMapCanvas));
        expect(map.controller.value.storage[0], closeTo(10, .001));
        final size =
            tester.getSize(find.byKey(const ValueKey('star-map-viewport')));
        final point = MatrixUtils.transformPoint(
            map.controller.value, map.scene.points[jita.id]!);
        expect((Offset.zero & size).contains(point), isTrue);
        expect(tester.takeException(), isNull);
        await _capture(tester, boundary, 'map05-zoom10');
      }
      await tester.tap(find.text('星系详情 ›'));
      await tester.pumpAndSettle();
      expect(find.text('所属星座'), findsOneWidget);
      expect(find.text('恒星光谱'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary, 'map05-details${config.suffix}');
      final detailsList = find.byWidget(tester.widget<ListView>(find.ancestor(
          of: find.byTooltip('关闭详情'), matching: find.byType(ListView))));
      await tester.scrollUntilVisible(find.textContaining('相邻星系（'), 120,
          scrollable: find.descendant(
              of: detailsList, matching: find.byType(Scrollable)));
      expect(find.textContaining('相邻星系（'), findsOneWidget);
      await tester.fling(detailsList, const Offset(0, 1000), 1200);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择星系'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('system-picker-search')), amarr.name);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('system-option-${amarr.id}')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('查看整条路线'));
      await tester.tap(find.byTooltip('查看整条路线'));
      await tester.pumpAndSettle();
      map = tester.widget<StarMapCanvas>(find.byType(StarMapCanvas));
      expect(map.routeIds.first, jita.id);
      expect(map.routeIds.last, amarr.id);
      final viewport = Offset.zero &
          tester.getSize(find.byKey(const ValueKey('star-map-viewport')));
      for (final id in map.routeIds) {
        expect(
            viewport.contains(MatrixUtils.transformPoint(
                map.controller.value, map.scene.points[id]!)),
            isTrue,
            reason: 'Route system $id must be visible after fit.');
      }
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary, 'map05-route${config.suffix}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
