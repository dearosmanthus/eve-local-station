# 本地装配引擎

本项目已经接入真正的 `eve-fit-os` Rust 库，默认启用，并内置由 CCP Tranquility
SDE build 3494416 生成的完整运行时数据包。首次启动自动安装到应用专有目录，装配计算
在本机完成；没有把 pyfa、Python 解释器或下载程序装进 Android。
当前独立 pyfa 对照覆盖 12 个装配、132 项数值，全部通过。这个有限样本的结果不代表
所有舰船和效果都已验证，通用 `pyfa_verified` 标记继续保持 `false`。

## 选型与固定版本

- 源仓库：[Embers-of-the-Fire/eve-fit-os](https://github.com/Embers-of-the-Fire/eve-fit-os)
- 固定提交：`5772f9d6238a019b71f0fb235fbeeaf1338694f5`
- 上游保留 MIT / Apache-2.0 两份许可证；本项目原创桥接代码采用根目录 MIT 许可证。
- 上游运行时代码存档在 `native/vendor/eve-fit-os/src`，未修改。
- 本地构建补丁见 `licenses/eve-fit-os-build.patch`；来源说明见
  `licenses/eve-fit-os-PROVENANCE.md`。

实际读取了此提交的 `fit.rs`、`calculate`、`validate.rs`、`protobuf.rs` 和数据转换器。
其 README 示例已落后于当前 API。接入使用当前的 `ItemID`、`FitContainer::new`
和 `Database::init_from_root`，而非照搬旧示例。引擎包含六阶段 Dogma 计算和装配验证。
这不等于它已与游戏客户端或 pyfa 全量一致。

上游构建脚本原本强制要求 `.env`、`OUTPUT_DIR/json/dogmaAttributes.json` 和
`dogmaEffects.json`。本项目仅修改构建过程：从固定提交的补丁 YAML 提取相同的负数 ID，
存为 `patch_ids.json`；构建时生成原有 Rust 常量。protobuf 编译器由构建依赖提供，
也接受 `PROTOC`。不需要在手机上下载、转换或编译任何东西。

```powershell
cargo test --manifest-path native/Cargo.toml --locked
cargo build --manifest-path native/Cargo.toml --release --lib --locked
# 只用于验证桥接缺省路径；该变体的计算返回 ENGINE_UNAVAILABLE
cargo test --manifest-path native/Cargo.toml --no-default-features --locked
```

## 数据构建与部署

CCP SDE 的目录/星图数据与 `eve-fit-os` 的计算数据是两条管线。目录 JSON 不能冒充
引擎数据库。固定上游的旧转换器要求 FSD 导出，本项目的开发工具已适配现代官方 JSONL
字段，直接使用同一份 SDE 中的类型、Dogma、英文名称和 `dbuffCollections.jsonl`，再应用
固定上游补丁。无需另下载 FSD 或加载本地化 pickle。五个必需的数据文件及清单已存放于
`app/assets/engine/`：

```
types.pb2
dogmaAttributes.pb2
dogmaEffects.pb2
typeDogma.pb2
dbuffcollections.pb2
engine-manifest.json   # 本项目的版本、补丁 ID 与 SHA-256 清单
```

当前五个 PB2 共 11,979,250 字节，独立重复构建与清单逐字节一致。转换器核对归档内
`_sde.jsonl` 的 buildNumber，验证全部引用、有限数值、Protobuf 字段与负数补丁 ID，
最后记录 SHA-256。清单使用 `sde_build: "3494416"`、`fsd_build: "sde-3494416"`；
后者明确表示效果来源是该 SDE，不是另一份独立 FSD。来源摘要、转换细节和限制见
[ENGINE_DATA.md](ENGINE_DATA.md)。

从项目根目录重建候选包；`--sde` 使用已准备好的官方 JSONL ZIP：

```powershell
python -m pip install -r tools/engine_data/requirements.txt
python tools/engine_data/build_pack.py `
  --sde C:/eve-data/eve-online-static-data-3494416-jsonl.zip --build 3494416 `
  --converted work/engine-candidate --destination work/engine-candidate-pack
```

工具拒绝覆盖非空部署目录；升级应先生成候选包并完成对照，再替换发行数据。转换工具
本身不联网，首次安装开发依赖可能需要网络。文件摘要用于完整性与版本匹配，并非 CCP
对数据包的数字签名。

Android 的 `EnginePackInstaller` 从只读 assets 安装到应用专有的
`engine-packs/pack-<引擎版本及数据摘要前缀>/`，将实际目录传给 `data_path`。它使用暂存目录、
安装锁和原生完整摘要校验，验证通过后才启用；已有缓存损坏时从 APK 内数据重建。
升级使用不同版本目录，玩家无需配置路径或准备数据。加载失败或引擎异常返回明确错误，
不回退到基础属性近似值。

## JSON / C ABI v1

库名为 `libeve_local_core.so`（Android）、`eve_local_core.dll`（Windows）。
头文件是 `native/include/eve_local_core.h`。Dart 通过 SDK 自带 `dart:ffi` 调用：

- `els_alloc(size)` 分配归零的输入缓冲区；长度包括末尾 NUL，最多 1 MiB + 1。
- `els_call(request)` 同步返回 NUL 结尾 UTF-8 JSON 字符串。
- `els_free(response)` 释放返回值；不得用输入缓冲区释放函数代替。
- `els_dealloc(input, original_size)` 用原始长度释放输入；每个指针只释放一次。

FFI 调用方必须提供有效指针，调用期间不能释放输入。解析/计算异常在边界内转换为错误。
`calculate` 会读本地磁盘、校验与加载数据库，客户端已通过 Dart isolate 调用，避免阻塞界面。
当前实现每次计算重新加载，不做共享可变引擎状态；后续可在隔离线程内缓存。

```json
{
  "op": "calculate",
  "data_path": "/app-private/engine-packs/pack-<installed-version>",
  "fit": {
    "ship_type_id": 587,
    "skill_mode": "all5",
    "skills": {},
    "modules": [
      {"type_id": 2889, "slot_type": "high", "index": 0, "state": "active", "charge_type_id": 185}
    ],
    "drones": [],
    "implants": []
  }
}
```

该 JSON 仅说明输入结构，不是被认可的标准装配。槽位为 `high/medium/low/rig/subsystem`；
序号从 0 开始；模块状态为 `offline/online/active/overloaded`。无人机为
`{"type_id":2456,"quantity":5,"state":"active"}`，未出舱时使用 `online`。
`offline` 在底层对应 `Passive`；改装件和子系统是固定装配，其被动效果仍生效。
普通模块允许的状态由实际效果决定，不能把所有模块都强制设为激活或过载。
植入体为 `{"type_id":27252,"index":6}`，槽位 1–10，实际适配仍由引擎验证。
`skill_mode` 默认 `custom`；`skills` 的键是类型 ID 字符串，等级 0–5；`all5`
从当前数据库的技能类别生成满技能，再应用显式覆盖。不联网查询角色。

`{"op":"health"}` 返回引擎编译状态、版本、`pyfa_verified:false`；可附加
`data_path` 检查文件状态。健康检查的 `ready` 表示版本和摘要正确，不表示已验算游戏结果。

成功响应：`{"ok":true,"result":{...}}`。计算结果包括：

- `ship_attributes`：已计算的有限 Dogma 数值，属性 ID 为 JSON 字符串键；缺失值省略。
- `module_attributes`：模块/无人机、实际状态、槽位、弹药属性及每项 `stats`。
- `stats`：下表中的命名数值。成功计算中的空汇总为零，未知单项省略；失败不产生统计值。
- EHP 使用 EM/热/动/爆各 25% 的伤害分布。`alpha` 包含舰船武器和当前激活无人机的齐射，
  无人机数量已展开，不重复乘数量，不计入停放无人机。
- `diagnostics`：上游装配验证错误或警告；可计算的超配仍可返回结果并显示错误。
- `pyfa_verified:false`：保留为通用的未全量验证标记，具体对照范围见下文。

| 舰船 `stats` 键 | 单位/含义 |
|---|---|
| `cpu_used`, `cpu_output` | tf |
| `powergrid_used`, `powergrid_output` | MW |
| `dps`, `dps_with_reload`, `drone_dps` | HP/s；前者不含重装填时间 |
| `alpha`, `ehp`, `shield_hp`, `armor_hp`, `hull_hp` | HP |
| `speed`, `align_time`, `warp_speed` | 分别为 m/s、s、AU/s |
| `shield_resist_*`, `armor_resist_*`, `hull_resist_*` | 后缀 `em/thermal/kinetic/explosive`；比例，0.5 即 50%，保留真实负抗性 |
| `capacitor_capacity` | GJ |
| `capacitor_peak_recharge`, `capacitor_peak_drain`, `capacitor_peak_delta` | GJ/s，来自引擎峰值计算 |
| `capacitor_recharge_time`, `shield_recharge_time` | s |
| `capacitor_stable`, `capacitor_duration`, `capacitor_simulation_limit` | 稳定标记 1/0、估算耗尽秒数、达到模拟上限标记 1 |
| `target_range`, `signature_radius` | m |
| `scan_resolution`, `max_targets` | 分别为 mm、数量 |
| `cargo_capacity`, `drone_bay_capacity`, `drone_bay_used` | m³ |
| `drone_bandwidth`, `drone_bandwidth_used`, `active_drones` | 分别为 Mbit/s、Mbit/s、数量 |

电容负耗尽时间解释为引擎估算稳定；达到 24 小时模拟上限时只返回
`capacitor_simulation_limit:1`，不声称已稳定或将在该时刻耗尽。电容结果不在当前 pyfa 对照样本内。

每个 `module_attributes[].stats` 可含 `optimal_range`、`falloff`（m）、`tracking_score`
（EVE 跟踪评分，不是 rad/s）、`dps`（HP/s）、`volley`（HP）、`cycle_time`（s）。
有对应弹药属性时提供 `charge_flight_time`（s）、`charge_velocity`（m/s），不将两者相乘冒充
已经验证的导弹射程。原始 Dogma 属性仍保留上游单位；只有这些命名统计值进行上述单位换算。

错误响应：`{"ok":false,"error":{"code":"DATA_MISSING","message":"..."}}`。
还可能包括 `INVALID_REQUEST`、`INVALID_UTF8`、`INVALID_FIT`、`UNKNOWN_TYPE`、
`ENGINE_UNAVAILABLE`、`DATA_INVALID`、`DATA_VERSION_MISMATCH`、`ENGINE_PANIC`。
失败响应没有 `result`，不产生“看起来合理”的 DPS 或 EHP。

## 当前覆盖与后续验证

原生核心 16 项测试通过，覆盖 FFI 分配释放、UTF-8、输入格式、非法状态、重复槽位、
技能范围、缺失数据、版本不匹配、摘要篡改、客户端请求格式、未出舱无人机状态映射、
空汇总、物理单位、电容上限与激活无人机齐射。数据转换器另有 6 项测试；这些测试不代替
独立计算对照。

真实 pyfa EOS 提交 `8b04f3b271e614b3e103853b44a7851a63d79d0e` 使用同版官方 SDE 的
独立 SQLite 转换，计算代码未修改，不读取本引擎 PB2 或补丁。12 个装配的 11 项指标
共 132 项比较全部通过，绝对/相对容差均为 `1e-6`，最大绝对差约 `9.58e-9`。
样本覆盖零/满技能、炮台激活/离线/过载、两个回转稳定器堆叠、AB/MWD、损伤控制、导弹及
出舱/停放无人机。输入、结果、复现方法及明确的剩余范围见 [PYFA.md](PYFA.md) 和
`data/benchmarks/core-report-3494416.json`。

另做了真实 Tengu 原生检查：舰船 29984，四个子系统 45626/45591/45601/45614 使用
Passive 状态，装载六个 Heavy Missile Launcher II（2410）与 Scourge Heavy Missile（209），
无诊断错误；CPU 为 185.625/587.5 tf，电网 425.25/915 MW，DPS 约 297.567175。
这个检查没有独立 pyfa T3 对照，不计入 132 项比较。T3 槽位由客户端依据实际子系统修正得到，
上游验证也单独累加子系统挂点；原始舰船槽位属性为零不能被解释为可用槽位总数。

电容、逐层抗性、射程及大量特殊效果尚未独立对照。当前上游不执行 10 个 `EffectStopper`
限制，详情见数据说明。铁骑、增效剂、深渊属性、舰队加成和自定义伤害分布未暴露给本版客户端。
