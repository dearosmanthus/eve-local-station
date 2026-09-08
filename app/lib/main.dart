import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain/catalogue.dart';
import 'domain/universe.dart';
import 'services/engine.dart';
import 'services/engine_pack.dart';
import 'services/local_store.dart';
import 'ui/fitting_page.dart';
import 'ui/map_page.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final notices = await rootBundle.loadString(
      'assets/licenses/THIRD_PARTY_NOTICES.txt',
    );
    yield LicenseEntryWithLineBreaks([
      'EVE Local Station and bundled components',
    ], notices);
  });
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});
  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<_AppData> _loading;
  String _progress = '正在打开本地宇宙…';

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<_AppData> _load() async {
    final assets = await Future.wait([
      rootBundle.loadString('assets/data/catalogue.json'),
      rootBundle.loadString('assets/data/universe.json'),
    ]);
    final directory = await LocalFitStore.appDirectory();
    FittingEngine engine;
    try {
      final pack = await EnginePackInstaller(
        root: Directory('${directory.path}/engine-packs'),
        loadAsset: rootBundle.load,
        validateDataset: validateNativeEngineDataset,
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
      ).install();
      engine = NativeFittingEngine(pack.directory.path);
    } on EnginePackException catch (error) {
      const allowDevelopmentFixture = bool.fromEnvironment(
        'ELS_ALLOW_MISSING_ENGINE_PACK',
      );
      if (kReleaseMode ||
          !allowDevelopmentFixture ||
          error.code != 'ENGINE_ASSET_MISSING') {
        rethrow;
      }
      engine = const UnavailableFittingEngine(
        code: 'DEVELOPMENT_ENGINE_PACK_MISSING',
        message: '此开发构建未包含本地装配数据，只能编辑和保存装配。请使用完整安装包进行计算。',
      );
    }
    return _AppData(
      Catalogue.decode(assets[0]),
      Universe.decode(assets[1]),
      directory,
      engine,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_AppData>(
        future: _loading,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data != null) {
            return EveLocalApp(
              catalogue: data.catalogue,
              universe: data.universe,
              store: LocalFitStore(data.directory),
              engine: data.engine,
            );
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: stationTheme(),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: snapshot.hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.storage_rounded,
                              size: 40,
                              color: StationColors.amber,
                            ),
                            const SizedBox(height: 18),
                            const Text('本地数据暂时无法打开'),
                            const SizedBox(height: 8),
                            Text('${snapshot.error}',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () =>
                                  setState(() => _loading = _load()),
                              child: const Text('重新读取'),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 24),
                            Text(_progress),
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      );
}

class _AppData {
  const _AppData(this.catalogue, this.universe, this.directory, this.engine);
  final Catalogue catalogue;
  final Universe universe;
  final Directory directory;
  final FittingEngine engine;
}

class EveLocalApp extends StatefulWidget {
  const EveLocalApp({
    required this.catalogue,
    required this.universe,
    required this.store,
    required this.engine,
    super.key,
  });
  final Catalogue catalogue;
  final Universe universe;
  final FitStore store;
  final FittingEngine engine;

  @override
  State<EveLocalApp> createState() => _EveLocalAppState();
}

class _EveLocalAppState extends State<EveLocalApp> {
  int _page = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EVE 本地空间站',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: stationTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              titleSpacing: 12,
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '本地空间站',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Text(
                    '国际服 · 离线',
                    style: TextStyle(fontSize: 11, color: StationColors.muted),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: '关于与数据来源',
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
                  onPressed: () => _about(context),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: IndexedStack(
                index: _page,
                children: [
                  FittingPage(
                    catalogue: widget.catalogue,
                    store: widget.store,
                    engine: widget.engine,
                  ),
                  StarMapPage(universe: widget.universe),
                ],
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (index) => setState(() => _page = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.view_in_ar_outlined),
                  selectedIcon: Icon(Icons.view_in_ar),
                  label: '舰船装配',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub),
                  label: '星图与路线',
                ),
              ],
            ),
          ),
        ),
      );

  void _about(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('你的离线装配工作台'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('EVE 本地空间站 0.5.0\n国际服中文工具，全部数据保存在本机。'),
              const SizedBox(height: 16),
              Text(
                '本地目录：${widget.catalogue.ships.length} 艘舰船\n静态星图：${widget.universe.systems.length} 个星系\nSDE 构建：${widget.catalogue.provenance['buildNumber'] ?? '未标记'}',
              ),
              const SizedBox(height: 16),
              const Text('路线仅使用静态星门，不反映战况、临时虫洞、玩家跳桥或跃迁限制。高安优先是一种路径偏好，不是安全保证。'),
              const SizedBox(height: 16),
              const Text(
                'Copyright © 2014 CCP hf. All rights reserved. "EVE", "EVE Online", "CCP", and all related logos and images are trademarks or registered trademarks of CCP hf.\n\n本应用是独立玩家工具，不代表 CCP，也不受其赞助。界面图形为原创矢量绘制。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'EVE 本地空间站',
              applicationVersion: '0.5.0',
            ),
            child: const Text('开源许可'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}
