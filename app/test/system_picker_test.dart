import 'package:eve_local_station/domain/universe.dart';
import 'package:eve_local_station/ui/system_picker.dart';
import 'package:eve_local_station/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic navigation fixtures; no gameplay accuracy claims.
SolarSystem _system(int id, String name, String chinese,
        {String constellation = '', String constellationZh = ''}) =>
    SolarSystem(
      id: id,
      name: name,
      nameZh: chinese,
      regionId: 10,
      regionName: 'The Forge',
      regionNameZh: '伏尔戈',
      constellationName: constellation,
      constellationNameZh: constellationZh,
      security: 0.8,
      x: 0,
      y: 0,
      z: 0,
    );

Universe _universe() => Universe([
      _system(100, 'A Jita Annex', 'AAA 吉他支线'),
      _system(30000142, 'Jita', '吉他',
          constellation: 'Kimotoro', constellationZh: '木本呂'),
      _system(200, 'Amarr', '艾玛'),
      for (var id = 4; id <= 8; id++) _system(id, 'Synthetic $id', '测试星$id'),
    ], const []);

Widget _host(Widget child, {double keyboard = 0}) => MaterialApp(
      theme: stationTheme(),
      home: MediaQuery(
        data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: Scaffold(resizeToAvoidBottomInset: false, body: child),
      ),
    );

void main() {
  testWidgets(
      'Chinese and English exact hits lead; constellation and ID searches work',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(_host(SystemPicker(title: '选择星系', universe: _universe())));
    final search = find.byKey(const ValueKey('system-picker-search'));
    for (final query in ['吉他', 'JITA']) {
      await tester.enterText(search, query);
      await tester.pump();
      expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('system-option-30000142')))
              .dy,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('system-option-100')))
              .dy));
    }
    for (final query in ['木本呂', 'Kimotoro', '30000142', '伏尔戈 Kimotoro']) {
      await tester.enterText(search, query);
      await tester.pump();
      expect(
          find.byKey(const ValueKey('system-option-30000142')), findsOneWidget);
      expect(find.byKey(const ValueKey('system-option-100')), findsNothing);
      expect(find.text('伏尔戈 · 木本呂'), findsOneWidget);
    }
    expect(tester.getSize(find.byKey(const ValueKey('system-picker-close'))),
        const Size(44, 44));
    expect(tester.getSize(find.byKey(const ValueKey('system-picker-clear'))),
        const Size(44, 44));
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(find.byKey(const ValueKey('system-option-100')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recent systems are unique, capped, one row, and return the selected object',
      (tester) async {
    final universe = _universe();
    SolarSystem? selected;
    await tester.pumpWidget(MaterialApp(
      theme: stationTheme(),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () async {
                      selected = await showModalBottomSheet<SolarSystem>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SizedBox(
                            height: 540,
                            child: SystemPicker(
                              title: '选择终点',
                              universe: universe,
                              recentIds: const [
                                30000142,
                                999,
                                30000142,
                                200,
                                4,
                                5,
                                6,
                                7,
                                8
                              ],
                            )),
                      );
                    },
                    child: const Text('打开'),
                  ))),
    ));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    final recent = find.byKey(const ValueKey('system-picker-recent'));
    expect(tester.getSize(recent).height, 52);
    final horizontal = tester.widget<ListView>(
        find.descendant(of: recent, matching: find.byType(ListView)));
    expect(horizontal.scrollDirection, Axis.horizontal);
    expect(horizontal.childrenDelegate.estimatedChildCount,
        11); // six items, five separators
    final first = find.byKey(const ValueKey('recent-system-30000142'));
    expect(tester.getSize(first).height, greaterThanOrEqualTo(44));
    expect(find.byKey(const ValueKey('recent-system-999')), findsNothing);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(selected, same(universe.byId[30000142]));
  });

  testWidgets(
      'rebuilds and query changes reuse aliases; replacement universe refreshes index',
      (tester) async {
    final counter = _ReadCounter();
    final systems = [
      _CountingSystem(1, counter),
      _CountingSystem(2, counter),
      _CountingSystem(3, counter),
    ];
    final universe = Universe(systems, const []);
    await tester
        .pumpWidget(_host(SystemPicker(title: '选择星系', universe: universe)));
    expect(counter.aliasReads, 3);
    await tester.enterText(find.byType(TextField), 'Fixture 2');
    await tester.pump();
    expect(counter.aliasReads, 3);
    await tester.pumpWidget(_host(
        SystemPicker(title: '选择新的终点', universe: universe, recentIds: const [2]),
        keyboard: 240));
    await tester.pump();
    expect(counter.aliasReads, 3);
    final padding = tester.widget<Padding>(
        find.byKey(const ValueKey('system-picker-keyboard-padding')));
    expect((padding.padding as EdgeInsets).bottom, 240);
    expect(find.byKey(const ValueKey('system-option-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('system-option-1')), findsNothing);
    expect(find.byKey(const ValueKey('system-picker-recent')), findsNothing);
    await tester.pumpWidget(_host(
        SystemPicker(title: '替换数据', universe: Universe(systems, const []))));
    expect(counter.aliasReads, 6);
    expect(find.byKey(const ValueKey('system-option-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ReadCounter {
  int aliasReads = 0;
}

class _CountingSystem extends SolarSystem {
  _CountingSystem(int number, this.counter)
      : super(
            id: number,
            name: 'Fixture $number',
            regionId: 1,
            regionName: 'Fixture region',
            security: 0,
            x: 0,
            y: 0,
            z: 0);

  final _ReadCounter counter;

  @override
  List<String> get searchAliases {
    counter.aliasReads++;
    return super.searchAliases;
  }
}
