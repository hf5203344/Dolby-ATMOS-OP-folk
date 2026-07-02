# Tasks: Dolby Atmos OnePlus folk popularization KSU Module

> 每个任务完成后,在本文件中勾选对应 `- [ ]` → `- [x]`
> 所有产物统一输出到 `/workspace/build/M{1..6}/` 与 `/workspace/build/dolby-atmos-op-folk-v1.0.0.zip`
> 详细设计: `设计/6a425bdc061cf7478c0b7de5_M{1..6}-*.md`
> 详细子任务: `设计加任务/6a425bdc061cf7478c0b7de5_M{1..6}-*.md` (本文件采用其高层聚合)

---

## Phase 1 (并行 3 个子 Agent: M1 + M6 + M2)

### Task 1: M1 - KSU 模块打包框架
- [ ] 1.1 创建 `module.prop`(id/version/versionCode/author/description)
- [ ] 1.2 实现 `customize.sh`: 6 阶段 (兼容性检测 → 用户确认 → 清理旧版本 → 权限设置 → audio_effects 合并 → 收尾)
- [ ] 1.3 实现 `post-fs-data.sh`: 清理包缓存、创建 DAP 数据目录、创建诊断目录、调用 `apply_sepolicy_patches`
- [ ] 1.4 实现 `service.sh`: 清理探针、确保 DAP 数据目录、bind AudioX 特性 XML、验证 VINTF 挂载、等待 APEX、等待系统服务、启动 DMS + Codec2 HAL、写入系统属性
- [ ] 1.5 实现 `system.prop` (2 个属性)
- [ ] 1.6 实现 `uninstall.sh` (停止服务 / umount / 清理属性 / 清理数据)
- [ ] 1.7 创建 `META-INF/com/google/android/update-binary` + `updater-script`
- [ ] 1.8 创建 `META-INF/compat.sh` 占位 (M6 完成后被 M6 内容覆盖)
- [ ] 1.9 编写 bats 测试覆盖 `ui_print` / `abort` / `perm_recursive` / `perm_one` / `clean_old_artifacts` / `clear_package_cache` / `setup_dolby_data_dir` / `start_once` / `wait_prop` / `file_sig` / `context_has` / `same_file_overlay`
- [ ] 1.10 通过 `shellcheck -s sh` 零错误零警告;`bats test/*.bats` 全部通过

### Task 2: M6 - 兼容性适配
- [ ] 2.1 实现 `META-INF/compat.sh`: 10 个检测函数 (`get_device_model` / `get_device_code` / `get_platform` / `get_sdk_version` / `get_android_version` / `detect_root_solution` / `is_oplus_device` / `detect_audio_stack` / `detect_conflicts` / `detect_hardware_dolby`)
- [ ] 2.2 实现 `pre_install_check`: SDK/ABI/冲突/硬件解码器/OPlus 综合判定
- [ ] 2.3 实现 `apply_sepolicy_patches`: 通过 `magiskpolicy --live --apply` 注入策略
- [ ] 2.4 实现 `get_device_dap_params`: PKG110 / PKG120|PKG130 / 其他 三档参数
- [ ] 2.5 实现 `select_dap_control_path` / `check_dap_runtime` / `check_decoder_runtime`
- [ ] 2.6 创建 `META-INF/sepolicy.rule`: 至少 4 类 allow 规则
- [ ] 2.7 编写 bats 测试覆盖所有 14 类函数 (正常/异常/边界)
- [ ] 2.8 通过 `shellcheck -s sh` 零错误零警告;`bats test/*.bats` 全部通过

### Task 3: M2 - 杜比解码器
- [ ] 3.1 编写 `system/odm/etc/media_codecs_c2.xml`: c2.dolby.eac3.decoder (ac3/eac3/eac3-joc) + c2.dolby.ac4.decoder
- [ ] 3.2 编写 `system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml`: HIDL IComponentStore default1+default2 + AIDL IDms default
- [ ] 3.3 从参考模块提取 6 个 `.so` 到 `system/vendor/lib64/`: libcodec2_soft_ac4dec_sp.so / libcodec2_soft_ddpdec_sp.so / libcodec2_soft_common.so / libcodec2_store_dolby_sp.so / libdeccfg_sp.so / libYokiScale.so
- [ ] 3.4 提取 `vendor.dolby_sp.media.c2@1.0-service` 到 `system/vendor/bin/hw/`
- [ ] 3.5 计算所有二进制 SHA256,写入 `checksums.txt`
- [ ] 3.6 编写 `test/validate_media_codecs.sh` (xmllint + XPath 关键节点断言) + `test/verify_checksums.sh` (`sha256sum -c`)
- [ ] 3.7 通过 `xmllint --noout` 零错误;`sh test/validate_media_codecs.sh` 通过;`sh test/verify_checksums.sh` OK

