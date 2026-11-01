# PrivateVault 技术可行性研究 01：三端本地 OpenList 复用

日期：2026-10-25（Asia/Shanghai） · 版本：v0.1 · 对应设计：项目根目录《PrivateVault-需求与架构设计-v0.2.md》

状态：**完成本项公开资料及关键源码研究，运行验证未执行。** 本次仅新增研究文档，未安装、构建、运行 OpenList，未连接网盘，未写实现代码，未修改 v0.1/v0.2 设计文档，未提交或推送。

## 1. 结论先行

**三端本地运行 OpenList 有明确的现成源码基础；Android 本地加密上传不是桌面专属能力。** 可以继续推进这条路线。但“已有 OpenList Mobile”不等同于“PrivateVault 的三端独立下载、可靠归档、视频快进及锁屏播放已经完整可用”。

建议方向：

1. PrivateVault 提供统一界面，复用 OpenList 的存储/加密核心，并保留自己的账户、资料库、归档状态和元信息同步边界。
2. macOS/Windows：优先采用受控的本地 OpenList 核心进程，通过本机 HTTP 接口使用能力。
3. Android：优先评估把 OpenList 核心编译为 AAR，在 PrivateVault 自己的 Android 宿主内启动；复用移动项目的桥接思路，调整生命周期、秘密保存和日志。
4. 下载来源解析、可靠任务队列、配额、媒体探测与元信息提交需要单独整合；不默认把现成 App 的下载按钮视为完整归档引擎。
5. 现成 Desktop/Mobile App 适合作为早期验证工具；正式产品的单一入口不宜建立在操控另一个 App 的界面或未声明稳定性的内部桥接方法之上。

本项结论是**有源码依据的可行方向＋明确适配工作**。尚未作出“运行通过”“全部现成可用”“已经锁定最终语言和客户端框架”的结论。

## 2. 范围、方法与证据等级

研究范围：三端核心启动、桥接与本地接口；Crypt 上传/随机读取；Android 下载、文件、后台服务、播放跳转；版本与分发约束。

未在本项完成：Pixiv/hanime1 的完整来源适配研究、百度账户/API 的端到端确认、独立账号服务实现、元信息多端冲突算法。这些分别承接后续研究项，不因本项完成而视为解决。

证据分类：

- **源码事实**：能定位到本轮读取的官方仓库文件及具体代码路径。
- **设计推断**：根据现成路径提出 PrivateVault 的复用方式，不代表已经集成或得到上游稳定 API 承诺。
- **待运行验证**：编译、权限、真机后台、账户授权、真实网络、性能与跨端互读。
- **未确认**：本轮没有足够依据，明确保留。

本轮没有完整审计上游仓库；检查了与上述问题直接相关的关键路径。未安装或执行上游构建脚本。浏览器读取 Android Developers 超时说明未能稳定完成，后台限制采用 AOSP 源码文档作为依据；不把页面标题或访问尝试算作读完文档。

## 3. 调查快照与复现边界

| 对象 | 本次固定版本/标识 | 用途 |
|---|---|---|
| OpenList 核心 v4.2.8 标签解析结果 | commit `25e4eb663ffb73991a68d85df4f690d48ad137a6` | 驱动注册、Crypt、HTTP 路由、模块依赖 |
| OpenList 核心 main 调查快照 | commit `0497ee853853eff5fc0ada9f21684a990887de83` | 初步比对；不代替实际移动 AAR 的构建版本 |
| OpenList Mobile | commit `585b70898cc30587d535f93d1f4ee383ae8d0646` | Android 宿主、构建脚本、下载、桥接 |
| OpenList Desktop | commit `7efcb538e7128a3281011604146137c3d178b369` | 桌面进程管理路线 |
| AOSP ServiceInfo.java | blob `8243d88e6260b61a00e047bfba4ba1b6ccece439` | dataSync 服务类型与时限说明 |
| AOSP Service.java | blob `aaddaa62a32fec846bf88847b1e21e1db4e9813e` | 服务被回收及超时回调说明 |
| CPython Android 使用文档 | blob `e24ecafc3a80f8e97e10fd20721cce8cbf4b1f4a` | Android Python 的嵌入与分发方式 |

