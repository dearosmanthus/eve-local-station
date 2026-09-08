import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import '../domain/fit.dart';
import '../domain/catalogue.dart';
import 'engine_pack.dart';

typedef _CallNative = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _CallDart = Pointer<Uint8> Function(Pointer<Uint8>);
typedef _FreeNative = Void Function(Pointer<Uint8>);
typedef _FreeDart = void Function(Pointer<Uint8>);
typedef _AllocNative = Pointer<Uint8> Function(IntPtr);
typedef _AllocDart = Pointer<Uint8> Function(int);
typedef _DeallocNative = Void Function(Pointer<Uint8>, IntPtr);
typedef _DeallocDart = void Function(Pointer<Uint8>, int);

class Calculation {
  const Calculation({
    this.stats = const {},
    this.error,
    this.code,
    this.diagnostics = const [],
    this.moduleStats = const [],
  });
  final Map<String, num> stats;
  final String? error;
  final String? code;
  final List<String> diagnostics;
  final List<ModuleCalculation> moduleStats;
  bool get available => error == null;

  ModuleCalculation? moduleFor(Slot slot, int index) {
    for (final module in moduleStats) {
      if (module.slot == slot && module.index == index) return module;
    }
    return null;
  }
}

class ModuleCalculation {
  const ModuleCalculation(this.typeId, this.slot, this.index, this.stats);
  final int typeId;
  final Slot? slot;
  final int index;
  final Map<String, num> stats;
}

abstract interface class FittingEngine {
  Future<Calculation> calculate(Fit fit);
}

class NativeFittingEngine implements FittingEngine {
  NativeFittingEngine(this.dataPath, {this.libraryPath});
  final String dataPath;
  final String? libraryPath;

  @override
  Future<Calculation> calculate(Fit fit) async {
    final request = buildEngineRequest(fit, dataPath);
    final override = libraryPath;
    try {
      // Open the library and execute Rust on a worker isolate so loading the
      // local Dogma dataset cannot block map gestures or fitting interaction.
      final response = await Isolate.run(
        () => _nativeCall(jsonEncode(request), libraryPath: override),
      );
      return decodeCalculation(response);
    } catch (error) {
      return Calculation(code: 'NATIVE_LIBRARY_UNAVAILABLE', error: '$error');
    }
  }
}

Future<void> validateNativeEngineDataset(
  String directory, {
  String? libraryPath,
}) async {
  Map<String, dynamic> json;
  try {
    final response = await Isolate.run(
      () => _nativeCall(
        jsonEncode({'op': 'health', 'data_path': directory}),
        libraryPath: libraryPath,
      ),
    );
    json = jsonDecode(response) as Map<String, dynamic>;
  } catch (error) {
    throw EnginePackException(
      'NATIVE_LIBRARY_UNAVAILABLE',
      '此设备无法启动本地装配引擎。',
      '$error',
    );
  }
  final result = json['result'] as Map<String, dynamic>?;
  if (json['ok'] != true ||
      result?['engine_enabled'] != true ||
      result?['data_status'] != 'ready') {
    final error = result?['data_error'] ?? json['error'];
    throw EnginePackException(
      'ENGINE_PACK_INVALID',
      '本地装配数据校验失败，未启用计算。',
      '$error',
    );
  }
}

/// Kept separate from persistence: the native ABI has its own versioned schema.
Map<String, dynamic> buildEngineRequest(Fit fit, String dataPath) =>
    <String, dynamic>{
      'op': 'calculate',
      'data_path': dataPath,
      'fit': {
        'ship_type_id': fit.shipTypeId,
        'skill_mode': fit.skillMode,
        'modules': fit.modules
            .map(
              (module) => {
                'type_id': module.typeId,
                'slot_type': module.slot.key,
                'index': module.index,
                'state': module.state.name,
                if (module.chargeTypeId != null)
                  'charge_type_id': module.chargeTypeId,
              },
            )
            .toList(),
        'drones': fit.drones
            .map(
              (drone) => {
                'type_id': drone.typeId,
                'quantity': drone.quantity,
                'state': drone.active ? 'active' : 'online',
              },
            )
            .toList(),
      },
    };

Calculation decodeCalculation(String response) {
  final json = jsonDecode(response) as Map<String, dynamic>;
  if (json['ok'] != true) {
    final error = json['error'];
    return Calculation(
      code: error is Map ? error['code']?.toString() : 'ENGINE_ERROR',
      error: error is Map ? error['message']?.toString() ?? '$error' : '$error',
    );
  }
  final result = json['result'] as Map<String, dynamic>? ?? {};
  final stats = result['stats'] as Map<String, dynamic>? ?? {};
  return Calculation(
    stats: {
      for (final entry in stats.entries)
        if (entry.value is num && (entry.value as num).isFinite)
          entry.key: entry.value as num,
    },
    diagnostics: (result['diagnostics'] as List<dynamic>? ?? [])
        .map(formatEngineDiagnostic)
        .where((message) => message.isNotEmpty)
        .toList(),
    moduleStats: (result['module_attributes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((module) {
      final values = module['stats'] as Map<String, dynamic>? ?? {};
      return ModuleCalculation(
          (module['type_id'] as num?)?.toInt() ?? 0,
          Slot.parse(module['slot_type']?.toString().toLowerCase()),
          (module['index'] as num?)?.toInt() ?? 0, {
        for (final entry in values.entries)
          if (entry.value is num && (entry.value as num).isFinite)
            entry.key: entry.value as num
      });
    }).toList(),
  );
}

