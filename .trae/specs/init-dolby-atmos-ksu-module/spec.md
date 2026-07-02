# Dolby Atmos OnePlus folk popularization (KSU Module) Spec

> **模块 ID:** `dolby_atmos_oplus_folk`
> **版本:** v1.0.0
> **目标设备:** OnePlus ACE5 (PKG110) / ACE5 Pro (PKG120/PKG130)
> **设计输入:** `设计/6a425bdc061cf7478c0b7de5_M{1..6}-*.md` + `设计/INDEX.md`
> **任务输入:** `设计加任务/6a425bdc061cf7478c0b7de5_M{1..6}-*.md` + `设计加任务/progress.md`

---

## Why

仓库内已有完整、经过用户评审的 6 模块详细设计 (M1 框架 / M2 解码器 / M3 音效链 / M4 配置 APK / M5 诊断 / M6 兼容),本 spec 将其收敛为可执行的需求契约,使后续 `apply` 阶段可以并行委派子 Agent 落地,并以可验证的质量门禁作为完成判据。

## What Changes

- **新增** KSU/Magisk/APatch 三 Root 兼容的模块打包框架 (M1: 6 个 shell 脚本 + `module.prop` + `META-INF/`)
- **新增** 杜比解码器集成 (M2: 2 份 XML + 6 个 `.so` + 1 个 HIDL 服务二进制)
- **新增** 杜比音效链 (M3: 1 份 audio_effects.xml 模板 + `merge_audio_effects()` shell 函数 + 7 个 DMS 库 + 3 个 DAP 库 + 1 份特性 XML)
- **新增** 配置 APK `com.dolby.atmos.oplus.folk` (M4: 完整 Android Kotlin 项目, MVVM, 中英 i18n)
- **新增** 诊断工具 `action.sh` (M5: 10 阶段诊断 + 分类报告)
- **新增** 兼容性适配 (M6: `META-INF/compat.sh` + `META-INF/sepolicy.rule`)
- **新增** 集成阶段最终 ZIP 包 `dolby-atmos-op-folk-v1.0.0.zip`
- **不修改** 任何 system/vendor 分区,通过 KSU overlay + mount-bind 注入
- **不引入** Hilt/Koin/Compose;M4 使用 ViewModel + Repository + ViewBinding,精简依赖以控制 APK 体积

## Impact

- **Affected specs:** 无 (本仓库内首次落地)
- **Affected code:**
  - 新建: `/workspace/build/M1..M6/` 全部产物
  - 新建: `/workspace/build/dolby-atmos-op-folk-v1.0.0.zip` (Phase 4)
  - 不动: `/workspace/prompt总结/`、`/workspace/设计/`、`/workspace/设计加任务/`、`/workspace/README.md`
- **Affected platforms:**
  - 设备: OnePlus ACE5 系列 (PKG110 / PKG120 / PKG130),arm64-v8a,Android 14+ (SDK ≥ 34)
  - Root 方案: KSU (主)、Magisk (≥ v25.2)、APatch

---

## ADDED Requirements

### Requirement: 模块打包框架 (M1)

The system SHALL 提供 KSU/Magisk/APatch 三 Root 兼容的模块打包框架,作为 M2-M6 的挂载基座。

#### Scenario: 安装阶段兼容性检测
- **WHEN** 用户在 KSU/Magisk/APatch Manager 中刷入模块 ZIP
- **THEN** `customize.sh` 依次执行 Root 方案检测、Android SDK ≥ 34 校验、芯片平台检测、设备型号检测、arm64-v8a 架构检测、音频栈 (AIDL/HIDL) 检测,任一硬性条件不满足时调用 `abort()` 中止安装并输出原因
- **AND** 检测结果写入 `$MODPATH/.audio_stack_type` 与 `$MODPATH/.install_info`

#### Scenario: 文件权限与 SELinux 上下文
- **WHEN** `customize.sh` 完成检测
- **THEN** 通过 `perm_recursive()` / `perm_one()` 为 `system/vendor/bin/hw/*`、`system/vendor/lib64/**`、`system/odm/etc/**`、`my_product/etc/permissions/**`、`system/system_ext/**` 设置正确的 owner/group/mode/SELinux context

#### Scenario: 启动阶段服务拉起
- **WHEN** 系统完成 `/data` 挂载 (`post-fs-data.sh`)
- **THEN** 清理 `DolbyAtmosControl-*` 包缓存、创建 `/data/vendor/dolby` (uid/gid 1013, mode 0770) 与 `/storage/emulated/0/dolbylog`、调用 M6 的 `apply_sepolicy_patches`
- **AND WHEN** 系统完成 `boot_completed` (`service.sh`)
- **THEN** 等待 `init.svc.servicemanager` / `init.svc.hwservicemanager` 均为 `running`,然后 `start_once` 拉起 `vendor.dolby.dms.service` 与 `vendor.dolby_sp.media.c2@1.0-service`,写入 `ro.oplus.audio.effect.type=dolby` 与 `ro.oplus.audio.dolby.equalizer_support=true`