AOSP/CPython 链接使用本次读取的 main 文件，记录的是文件 blob，不是仓库提交号，分支链接未来可能变化。前三个项目的关键引用使用固定提交链接。

Mobile 的 `openlist_version` 在该快照中为 v4.2.8，但其初始化脚本动态选择上游标签并拉取源码。这个文本标识不能证明某个已发布 APK 内嵌的 AAR 恰好来自本报告的核心提交，也不能证明三端运行的是同一版本。实际验证必须记录安装包来源、签名/校验信息、内核版本和 Crypt 参数。[S1][S2]

## 4. macOS / Windows：已有受控进程管理路线

**源码事实**：Desktop 的启动配置把 OpenList 核心作为本地可执行文件启动，传入服务模式和独立数据目录；进程管理器使用系统子进程接口启动、查询和停止进程，并区分 Windows 与其他桌面平台。[S3][S4]

这证明“桌面界面＋本地核心进程”有官方项目实现可参考。它不证明 PrivateVault 已能直接控制另一个 Desktop App，也不等于 PrivateVault 应复制其完整 UI 或自动更新策略。

**建议的 PrivateVault 桌面结构**：

- 自有客户端管理本应用使用的核心版本、数据目录、监听地址、启动和退出。
- 存储/加密操作通过经过认证的本机接口适配；任务、元信息同步与账号语义留在 PrivateVault。
- 不把系统磁盘挂载作为播放前提。HTTP 读取/上传路线不要求先引入 FUSE/WinFsp；如果以后需要挂载，再核查对应依赖。
- 不接管用户已有 OpenList 实例的数据目录或修改其配置；验证用独立目录和端口。

**待验证**：macOS/Windows 实际系统版本和 CPU 架构、可执行文件分发与签名、端口冲突、应用退出后的进程行为、休眠后任务恢复、安装包升级对数据目录的影响。

Desktop README 提示其处于早期开发阶段；不能因为存在桌面包装层就把所有管理方法当作长期稳定的 SDK。[S5]

## 5. Android：内嵌核心路径已有直接依据

### 5.1 本地执行链

在 Mobile 快照中可以追到以下路径：

Flutter 界面 → MethodChannel 服务桥接 → Kotlin OpenListService → Kotlin OpenList 包装 → gomobile 生成的 Openlistlib → 本机 Go 核心。

- `ServiceBridge` 提供启动、停止、状态及地址等界面内桥接方法，并调用 Android 服务启动机制。[S6]
- Kotlin 包装配置数据目录并调用 Go 初始化/启动方法。[S7]
- Go 包装公开 Init、Start、Shutdown、IsRunning 等方法，调用 OpenList bootstrap。[S8]
- 构建脚本用 `gomobile bind` 生成 AAR/JAR，Android 构建配置引用这些库。[S2][S9]

**可以确认**：Mobile 具备在手机进程内承载 OpenList 核心的源码结构。无需把手机一律当作远程 Mac 的浏览器。

**不能确认**：本轮没有构建 APK，不能证明当前工具链、依赖、ABI、设备权限和驱动组合均可用。包装函数存在也不等于重新初始化、反复启停、错误退出及重启后恢复都没有问题。

### 5.2 百度与 Crypt 是否进入同一核心

Mobile 的设置包装导入核心 cmd 包；所查核心 cmd 导入 drivers，v4.2.8 的 `drivers/all.go` 同时注册百度网盘与 Crypt 驱动。[S10]

这给出“移动绑定能够沿着完整核心注册链取得两种驱动”的源码依据。初始化脚本拉取并合入完整核心，而不是本轮看到的一个仅含远程浏览功能的空壳。[S2]

仍须在具体构建中检查驱动实际可见、初始化和授权，以及是否有打包裁剪/依赖差异。不能仅凭注册 import 就声明具体手机账户端到端通过。

### 5.3 现成 App 与自有宿主不能混为一谈

