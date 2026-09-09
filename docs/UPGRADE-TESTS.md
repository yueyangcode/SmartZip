# 0.1.0.11 覆盖升级验收

本机已完成健康 0.1.0.8 → 0.1.0.11 升级；用户另反馈本机卸载、重装及使用正常。证据范围见 [验收记录](TESTED-BASELINE.md)。真实故障回滚及第二台干净机器仍需验收。

以下清单供隔离测试机使用。当前已工作的 0.1.0.11 无需卸载；同版安装会被拒绝，不能用它验证覆盖升级。

## 正常升级

1. 保留已工作的 0.1.0.8，记录安装目录、用户配置内容、Package、卸载项和项目证书指纹。
2. 关闭正在执行解压的窗口及 SmartZip 设置窗口。正常启动 `SmartZipSetup-0.1.0.11-test.exe`。
3. 应自动使用原目录，不允许升级中迁移；验证旧身份通过后跳过重复证书授权。
4. 安装完成后确认当前用户的 Package 为 0.1.0.11，外部位置为新版本目录，VerifyIsOK=True 且无 Modified/NeedsRemediation 等异常；现代菜单可用，用户配置不变，证书创建者属性继续保留。
5. 测试 ZIP/RAR/7Z、中文/空格/特殊字符、多选。确认旧原版 SmartZip、旧 UnZip 和独立 7-Zip 未受影响。
6. 同版重复安装和旧版本安装包应拒绝，不应写入数据。
7. 通过正式卸载入口卸载：移除 Package、项目状态、所有由本产品记录的版本目录与快捷方式；证书按最初所有权处理，用户配置保留。

## 实际回滚测试（仅测试环境）

从已工作的 0.1.0.8 基线开始，每次只运行一个故障构建：

```powershell
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.11 -FaultAt after-stage
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.11 -FaultAt after-package
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.11 -FaultAt before-commit
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.11 -FaultAt after-state
```

生成的文件名包含 `-fault-`，不要发布给普通用户。故障点分别覆盖文件写入、Package 切换、Inno 元数据提交后以及产品状态部分更新后。

每次失败后重新获取旧 Package，验证健康状态、COM 和菜单可用，旧卸载 EXE/DAT/MSG、快捷方式、产品状态与备份内容一致，新目录被清理，原证书和用户配置未变化。版本号恢复但健康检查失败，仍算回滚失败。
若旧 Package 恢复被 Windows 拒绝，应明确报回滚不完整，保留文件和 `.upgrade-随机编号` 备份，不继续删除依赖；不得人工清理后宣称自动回滚成功。

备份不含自定义注册表 ACL，保存的是原始值及类型、卸载文件/快捷方式字节。断电/杀进程恢复不承诺自动重试；发现不完整状态会阻止继续覆盖。升级期间不要启动另一个旧版卸载器或手工修改项目文件。

依据：

- [微软 Package 强制恢复指定版本选项](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.addpackageoptions.forceupdatefromanyversion)
- [Inno 累积卸载记录](https://jrsoftware.org/ishelp/topic_appendnotes.htm)
