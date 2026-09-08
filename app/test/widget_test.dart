import 'dart:io';
import 'dart:ui' as ui;

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/main.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:eve_local_station/ui/type_picker.dart';
import 'package:eve_local_station/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'new fitting saves locally and map remains navigable on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryFitStore();
      await tester.pumpWidget(
        EveLocalApp(
          catalogue: testCatalogue(),
          universe: testUniverse(),
          store: store,
          engine: const UnavailableFittingEngine(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无本地装配'), findsOneWidget);
      await tester.tap(find.text('新建装配'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rifter'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fitting-summary')), findsOneWidget);
      await tester.tap(find.byTooltip('保存到本机'));
      await tester.pumpAndSettle();
      expect((await store.load()).single.shipTypeId, 587);
      await tester.tap(find.text('星图与路线').last);
      await tester.pumpAndSettle();
      expect(find.text('最少跳数'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual SDE screens render without overflow at phone and desktop sizes',
    (tester) async {
      final preview = Platform.environment['ELS_PREVIEW_DIR'];
      if (preview != null && Platform.isWindows) {
        final font = File('C:/Windows/Fonts/msyh.ttc');
        if (font.existsSync()) {
          for (final family in ['Roboto', 'Ahem', 'Segoe UI']) {
            final loader = FontLoader(family)
              ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              );
            await loader.load();
          }
          final material = File(
            '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
          );
          if (material.existsSync()) {
            final icons = FontLoader('MaterialIcons')
              ..addFont(
                Future.value(ByteData.sublistView(material.readAsBytesSync())),
              );
            await icons.load();
          }
        }
      }
      final catalogue = Catalogue.decode(
        File('assets/data/catalogue.json').readAsStringSync(),
      );
      final universe = Universe.decode(
        File('assets/data/universe.json').readAsStringSync(),
      );
      final ship = catalogue.ships.firstWhere((ship) => ship.name == 'Rifter');
      final fit = Fit.newShip(ship)..name = '${ship.displayName} · 实用装配';
      final gun = catalogue.modules.firstWhere(
        (type) => type.name == '200mm AutoCannon II',
      );
      for (var index = 0; index < 3; index++) {
        fit.modules.add(FittedModule(
            typeId: gun.id,
            slot: Slot.high,
            index: index,
            chargeTypeId: catalogue.byName['emp s']!.id));
      }
      fit.modules.add(FittedModule(
          typeId: catalogue.byName['1mn afterburner ii']!.id,
          slot: Slot.medium,
          index: 0));
      fit.modules.add(FittedModule(
          typeId: catalogue.byName['small armor repairer ii']!.id,
          slot: Slot.low,
          index: 0));
      final library = Platform.environment['ELS_NATIVE_LIBRARY'];
      FittingEngine engine = const UnavailableFittingEngine();
      if (library != null) {
        final measured = await tester.runAsync(() => NativeFittingEngine(
                Directory('assets/engine').absolute.path,
                libraryPath: library)
            .calculate(fit));
        expect(measured!.available, isTrue, reason: measured.error);
        expect(measured.stats['dps'], greaterThan(0));
        // A real FFI result for precisely this fixture is captured before the
        // widget's fake clock starts. No preview numbers are fabricated.
        engine = _MeasuredPreviewEngine(measured);
      }
      final store = MemoryFitStore();
      await store.save([fit]);
      for (final size in [const Size(390, 844), const Size(1280, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: EveLocalApp(
              catalogue: catalogue,
              universe: universe,
              store: store,
              engine: engine,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('fitting-summary')), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (preview != null) {
          await _capture(
            boundary,
            '$preview/fitting-${size.width.toInt()}.png',
            tester,
          );
        }
        if (library != null && size.width < 900) {
          await tester.tap(find.byKey(const ValueKey('fitting-summary')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('CPU 使用量'));
          await tester.pumpAndSettle();
          expect(find.text('理论伤害'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (preview != null) {
            await _capture(boundary,
                '$preview/fitting-stats-${size.width.toInt()}.png', tester);
          }
          Navigator.of(tester.element(find.text('CPU 使用量'))).pop();
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('星图与路线').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择星系'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Amarr');
        await tester.pumpAndSettle();
        await tester.tap(find
            .text(universe.systems
                .firstWhere((system) => system.name == 'Amarr')
                .displayName)
            .last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (preview != null) {
          await _capture(
            boundary,
            '$preview/map-${size.width.toInt()}.png',
            tester,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );

  testWidgets(
      'compatibility picker hides known invalid choices and explains them when explicitly shown',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: stationTheme(),
        home: Scaffold(
            body: TypePicker(
          title: '选择弹药',
          types: [
            EveType(id: 1, name: 'Compatible round', kind: 'charge'),
            EveType(id: 2, name: 'Wrong size round', kind: 'charge')
          ],
          incompatibility: (type) => type.id == 2 ? '弹药尺寸不兼容' : null,
        ))));
    expect(find.text('Compatible round'), findsOneWidget);
    expect(find.text('Wrong size round'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Wrong size round'), findsOneWidget);
    expect(find.text('弹药尺寸不兼容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('passive equipment menu exposes only native-supported states',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalogue =
        Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());
    final gyro = catalogue.byName['gyrostabilizer ii']!;
    final fit = Fit.newShip(catalogue.byName['rifter']!)
      ..modules.add(FittedModule(
          typeId: gyro.id,
          slot: Slot.low,
          index: 0,
          state: defaultModuleState(gyro)));
    final store = MemoryFitStore();
    await store.save([fit]);
    await tester.pumpWidget(EveLocalApp(
        catalogue: catalogue,
        universe: testUniverse(),
        store: store,
        engine: const UnavailableFittingEngine()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('模块状态：在线'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('模块状态：在线'));
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(PopupMenuItem<ModuleState>, '离线'), findsOneWidget);
    expect(
        find.widgetWithText(PopupMenuItem<ModuleState>, '在线'), findsOneWidget);
    expect(find.widgetWithText(PopupMenuItem<ModuleState>, '激活'), findsNothing);
    expect(find.widgetWithText(PopupMenuItem<ModuleState>, '过载'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _MeasuredPreviewEngine implements FittingEngine {
  const _MeasuredPreviewEngine(this.result);
  final Calculation result;
  @override
  Future<Calculation> calculate(Fit fit) async => result;
}

Future<void> _capture(GlobalKey key, String path, WidgetTester tester) async {
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
