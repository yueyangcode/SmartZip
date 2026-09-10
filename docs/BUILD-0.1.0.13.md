# 0.1.0.13 提交失败回滚修复候选

## 后续实际复测：FAIL，停止作为候选

`build/sandbox-rollback-0.1.0.13/Output/rollback-run-20260909-210459/`：前两项 PASS；`before-commit` 返回 `20`，日志确认已恢复健康的 `.8` Package，但独立快照多出一个原本不存在的零字节 `unins000.msg`（SHA-256 `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`），因此仍为 FAIL；第四项未运行。

直接复现发现备份的源生成快速序列化把 `byte[]? = null` 写成 `""`，丢失文件不存在的信息。退出码/提交状态修复已在该轮生效；备份修复转入 `.14`。原安装包、哈希及失败快照保持不变。下文为构建时的历史记录，不代表后续验收通过。

2026-09-09：代码修复、正常包和四个故障包构建完成；**未安装、未发布，真实沙盒回滚复测尚未执行**。旧 `.11` 的 `before-commit` 失败记录不变。

## 修复范围

沿用原部署助手、Package 注册和备份恢复逻辑，只修正 Inno 安装事件的完成判定及失败处理，并保留 `.12` 的共享中文字体修复。

- `Completed` 只在提交助手真正成功返回后置真；`ssDone` 不再无条件宣布成功。异常分支显式保持未完成。
- 提交失败在完成页面之前调用原回滚助手。回滚只尝试一次；失败时保留恢复资料，不在退出时自动反复重试。
- 回滚成功但安装失败返回 `20`；回滚未完成返回 `21`。原准备阶段失败仍使用 Inno 的非零返回码（例如 `7`）。
- `GetCustomSetupExitCode` 在 `DeinitializeSetup` 之前调用，所以错误码决定前必须已有回滚结果，不能只依赖退出事件。
- 失败页面显示“SmartZip 安装未完成”，区分已回滚与回滚未完成，不再显示成功安装。
- 新装失败清理卸载项/快捷方式时检查返回值；升级失败继续由原备份恢复，不使用新装清理分支删除旧信息。
- 成功提交后的收尾清理失败沿用“保留备份并记录警告”的语义，不反向拆除已经提交的版本。

依据：[Inno 6.2.2 安装事件/退出流程源码](https://github.com/jrsoftware/issrc/blob/is-6_2_2/Projects/Main.pas)、[自定义退出码文档](https://jrsoftware.org/ishelp/topic_scriptevents.htm)。

## 构建产物

所有文件位于 `dist/`，均为 x64 开发测试包。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| SmartZipSetup-0.1.0.13-test.exe | 14,340,344 | C26A11A483FB792D647653E53DFEDFA5AEE12450DBF977FE0B662750E32677B8 |
| SmartZipSetup-0.1.0.13-test-fault-after-stage.exe | 14,336,760 | 975934925BE13D5396F81D0C6BA95EA395B8433A2D5D744E2B4609B059F36FB4 |
| SmartZipSetup-0.1.0.13-test-fault-after-package.exe | 14,336,736 | 96351A78B07C2A6E507C1FE9BC5123741B3A97F63FFB0B7665EFE1DA63D74D77 |
| SmartZipSetup-0.1.0.13-test-fault-before-commit.exe | 14,339,264 | D80927538A6D2F843396C970CD99802AE4A297E41799549EF729989C09E3CCA0 |
| SmartZipSetup-0.1.0.13-test-fault-after-state.exe | 14,339,000 | 17C9FFF2E6EF619A2BDCBFDE97E57CD8F8CDD5597CFCFE5CFBA7A748A8902F56 |

正常包约 13.68 MiB，`FaultAt` 为空。四个 `-fault-` 文件不得发布给普通用户。正常包最后重新构建以包含更新后的 README，并使构建暂存载荷恢复为正常、非注入状态；本轮第一次正常构建仅归档在 `build/rollback-fix-0.1.0.13/normal-first-build.exe`，不是交付文件。

开发签名仍为 `CN=SmartZip Modern Evaluation`，指纹 `A1709CED9DB02150E2FB40CE6496BD1938D89195`。开发机签名验证 Valid 不等于新电脑已有公开发行信任；未购买证书、未导入任何新证书。

重建正常包：`pwsh -NoProfile -File build.ps1 -Signing Test -Version 0.1.0.13`。故障包加 `-FaultAt after-stage` 等参数；不要覆盖已固定哈希的测试材料。

## 自动化验证

完整构建检查及离线更新验签测试通过。新增 `tests/CommitLifecycle.Tests.ps1` 提取**实际生产 Pascal 事件处理代码**，用相同 Inno 6.2.2 运行完整安装事件顺序；仅替换部署助手/新装清理为测试替身。测试 EXE 无载荷、无卸载记录、无 Package/证书操作，不安装 SmartZip。

| 场景 | 实测返回码 | 结果 |
| --- | ---: | --- |
| 提交成功 | 0 | 不回滚，正常收尾 |
| 提交返回失败 | 20 | 回滚一次，不收尾，不显示成功 |
| 提交调用抛异常 | 20 | 同上，完成状态保持假 |
| 回滚返回失败 | 21 | 不重复尝试，提示保留现场 |
| 回滚调用抛异常 | 21 | 同上 |
| 首次安装提交失败 | 20 | 回滚后执行新装元数据清理 |
| 新装元数据清理失败 | 21 | 明确失败，不误报清理成功 |
| 成功提交后收尾返回失败 | 0 | 已提交安装保留，日志提示备份未清理 |

证据：`build/tests/commit-lifecycle/`；正常最终构建日志：`build/rollback-fix-0.1.0.13/normal-final.log`；四个故障构建日志位于同目录。

## 沙盒复测准备与边界

- 原沙盒保持不动。`Save-Failed-State.cmd` 已放入旧只读映射，必须在旧沙盒内运行；它只导出本次固定 nonce/SHA-256 的备份和三份收据/标记文件到旧日志目录，验证哈希，不注册 Package、不导入证书、不修改安装目录。
- 不开发一次性的自动修补/清理工具。旧现场导出并经检查后，使用新沙盒重新准备 `.8` 基线，原失败仍记 FAIL；销毁/重建沙盒绝不计作回滚成功。
- `pwsh -NoProfile -File tests/Prepare-SandboxRollback.ps1` 已生成独立 `build/sandbox-rollback-0.1.0.13/SmartZip-Rollback-0.1.0.13.wsb`；新 Output 为空，未启动沙盒。
- 新映射仍只共享只读测试材料和专用可写日志目录，不共享私钥、凭据或主机软件；网络和剪贴板关闭。基线安装入口继续使用未修改的 `.8` 安装包，首次证书授权由用户在向导确认。
- 新测试工具固定四个 `.13` 故障包哈希，拒绝主机/错误用户/不同会话执行。自身编译、自检及主机拒绝测试通过；SHA-256 为 `311AA67028D2A837EC0D06601E458C858DCC42CDE69EF72587604D2909425DFE`。
- 四项实际回滚、现代菜单/解压、完整安装卸载界面和真实更新链仍须验收，当前不能声称全部修复验证完成。
