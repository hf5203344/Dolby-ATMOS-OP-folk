# Dolby Atmos KSU 模块 — 修复后设计计划

> **模式:** 计划模式 (Plan Mode)
> **任务:** 深入审查 6 个模块设计文档, 修复 4 个 Critical + 11 个 High 问题, 重写原设计文档
> **生成日期:** 2026-07-02
> **基础:** 已完成的 [设计审查-v1.0.md](file:///workspace/%E8%AE%BE%E8%AE%A1%E5%AE%A1%E6%9F%A5-v1.0.md)

---

## 1. 范围确认

| 范围 | 选择 | 数量 |
|------|------|------|
| 修复问题 | 仅 Critical + High | 4 + 11 = 15 个 |
| 输出格式 | **重写原文档** (用户指定) | 6 个独立文档 |
| 修复内容 | 设计层面 + 关键代码片段 | 不实施, 不写可运行代码 |
| 保留 | 文档结构、接口契约、模块职责 | — |

---

## 2. 修复问题清单 (15 个)

### 2.1 Critical (4 个)

| # | 模块 | 问题 | 修复方案 |
|---|------|------|----------|
| C-1 | M1 + M6 | `detect_root_solution()` 在 M1/M6 中重复定义, source 后冲突 | M1 保留完整版, M6 改为 `detect_root_solution_v2()` 仅做 echo |
| C-2 | M2 | 6 个 `.so` 的 SHA256 "待确认" 阻塞集成测试 | 新增 "二进制 SHA256 计算与校验" 章节, 给出 build 脚本流程 |
| C-3 | M4 | 文档自相矛盾: 1.3 节"手动 DI" vs 4.6 节"@AndroidEntryPoint" | 统一为手动 DI, 删除 `@AndroidEntryPoint`, 删除 Hilt 依赖 |
| C-4 | M4 | `Preset.ROCK/POP/CLASSICAL/JAZZ/VOCAL/FLAT` 在 EqualizerViewModel 引用, 但枚举不存在 | 重构为统一的 `EqualizerPreset` 枚举 (10 种), 区分 `DolbyPreset` (5 种, 来自 M3) |

### 2.2 High (11 个)

| # | 模块 | 问题 | 修复方案 |
|---|------|------|----------|
| H-1 | M1 | `getevent -qlc 1` PATH 兼容性, 超时无明确退出 | 增加 fallback: 没有 getevent 时, 5 秒超时直接默认安装 |
| H-2 | M1 | `clean_old_artifacts` 硬编码 `daxapp/daxcontroller` 不通用 | 改为根据 `module.prop` 中 `id` 前缀通配清理 |
| H-3 | M1 | APK SELinux 上下文错误 (`system_file`) | 改为 `privapp` 类型上下文 |
| H-4 | M1+M5 | 探针清理在 M1 service.sh 和 M5 action.sh 重复 | M1 保留主清理, M5 改为只读 (不重复清理) |
| H-5 | M2 | VINTF `default1`/`default2` 指向未明确 | 文档中明确: `default2` → Qualcomm, `default1` → Dolby, 互斥 |
| H-6 | M3 | `merge_audio_effects` awk 只处理 music 流 | 扩展为处理 music/ring/alarm/system/notification/voice_call 全部流 |
| H-7 | M3 | gsub 只修正 3 个固定路径 | 改为更通用的"提取 basename"逻辑 |
| H-8 | M4 | `MainViewModel.init` 协程在重建时重复启动 | 改用 `viewModelScope.launch` + `repeatOnLifecycle`, 仅 STARTED 时执行 |
| H-9 | M4 | 系统权限需要 platform 签名, 文档无方案 | 新增 "签名与权限" 章节: 提供 platform.pem 提取流程 + 签名脚本 |
| H-10 | M5 | `set -e` 太严格, 一个错误就停止采集 | 改为 `set +e`, 关键步骤显式错误处理 |
| H-11 | M6 | `detect_audio_stack` 单文件检测不可靠 | 改为多信号综合判断: 文件 + prop + dumpsys |

---

## 3. 输出文件清单

每个原文档重写为一个 `*-fixed.md` 文件:

| 原文档 | 修复后文件 | 修复问题 | 行数预估 |
|--------|------------|----------|----------|
| `M1-ksu-module-framework.md` (962 行) | `设计-修复/M1-ksu-module-framework-fixed.md` | C-1, H-1, H-2, H-3, H-4 | ~1100 行 |
| `M2-dolby-decoder.md` (315 行) | `设计-修复/M2-dolby-decoder-fixed.md` | C-2, H-5 | ~400 行 |
| `M3-dolby-audio-effect.md` (476 行) | `设计-修复/M3-dolby-audio-effect-fixed.md` | H-6, H-7 | ~550 行 |
| `M4-config-apk.md` (1291 行) | `设计-修复/M4-config-apk-fixed.md` | C-3, C-4, H-8, H-9 | ~1500 行 |
| `M5-diagnostics.md` (432 行) | `设计-修复/M5-diagnostics-fixed.md` | H-4, H-10 | ~450 行 |
| `M6-compatibility.md` (340 行) | `设计-修复/M6-compatibility-fixed.md` | C-1, H-11 | ~400 行 |
| **合计** | | | **~4400 行** |

---

## 4. 修复设计原则

1. **保留未改动的章节**: 大部分原文档的章节、表格、序列图不需修改, 完整保留
2. **明确标注改动**: 在每个改动处增加 `🔧 FIX: <编号>` 标记, 注明原问题编号和修复说明
3. **修复后保留向后兼容**: 不删除任何对外接口, 只修正实现细节
4. **修复后保持文档结构**: 6 大章节结构、版本历史、附录均保留
5. **修复以"最小破坏"为原则**: 仅修改必要代码, 不大规模重写

---

## 5. 执行步骤

1. ✅ Phase 1: 探索项目上下文
2. ✅ Phase 2: 与用户确认修复范围 (已完成: C+H, 重写原文档)
3. ⏳ Phase 3: 编写本计划
4. ⏸ Phase 4: 通知用户, 请求批准
5. ⏳ 执行: 创建 6 个 fixed 文档
6. ⏳ 自检: 扫描 6 文档, 确认所有 C/H 都有 FIX 标记
7. ⏳ 提交 6 文档给用户

---

## 6. 修复后变更摘要表 (Cross-Module)

将在 6 文档头部统一放置以下 "本版本变更摘要" 表格:

```markdown
| # | 类型 | 模块 | 章节 | 修复内容 |
|---|------|------|------|----------|
| C-1 | Critical | M1+M6 | 兼容 | detect_root_solution 二选一 |
| C-2 | Critical | M2 | 二进制 | SHA256 计算流程 |
| ... | ... | ... | ... | ... |
```

---

## 7. 不做什么

| 不做 | 原因 |
|------|------|
| ❌ 修改 Medium/Low 问题 | 用户仅要求 C+H |
| ❌ 实际编写可运行代码 | 用户要求"设计"层面 |
| ❌ 重命名函数/接口 | 保持向后兼容 |
| ❌ 修改 INDEX.md 和 progress.md | 用户仅要求修复 6 个模块设计 |
| ❌ 创建 ZIP 包 | 设计阶段, 不到打包时机 |

---

## 8. 风险与依赖

| 风险 | 应对 |
|------|------|
| 6 文档总行数 ~4400, 单次 Write 可能失败 | 拆分多次 Write, 每个文档单独 Write |
| 修复可能引入新矛盾 | 自检阶段交叉检查 UUID/路径一致性 |
| 修复后与原文档不一致 | 明确文档名为 "-fixed", 区分原版 |
