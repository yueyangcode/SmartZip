# SmartZip 0.1.0.15 公开预览版

在 Windows 11 一级右键菜单中选择「智能解压」。内置 7-Zip 解压引擎，无需另装 WinRAR 或 7-Zip，可与已有压缩软件共存。

这是自签名开发测试版（Pre-release），适合愿意接受测试证书和已知限制的用户；不是稳定版。

## 下载与安装

适用于 **Windows 11 x64，Build 22621 或更新**。安装向导和菜单使用简体中文；本版不提供 ARM64、macOS 或 Linux 安装包。

下载本页 Assets 中的 **`SmartZipSetup-0.1.0.15-test.exe`** 和 `SHA256SUMS.txt`。`Source code` 是源码，不是安装包。

1. 核对 SHA-256 后运行 EXE。
2. 选择父目录，安装向导会补齐 `SmartZip` 文件夹，仅为当前用户安装。
3. 右键压缩包 →「智能解压」。设置与正常卸载入口位于开始菜单的 SmartZip 文件夹。

首次安装需要你同意添加项目专用测试证书。证书助手可能请求管理员权限，将公钥证书加入“本地计算机 → 受信任人”（`LocalMachine\TrustedPeople`）；不会写入 Root 或导入私钥。这会改变设备的证书信任配置，请阅读安装提示。安装前已有的证书不接管，卸载按项目所有权和共享情况处理。

证书 Subject：`CN=SmartZip Modern Evaluation`；指纹：`A1709CED9DB02150E2FB40CE6496BD1938D89195`。遇到 Windows 安全提示请先核验下载来源，不要关闭安全保护。

## 本版更新与验证

- 换用 Win11 风格图标，统一安装向导、开始菜单和「智能解压」右键菜单。
- 保留中文安装、自选父目录、多选及中文/空格/特殊字符路径支持。
- 相比 `.14`，本版未改变解压、权限、升级回滚和更新器逻辑。`.14` 的格式测试、故障回滚、卸载与重装记录继续保留。
- `.15` 已完成构建与离线检查、沙盒内 `.14 → .15` 覆盖升级检查；用户确认新图标、菜单及 ZIP 解压正常。本轮没有重跑 `.14` 的全部测试。

验证范围与限制见 [`.15` 验收记录](https://github.com/yueyangcode/SmartZip/blob/main/docs/SANDBOX-0.1.0.15-ACCEPTANCE.md) 和 [`.14` 验收记录](https://github.com/yueyangcode/SmartZip/blob/main/docs/SANDBOX-0.1.0.14-ACCEPTANCE.md)。

## 升级与已知限制

- 健康的 `0.1.0.8` 至 `0.1.0.14` 测试版支持同目录、同证书升级；安装器检查不通过会停止。已装 `.15` 无需重装，同版覆盖、降级和目录迁移不支持。
- 本轮沙盒关闭了 UAC（`EnableLUA=0`）。当前版在普通启用 UAC 的新用户环境，以及 GitHub 更新提示到静默安装的完整流程仍待验证。
- 当前更新器忽略预发布，本次发布不会触发自动更新提示。公共 WinGet 包尚未提供；测试版到未来正式证书版本不支持自动迁移。
- 安装或卸载报错时，请保留弹窗所示日志并到 [Issues](https://github.com/yueyangcode/SmartZip/issues) 反馈版本、错误码和复现步骤。分享前隐去个人用户名和路径。请使用正常卸载，不要手工删文件、补注册或改证书。

## 文件校验

文件大小：15,153,232 字节（14.45 MiB）。安装包与已验收产物一致，未重新打包。

```text
1AED980A38A21BFC5BC3C92410C5895A2B852F6E2680454AEAECDA9D5F815E2D  SmartZipSetup-0.1.0.15-test.exe
```

对应源码：[`8b26169`](https://github.com/yueyangcode/SmartZip/commit/8b2616900f9fa6e5d2671527a9b531c1c239b501)。第三方许可证及对应上游源码随安装包提供，见 [第三方声明](https://github.com/yueyangcode/SmartZip/blob/8b2616900f9fa6e5d2671527a9b531c1c239b501/ThirdPartyNotices.md)。

**English:** Windows 11 x64 (build 22621+) preview, with a Simplified Chinese UI. Download the EXE under Assets. Installation requires consent to trust a project-specific self-signed test certificate in LocalMachine TrustedPeople and may request administrator permission. This is not a stable release; automatic update prompts and a public WinGet package are not available for this preview. See the [English README](https://github.com/yueyangcode/SmartZip/blob/main/README.en.md).