---

## Phase 2 (并行 2 个子 Agent: M3 + M5)

### Task 4: M3 - 杜比音效链
- [ ] 4.1 编写 `system/odm/etc/audio_effects.xml` 静态模板 (3 library + 8 effect + postprocess music)
- [ ] 4.2 编写 `merge_audio_effects()` 函数 (独立 shell 脚本 + awk 合并,跳过 AudioX、补全 library/effect、补全 music stream apply)
- [ ] 4.3 编写 `my_product/etc/permissions/oplus.product.features_audiox.xml`
- [ ] 4.4 从参考模块提取 7 个 DMS 库到 `system/vendor/lib64/` + 3 个 DAP 库到 `system/vendor/lib64/soundfx/`
- [ ] 4.5 提取 `vendor.dolby.dms.service` 到 `system/vendor/bin/hw/`
- [ ] 4.6 提取 `multimedia_dolby_dax_dflt.xml` 到 `system/vendor/etc/dolby/`
- [ ] 4.7 编写 bats 测试覆盖 `merge_audio_effects` 正常合并 / 幂等性 / 损坏 XML 回退 / AudioX 效果移除 / music stream 补全 5 个场景
- [ ] 4.8 通过 `shellcheck -s sh` 零错误零警告;`xmllint --noout` 零错误;`bats test/*.bats` 全部通过

### Task 5: M5 - 诊断工具
- [ ] 5.1 实现 `action.sh` 阶段 1 (系统信息: 设备/内核/芯片/架构/SELinux)
- [ ] 5.2 实现阶段 2 (模块状态: module.prop / .install_info / .audio_stack_type)
- [ ] 5.3 实现阶段 3 (服务状态: Codec2/DMS/HIDL/AIDL)
- [ ] 5.4 实现阶段 4 (文件完整性: 17 个二进制/配置/APK)
- [ ] 5.5 实现阶段 5 (运行时检查: DAP 数据目录/属性/SELinux 上下文/挂载点/AudioFlinger/Codec2)
- [ ] 5.6 实现阶段 6 (Logcat 采集,最近 1000 行 Dolby 相关 + 500 行事件日志)
- [ ] 5.7 实现阶段 7 (Tombstone + ANR 筛选与归档)
- [ ] 5.8 实现阶段 8 (包管理器状态,APK 安装情况)
- [ ] 5.9 实现阶段 9 (分类报告,11 类检查点 pass/warn/fail + 建议)
- [ ] 5.10 实现阶段 10 (日志打包 + 控制台摘要)
- [ ] 5.11 编写 bats 测试覆盖 10 类工具函数 (正常设备/缺失文件/服务停止/无 root)
- [ ] 5.12 通过 `shellcheck -s sh` 零错误零警告;`bats test/*.bats` 全部通过

---

## Phase 3 (1 个子 Agent: M4)

