# 0.1.0.12 中文字体修复候选

**暂停安装/发布**：2026-09-09 的真实沙盒测试发现原安装器在 `before-commit` 失败后仍进入完成状态并跳过回滚。0.1.0.12 仅修正字体，仍包含该安装事件逻辑，因此不能作为修复回滚问题的版本。原包保留不覆盖；后续修复构建使用 0.1.0.13。

2026-09-09：构建和自动化检查通过；尚未安装，也未发布。
目标沙盒的证书页字体预览已由用户截图确认：中文正常，正文、勾选项及按钮没有明显裁切。此结论仅覆盖该预览页面，完整安装、卸载界面仍待验收。

## 改动

- `installer/ChineseSimplified.isl` 为安装器、卸载器和共用此语言文件的诊断程序明确选择 `Microsoft YaHei UI`；正文 9 pt，欢迎/完成页标题 12 pt。
- 保持 UTF-8 BOM。未改变证书授权、Package 部署、升级、回滚或解压逻辑。
- 不捆绑、不安装字体，不更改系统字体链接、语言、区域、执行策略或 Windows Feature。
- `tests/FontWizard.Tests.ps1` 用现有 Inno Setup 6.2.2 和生产证书页的原始文字/控件构建只读字体预览；预览没有安装载荷，禁止进入安装流程。
- 预览使用同一份语言配置并记录实际使用的字体和相关字体文件/注册项；目标设备的可读性与裁切情况仍需目视检查。

## 产物

- 文件：`dist/SmartZipSetup-0.1.0.12-test.exe`
- 大小：14,336,840 字节（13.67 MiB）
- SHA-256：`0F216E267B4D88F038CE611544CF6E28EA1C917DF84A2DEE3A5F1C5E1C6CF1CD`
- 开发签名：`CN=SmartZip Modern Evaluation`；不是面向公众的受信任发行签名。
- `FaultAt` 为空：这是正常逻辑的字体修复候选，不是故障注入包。

重建：`pwsh -NoProfile -File ./build.ps1 -Signing Test -Version 0.1.0.12`。
仅重建字体预览：`pwsh -NoProfile -File ./tests/FontWizard.Tests.ps1`；输出在 `build/tests/font-wizard/`。

## 验证范围

完整构建检查通过，包括中文/字体配置、原生产 Pascal 目录逻辑、预览禁止安装、原有事务/回滚/命名管道/COM 选择测试，以及离线更新验签和发布限制测试。
这些检查不等同于沙盒真实故障回滚或真实升级验收。

首次字体预览在目标沙盒记录了 `Microsoft YaHei UI`（9 pt），且 `msyh.ttc`、`simsun.ttc` 和字体注册项均存在，因此不能将此沙盒描述为完全缺少中文字库。
但预览页未打开：预览专用 `NextButtonClick` 错误地拒绝了 Inno 跳过隐藏欢迎页时的内部导航。
已仅修正预览程序为“到达预览页后才关闭”，并新增实际 Pascal 导航回归测试（欢迎页放行、其他前置页放行、预览页关闭）。
此修正不影响正式安装器逻辑，0.1.0.12 安装包未重建、SHA-256 未变化。目标沙盒已用 `Preview-Fonts-v2.cmd` 验证显示效果；日志于 2026-09-09 19:25:50 记录 `FONT_PREVIEW_PAGE_REACHED`，19:26:00 正常关闭。用户截图与日志共同支持“当前沙盒预览通过”，不代表所有系统或完整安装界面均已通过。

原 0.1.0.8 基线包、正常 0.1.0.11 包及四个 0.1.0.11 故障包的 SHA-256 全部保持不变。
主机仍为已安装的 0.1.0.11；沙盒基线仍为 0.1.0.8，不应为预览字体提前升级或卸载。

依据：[Inno 字体配置](https://jrsoftware.org/ishelp/topic_langoptionssection.htm)、[Windows 11 字体清单](https://learn.microsoft.com/en-us/typography/fonts/windows_11_font_list)。若目标系统缺少指定字体，仍需根据预览日志进一步处理，不能承诺所有精简系统都已兼容。
