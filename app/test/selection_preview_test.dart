import 'dart:io';
import 'dart:ui' as ui;

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/catalogue_browser.dart';
import 'package:eve_local_station/domain/compatibility.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/main.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:eve_local_station/ui/theme.dart';
import 'package:eve_local_station/ui/type_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

var _loadedFonts = false;

Future<void> _previewFonts() async {
  if (_loadedFonts ||
      Platform.environment['ELS_PREVIEW_DIR'] == null ||
      !Platform.isWindows) {
    return;
  }
  _loadedFonts = true;
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

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['ELS_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void _size(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
}

void _reset(WidgetTester tester) {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _openGroup(
    WidgetTester tester, CatalogueBrowser browser, int id) async {
  for (final group in browser.pathTo(id)) {
    if (find
        .widgetWithText(TextButton, group.displayName)
        .evaluate()
        .isNotEmpty) {
      continue;
    }
    final row = find.byKey(ValueKey('picker-group-${group.id}'));
    await tester.scrollUntilVisible(row, 160,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('picker-results')),
            matching: find.byType(Scrollable)),
        maxScrolls: 35);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }
}

void main() {
  final catalogue =
      Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());

  for (final ships in [true, false]) {
    testWidgets(
        '${ships ? 'ship' : 'module'} categories render on small screens with keyboard',
        (tester) async {
      _reset(tester);
      await _previewFonts();
      final types = ships
          ? catalogue.ships
          : catalogue.modules.where((type) => type.slot == Slot.high).toList();
      final fit = Fit.newShip(catalogue.byName['vexor']!);
      String? incompatibility(EveType type) {
        final issues = moduleCompatibility(
            module: type,
            catalogue: catalogue,
            fit: fit,
            slot: Slot.high,
            index: 0);
        return issues.isEmpty ? null : issues.join('；');
      }

      final candidates = ships
          ? types
          : types.where((type) => incompatibility(type) == null).toList();
      final browser = CatalogueBrowser(catalogue, candidates);
      final target = catalogue.marketGroups.values.firstWhere((group) =>
          group.name == (ships ? 'Standard Frigates' : 'Autocannons'));
      for (final configuration in [
        (size: const Size(390, 844), scale: 1.0),
        (size: const Size(360, 720), scale: 1.3)
      ]) {
        _size(tester, configuration.size, configuration.scale);
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                theme: stationTheme(),
                debugShowCheckedModeBanner: false,
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                home: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: SafeArea(
                        child: TypePicker(
                            title: ships ? '选择舰船' : '选择高槽模块',
                            types: types,
                            catalogue: catalogue,
                            incompatibility:
                                ships ? null : incompatibility))))));
        await tester.pumpAndSettle();
        await _openGroup(tester, browser, target.id);
        expect(find.widgetWithText(TextButton, target.displayName),
            findsOneWidget);
        expect(
            tester.getSize(find.byKey(const ValueKey('picker-results'))).height,
            greaterThan(300));
        expect(tester.takeException(), isNull);
        await _capture(tester, boundary,
            '${ships ? 'ship' : 'module'}-picker${configuration.scale == 1 ? '' : '-360'}');
        await tester.showKeyboard(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byType(TextField), ships ? 'Rifter' : '200mm AutoCannon II');
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('picker-type-${ships ? 587 : 2889}')),
            findsOneWidget);
        expect(
            tester.getSize(find.byKey(const ValueKey('picker-results'))).height,
            greaterThan(100));
        expect(tester.takeException(), isNull);
        if (configuration.scale > 1) {
          await _capture(tester, boundary,
              '${ships ? 'ship' : 'module'}-picker-keyboard-360');
        }
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('Vexor copy menu uses a real native calculation for preview',
      (tester) async {
    _reset(tester);
    await _previewFonts();
    final module = catalogue.byName['drone link augmentor i']!;
    final fit = Fit.newShip(catalogue.byName['vexor']!)
      ..modules.add(FittedModule(
          typeId: module.id,
          slot: Slot.high,
          index: 0,
          state: defaultModuleState(module)));
    final library = Platform.environment['ELS_NATIVE_LIBRARY'];
    FittingEngine engine = const UnavailableFittingEngine();
    if (Platform.environment['ELS_PREVIEW_DIR'] != null) {
      expect(library, isNotNull,
          reason: 'Exported fitting previews require the real native library.');
    }
    if (library != null) {
      final result = await tester.runAsync(() => NativeFittingEngine(
              Directory('assets/engine').absolute.path,
              libraryPath: library)
          .calculate(fit));
      expect(result!.available, isTrue, reason: result.error);
      expect(result.stats['cpu_used'], greaterThan(0));
      engine = _MeasuredEngine(result);
    }
    final store = MemoryFitStore();
    await store.save([fit]);
    for (final configuration in [
      (size: const Size(390, 844), scale: 1.0),
      (size: const Size(360, 720), scale: 1.3)
    ]) {
      _size(tester, configuration.size, configuration.scale);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: EveLocalApp(
              catalogue: catalogue,
              universe: testUniverse(),
              store: store,
              engine: engine)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text(module.displayName));
      await tester.pumpAndSettle();
      expect(find.text('复制一个'), findsOneWidget);
      expect(find.text('填满剩余同类槽位'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(ListTile, '复制一个')).height,
          greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
      await _capture(tester, boundary,
          'module-copy${configuration.scale == 1 ? '' : '-360'}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}

// The exact displayed fixture is measured once outside the widget's fake clock;
// this render-only engine never synthesizes numbers or accepts editing actions.
class _MeasuredEngine implements FittingEngine {
  const _MeasuredEngine(this.result);
  final Calculation result;
  @override
  Future<Calculation> calculate(Fit fit) async => result;
}
