import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eve_local_station/services/engine_pack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('els-pack-test-');
    root = Directory('${temporary.path}/engine-packs');
  });
  tearDown(() async => temporary.delete(recursive: true));

  test(
    'verified extraction is reused only after full native revalidation',
    () async {
      final bundle = _Bundle();
      final installer = bundle.installer(root);
      final installed = await installer.install();
      expect(bundle.loaded.length, 6);
      expect(bundle.validated.single, contains('.staging-'));
      expect(installed.directory.path, contains('/pack-'));
      final again = await installer.install();
      expect(again.directory.path, installed.directory.path);
      expect(
        bundle.loaded.length,
        7,
        reason:
            'A verified cache reload reads only the immutable bundled manifest',
      );
      expect(bundle.validated.last, installed.directory.path);
      expect(
        root.listSync().where((entry) => entry.path.contains('.staging-')),
        isEmpty,
      );
    },
  );

  test(
    'modified cached PB2 bytes are detected and repaired from bundled data',
    () async {
      final bundle = _Bundle();
      final first = await bundle.installer(root).install();
      await File(
        '${first.directory.path}/types.pb2',
      ).writeAsString('corrupted bytes');
      final recovered = await bundle.installer(root).install();
      expect(
        await File('${recovered.directory.path}/types.pb2').readAsString(),
        'genuine-test-payload:types.pb2:1',
      );
      expect(bundle.loaded.length, 12);
      expect(bundle.validated.length, 3);
    },
  );

  test(
    'failed update preserves previous verified pack and never promotes partial files',
    () async {
      final previousBundle = _Bundle();
      final previous = await previousBundle.installer(root).install();
      final update = _Bundle(version: 2)..missing = 'dogmaEffects.pb2';
      await expectLater(
        update.installer(root).install(),
        throwsA(
          isA<EnginePackException>().having(
            (error) => error.code,
            'code',
            'ENGINE_ASSET_MISSING',
          ),
        ),
      );
      expect(await previous.directory.exists(), isTrue);
      expect(
        root.listSync().where((entry) => entry.path.contains('.staging-')),
        isEmpty,
      );
      update.missing = null;
      final repaired = await update.installer(root).install();
      expect(repaired.directory.path, isNot(previous.directory.path));
      expect(
        await previous.directory.exists(),
        isFalse,
        reason: 'Old caches are pruned only after the replacement validates',
      );
    },
  );

  test(
    'failed checksum validation cannot replace an earlier valid pack',
    () async {
      final previous = await _Bundle().installer(root).install();
      final update = _Bundle(version: 2)..rejectValidation = true;
      await expectLater(
        update.installer(root).install(),
        throwsA(isA<EnginePackException>()),
      );
      expect(await previous.directory.exists(), isTrue);
      expect(root.listSync().whereType<Directory>().length, 1);
    },
  );

  test(
    'interrupted staging directories are recovered without touching saved fittings',
    () async {
      final stage = Directory('${root.path}/.staging-interrupted');
      await stage.create(recursive: true);
      await File('${stage.path}/types.pb2').writeAsString('half a file');
      final fitFile = File('${temporary.path}/fits-v1.json');
      await fitFile.writeAsString('user data');
      await _Bundle().installer(root).install();
      expect(await stage.exists(), isFalse);
      expect(await fitFile.readAsString(), 'user data');
    },
  );

  test('concurrent first launches share one atomic installation', () async {
    final bundle = _Bundle();
    final results = await Future.wait([
      bundle.installer(root).install(),
      bundle.installer(root).install(),
    ]);
    expect(results[0].directory.path, results[1].directory.path);
    expect(bundle.loaded.length, 6);
    expect(bundle.validated.length, 1);
  });

  test(
    'malformed/extra manifest filenames fail before any extraction',
    () async {
      final bundle = _Bundle()..extraFile = '../outside.pb2';
      await expectLater(
        bundle.installer(root).install(),
        throwsA(
          isA<EnginePackException>().having(
            (error) => error.code,
            'code',
            'ENGINE_MANIFEST_INVALID',
          ),
        ),
      );
      expect(await root.exists(), isFalse);
      expect(await File('${temporary.path}/outside.pb2').exists(), isFalse);
    },
  );
}

// Installer tests exercise the trust boundary, publication and crash recovery.
// The injected validator stands in for native SHA-256 validation (covered by
// Cargo and the separate real-DLL integration test), never a production bypass.
class _Bundle {
  _Bundle({this.version = 1});
  final int version;
  final List<String> loaded = [];
  final List<String> validated = [];
  String? missing;
  String? extraFile;
  bool rejectValidation = false;

  EnginePackInstaller installer(Directory root) => EnginePackInstaller(
        root: root,
        loadAsset: load,
        validateDataset: validate,
      );

  Future<ByteData> load(String asset) async {
    final name = asset.substring(EnginePackInstaller.assetPrefix.length);
    loaded.add(name);
    if (name == missing) throw StateError('Test interrupted bundle');
    final content = name == EnginePackInstaller.manifestName
        ? jsonEncode({
            'schema_version': 1,
            'server': 'tranquility',
            'upstream_revision': List.filled(40, 'a').join(),
            'patch_ids_sha256': List.filled(64, 'b').join(),
            'files': {
              for (final name in EnginePackInstaller.dataFiles)
                name: List.filled(64, '$version').join(),
              if (extraFile != null) extraFile!: List.filled(64, 'c').join(),
            },
          })
        : 'genuine-test-payload:$name:$version';
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  }

  Future<void> validate(String directory) async {
    validated.add(directory);
    if (rejectValidation) {
      throw const EnginePackException(
        'ENGINE_PACK_INVALID',
        'Rejected test checksum',
      );
    }
    for (final name in EnginePackInstaller.dataFiles) {
      if (await File('$directory/$name').readAsString() !=
          'genuine-test-payload:$name:$version') {
        throw const EnginePackException(
          'ENGINE_PACK_INVALID',
          'Rejected test checksum',
        );
      }
    }
  }
}