#### Scenario: META-INF 装载
- **WHEN** 模块被 KSU/Magisk 加载
- **THEN** `META-INF/com/google/android/update-binary` 调用 `install_module` 包装,`updater-script` 保留最小 `#MAGISK` 行,`META-INF/compat.sh` 由 M6 提供并被 `customize.sh` `source`

#### Scenario: 卸载清理
- **WHEN** 用户在 Manager 中移除模块
- **THEN** `uninstall.sh` 停止两个守护进程、umount `my_product` 特性 XML 与 `apex/apex-info-list.xml` 的 bind、`resetprop --delete` 两个系统属性、清理 `/data/vendor/dolby` 与 DolbyAtmosControl 包缓存

### Requirement: 杜比解码器 (M2)

The system SHALL 注册 AC-3 / E-AC-3 / E-AC-3-JOC / AC-4 四种软件解码器到 Codec2 框架,并提供完整 VINTF 声明。

#### Scenario: 解码器能力注册
- **WHEN** Android 框架加载 `/odm/etc/media_codecs_c2.xml`
- **THEN** `c2.dolby.eac3.decoder` 暴露 `audio/ac3` (6ch, 32-48kHz, ≤640kbps)、`audio/eac3` (8ch, 32-48kHz, ≤6144kbps)、`audio/eac3-joc` (16ch, 48kHz, ≤6144kbps)
- **AND** `c2.dolby.ac4.decoder` 暴露 `audio/ac4` (16ch, 48kHz, 16-2688kbps),带 `OMX.*` 兼容 alias

#### Scenario: VINTF 与 HIDL 服务
- **WHEN** `service.sh` 启动守护进程
- **THEN** `vendor.dolby_sp.media.c2@1.0-service` 通过 HIDL `android.hardware.media.c2@1.0::IComponentStore/default1` 注册,同时保留 `default2` 给原厂
- **AND** `c2_manifest_vendor_audio.xml` 额外声明 AIDL `vendor.dolby.dms IDms/default`(为 M3 共享)

#### Scenario: 原生库完整性
- **WHEN** `customize.sh` 完成安装
- **THEN** 6 个 `.so` (`libcodec2_soft_ac4dec_sp.so` / `libcodec2_soft_ddpdec_sp.so` / `libcodec2_soft_common.so` / `libcodec2_store_dolby_sp.so` / `libdeccfg_sp.so` / `libYokiScale.so`) 部署到 `$MODPATH/system/vendor/lib64/`,其 SHA256 写入 `checksums.txt`
- **AND** `vendor.dolby_sp.media.c2@1.0-service` 部署到 `$MODPATH/system/vendor/bin/hw/`,mode 0755,selinux `vendor_file`

### Requirement: 杜比音效链 (M3)

The system SHALL 部署 DMS 服务与 DAP 音效引擎,提供 5 种 DVL 音量均衡监听器 + DAP 核心 + 游戏 DAP 效果,并合并现场 `audio_effects.xml`。

#### Scenario: 静态音效链模板
- **WHEN** 模块内 `audio_effects.xml` 缺失或合并失败
- **THEN** 静态模板提供 3 个 library (dap / dvl / gamedap)、8 个 effect (含 DAP UUID `9d4921da-8225-4f29-aefa-39537a04bcaa`)、music 流的 `<apply effect="dap"/>` + `<apply effect="dlb_music_listener"/>`

#### Scenario: 现场配置合并
- **WHEN** `customize.sh` 阶段 5 调用 `merge_audio_effects <MODPATH>`
- **THEN** awk 脚本读取 `/odm/etc/audio_effects.xml`,跳过 `oppo_audiox_sw_effects` 与 UUID `41f6c0f4-5d8f-11ec-bf63-0242ac130002`,在 `</libraries>` / `</effects>` 前补全缺失的 3 个 library 与 7 个 effect,在 `</postprocess>` 前确保 `stream type="music"` 存在且包含 dap + dlb_music_listener
- **AND** 合并结果必须通过 xmllint 校验、包含 DAP UUID、包含两个 `<apply>`,否则回退到静态模板并不报错

#### Scenario: AudioX 特性替换
- **WHEN** `service.sh` 启动阶段
- **THEN** 通过 `mount --bind` 将 `my_product/etc/permissions/oplus.product.features_audiox.xml`(声明 `oplus.software.audio.audioeffect_support` + `oplus.software.audio.dolby_support`)覆盖到 `/my_product/etc/permissions/oplus.product.features_audiox.xml`

