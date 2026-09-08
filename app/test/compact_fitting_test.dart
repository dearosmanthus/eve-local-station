import 'dart:io';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/main.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Catalogue _catalogue() =>
    Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());

Fit _fit(Catalogue catalogue) {
  final fit = Fit.newShip(catalogue.byName['rifter']!);
  final gun = catalogue.byName['200mm autocannon ii']!;
  for (var index = 0; index < 3; index++) {
    fit.modules.add(FittedModule(
        typeId: gun.id,
        slot: Slot.high,
        index: index,
        state: defaultModuleState(gun),
        chargeTypeId: catalogue.byName['emp s']!.id));
  }
  return fit;
}

Future<void> _show(WidgetTester tester, Catalogue catalogue, FitStore store,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(EveLocalApp(
      catalogue: catalogue,
      universe: testUniverse(),
      store: store,
      engine: const UnavailableFittingEngine()));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'strategic cruisers keep drone editing available during calculation',
      (tester) async {
    final catalogue = _catalogue();
    final store = MemoryFitStore();
    await store.save([Fit.newShip(catalogue.byName['tengu']!)]);
    await _show(tester, catalogue, store);
    await tester.ensureVisible(find.text('添加无人机'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加无人机'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('compact phone shows at least 9 complete slot rows at $scale',
        (tester) async {
      final catalogue = _catalogue();
      final store = MemoryFitStore();
      await store.save([_fit(catalogue)]);
      await _show(tester, catalogue, store, scale: scale);
      final viewport = tester
          .getRect(find.byKey(const ValueKey('fitting-equipment-scroll')));
      final rows = find.byWidgetPredicate((widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('fit-slot-'));
      final visible = rows.evaluate().where((element) {
        final box = element.renderObject as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        return rect.top >= viewport.top && rect.bottom <= viewport.bottom;
      }).length;
      expect(visible, greaterThanOrEqualTo(9),
          reason:
              'The first viewport must show useful equipment, not decoration.');
      expect(
          tester.getSize(find.byKey(const ValueKey('fit-slot-high-0'))).height,
          52);
      expect(
          tester
              .getSize(find.byKey(const ValueKey('fit-slot-medium-0')))
              .height,
          44);
      expect(tester.getSize(find.byTooltip('移除模块').first).width,
          greaterThanOrEqualTo(44));
      expect(find.text('装配工作台'), findsNothing);
      expect(find.text(catalogue.byName['200mm autocannon ii']!.displayName),
          findsNWidgets(3));
      expect(find.text('200mm AutoCannon II'), findsNothing);
      final summary = find.byKey(const ValueKey('fitting-summary'));
      final summaryTop = tester.getTopLeft(summary);
      await tester.drag(find.byKey(const ValueKey('fitting-equipment-scroll')),
          const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(summary), summaryTop);
      await tester.tap(find.byKey(const ValueKey('rack-filter-rig')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fit-slot-rig-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('fit-slot-high-0')), findsNothing);
      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(find.text('计算暂不可用'), findsOneWidget);
      expect(find.text('技能假设'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'compact menus preserve module actions, unsaved guard and English EFT',
      (tester) async {
    final catalogue = _catalogue();
    final store = MemoryFitStore();
    await store.save([_fit(catalogue)]);
    await _show(tester, catalogue, store);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments['text'];
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(
        find.text(catalogue.byName['200mm autocannon ii']!.displayName).first);
    await tester.pumpAndSettle();
    expect(find.text('200mm AutoCannon II'), findsOneWidget);
    expect(find.text('更换模块'), findsOneWidget);
    expect(find.text('更换弹药'), findsOneWidget);
    await tester.tap(find.text('卸下弹药'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('fit-slot-high-0'))).height,
        44);
    await tester.tap(find.byTooltip('新建装配'));
    await tester.pumpAndSettle();
    expect(find.text('保存这份装配？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多装配操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '测试装配');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存到本机'));
    await tester.pumpAndSettle();
    expect((await store.load()).single.name, '测试装配');
    expect((await store.load()).single.at(Slot.high, 0)!.chargeTypeId, isNull);
    await tester.tap(find.byTooltip('更多装配操作'));
    await tester.pumpAndSettle();
    expect(find.text('导入 EFT'), findsOneWidget);
    expect(find.text('删除装配'), findsOneWidget);
    await tester.tap(find.text('复制 EFT'));
    await tester.pumpAndSettle();
    expect(copied, startsWith('[Rifter, 测试装配]'));
    expect(copied, contains('200mm AutoCannon II'));
    expect(copied,
        isNot(contains(catalogue.byName['200mm autocannon ii']!.displayName)));
    expect(tester.takeException(), isNull);
  });
}