String formatEngineDiagnostic(Object? value) {
  final raw = value is Map
      ? value['message']?.toString() ?? ''
      : value?.toString() ?? '';
  if (raw.isEmpty) return '';
  const messages = {
    'IncompatibleChargeSize': '弹药尺寸与模块不兼容',
    'IncompatibleChargeCapacity': '弹药超出模块容量',
    'IncompatibleChargeGroup': '弹药组别与模块不兼容',
    'TooMuchTurret': '炮台数量超过舰船挂点',
    'TooMuchLauncher': '发射器数量超过舰船挂点',
    'ConflictItem': '同组模块存在装配冲突或超过数量上限',
    'DuplicateBooster': '同一增效剂位置重复使用',
    'IncompatibleShipGroup': '模块不适用于此舰船类别',
    'IncompatibleShipType': '模块不适用于此舰船',
    'IncompatibleRigSize': '改装件尺寸不适用于此舰船',
    'PowergridExceeded': '能量栅格使用量超过总量',
    'CpuExceeded': 'CPU 使用量超过总量',
    'CalibrationExceeded': '改装件校准值超过上限',
    'DroneBandwidthExceeded': '启用无人机的带宽超过上限',
    'DroneBayExceeded': '无人机体积超过无人机舱容量',
    'TooManyActiveDrones': '启用无人机数量超过当前技能与舰船限制',
    'TooMuchFighterTube': '铁骑舰载机发射管数量超过上限',
    'TooMuchFighterSquadron': '铁骑舰载机中队数量超过上限',
    'StateExceedsMax': '此模块不支持当前激活或过载状态',
    'MissingCharge': '尚未装载弹药',
  };
  String? message;
  for (final entry in messages.entries) {
    if (raw.contains(entry.key)) {
      message = entry.value;
      break;
    }
  }
  message ??= raw.contains('{') ||
          raw.startsWith('Error(') ||
          raw.startsWith('Warning(')
      ? '本地引擎报告一项需要检查的装配限制'
      : raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (value is! Map) return message;
  final slotText = value['slot_type']?.toString().toLowerCase();
  final slot = Slot.parse(slotText);
  final index = value['index'];
  final prefix = slot != null && index is int
      ? '${slot.label} ${index + 1}：'
      : slotText == 'drone'
          ? '无人机：'
          : '';
  return '$prefix$message';
}

String _nativeCall(String request, {String? libraryPath}) {
  final name = Platform.isAndroid || Platform.isLinux
      ? 'libeve_local_core.so'
      : Platform.isWindows
          ? 'eve_local_core.dll'
          : 'libeve_local_core.dylib';
  final library = DynamicLibrary.open(libraryPath ?? name);
  final alloc = library.lookupFunction<_AllocNative, _AllocDart>('els_alloc');
  final dealloc = library.lookupFunction<_DeallocNative, _DeallocDart>(
    'els_dealloc',
  );
  final call = library.lookupFunction<_CallNative, _CallDart>('els_call');
  final free = library.lookupFunction<_FreeNative, _FreeDart>('els_free');
  final bytes = utf8.encode(request);
  final pointer = alloc(bytes.length + 1);
  if (pointer == nullptr) throw StateError('Native request allocation failed');
  Pointer<Uint8> response = nullptr;
  try {
    pointer.asTypedList(bytes.length + 1)
      ..setRange(0, bytes.length, bytes)
      ..[bytes.length] = 0;
    response = call(pointer);
    if (response == nullptr) throw StateError('Native engine returned null');
    var length = 0;
    while (length < 16 * 1024 * 1024 && response[length] != 0) {
      length++;
    }
    if (length == 16 * 1024 * 1024) {
      throw const FormatException('Native response exceeds 16 MiB');
    }
    return utf8.decode(response.asTypedList(length));
  } finally {
    if (response != nullptr) free(response);
    dealloc(pointer, bytes.length + 1);
  }
}

class UnavailableFittingEngine implements FittingEngine {
  const UnavailableFittingEngine({
    this.code = 'ENGINE_UNAVAILABLE',
    this.message = '本地装配计算引擎尚未就绪。',
  });
  final String code;
  final String message;
  @override
  Future<Calculation> calculate(Fit fit) async =>
      Calculation(code: code, error: message);
}
