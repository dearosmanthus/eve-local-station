# 项目交接 · 0.5.0

本项目是 Android 优先的纯本地 EVE Online 国际服工具，当前交接基线为 **0.5.0+5**。
请先阅读本页，再按 [BUILD.md](BUILD.md) 构建。已有交付的证据与边界见
[BUILD_REPORT.md](../BUILD_REPORT.md)，功能试用步骤见 [TESTING.md](TESTING.md)。

用户希望其他开发者继续实现功能，最后由用户指定的 Codex 审阅并执行合并。后续改动通过
分支和 Pull Request 提交，保持默认分支可构建；交接文档不代表已配置分支保护、审阅人账号
或自动合并。不要自行把尚未审阅的改动合入默认分支。

## 当前能做什么

| 模块 | 当前状态 |
| --- | --- |
| 装配 | 中文紧凑列表；选船、装备分类、状态、弹药、无人机；全 0 / 全 5 技能；复制模块和批量填槽；本地保存与 EFT 导入导出 |
| 计算 | 固定版本 eve-fit-os，通过 Rust C ABI / Dart FFI 在本机计算；应用内置真实 PB2 数据；错误时明确显示不可用 |
| 星图 | 静态星门、本地最少跳数/高安偏好路线、避让、区域与搜索定位；小尺寸星点、视野裁剪、绘制缓存；星系详情与相邻星系跳转 |
| 市场 | 仅有抽象接口；装备选择使用的官方 marketGroups 是静态分类目录，没有价格、订单或市场服务 |
| Android | ARM64、Android 7.0/API 24+、target 36；预览签名 APK；不请求联网或设备访问权限 |

打包数据为 CCP Tranquility SDE **3494416（2026-09-04）**，管线版本 6：423 艘舰船、
4,021 种模块、154 种无人机、1,017 种弹药、8,490 个星系、6,989 条静态星门连接。
默认星门网络显示其中 5,268 个有静态连接的星系；其余仍可搜索或按星域查看。

0.5 的已有构建记录为 78 项 Python、16 项 Rust、91 项 Flutter 测试通过，Flutter 静态分析
及最终 APK 离线审计通过。这是该版本的记录，不能代替新分支上的检查。界面预览是
[Flutter widget 渲染](previews/README.md)，未执行 Android 真机安装、升级或触摸性能验证。

## 必须保持的约束

[AGENTS.md](../AGENTS.md) 是仓库约束入口，[OFFLINE.md](OFFLINE.md) 解释实现方式。

- 应用运行时禁止联网、后台服务器、账号、SSO、遥测、广告、WebView、远程字体和图片；
  debug/profile/release 均不得新增联网或设备访问权限。保留 AndroidX 的 signature 级
  内部广播保护，使用应用私有存储，保持系统备份关闭。
- 开发工具可以显式准备依赖和官方 SDE；工具不得打包进应用或由应用调用。缓存缺失时，
  `--offline` 构建应报错，不得悄悄改为联网重试。
- 不使用旧 EVE 空间站 APK 中提取的代码、二进制、数据库、图片或其他素材。其功能操作
  仅作参考，界面与交互自行实现。中文名称来自官方 SDE，EFT 物品名使用国际服英文名称。
- 引擎或数据不可用时返回和显示明确错误，不能用基础属性或估算值伪造 DPS、EHP 等结果。
  原始目录属性用于选择和静态限制，不替代 Dogma 计算。
- 固定引擎提交、保留许可证和最小补丁；PB2、补丁 ID、引擎版本和文件摘要必须匹配。
  pyfa 仅作独立开发参考，不成为 APK 运行时依赖。
- 不提交工具链、原始下载归档、密钥、`local.properties`、构建和缓存目录。保留锁文件、
  经转换的数据、来源清单、独立对照输入及报告。

## 从哪里改