#### Scenario: DMS 与 DAP 库部署
- **WHEN** 模块安装完成
- **THEN** `vendor.dolby.dms.service` 部署到 `system/vendor/bin/hw/`,DMS 库 (7 个: `libdlbdsservice_sp.so` / `libdapparamstorage_sp.so` / `libdlbpreg_sp.so` / `libdmshal.so` / `libspatializerparamstorage.so` / `vendor.dolby.dms-V1-ndk.so` / `vendor.dolby_sp.hardware.dmssp@2.0.so`) 部署到 `system/vendor/lib64/`,DAP 库 (3 个: `libswdap_sp.so` / `libdlbvol_sp.so` / `libswgamedap_sp.so`) 部署到 `system/vendor/lib64/soundfx/`,调音参数 `multimedia_dolby_dax_dflt.xml` 部署到 `system/vendor/etc/dolby/`

### Requirement: 配置 APK (M4)

The system SHALL 提供 `com.dolby.atmos.oplus.folk` 杜比配置 APK,采用 MVVM,基于 M3 的 DAP UUID 与 DMS AIDL 控制音效。

#### Scenario: 包与依赖
- **WHEN** 用户在桌面启动 `DolbyAtmosControl`
- **THEN** APK `minSdk=34`、`targetSdk=35`、Kotlin 1.9+、MVVM、ViewBinding,安装到 `/system/system_ext/priv-app/DolbyAtmosControl/`
- **AND** 持有 `MODIFY_DEFAULT_AUDIO_EFFECTS` 系统权限、声明 system 平台签名

#### Scenario: 主控制面板
- **WHEN** 用户进入主面板
- **THEN** 展示总开关 (`MaterialSwitch`)、设备状态栏 (扬声器/有线/蓝牙/USB)、5 个预设卡片 (电影/音乐/游戏/语音/自定义)、底部导航
- **AND** `MainViewModel` 维护 `DolbyState: StateFlow`,切换失败时回滚 `enabled` / `currentPreset`

#### Scenario: 10 段均衡器
- **WHEN** 用户进入均衡器页
- **THEN** 展示 32/64/125/250/500/1k/2k/4k/8k/16k Hz 的 10 个垂直滑块、6 个 EQ 预设曲线 (Rock/Pop/Classical/Jazz/Vocal/Flat) Chip、重置按钮
- **AND** 滑块值 clamp 在 [-12, +12] dB,`EqualizerViewModel.setBandGain()` 实时写入底层

#### Scenario: 双路径音效控制
- **WHEN** `MainViewModel.setPreset(preset)` 被调用
- **THEN** `DolbyRepository` 通过两条独立路径写入:
  1. `DmsBinder` 绑定 `vendor.dolby.dms.IDms/default` (5 次重试,2s 间隔) 走 AIDL
  2. `DapEffectController` 构造 `AudioEffect(EFFECT_TYPE_NULL, DAP_UUID, 0, 0)` 走 AudioEffect API
- **AND** 任一路径失败不阻塞另一路径,最终结果合并到 `Result<Unit>`

#### Scenario: 设备切换与开机自启
- **WHEN** 系统报告音频设备变化 (`AudioDeviceMonitor` 监听 `AudioManager`)
- **THEN** `MainViewModel` 加载 `SettingsRepository.getDevicePreset(deviceType)` 并自动应用
- **AND** `BootReceiver` 收到 `ACTION_BOOT_COMPLETED` 后,若 `PreferencesManager.getAutoStart()` 为 true,则以 `startForegroundService` 拉起 `DolbyControlService`,恢复上次 enabled/preset

#### Scenario: 国际化与主题
- **WHEN** 用户在设置中切换语言
- **THEN** 界面文字立即在英文 (`values/strings.xml`) 与中文 (`values-zh/strings.xml`) 间切换,Material 3 主题色与排版保持一致

### Requirement: 诊断工具 (M5)

The system SHALL 提供 `action.sh` 端到端诊断脚本,输出到 `/storage/emulated/0/dolbylog/`。

#### Scenario: 10 阶段诊断
- **WHEN** 用户执行 `su -c "sh /data/adb/modules/dolby_atmos_oplus_folk/action.sh"`
- **THEN** 依次输出: 1)系统信息 → 2)模块状态 → 3)服务状态 (Codec2/DMS/HIDL/AIDL) → 4)文件完整性 → 5)运行时检查 (DAP 数据目录/属性/SELinux/挂载点/AudioFlinger/Codec2) → 6)Logcat 采集 → 7)Tombstone 分析 → 8)APK 状态 → 9)分类报告 (通过/警告/失败 计数) → 10)日志打包
- **AND** 最终报告写入 `dolby_report_<timestamp>.txt`,分类结果遵循"硬失败 vs 软警告"二档 (例如 DMS 缺失 = warn,Codec2 缺失 = fail)

