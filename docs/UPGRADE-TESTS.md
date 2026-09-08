# 0.1.0.9 覆盖升级验收

代码已实现并有自动化策略/序列化/失败顺序测试；Windows 实际升级、失败恢复和升级后卸载仍需独立验收。不要把模拟测试写成真实机器测试成功。

## 正常升级

1. 保留已工作的 0.1.0.8，记录安装目录、用户配置内容、Package、卸载项和项目证书指纹。
2. 关闭正在执行解压的窗口。正常启动 `SmartZipSetup-0.1.0.9-test.exe`。
3. 应自动使用原目录，不允许升级中迁移；验证旧身份通过后跳过重复证书授权。
4. 安装完成后确认 Package 仅有当前 0.1.0.9 注册，外部位置为新版本目录，现代菜单可用；用户配置不变，证书创建者属性继续保留。
5. 测试 ZIP/RAR/7Z、中文/空格/特殊字符、多选。确认旧原版 SmartZip、旧 UnZip 和独立 7-Zip 未受影响。
6. 同版重复安装和旧版本安装包应拒绝，不应写入数据。
7. 通过正式卸载入口卸载：移除 Package、项目状态、所有由本产品记录的版本目录与快捷方式；证书按最初所有权处理，用户配置保留。

## 实际回滚测试（仅测试环境）

从已工作的 0.1.0.8 基线开始，每次只运行一个故障构建：

```powershell
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.9 -FaultAt after-stage
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.9 -FaultAt after-package
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.9 -FaultAt before-commit
pwsh -File .\build.ps1 -Signing Test -Version 0.1.0.9 -FaultAt after-state
```

生成的文件名包含 `-fault-`，不要发布给普通用户。故障点分别覆盖文件写入、Package 切换、Inno 元数据提交后以及产品状态部分更新后。

每次失败后验证旧 Package/COM 可用，旧卸载 EXE/DAT/MSG、快捷方式、产品状态与备份内容一致，新目录被清理，原证书和用户配置未变化。
若旧 Package 恢复被 Windows 拒绝，应明确报回滚不完整，保留文件和 `.upgrade-随机编号` 备份，不继续删除依赖；不得人工清理后宣称自动回滚成功。

备份不含自定义注册表 ACL，保存的是原始值及类型、卸载文件/快捷方式字节。断电/杀进程恢复不承诺自动重试；发现不完整状态会阻止继续覆盖。升级期间不要启动另一个旧版卸载器或手工修改项目文件。

依据：

- [微软 Package 强制恢复指定版本选项](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.addpackageoptions.forceupdatefromanyversion)
- [Inno 累积卸载记录](https://jrsoftware.org/ishelp/topic_appendnotes.htm)
