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

class _CountingEngine implements FittingEngine {
  int calls = 0;
  @override
  Future<Calculation> calculate(Fit fit) async {
    calls++;
    return const Calculation(error: 'Test-only unavailable engine');
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, Catalogue catalogue,
    MemoryFitStore store, FittingEngine engine,
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
      engine: engine));
  await _settle(tester);
}

void main() {
  final catalogue =
      Catalogue.decode(File('assets/data/catalogue.json').readAsStringSync());

  testWidgets(
      'Vexor copy and fill are one batch each and save/export all copies',
      (tester) async {
    final ship = catalogue.byName['vexor']!;
    final module = catalogue.byName['drone link augmentor i']!;
    final fit = Fit.newShip(ship)
      ..modules.add(FittedModule(
          typeId: module.id,
          slot: Slot.high,
          index: 0,
          state: defaultModuleState(module)));
    final store = MemoryFitStore();
    final engine = _CountingEngine();
    await store.save([fit]);
    await _show(tester, catalogue, store, engine, scale: 1.3);
    expect(engine.calls, 1);
    await tester.tap(find.text(module.displayName).first);
    await tester.pumpAndSettle();
    expect(find.text('复制一个'), findsOneWidget);
    expect(find.text('填满剩余同类槽位'), findsOneWidget);
    expect(tester.getSize(find.widgetWithText(ListTile, '复制一个')).height,
        greaterThanOrEqualTo(44));
    await tester.tap(find.text('复制一个'));
    await _settle(tester);
    expect(find.text(module.displayName), findsNWidgets(2));
    expect(engine.calls, 2);
    expect(find.textContaining('未保存 · '), findsOneWidget);
    await tester.tap(find.text(module.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('填满剩余同类槽位'));
    await _settle(tester);
    expect(find.text(module.displayName), findsNWidgets(4));
    expect(engine.calls, 3,
        reason: 'A fill batch must schedule one native recalculation.');
    await tester.tap(find.byTooltip('保存到本机'));
    await tester.pumpAndSettle();
    final saved = (await store.load()).single;
    expect(saved.id, fit.id);
    expect(saved.modules.map((module) => module.index), [0, 1, 2, 3]);
    expect(saved.modules.every((copy) => copy.typeId == module.id), isTrue);
    String? clipboard;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = call.arguments['text'];
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.byTooltip('更多装配操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制 EFT'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('[Vexor,'));
    expect('Drone Link Augmentor I'.allMatches(clipboard!).length, 4);
    await tester.tap(find.text(module.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制一个'));
    await _settle(tester);
    expect(find.textContaining('已满，没有可复制的空槽'), findsOneWidget);
    expect(engine.calls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'loaded copies stay independent when the original ammunition changes',
      (tester) async {
    final gun = catalogue.byName['200mm autocannon ii']!;
    final ammo = catalogue.byName['emp s']!;
    final fit = Fit.newShip(catalogue.byName['rifter']!)
      ..modules.add(FittedModule(
          typeId: gun.id,
          slot: Slot.high,
          index: 0,
          state: ModuleState.overloaded,
          chargeTypeId: ammo.id));
    final store = MemoryFitStore();
    await store.save([fit]);
    await _show(tester, catalogue, store, _CountingEngine());
    await tester.tap(find.text(gun.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制一个'));
    await _settle(tester);
    expect(find.text(ammo.displayName), findsNWidgets(2));
    await tester.tap(find.text(gun.displayName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('卸下弹药'));
    await _settle(tester);
    await tester.tap(find.byTooltip('保存到本机'));
    await tester.pumpAndSettle();
    final saved = (await store.load()).single;
    expect(saved.at(Slot.high, 0)!.chargeTypeId, isNull);
    expect(saved.at(Slot.high, 1)!.chargeTypeId, ammo.id);
    expect(saved.at(Slot.high, 1)!.state, ModuleState.overloaded);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'invalid source state explains refusal without changing or recalculating',
      (tester) async {
    final gyro = catalogue.byName['gyrostabilizer ii']!;
    final fit = Fit.newShip(catalogue.byName['rifter']!)
      ..modules.add(FittedModule(
          typeId: gyro.id,
          slot: Slot.low,
          index: 0,
          state: ModuleState.overloaded));
    final store = MemoryFitStore();
    final engine = _CountingEngine();
    await store.save([fit]);
    await _show(tester, catalogue, store, engine);
    await tester.ensureVisible(find.text(gyro.displayName));
    await tester.tap(find.text(gyro.displayName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('填满剩余同类槽位'));
    await _settle(tester);
    expect(find.textContaining('原模块不支持当前过载状态'), findsOneWidget);
    expect(engine.calls, 1);
    expect((await store.load()).single.modules.length, 1);
    expect(tester.takeException(), isNull);
  });
}
