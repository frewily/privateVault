# Android OpenList 包装

自有 Go 包装叠加至固定 OpenList v4.2.8 源码模块的 `privatevault/pvcore/`，以合法导入其 internal 包。上游提交、驱动集合及构建版本见 `toolchains/w01-android.json`。不执行 Mobile 初始化脚本，不复制其密码日志实现，不修改 Crypt 算法。

`pvcore.go`、`overlay/op/` 启动限制和无脚本占位静态资源为本项目新增；上游 OpenList 源码及 AGPL 许可保存在 `.tools/src/openlist-v4.2.8/`，构建时保留来源与叠加摘要。运行时注册表只允许 Local、BaiduNetdisk、Crypt；注册百度/Crypt 驱动不代表接入账号或验证云端业务。上游离线工具和搜索仍间接编译了额外驱动包，不能将本 AAR 称为仅含三种驱动的严格裁剪构件；完整编译裁剪尚未完成。未决定仓库整体公开许可，不对外发布。

Go 运行时仅由 Android 的 `:pv_core` 服务进程加载，每进程只允许初始化一次。凭证结果（包括用于本次HS256实例证明的签名密钥）仅交给 Kotlin 服务，禁止进入 Flutter、HTTP请求、普通日志与证据文件。停止之后须结束自有服务进程，不能调用 Start 重用 Go 全局状态。

当前AAR/APK构建、ELF/ZIP对齐、目标Kotlin编译及主机检查已通过，Owner另反馈首次手机启动/读图、三轮启停和后台返回成功，完整进程/故障矩阵仍未独立验证。构建结果见 `docs/validation/29-W01-A构建验收结果-v0.1.md`，用户反馈见报告30，报告27保留早期停止语境。源码或主机检查通过不代替对应设备验收。
