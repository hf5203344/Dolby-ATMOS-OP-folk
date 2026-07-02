# Phase 1 实施计划 + 仓库整理 — 总计划

> **模式:** 计划模式 (Plan Mode)
> **任务:**
> 1. 编写 Phase 1 实施计划 (M1+M6+M2, 使用 writing-plans 思路)
> 2. 删除 3 个原始 zip
> 3. 整理仓库结构, 把所有产出放进去
> **生成日期:** 2026-07-02
> **基础:**
> - [设计审查-v1.0.md](../../设计审查-v1.0.md)
> - [设计-修复/](../设计-修复/) 6 份修复设计

---

## 1. 背景

`/workspace` 现状:

```
/workspace/
├── 设计.zip          ← 删除
├── 设计加任务.zip    ← 删除
├── prompt总结.zip    ← 解压后保留 prompt.md
├── 进度              ← 空文件 (1 byte), 转为文件夹
├── 设计审查-v1.0.md           ← 我的产出, 移到 docs/
├── 设计-修复/                  ← 我的产出, 6 份修复设计, 移到 docs/修复设计/
└── .trae/documents/            ← 我的产出, 计划文件
```

用户已确认:
- Implementation plan 范围: **只 Phase 1 (M1+M6+M2)** ≈ 80 个子任务
- 仓库结构: **删除原始 zip, 整理文件夹, 包含我的产出**

---

## 2. 最终仓库结构 (目标)

```
/workspace/
├── README.md                                    # 项目总览, 指向 docs/ 各文档
├── 进度/                                        # 进度跟踪 (原空文件转文件夹)
│   ├── README.md                                # 进度说明
│   └── Phase1-进度跟踪.md                       # Phase 1 任务进度表
├── docs/                                        # 全部文档
│   ├── 01-设计审查-v1.0.md                      # 设计审查报告 (原 设计审查-v1.0.md)
│   ├── 02-修复设计/                             # 修复后的 6 份设计文档
│   │   ├── M1-ksu-module-framework-fixed.md
│   │   ├── M2-dolby-decoder-fixed.md
│   │   ├── M3-dolby-audio-effect-fixed.md
│   │   ├── M4-config-apk-fixed.md
│   │   ├── M5-diagnostics-fixed.md
│   │   └── M6-compatibility-fixed.md
│   └── 03-实施计划/                             # 实施计划
│       ├── Phase1-实施计划.md                   # 本次产出
│       └── 总览.md                              # Phase 1-5 概览
├── workflow/                                    # 工作流
│   └── prompt.md                                # Vibe Coding workflow (从原 prompt总结.zip 解压)
└── plans/                                       # Trae 计划文件 (从 .trae/documents 迁出)
    ├── dolby-atmos-design-review-plan.md
    ├── dolby-atmos-design-fix-plan.md
    └── dolby-atmos-phase1-and-reorg-plan.md    # 本文件
```

---

## 3. Phase 1 实施计划范围

**目标:** 实现 Dolby Atmos KSU 模块的 Phase 1 (M1+M6+M2), 形成可安装的 ZIP 包.

### 3.1 范围

| 模块 | 任务数 (来自 progress.md) | 复杂度 |
|------|---------------------------|--------|
| M1 KSU 框架 | 51 | 中 |
| M2 解码器 | 39 | 中 |
| M6 兼容性 | 35 | 低 |
| **Phase 1 合计** | **125** | **~1500 行 plan** |

### 3.2 不在范围 (留到后续 Phase)

| 模块 | 计划阶段 |
|------|----------|
| M3 音效链 | Phase 2 |
| M5 诊断 | Phase 2 |
| M4 APK | Phase 3 |

---

## 4. 实施计划文档结构

`docs/03-实施计划/Phase1-实施计划.md` 包含:

### 4.1 总览
- 目标 / 范围 / 不做事项
- 关键路径
- 关键修复 (C-1, C-2, H-1~H-5, H-11)

### 4.2 前置准备 (Phase 0, 1-2 天)
- 收集参考模块二进制
- 计算 SHA256 (C-2)
- 提取 platform.pem (H-9 准备)
- 准备测试设备

### 4.3 M1 实施 (51 任务, ~3-5 天)
- module.prop / customize.sh / post-fs-data.sh / service.sh / system.prop / uninstall.sh
- 关键修复:
  - C-1: detect_root_solution 完整版
  - H-1: getevent fallback
  - H-2: clean_old_artifacts 通配
  - H-3: APK 上下文 privapp
  - H-4: clean_probe 保留在 M1, M5 改为只读

### 4.4 M6 实施 (35 任务, ~2-3 天)
- META-INF/compat.sh
- 关键修复:
  - C-1: 不重定义 M1 函数, 改用 compat_ 前缀
  - H-11: compat_detect_audio_stack_v2 多信号投票