| 路径 | 职责与注意点 |
| --- | --- |
| `app/lib/main.dart`、`app/lib/ui/theme.dart` | 应用入口、页面容器、中文主题和版本显示 |
| `app/lib/ui/fitting_page.dart`、`type_picker.dart` | 装配操作与分类选择；延续紧凑布局，避免把详情堆在主页面 |
| `app/lib/domain/fit.dart`、`compatibility.dart`、`module_copy.dart` | 装配模型、静态适配与复制限制；不要覆盖已有装备或把未知限制当作禁止 |
| `app/lib/domain/eft.dart`、`app/lib/services/local_store.dart` | 英文 EFT 交换与本机保存；修改持久化格式需处理旧装配兼容 |
| `app/lib/services/engine.dart`、`engine_pack.dart` | FFI、隔离线程计算、本地数据安装及校验；失败不生成统计值 |
| `native/src/lib.rs`、`engine.rs`、`native/include/eve_local_core.h` | C ABI、输入检查与上游计算适配；调用方必须正确释放输入和输出内存 |
| `native/vendor/eve-fit-os`、`licenses/eve-fit-os-build.patch` | 固定上游与构建补丁，避免无记录修改或升级 |
| `app/lib/domain/universe.dart` | 星系数据、图与本地路线算法；静态高安偏好不代表实时安全 |
| `app/lib/ui/map_page.dart`、`star_map_canvas.dart`、`system_picker.dart` | 地图交互、画布与索引、搜索；缩放和拖动不应重新投影全部数据或重建整页 |
| `tools/data`、`tools/engine_data` | 官方 SDE → 目录/星图与 PB2，两套输出需按同一来源版本成套更新 |
| `tools/benchmark`、`data/benchmarks` | 独立 pyfa 采集、原生采集、比较器及真实基线；不得反向修改参考值来消除差异 |
| `tools/build_android.py`、`stage_android_build.py`、`audit_offline.py` | 构建、Windows ASCII 路径副本和最终包权限审计 |

当前桥接直接使用 Dart SDK 的 `dart:ffi`，不是早期设想的 `flutter_rust_bridge`。
计算通过 isolate 避免阻塞界面；原生实现目前每次计算重新加载数据，后续可以在独立线程中
评估安全缓存。完整接口见 [ENGINE.md](ENGINE.md)。

## 接手后的第一次构建

建议将仓库克隆到全 ASCII 路径，尤其在 Windows 上。准备固定工具版本：Flutter 3.35.7 /
Dart 3.9.2、Rust 1.98.1、JDK 17、Android SDK 36、NDK 27.0.12077973、CMake 3.22.1、
cargo-ndk 4.1.2；其余版本和环境变量见 [BUILD.md](BUILD.md)。

发行数据已在仓库中，普通开发构建不需要重新下载约 99 MB 的原始 SDE，也不需要重新生成
PB2。第一次准备工具链可能需要网络；已缓存环境优先复用缓存。

在仓库根目录运行：

```sh
python -m unittest discover -s tools/tests -v
cargo test --manifest-path native/Cargo.toml --locked
python tools/build_android.py --offline
```

完整构建脚本会编译 Android Rust 库，执行 Flutter 分析与测试，构建 APK，并审计最终包。
若依赖尚未准备，按构建文档先完成准备；允许下载的开发环境可显式去掉 `--offline`。
输出为 `app/build/app/outputs/flutter-apk/app-release.apk`。不要只改 Flutter 页面然后拿
旧 `.so` 或旧 APK 当作本次构建结果。

独立运行 Flutter 检查时：

```sh
cd app
flutter --no-version-check --suppress-analytics pub get --offline
flutter --no-version-check --suppress-analytics analyze --no-pub
flutter --no-version-check --suppress-analytics test --no-pub
```

原生集成 widget 测试需要 `ELS_NATIVE_LIBRARY` 指向本次在主机编译的 DLL/共享库；未设置
时相关测试会跳过。测试说明中须记录跳过项，不能将未执行的原生集成检查记为通过。
Windows GNU 工具链与中文路径的已知问题及临时源码副本命令见 [BUILD.md](BUILD.md)。

交付 Android 包必须使用真实的新原生库，并执行：

```sh
python tools/audit_offline.py --apk app/build/app/outputs/flutter-apk/app-release.apk --aapt /path/to/android-sdk/build-tools/36.0.0/aapt
```