Mobile 的 OpenListService 在 Manifest 中声明 `exported=false`，`onBind` 返回空；Flutter MethodChannel 是该 App 内部界面与原生层之间的桥接，不是已声明稳定的其他 App 控制 SDK。[S6][S11]

另外存在导出的 SwitchServerActivity，但源码行为是根据当前状态“切换启动/停止”；它不等同于幂等的“保证启动且返回受认证连接信息”协议。[S12]

因此不能承诺 PrivateVault 只要另装 Mobile，就自动拥有可靠的启动、关闭、身份注入和恢复能力。可选方式有：

| 路线 | 优点 | 代价与结论 |
|---|---|---|
| 连接已启动的独立 Mobile App | 早期样本验证较快，可先观察已有行为 | 用户可能要单独操作服务；跨 App 启停和权限没有稳定接口依据，适合验证候选 |
| 自有宿主内嵌核心库 | 可以把界面、文件权限、任务与核心生命周期统一管理 | 需维护 Android 绑定/服务适配；本报告优先建议评估 |
| 完整派生 Mobile 并增加 PrivateVault | 可复用现有 Flutter、桥接和部分界面基础 | 需评估许可证、维护范围与上游合并，不能认定改几页就完成 |

## 6. 加密上传与随机读取：复用核心而非重写密码学

所查 Crypt 驱动的上传方法先调用 rclone Crypt 的 EncryptData，再创建加密后的文件流并交给底层存储写入；没有 macOS/Windows 专属分支限制。[S13]

读取路径从下层存储取得 RangeReader，再调用可定位解密方法。它给出了随机读取的实现路径，也明确可能因下层驱动能力不足而报错。[S13]

据此可以形成设计判断：

- Android 本地加密上传有可复用基础，符合用户选择的三端独立目标。
- 需要复用固定版本的核心 Crypt；不要在 Dart/Kotlin/前端重新实现一份相同算法来追求“统一”。
- 可以采用普通库直接走存储访问、加密库经过 Crypt 的统一适配层。
- 密钥、salt、编码、文件名/目录模式和根目录必须在三端一致；相同配置仍须用样本互读确认。
- “存在随机解密方法”不等于“百度 API＋代理＋HTTP 响应＋播放器快进”全部通过；这些留给百度链路研究与样本验证。
- 上传流不自动保证零落盘、秒传或任意字节续传；底层缓存与重试成本仍待测。

## 7. 本机接口：可以隔离 UI 与核心内部结构

固定核心提交的路由中能确认下列接口组：[S14]

| 能力 | 源码确认的接口 | PrivateVault 使用边界 |
|---|---|---|
| 登录本机 OpenList | POST `/api/auth/login` | 与独立 PrivateVault 账号分开；不能直接拿中心账号令牌当本机管理员凭证 |
| 列目录/取得文件信息 | `/api/fs/list`、`/api/fs/get` | 路径、权限、签名链接及缓存语义须适配 |
| 上传 | PUT `/api/fs/put`、PUT `/api/fs/form` | 不是本站自定义接口；授权、请求头、大小与返回的完成含义须验证 |
| 配置存储 | `/api/admin/storage/create`、`update` 等 | 仅限受控本机管理路径；避免把整个管理权限暴露给不可信网页 |
| 文件内容访问 | GET/HEAD `/d/*path`、`/p/*path` | 明文长度/Range/签名与云端请求头逐项确认 |

代码还出现分片、任务、媒体库、播放进度等路由。它们是后续评估复用的候选，不代表现成语义已经满足 PrivateVault 的跨端资料区、普通/加密库和独立账号设计。尤其“已有媒体 API”不能直接推定元信息已在百度同步。[S14]

**建议**：将这些调用包在 PrivateVault 的 OpenListAdapter 中，固定版本并统一处理授权、路径、错误和能力检查。仅生命周期适配涉及平台原生层；业务 UI 不直接调用核心 internal Go 包。

OpenList Mobile 当前通过将包装放到核心源码模块中访问 internal 包来构建，并非提供了一份与上游实现完全解耦的稳定 SDK。把普通文件操作优先放在 HTTP 边界，有助于缩小未来升级需要修改的范围；这属于设计判断。[S2][S8][S10]

