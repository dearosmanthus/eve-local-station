# 真实本地装配数据

本版已从缓存的 CCP Tranquility SDE build **3494416** 生成真实的 `eve-fit-os` 数据包，
随应用存放在 `app/assets/engine/`。不需要玩家下载、配置或准备数据。数据构建不使用旧 APK。

过去“还必须单独下载 FSD 和本地化 pickle”的阻塞已经解除：当前官方 JSONL SDE 包含
全部所需的类型、Dogma 与 `dbuffCollections.jsonl`。旧版上游转换器尚未适配新的字段布局；
本项目增加开发机转换工具，运行时仍只读取本地 PB2，不包含 Python 或任何下载程序。

| 输入 | 官方记录数 | 用途 |
|---|---:|---|
| types.jsonl | 52,999 | 物品类型、物理属性、英文规则匹配名称 |
| groups.jsonl | 1,610 | 组与类别关系 |
| categories.jsonl | 48 | 舰船、模块、技能等类别 |
| dogmaAttributes.jsonl | 2,867 | 默认值、堆叠/优劣标记 |
| dogmaEffects.jsonl | 3,417 | 官方效果与修正关系 |
| typeDogma.jsonl | 26,828 | 每类物品的属性与效果 |
| dbuffCollections.jsonl | 276 | 当前官方增益集合 |

源 ZIP SHA-256：`dae55c6fcb25ec2f5fc9ddb651ee81815c07b10bb20892a7955657142d3d8409`。
引擎提交固定为 `5772f9d6238a019b71f0fb235fbeeaf1338694f5`。
清单写入 `sde_build: "3494416"`、`fsd_build: "sde-3494416"`，明确 FSD 字段来源是这份 SDE，
没有宣称下载了另一份独立 FSD 数据。

## 转换过程

`tools/engine_data/build_pack.py` 只做数据结构适配和固定上游补丁：

1. 先核对归档内 `_sde.jsonl` 的官方 buildNumber，再逐行读取上述七个文件，拒绝重复 ID。
2. 将 `effectCategoryID` 转为上游 `effectCategory`，`name` 转为 `effectName`；保留官方修正关系。
3. 使用官方英文名称解析上游补丁引用；不存在的 Dogma 数组表示空集合，不填造属性。
4. 应用仓库中固定版本的 YAML 补丁，生成与编译时完全相同的负数属性/效果 ID。
5. 检查所有类型、组、类别、属性、效果、技能和增益引用，验证有限数值及标识映射。
6. 使用固定 Protobuf schema 做确定性序列化；逐一核对 JSON/PB2 负数 ID，生成 SHA-256 清单。

构建后的数量为 52,999 types、2,954 attributes、3,481 effects、26,863 typeDogma、276 buffs。
五个 PB2 合计约 12 MB，真正的游戏计算结果由 Rust 引擎在本机产生。

两项上游细节有明确记录：

- 上游忽略表中的 type 78594 遵循原转换器行为。
- 上游 DPS 补丁通过 speed/duration 两条筛选分支，在 11 种探针发射器上重复注册相同负数
  效果。适配器只移除 22 个完全相同的重复补丁注册，不改变任何 CCP 正数效果或默认状态；
  完整名单保存在构建验证报告中。

官方 `skillEffect` 的 operation 9 被完整保留。上游明确忽略该“技能点换算等级”操作，
因为本地装配直接提供技能等级。10 个 `EffectStopper` 修正同样保留，但上游当前不会执行
其上线限制；原 Protobuf schema 也不支持它们的目标 `effectID` 字段。数据清单与验证报告
明确记录该引擎限制，不声称所有特殊装配限制已经覆盖。

## 开发机重建

从项目根目录执行，`--sde` 指向已经下载的官方 JSONL ZIP：

```powershell
python -m pip install -r tools/engine_data/requirements.txt
python tools/engine_data/build_pack.py --sde C:/eve-data/eve-online-static-data-3494416-jsonl.zip --build 3494416
```

默认中间文件在 `work/engine-converted/`，部署文件在 `app/assets/engine/`。部署目标非空时
工具拒绝覆盖，应先在新的候选目录完成生成与对照，再替换发行包中的数据；例如：

```powershell
python tools/engine_data/build_pack.py --sde C:/eve-data/eve-online-static-data-3494416-jsonl.zip --build 3494416 --converted work/engine-candidate --destination work/engine-candidate-pack
```

构建工具完全不联网。开发依赖首次安装需要网络；此次复用了缓存 SDE，仅额外获取一个
435 KB 的 Protobuf Python wheel。PyYAML 也使用已有缓存。

App 首次启动把包内数据安装到应用专有、带版本的目录，并通过原生引擎检查清单、版本和
文件摘要。更新使用新目录，避免中断写入破坏正在使用的数据。玩家不需要指定文件路径。

## 已验证范围

真实数据的引用完整性检查为零错误。原生烟雾检查覆盖空白舰船、零技能/满技能、炮台与弹药、
激活/停放无人机以及推进/维修模块；六个请求均产生真实计算结果，且停放无人机不会计入 DPS。
独立重复构建的五个 PB2 与清单逐字节一致；PB2 总体积为 11,979,250 字节。
独立 pyfa 回归的结果与范围另见 `docs/PYFA.md`；存在可用 PB2 不等于已验证所有 EVE 效果。

Native 返回的新增数值直接来自计算后属性：HP、抗性、锁定、容量、电容与模块射程。
抗性为 0–1 比例（可能出现真实负抗性），时间统一换算为秒，距离为米。
`tracking_score` 是游戏跟踪评分，不错误标记为弧度/秒。电容的负耗尽时间解释为引擎估算稳定；
超过 24 小时模拟上限时返回“达到模拟上限”，不会伪装成准确耗尽时间或已证明稳定。
`alpha` 表示舰船武器与当前激活无人机的合计齐射；无人机部分从计算后的 volley 属性求和，
不会计入停放无人机。成功计算中的空伤害/带宽汇总为数学意义上的零；失败状态仍不返回统计值。
