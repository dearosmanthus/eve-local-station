import 'dart:io';

import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/main.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:eve_local_station/ui/star_map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<void> showMap(WidgetTester tester, Universe universe) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(EveLocalApp(
      catalogue: testCatalogue(),
      universe: universe,
      store: MemoryFitStore(),
      engine: const UnavailableFittingEngine()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('星图与路线').last);
  await tester.pumpAndSettle();
}

StarMapCanvas canvas(WidgetTester tester) =>
    tester.widget<StarMapCanvas>(find.byType(StarMapCanvas));

Future<void> chooseSystem(
    WidgetTester tester, Finder endpoint, SolarSystem system) async {
  await tester.tap(endpoint);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), system.name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('system-option-${system.id}')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'zoom below one goes the right direction and resizing preserves the panned center',
      (tester) async {
    await showMap(tester, testUniverse());
    final originalScene = canvas(tester).scene;
    final controller = canvas(tester).controller;
    final initialScale = controller.value.storage[0];
    expect(initialScale, lessThan(1));
    await tester.tap(find.byTooltip('缩小星图'));
    await tester.pumpAndSettle();
    expect(controller.value.storage[0], closeTo(initialScale / 1.6, 0.00001));
    await tester.tap(find.byTooltip('放大星图'));
    await tester.pumpAndSettle();
    expect(controller.value.storage[0], closeTo(initialScale, 0.00001));
    await tester.dragFrom(tester.getCenter(find.byType(InteractiveViewer)),
        const Offset(-40, 30));
    await tester.pumpAndSettle();
    final oldSize = tester.getSize(find.byType(StarMapCanvas));
    final center =
        controller.toScene(Offset(oldSize.width / 2, oldSize.height / 2));
    final scale = controller.value.storage[0];
    tester.view.physicalSize = const Size(390, 924);
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(StarMapCanvas));
    final resizedCenter =
        controller.toScene(Offset(size.width / 2, size.height / 2));
    expect((resizedCenter - center).distance, lessThan(0.0001));
    expect(controller.value.storage[0], closeTo(scale, 0.00001));
    expect(identical(canvas(tester).scene, originalScene), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'swap route and fit the entire route while retaining scene on ordinary UI changes',
      (tester) async {
    final universe = testUniverse();
    await showMap(tester, universe);
    final originalScene = canvas(tester).scene;
    await chooseSystem(tester, find.text('选择星系'), universe.byId[3]!);
    expect(canvas(tester).routeIds, [1, 2, 3]);
    expect(identical(canvas(tester).scene, originalScene), isTrue);
    await tester.tap(find.byTooltip('交换起终点'));
    await tester.pumpAndSettle();
    expect(canvas(tester).originId, 3);
    expect(canvas(tester).destinationId, 1);
    expect(canvas(tester).routeIds, [3, 2, 1]);
    await tester.tap(find.byTooltip('查看整条路线'));
    await tester.pumpAndSettle();
    final view = canvas(tester);
    final size = tester.getSize(find.byType(StarMapCanvas));
    for (final id in view.routeIds) {
      final point = MatrixUtils.transformPoint(
          view.controller.value, view.scene.points[id]!);
      expect(point.dx, inInclusiveRange(0, size.width));
      expect(point.dy, inInclusiveRange(0, size.height));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'same isolated system remains visible when showing its zero jump route',
      (tester) async {
    final universe = testUniverse();
    await showMap(tester, universe);
    await chooseSystem(tester, find.text('Jita'), universe.byId[6]!);
    await chooseSystem(tester, find.text('选择星系'), universe.byId[6]!);
    expect(canvas(tester).routeIds, [6]);
    await tester.tap(find.byTooltip('查看整条路线'));
    await tester.pumpAndSettle();
    expect(canvas(tester).scene.points.containsKey(6), isTrue);
    expect(canvas(tester).selectedId, 6);
    expect(find.byKey(const ValueKey('map-system-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'official detail, copy, avoidance recovery and neighboring system navigation',
      (tester) async {
    final universe =
        Universe.decode(File('assets/data/universe.json').readAsStringSync());
    final jita = universe.systems.firstWhere((system) => system.name == 'Jita');
    await showMap(tester, universe);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    canvas(tester).onSelect(jita);
    await tester.pumpAndSettle();
    await tester.tap(find.text('星系详情 ›'));
    await tester.pumpAndSettle();
    expect(find.text(jita.constellationDisplayName), findsOneWidget);
    expect(find.text('行星数量'), findsOneWidget);
    await tester.tap(find.text('复制英文名'));
    await tester.pumpAndSettle();
    expect(copied, 'Jita');
    await tester.tap(find.text('避开此星系'));
    await tester.pumpAndSettle();
    expect(canvas(tester).avoided, contains(jita.id));
    await tester.tap(find.text('取消绕行'));
    await tester.pumpAndSettle();
    expect(canvas(tester).avoided, isNot(contains(jita.id)));
    final neighbor = universe.neighbors[jita.id]!.first;
    final neighborRow = find.byKey(ValueKey('map-neighbor-$neighbor'));
    await tester.scrollUntilVisible(neighborRow, 150,
        scrollable: find
            .descendant(
                of: find.byType(BottomSheet), matching: find.byType(Scrollable))
            .first);
    await tester.tap(neighborRow);
    await tester.pumpAndSettle();
    expect(canvas(tester).selectedId, neighbor);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'changing region clears outside selection and display settings preserve camera',
      (tester) async {
    final universe = Universe([
      ...testUniverse().systems,
      const SolarSystem(
          id: 20,
          name: 'Other region',
          regionId: 20,
          regionName: 'Second',
          security: 0.2,
          x: 0,
          y: 0,
          z: 0),
    ], testUniverse().gates);
    await showMap(tester, universe);
    canvas(tester).onSelect(universe.byId[1]!);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-region-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second').last);
    await tester.pumpAndSettle();
    expect(canvas(tester).selectedId, isNull);
    expect(canvas(tester).scene.byId.keys.toList(), [20]);
    final before = canvas(tester).controller.value.clone();
    await tester.tap(find.byTooltip('星图设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, '星门连线'));
    await tester.pumpAndSettle();
    expect(canvas(tester).showConnections, isFalse);
    expect(canvas(tester).controller.value, before);
    expect(tester.takeException(), isNull);
  });
}
