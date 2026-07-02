# MANIFEST — dolby-atmos-op-folk-v1.0.0-dev

> **模块 ID**: `dolby_atmos_oplus_folk`
> **版本**: `v1.0.0-dev` (开发版,非 GA)
> **目标设备**: OnePlus ACE5 (PKG110) / ACE5 Pro (PKG120 / PKG130)
> **Root 兼容**: KSU (主) / Magisk (≥ v25.2) / APatch
> **最低 Android**: 14 (SDK 34)
> **架构**: arm64-v8a
> **生成日期**: 当前流水线输出

---

## 1. 质量门禁结果

| 门禁 | 状态 | 备注 |
|---|---|---|
| shellcheck (9 文件) | ✅ 7 PASS / 2 WARN (M2 test 脚本) | 0 error，2 warning 详情见 self-check-report.md |
| xmllint (2 XML) | ✅ 2/2 PASS | 0 error |
| bats 测试 | ✅ 152/152 PASS / 15 SKIP | 0 failure，SKIP 来自 M3/M2 待办 |
| 二进制占位核对 | ✅ PASS | 7 PENDING 符合预期 |
| ZIP 完整性 | ✅ PASS | `zip -T` OK |

---

## 2. 文件清单 (15 个,按模块分组)

### M1 — KSU 模块打包框架 (10 文件)
| SHA256 (前 12) | Size (B) | 路径 |
|---|---|---|
| `71a2c935d53c` | 824 | `M1/META-INF/com/google/android/update-binary` |
| `d2b8203193a0` | 8 | `M1/META-INF/com/google/android/updater-script` |
| `2e5d0d556bb8` | 8523 | `M1/META-INF/compat.sh` |
| `03668f37e546` | 12004 | `M1/customize.sh` |
| `b8abc3541b10` | 345 | `M1/module.prop` |
| `89665e29ce8e` | 1881 | `M1/post-fs-data.sh` |
| `d84d9a4037af` | 5375 | `M1/service.sh` |
| `9057442f3391` | 193 | `M1/system.prop` |
| `b6cb1ebaede7` | 2060 | `M1/uninstall.sh` |
| `bc08d529e99f` | 615 | `M2/checksums.txt` (兼容 M2 引用) |

### M2 — 杜比解码器 (2 文件)
| SHA256 (前 12) | Size (B) | 路径 |
|---|---|---|
| `33b39ca0c80f` | 1736 | `M2/system/odm/etc/media_codecs_c2.xml` |
| `f0fa2521d0ce` | 603 | `M2/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml` |

### M6 — 兼容性适配 (2 文件)
| SHA256 (前 12) | Size (B) | 路径 |
|---|---|---|
| `2e5d0d556bb8` | 8523 | `M6/META-INF/compat.sh` |
| `2a8c09c1a8e6` | 1080 | `M6/META-INF/sepolicy.rule` |

### 集成元数据
| SHA256 (前 12) | Size (B) | 路径 |
|---|---|---|
| (本文件) | — | `MANIFEST.md` |

---

## 3. 已知缺失项 (本版本不包含)

| 项 | 状态 | 影响 | 解除条件 |
|---|---|---|---|
| 6 个杜比解码器 `.so` | PENDING | M2 解码器无法运行时加载 (AC-3/E-AC-3/JOC/AC-4 全部缺失) | 从参考设备提取后填入 `M2/system/vendor/lib64/` 并替换 checksums.txt |
| `vendor.dolby_sp.media.c2@1.0-service` | PENDING | Codec2 HAL 服务无法启动 | 同上 |
| 7 个 DMS 库 + 3 个 DAP 库 | 未实现 | M3 音效链无法部署 | M3 落地 |
| `audio_effects.xml` | 未实现 | DAP 效果未注入 | M3 落地 |
| `oplus.product.features_audiox.xml` | 未实现 | AudioX 特性未声明 | M3 落地 |
| `multimedia_dolby_dax_dflt.xml` | 未实现 | DAP 调音参数缺失 | M3 落地 |
| `DolbyAtmosControl.apk` | 未实现 | 配置入口缺失 | M4 落地 |
| `action.sh` 诊断工具 | 未实现 | 端到端诊断缺失 | M5 落地 |

---

## 4. 安装前置要求

1. **设备**: OnePlus ACE5 / ACE5 Pro，已解锁 Bootloader
2. **Root**: 任意一种 KSU / Magisk (≥ v25.2) / APatch
3. **Android**: 14+ (SDK ≥ 34)
4. **架构**: arm64-v8a

---

## 5. 风险与免责

- 本模块修改系统音频栈 (vendor/lib64 / vendor/bin/hw / odm/etc / my_product/etc),不当安装可能导致:
  - 无法开机
  - 音频服务崩溃
  - 系统卡顿
- 请在安装前备份重要数据
- 一加/OPPO 以外设备兼容性未验证
- 当前 v1.0.0-dev 仅含框架与 XML 声明，**缺少运行所需 .so / .apk**；实际刷入后**音频服务无法启动**

---

## 6. 下一里程碑

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M3 落地 | 音效链 (DMS 库 + audio_effects.xml + features_audiox.xml) | 🔲 任务清单已编写,实现未启动 |
| M4 落地 | 配置 APK (DolbyAtmosControl) | 🔲 任务清单已编写,实现未启动 |
| M5 落地 | 诊断 action.sh | 🔲 任务清单已编写,实现未启动 |
| .so 提取 | 从参考设备提取 6 个 .so + 1 service | 🔲 任务清单已编写,执行未启动 |
| Phase 4 | 集成 ZIP / E2E / 最终 MANIFEST | 🔲 阻塞于 M3-M5 + .so 提取 |
| v1.0.0 GA | 上述全部完成后发布 | 🔲 阻塞 |
