import 'dart:io';
import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/catalogue_browser.dart';
import 'package:eve_local_station/domain/compatibility.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/ui/type_picker.dart';
import 'package:eve_local_station/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openPicker(
    WidgetTester tester, Catalogue catalogue, List<EveType> types,
    {String? Function(EveType)? incompatibility, double scale = 1}) async {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  int? selected;
  await tester.pumpWidget(MaterialApp(
      theme: stationTheme(),
      home: Scaffold(
          body: StatefulBuilder(
              builder: (context, update) => Column(children: [
                    TextButton(
                        onPressed: () async {
                          final type = await pickType(context,
                              title: '选择物品',
                              catalogue: catalogue,
                              types: types,
                              incompatibility: incompatibility,
                              hint: incompatibility == null
                                  ? null
                                  : '仅筛选已知静态兼容条件。');
                          update(() => selected = type?.id);
                        },
                        child: const Text('打开')),
                    Text('已选 $selected'),
                  ])))));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Future<void> tapRow(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(target, 180,
      scrollable: find.descendant(
          of: find.byKey(const ValueKey('picker-results')),
          matching: find.byType(Scrollable)));
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  final catalogue =
      Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());
  testWidgets('official ship hierarchy reaches a hull without typing',
      (tester) async {
    await openPicker(tester, catalogue, catalogue.ships);
    final rifter = catalogue.byName['rifter']!;
    final path = CatalogueBrowser(catalogue, catalogue.ships)
        .pathTo(rifter.marketGroupId!);
    for (final group in path) {
      await tapRow(tester, 'picker-group-${group.id}');
    }
    await tapRow(tester, 'picker-type-${rifter.id}');
    expect(find.text('已选 587'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'global search returns to category and unclassified ships remain selectable',
      (tester) async {
    await openPicker(tester, catalogue, catalogue.ships);
    final rifter = catalogue.byName['rifter']!;
    final browser = CatalogueBrowser(catalogue, catalogue.ships);
    final path = browser.pathTo(rifter.marketGroupId!);
    await tapRow(tester, 'picker-group-${path.first.id}');
    await tester.enterText(find.byType(TextField), 'Punisher');
    await tester.pumpAndSettle();
    expect(
        find.byKey(ValueKey('picker-type-${catalogue.byName['punisher']!.id}')),
        findsOneWidget);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('picker-group-${path[1].id}')), findsWidgets);
    await tester.tap(find.text('全部分类'));
    await tester.pumpAndSettle();
    await tapRow(tester, 'picker-ungrouped');
    await tapRow(tester, 'picker-type-${browser.ungroupedTypes.first.id}');
    expect(find.text('已选 ${browser.ungroupedTypes.first.id}'), findsOneWidget);
  });

  testWidgets(
      'equipment grouping keeps compatibility and works with keyboard at large text',
      (tester) async {
    final fit = Fit.newShip(catalogue.byName['rifter']!);
    final modules =
        catalogue.modules.where((t) => t.slot == Slot.high).toList();
    String? incompatibility(EveType type) {
      final issues = moduleCompatibility(
          module: type,
          catalogue: catalogue,
          fit: fit,
          slot: Slot.high,
          index: 0);
      return issues.isEmpty ? null : issues.join('；');
    }

    await openPicker(tester, catalogue, modules,
        incompatibility: incompatibility, scale: 1.3);
    final gun = catalogue.byName['200mm autocannon ii']!;
    final browser = CatalogueBrowser(
        catalogue, modules.where((t) => incompatibility(t) == null));
    for (final group in browser.pathTo(gun.marketGroupId!)) {
      await tapRow(tester, 'picker-group-${group.id}');
    }
    await tester.scrollUntilVisible(
        find.byKey(ValueKey('picker-type-${gun.id}')), 180,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('picker-results')),
            matching: find.byType(Scrollable)));
    expect(find.byKey(ValueKey('picker-type-${gun.id}')), findsOneWidget);
    final invalid = modules.firstWhere((type) => incompatibility(type) != null);
    await tester.enterText(find.byType(TextField), '${invalid.id}');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('picker-type-${invalid.id}')), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('picker-type-${invalid.id}')), findsOneWidget);
    // Larger guns may fit statically if they use the same slot/hardpoint;
    // resource usage is left to the engine, never invented by this picker.
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), '${gun.id}');
    await tester.pumpAndSettle();
    await tapRow(tester, 'picker-type-${gun.id}');
    expect(find.text('已选 ${gun.id}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'back from an ancestor of the automatic base goes up instead of jumping into its leaf',
      (tester) async {
    final gun = catalogue.byName['200mm autocannon ii']!;
    final path = CatalogueBrowser(catalogue, [gun]).pathTo(gun.marketGroupId!);
    await openPicker(tester, catalogue, [gun]);
    expect(find.byKey(ValueKey('picker-type-${gun.id}')), findsOneWidget);
    await tester.ensureVisible(find.text(path.first.displayName));
    await tester.tap(find.text(path.first.displayName));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回上级分类'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(ValueKey('picker-group-${path.first.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('picker-type-${gun.id}')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
