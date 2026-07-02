# Checklist: Dolby Atmos OnePlus folk popularization KSU Module

> 验收检查点: 每个 checkbox 均为可独立验证的事实陈述
> 验证方式: 读取产物 / 执行命令 / 解析输出
> 全部勾选后即视为本 spec 实施完成

---

## M1 - KSU 模块打包框架

- [ ] `module.prop` 含 `id=dolby_atmos_oplus_folk` / `version=v1.0.0` / `versionCode=100` / `author=Dolby Atmos OnePlus folk popularization Team` 字段
- [ ] `customize.sh` 通过 `shellcheck -s sh` 零错误零警告
- [ ] `customize.sh` 实现 6 阶段: 兼容性检测 / 用户确认 / 清理旧版本 / 权限设置 / audio_effects 合并 / 收尾
- [ ] `customize.sh` 在缺 KSU/Magisk/APatch 环境变量时调用 `abort` 并输出原因
- [ ] `customize.sh` 在 SDK < 34 时调用 `abort`
- [ ] `customize.sh` 在 `cpu_abi != arm64-v8a` 时调用 `abort`
- [ ] `customize.sh` 调用的 `perm_recursive` / `perm_one` 兼容 `set_perm` / `set_perm_recursive` 与 chown/chmod/chcon 两套后端
- [ ] `post-fs-data.sh` 在 `/data/system/package_cache` 清理 `DolbyAtmosControl-*` 条目
- [ ] `post-fs-data.sh` 创建 `/data/vendor/dolby`,uid/gid 1013,mode 0770
- [ ] `post-fs-data.sh` 创建 `/storage/emulated/0/dolbylog`
- [ ] `post-fs-data.sh` 调用 `apply_sepolicy_patches` (来自 M6)
- [ ] `service.sh` 等待 `init.svc.servicemanager=running` 与 `init.svc.hwservicemanager=running`(各 60s 超时)
- [ ] `service.sh` 通过 `start_once` 拉起 `vendor.dolby.dms.service` 与 `vendor.dolby_sp.media.c2@1.0-service`
- [ ] `service.sh` 写入 `ro.oplus.audio.effect.type=dolby` 与 `ro.oplus.audio.dolby.equalizer_support=true`
- [ ] `service.sh` 通过 `mount --bind` 挂载 `oplus.product.features_audiox.xml`
- [ ] `system.prop` 含上述 2 条属性
- [ ] `uninstall.sh` 停止两个守护进程、umount 两个 bind 路径、删除 2 条系统属性、清理 `/data/vendor/dolby` 与包缓存
- [ ] `META-INF/com/google/android/update-binary` 加载 `/data/adb/magisk/util_functions.sh` 后调用 `install_module`
- [ ] `META-INF/com/google/android/updater-script` 仅为 `#MAGISK` 一行
- [ ] `bats test/test_customize.bats` 覆盖 ui_print / abort / perm_recursive / perm_one 正常 + 异常路径
- [ ] `bats test/test_service.bats` 覆盖 wait_prop / start_once / file_sig / context_has / same_file_overlay

## M6 - 兼容性适配

- [ ] `META-INF/compat.sh` 通过 `shellcheck -s sh` 零错误零警告
- [ ] `compat.sh` 实现 10 个检测函数 (`get_device_model` / `get_device_code` / `get_platform` / `get_sdk_version` / `get_android_version` / `detect_root_solution` / `is_oplus_device` / `detect_audio_stack` / `detect_conflicts` / `detect_hardware_dolby`)
- [ ] `pre_install_check` 返回值等于 error 数(SDK<34 或 ABI≠arm64-v8a 触发)
- [ ] `apply_sepolicy_patches` 优先调用 `magiskpolicy --live --apply`,缺工具时优雅跳过
- [ ] `get_device_dap_params` 对 PKG110 / PKG120|PKG130 / 其他 返回不同蓝牙采样率
- [ ] `select_dap_control_path` 对 AIDL 栈返回 `audioeffect_primary_dms_fallback`,HIDL 返回 `dms_hidl_primary_audioeffect_fallback`
- [ ] `check_dap_runtime` / `check_decoder_runtime` 通过 `dumpsys` 验证后返回 `available` / `unavailable`
- [ ] `META-INF/sepolicy.rule` 含 4 类 allow 规则: DMS↔audioserver / C2↔mediacodec / DMS↔audio_device / DMS↔vendor_data_file
- [ ] `bats test/test_compat.bats` 覆盖所有 14 类函数 (正常/异常/边界),全部通过

