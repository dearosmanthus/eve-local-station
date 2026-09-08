# EVE 本地空间站 · EVE Local Station

Android 优先的纯本地 Tranquility 工具。原创 Flutter/Dart 界面、Rust 装配计算适配层、打包的官方静态数据。第一版只做装配和星图，市场仅有抽象接口。

GitHub：[项目仓库](https://github.com/dearosmanthus/eve-local-station) · [0.5 安装包与校验记录](https://github.com/dearosmanthus/eve-local-station/releases/tag/v0.5.0)。当前仓库为私有，接手者需由仓库所有者添加访问权限；收到权限后先阅读交接说明，使用分支和 Pull Request 提交改动。

**0.5.0 星图改进版：小尺寸星系点、视野裁剪与绘制缓存、路线视角和本地星系详情。** 保留模块复制、分类选择和完整离线计算数据；同版数据的独立 pyfa 对照范围、APK 和真机验证状态见 [BUILD_REPORT.md](BUILD_REPORT.md)。

接手开发请先读 [项目交接说明](docs/HANDOFF.md)：架构入口、构建与验收、已知限制、优先任务和 PR 要求。后续贡献通过 PR 提交，由用户指定的 Codex 最终审阅并合并。

实际 Flutter widget 渲染预览（非真机截图）：[手机装配页](docs/previews/fitting-phone.png) · [新版星图](docs/previews/map05-overview.png) · [放大星图](docs/previews/map05-zoom10.png) · [星系详情](docs/previews/map05-details.png)。

## 已实现

- 星图缩放时圆点、选中环和文字保持屏幕尺寸；点击范围独立保留。绘制按视野裁剪并复用连线、文字缓存，全图批量绘制。
- 起终点交换、完整路线视角、缩放按钮、名称/连线开关、英文路线复制、最近选择；星系详情含星座、行星、恒星光谱及相邻星系。
- 复制单个模块或填满同类空槽，保留弹药和状态，逐个检查挂点/数量等静态限制，不覆盖已有装备。
- 舰船按官方类型、科技类别、阵营浏览，装备按用途、种类和尺寸浏览；814个官方分类，未分类物品仍可选择。
- 简体中文界面和系统菜单，物品、星系支持中文、英文和 ID 搜索；缺少官方译名时保留英文/代码，国际服 EFT 名称仍为英文。
- 紧凑装配栏、常驻 CPU/能量栅格/伤害/EHP 摘要、槽位分类切换，详细属性与已存装配在弹出面板中查看。
- 新建装配、选择舰船、槽位装备、模块状态、弹药、无人机、全 0 / 全 5 技能基线。
- 装备/弹药尺寸与舰船适配筛选、炮台/发射器限制、T3 子系统动态槽位与系列限制。
- 本地装配保存、载入、删除，EFT 文本导入/导出；无法识别的行明确提示。
- 深色可缩放星图、星系搜索、区域筛选、本地最短路线与高安偏好路线、避让星系。
- 正式 Tranquility SDE 3494416（2026-09-04）：423 艘舰船、4,021 种模块、154 种无人机、1,017 种弹药、8,490 个星系、6,989 条静态星门连接。
- 固定提交的 eve-fit-os 原生集成、C ABI / Dart FFI，计算 CPU/PG、伤害、EHP、速度与更多舰船属性。
- 首次启动从安装包解包计算数据；逐文件 SHA256 校验、版本隔离、缓存损坏修复和中断恢复。
- 可复现的 SDE → 目录/星图/PB2 工具、独立 pyfa 测量与比较器、基础测试、Android 构建和最终包离线审计。

## 纯本地约束

没有后台服务器、登录、SSO、遥测、广告、WebView 或市场联网实现。应用不请求联网、共享存储等系统权限；INTERNET 在 manifest 合并时被明确移除，debug/profile 同样不添加。开发机可以下载依赖和游戏数据，运行时没有下载入口。详情见 [离线设计](docs/OFFLINE.md)。

旧 EVE 空间站仅作为功能范围参考。本项目不复制其反编译代码、数据库、图片、UI 素材或二进制库。图标为本项目原创几何图形，游戏静态数据独立来自 CCP 官方 SDE。

## 快速开始

环境与命令见 [构建说明](docs/BUILD.md)。准备 Flutter 3.35.7、Rust、Android SDK/NDK、JDK 17 后：

```sh
python -m unittest discover -s tools/tests -v
cargo test --manifest-path native/Cargo.toml --locked
python tools/build_android.py
# 依赖已缓存时可完全离线构建，避免重复获取元数据：
python tools/build_android.py --offline
```

APK 路径：`app/build/app/outputs/flutter-apk/app-release.apk`。当前签名是本地预览签名，面向 Android 7.0+ ARM64。

## 计算能力边界

eve-fit-os 被固定在 `5772f9d6238a019b71f0fb235fbeeaf1338694f5`。上游构建脚本依赖已生成的游戏数据；本项目仅对构建过程做小范围可审查补丁，保留计算代码及双许可证。详情和补丁见 [ENGINE.md](docs/ENGINE.md)。

当前官方 JSONL SDE 已包含 Dogma 与 dbuffCollections。新的适配器解决了上游旧字段格式差异，直接从缓存的同一份 SDE 构建五个 PB2 文件，无须另下载 FSD 游戏资源。数据、补丁 ID、版本和摘要均可追溯，见 [ENGINE_DATA.md](docs/ENGINE_DATA.md)。损坏或不匹配的数据会被拒绝，不填入估算数值。

pyfa 只用于开发机上的结果对照，APK 未嵌入 Python、pyfa 或其计算代码。已用固定提交的未修改 EOS 和独立 SQLite 数据转换器采集 12 组真实装配、132 项数值，并保存输入、原始结果与可复现工具。[PYFA.md](docs/PYFA.md) 列出具体覆盖范围。通过部分基准不代表所有舰船和特殊效果均与 pyfa 一致。

EFT 不保存所有模块状态、技能模式等本应用字段；无损编辑记录以本地装配文件为准。临时虫洞、跳桥、实时危险和舰船通行限制不在静态路线范围内。

## 项目目录

| 路径 | 内容 |
|---|---|
| app/lib | Flutter 界面、装配模型、EFT、本地保存和路线算法 |
| app/android | 原生 Android runner、私有存储通道、离线 manifest |
| app/assets/data | 官方 SDE 转换出的实际数据和版本清单 |
| app/assets/engine | 同版 SDE 构建的五个 PB2 文件与校验清单 |
| native | Rust C ABI、适配层、测试、固定上游源码与补丁 |
| tools/data | 显式下载与纯本地转换 |
| tools/engine_data | 官方 JSONL → 固定上游补丁 → 确定性 PB2 |
| tools/benchmark | pyfa 对照和本地结果采集 |
| tools | Android 构建、最终 APK 权限审计、许可证归档 |
| data | 对照样例、测试数据与能力覆盖清单 |
| docs | 构建、离线边界、数据来源、计算限制和交互说明 |
| licenses | 上游许可证、CCP 条款来源和依赖归档 |

## 授权与来源

原创代码采用 [MIT](LICENSE)。eve-fit-os 的 MIT/Apache-2.0、Flutter BSD、依赖许可证、pyfa 仅参考工具的 GPLv3 说明和 CCP 游戏数据条款分别归档，见 [THIRD_PARTY.md](licenses/THIRD_PARTY.md)。原创代码许可证不改变 CCP 数据与商标的权利。

EVE Online and all related logos and designs are the intellectual property of CCP hf. This is an independent fan tool and is not endorsed by CCP.

## 后续优先级

1. Android 真机飞行模式验证、操作体验和性能检查。
2. 扩展 pyfa 对照至电容、复杂抗性、T3、特殊武器和更多舰船。
3. 植入体、细粒度技能、增效剂与舰队效果编辑；完整本地备份格式。
4. 正式签名与发布准备。市场保持未启用。
