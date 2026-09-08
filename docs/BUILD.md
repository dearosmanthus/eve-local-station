# 构建与验证

## 固定基线

| 工具 | 本次使用版本 |
|---|---|
| Flutter / Dart | 3.35.7 / 3.9.2 |
| Rust | 1.98.1 stable |
| JDK | 17 |
| Android SDK / build-tools | 36 / 35.0.0、36.0.0 |
| Android NDK | 27.0.12077973 |
| CMake（Flutter 构建使用） | 3.22.1 |
| Gradle / Android Gradle Plugin | 8.12 / 8.9.1 |
| Kotlin | 2.1.0 |
| cargo-ndk | 4.1.2 |
| Android 输出 | ARM64，API 24+，target 36 |

仓库包含 Gradle wrapper、Cargo.lock、pubspec.lock，以及固定提交的 eve-fit-os 源码。构建时允许开发机下载依赖；应用运行时不联网。构建记录见 BUILD_REPORT.md。

## 准备工具

安装 Flutter、Rust、JDK 17、Android command-line tools，配置 PATH、JAVA_HOME、ANDROID_HOME。在开发机完成 Android SDK 许可后安装：

```sh
sdkmanager "platform-tools" "platforms;android-36" "build-tools;35.0.0" "build-tools;36.0.0" "ndk;27.0.12077973" "cmake;3.22.1"
rustup target add aarch64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
flutter config --no-analytics
flutter precache --android
```

推荐 Linux 或装好 Visual Studio C++ Build Tools 的 Windows。若在 Windows 使用 Rust GNU 工具链，且 dlltool 报找不到 assembler，可将 NDK 的 `toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-dlltool.exe` 复制为工作目录中的 `dlltool.exe` 并将该目录加入当前进程 PATH。不要替换系统工具。

## 一次构建

项目根目录：

```sh
python -m unittest discover -s tools/tests -v
cargo test --manifest-path native/Cargo.toml --locked
python tools/build_android.py
```

脚本先构建并复制 Rust 动态库，然后执行 Flutter 分析、测试、APK 构建和最终 APK 离线审计。所有 Flutter 命令关闭版本检查与遥测；依赖解析只做一次，后续分析、测试与构建传入 `--no-pub`。直接运行 `flutter build apk` 时若 Rust 库不存在，Gradle 会明确报错。不要用空库跳过检查。

输出为 `app/build/app/outputs/flutter-apk/app-release.apk`。当前 release 构建使用本地 debug key 签名，适合安装预览，不应直接作为商店正式发布包。正式发布前使用自有签名、完成独立 pyfa 对照和真机飞行模式测试。

## 复用缓存与节省流量

依赖已准备好的开发机可以显式使用缓存构建。先保留已有的 `CARGO_HOME`、`RUSTUP_HOME`、`PUB_CACHE`、`GRADLE_USER_HOME`、`ANDROID_HOME` 和工具链 PATH；不要为了构建新目录而重新下载工具链。缓存路径没有写死在项目中。以下路径仅为示例，应指向之前实际使用的缓存：

```sh
python tools/build_android.py --offline --plan-only --cargo-target-dir C:/eve-cache/native-target --gradle-project-cache-dir C:/eve-cache/android-gradle
python tools/build_android.py --offline --cargo-target-dir C:/eve-cache/native-target --gradle-project-cache-dir C:/eve-cache/android-gradle
```

`--plan-only` 只检查本地工具/关键缓存并打印将执行的命令，不启动构建进程。真正的 `--offline` 模式使用 Cargo `--frozen`、pub `get --offline` 与 Gradle `--offline`；缓存缺失时直接失败，没有自动联网重试。Flutter/Rust 工具本身若缺少二进制缓存，其下载入口在当前子进程中指向不可用的本机端口，以阻止下载大型 SDK。脚本不修改用户的全局工具配置，也不清空已有缓存；正常编译仍会更新相应构建缓存。

Flutter 3.35.7 没有把 Gradle `--offline` 直接透传的选项。因此脚本先运行 Flutter `build apk --config-only --no-pub` 生成当前版本的 `local.properties` 和插件配置，再调用 wrapper 指定版本在 `GRADLE_USER_HOME` 中已经解压的 Gradle 执行 `assembleRelease --offline`。Flutter Gradle 插件仍负责真实 Dart/AOT 编译，并把 APK 放到相同输出目录。脚本不会临时安装全局 Gradle init 脚本，也不会调用可能自行下载分发包的 wrapper。Gradle 保留原始 Maven 仓库标识，避免已下载的依赖因仓库地址改变而无法命中缓存。

