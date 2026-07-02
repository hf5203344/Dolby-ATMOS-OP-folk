# 计划：生成 trae/agent-6dzWd3 → origin/main 合并摘要报告

## Summary

用户要求根据已提供的 26 个变更文件（diff 摘要）生成一份 Markdown 格式的合并差异摘要报告。报告须遵循用户指定的严格格式：2-3 句中文总体摘要 + 单个 Markdown 表格（文件路径 | 变更，每条变更以 `-` 开头、`<br>` 分隔），不包含其他内容。

## Current State Analysis

已完成 Phase 1 探索，逐文件读取了全部 26 个变更文件的内容，识别出三个产物分组：

- **规格文档**（3 个）：`.trae/specs/init-dolby-atmos-ksu-module/{spec.md, tasks.md, checklist.md}` —— 定义模块契约、任务分解、验收清单
- **M1 模块打包框架**（11 个）：`build/M1/` 下的 8 个运行时脚本 / 配置 + 3 个 bats 测试
- **M2 杜比解码器**（6 个）：`build/M2/` 下的 2 份 XML + 2 个占位文件 + 2 个测试 / 校验脚本
- **M6 兼容性适配**（6 个）：`build/M6/` 下的 compat.sh + sepolicy.rule + 3 个 bats 测试

合并性质：26 个文件全部为新增（diff 头 `@@ -0,0 +X,Y @@`），无修改或删除。

## Proposed Changes

### 输出文件
直接在对话中输出报告（用户要求的"输出格式"未指定落盘文件，且明确说"不输出任何其他内容"）。无文件创建 / 编辑。

### 报告结构

**第 1 部分**：2-3 句中文总体摘要，覆盖：
- 此次合并的项目首次落地（Dolby Atmos OnePlus KSU 模块 v1.0.0）
- 三个并行模块（M1 框架 / M2 解码器 / M6 兼容性）的核心交付物
- 范围影响（OnePlus ACE5 系列，KSU/Magisk/APatch 三 Root 兼容）

**第 2 部分**：Markdown 表格，列结构：
- 左列：相对路径（自仓库根 `/workspace/` 截取后的路径）
- 右列：每条变更一行，格式 `- <一句话描述>`，多条用 `<br>` 分隔

### 关键映射（每文件的核心变更点）

| 文件 | 核心变更 |
|---|---|
| `spec.md` | 新增 Dolby Atmos KSU 模块契约（7 类需求，4 阶段交付） |
| `tasks.md` | 新增 7 个任务 / 4 阶段并行化分解 |
| `checklist.md` | 新增 6 模块验证清单 + 全局门禁 |
| `M1/module.prop` | 新增模块元数据（id=v1.0.0, OnePlus ACE5） |
| `M1/system.prop` | 新增 2 条 ro.oplus.audio.* 属性 |
| `M1/customize.sh` | 新增 6 阶段安装脚本（兼容 KSU/Magisk/APatch） |
| `M1/post-fs-data.sh` | 新增数据挂载后清理 / 目录创建 / SELinux 补丁 |
| `M1/service.sh` | 新增启动阶段服务拉起 + VINTF/APEX 挂载 |
| `M1/uninstall.sh` | 新增模块卸载清理（停止服务、umount、属性复位） |
| `M1/META-INF/update-binary` | 新增 Magisk install_module 包装器 |
| `M1/META-INF/updater-script` | 新增 `#MAGISK` 标记 |
| `M1/META-INF/compat.sh` | 新增 14 个检测 / 策略函数（与 M6 同源） |
| `M1/test/test_customize.bats` | 新增 23 个 customize.sh 单元测试 |
| `M1/test/test_post_fs_data.bats` | 新增 8 个 post-fs-data.sh 单元测试 |
| `M1/test/test_service.bats` | 新增 15 个 service.sh 工具函数单元测试 |
| `M2/.binaries_pending` | 新增 6 .so + 1 service 二进制提取待办 |
| `M2/checksums.txt` | 新增 7 个 SHA256 PENDING 占位行 |
| `M2/system/odm/etc/media_codecs_c2.xml` | 新增 AC-3 / E-AC-3 / JOC / AC-4 解码器注册 |
| `M2/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml` | 新增 HIDL IComponentStore + AIDL IDms 声明 |
| `M2/test/test_decoder_xml.bats` | 新增 19 个解码器 XML 校验测试 |
| `M2/test/validate_media_codecs.sh` | 新增 5 段集成校验脚本（xmllint + XPath + DAP UUID） |
| `M2/test/verify_checksums.sh` | 新增 SHA256 校验脚本（自动 SKIP PENDING 状态） |
| `M6/META-INF/compat.sh` | 新增 10 检测函数 + pre_install_check + sepolicy + 多机型参数 |
| `M6/META-INF/sepolicy.rule` | 新增 4 类 allow 规则（DMS↔audioserver / C2↔mediacodec / chr_file / vendor_data） |
| `M6/test/test_compat.bats` | 新增 30+ 个 compat.sh 函数级单元测试 |
| `M6/test/test_pre_install_check.bats` | 新增 11 个 pre_install_check 5 分支覆盖测试 |
| `M6/test/test_sepolicy.bats` | 新增 16 个 sepolicy 规则与应用行为测试 |

## Assumptions & Decisions

1. **文件路径格式**：使用相对仓库根的相对路径（去掉 `/workspace/` 前缀），符合用户要求"左列：文件路径（相对路径）"。
2. **变更粒度**：每个文件一条 `-` 项（多数文件为全新落地，仅含单一意图）；含多个独立交付物的文件（如 `compat.sh`）以"功能 + 数量"描述，但合并为单条（用户要求"每条一句"）。
3. **语言**：中文描述，保持与用户输入一致。
4. **输出不含**：标题、分支信息表格、Phase 标识、emoji；只输出"2-3 句 + 表格"。
5. **不重新执行 git diff**：用户已在任务描述中提供 diff 头信息，且文件已读取，凭此即可生成报告；无需执行非只读命令。

## Verification

- 总体摘要：2-3 句，涵盖"项目 / 模块 / 影响"
- 表格：26 行，每行左列为相对路径，右列为单条 `-` 描述
- 路径一致性：同一文件不重复出现在不同行（M1 与 M6 的 `compat.sh` 分属不同目录，需分别列出）
- 严格遵守"不输出其他内容"的格式约束
