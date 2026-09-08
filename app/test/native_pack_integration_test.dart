import 'dart:io';
import 'dart:typed_data';

import 'package:eve_local_station/domain/catalogue.dart';
import 'package:eve_local_station/domain/fit.dart';
import 'package:eve_local_station/domain/eft.dart';
import 'package:eve_local_station/services/engine.dart';
import 'package:eve_local_station/services/engine_pack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final library = Platform.environment['ELS_NATIVE_LIBRARY'];
  test(
    'actual bundled PB2 installs through the real FFI SHA verifier and calculates a ship',
    () async {
      final temporary = await Directory.systemTemp.createTemp('els-real-pack-');
      try {
        final installer = EnginePackInstaller(
          root: Directory('${temporary.path}/engine-packs'),
          loadAsset: (asset) async =>
              ByteData.sublistView(await File(asset).readAsBytes()),
          validateDataset: (directory) =>
              validateNativeEngineDataset(directory, libraryPath: library),
        );
        final pack = await installer.install();
        final catalogue = Catalogue.decode(
          await File('assets/data/catalogue.json').readAsString(),
        );
        final ship = catalogue.byName['rifter']!;
        final result = await NativeFittingEngine(
          pack.directory.path,
          libraryPath: library,
        ).calculate(Fit.newShip(ship));
        expect(
          result.available,
          isTrue,
          reason: '${result.code}: ${result.error}',
        );
        expect(result.stats['cpu_output'], greaterThan(0));
        expect(result.stats['powergrid_output'], greaterThan(0));
        final passiveFit = importEft(
                '[Rifter, Native state check]\nGyrostabilizer II\n\n200mm AutoCannon II, EMP S\n\nSmall Projectile Burst Aerator I',
                catalogue)
            .fit;
        final passiveResult =
            await NativeFittingEngine(pack.directory.path, libraryPath: library)
                .calculate(passiveFit);
        expect(passiveResult.available, isTrue, reason: passiveResult.error);
        expect(
            passiveResult.diagnostics
                .where((message) => message.contains('状态')),
            isEmpty,
            reason:
                'Frontend defaults for patched PB2 rigs and passive ordinary modules must be legal in the actual native engine');
        await File(
          '${pack.directory.path}/types.pb2',
        ).writeAsString('corrupt cache');
        final repaired = await installer.install();
        await validateNativeEngineDataset(
          repaired.directory.path,
          libraryPath: library,
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set ELS_NATIVE_LIBRARY to a locally built native DLL/shared library; never download in tests.'
        : false,
  );
}
