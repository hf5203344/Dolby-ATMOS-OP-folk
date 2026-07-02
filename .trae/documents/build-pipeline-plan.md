# 计划：自检 → 测试 → 打包 → 构建 GitHub 仓库

## Summary

用户要求基于当前 `trae/agent-6dzWd3` 分支（合并自 `origin/main` 后含 M1/M2/M6 全部产物），执行端到端的发布前流水线：
1. 自检（shellcheck / xmllint / 二进制占位核对）
2. 跑测试（bats 全部用例）
3. 打包成可分发 ZIP
4. 构建 GitHub 仓库基础设施（CI workflows + README + 推送）

## Current State Analysis

- **环境已就绪**：`shellcheck` / `xmllint` / `bats` / `sha256sum` / `zip` / `git` 均在 `/usr/bin/` 可用
- **缺失**：`gh` CLI 未安装
- **Git 状态**：当前在 `trae/agent-6dzWd3` 分支，处于 `git revert a2ed5fa` 进行中（HEAD = 3f1f584）。被回滚的提交 `a2ed5fa` 只影响我之前生成的 `merge-summary-dolby-atmos-ksu-module.md` 文档，不影响 M1/M2/M6 实际代码。**为了执行完整流水线，必须先 `git revert --abort` 恢复工作区**。
- **远程**：`origin = https://github.com/hf5203344/Dolby-ATMOS-OP-folk`（凭据由 git credential helper 管理，仓库内不存储明文 token）
- **现有内容**：
  - `/workspace/.trae/specs/init-dolby-atmos-ksu-module/{spec,tasks,checklist}.md`
  - `/workspace/build/{M1,M2,M6}/` 全部产物（11 + 6 + 6 = 23 个文件）
  - `/workspace/README.md`（已存在，内容为基础）
  - `/workspace/进度`、`设计.zip`、`设计加任务.zip`、`prompt总结.zip`（参考材料，不入仓）
  - 无 `.github/` 目录
- **未交付的子模块**：M3 音效链、M4 配置 APK、M5 诊断工具、Phase 4 集成 ZIP。本次只对已落地的 M1/M2/M6 做端到端验证 + 打包 + 发布；M3-M5 维持任务清单状态。

## Proposed Changes

### 阶段 0：恢复工作区（前置）
- `git -C /workspace revert --abort`（取消误操作的 revert）
- 确认 `git status` 为 clean

### 阶段 1：自检（不写文件，只生成报告）

#### 1.1 Shell 静态检查
针对全部 9 个 shell 脚本（`M1/*.sh` + `M1/META-INF/com/*.sh` + `M6/META-INF/compat.sh` + `M2/test/*.sh`）执行：
```bash
for f in /workspace/build/M1/*.sh /workspace/build/M1/META-INF/compat.sh \
         /workspace/build/M1/META-INF/com/google/android/update-binary \
         /workspace/build/M6/META-INF/compat.sh \
         /workspace/build/M2/test/*.sh; do
  shellcheck -s sh "$f" 2>&1
done
```
**目标**：零 error 零 warning（spec 质量门禁）。若有 warning，单独列出但**不修改代码**（用户没要求改代码，仅自检）。

#### 1.2 XML 格式校验
```bash
xmllint --noout /workspace/build/M2/system/odm/etc/media_codecs_c2.xml
xmllint --noout /workspace/build/M2/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml
```
**目标**：两文件均 exit 0。

#### 1.3 二进制占位核对
```bash
cat /workspace/build/M2/checksums.txt  # 应有 7 行 PENDING
cat /workspace/build/M2/.binaries_pending  # 应有 7 个二进制描述
ls -la /workspace/build/M2/system/vendor/lib64/ 2>&1  # 不存在（符合预期）
```
**目标**：确认 M2 的 `.so` 提取任务清单与当前未落地状态一致。

#### 1.4 自检报告
- 收集所有阶段 1 结果，输出到 `/workspace/.trae/documents/self-check-report.md`
- 包含：每项 PASS/FAIL/WARN + 原始命令输出截取

### 阶段 2：测试（运行 bats 全部用例）

依次执行 7 个 bats 文件（共 130+ 个用例）：
```bash
bats /workspace/build/M1/test/test_customize.bats
bats /workspace/build/M1/test/test_post_fs_data.bats
bats /workspace/build/M1/test/test_service.bats
bats /workspace/build/M2/test/test_decoder_xml.bats
sh /workspace/build/M2/test/validate_media_codecs.sh
sh /workspace/build/M2/test/verify_checksums.sh
bats /workspace/build/M6/test/test_compat.bats
bats /workspace/build/M6/test/test_pre_install_check.bats
bats /workspace/build/M6/test/test_sepolicy.bats
```
- 收集 PASS / FAIL 计数
- 失败用例记录原始错误输出
- 报告落盘：`/workspace/.trae/documents/test-report.md`

**已知风险**：
- `test_compat.bats` / `test_pre_install_check.bats` 会 `mkdir -p /vendor /odm /data/adb`，可能受环境权限影响
- `verify_checksums.sh` 在 PENDING 状态下应 SKIP（已被脚本实现）

