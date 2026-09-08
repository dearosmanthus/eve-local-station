import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/ui/stat_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native warnings become actionable labels without serialised maps', () {
    expect(
        formatEngineDiagnostic({
          'severity': 'error',
          'slot_type': 'High',
          'index': 1,
          'message': 'Error(IncompatibleChargeSize { expected: 1, actual: 2 })'
        }),
        '高槽 2：弹药尺寸与模块不兼容');
    expect(
        formatEngineDiagnostic({
          'slot_type': 'Ship',
          'index': 0,
          'message': 'Error(CpuExceeded { expected: 200.0, actual: 250.0 })'
        }),
        'CPU 使用量超过总量');
    expect(
        formatEngineDiagnostic({
          'slot_type': 'Drone',
          'message':
              'Error(DroneBandwidthExceeded { expected: 25, actual: 50 })'
        }),
        '无人机：启用无人机的带宽超过上限');
    final unknown = formatEngineDiagnostic(
        {'message': 'Error(FutureConstraint { fields: 2 })'});
    expect(unknown, isNot(contains('{')));
    expect(unknown, contains('需要检查'));
  });

  test('stat units and capacitor duration preserve source semantics', () {
    expect(const StatField('range', '射程', 'km', scale: .001).format(12500),
        '12.5 km');
    expect(const StatField('resist', '抗性', '%', scale: 100).format(.325),
        '32.5 %');
    expect(capacitorStatus({'capacitor_stable': 1}), '电容稳定');
    expect(capacitorStatus({'capacitor_stable': 0, 'capacitor_duration': 108}),
        '预计持续 1 分 48 秒');
    expect(
        capacitorStatus({'capacitor_simulation_limit': 1}), contains('未判定为稳定'));
  });

  testWidgets('capacitor simulation limit is visible without a stable field',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: CalculationDetails(
                calculation: Calculation(stats: {
      'capacitor_capacity': 312.5,
      'capacitor_simulation_limit': 1,
    })))));
    await tester.tap(find.text('电容'));
    await tester.pumpAndSettle();
    expect(find.text('24 小时模拟内未耗尽，未判定为稳定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'module results bind to their native slot and index without inventing missing stats',
      () {
    final result = decodeCalculation(
        '{"ok":true,"result":{"stats":{"dps":0},"module_attributes":[{"type_id":2889,"slot_type":"High","index":2,"stats":{"optimal_range":1500,"tracking_score":316.8}}]}}');
    final module = result.moduleFor(Slot.high, 2)!;
    expect(module.typeId, 2889);
    expect(module.stats['optimal_range'], 1500);
    expect(module.stats.containsKey('volley'), isFalse);
    expect(result.moduleFor(Slot.high, 1), isNull);
    expect(result.stats['dps'], 0);
  });
}
