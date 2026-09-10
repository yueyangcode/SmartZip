# 0.1.0.14 缺失文件备份修复候选

2026-09-09 构建，验收更新至 2026-09-10：正常包和四个故障包未更换，未公开发布。四个沙盒故障场景均已验证通过（第三项为补充日志复核，原自动 FAIL 保留）；随后正常升级、功能及正式卸载清理验收通过。卸载后重装部署和注册检查通过，用户确认重装后全部 case 无问题；实际新目录文件清单未独立采集。最新结果见 [沙盒验收记录](SANDBOX-0.1.0.14-ACCEPTANCE.md)。

## 后续实测与测试工具修复（安装包不变）

`build/sandbox-rollback-0.1.0.14/Output/rollback-run-20260909-212727/`：前两项自动 PASS；第三项自动 FAIL，但退出 `20`、快照差异 0。补充日志确认是测试工具仅采新文件名造成漏采，不是产品回滚失败。

PID `7704` 被复用：原日志 864 字节，补充导出为 1825 字节，原前缀 SHA-256 完全一致；新增的 961 字节明确记录恢复健康 `.8` Package 和 `UPGRADE_ROLLBACK_COMPLETE`。故障点和新增回滚日志齐全、没有不完整回滚标记，前后快照 SHA-256 均为 `8AEBE3AD8A59ECAFB07118414150EC0F2A720BC5A4329CB6D64ED19A1B20BB50`，不存在额外 `unins000.msg`。第三项因此为**补证复核 PASS**，原 `result.json` 和 `overall.txt` 仍保留自动 FAIL，不覆盖。

测试器现在保存日志完整的测试前/后字节，只把验证过的新增后缀作为本阶段证据。同名 PID 复用可正确采集；旧完成标记不能造成误报 PASS；日志被删除、截短或前缀改写时停止。自检覆盖追加、新日志、不变日志、大小写、Unicode、旧标记排除及上述异常。快照读取保留原文件，兼容原 UTF-8 BOM；纯测试和固定真实证据审计均通过，发布时裁剪/警告作为错误检查通过。

**历史继续方案（现已执行完成，不要重跑）：**`Continue-After-State.cmd` 使用新名字的 `SandboxRollback-logfix.exe`，先核验固定原始/补充证据及当时完整 `.8` 基线，然后只运行原哈希的 `after-state` 故障包。任一不符则停止，不补注册、不清理、不重试、不运行正常升级。现有继续输出会阻止再次执行。

- 新工具：12,151,946 字节；SHA-256 `C08B66DA1A2F5D6FD2F25A133368475727A3196DFB08E61197EC739CD64F6127`。
- 新入口 SHA-256：`4C4E14926EC77FB480FBBD8A3E82341AD7EA4F1B9B946CF4748BF81C2D87E3ED`。
- 继续输出：`Output/rollback-continuation-20260909-212727-after-state/`，与原测试目录分离；后续已取得第四项 PASS、前后快照差异 0。
- 准备命令：`pwsh -NoProfile -File tests/Prepare-SandboxRollback.ps1 -ContinueAfterLogAudit`，不覆盖已有继续材料；主机日志 `build/rollback-logfix-0.1.0.14/prepare.log`。当前新版工具的普通执行/继续执行均已验证拒绝主机；无关旧测试的证据被拒绝。
- 五个 `.14` 安装包和旧测试器、前三项原记录均再次校验未改变；不重新打包、不升成 `.15`。下文是原构建记录及首次沙盒准备步骤，不要在当前会话重复建立基线。

## 根因与最小修复

`.13` 沙盒的 `before-commit` 已正确返回 `20` 并恢复健康的 `.8` Package，但多出空 `unins000.msg`，快照差异 1，第四项未运行。证据保留在 `build/sandbox-rollback-0.1.0.13/Output/rollback-run-20260909-210459/`。

使用项目固定 SDK 8.0.425 的原序列化代码直接复现：`BackupFile.Data = null`（不存在）与 `byte[0]`（已有空文件）均写成 `"Data":""`；读回都成为零长数组。恢复代码按非 null 数据写文件，因此创建了不应存在的文件。旧测试只比较两次生成的 JSON，无法发现第一次序列化已丢失信息。

`UpgradeBackupContext` 改为源生成 Metadata 模式，明确保留 `"Data":null` 与 `"Data":""` 的区别；不启用反射、不增加依赖、不升级运行库、不改变 Package/证书/COM/文件恢复顺序。参考 [Microsoft 源生成模式说明](https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation-modes)。

`tests/UpgradeTests/Program.cs` 增加 7 个受控文件位置 × 3 种内容状态的 21 项值语义往返测试。修复前该测试确实失败；修复后必须在常规运行与 win-x64 裁剪发布运行中同时通过。测试验证原始值与恢复值，而不只比较重新编码后的文本。

已经把缺失信息丢成 `""` 的旧备份无法凭该值可靠复原。本版不猜测解释、不自动修改旧失败现场；也不靠删除空文件或忽略快照来通过验收。

