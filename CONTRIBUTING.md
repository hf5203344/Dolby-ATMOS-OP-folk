# Contributing to Dolby-ATMOS-OP-folk

感谢你愿意为 OnePlus ACE5 系列的杜比全景声适配做出贡献。本项目面向开发者与小范围测试者，请先阅读以下约定再提交 PR。

## 1. 仓库结构

```
.
├── .github/workflows/        # CI 与 Release 工作流
├── .trae/
│   ├── specs/                # 规范、任务清单、验收清单 (来源真相)
│   └── documents/            # 流水线报告 (不入版本控制)
├── build/
│   ├── M1/                   # KSU 模块打包框架
│   ├── M2/                   # 杜比解码器 (XML + 二进制)
│   ├── M3/                   # 杜比音效链 (待实施)
│   ├── M4/                   # 配置 APK (待实施)
│   ├── M5/                   # 诊断工具 (待实施)
│   ├── M6/                   # 兼容性适配 (compat.sh + sepolicy)
│   └── MANIFEST.md           # 集成清单 (本仓库 ZIP 的来源)
├── 设计/                     # 原始设计材料 (本地参考)
├── 设计加任务/                # 任务拆解 (本地参考)
├── prompt总结/                # AI prompt 历史 (本地参考)
└── 进度/                      # 进度记录 (本地参考)
```

## 2. 编码规范

### Shell 脚本 (POSIX sh)

- **严格 POSIX sh**：使用 `set -e` / `set -u` / `set -o pipefail` 之一；不依赖 bash 特性
- **函数必须先定义再调用**（POSIX sh 要求）
- **`local` 局部变量**：可用（Android `/system/bin/sh` 实际为 mksh，支持 local）；shellcheck SC3043 可在文件头 `shellcheck disable=SC3043`
- **日志与 abort**：使用 `ui_print` / `abort` / `log` 函数，不要直接 `echo` 到 stdout
- **错误信息**：使用中文（项目面向中文用户）
- **路径**：尽量使用相对模块根的路径；不假设 `$PATH` 中有 busybox 以外工具

### XML

- 顶部必须有 `<?xml version="1.0" encoding="utf-8" ?>`
- 缩进 4 空格
- 通过 `xmllint --noout` 零错误

### Kotlin (M4)

- Kotlin 1.9+, minSdk 34, targetSdk 35
- ViewBinding（不用 Compose、不用 Hilt/Koin）
- Material 3 主题
- 通过 `./gradlew detekt ktlintCheck test` 零错误

## 3. 质量门禁 (必过)

提交 PR 前本地执行：

```bash
# Shell 静态检查
shellcheck -s sh build/M1/*.sh build/M1/META-INF/compat.sh \
                   build/M6/META-INF/compat.sh

# XML 格式
xmllint --noout build/M2/system/odm/etc/media_codecs_c2.xml
xmllint --noout build/M2/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml

# 单元测试
bats build/M1/test/*.bats
bats build/M2/test/*.bats
bats build/M6/test/*.bats
sh build/M2/test/validate_media_codecs.sh
sh build/M2/test/verify_checksums.sh
```

CI 会自动运行上述命令，**任何一项失败都不允许合并**。

## 4. bats 单元测试约定

- **每个 shell 函数必须有对应测试**：新增函数时同步添加 bats 用例
- **测试函数名**：`@test "<函数>: <场景描述>"`
- **测试文件**：`build/<模块>/test/test_<脚本>.bats`
- **覆盖率目标**：正常路径 + 异常路径 + 边界值
- **bats ≥ 1.5.0**（`bats_require_minimum_version 1.5.0`）

## 5. SELinux 策略

- **修改 sepolicy.rule 时**：每条规则必须对应一个 spec.md 中明确列出的能力
- **`@` 符号**：在 SELinux type 名中必须写成 `_`（如 `c2@1.0-service` → `c2_1_0_service`）
- **回归测试**：运行 `bats build/M6/test/test_sepolicy.bats`，确保关键字覆盖与行为测试全过

## 6. 提交规范

- 提交信息使用英文祈使句：`feat: add M3 audio effects merge`
- 范围限定：`<type>(<scope>): <subject>`，type ∈ {feat, fix, refactor, docs, test, chore}
- 一次提交只解决一个原子问题
- 不要把 ZIP 产物、`.trae/documents/` 报告、`*.so` 提交到版本控制

## 7. 提交流程

1. Fork → 创建 feature branch (`feat/<scope>-<desc>`)
2. 编写代码 + 同步添加 bats 测试
3. 本地跑通质量门禁
4. Push → 提交 PR 到 `main`
5. 等 CI 全绿 + 1 位维护者 review

## 8. 设备测试

- 仅 OnePlus ACE5 / ACE5 Pro 可作为验收设备
- 每次涉及 M1 customize.sh / service.sh / uninstall.sh 的修改，必须在真机上跑：
  - 全新安装
  - 卸载（确认残留清理）
  - 升级安装（从旧版本）
- 失败案例请附 `dmesg` + `logcat -d -s DolbyAtmosControl:V` 到 issue

## 9. 联系方式

- GitHub Issues: 缺陷 / 功能请求
- GitHub Discussions: 通用问题 / 设计讨论

## 10. 许可证

贡献者协议：Apache-2.0。提交 PR 即视为同意以 Apache-2.0 许可发布。
