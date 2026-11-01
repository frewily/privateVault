# PrivateVault

个人媒体管理项目，目标平台为 macOS、Windows 和 Android。各设备通过自己的本机 OpenList 访问存储、处理 Crypt；账号服务不作为媒体必经中转。

**当前状态（2026-11-01）：W01-M成果保留；W01-A首轮手机可见验收由Owner反馈全部成功。** 用户自行安装后，首次启动/读图、三轮启停、后台返回重启成功；这是用户反馈，进程故障与完整实机矩阵仍未关闭。此前Debug目标编译及APK签名/权限/16KB静态检查通过。按Owner最新引导，包体优化并入后续新功能交付，不再单独发旧功能包重复验收；Release配置已准备但尚缺lint依赖，未生成小包。下一工作包W02已有具体提案，尚未实施。账号、真实库、网盘、来源与播放仍按后续工作包推进。

## 从哪里开始

- 新对话接手：先读 [AGENTS.md](AGENTS.md) 和[开发交接记录](docs/development/开发交接记录.md)，再按当前工作包阅读提案与证据。交接不自动批准下一阶段研发。

- 想了解产品方向：[需求 v0.2](PrivateVault-需求与架构设计-v0.2.md)、[架构 v0.3](PrivateVault-架构细化与首版边界-v0.3.md)。
- 想了解当前开发范围：[W01 实施提案](docs/design/22-W01实施提案-v0.1.md)。
- BoxPlayer 参考：[源码对照](docs/research/25-BoxPlayer功能与核心需求源码对照-v0.1.md)、[借鉴与五项已确认决策](docs/design/26-BoxPlayer借鉴与订阅归档决策-v0.1.md)。继续原开发路线，沿用 Crypt；借鉴任务恢复、能力声明与交互，不改用其自有加密格式。
- 当前工作包：[W01-A提案](docs/design/24-W01-A实施提案-v0.1.md)、[最新构建验收结果](docs/validation/29-W01-A构建验收结果-v0.1.md)、[APK审阅与手机验收说明](docs/development/W01-A-APK安装与验收说明.md)、[运行说明](docs/development/W01-A运行说明.md)。[报告27](docs/validation/27-W01-A执行结果-v0.1.md)保留早期流量停止快照；新的下载授权不自动批准手机/adb或Git操作。
- 最新反馈：[手机手动验收与后续包体要求](docs/validation/30-W01-A手动验收反馈与包体要求-v0.1.md)。当前137.77MiB包已是单arm64；[优化准备与推进调整31](docs/validation/31-W01-A包体优化准备与推进调整-v0.1.md)记录候选Release配置、实际失败点及停止单独打包的决定，不能称为已验证的小包。
- 下一阶段：[W02本地库配置与秘密边界提案](docs/design/32-W02本地库配置与秘密边界实施提案-v0.1.md)。主人已批准第一轮保存推送后开启第二轮，先Mac、再接Android；新增功能集中交付，保留既有手机验收结果。真实账号/库接入仍不包含。
- 本机工具已完成[共享化迁移](docs/validation/28-共享工具链迁移结果-v0.1.md)：Go/Gradle 可在终端直接使用，Flutter 按版本共享，项目锁定 3.47.5；原有默认 3.47.8 保留。工具路径和缓存见 [shared-local.json](toolchains/shared-local.json)，没有新增下载。
- 想看实际结果与限制：[W01-M 阶段结果](docs/validation/23-W01-M执行结果-v0.1.md)。
- Owner 当前聚焦架构、关键决策与验收；[学习路线](docs/development/Owner导读与随项目学习路线-v0.1.md)保留，统一源码阅读放到整个项目完成后。
- 想运行或继续验收：[W01-M 运行说明](docs/development/W01-M运行说明.md)。

## 当前目录

| 目录 | 职责 |
|---|---|
| `apps/privatevault/lib/` | Dart 界面、平台选择、CoreHost 契约与共享消息桥接 |
| `apps/privatevault/android/` | 独立服务进程与桥接，目标编译通过；Owner反馈首轮手机交互成功，完整故障矩阵待补 |
| `native/openlist_bridge/` | 固定 Go 核心包装、运行时驱动限制、占位资源及本机检查 |
| `apps/privatevault/macos/Runner/` | Swift 本机核心生命周期、认证/读取、应用桥接与退出处理 |
| `apps/privatevault/macos/Helpers/` | 通过父应用管道存活状态监督自己的核心，避免主应用强退留下孤儿服务 |
| `apps/privatevault/test/` | 界面与桥接检查、真实核心原生检查 |
| `apps/privatevault/integration_test/` | 实际 Mac 应用集成验收；与无屏幕 Widget 测试分别记录 |
| `tools/` | 固定核心准备、构建与检查入口 |
| `toolchains/` | 公开版本和构件摘要清单 |
| `docs/` | 设计、调研、执行证据与 Owner 导读 |

通用 SDK 和依赖缓存复用本机共享目录；项目 `.tools/` 保留兼容链接，项目特有源码、产物、运行数据仍放忽略目录。不能用 Git 同步秘密，也不能沿兼容链接删除共享工具。正式产品的账号、媒体库、任务、同步与来源功能按后续工作包推进；Windows 实机验收维持暂缓。