### Task 6: M4 - 配置 APK
- [ ] 6.1 初始化 Android 项目 (Kotlin, AGP 8.x, minSdk=34, targetSdk=35, ViewBinding, Material 3)
- [ ] 6.2 编写 `gradle/libs.versions.toml` + `app/build.gradle.kts` (依赖: lifecycle-viewmodel-ktx, material, constraintlayout, recyclerview, coroutines, mockk, turbine, junit5)
- [ ] 6.3 实现 Domain 层: `DolbyState` / `Preset` / `EqualizerBand` / `AudioDevice` / `DeviceType` / `AppLanguage` / `DolbyRepository` 接口 / `SettingsRepository` 接口
- [ ] 6.4 实现 Data 层: `DapEffectController` (DAP UUID `9d4921da-8225-4f29-aefa-39537a04bcaa`,`setEnabled` / `setPreset` / `setEqualizerBand` / `release`)
- [ ] 6.5 实现 Data 层: `DmsBinder` (5 次重试绑定 `vendor.dolby.dms.IDms/default` + `StateFlow<Boolean>` connectionState)
- [ ] 6.6 实现 Data 层: `DmsRepositoryImpl` / `PreferencesManager` (SharedPreferences 封装) / `SettingsRepositoryImpl` / `AudioDeviceMonitor`
- [ ] 6.7 实现 UI 层: `MainActivity` + `MainFragment` + `MainViewModel` (toggleDolby/setPreset 含失败回滚 + observeDeviceChanges)
- [ ] 6.8 实现 UI 层: `EqualizerFragment` + `EqualizerViewModel` (10 段滑块 + 6 个 EQ 预设曲线 + resetToFlat)
- [ ] 6.9 实现 UI 层: `SettingsFragment` + `SettingsViewModel` (语言切换/自动启动/蓝牙独立配置)
- [ ] 6.10 实现 UI 层: 公共组件 `DolbySwitch` / `PresetCard` / `EqualizerSlider` / `DeviceStatusBar` / `LanguageSelector` + Material 3 主题
- [ ] 6.11 实现 Service 层: `DolbyControlService` (前台服务,启动时 `DapEffectController.initialize()` + 恢复状态) + `BootReceiver` (监听 BOOT_COMPLETED)
- [ ] 6.12 编写 `values/strings.xml` (英文) + `values-zh/strings.xml` (中文) + `AndroidManifest.xml` (system 签名 + `MODIFY_DEFAULT_AUDIO_EFFECTS` + `<service>` + `<receiver>`)
- [ ] 6.13 配置 `system/system_ext/etc/permissions/com.dolby.atmos.oplus.folk.xml` (签名白名单 + 权限授予)
- [ ] 6.14 编写 JUnit 5 + MockK + Turbine 测试覆盖 15 类核心场景 (initialize / setEnabled / setPreset / setEqualizerBand / DmsBinder bind 重试 / MainViewModel 切换回滚 / EqualizerViewModel clamp / SettingsViewModel 等)
- [ ] 6.15 通过 `./gradlew detekt ktlintCheck test` 零错误;生成 `app-release.apk`;复制到 `system/system_ext/priv-app/DolbyAtmosControl/DolbyAtmosControl.apk`

---

## Phase 4 (1 个子 Agent: 集成测试与打包)

### Task 7: 集成与最终打包
- [ ] 7.1 合并 `/workspace/build/M{1..6}/` 到统一 ZIP 根目录
- [ ] 7.2 验证 ZIP 内文件清单与 `设计/INDEX.md` §"文件清单汇总"完全一致
- [ ] 7.3 执行 `zip -T dolby-atmos-op-folk-v1.0.0.zip` 完整性校验
- [ ] 7.4 在容器内执行 `test_e2e_install.sh`: 模拟 `customize.sh` 6 阶段(无 root 时回退)、`post-fs-data.sh` 关键步骤、`service.sh` 工具函数、bat 关键断言
- [ ] 7.5 生成 `MANIFEST.md` (版本/模块清单/SHA256/size/质量门禁结果)
- [ ] 7.6 更新 `设计加任务/.../progress.md` 所有 checkbox 为 `[x]`

---

## Task Dependencies

- Task 1 (M1) ← Task 2 (M6) [M1 source M6 的 compat.sh,M6 必须在 M1 完成前或同步完成]
- Task 4 (M3) ← Task 3 (M2) [M3 共享 M2 的 VINTF manifest]
- Task 6 (M4) ← Task 4 (M3) [M4 依赖 M3 的 DAP UUID 与 DMS AIDL]
- Task 5 (M5) ← Task 1 (M1) [M5 依赖 M1 的 MODDIR 路径约定]
- Task 7 (Phase 4) ← Tasks 1, 2, 3, 4, 5, 6 (全部)

## Parallelization

- Phase 1: Tasks 1, 2, 3 可并行 (约束: 最多 3 个子 Agent)
- Phase 2: Tasks 4, 5 可并行 (约束: 最多 3 个子 Agent;M5 仅依赖 M1 的目录约定,不依赖 M1 代码完成)
- Phase 3: Task 6 单 Agent (依赖 M3 完成)
- Phase 4: Task 7 单 Agent
