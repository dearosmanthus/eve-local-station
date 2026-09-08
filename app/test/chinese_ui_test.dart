import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/main.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:eve_local_station/ui/theme.dart';
import 'package:eve_local_station/ui/type_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  testWidgets('Chinese picker accepts English, translated and ID queries',
      (tester) async {
    final catalogue =
        Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());
    final rifter = catalogue.byName['rifter']!;
    await tester.pumpWidget(MaterialApp(
      theme: stationTheme(),
      home: Scaffold(body: TypePicker(title: '选择舰船', types: catalogue.ships)),
    ));
    for (final query in ['Rifter', rifter.displayName, '587']) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(ListTile),
              matching: find.text(rifter.displayName)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(ListTile), matching: find.text('Rifter')),
          findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
        'Chinese map leaves room for the map on a small phone at $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final universe =
          Universe.decode(File('assets/data/universe.json').readAsStringSync());
      final amarr = universe.systems.firstWhere((s) => s.name == 'Amarr');
      final jita = universe.systems.firstWhere((s) => s.name == 'Jita');
      await tester.pumpWidget(EveLocalApp(
        catalogue: testCatalogue(),
        universe: universe,
        store: MemoryFitStore(),
        engine: const UnavailableFittingEngine(),
      ));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context), const Locale('zh', 'CN'));
      expect(MaterialLocalizations.of(context).closeButtonTooltip, '关闭');
      await tester.tap(find.text('星图与路线').last);
      await tester.pumpAndSettle();
      expect(find.text(jita.displayName), findsOneWidget);
      await tester.tap(find.text('选择星系'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Amarr');
      await tester.pumpAndSettle();
      await tester.tap(find.text(amarr.displayName).last);
      await tester.pumpAndSettle();
      expect(find.text(amarr.displayName), findsOneWidget);
      expect(tester.getSize(find.byType(InteractiveViewer)).height,
          greaterThanOrEqualTo(300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(find.text(jita.displayName).last, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