## M2 - 杜比解码器

- [ ] `system/odm/etc/media_codecs_c2.xml` 通过 `xmllint --noout` 零错误
- [ ] XML 含 `c2.dolby.eac3.decoder` (audio/ac3 + audio/eac3 + audio/eac3-joc) + `c2.dolby.ac4.decoder` (audio/ac4)
- [ ] XML 中 4 个 MIME type 全部带 OMX alias 与 software-codec attribute
- [ ] `system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml` 通过 `xmllint --noout` 零错误
- [ ] VINTF manifest 声明 HIDL IComponentStore default1 + default2 + AIDL IDms default
- [ ] 6 个 `.so` 部署到 `system/vendor/lib64/`,文件存在且 size > 0
- [ ] `vendor.dolby_sp.media.c2@1.0-service` 部署到 `system/vendor/bin/hw/`,mode 0755
- [ ] `checksums.txt` 含 7 行 SHA256 记录 (6 个 `.so` + 1 个 service)
- [ ] `sh test/verify_checksums.sh` 输出 `OK` (全部 sha256sum -c 成功)
- [ ] `sh test/validate_media_codecs.sh` 通过 (xmllint + XPath 关键节点断言全部命中)

## M3 - 杜比音效链

- [ ] `system/odm/etc/audio_effects.xml` 静态模板通过 `xmllint --noout` 零错误
- [ ] XML 含 3 个 library (dap / dvl / gamedap) + DAP UUID `9d4921da-8225-4f29-aefa-39537a04bcaa`
- [ ] XML 含 postprocess 段,music 流绑定 dap + dlb_music_listener
- [ ] `merge_audio_effects()` 函数通过 `shellcheck -s sh` 零错误零警告
- [ ] 函数对包含杜比效果的输入产生幂等结果(重复调用不会增加 effect)
- [ ] 函数对损坏 XML 输入回退到静态模板,不报错且不污染输出
- [ ] 函数对包含 `oppo_audiox_sw_effects` / `41f6c0f4-5d8f-11ec-bf63-0242ac130002` 的输入正确跳过
- [ ] 函数对缺失 `stream type="music"` 的输入在 `</postprocess>` 前补全
- [ ] `my_product/etc/permissions/oplus.product.features_audiox.xml` 声明 `oplus.software.audio.audioeffect_support` + `oplus.software.audio.dolby_support`
- [ ] 7 个 DMS 库 + 3 个 DAP 库 + 1 个 service + 1 个 XML 全部就位
- [ ] `bats test/test_merge_audio_effects.bats` 5 个场景全部通过
- [ ] `bats test/test_dap_uuids.bats` 验证 7 个 UUID 与 `libswdap_sp.so` 一致

## M4 - 配置 APK

- [ ] Android 项目结构完整: `app/build.gradle.kts` / `settings.gradle.kts` / `gradle/libs.versions.toml` / `AndroidManifest.xml`
- [ ] `minSdk=34`, `targetSdk=35`, Kotlin 1.9+, ViewBinding enabled, Material 3
- [ ] `AndroidManifest.xml` 声明 `<service android:name=".service.DolbyControlService">` + `<receiver android:name=".service.BootReceiver">` + `MODIFY_DEFAULT_AUDIO_EFFECTS` 权限
- [ ] APK 输出到 `system/system_ext/priv-app/DolbyAtmosControl/DolbyAtmosControl.apk`,存在且 size > 0
- [ ] Domain 层 5 个 data class / 2 个 enum / 2 个 repository 接口存在
- [ ] `DapEffectController` 使用 DAP UUID `9d4921da-8225-4f29-aefa-39537a04bcaa`,包含 initialize / setEnabled / setPreset / setEqualizerBand / release
- [ ] `DmsBinder` 5 次重试绑定 `vendor.dolby.dms.IDms/default`,暴露 `connectionState: StateFlow<Boolean>`
- [ ] `MainViewModel` 在 setEnabled / setPreset 失败时回滚 `dolbyState` 字段
- [ ] `EqualizerViewModel` 滑块值 clamp 到 [-12, +12] dB,10 段中心频率 32-16000 Hz
- [ ] `DolbyControlService` 是前台服务,`onCreate` 中 `DapEffectController.initialize()` 并恢复上次 enabled/preset
- [ ] `BootReceiver` 监听 `ACTION_BOOT_COMPLETED`,读取 `PreferencesManager.getAutoStart()` 决定是否拉起服务
- [ ] `values/strings.xml` (英文) + `values-zh/strings.xml` (中文) 含全部 28+ 字符串
- [ ] `values/colors.xml` + `values/themes.xml` Material 3 主题就位
- [ ] `com.dolby.atmos.oplus.folk.xml` 系统权限文件含 `MOUNT_UNMOUNT_FILESYSTEMS` 之外至少 1 条 signature 权限
- [ ] `./gradlew detekt ktlintCheck` 零错误
- [ ] `./gradlew test` 全部 JUnit 5 + MockK + Turbine 用例通过 (≥ 15 个核心场景)

