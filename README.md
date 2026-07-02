# Dolby-ATMOS-OP-folk

> 杜比全景声一加补全适配 —— KSU / Magisk / APatch 通用 Magisk 模块

[![CI](https://github.com/hf5203344/Dolby-ATMOS-OP-folk/actions/workflows/ci.yml/badge.svg)](https://github.com/hf5203344/Dolby-ATMOS-OP-folk/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## 项目状态

**当前版本**：`v1.0.0-dev`（开发版，非 GA）

| 模块 | 状态 | 说明 |
|---|---|---|
| M1 — KSU 模块打包框架 | ✅ 已落地 | 6 阶段安装、3 个 bats 测试套件全过 |
| M2 — 杜比解码器 | 🟡 部分落地 | XML 声明完成，6 个 .so + 1 service 二进制待提取 |
| M3 — 杜比音效链 | 🔲 未实施 | 任务清单已编写 |
| M4 — 配置 APK | 🔲 未实施 | 任务清单已编写 |
| M5 — 诊断工具 | 🔲 未实施 | 任务清单已编写 |
| M6 — 兼容性适配 | ✅ 已落地 | 10 个检测函数 + SELinux 策略，76 个 bats 用例全过 |
| Phase 4 — 集成 ZIP | 🟡 dev 已生成 | `build/dolby-atmos-op-folk-v1.0.0-dev.zip` |

> ⚠️ **当前 dev ZIP 不含运行所需 .so / APK，不可直接刷入设备运行**。仅用于集成测试、CI 烟测、协作开发。

## 目标设备

| 设备代号 | 设备名 | 蓝牙采样率 | 状态 |
|---|---|---|---|
| PKG110 | OnePlus ACE5 | 48 kHz | 主目标 |
| PKG120 | OnePlus ACE5 Pro | 96 kHz | 兼容 |
| PKG130 | OnePlus ACE5 Pro (高配) | 96 kHz | 兼容 |

## 兼容性

- **Root**: KSU（主）、Magisk ≥ v25.2、APatch
- **Android**: 14+ (SDK ≥ 34)
- **架构**: arm64-v8a
- **音频 HAL**: AIDL 与 HIDL 双栈自适应

## 功能特性

- **AC-3 / E-AC-3 / E-AC-3-JOC / AC-4** 软件解码器注册（C2 framework）
- **DMS AIDL 服务** + **Codec2 HIDL 服务** 启动与守护
- **AudioX 特性** 挂载（`oplus.software.audio.dolby_support`）
- **SELinux 策略** 注入（4 类 allow 规则，DMS/C2 与 audioserver/mediacodec/audio_device 互通）
- **多机型蓝牙采样率** 自动适配（PKG110 → 48kHz，PKG120/130 → 96kHz）
- **配置 APK**（待实施）+ **诊断工具**（待实施）

## 快速开始（开发者）

```bash
# 克隆
git clone https://github.com/hf5203344/Dolby-ATMOS-OP-folk.git
cd Dolby-ATMOS-OP-folk

# 自检
shellcheck -s sh build/M1/*.sh build/M1/META-INF/compat.sh build/M6/META-INF/compat.sh
xmllint --noout build/M2/system/odm/etc/media_codecs_c2.xml

# 跑测试
bats build/M1/test/*.bats build/M2/test/*.bats build/M6/test/*.bats
sh build/M2/test/validate_media_codecs.sh
sh build/M2/test/verify_checksums.sh   # 当前 SKIP（.so 未提取）

# 打包
cd build && zip -r dolby-atmos-op-folk-dev.zip M1 M2 M6 MANIFEST.md \
    -x "M1/test/*" "M2/test/*" "M6/test/*" "M2/.binaries_pending"
```

## 安装（用户，**待 v1.0.0 GA 后**）

> ⚠️ **当前 dev 版不可安装**。请等待 v1.0.0 GA（含 .so + APK）。

```bash
# 在 KSU / Magisk / APatch Manager 中刷入 ZIP
# 或命令行：
adb push dolby-atmos-op-folk-v1.0.0.zip /sdcard/
adb shell su -c "magisk --install-module /sdcard/dolby-atmos-op-folk-v1.0.0.zip"
```

## ⚠️ 风险警告

本模块修改系统音频栈 (`vendor/lib64`、`vendor/bin/hw`、`odm/etc`、`my_product/etc`)，不当安装可能导致：

- 无法开机（最坏情况，需刷回原厂固件）
- 音频服务崩溃
- 系统卡顿

**安装前必须**：
1. 备份重要数据
2. 准备原厂固件刷机包（救砖用）
3. 了解你的 Root Manager 的模块禁用方法

非 OnePlus / OPPO 设备**兼容性未验证**，不建议刷入。

## 仓库结构

```
.
├── .github/workflows/        # CI / Release
├── .trae/specs/              # 规范 (来源真相)
├── build/                    # 模块产物
│   ├── M1/ ... M6/
│   ├── MANIFEST.md
│   └── dolby-atmos-op-folk-v1.0.0-dev.zip
├── 设计/ 设计加任务/ prompt总结/ 进度/   # 本地参考材料
├── CONTRIBUTING.md           # 贡献指南
├── LICENSE                   # Apache-2.0
└── README.md                 # 本文件
```

## 文档

- [规范 `.trae/specs/init-dolby-atmos-ksu-module/spec.md`](.trae/specs/init-dolby-atmos-ksu-module/spec.md)
- [任务清单 `.trae/specs/init-dolby-atmos-ksu-module/tasks.md`](.trae/specs/init-dolby-atmos-ksu-module/tasks.md)
- [验收清单 `.trae/specs/init-dolby-atmos-ksu-module/checklist.md`](.trae/specs/init-dolby-atmos-ksu-module/checklist.md)
- [集成清单 `build/MANIFEST.md`](build/MANIFEST.md)
- [贡献指南 `CONTRIBUTING.md`](CONTRIBUTING.md)

## 致谢

- Dolby Laboratories —— 提供杜比解码参考实现
- Qualcomm —— AC-4 硬件解码参考
- KernelSU / Magisk / APatch —— Root 框架
- oneplus-folk 社区 —— 设计参考与多机型数据

## 免责声明

本项目为**非商业、互操作性研究**用途。杜比相关商标与解码技术归 Dolby Laboratories 所有。

本项目作者不为因使用本模块造成的设备损坏、数据丢失承担任何责任。使用即视为同意自行承担风险。
