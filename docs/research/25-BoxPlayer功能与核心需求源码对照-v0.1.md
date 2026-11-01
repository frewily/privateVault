# BoxPlayer 功能与核心需求源码对照 v0.1

- 调研日期：2026-10-30。
- 公开仓库：[gaozhangmin/boxplayer](https://github.com/gaozhangmin/boxplayer)。
- 固定版本：[f926398d093a5eae96a4bff1015b313acc883950](https://github.com/gaozhangmin/boxplayer/commit/f926398d093a5eae96a4bff1015b313acc883950)，提交时间 2026-10-29 08:57:39 UTC。
- 核查范围：完整文件树、51 个文件的源码/文档静态阅读，以及关键词检索；文件与 Git blob 摘要见 [调研快照](25-BoxPlayer源码调研快照.json)。
- 本轮只做公开源码阅读与项目文档调整；未安装依赖、构建或运行 BoxPlayer，未读取本机应用配置、账号、收藏列表或凭证，未执行云端操作。
- 用户截图证明安装应用有该加解密界面；截图本身不能证明加解密、百度上传或定时归档执行成功。尚未确认所安装应用版本与此源码快照一致。
- 此文是替代方案评估与后续参考索引，不代表对其全部功能、安全性或移动端的完整审计。

## 1. 决策摘要

**建议将 BoxPlayer 作为功能与实现参考，暂不以它替换 PrivateVault，也不直接整仓 fork。**

理由不是它没有自动化：源码确实包含影视获取、追更、定时巡检、暂存目录、持久化任务、租约和重试。真正差异在自动化对象与加密体系：

1. 它的追更围绕 TMDB 影视条目、季集和缺集补齐；未找到 Pixiv 收藏列表解析、分页游标、作品级增量归档与对应作者/标签元数据链路。
2. 截图入口对应自有 FlowEnc 文件转换；不是 OpenList 使用的 rclone Crypt。相同密码不能让两者直接互读。
3. 百度上传分支读取本地文件分片上传；已读链路未接入 FlowEnc。把手动加密后的文件作为普通文件上传，与“来源订阅自动加密归档”是两回事。
4. WebDAV/AList 在能力清单中明确为浏览、下载、播放、扫描和刮削用途，不支持写操作；不能直接承担我们通过 OpenList Crypt 上传的完整写入链路。
5. 该仓库主要是 Electron 桌面客户端；不能从这里推导 Android 与桌面功能一致或已实现三端独立 Crypt。

这些证据足以得出“目前不能证明可以直接替代核心需求”，不等于断言它所有版本、服务端或第三方插件永远无法补齐。

## 2. 功能清单与证据等级

“源码有实现”表示看到具体路径/调用，不表示本次在真实账号、网络或设备上运行成功。README 声明与移动端能力单独看待。

| 功能域 | 当前公开证据 | 与 PrivateVault 的关系及限制 |
|---|---|---|
| 多云盘账号、目录和文件管理 | README、各 provider 目录、能力注册表有实现 | 重叠较大；不同云盘的写入、分享、回收站并不相同 |
| 百度文件上传 | uploader → providerUpload → BaiduUploadDisk → 分块 API；有分片重试、MD5 与预上传 | 可参考上传分层；不是本轮真实百度业务成功 |
| 影视媒体库、扫描、刮削、收藏、播放列表、续播 | README、mediaLibraryBootstrap、medialibrary store 有实现 | 浏览与播放部分重叠；主要影视模型不等于作品/多图/ASMR 收藏模型 |
| 指定目录与来源扫描 | AList 添加表单有 rootPath；音乐/书籍扫描器有指定目录入口 | 与用户指定目录接入一致，可借鉴交互与限速设计 |
| 音乐库、歌曲/歌手/专辑、歌单 | README 与 musicScanner 代码 | 可参考；ASMR 的作者、系列、作品来源等需自己建模 |
| 电子书、阅读、AI 阅读 | README 与 bookScanner 代码 | 已有功能域，当前 PrivateVault 无需照搬 |
| 视频播放与外部 MPV/IINA | README、proxyhelper 的媒体代理与 Range 分支 | 可参考协议/错误处理；本次未验证播放质量或 Range 全部边界 |
| Jellyfin/Emby/Plex、WebDAV/AList | README、服务接入 UI、providerCapabilities | 可作为播放入口候选，需单独验证 OpenList 兼容 |
| 外链下载 | UrlDownloadModal 接受 HTTP(S) 和可选请求头；调用 DownDAL 创建下载任务 | 接受 URL 不等于解析网页作品、收藏分页、原图及元数据 |
| 本地文件加解密 | RssJiaMi → DoJiaMi → FlowEnc | 与截图对应；自有格式，不兼容 rclone Crypt |
| 流式加密上传 | AliUploadDisk 内使用 getFlowEnc / encryptBuff | 已读调用在阿里上传路径；不能推广为百度、所有 provider 或移动端 |
| 加密媒体代理与定位 | proxyhelper 调用 decryptTransform、setPosition(start) | 有自有格式解密代理代码；不代表支持 rclone 密文 |
| 自动获取与定时追更 | mediaAcquisition 类型、workflowRunner、tracking、主进程 wake scheduler | 确实有；面向影视季集，且执行入口有 Pro 判断 |
| 持久化任务、状态、事件、重试与执行租约 | MediaAcquisitionDb、Service、workflowRunner | 高价值参考；租约是本地数据库执行协调，不能当成跨设备执行设备切换协议 |
| CLI / MCP | 独立 CLI README 声明文件管理边界 | 顶层 README 的整理能力表述更宽；按独立文档与实际 schema 核对，不预设可操控全部媒体流程 |
| 图片作品库、Pixiv 收藏订阅 | 本次未找到专用实现 | 不能以普通文件浏览或影视海报替代完整图片收藏体验 |
| hanime1 来源下载 | 未找到目标站适配；搜索 hanime 命中 searchAnime 方法名 | 不能把动漫搜索/弹幕能力算作该来源下载能力 |
| 三端统一同步、Crypt 恢复材料 | 未确认满足 PrivateVault 协议 | 本地数据库/同应用窗口同步不能证明跨设备同步；未验证移动客户端 |

## 3. 截图的“加密”为何不一样

密码只是输入之一。能否互读取决于密钥派生、内容格式、分块与认证、文件名/目录名规则；并不是都填写相同密码就兼容。

### 3.1 截图实际对应的实现

- RssJiaMi.vue：输入/输出均为本地目录，选 AES-CTR 或 RC4-MD5，可选名称转换；“私密”模式将当前 user_id 作为密码输入。
- DoJiaMi：枚举本地文件，创建 FlowEnc(password, encType, size)，通过 Node 流转换写入输出文件。
- 默认 breakSmall 为 true，实现条件是文件大小 **大于** 5 MiB 才入选；因此图片小样本可能被跳过，不能以“点了执行却没输出”判断格式。
- 文件名使用 MixBase64 与 CRC6 自有编码；保留扩展名；目录层级在该工具里保持原路径。
- AES 分支使用 aes-128-ctr，以及其自有 PBKDF2/MD5/文件长度派生；没有看到该分支输出内容认证标签的流程。
- “私密”的 user_id 绑定是应用逻辑，不应等同于硬件密钥、不可迁移的设备身份或独立秘密。
- 源码的说明文字带有“其他软件无法解密”等表述；调研只采信实际格式与算法，不能据此认定只能由本软件恢复。

### 3.2 与当前 OpenList Crypt 对照

本项目固定的 OpenList v4.2.8 源码 driver.go 直接导入 github.com/rclone/rclone/backend/crypt，使用 rcCrypt.NewCipher、EncryptData、DecryptDataSeek，以及文件/目录名加解密。meta.go 提供 password、salt、文件名模式、目录名模式、编码、suffix 等参数。

| 项目 | BoxPlayer 截图工具 | PrivateVault 既定路径 |
|---|---|---|
| 格式实现 | FlowEnc 自有实现 | OpenList 调用 rclone Crypt |
| 密钥输入 | 手动密码或其用户 ID 逻辑，结合算法与文件长度 | 完整 Crypt profile：密码/salt/命名与编码参数 |
| 名称转换 | MixBase64 + CRC6，工具中保留扩展名 | rclone 的名称与目录规则 |
| 互通结论 | 该链路输出不是 rclone Crypt 数据 | 不能直接拿 BoxPlayer 密文交给既有 Crypt 挂载解密 |
| 接入办法 | 可另做格式适配，或先本地解密再按 Crypt 重新加密 | 这会新增迁移、安全与验证成本，本轮不实施 |

这里针对已读的截图加密路径做格式判断，没有执行跨软件互解实验，也没有审计所有加密分支。暂不采用其自有算法替换已经确认的 Crypt 方案。

来源：
- [RssJiaMi.vue](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/rss/rssjiami/RssJiaMi.vue)
- [jiami.ts L51–81](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/rss/rssjiami/jiami.ts#L51)
- [AES-CTR 实现 L13–29](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/module/flow-enc/lib/aesCTR.ts#L13)
- [名称编码](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/module/flow-enc/utils.ts#L27)
- [OpenList Crypt 驱动](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/drivers/crypt/driver.go#L24)、[配置字段](https://github.com/OpenListTeam/OpenList/blob/25e4eb663ffb73991a68d85df4f690d48ad137a6/drivers/crypt/meta.go#L7)

## 4. 核心问题：Pixiv 收藏链接能否定期拉取并加密归档

### 4.1 已有自动化到底做什么

静态调用链：

影视目标（movie/tv/anime、tmdbId、season、missingEpisodes）
→ 持久化获取任务
→ 到期巡检/检查已播集与目标目录已有集
→ 搜索资源候选
→ 分享转存 / magnet / HTTP 云离线
→ 回读落盘文件与季集覆盖
→ 目录整理、媒体索引、通知。

关键限制：

- shared/types/mediaAcquisition.ts 的 Target 和 Tracking 以影视、季集建模，没有收藏页、作品 ID、收藏游标等字段。
- tracking.ts 默认巡检时刻是北京时间 06:00、21:00；支持配置时刻，最多六个。**8 秒 runner 轮询与 60 秒主进程唤醒不是来源抓取周期。**
- workflowRunner 的执行与巡检入口均检查 isPro；公开 README 里的“核心功能可用”不能推导这个追更入口免费可用。
- worker 位于 Electron renderer，主进程每分钟发 wake；存在数据库租约、续租、重试字段，但电脑睡眠/应用退出时本机定时器不会继续执行。代码不能证明 VPS 无头运行或手机后台常驻。
- HTTP 候选允许提交一般 URL，但执行器将其作为网盘 HTTP 离线任务；只允许 115、光鸭、PikPak、123 等指定平台。**这不是 Pixiv 网页解析器，也不包含百度。**
- 搜索候选使用应用配置中的后端资源搜索接口；未审计其私有服务端，不能据此承诺私有收藏可被安全解析或支持任何站点。
- 已读 workflowRunner/执行器没有看到 FlowEnc/Crypt 加密处理步骤。
- “verifying”主要核对落盘、文件及集数覆盖，不等于本项目要求的完整解密回读 SHA-256。

### 4.2 对主人目标的逐项判断

| 必要环节 | 本次证据 | 判断 |
|---|---|---|
| 输入本人可访问的 Pixiv 收藏列表 | 搜索 pixiv 未命中；已读类型/解析器没有专用入口 | 未找到实现 |
| 使用来源授权读取私有/公开收藏 | 未找到 Pixiv 登录上下文及收藏分页处理 | 未验证，不能假定 |
| 分页、作品/多图/动图资源展开 | 未找到对应来源适配 | 未找到实现 |
| 定期检查新增收藏、按作品 ID 幂等 | 有影视追更；没有看到收藏游标/归档账本 | 已有机制不能直接替代 |
| 下载原始资源并提取作者/标签/来源 | 有通用下载，不等于作品元数据适配 | 未找到目标链路 |
| 加密并上传百度指定目录 | 有独立本地加密和普通百度上传，未见自动衔接 | 未证明目标闭环 |
| 完整回读校验后提交元数据 | 有影视落盘核验，未见对应 Crypt 哈希校验 | 未找到目标闭环 |
| 别的设备独立解密并同步资料 | Electron 实现不能证明 Android/Windows 全部行为 | 需另验 |

**结论：在固定公开版本中，未找到可满足“Pixiv 收藏链接→定期增量拉取→Crypt 加密→百度归档”的完整实现。不建议把继续找一个隐藏开关当成当前路线。**

检索说明：检查了完整文件树和相关模块，GitHub 索引检索 pixiv/rclone/gallery-dl/yt-dlp 均为 0；hanime 命中两处 searchAnime 函数名称，并非 hanime1 适配。索引检索可能漏掉泛化插件、外部服务与动态能力，负面结果不构成全版本绝对不存在的证明。

来源：
- [类型与状态](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/shared/types/mediaAcquisition.ts#L1)
- [runner 与 Pro/巡检入口 L66–170](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/services/mediaAcquisition/workflowRunner.ts#L66)
- [巡检时刻与缺集计算](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/services/mediaAcquisition/tracking.ts#L13)
- [HTTP 执行器 L47 起](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/services/mediaAcquisition/magnetExecutor.ts#L47)
- [搜索候选](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/services/mediaAcquisition/agent.ts#L1)
- [主进程唤醒](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/electron/main/mediaAcquisition/MediaAcquisitionWakeScheduler.ts#L1)

## 5. 百度上传、OpenList 接入与平台边界

### 5.1 百度不等于所有能力自动具备

- StartUpload 对非阿里 provider 走 uploadProviderFile 后返回；百度分派到 BaiduUploadDisk。
- BaiduUploadDisk 计算本地原始文件 MD5 和分片列表，readSlice 读取本地原始数据，再调用百度上传 API；未见加密转换。
- AliUploadDisk 则显式调用 getFlowEnc / encryptBuff。不能混用两个 provider 的结论。
- 百度能力声明按默认规则得到 upload.encrypted=false、offline.http=false、offline.magnet=false、share.import=false。该声明与已读执行分支相互印证。
- 可以手工加密文件后普通上传；但仍需另证自动识别密文、播放、跨端互读和恢复，不是当前产品核心链路已经完成。

来源：[uploader L35–70](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/workerpage/uploader.ts#L35)、[百度上传](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/cloudbaidu/uploaddisk.ts#L40)、[阿里加密上传](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/aliapi/uploaddisk.ts#L24)、[能力默认值](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/services/agent/providerCapabilityTypes.ts#L32)、[百度覆盖项](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/cloudbaidu/capabilities.ts)。

### 5.2 BoxPlayer + OpenList 仍可作为未来播放候选

- 能力清单把 AList 归到 WebDAV，明确“仅用于浏览、下载、播放、扫描和刮削，不支持任何写操作”。
- 若接入各设备自己的本地 OpenList 解密视图，理论上可由 OpenList 提供明文读取，BoxPlayer 无需自己支持 Crypt。
- 但需验证 Android 能否配置本机地址、两应用生命周期、播放请求头/签名、Range、文件类型与元数据映射。
- 不能把连接 Mac 上服务当成手机独立解密；也不能从桌面表单推断手机支持。
- 仅作为将来 W05 播放实现时的候选比较，不在本轮修改既定客户端架构。

来源：[能力注册表](https://github.com/gaozhangmin/boxplayer/blob/f926398d093a5eae96a4bff1015b313acc883950/src/services/agent/providerCapabilities.ts#L18)。

## 6. 可借鉴的实现索引

| 遇到的 PrivateVault 问题 | 优先查看的 BoxPlayer 模块 | 借鉴范围与须改造处 |
|---|---|---|
| 网盘能力不同，界面/任务误用操作 | services/agent/providerCapabilities、providerCapabilityTypes；各 provider/capabilities | 学习声明能力与证据等级；仍需我们自己的 StorageProvider 合同 |
| 任务抢占、重启恢复、重复执行 | electron/main/mediaAcquisition/MediaAcquisitionDb；workflowRunner | 参考持久状态、worker lease、next_attempt_at；按实际副作用设计幂等和恢复 |
| 上传结果不确定、任务残留 | mediaAcquisition/staging、shareExecutor、magnetExecutor | 参考提交意图与落盘回读；不要照搬自动删除暂存目录行为，须符合我们默认保留云端政策 |
| 入库前校验、整理和索引 | targetSnapshot、organizer、workflowRunner | 参考分阶段提交；补完整哈希、作品级账本和冲突规则 |
| 指定目录扫描、取消与限速 | musicScanner、bookScanner、mediaLibraryBootstrap | 参考交互与扫描协调；目录索引增量不等于来源订阅增量 |
| 资料库、来源归属、播放列表 | store/medialibrary、mediaSourceMembership | 参考表现与缓存；不把本地/多窗口同步当作云端多设备冲突解决 |
| 音视频 Range 和请求头 | utils/proxyhelper、proxyHeaders、media-server 播放代码 | 参考协议边界和回归场景；按我们本机安全边界重新实现 |
| 后台停止、恢复唤醒 | MediaAcquisitionWakeScheduler、workflowRunner | 可参考生命周期问题；不能照搬桌面 renderer 到 Android 后台 |
| 云盘分片上传 | cloudbaidu/upload、uploaddisk；providerUpload | 参考 provider 分层与错误解释；我们仍以 OpenList 为存储执行核心 |
| 加密实现 | module/flow-enc | 用于理解格式差异，不采用其算法替换 rclone Crypt |

附加判断：
- 本地加密工具在 readStream 的 end 事件里 rename，而非等待目标写流 finish；错误事件/清理与并发统计也需要进一步审查。它是功能存在的证据，不宜当作可直接复制的可靠模板。
- AES-CTR 分支的密钥/IV派生及无内容认证流程，不作为 PrivateVault 的安全方案依据。这不是对整个产品的渗透审计或实测漏洞报告。
- 仓库 LICENSE 与 package.json 标注 GPL-3.0。参考行为和思路与直接复制代码分别处理；若以后复制、修改并分发代码，先核对相关文件/依赖许可、版权标注和对应源码提供义务。本轮没有把第三方实现复制进产品。

## 7. 计划调整记录

本轮按主人要求，将“先核查 BoxPlayer 源码与功能，再决定是否替代”的评估插入实施前。

| 工作项 | 当前处置 |
|---|---|
| 已完成 W01-M | 保留实现和已有验证，不重复测试 |
| W01-A | 保留提案，研发仍待批准；本轮不下载工具链或写 Android 实现 |
| BoxPlayer 评估 | 完成本轮公开源码级对照；推荐作为参考仓库 |
| 产品核心目标 | 保留来源收藏增量归档、可选 Crypt、百度指定目录、媒体元数据与三端独立访问 |
| 下一实施路线 | 如主人接受本结论，回到既定 W01-A → W02 顺序；不因本次调研自动授权实施 |
| 来源可行性未决项 | Pixiv 收藏的授权/分页/增量/多资源展开，以及 hanime1 来源支持仍需独立验证；不能因为 BoxPlayer 不覆盖就假定 PrivateVault 已能实现 |
| Owner 学习安排 | 只需要审阅核心结论与决定取舍；不要求阅读本报告列出的源码 |

本报告不把来源订阅静默提前并入 W01-A，也不删除现有整体阶段安排。若希望提前验证来源适配，可单独提出一个有输入样本、授权边界和验收条件的小工作包。

## 8. 若以后要做实机补充验证

这不是本轮必须执行的安装任务，也不要求主人现在重新输入账号。

1. 先记录主人已安装应用的平台、版本与构建号，再与公开源码对应。
2. 若只评估播放复用：用合成素材和只读测试目录验证本机 OpenList 接入、图片/音视频、Range 和断开 Mac 后独立读取。
3. 若要挑战“收藏归档无现成支持”的结论：必须看到明确的收藏订阅入口/官方说明，随后用本人合法可访问的小收藏样本跑两轮，第二轮新增一件作品；核对幂等、元数据、加密百度目标和失败恢复。
4. 不用真实全量收藏做第一次测试，不把 Cookie、密码、账号备份放入调研文档。
5. 目前核心差异已有足够静态证据，无需为证明“缺少功能”而上传真实资料或购买 Pro。

验收要求是“作品实际新增并在另一设备独立解密读回，元数据与来源一致”，不是出现订阅标签、任务入队或 HTTP 200。
