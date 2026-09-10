# 0.1.0.15 新图标版沙盒验收

更新日期：2026-09-10。用户在原 Windows 沙盒中完成正常覆盖升级，开发代理只读核对共享输出。部署检查通过；用户随后确认安装向导、新图标、一级菜单和一次 ZIP 解压均正常。后续已于当日 20:16 公开预发布，见[发布记录](PUBLICATION-0.1.0.15.md)；此操作没有新增或改变测试结论。

## 固定安装包与环境

- 安装包：`SmartZipSetup-0.1.0.15-test.exe`，15,153,232 字节。
- SHA-256：`1AED980A38A21BFC5BC3C92410C5895A2B852F6E2680454AEAECDA9D5F815E2D`。构建、沙盒输入和本地发布附件为同一产物，没有重新打包。
- 来宾：Windows 11 Enterprise 24H2 x64，26100.9278，`EnableLUA=0`。本轮不能代表普通启用 UAC 的新用户环境。
- 起点：已完成卸载后重装及功能确认的 `.14`，安装根目录为 `C:\SmartZip`。本轮没有先卸载、手工清理、补注册或导入证书。
- 入口：`tests/SandboxFunctional/Run-Icon-Upgrade.cmd` 及配套 PowerShell 脚本；只在沙盒内启动一次普通交互安装。

## 15:03 部署证据

采集目录：`build/sandbox-rollback-0.1.0.14/Output/normal-upgrade-0.1.0.15/`。目录名保留最初沙盒映射版本，当前验收目标为 `.15`。

| 检查 | 结果 |
| --- | --- |
| 安装器与采集器退出码 | 均为 0；`DeploymentChecksPassed=True` |
| 产品状态、卸载项、Package | 均为 `0.1.0.15`；版本路径 `C:\SmartZip\Versions\0.1.0.15` |
| Package 健康 | `Status=Ok`；助手健康检查无 Modified、NeedsRemediation、Tampered 或 PartiallyStaged |
| COM 与现代菜单声明 | 预期 Packaged COM 类存在；manifest 的 COM 类与 SmartExtract 菜单声明指向同一 CLSID |
| 提交完成 | 助手日志包含 `UPGRADE_PREPARED`、`COMMITTED`、`FINALIZED` |
| 新图标 | 已安装 ICO 的 SHA-256 与构建资源一致：`0F0F2E6467718761368A37273D965D70A59AE6C485398FE62C9C4B228DB8CED5` |
| 原文件与配置 | 独立比较 `.14` 的 132 个文件，差异 0；用户配置 SHA-256 未变 |
| 证书 | 前后状态未变；项目公钥仍只物理存放于 LocalMachine\TrustedPeople，无私钥；LM/CU Root 均无项目证书 |
| Explorer | 升级前后采集的 PID 和启动时间相同；本轮未新增独立 Event Log 采集 |

CurrentUser\TrustedPeople 的逻辑视图可见该证书，但物理键不存在，不能据此认定重复导入。项目保留原有证书所有权标记。

本轮采集器读取实际 `C:\SmartZip` 的前后文件清单，补充了该目录的证据；不回写或改变 `.14` 重装采集器当时未覆盖新目录的历史限制。

原始文件保留在本机，不上传设备日志或恢复资料：

- `before.json` SHA-256：`3020F446A3EE4D28DB5A10795887C3FE10694D215FCD51319C53AB18EBAA4F89`。
- `result.json` SHA-256：`787DFFDFC6B447654BB6196C2EFBC7A14AE37F9277B51C38A5534102D19EE17B`。
- `logs.json` 列出的 5 个助手日志已逐一核对大小与 SHA-256，均匹配；Inno 日志保留为 `upgrade-inno.log`。

## 用户界面与功能确认

用户在部署核验后回复“都是正常的”，对应以下三项：

1. 安装向导中文及新 Logo 显示正常。
2. 开始菜单和一级右键菜单图标正常，“智能解压”仍可见。
3. 按建议将可信 ZIP 放入新的临时目录，通过右键“智能解压”成功解压。

这三项记为用户实际操作确认，不声称开发代理自动点击了菜单、另行校验了解压文件哈希或完成多 DPI/全主题显示测试。`.14` 的完整格式、多选、卸载重装与四项故障测试保留原结论，本轮没有重跑，也不将它们标成 `.15` 的独立重测结果。

## 发布边界

用户已确认公开发布 `.15` 预览版；安装包与本轮验收产物一致。正式可信签名、当前版本普通启用 UAC 的新用户环境、GitHub 更新提示到静默安装的端到端链路和公共 WinGet 仍未完成。当前更新器忽略草稿与 Pre-release，不会因发布测试版而提示自动更新。

继续保留沙盒和 `.15` 安装状态。发布操作不应触发主机或沙盒的再次安装、卸载、清理或系统设置更改。