## 8. Android 下载：有 HTTP 文件传输基础，可靠归档仍需补齐

Mobile 的 DownloadManager 使用 Dart/Dio 下载；`downloadFileInBackground` 调用现有下载方法，任务主要存在静态 Map/List 中。[S15]

**可以复用或参考的基础**：HTTP 下载、进度、取消、通知、文件保存，以及部分 WebView Blob 下载衔接。

**本轮不能据此确认的能力**：

- Pixiv/hanime1 的来源识别、登录流程、作品解析和媒体地址提取。
- 应用进程退出后，完整恢复下载任务、归档步骤及原上传会话。
- 任意服务器都支持 Range 续传，或来源 URL 变化后可以安全拼接旧片段。
- 一次下载结束后自动完成探测、Crypt 上传、远端验证和资料提交。

方法名称里的“Background”以及 UI 不阻塞，只能说明这条调用采用异步流程，不能证明操作系统授予了无限后台运行时间。所查任务文件中的内存表也不能作为持久化归档队列的验收证据。

**PrivateVault 仍需的整合层**：设备本地持久任务状态、阶段检查点、工作文件登记、来源适配器、空间预留、上传对账、资料提交和幂等。首版任务继续由发起设备负责，符合 v0.2 已确认边界。

## 9. Android 上的下载器与媒体探测不能照搬桌面环境

桌面上调用下载器或媒体探测进程较直接；Android 应用必须考虑解释器、依赖、ABI、原生库、文件权限和生命周期。

CPython 官方文档明确区分 Android 与桌面使用方式：Android 的应用分发场景需要把解释器和依赖嵌入/打包到 App，并存在标准库限制；文档列出若干可用工具路线。[S16]

因此，不能从“Mac 能调用某 Python 下载器”推导“Android 可以运行相同命令而无需额外工作”。也不能据此说 Android 无法运行 Python。

待后续来源研究比较：

1. 使用平台可分发的原生/共享语言来源适配器，下载交给本机传输层。
2. 将成熟 Python 下载逻辑及运行时嵌入 Android，逐项核查依赖与接口是否可用。
3. 某些平台采用不同适配实现，但使用相同的作品描述、下载计划和归档接口，维持产品行为一致。

媒体时长、封面提取也需确认平台实现；首版不自动转码，不必先把桌面整套转码链作为手机必需依赖。具体探测库与支持格式还未选定。

## 10. Android 后台与播放：主要适配门槛

### 10.1 已有机制

所查 OpenListService 提供通知、可选 PARTIAL_WAKE_LOCK 和 START_STICKY 返回值；Manifest 把服务类型声明为 dataSync。[S11][S17]

这是后台服务管理的基础，不能单凭这些机制承诺永不停止。AOSP 的 Service 文档说明服务仍可能被系统回收；重启服务也不代表业务任务检查点自动恢复。[S18]

### 10.2 dataSync 存在时间限制

AOSP ServiceInfo 的文档对 dataSync 说明了从 Android 15 对应版本开始存在 6 小时时限；Service 的超时回调文档解释了滚动 24 小时窗口及回到前台等计时行为。[S18][S19]

这些源码足以否定“启用前台通知＋唤醒锁就可以无条件永久常驻”的假设。**不能直接断言所有手机或所有 APK 都在第六小时退出**：适用系统版本、target SDK、平台配置及实现处理方式仍需按实际验证环境确认。

Mobile 的 Gradle 配置中 compileSdk 为 35，targetSdk 取 Flutter 配置变量，minSdk 为 21；gomobile 绑定脚本另有自己的 androidapi 参数。它们不是同一个概念，不能只读取其中一个数值就认定实际安装包兼容范围或所有后台规则。[S9]

### 10.3 分场景判断

| 场景 | 本项判断 | 后续验证重点 |
|---|---|---|
| 用户打开应用发起本机上传/归档 | 有可行基础，值得优先推进 | 前台启动、进度、权限、空间、阶段恢复 |
| 切到其他应用或短时锁屏继续任务 | 条件可行，尚未验证 | 系统服务、进程/引擎状态、网络与厂商策略 |
| 长时间锁屏、音频持续播放 | 独立专项，不能用短播放通过代替 | 本地解密服务与播放器同时存活、媒体会话及系统服务类型 |
| 手机全天自动订阅 | 不能当前承诺持续常驻 | 周期调度、时间限额、用户停止后的规则、恢复和分配有效性 |