仓库已有 CI 定义；Linux 任务先编译主机原生库，并向构建步骤传入 `ELS_NATIVE_LIBRARY`，
让 Flutter 原生集成检查实际加载该库。新 runner 会下载工具链和依赖。CI 配置存在不代表
某次 GitHub 运行已成功，须检查具体 PR 对应提交的结果。没有真机时如实注明，不用电脑
测量结果推算手机 FPS。

## 数据与数值验证

引擎固定提交为 `5772f9d6238a019b71f0fb235fbeeaf1338694f5`。数据升级先在新的候选目录生成，
完成检查与独立对照后再替换成套资产，不覆盖唯一可用包。来源、转换及许可证分别见
[DATA.md](DATA.md)、[ENGINE_DATA.md](ENGINE_DATA.md) 和
[第三方说明](../licenses/THIRD_PARTY.md)。

当前独立 pyfa 参考为 12 组装配 × 11 项指标，共 132 项已通过比较，覆盖常见 CPU/PG、
推进、伤害、部分堆叠、过载和无人机行为。参考与本地引擎使用同版 SDE，输入、原始结果和
容差可追溯。复现命令见 [PYFA.md](PYFA.md)。

电容、逐层抗性、射程、完整 T3、特殊武器、植入体、增效剂和舰队效果未被这 132 项覆盖；
通用 `pyfa_verified` 仍为 `false`。扩展参考转换器时必须保持独立，不读取本引擎 PB2 或补丁
来生成所谓参考答案。上游当前不执行 10 个 `EffectStopper` 限制，不能宣称静态检查已涵盖
所有上线限制。

## 已知限制与优先接手工作

1. **真机验收。** 飞行模式首次启动、退出重开、从旧版本覆盖安装后保留装配；检查小屏、
   大字体、横屏、软键盘和长名称。星图记录全图/局部视角的触摸手感及性能，附机型和 Android
   版本。先据实定位问题，再决定缓存、文字预算或重绘策略。
2. **扩充独立计算对照。** 优先电容、抗性层与堆叠、完整 T3，逐项记录具体装配、技能、状态、
   数据版本及单位。差异先区分适配问题、引擎问题与参考上下文差异。
3. **本地装配保护与编辑。** 设计完整本地备份/恢复，再扩展细粒度技能、植入体等输入。
   当前 EFT 不保留全部状态和技能设置；卸载会删除应用私有装配，现有系统备份保持关闭。
4. **发布准备。** 当前为预览签名。正式密钥由维护者单独保管，不能入库。不同开发机新生成的
   debug key 通常不能覆盖现有预览包；不要让测试者直接卸载丢失装配，应先安排导出和升级方案。

保持中文、深色、紧凑交互，详情按需展开。市场和所有在线功能仍在范围之外。星图只表达
静态星门，不提供临时虫洞、跳桥、实时危险或访问限制信息。当前没有 Web 或 Windows UI
交付目标。

## Pull Request 交付要求

- 一项明确问题对应一个可审阅分支/PR；说明触发步骤、改动后的行为与用户影响，避免把无关
  重构、引擎升级和数据升级混在一起。
- 附对应提交的实际测试命令与结果，包括失败、跳过及环境限制。界面变更附小屏中文预览或
  真机截图；计算变更附独立对照证据；数据变更附来源版本、摘要和候选包验证结果。
- 修改存储、版本或签名时说明旧装配与升级兼容；新增依赖时解释用途并归档许可证，确认不
  引入运行时网络及权限。
- 交付 APK 时记录版本、SHA256、权限审计、签名与真机验证状态。密钥只由原维护者安全保存，
  不通过 PR、附件或源码包传播。
- 更新相关文档和已知限制，使用 [PR 模板](../.github/pull_request_template.md)。遇到未覆盖的
  数值或特殊效果明确标为未验证。
- 提交后把 PR 链接交给用户，由用户指定的 Codex 针对最新提交审阅、提出修改并在验证通过后
  执行最终合并。新增提交后重新检查受影响部分；CI 通过本身不等同于最终审阅通过。