## 构建及验证证据

所有产物位于 `dist/`；正常包为 14,335,128 字节（约 13.67 MiB），`FaultAt` 为空。故障包先构建，正常包最后构建，构建暂存载荷也保持为正常状态。

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| SmartZipSetup-0.1.0.14-test.exe | 14,335,128 | C8A9C6F0D3B18D3DFA3D276F3E7C10BD3732771054DF3EED1B8970F5F58594E1 |
| SmartZipSetup-0.1.0.14-test-fault-after-stage.exe | 14,338,704 | EED84F66738EBABEB4A806273B550EEF12B2C26743CA3A4DABA7F27813CA23F4 |
| SmartZipSetup-0.1.0.14-test-fault-after-package.exe | 14,337,848 | 5AECBEE9FB361187FC8F665AF1706DA4AFC059BEF3E6C327DB672EE2B166E82C |
| SmartZipSetup-0.1.0.14-test-fault-before-commit.exe | 14,337,080 | 4849A480213D5E25B8F6CC786998C2DBEC6B9358FA1599F1CAE3CA87E435C7C6 |
| SmartZipSetup-0.1.0.14-test-fault-after-state.exe | 14,337,856 | 030A4BDFC0187EA6F92593BD68F989D8956DF7BB96F954BBFF2A54FF751A22EE |

五个文件开发机签名验证均为 Valid，签名者指纹仍为 `A1709CED9DB02150E2FB40CE6496BD1938D89195`。这不代表全新电脑具备公开发行信任。原 `.8` 与全部 `.13` 安装包哈希再次核验未改变，`.13` 失败证据未修改。

| 自动化检查 | 结果 | 证据 |
| --- | --- | --- |
| 修复前新增缺失文件回归 | 如预期失败 | backup-regression-before.log，退出 -532462766 |
| 修复后 21 项备份值语义检查及原升级测试 | PASS | backup-regression-after.log |
| win-x64 自包含裁剪发布后的相同测试 | PASS | trimmed-backup-tests-build.log / trimmed-backup-tests.log |
| 五次完整构建及原有测试 | PASS | after-stage.log / after-package.log / before-commit.log / after-state.log / normal.log |
| 实际 Inno 无载荷事件的 8 个场景 | PASS | 各完整构建日志，成功 0、安装失败回滚成功 20、回滚失败 21 |
| 沙盒工具纯函数自检及主机拒绝执行 | PASS | sandbox-prepare.log；拒绝发生在创建运行目录/启动安装器之前 |
| 沙盒映射副本哈希、新输出目录为空、旧包及旧证据保留 | PASS | 构建后只读复核 |
| 真实 Package/文件/注册表/证书的四项故障回滚 | 构建时未运行；后续已验证 | 第三项补证复核，原自动 FAIL 保留；实际结果见本文顶部及沙盒验收记录 |

日志位于 `build/rollback-fix-0.1.0.14/`。使用 `pwsh -NoProfile -File build.ps1 -Signing Test -Version 0.1.0.14` 重建正常包，故障构建加原有 `-FaultAt` 参数。四个故障包仅供隔离环境，不得提供给普通用户。固定哈希的测试产物不可重建覆盖。

安装范围和证书策略不变：per-user；仅首次建立开发证书信任时最小化助手可请求 UAC，公钥在 `LocalMachine\TrustedPeople`，不进入 Root。沿用已有开发签名材料，构建不向系统信任库导入证书，不安装或启动 SmartZip。

## 首次沙盒准备（历史步骤，已执行）

已准备独立 `build/sandbox-rollback-0.1.0.14/SmartZip-Rollback-0.1.0.14.wsb`，只映射测试材料与日志，不覆盖 `.13` 现场或启动沙盒。新 Input 不包含正常候选安装器，Output 为空。测试工具 SHA-256 为 `456CFF8F40666C897A08B1513E544A8A78A571E042703EDC867C6B46A96D1B54`；除版本/固定哈希更新外，增加基线缺失 `unins000.msg` 的前置要求及空文件快照差异自检，不放宽原验收条件。

1. 用户确认保留旧证据后，关闭旧沙盒，再打开新 `.wsb`；沙盒重建不是回滚成功。
2. 新沙盒的只读预检查必须返回 0。在 `C:\SmartZipTestInput` 运行 `Install-Baseline.cmd`，使用原始 `.8` 安装包和默认目录完成向导。该旧基线包的旧字体保持不变。
3. 确认基线成功后运行 `Run-Rollback.cmd`，保持沙盒和命令窗口打开，不使用 SmartZip 或右键激活它。
4. 四项依次验证；任何失败立即停止，不人工补注册、修复或删除文件。特别要求 `before-commit` 后 `unins000.msg` 继续不存在。

后续四项回滚、正常升级、功能、卸载及重装结果见本文顶部与沙盒验收记录，不要重复以上历史步骤。GitHub 提示到静默升级的完整更新链仍未验收。
