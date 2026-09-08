import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/fit.dart';

abstract interface class FitStore {
  Future<List<Fit>> load();
  Future<void> save(List<Fit> fits);
}

class LocalFitStore implements FitStore {
  LocalFitStore(this.directory);
  final Directory directory;
  File get _file => File('${directory.path}/fits-v1.json');

  static Future<Directory> appDirectory() async {
    const channel = MethodChannel('eve_local_station/local_storage');
    if (Platform.isAndroid || Platform.isIOS) {
      final path = await channel.invokeMethod<String>('documentsPath');
      if (path == null || path.isEmpty) {
        throw StateError('App-private storage path unavailable');
      }
      return Directory(path)..createSync(recursive: true);
    }
    final base = Platform.isWindows
        ? Platform.environment['LOCALAPPDATA']
        : Platform.environment['XDG_DATA_HOME'] ??
            '${Platform.environment['HOME']}/.local/share';
    if (base == null || base.isEmpty) {
      throw StateError('Local storage path unavailable');
    }
    return Directory('$base/EveLocalStation')..createSync(recursive: true);
  }

  @override
  Future<List<Fit>> load() async {
    if (!await _file.exists()) return [];
    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported local fitting format');
    }
    return (json['fits'] as List<dynamic>)
        .map((entry) => Fit.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> save(List<Fit> fits) async {
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'fits': fits.map((fit) => fit.toJson()).toList(),
      }),
      flush: true,
    );
    // A sibling temporary file keeps Android rename on the same filesystem.
    await temporary.rename(_file.path);
  }
}

class MemoryFitStore implements FitStore {
  List<Fit> _fits = [];
  @override
  Future<List<Fit>> load() async => _fits.map((fit) => fit.copy()).toList();
  @override
  Future<void> save(List<Fit> fits) async {
    _fits = fits.map((fit) => fit.copy()).toList();
  }
}