离线构建需要完整的 Flutter host tester、Android ARM64 release snapshot、pub 包、Gradle 分发包/插件/Maven 依赖、Android SDK/NDK/CMake 和 Rust Android target。预检查覆盖关键工具；剩余的包缓存缺失会由对应工具说明。先在允许下载的网络上按固定版本准备缺失项，再使用同一缓存重试；不要把离线失败改成自动下载。

中文源项目可以保留原位置，但本次 Windows Flutter 3.35.7 的 `gen_snapshot` / `impellerc` 实测无法可靠打开中文构建路径。`app/android/gradle.properties` 中的 `android.overridePathCheck=true` 和 JVM UTF-8 设置只解决 AGP 配置检查，不能解决这些原生编译工具的路径问题。请从原项目运行以下临时副本构建，目标必须是项目之外、全 ASCII 路径的新目录或空目录：

```sh
python tools/stage_android_build.py --destination C:/eve-cache/android-preview-0.5 --offline --cargo-target-dir C:/eve-cache/native-target --gradle-project-cache-dir C:/eve-cache/android-gradle
```

脚本复制便携源码和正式数据，沿用 `package_source.py` 的目录排除规则，不复制工具链、缓存、工作文件、旧 APK、构建输出或签名密钥；原项目不移动、不删除。它始终要求离线缓存构建，在临时副本中运行完整的 Rust 编译、Flutter 分析/测试、AOT 编译及 APK 审计。只有这些步骤成功，才把本次新生成且审计通过的 APK 按 SHA-256 核对后复制回原项目的正常输出位置。失败时保留临时副本供检查，不会把旧 APK 当作新结果。

源文件逐项 SHA-256 清单、整体快照摘要和构建状态保存在副本的 `work/staging-provenance.json`；成功后的 APK 旁另有 `app-release.staging.json`，记录同一快照和 APK 摘要。`--plan-only` 会创建副本并检查本地依赖，但不编译、也不复制 APK；之后的正式运行必须另选新目录，因为工具拒绝清理或覆盖非空副本。

使用 Windows GNU Rust 工具链时，`CARGO_TARGET_DIR` 也应为 ASCII 路径；通过环境变量或 `--cargo-target-dir` 复用之前的构建目录。`--gradle-project-cache-dir` 可复用项目级 Gradle 缓存。所有缓存环境变量和 PATH 都由调用进程保留，无需再下载依赖。

## CI 缓存策略

现有 `.github/workflows/ci.yml` 在新 runner 上显式安装固定工具链，首次准备仍会使用网络；“应用离线”不等于“冷缓存 CI 无需下载”。要使用 `--offline`，runner 必须先恢复同一平台、同一工具链版本的完整缓存，包含 `GRADLE_USER_HOME` 的 wrapper 分发包和依赖缓存、pub/Cargo 缓存以及 Android/Flutter 二进制。建议缓存键包含平台、Flutter/Rust/Gradle 版本和 `pubspec.lock`、`Cargo.lock`；没有命中时停止离线任务或单独安排允许下载的准备任务，避免把两种模式混在一次自动重试中。

对已缓存的 runner，将构建步骤改为 `python tools/build_android.py --offline`，仍执行源码审计、Rust 编译、Flutter 分析/测试和最终 APK 审计。脚本不跳过检查，也不使用旧 APK 冒充本次输出。

## 单独检查

```sh
cd app
flutter --no-version-check --suppress-analytics pub get --offline
flutter --no-version-check --suppress-analytics analyze --no-pub
flutter --no-version-check --suppress-analytics test --no-pub
cd ..
python tools/audit_offline.py
python tools/audit_offline.py --apk app/build/app/outputs/flutter-apk/app-release.apk --aapt /path/to/android-sdk/build-tools/36.0.0/aapt
```

本项目不提供 Web 构建目标，FFI 与本地文件是设计的一部分。后续 Windows 客户端需要增加桌面 runner，当前不宣称 Windows UI 已交付。

## 数据与计算

选船、兼容性与星图的正式数据已打包，可直接编译。更新方式见 DATA.md。当前 `tools/engine_data/build_pack.py` 已从同一份缓存的官方 SDE 生成与固定 eve-fit-os 提交及补丁映射相匹配的 PB2 数据包；不再需要额外下载 FSD。引擎数据构建及已知限制见 ENGINE_DATA.md，独立参考值验证见 PYFA.md。数据包转换成功不代表所有计算已经与 pyfa 一致，缺失或校验失败时仍必须明确报错。
