# SmartZip Win11 图标

用户于 2026-09-10 确认采用 `smartzip-win11-concept-v1.png`，随后明确允许本地图像处理：只清理背景，保持设计不变。

- 设计原稿由内置 image_gen 生成；[原提示词](smartzip-win11-concept-v1.prompt.md)保留。工具未提供模型选择或版本确认，不能声称指定了 image2.5。
- 自动生成的透明版存在假棋盘格或毛边，未用于软件。`Prepare-Logo.ps1` 只沿原稿外轮廓建立抗锯齿遮罩，保留内部像素、白色文档及拉链，不重新绘制设计。
- 发布资源母版：`../../packaging/Assets/SmartZip.png`，1254 × 1254，真实 RGBA。该母版不随软件安装。
- `../../packaging/MakeAssets.ps1` 使用现有 System.Drawing 缩放，生成 16、20、24、32、40、48、64、96、128、256 像素 ICO，以及 44/50/150 像素 Package PNG。只收紧透明留白，不改变纵横比例。
- 安装向导的小图使用白底、3 倍分辨率 BMP；程序/菜单 ICO 和 Package PNG 保留透明背景。不添加软件运行依赖。
- [浅色与深色小尺寸预览](smartzip-win11-icon-preview.png)直接读取最终 ICO，按实际像素尺寸展示，不是系统截图。

在仓库根目录重建资源及检查：

```powershell
pwsh -File .\design\logo\Prepare-Logo.ps1
pwsh -File .\packaging\MakeAssets.ps1 -Destination .\build\payload\Assets
pwsh -File .\tests\IconAssets.Tests.ps1 -Assets .\build\payload\Assets
```

完整 `build.ps1` 还会只读检查 SmartZip、部署助手、测试证书助手和最终安装器中的 10 档图标字节，与 ICO 逐一匹配；不会执行这些程序进行安装。真实安装后的 Shell 缓存、向导及任务栏显示仍需验收。