不把“关闭所有电池优化”作为唯一架构方案，也不修改用户系统设置来掩盖恢复缺失。设计上需要可中断、可恢复，明确哪些阶段正在运行，哪些在等待用户重新打开或系统允许执行。

### 10.4 播放入口证据与限制

Mobile WebView 指向本地核心地址；源码包含把 URL 交给 Android 外部应用选择器的路径。[S20]

这可作为本地内容服务＋内嵌/外部播放器的原型依据。但播放器能接收地址，不证明它能取得所需请求头、签名、格式、Range，或锁屏后本地解密服务继续运行。外部播放器播放与 OpenList 服务的生命周期仍要联合测试。

所查 Manifest 仅见 dataSync 服务类型，不能据此认定已具备完整的原生媒体会话与长期后台播放实现。是否增加媒体播放组件、采用什么播放器和合适的生命周期方案，留作后续设计及真机验证。

## 11. 文件与秘密保存：不能直接复制默认行为

### 11.1 下载目录与选择文件

现有下载管理器在 Android 上优先使用公共 Download 下的 OpenList 目录，并申请相关存储权限；Manifest 包含较宽的文件访问声明。[S11][S15]

这不满足“PrivateVault 的所有临时明文自动受专用工作区配额管理”的证明要求。建议 PrivateVault 使用自己的受控工作区，用户选择本地文件时通过平台文件访问机制取得授权；内容 URI、持续授权、流读取和大文件成本待验证。是否需要更广存储权限应由具体功能决定，不能因为参考项目申请了就默认必须申请。

Android 加密库的下载明文、封面生成输入和播放器缓存，都要计入临时文件/隐私设计；不能因为最终云端是密文就忽略本地暂存。

### 11.2 管理密码日志

**具体源码事实**：Mobile 的 Go 包装在 SetAdminPassword 中记录用户名和传入密码；Kotlin 包装将 Go 日志传给 Android 日志及日志记录入口。[S7][S21]

这不是对实际用户密码泄露的观察——本次没有运行或读取任何用户凭证。它意味着若 PrivateVault 复用这层包装，必须在实施时去掉/屏蔽秘密日志并验证日志链，不直接照搬。当前未修改上游或项目代码。

Crypt 的配置处理还使用 rclone obscure 做混淆；不能把这种保存形式等同于平台安全凭证库。PrivateVault 的本机管理凭证、百度授权、Crypt 参数和中心 PrivateVault 会话需要独立、受保护地处理。[S13]

## 12. 版本、构建与许可证约束

### 12.1 动态取最新版本不适合作为验收基准

Mobile 初始化脚本动态拉取上游标签，构建流程又分别获取版本信息。本轮没有执行这些脚本，也没有取得 AAR/APK。[S1][S2]

实际验证建议固定：核心提交、移动包装提交、前端资源版本、Go/gomobile/NDK/Flutter 工具链，以及设备 ABI。不能把 main、某标签、某次发布 AAR 和用户现装 App 的能力混称为同一版本。

所查移动 workflow 的 Go 设置与核心模块声明并不相同；Go 自动工具链机制是否介入、构建能否完成，本轮未验证。结论是需要锁定并核查工具链，不是已经证明构建必然失败。[S22]

### 12.2 许可证

所查核心和 Mobile 使用 AGPL-3.0 文本，Desktop 使用 GPL-3.0 文本。[S23]

这些不是禁止个人研究或复用的结论。若未来修改、分发客户端、提供网络服务或发布项目，需要针对实际组合履行相应义务并保留许可信息；不能仅因采用独立进程调用就默认所有许可证问题消失。本轮不作完整法律合规结论，也不需要为只读研究另行发布代码。

## 13. 候选整合方案比较与推荐