## M5 - 诊断工具

- [ ] `action.sh` 通过 `shellcheck -s sh` 零错误零警告
- [ ] 阶段 1 输出设备型号 / 设备代号 / Android 版本 / 内核 / 芯片 / 架构 / SELinux
- [ ] 阶段 2 输出模块 id / version / author 与 .install_info 内容
- [ ] 阶段 3 输出 Codec2 / DMS 进程 PID + lshal 输出 + service list | grep dolby 输出
- [ ] 阶段 4 输出 17 个二进制/配置/APK 的"存在/缺失"判定
- [ ] 阶段 5 输出 DAP 数据目录权限 / 系统属性 / SELinux 上下文 / 挂载点 / AudioFlinger 效果 / Codec2 解码器
- [ ] 阶段 6 采集最近 1000 行 Dolby 相关 logcat + 500 行事件日志
- [ ] 阶段 7 筛选 Dolby 相关 tombstone 与 ANR trace 到 `crash_<timestamp>/`
- [ ] 阶段 8 输出 `pm list packages | grep com.dolby.atmos.oplus.folk` 与 `pm path` 结果
- [ ] 阶段 9 至少 11 类检查点 pass/warn/fail 分类,DMS 缺失为 warn,Codec2 缺失为 fail
- [ ] 阶段 10 输出报告/logcat/dumpsys/event/crash 5 类文件路径
- [ ] `bats test/test_action.bats` 覆盖 4 类场景 (正常/缺失/服务停止/无 root),全部通过
- [ ] 报告文件 `dolby_report_<timestamp>.txt` 含分类结果统计行

## Phase 4 - 集成与打包

- [ ] `dolby-atmos-op-folk-v1.0.0.zip` 存在
- [ ] `zip -T dolby-atmos-op-folk-v1.0.0.zip` 输出 `test of <name> OK`
- [ ] ZIP 内文件清单与 `设计/INDEX.md` §"文件清单汇总"完全一致 (≥ 30 个文件)
- [ ] `META-INF/compat.sh` 在 ZIP 内存在,内容与 M6 产物一致
- [ ] `MANIFEST.md` 含版本号 / 模块清单 / 各文件 SHA256 / 各文件 size / 质量门禁结果
- [ ] `test_e2e_install.sh` 模拟 customize.sh 6 阶段 + service.sh 工具函数 + bat 关键断言全部通过
- [ ] `设计加任务/.../progress.md` 全部 checkbox 标记为 `[x]`

## 全局门禁 (跨模块)

- [ ] 任何模块未通过对应质量门禁时,`tasks.md` 对应任务被回退到 `in_progress` 并追加修复子任务
- [ ] 全部 Shell 文件累计 `shellcheck` warning = 0
- [ ] 全部 bats 用例通过
- [ ] 全部 XML 文件 `xmllint` 通过
- [ ] 全部 .so 文件 SHA256 与 `checksums.txt` 匹配
- [ ] 全部 JUnit 用例通过
- [ ] 最终 ZIP 在容器内可被 `unzip -l` 列出 30+ 文件,`zip -T` 报告 OK
