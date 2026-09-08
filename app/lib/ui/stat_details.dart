import 'package:flutter/material.dart';

import '../services/engine.dart';
import 'theme.dart';

class StatField {
  const StatField(this.key, this.label, this.unit,
      {this.scale = 1, this.decimals = 1});
  final String key;
  final String label;
  final String unit;
  final double scale;
  final int decimals;
  String format(num value) =>
      '${(value * scale).toStringAsFixed(decimals)}${unit.isEmpty ? '' : ' $unit'}';
}

class CalculationDetails extends StatelessWidget {
  const CalculationDetails({required this.calculation, super.key});
  final Calculation calculation;

  @override
  Widget build(BuildContext context) {
    final stats = calculation.stats;
    return Column(children: [
      if (stats.containsKey('capacitor_capacity'))
        _section('电容', Icons.battery_charging_full, [
          if (stats.containsKey('capacitor_stable') ||
              stats.containsKey('capacitor_duration') ||
              stats.containsKey('capacitor_simulation_limit'))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(capacitorStatus(stats),
                      style: TextStyle(
                          color: stats['capacitor_stable'] == 1
                              ? StationColors.cyan
                              : StationColors.amber,
                          fontSize: 12))),
            ),
          ..._fields(stats, const [
            StatField('capacitor_capacity', '容量', 'GJ'),
            StatField('capacitor_recharge_time', '自然回充时间', 's'),
            StatField('capacitor_peak_recharge', '峰值回充', 'GJ/s', decimals: 2),
            StatField('capacitor_peak_drain', '峰值消耗', 'GJ/s', decimals: 2),
            StatField('capacitor_peak_delta', '峰值收支', 'GJ/s', decimals: 2),
          ]),
        ]),
      if (stats.containsKey('shield_hp') || stats.containsKey('armor_hp'))
        _section('防御与抗性', Icons.shield_outlined, [
          ..._fields(stats, const [
            StatField('shield_hp', '护盾', 'HP'),
            StatField('armor_hp', '装甲', 'HP'),
            StatField('hull_hp', '结构', 'HP')
          ]),
          const SizedBox(height: 8),
          _resistances(stats),
          const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('EHP 按电磁、热能、动能、爆炸伤害各 25% 计算。',
                  style: TextStyle(fontSize: 11, color: StationColors.muted))),
        ]),
      _section(
          '航行、锁定与货舱',
          Icons.navigation_outlined,
          _fields(stats, const [
            StatField('speed', '最大速度', 'm/s'),
            StatField('align_time', '起跳时间', 's', decimals: 2),
            StatField('warp_speed', '跃迁速度', 'AU/s', decimals: 2),
            StatField('target_range', '锁定距离', 'km', scale: 0.001),
            StatField('scan_resolution', '扫描分辨率', 'mm'),
            StatField('max_targets', '最大锁定数', '', decimals: 0),
            StatField('signature_radius', '信号半径', 'm'),
            StatField('cargo_capacity', '货舱容量', 'm³'),
          ])),
      _section(
          '无人机',
          Icons.grain,
          _fields(stats, const [
            StatField('active_drones', '启用数量', '', decimals: 0),
            StatField('drone_dps', '无人机 DPS', '', decimals: 1),
            StatField('drone_bandwidth_used', '带宽使用量', 'Mbit/s'),
            StatField('drone_bandwidth', '带宽上限', 'Mbit/s'),
            StatField('drone_bay_used', '舱容使用量', 'm³'),
            StatField('drone_bay_capacity', '无人机舱容量', 'm³'),
          ])),
    ]);
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      leading: Icon(icon, size: 17, color: StationColors.cyan),
      title: Text(title, style: const TextStyle(fontSize: 12)),
      children: children,
    );
  }

  Widget _resistances(Map<String, num> stats) => Table(
        columnWidths: const {0: FixedColumnWidth(42)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            for (final label in ['', '电磁', '热能', '动能', '爆炸'])
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10, color: StationColors.muted)))
          ]),
          for (final layer
              in const {'shield': '护盾', 'armor': '装甲', 'hull': '结构'}.entries)
            TableRow(children: [
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child:
                      Text(layer.value, style: const TextStyle(fontSize: 10))),
              for (final type in ['em', 'thermal', 'kinetic', 'explosive'])
                Center(
                    child: Text(
                        stats['${layer.key}_resist_$type'] == null
                            ? '—'
                            : '${(stats['${layer.key}_resist_$type']! * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontSize: 10, color: StationColors.cyan))),
            ]),
        ],
      );
}

List<Widget> _fields(Map<String, num> stats, List<StatField> fields) => [
      for (final field in fields)
        if (stats.containsKey(field.key))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                  child: Text(field.label,
                      style: const TextStyle(
                          fontSize: 11, color: StationColors.muted))),
              Text(field.format(stats[field.key]!),
                  style: const TextStyle(fontSize: 12))
            ]),
          ),
    ];

String capacitorStatus(Map<String, num> stats) {
  if (stats['capacitor_stable'] == 1) return '电容稳定';
  final duration = stats['capacitor_duration'];
  if (duration != null) {
    final seconds = duration.ceil();
    return '预计持续 ${seconds ~/ 60} 分 ${seconds % 60} 秒';
  }
  if (stats['capacitor_simulation_limit'] == 1) return '24 小时模拟内未耗尽，未判定为稳定';
  return '电容不稳定，暂无持续时间';
}

Future<void> showModuleStatistics(
        BuildContext context, String name, ModuleCalculation module,
        {String? canonicalName}) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: const TextStyle(fontSize: 16)),
              if (canonicalName != null && canonicalName != name)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(canonicalName,
                      style: const TextStyle(
                          fontSize: 11, color: StationColors.muted)),
                ),
              ..._fields(module.stats, const [
                StatField('dps', '理论 DPS', ''),
                StatField('volley', '齐射伤害', 'HP'),
                StatField('cycle_time', '周期', 's', decimals: 2),
                StatField('optimal_range', '最佳射程', 'km',
                    scale: 0.001, decimals: 2),
                StatField('falloff', '失准距离', 'km', scale: 0.001, decimals: 2),
                StatField('tracking_score', '跟踪评分', '', decimals: 2),
                StatField('charge_flight_time', '弹药飞行时间', 's', decimals: 2),
                StatField('charge_velocity', '弹药飞行速度', 'm/s'),
              ]),
              const SizedBox(height: 12),
              const Text('数据按当前技能、装配与模块状态计算。跟踪评分使用游戏数值，并非弧度/秒。',
                  style: TextStyle(fontSize: 10, color: StationColors.muted)),
            ]),
      )),
    );