| 方案 | 三端独立目标 | 统一入口 | 主要成本 | 建议 |
|---|---|---|---|---|
| 现成 Desktop/Mobile＋PrivateVault 连接本地接口 | 可作为验证目标 | 依赖其他 App 的启动与配置，尚无稳定跨 App 管理依据 | 跨应用生命周期、权限和版本耦合 | 用于早期验证候选 |
| PrivateVault 自有宿主＋桌面进程/Android AAR＋本机接口适配 | 保留 | 最符合目标 | 原生生命周期、打包、任务与秘密保存 | **优先设计路线** |
| 分别完整派生 Desktop 和 Mobile | 保留 | 可做到，但两套现有界面技术不同 | 两套 UI/宿主维护、上游合并与许可 | 备选，先估维护成本 |
| 统一远程 Web＋中心执行 | 依赖中心在线 | 简单 | 改变三端独立归档目标 | 不作为已确认需求的替代结论 |

建议先锁定**核心和适配边界**，再选择 UI 框架：

- 存储与 Crypt：OpenList 固定版本核心。
- 本机通用操作：OpenListAdapter，面向 HTTP 文件/存储接口。
- 平台层：桌面进程管理；Android 库绑定、服务、文件权限和播放组件。
- 业务层：归档任务、资料库、元信息同步及独立账号。

Flutter 值得作为共享 UI 的优先候选，因为 Mobile 已有 Flutter＋Kotlin＋Go 绑定实例；但该项目本身没有证明 PrivateVault 所需 macOS/Windows 宿主已经一并完成。Tauri/Web UI 路线也须单独验证 Android 原生集成，不能把 Desktop 的 Rust/Vue 管理代码当作跨三端现成方案。[S5][S6][S9]

本报告不冻结最终 UI/下载器语言。后续来源研究会决定 Android 是否需要嵌入 Python、使用原生适配，或采用分平台实现；这会影响最终选型。

## 14. 可行性分级与阻断项

| 能力 | 现阶段等级 | 说明 |
|---|---|---|
| 桌面本机核心启动/停止 | 源码路径明确 | 官方 Desktop 有进程管理实现；未运行验证 |
| Android 本机 Go 核心 | 源码路径明确 | gomobile/AAR、Kotlin 与 bootstrap 链路可追踪；未构建 |
| Android Crypt 加密上传 | 有直接核心路径，需组合验证 | 不能因平台是手机就排除，也不能仅凭代码宣称已通过 |
| 三端统一基本文件接口 | 有接口基础，需适配 | 版本、凭证、路径、上传完成含义与 Range 待测 |
| 来源链接自动归档 | 尚未证实 | 下载器不等于来源解析器；下一研究项解决 |
| 重启后可靠任务恢复 | 需 PrivateVault 整合与验证 | 当前下载文件中的内存状态不是验收依据 |
| Android 长期后台/锁屏播放 | 条件性高风险，未验证 | dataSync 时限、系统回收和播放器配合 |
| 新设备统一账号自动恢复 | 本项未覆盖完整实现 | 本地管理接口不是中心账号与密钥分发的替代 |
| 三端元信息同步 | 本项未覆盖完整实现 | 现有媒体 API 不等同于云端库资料区同步 |

阻断性条件：Android 无法构建/注册必要驱动、无法在可接受的生命周期内完成本机归档、来源适配无法在手机运行、百度 Range/上传不可用、或核心接口不能安全满足所需操作。遇到这些情况应回到设计评估，不静默改成依赖 Mac 代执行。

## 15. 后续最小验证清单（计划，未执行）

先完成来源适配和百度链路两项只读研究，再收敛工具/样本/设备范围申请实际验证。以下不包含安装命令或实现代码。

