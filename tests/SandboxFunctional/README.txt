SmartZip 0.1.0.14 沙盒功能测试

这里只放测试材料，不是安装程序。请勿卸载、修改 Feature 或手动补注册。
先在 C:\SmartZipTestInput 双击 Prepare-Functional-Tests.cmd。
随后在 C:\SmartZipTestOutput\functional-tests-0.1.0.14\Cases 测试。
不要直接在只读的 C:\SmartZipTestInput\FunctionalFixtures 里解压。

第一组：先检查一级菜单，再点击“智能解压”
01-ZIP：右键唯一的 ZIP，应直接出现“智能解压”；点击后生成一个文本文件。
02-RAR：右键唯一的 RAR；点击后生成 helloworld.txt。
03-7Z：右键唯一的 7Z；点击后生成一个文本文件。
04-中文 空格 & (括号) 📦：验证完整路径和文件名里的中文、空格、符号。
05-Multi：同时选中 ZIP 和 RAR，右键并点击一次；应生成两个文本文件。
ZIP/7Z 内容应为 SmartZip 中文 Unicode payload 123；RAR 为 hello libarchive test suite!。
如果入口只在“显示更多选项”中出现，请记录失败，不要修改系统来让它出现。

第二组：过滤测试，只右键，不点击解压
06-Filter：分别右键 TXT、DOCX、JPG、普通文件夹，都不应出现“智能解压”。
再同时选择 ZIP + TXT，命令应隐藏或不可用。
DOCX/JPG 是仅供扩展名过滤测试的文本占位文件，不要双击打开。
另外确认“显示更多选项”仍可打开；这个干净沙盒原本没有旧版 UnZip 菜单。

第三组：其他格式
07-CAB、08-TAR、09-GZ、10-BZ2、11-GZIP：分别右键其中的压缩包并智能解压。
12-Volume-001：只选 .001 第一卷，解压后应只有一个文本文件。
13-Volume-Multi：同时选择 .001 至 .004 全部分卷，解压后也应只有一个文本文件。
每组只点击一次；若已解压，不要重复点击制造重名文件。

界面与稳定性
记录菜单文字是否正常，是否明显卡顿、报错或 Explorer 崩溃/重启。
出现崩溃或明显卡顿时立即停止连续测试，保留现场。
如果“设置 → 个性化”里本来就有 Context menu / App extensions 页面，请记录
SmartZip 的实际显示名称和开关行为；页面不存在则记“此沙盒未提供页面”，不要开 Feature。
当前沙盒为 24H2 26100.9278，不能据此替代宿主机 25H2 的 App extensions 验收。

完成或遇到问题后
在 C:\SmartZipTestInput 双击 Collect-Functional-Results.cmd，然后把窗口截图发来。
并告诉开发者：一级菜单是否直接出现、哪些组测试过、中文是否正常、有没有卡顿/崩溃。
采集器只读取本次样本/解压结果和相关错误日志，不会自动点击菜单、解压、卸载或修复。
哈希检查只能证明文件结果正确，不能单独证明是从现代一级菜单调用的。
请保持沙盒打开，不要卸载。没有进行的项目会保留为未确认，不会自动算通过。