### 阶段 3：打包

#### 3.1 决定打包边界
- **打包**：M1（完整）+ M2 的 XML/VINTF/配置 + M6（META-INF 完整）
- **不打包**：M2 的 `.so` 二进制（未提取）、M3/M4/M5（未实施）
- **额外入包**：自检报告 + 测试报告 + MANIFEST

#### 3.2 生成 MANIFEST.md
`/workspace/build/MANIFEST.md`，内容：
- 模块 ID / 版本 / 设备目标
- 文件清单（按模块分组，附 SHA256 + size）
- 质量门禁结果（shellcheck / xmllint / bats / checksum-pending 标记）
- 已知缺失项（M2 .so / M3-M5）

#### 3.3 生成 ZIP
```bash
cd /workspace/build && zip -r dolby-atmos-op-folk-v1.0.0-dev.zip \
  M1/ M2/ M6/ MANIFEST.md \
  -x "M2/.binaries_pending" "M2/checksums.txt" "**/test/*"
# 校验
zip -T dolby-atmos-op-folk-v1.0.0-dev.zip
unzip -l dolby-atmos-op-folk-v1.0.0-dev.zip
```
- **排除**：`M2/.binaries_pending`（仅开发占位）、`checksums.txt`（无实际值）、`test/`（构建期产物不入分发包）
- 输出：`/workspace/build/dolby-atmos-op-folk-v1.0.0-dev.zip`

### 阶段 4：构建 GitHub 仓库

#### 4.1 添加 .github/workflows/
- `.github/workflows/ci.yml`：Ubuntu-latest，运行 shellcheck + xmllint + 全部 bats，用 matrix 列出每个测试文件，PR/push 触发
- `.github/workflows/release.yml`：tag 触发，自动 `zip` 打包 + 创建 GitHub Release（用 `softprops/action-gh-release`）

#### 4.2 添加仓库基础设施
- `.gitignore`：忽略 `*.zip`、`build/M2/system/vendor/lib64/*.so`、`/data/`、`/vendor/`、`/odm/` 等运行时残留
- `CONTRIBUTING.md`：开发约定（POSIX sh / 质量门禁 / bats 必须随实现）
- 更新 `README.md`：补充模块功能 / 安装 / 风险警告 / 设备列表 / 自检命令 / 致谢
- `LICENSE`：Apache-2.0（沿用 spec 提到的宽松协议）

#### 4.3 提交 + 推送
- `git add` 指定文件（不 -A，避免误提交 ZIP / 临时文件）
- 提交信息：`chore: self-check + tests + CI workflows for M1/M2/M6 v1.0.0-dev`
- `git push -u origin trae/agent-6dzWd3`
- 如远程 main 落后，再开 PR 或直接 fast-forward（根据 `git push` 结果决定）

### 不修改的内容
- 不修改 M1/M2/M6 任何现有文件（仅自检与测试，发现问题记录但不修复，除非用户后续要求）
- 不动 `设计/`、`设计加任务/`、`prompt总结/`、`进度/`
- 不创建 M3/M4/M5 实现

## Assumptions & Decisions

1. **优先 `git revert --abort`**：被回滚的提交仅影响我生成的 plan 文档，不影响核心代码；恢复后工作区与 `a2ed5fa` 前等价，符合"自检/测试/打包"需要。
2. **自检不修代码**：用户说"自检"不是"修复"，仅生成报告。
3. **打包用 `-dev` 后缀**：M2 .so 缺失 + M3-M5 未实施，不能称 v1.0.0 GA。
4. **GitHub 仓库"构建"= 添加 CI/基础设施 + 推送**：无 `gh` CLI，使用 git 直推。
5. **不强制 PR**：当前在 feature 分支 `trae/agent-6dzWd3`，推送后由用户决定是否合 main。
6. **不创建 .so 占位**：遵循 spec 的 PENDING 设计，避免误导用户。
7. **质量门禁不阻塞**：若某 bats 用例失败，记录到报告但不中止流水线（用户要求"自检 / 测试 / 打包"，不是"修复"）。

## Verification

每阶段结束给出明确指标：
- 阶段 1：每个文件 PASS/FAIL/WARN 计数
- 阶段 2：总用例数、通过数、失败数、SKIP 数
- 阶段 3：`zip -T` 输出 OK + `unzip -l` 列出 N 个文件
- 阶段 4：`git push` 成功 + 远程分支可见 + CI yaml 通过 `actionlint`（如有）

最终交付物清单：
- `/workspace/.trae/documents/self-check-report.md`
- `/workspace/.trae/documents/test-report.md`
- `/workspace/build/dolby-atmos-op-folk-v1.0.0-dev.zip`
- `/workspace/build/MANIFEST.md`
- `/workspace/.github/workflows/{ci,release}.yml`
- `/workspace/.gitignore`、`CONTRIBUTING.md`、`LICENSE`、更新后 `README.md`