| 编号 | 验证 | 通过条件 |
|---|---|---|
| V01 | 三端核心生命周期 | 记录固定版本与本机端点；启动/停止/重复启动/崩溃重启的状态准确 |
| V02 | 驱动与独立配置 | 三端实际看到普通百度及 Crypt 驱动；使用独立工作目录，不改变既有用户配置 |
| V03 | 本地文件上传 | 普通库和加密库各上传授权样本；不经 Mac 转发；远端读取与校验一致 |
| V04 | 手机独立性 | 已配置手机在 Mac 睡眠、账号服务关闭时，仍能完成已授权的本机读取与手动上传 |
| V05 | 核心接口适配 | 认证、建存储、列目录、上传、内容读取及错误处理符合固定版本契约 |
| V06 | Range 与播放器 | 冷缓存中尾部读取逐字节正确；拖动不先下载整个前缀；内嵌/外部播放器分别记录 |
| V07 | Android 生命周期 | 前台、切应用、锁屏、系统终止、重新打开分别测试；不能恢复时如实重试，不误报成功 |
| V08 | 长时间音频 | 本地解密服务与播放器联合验证约定时长；短样本通过不代替长锁屏行为 |
| V09 | 来源归档运行环境 | 后续选定适配器在三端完成解析→下载→上传；URL/授权过期可处理 |
| V10 | 空间/秘密 | 私有工作区配额、临时明文清理、日志脱敏、管理员密码设置及恢复材料不泄露 |

本研究形成时，测试设备的 Android 版本、厂商/型号、CPU 架构和可用空间尚未提供；不影响当时源码研究完成。

2026-10-28 设备更新：用户已提供一加 Ace 5 Ultra、Android 16、OpenList 移动端 `v4.2.5.26080717 (150)`，报告电脑备份导入后可浏览百度及原 Crypt 目录文件。对应公开版本已核对，见[Android 设备基线与 C1 提案](../validation/14-Android设备基线与最小验证提案-v0.1.md)。实际 ABI、可用空间及 Mac 休眠后的独立性仍未实测；手动配置迁移与 PrivateVault 自动配置/元信息同步分别验收。

## 16. 对 v0.2 的影响与下一项研究

本项支持保留 v0.2 的三端独立方向，不需要退回 Mac 唯一归档节点。需要在后续技术细化中明确“复用 OpenList 核心”与“依赖另装现成 App”之间的区别，并补足 Android 宿主和可靠任务层。

v0.2 中以下事项仍开放：Q01 Android 集成/生命周期，Q03 百度链路，Q04 账户恢复，Q05 元信息同步，Q09 空间与设备指标，Q11 锁屏/离线，Q14 版本分发。源码研究完成只推进 Q01 的证据收集，不等于关闭其运行验证。

推荐下一项：**Pixiv/hanime1 来源适配与 Android 下载运行环境研究**。它将直接影响是否嵌入 Python、是否需要不同平台适配器，以及最终客户端技术选择。随后完成百度授权/Crypt/Range 链路研究，再提交实际最小验证计划。

## 17. 关键证据链接

除特别说明外，链接均为本轮已读取的官方仓库固定提交；行号用于快速核对，不替代上下文。