### 4.5 M2 实施 (39 任务, ~3-5 天)
- 解码器 .so 部署
- media_codecs_c2.xml / c2_manifest_vendor_audio.xml
- Codec2 HIDL 服务启动
- 关键修复:
  - C-2: SHA256 计算与校验流程
  - H-5: VINTF default1=Dolby, default2=Qualcomm

### 4.6 集成测试 (~1-2 天)
- ZIP 打包
- 在真机安装
- 验证 4 大关键路径
- 自动化测试套件

### 4.7 验收标准
- 286/286 子任务 (Phase 1 部分: 125/125) 完成
- 所有 Critical/High 修复在代码中落地
- 集成测试通过
- 文档同步更新

---

## 5. 仓库整理执行步骤

### 5.1 删除原始 zip

```bash
rm -f /workspace/设计.zip
rm -f /workspace/设计加任务.zip
rm -f /workspace/prompt总结.zip
```

### 5.2 解压 prompt.md 到 workflow/

```bash
unzip -p /workspace/prompt总结.zip '*' 2>/dev/null || \
  (cd /tmp && unzip -o /workspace/prompt总结.zip -d /tmp/prompt_extract/)
# 拷贝 prompt.md (注意: zip 已删除, 先备份解压)
# 实际: 先解压到临时目录, 再删除 zip
```

(注: 由于 zip 包含在原 prompt 路径的 6a425bdc061cf7478c0b7de5_prompt.md, 解压后转存)

### 5.3 创建目标目录

```bash
mkdir -p /workspace/进度
mkdir -p /workspace/docs/02-修复设计
mkdir -p /workspace/docs/03-实施计划
mkdir -p /workspace/workflow
mkdir -p /workspace/plans
```

### 5.4 移动文件

```bash
# 移动我的产出
mv /workspace/设计审查-v1.0.md /workspace/docs/01-设计审查-v1.0.md
mv /workspace/设计-修复/*.md /workspace/docs/02-修复设计/
rmdir /workspace/设计-修复

# 移动计划文件
mv /workspace/.trae/documents/dolby-atmos-design-review-plan.md /workspace/plans/
mv /workspace/.trae/documents/dolby-atmos-design-fix-plan.md /workspace/plans/
mv /workspace/.trae/documents/dolby-atmos-phase1-and-reorg-plan.md /workspace/plans/

# 移动解压后的 prompt.md
mv /tmp/prompt_extract/prompt总结/6a425bdc061cf7478c0b7de5_prompt.md /workspace/workflow/prompt.md
rm -rf /tmp/prompt_extract
```

### 5.5 创建新文档

1. `/workspace/README.md` — 项目总览
2. `/workspace/进度/README.md` — 进度说明
3. `/workspace/进度/Phase1-进度跟踪.md` — Phase 1 任务清单
4. `/workspace/docs/03-实施计划/Phase1-实施计划.md` — Phase 1 实施计划
5. `/workspace/docs/03-实施计划/总览.md` — Phase 1-5 概览

### 5.6 验证最终结构

```bash
find /workspace -type f -name "*.md" | sort
# 预期: 15-20 个 .md 文件, 分布在 docs/ plans/ workflow/ 进度/
```

---

## 6. 不做什么

| 不做 | 原因 |
|------|------|
| ❌ 实现 M3/M5/M4 实施计划 | Phase 2-3 范围, 用户未要求 |
| ❌ 实际编写代码 (Shell/Kotlin) | 用户要求"实施计划"层面 |
| ❌ 实际计算 18 个二进制 SHA256 | 需要真实参考模块, 计划中标注"待 Phase 0 完成" |
| ❌ 创建 ZIP 包 | Phase 1 实施后再打包 |
| ❌ 初始化 git 仓库 | 用户未要求 |

---

## 7. 风险与依赖

| 风险 | 应对 |
|------|------|
| Phase 1 实施计划过长 (125 任务) | 分章节, 每模块一节, 任务列表用表格 |
| 解压 prompt.md 时 zip 已被删 | 先解压到 /tmp 再删除原 zip |
| 路径变化破坏我之前的引用 | 计划文件中说明新路径映射 |
| 进度文件从 1 byte 改为文件夹 | 旧"进度"文件被删除, 替换为同名文件夹 |

---

## 8. 执行步骤

1. ✅ Phase 1: 探索 (已完成)
2. ✅ Phase 2: 与用户确认范围 (已完成: Phase 1 + 删除原始 zip)
3. ⏳ Phase 3: 编写本计划
4. ⏸ Phase 4: 通知用户, 请求批准
5. ⏳ 执行:
   - 删除 3 个 zip
   - 解压 prompt.md
   - 创建目录结构
   - 移动我的产出
   - 编写 Phase 1 实施计划
   - 编写 README 和进度跟踪
6. ⏳ 自检: 验证最终结构
7. ⏳ 提交给用户
