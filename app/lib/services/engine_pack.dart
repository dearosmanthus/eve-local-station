import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef EngineAssetLoader = Future<ByteData> Function(String path);
typedef EngineDatasetValidator = Future<void> Function(String directory);
typedef EngineInstallProgress = void Function(String message);

/// Native validation checks every SHA-256 as well as engine/patch compatibility.
/// The installer never treats a directory or completion marker alone as valid.
class EnginePackException implements Exception {
  const EnginePackException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final String? details;

  @override
  String toString() => '$message${details == null ? '' : '\n$details'}';
}

class InstalledEnginePack {
  const InstalledEnginePack(this.directory, this.manifest);
  final Directory directory;
  final Map<String, dynamic> manifest;
}

class EnginePackInstaller {
  EnginePackInstaller({
    required this.root,
    required this.loadAsset,
    required this.validateDataset,
    this.onProgress,
  });

  final Directory root;
  final EngineAssetLoader loadAsset;
  final EngineDatasetValidator validateDataset;
  final EngineInstallProgress? onProgress;

  static const assetPrefix = 'assets/engine/';
  static const manifestName = 'engine-manifest.json';
  static const dataFiles = [
    'types.pb2',
    'dogmaAttributes.pb2',
    'dogmaEffects.pb2',
    'typeDogma.pb2',
    'dbuffcollections.pb2',
  ];
  static final Map<String, Future<InstalledEnginePack>> _inFlight = {};

  Future<InstalledEnginePack> install() {
    final key = _pathKey(root.path);
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final pending = _install().whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = pending;
    return pending;
  }

  Future<InstalledEnginePack> _install() async {
    onProgress?.call('正在检查本地装配数据…');
    final manifestBytes = await _asset(manifestName);
    final manifest = _parseManifest(manifestBytes);
    // Prefixes keep Android/Windows paths short. Reuse additionally requires
    // byte-identical full manifests, followed by all complete SHA-256 checks.
    final hashes = manifest['files'] as Map<String, dynamic>;
    final version =
        '${(manifest['upstream_revision'] as String).substring(0, 12)}-'
        '${dataFiles.map((name) => (hashes[name] as String).substring(0, 12)).join('-')}';
    final installed = Directory('${root.path}/pack-$version');
    await root.create(recursive: true);
    final lock = await File(
      '${root.path}/.install.lock',
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      await _removeIncomplete();
      if (await _matches(installed, manifestBytes)) {
        try {
          await validateDataset(installed.path);
          await _pruneOldPacks(installed);
          return InstalledEnginePack(installed, manifest);
        } catch (_) {
          // A corrupted cache is reconstructed from the immutable APK assets.
          onProgress?.call('正在修复本地装配数据…');
        }
      }
      final nonce = '$pid-${DateTime.now().microsecondsSinceEpoch}';
      final staging = Directory('${root.path}/.staging-$nonce');
      final previous = Directory('${root.path}/.replaced-$nonce');
      await staging.create();
      var movedPrevious = false;
      var promoted = false;
      try {
        for (var index = 0; index < dataFiles.length; index++) {
          final name = dataFiles[index];
          onProgress?.call('正在准备本地装配数据 ${index + 1}/${dataFiles.length}…');
          final bytes = await _asset(name);
          if (bytes.isEmpty) {
            throw EnginePackException(
              'ENGINE_ASSET_INVALID',
              '安装包中的装配数据不完整。',
              name,
            );
          }
          await File('${staging.path}/$name').writeAsBytes(bytes, flush: true);
        }
        await File(
          '${staging.path}/$manifestName',
        ).writeAsBytes(manifestBytes, flush: true);
        onProgress?.call('正在验证本地装配数据…');
        await validateDataset(staging.path);
        final existingType = await FileSystemEntity.type(
          installed.path,
          followLinks: false,
        );
        if (existingType != FileSystemEntityType.notFound) {
          if (existingType != FileSystemEntityType.directory) {
            throw const EnginePackException(
              'ENGINE_CACHE_INVALID',
              '本地装配数据目录需要修复。',
            );
          }
          await installed.rename(previous.path);
          movedPrevious = true;
        }
        await staging.rename(installed.path);
        promoted = true;
        if (movedPrevious) await _removeManaged(previous.path);
        await _pruneOldPacks(installed);
        return InstalledEnginePack(installed, manifest);
      } catch (_) {
        if (!promoted && movedPrevious && !await installed.exists()) {
          await previous.rename(installed.path);
        }
        rethrow;
      } finally {
        if (!promoted && await staging.exists()) {
          await _removeManaged(staging.path);
        }
      }
    } finally {
      await lock.close();
    }
  }

  Future<Uint8List> _asset(String name) async {
    try {
      final data = await loadAsset('$assetPrefix$name');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (error) {
      throw EnginePackException(
        'ENGINE_ASSET_MISSING',
        '安装包缺少完整的本地装配数据，请安装完整版本。',
        '$name: $error',
      );
    }
  }

  Map<String, dynamic> _parseManifest(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final files = json['files'] as Map<String, dynamic>;
      bool hex(Object? value, int length) =>
          value is String && RegExp('^[a-f0-9]{$length}\$').hasMatch(value);
      if (json['schema_version'] != 1 ||
          json['server'] != 'tranquility' ||
          !hex(json['upstream_revision'], 40) ||
          !hex(json['patch_ids_sha256'], 64) ||
          files.length != dataFiles.length ||
          !dataFiles.every((name) => hex(files[name], 64))) {
        throw const FormatException('Unsupported engine manifest');
      }
      return json;
    } catch (error) {
      throw EnginePackException(
        'ENGINE_MANIFEST_INVALID',
        '安装包中的装配数据清单无效。',
        '$error',
      );
    }
  }

  Future<bool> _matches(Directory directory, Uint8List bytes) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    try {
      final cached = await File(
        '${directory.path}/$manifestName',
      ).readAsBytes();
      if (cached.length != bytes.length) return false;
      for (var index = 0; index < bytes.length; index++) {
        if (cached[index] != bytes[index]) return false;
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _removeIncomplete() async {
    await for (final child in root.list(followLinks: false)) {
      final name = child.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (name.startsWith('.staging-') || name.startsWith('.replaced-')) {
        await _removeManaged(child.path);
      }
    }
  }

  Future<void> _pruneOldPacks(Directory current) async {
    await for (final child in root.list(followLinks: false)) {
      final name = child.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (name.startsWith('pack-') &&
          _pathKey(child.path) != _pathKey(current.path)) {
        await _removeManaged(child.path);
      }
    }
  }

  Future<void> _removeManaged(String path) async {
    final child = File(path);
    // Only direct, installer-owned children of this private cache are removed.
    // Never follow a link or accept a manifest-controlled filename.
    if (_pathKey(child.parent.path) != _pathKey(root.path)) {
      throw StateError('Refusing to remove a path outside the engine cache');
    }
    final kind = await FileSystemEntity.type(path, followLinks: false);
    if (kind == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (kind == FileSystemEntityType.link) {
      await Link(path).delete();
    } else if (kind == FileSystemEntityType.file) {
      await File(path).delete();
    }
  }

  String _pathKey(String path) {
    final normalized = File(path).absolute.uri.normalizePath().toFilePath();
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