- **S1**：[Mobile openlist_version](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/openlist_version)；本次标识 v4.2.8。
- **S2**：[初始化核心源码](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/openlist-lib/scripts/init_openlist.sh#L3-L27)、[gomobile 绑定](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/openlist-lib/scripts/gobind.sh#L64-L73)；仅阅读，未执行。
- **S3**：[Desktop 核心进程配置](https://github.com/OpenListTeam/OpenList-Desktop/blob/7efcb538e7128a3281011604146137c3d178b369/src-tauri/src/cmd/openlist_core.rs#L13-L69)。
- **S4**：[Desktop 子进程启动](https://github.com/OpenListTeam/OpenList-Desktop/blob/7efcb538e7128a3281011604146137c3d178b369/src-tauri/src/core/process_manager.rs#L522-L545)。
- **S5**：[Desktop README](https://github.com/OpenListTeam/OpenList-Desktop/blob/7efcb538e7128a3281011604146137c3d178b369/README.md#L16-L36)；早期开发提示、Tauri/Vue 及服务管理定位。
- **S6**：[Android ServiceBridge](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/android/app/src/main/kotlin/com/openlist/mobile/bridge/ServiceBridge.kt#L16-L105)。
- **S7**：[Kotlin OpenList 包装](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/android/app/src/main/kotlin/com/openlist/mobile/model/openlist/OpenList.kt#L28-L164)；初始化、日志回调与启动。
- **S8**：[Go 生命周期包装](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/openlist-lib/openlistlib/server.go#L28-L72)。
- **S9**：[Android 构建配置](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/android/app/build.gradle)、[Flutter 依赖](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/pubspec.yaml)。
- **S10**：[Mobile 设置包装导入 cmd](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/openlist-lib/openlistlib/settings.go#L3-L8)、[核心 cmd 注册 drivers](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/cmd/root.go#L3-L10)、[v4.2.8 驱动注册](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/drivers/all.go#L23-L32)；all.go 初次按 v4.2.8 标签读取，标签随后解析为此提交。
- **S11**：[Android Manifest](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/android/app/src/main/AndroidManifest.xml#L85-L90)；同文件包含权限声明。
- **S12**：[SwitchServerActivity](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/android/app/src/main/kotlin/com/openlist/mobile/SwitchServerActivity.kt#L15-L36)。
- **S13**：[Crypt 可定位解密](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/drivers/crypt/driver.go#L300-L307)、[加密上传](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/drivers/crypt/driver.go#L354-L381)、[配置混淆](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/drivers/crypt/driver.go#L85-L95)。
- **S14**：[HTTP 路由](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/server/router.go)；认证 75—82、媒体 136—156、存储 188—201、文件/上传 279—310 行。接口参数和处理器语义尚未逐一验收。
- **S15**：[DownloadManager 内存状态](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/lib/utils/download_manager.dart#L81-L96)、[异步下载入口](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/lib/utils/download_manager.dart#L239-L247)、[默认下载目录](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/lib/utils/download_manager.dart#L429-L464)。
- **S16**：[CPython Android 使用文档](https://github.com/python/cpython/blob/main/Doc/using/android.rst#L7-L24)；main 文件 blob 见第 3 节；不是下载器兼容证明。
- **S17**：[OpenListService](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/android/app/src/main/kotlin/com/openlist/mobile/OpenListService.kt)；onBind 70、唤醒锁 122—133、onStartCommand/START_STICKY 279—295、startForeground 431 行。
- **S18**：[AOSP Service 文档](https://github.com/aosp-mirror/platform_frameworks_base/blob/main/core/java/android/app/Service.java#L210-L253)、[超时与时间窗口](https://github.com/aosp-mirror/platform_frameworks_base/blob/main/core/java/android/app/Service.java#L1198-L1224)；main 文件 blob 见第 3 节。
- **S19**：[AOSP dataSync 类型说明](https://github.com/aosp-mirror/platform_frameworks_base/blob/main/core/java/android/content/pm/ServiceInfo.java#L141-L173)；main 文件 blob 见第 3 节；具体适用条件仍需对照验证设备和 target SDK。
- **S20**：[本地 WebView 与外部打开路径](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/lib/pages/web/web.dart#L315-L321)、[下载/外部应用选择](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/lib/pages/web/web.dart#L528-L566)。
- **S21**：[设置管理员密码时的日志调用](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/openlist-lib/openlistlib/settings.go#L26-L40)。
- **S22**：[Mobile 构建 workflow](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/.github/workflows/build_openlist.yaml#L55-L88)、[核心模块工具链声明](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/go.mod#L1-L5)。
- **S23**：[核心许可证](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/LICENSE)、[Mobile 许可证](https://github.com/OpenListTeam/OpenList-Mobile/blob/585b70898cc30587d535f93d1f4ee383ae8d0646/LICENSE)、[Desktop 许可证](https://github.com/OpenListTeam/OpenList-Desktop/blob/7efcb538e7128a3281011604146137c3d178b369/LICENSE)；本轮核对了许可证标题与版本，不是完整法律审查。

## 18. 完成记录

- 已完成：本项关键调用链、现成能力、缺口、候选整合方式、版本边界、后续验证条件的文档研究。
- 未完成且未声称完成：安装、构建、模拟器/真机、百度授权、样本上传/解密/播放、来源适配、跨端验收及实现。
- 本次变更范围：仅本研究文档。项目原有设计文档保留，当前仍处于设计与可行性研究阶段。