#### Scenario: 异常降级
- **WHEN** 脚本在无 root 权限下执行
- **THEN** 优雅退出,不破坏 `/storage/emulated/0/dolbylog/`

### Requirement: 兼容性适配 (M6)

The system SHALL 提供 `META-INF/compat.sh` 与 `META-INF/sepolicy.rule`,作为 M1-M5 的横切适配层。

#### Scenario: 设备信息与检测
- **WHEN** M1 的 `customize.sh` `source` `META-INF/compat.sh`
- **THEN** 暴露 `get_device_model` / `get_device_code` / `get_platform` / `get_sdk_version` / `get_android_version` / `detect_root_solution` / `is_oplus_device` / `detect_audio_stack` / `detect_conflicts` / `detect_hardware_dolby` 共 10 个检测函数

#### Scenario: 安装前综合检测
- **WHEN** M1 调用 `pre_install_check`
- **THEN** SDK < 34 记 1 个 error、CPU ABI ≠ arm64-v8a 记 1 个 error,冲突模块 / 硬件解码器 / 非 OPlus 设备 记为 warn,error 数 > 0 时由调用方决定是否 `abort`

#### Scenario: SELinux 策略补丁
- **WHEN** `post-fs-data.sh` 调用 `apply_sepolicy_patches`
- **THEN** 读取 `$MODDIR/META-INF/sepolicy.rule`,通过 `magiskpolicy --live --apply` 注入至少 4 类 allow 规则: 1) `vendor_dolby_dms_service` ↔ `audioserver` binder / service_manager 2) `vendor_dolby_sp_media_c2@1_0_service` ↔ `mediacodec` binder / service_manager 3) `vendor_dolby_dms_service` ↔ `audio_device:chr_file` 4) `vendor_dolby_dms_service` 写 `vendor_data_file`

#### Scenario: 多机型参数
- **WHEN** 调用 `get_device_dap_params`
- **THEN** 按 `ro.product.device` 分支返回: `PKG110` → 48kHz 蓝牙上限,`PKG120|PKG130` → 96kHz 蓝牙上限,其他 → 48kHz 默认

#### Scenario: 运行时路径选择
- **WHEN** 调用 `select_dap_control_path`
- **THEN** AIDL 栈返回 `audioeffect_primary_dms_fallback`,HIDL 栈返回 `dms_hidl_primary_audioeffect_fallback`,未知栈返回 `audioeffect_only`
- **AND** `check_dap_runtime` / `check_decoder_runtime` 通过 dumpsys 验证效果与解码器已注册

### Requirement: 集成打包 (Phase 4)

The system SHALL 在所有模块完成后,合并为单一可分发 ZIP。

#### Scenario: 集成 ZIP 生成
- **WHEN** Phase 1-3 全部通过质量门禁
- **THEN** `dolby-atmos-op-folk-v1.0.0.zip` 包含 INDEX 中列出的全部 30+ 文件,`zip -T` 完整性校验通过
- **AND** `META-INF/compat.sh` 在 ZIP 内存在,与 M1 的 `customize.sh` `source` 路径一致

---

## MODIFIED Requirements

无 (本仓库为首次落地,无既有规范可被修改)

## REMOVED Requirements

无

---

## 质量门禁 (跨模块统一)

| 门禁 | 命令 | 通过标准 |
|------|------|----------|
| Shell 静态检查 | `shellcheck -s sh <files>` | 0 error, 0 warning |
| Shell 测试 | `bats test/*.bats` | 全部用例通过 |
| XML 格式 | `xmllint --noout <files>` | 无错误 |
| XML 结构 | xmllint + XPath 断言 | 关键节点 (DAP UUID / Dolby 解码器) 存在 |
| `.so` 完整性 | `sha256sum -c checksums.txt` | 全部 OK |
| ZIP 完整性 | `zip -T dolby-atmos-op-folk-v1.0.0.zip` | OK |
| Kotlin 静态 | `./gradlew detekt ktlintCheck` | 0 error |
| Kotlin 测试 | `./gradlew test` | 全部 JUnit 用例通过 |

## 任务依赖 (高层)

```
M6 ──┐
     ├── M1 (M1 source M6 的 compat.sh)
M2 ──┘
M2 ── M3 (共享 VINTF) ── M4 (M4 依赖 M3 的 DAP UUID / DMS AIDL)
M1 ── M5 (M5 依赖 M1 的 MODDIR)
Phase 4 ← (M1, M2, M3, M4, M5, M6)
```

详细任务分解见 `tasks.md`,验收清单见 `checklist.md`。
