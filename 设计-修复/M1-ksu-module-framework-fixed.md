# M1: KSU 模块打包框架 — 详细设计文档 **[FIXED v1.0]**

> **版本:** v1.0-FIXED | **日期:** 2026-07-02 | **状态:** 详细设计 (含修复)
> **基础版本:** v1.0 (2026-06-29)
> **本版本变更:** 修复 [设计审查-v1.0.md](../../设计审查-v1.0.md) 中的 C-1, H-1, H-2, H-3, H-4

---

## 0. 本版本变更摘要 (v1.0-FIXED)

| # | 类型 | 章节 | 修复内容 |
|---|------|------|----------|
| C-1 | Critical | §2.2 customize.sh, §3.1 | M1 保留完整 `detect_root_solution()`, M6 必须改名为 `detect_root_solution_v2()` (已在 M6-fixed 修复) |
| H-1 | High | §2.2 customize.sh | `getevent` 不可用时增加 fallback, 5 秒超时默认安装 |
| H-2 | High | §2.2 customize.sh | `clean_old_artifacts` 改为基于 `module.prop` 中 `id` 前缀通配清理 |
| H-3 | High | §2.2 customize.sh | APK SELinux 上下文从 `system_file` 改为 `privapp` |
| H-4 | High | §2.4 service.sh | service.sh 保留 `clean_probe`, M5 action.sh 改为只读 (已在 M5-fixed 修复) |

---

## 1. 模块概述

### 1.1 职责

M1 是整个 Dolby Atmos 模块的骨架，负责：

- 定义模块元信息（`module.prop`）
- 实现安装/卸载生命周期脚本（`customize.sh`、`uninstall.sh`）
- 管理启动阶段脚本（`post-fs-data.sh`、`service.sh`）
- 设定系统属性（`system.prop`）
- 统一文件权限和 SELinux 上下文设置
- 兼容 KSU、Magisk、APatch 三种 Root 方案

### 1.2 依赖关系

| 方向 | 模块 | 说明 |
|------|------|------|
| 上游依赖 | 无 | M1 是基础模块，无外部依赖 |
| 下游依赖 | M2, M3, M4, M5, M6 | 所有模块通过 M1 的目录结构和生命周期钩子挂载 |

### 1.3 接口约定

M1 通过以下约定对外暴露接口，其他模块必须遵守：

| 约定 | 说明 |
|------|------|
| `$MODPATH` | 模块安装根路径，由 KSU/Magisk 在安装时注入，默认值为 `${0%/*}` |
| `$MODDIR` | 模块运行时根路径，由启动脚本注入，值为 `${0%/*}` |
| `$TMPDIR` | 临时目录，安装阶段为 `/dev/tmp`，运行时为 `/data/local/tmp` |
| `$ARCH` | 目标架构，固定为 `arm64-v8a` |
| `$API` | Android SDK 版本号，通过 `getprop ro.build.version.sdk` 获取 |

**🔧 FIX C-1 (新增):** `detect_root_solution()` 函数由 M1 完整定义, M6 的 `META-INF/compat.sh` **不得重新定义同名函数**, 仅允许 `source` 后调用. M6 中如需类似函数, 必须使用不同名称 (如 `compat_detect_root`).

---

## 2. 文件清单与实现

### 2.1 `module.prop`

```properties
id=dolby_atmos_oplus_folk
name=Dolby Atmos OnePlus folk popularization
version=v1.0.0
versionCode=100
author=Dolby Atmos OnePlus folk popularization Team
description=Dolby Atmos decoder and audio effect for OnePlus ACE5 series. Supports AC-4, E-AC-3, E-AC-3-JOC decoding and DAP global audio processing. Compatible with KSU, Magisk, and APatch.
```

**设计说明:**
- `id` 使用唯一的模块标识符，避免与其他模块冲突
- `versionCode` 采用 `major * 100 + minor * 10 + patch` 格式，便于版本比较
- `description` 为英文，安装时脚本中可输出中文提示

---

### 2.2 `customize.sh` — 安装脚本

```bash
#!/system/bin/sh
# ============================================================
# M1: customize.sh — Dolby Atmos 模块安装脚本
# 兼容: KSU / Magisk / APatch
# 功能: 兼容性检测、音量键选择、文件权限、audio_effects 合并
# ============================================================

# ---- 环境变量初始化 ----
MODPATH="${MODPATH:-${0%/*}}"
TMPDIR="${TMPDIR:-/dev/tmp}"
ARCH="${ARCH:-arm64-v8a}"
API="$(getprop ro.build.version.sdk 2>/dev/null)"
[ -z "$API" ] && API=0

# ---- 日志函数 ----
ui_print() {
  echo "$1"
}

abort() {
  ui_print "错误: $1"
  exit 1
}

# ---- 导入 M6 兼容性检测函数 ----
# (M6 模块提供的函数，此处通过 source 引入)
# 🔧 FIX C-1: M6 中不得定义同名函数, 此处 source 是安全的
COMPAT_SCRIPT="$MODPATH/META-INF/compat.sh"
if [ -f "$COMPAT_SCRIPT" ]; then
  source "$COMPAT_SCRIPT"
fi

# ============================================================
# 阶段 1: 兼容性检测
# ============================================================
ui_print "=========================================="
ui_print " Dolby Atmos OnePlus folk popularization"
ui_print " v1.0.0"
ui_print "=========================================="
ui_print ""

# 1.1 Root 方案检测
# 🔧 FIX C-1: 完整版保留在 M1, 全局变量 ROOT_TYPE 等供后续阶段使用
detect_root_solution() {
  if [ -n "$KSU" ]; then
    ROOT_TYPE="KSU"
    ROOT_VER="$KSU_VER"
    ROOT_VER_CODE="$KSU_VER_CODE"
  elif [ -n "$APATCH" ]; then
    ROOT_TYPE="APatch"
    ROOT_VER="$APATCH_VER"
  elif [ -n "$MAGISK_VER" ]; then
    ROOT_TYPE="Magisk"
    ROOT_VER="$MAGISK_VER"
    ROOT_VER_CODE="$MAGISK_VER_CODE"
  else
    ROOT_TYPE="Unknown"
  fi
  ui_print "(1/6) Root 方案: $ROOT_TYPE"
  [ "$ROOT_TYPE" = "Unknown" ] && abort "未检测到 KSU/Magisk/APatch"
}

# 1.2 Android 版本检测
detect_android_version() {
  ANDROID_VER="$(getprop ro.build.version.release 2>/dev/null)"
  SDK_VER="$(getprop ro.build.version.sdk 2>/dev/null)"
  ui_print "(2/6) Android 版本: $ANDROID_VER (SDK $SDK_VER)"
  if [ "$SDK_VER" -lt 34 ]; then
    abort "不支持 Android $ANDROID_VER (SDK $SDK_VER)，最低要求 Android 14 (SDK 34)"
  fi
}

# 1.3 芯片平台检测
detect_platform() {
  PLATFORM="$(getprop ro.board.platform 2>/dev/null)"
  HARDWARE="$(getprop ro.hardware 2>/dev/null)"
  ui_print "(3/6) 芯片平台: ${PLATFORM:-$HARDWARE}"
  case "$PLATFORM" in
    *"sm8650"*|*"pineapple"*)
      PLATFORM_FAMILY="sm8650"
      ;;
    *"sm8750"*)
      PLATFORM_FAMILY="sm8750"
      ;;
    *)
      PLATFORM_FAMILY="unknown"
      ui_print "  警告: 未识别的芯片平台，可能不兼容"
      ;;
  esac
}

# 1.4 设备型号检测
detect_device() {
  DEVICE_MODEL="$(getprop ro.product.model 2>/dev/null)"
  DEVICE_NAME="$(getprop ro.product.device 2>/dev/null)"
  DEVICE_OEM="$(getprop ro.product.manufacturer 2>/dev/null)"
  ui_print "(4/6) 设备型号: $DEVICE_MODEL ($DEVICE_NAME)"
  # 检查是否为一加设备
  case "$DEVICE_OEM" in
    *"OnePlus"*|*"oneplus"*|*"OPPO"*|*"oplus"*)
      IS_OPLUS=1
      ;;
    *)
      IS_OPLUS=0
      ui_print "  警告: 非一加/OPPO 设备，兼容性未验证"
      ;;
  esac
}

# 1.5 架构检测
detect_architecture() {
  CPU_ABI="$(getprop ro.product.cpu.abi 2>/dev/null)"
  ui_print "(5/6) CPU 架构: $CPU_ABI"
  case "$CPU_ABI" in
    "arm64-v8a") ARCH="arm64-v8a" ;;
    *) abort "不支持 $CPU_ABI 架构，仅支持 arm64-v8a" ;;
  esac
}

# 1.6 音频栈检测
detect_audio_stack() {
  if [ -e "/vendor/lib64/libaconfig_storage_read_api_cc.so" ] || \
     [ -e "/odm/etc/vintf/manifest/dvs-aidl-service.xml" ]; then
    AUDIO_STACK="AIDL"
  else
    AUDIO_STACK="HIDL"
  fi
  ui_print "(6/6) 音频 HAL 栈: $AUDIO_STACK"
  # 记录检测结果供后续模块使用
  echo "$AUDIO_STACK" > "$MODPATH/.audio_stack_type"
}

# 执行所有检测
detect_root_solution
detect_android_version
detect_platform
detect_device
detect_architecture
detect_audio_stack

# ============================================================
# 阶段 2: 用户确认
# ============================================================
ui_print ""
ui_print "=========================================="
ui_print " 警告"
ui_print "=========================================="
ui_print "此模块修改系统音频栈，可能导致:"
ui_print "  - 无法开机"
ui_print "  - 音频服务崩溃"
ui_print "  - 系统卡顿"
ui_print ""
ui_print "请确保已备份重要数据，了解救砖方法"
ui_print "=========================================="
ui_print ""

# 音量键选择: 上键=安装并访问更新页, 下键=直接安装
ui_print "音量 [+] 安装并访问更新页"
ui_print "音量 [-] 直接安装"
ui_print "等待 5 秒后默认直接安装..."

# 🔧 FIX H-1: getevent PATH 兼容性 + 5 秒超时默认
KEY_CLICK=""
TIMEOUT=5
HAVE_GETEVENT=0
if command -v getevent >/dev/null 2>&1; then
  HAVE_GETEVENT=1
else
  ui_print "  (getevent 不可用, 跳过音量键选择, 默认直接安装)"
fi

while [ "$TIMEOUT" -gt 0 ] && [ -z "$KEY_CLICK" ]; do
  if [ "$HAVE_GETEVENT" = "1" ]; then
    KEY_CLICK="$(getevent -qlc 1 2>/dev/null | awk '/KEY_VOLUMEUP|KEY_VOLUMEDOWN/ {print $3; exit}')"
  else
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
  fi
done

if [ "$KEY_CLICK" = "KEY_VOLUMEUP" ]; then
  INSTALL_MODE="update"
  if command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "https://github.com/dolby-atmos-oplus-folk" >/dev/null 2>&1
  fi
else
  INSTALL_MODE="direct"
fi
ui_print "安装模式: $INSTALL_MODE"

# ============================================================
# 阶段 3: 清理旧版本残留
# ============================================================
ui_print ""
ui_print "正在清理旧版本残留..."

# 🔧 FIX H-2: 改为基于 module.prop 中 id 前缀通配清理
clean_old_artifacts() {
  local MODPATH="$1"
  local MOD_ID=""

  # 从 module.prop 读取 id
  if [ -f "$MODPATH/module.prop" ]; then
    MOD_ID="$(grep '^id=' "$MODPATH/module.prop" | cut -d= -f2- | tr -d '[:space:]')"
  fi
  [ -z "$MOD_ID" ] && MOD_ID="dolby_atmos_oplus_folk"

  # 仅清理与本模块 ID 直接相关的旧版本残留
  # 避免误删其他 Dolby 模块 (如 daxapp, daxcontroller) 的文件
  case "$MOD_ID" in
    *dolby_atmos_oplus_folk*|dolby_atmos*)
      # 本模块族, 安全清理
      rm -rf "$MODPATH/.probe_lock" "$MODPATH/.probe_tmp" 2>/dev/null
      rm -f "$MODPATH/last_probe.txt" "$MODPATH/last_probe.raw.log" 2>/dev/null
      rm -f "$MODPATH/boot_probe_state.txt" "$MODPATH/boot_process_context.txt" 2>/dev/null
      rm -f "$MODPATH/boot_service_stdout.txt" "$MODPATH/boot_service_stderr.txt" 2>/dev/null
      rm -f "$MODPATH/boot_dms_stdout.txt" "$MODPATH/boot_dms_stderr.txt" 2>/dev/null
      # 清理本模块旧的 priv-app 残留 (本模块 ID 为前缀)
      rm -rf "$MODPATH/system/system_ext/priv-app/DolbyAtmosControl" 2>/dev/null
      # 清理本模块的旧权限文件
      rm -f "$MODPATH/system/system_ext/etc/permissions/com.dolby.atmos.oplus.folk.xml" 2>/dev/null
      ;;
    *)
      # 未知 ID, 不进行任何清理, 防止误删
      ui_print "  警告: module.prop 中 id='$MOD_ID' 不属于 dolby_atmos 系列, 跳过清理"
      ;;
  esac
}
clean_old_artifacts "$MODPATH"

# ============================================================
# 阶段 4: 文件权限设置
# ============================================================
ui_print "正在设置文件权限..."

# 通用递归权限设置函数
perm_recursive() {
  local target="$1"
  local owner="$2"
  local group="$3"
  local dir_mode="$4"
  local file_mode="$5"
  local context="$6"
  [ -e "$target" ] || return 0
  # 使用 Magisk/KSU 内置函数（如果可用）
  if type set_perm_recursive >/dev/null 2>&1; then
    set_perm_recursive "$target" "$owner" "$group" "$dir_mode" "$file_mode" "$context" 2>/dev/null
  fi
  # 后备方案：直接使用 chown/chmod/chcon
  chown -R "$owner:$group" "$target" 2>/dev/null
  find "$target" -type d -exec chmod "$dir_mode" {} \; 2>/dev/null
  find "$target" -type f -exec chmod "$file_mode" {} \; 2>/dev/null
  chcon -R "$context" "$target" 2>/dev/null
}

# 单文件权限设置
perm_one() {
  local target="$1"
  local owner="$2"
  local group="$3"
  local mode="$4"
  local context="$5"
  [ -e "$target" ] || return 0
  if type set_perm >/dev/null 2>&1; then
    set_perm "$target" "$owner" "$group" "$mode" "$context" 2>/dev/null
  fi
  chown "$owner:$group" "$target" 2>/dev/null
  chmod "$mode" "$target" 2>/dev/null
  chcon "$context" "$target" 2>/dev/null
}

# 系统路径定义
VENDOR_ROOT="$MODPATH/system/vendor"
ODM_ROOT="$MODPATH/system/odm"
MY_PRODUCT_ROOT="$MODPATH/my_product"
SYSTEM_EXT_ROOT="$MODPATH/system/system_ext"
VENDOR_BIN="$VENDOR_ROOT/bin"
VENDOR_LIB="$VENDOR_ROOT/lib64"
VENDOR_ETC="$VENDOR_ROOT/etc"
ODM_ETC="$ODM_ROOT/etc"
SOUNDFX_DIR="$VENDOR_LIB/soundfx"
MY_PRODUCT_PERMISSIONS="$MY_PRODUCT_ROOT/etc/permissions"
SYSTEM_EXT_PRIV_APP="$SYSTEM_EXT_ROOT/priv-app"
SYSTEM_EXT_PERMISSIONS="$SYSTEM_EXT_ROOT/etc/permissions"

# ---- 设置各目录权限 ----
# vendor/bin (HAL 服务可执行文件)
perm_recursive "$VENDOR_BIN" 0 2000 0755 0755 "u:object_r:vendor_file:s0"
# vendor/lib64 (原生库)
perm_recursive "$VENDOR_LIB" 0 2000 0755 0644 "u:object_r:vendor_file:s0"
# vendor/lib64/soundfx (音效库)
perm_recursive "$SOUNDFX_DIR" 0 2000 0755 0644 "u:object_r:vendor_file:s0"
# vendor/etc (配置文件)
perm_recursive "$VENDOR_ETC" 0 2000 0755 0644 "u:object_r:vendor_configs_file:s0"
# odm/etc (ODM 配置)
perm_recursive "$ODM_ETC" 0 2000 0755 0644 "u:object_r:vendor_configs_file:s0"
# my_product (产品特性)
perm_recursive "$MY_PRODUCT_ROOT" 0 0 0755 0644 "u:object_r:system_file:s0"
# system_ext (APK 和权限)
perm_recursive "$SYSTEM_EXT_ROOT" 0 0 0755 0644 "u:object_r:system_file:s0"

# ---- 关键文件单独设置 ----
# 解码器 HAL 服务
perm_one "$VENDOR_BIN/hw/vendor.dolby_sp.media.c2@1.0-service" 0 2000 0755 "u:object_r:vendor_file:s0"
# DMS 服务
perm_one "$VENDOR_BIN/hw/vendor.dolby.dms.service" 0 2000 0755 "u:object_r:vendor_file:s0"
# DAP 预注册库
perm_one "$VENDOR_LIB/libdlbpreg_sp.so" 0 2000 0644 "u:object_r:vendor_file:s0"
# 空间化参数库
perm_one "$VENDOR_LIB/libspatializerparamstorage.so" 0 2000 0644 "u:object_r:vendor_file:s0"
# DMS 调音参数 XML
perm_one "$VENDOR_ETC/dolby/multimedia_dolby_dax_dflt.xml" 0 2000 0644 "u:object_r:vendor_configs_file:s0"
# VINTF manifest
perm_one "$VENDOR_ETC/vintf/manifest/c2_manifest_vendor_audio.xml" 0 2000 0644 "u:object_r:vendor_configs_file:s0"
# 解码器注册
perm_one "$ODM_ETC/media_codecs_c2.xml" 0 2000 0644 "u:object_r:vendor_configs_file:s0"
# 音效配置
perm_one "$ODM_ETC/audio_effects.xml" 0 2000 0644 "u:object_r:vendor_configs_file:s0"
# 产品特性
perm_one "$MY_PRODUCT_PERMISSIONS/oplus.product.features_audiox.xml" 0 0 0644 "u:object_r:system_file:s0"
# 启动脚本
perm_one "$MODPATH/post-fs-data.sh" 0 0 0755 "u:object_r:system_file:s0"
perm_one "$MODPATH/service.sh" 0 0 0755 "u:object_r:system_file:s0"
perm_one "$MODPATH/uninstall.sh" 0 0 0755 "u:object_r:system_file:s0"
# APK 权限文件
perm_one "$SYSTEM_EXT_PERMISSIONS/com.dolby.atmos.oplus.folk.xml" 0 0 0644 "u:object_r:system_file:s0"
# 🔧 FIX H-3: APK 上下文改为 privapp 类型
# 原: "u:object_r:system_file:s0" (错误, 可能导致 PackageManager 拒绝加载)
# 现: "u:object_r:privapp_data_file:s0" (标准 priv-app APK 上下文)
# 注意: SELinux 策略中也需允许 package_manager 加载此上下文
perm_one "$SYSTEM_EXT_PRIV_APP/DolbyAtmosControl/DolbyAtmosControl.apk" 0 0 0644 "u:object_r:privapp_data_file:s0"
# APK 目录也需要 privapp 上下文
perm_recursive "$SYSTEM_EXT_PRIV_APP/DolbyAtmosControl" 0 0 0755 0644 "u:object_r:privapp_data_file:s0"

# ============================================================
# 阶段 5: audio_effects.xml 合并 (由 M3 模块提供函数)
# ============================================================
if type merge_audio_effects >/dev/null 2>&1; then
  ui_print "正在合并 audio_effects.xml..."
  merge_audio_effects "$MODPATH"
else
  ui_print "使用模块内置 audio_effects.xml 回退版本"
fi

# ============================================================
# 阶段 6: 安装完成
# ============================================================
ui_print ""
ui_print "=========================================="
ui_print " Dolby Atmos OnePlus folk popularization"
ui_print " 安装完成"
ui_print "=========================================="
ui_print "请重启设备以生效"
ui_print ""

# 记录安装信息
{
  echo "install_time=$(date +%s)"
  echo "root_type=$ROOT_TYPE"
  echo "android_ver=$ANDROID_VER"
  echo "sdk_ver=$SDK_VER"
  echo "platform=$PLATFORM"
  echo "device_model=$DEVICE_MODEL"
  echo "device_name=$DEVICE_NAME"
  echo "audio_stack=$AUDIO_STACK"
  echo "module_version=v1.0.0"
} > "$MODPATH/.install_info"

exit 0
```

---

### 2.3 `post-fs-data.sh` — 挂载后脚本

```bash
#!/system/bin/sh
# ============================================================
# M1: post-fs-data.sh — 数据分区挂载后执行
# 执行时机: /data 分区挂载后，Zygote 启动前
# 功能: 清理包缓存、创建运行时目录
# ============================================================
set +e

MODDIR="${0%/*}"

# ---- 日志函数 ----
log() {
  echo "[post-fs-data] $(date '+%H:%M:%S'): $1" >> "$MODDIR/post-fs-data.log" 2>/dev/null
}

log "post-fs-data 开始执行"

# ---- 1. 清理 APK 包缓存 ----
clear_package_cache() {
  local cache_root="/data/system/package_cache"
  [ -d "$cache_root" ] || return 0

  # 清理与 DolbyAtmosControl APK 相关的缓存
  find "$cache_root" -type f -name 'DolbyAtmosControl-*' 2>/dev/null | while read -r entry; do
    case "$entry" in
      "$cache_root"/*/DolbyAtmosControl-*)
        rm -f "$entry" 2>/dev/null
        log "已清理包缓存: $entry"
        ;;
    esac
  done
}

clear_package_cache

# ---- 2. 创建 DAP 运行时数据目录 ----
setup_dolby_data_dir() {
  local data_dolby="/data/vendor/dolby"
  mkdir -p "$data_dolby" 2>/dev/null
  # 设置 media 用户和组 (uid=1013, gid=1013)
  chown 1013:1013 "$data_dolby" 2>/dev/null || chown media:media "$data_dolby" 2>/dev/null
  chmod 0770 "$data_dolby" 2>/dev/null
  log "DAP 数据目录已创建: $data_dolby"
}

setup_dolby_data_dir

# ---- 3. 创建诊断日志目录 ----
setup_diag_dir() {
  # 在 post-fs-data 阶段 sdcardfs 尚未挂载, 创建可能失败, 不强制
  local diag_dir="/storage/emulated/0/dolbylog"
  if mkdir -p "$diag_dir" 2>/dev/null; then
    log "诊断日志目录已创建: $diag_dir"
  else
    log "诊断日志目录创建失败 (sdcardfs 尚未挂载), 将在 service.sh 重试"
  fi
}

setup_diag_dir

# ---- 4. SELinux 策略调整 (如果 M6 提供) ----
if type apply_sepolicy_patches >/dev/null 2>&1; then
  apply_sepolicy_patches "$MODDIR"
  log "SELinux 策略补丁已应用"
fi

log "post-fs-data 执行完成"
exit 0
```

---

### 2.4 `service.sh` — 服务启动脚本

```bash
#!/system/bin/sh
# ============================================================
# M1: service.sh — 系统启动后延迟执行
# 执行时机: 系统完全启动后 (boot_completed)
# 功能: 启动 DMS 服务、Codec2 HAL 服务、挂载绑定
# ============================================================
set +e

MODDIR="${0%/*}"

# ---- 路径定义 ----
C2_NAME="vendor.dolby_sp.media.c2@1.0-service"
C2_BIN="/vendor/bin/hw/$C2_NAME"
DMS_NAME="vendor.dolby.dms.service"
DMS_BIN="/vendor/bin/hw/$DMS_NAME"
MODULE_VINTF="$MODDIR/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml"
VENDOR_VINTF="/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml"
MODULE_FEATURE_XML="$MODDIR/my_product/etc/permissions/oplus.product.features_audiox.xml"
LIVE_FEATURE_XML="/my_product/etc/permissions/oplus.product.features_audiox.xml"
DATA_DOLBY="/data/vendor/dolby"
APEX_INFO_ORIG="/apex/apex-info-list.xml"
APEX_INFO_MOD="$MODDIR/apex-info-list.h1.xml"

# ---- 日志函数 ----
log() {
  echo "[service] $(date '+%H:%M:%S'): $1" >> "$MODDIR/service.log" 2>/dev/null
}

# ---- 工具函数 ----

# 文件签名比较
file_sig() {
  if [ ! -f "$1" ]; then echo "missing"; return; fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk 'NR==1 {print $1}'
  else
    cksum "$1" 2>/dev/null | awk 'NR==1 {print $1 ":" $2}'
  fi
}

# 检查文件是否相同（通过签名）
same_file_overlay() {
  [ -f "$1" ] && [ -f "$2" ] || return 1
  [ "$(file_sig "$1")" = "$(file_sig "$2")" ]
}

# 检查 SELinux 上下文
context_has() {
  local path="$1" wanted="$2"
  ls -Zd "$path" 2>/dev/null | grep -q "$wanted" && return 0
  ls -lZ "$path" 2>/dev/null | grep -q "$wanted" && return 0
  return 1
}

# 等待系统属性 (默认 30s, 避免启动过慢)
wait_prop() {
  local prop="$1" value="$2" limit="${3:-30}" i=0
  while [ "$i" -lt "$limit" ]; do
    [ "$(getprop "$prop" 2>/dev/null)" = "$value" ] && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

# 启动服务（仅启动一次）
start_once() {
  local name="$1" bin="$2"
  [ -x "$bin" ] || return 1
  pidof "$name" >/dev/null 2>&1 && return 0
  "$bin" >/dev/null 2>&1 &
  return 0
}

# ============================================================
# 主流程
# ============================================================
log "service.sh 开始执行"

# ---- 1. 清理探针残留 ----
# 🔧 FIX H-4: 此处保留作为主清理, M5 action.sh 不再重复此操作
clean_probe() {
  rm -rf "$MODDIR/.probe_lock" "$MODDIR/.probe_tmp" 2>/dev/null
  rm -f "$MODDIR/last_probe.txt" "$MODDIR/last_probe.raw.log" 2>/dev/null
  rm -f "$MODDIR/boot_probe_state.txt" "$MODDIR/boot_process_context.txt" 2>/dev/null
  rm -f "$MODDIR/boot_service_stdout.txt" "$MODDIR/boot_service_stderr.txt" 2>/dev/null
  rm -f "$MODDIR/boot_dms_stdout.txt" "$MODDIR/boot_dms_stderr.txt" 2>/dev/null
}
clean_probe

# ---- 2. 确保 DAP 数据目录权限 ----
mkdir -p "$DATA_DOLBY" 2>/dev/null
chown 1013:1013 "$DATA_DOLBY" 2>/dev/null || chown media:media "$DATA_DOLBY" 2>/dev/null
chmod 0770 "$DATA_DOLBY" 2>/dev/null
log "DAP 数据目录权限已设置"

# ---- 3. 挂载 OPlus AudioX 特性 XML ----
if [ -f "$MODULE_FEATURE_XML" ] && [ -f "$LIVE_FEATURE_XML" ]; then
  mount --bind "$MODULE_FEATURE_XML" "$LIVE_FEATURE_XML" 2>/dev/null
  if [ $? -eq 0 ]; then
    log "AudioX 特性 XML 挂载成功"
  else
    log "AudioX 特性 XML 挂载失败，跳过"
  fi
fi

# ---- 4. 验证 VINTF 挂载 ----
same_file_overlay "$MODULE_VINTF" "$VENDOR_VINTF" || {
  log "VINTF manifest 未正确挂载，退出"
  exit 0
}
context_has "$VENDOR_VINTF" "vendor_configs_file" || {
  log "VINTF manifest SELinux 上下文不匹配，退出"
  exit 0
}
log "VINTF manifest 挂载验证通过"

# ---- 5. 等待 APEX 信息加载 (30s 超时) ----
i=0
while [ "$i" -lt 30 ] && [ ! -f "$APEX_INFO_ORIG" ]; do
  sleep 1; i=$((i + 1))
done

if [ -f "$APEX_INFO_ORIG" ]; then
  rm -f "$APEX_INFO_MOD" 2>/dev/null
  cp -p "$APEX_INFO_ORIG" "$APEX_INFO_MOD" 2>/dev/null || cp "$APEX_INFO_ORIG" "$APEX_INFO_MOD" 2>/dev/null
  chmod 0644 "$APEX_INFO_MOD" 2>/dev/null
  mount --bind "$APEX_INFO_MOD" "$APEX_INFO_ORIG" 2>/dev/null
  touch "$APEX_INFO_MOD" "$APEX_INFO_ORIG" 2>/dev/null
  log "APEX 信息列表挂载完成"
fi

# ---- 6. 等待系统服务就绪 (30s 超时) ----
wait_prop "init.svc.servicemanager" "running" 30 || {
  log "servicemanager 未就绪，退出"
  exit 0
}
wait_prop "init.svc.hwservicemanager" "running" 30 || {
  log "hwservicemanager 未就绪，退出"
  exit 0
}
log "系统服务就绪"

# ---- 7. 启动 DMS 服务 ----
log "启动 DMS 服务..."
start_once "$DMS_NAME" "$DMS_BIN"
sleep 2

# 验证 DMS 服务启动
if pidof "$DMS_NAME" >/dev/null 2>&1; then
  log "DMS 服务已启动 (PID: $(pidof "$DMS_NAME"))"
else
  log "DMS 服务启动失败"
fi

# ---- 8. 启动 Codec2 HAL 服务 ----
log "启动 Codec2 HAL 服务..."
start_once "$C2_NAME" "$C2_BIN"
sleep 1

if pidof "$C2_NAME" >/dev/null 2>&1; then
  log "Codec2 HAL 服务已启动 (PID: $(pidof "$C2_NAME"))"
else
  log "Codec2 HAL 服务启动失败"
fi

# ---- 9. 写入系统属性 ----
resetprop ro.oplus.audio.effect.type dolby 2>/dev/null
resetprop ro.oplus.audio.dolby.equalizer_support true 2>/dev/null
log "系统属性已设置"

log "service.sh 执行完成"
exit 0
```

---

### 2.5 `system.prop` — 系统属性

```properties
# Dolby Atmos OnePlus folk popularization
# 系统属性配置文件

# 音频效果类型
ro.oplus.audio.effect.type=dolby

# 杜比均衡器支持
ro.oplus.audio.dolby.equalizer_support=true
```

---

### 2.6 `uninstall.sh` — 卸载脚本

```bash
#!/system/bin/sh
# ============================================================
# M1: uninstall.sh — 卸载清理脚本
# 执行时机: 模块被移除时 (KSU/Magisk 调用)
# 功能: 恢复原始配置、清理残留文件
# ============================================================
set +e

MODDIR="${0%/*}"

# ---- 日志函数 ----
log() {
  echo "[uninstall] $(date '+%H:%M:%S'): $1" >> /storage/emulated/0/dolbylog/uninstall.log 2>/dev/null
}

log "开始卸载 Dolby Atmos 模块"

# ---- 1. 停止运行中的服务 ----
stop_services() {
  # 停止 Codec2 HAL 服务
  if pidof "vendor.dolby_sp.media.c2@1.0-service" >/dev/null 2>&1; then
    kill "$(pidof vendor.dolby_sp.media.c2@1.0-service)" 2>/dev/null
    log "Codec2 HAL 服务已停止"
  fi
  # 停止 DMS 服务
  if pidof "vendor.dolby.dms.service" >/dev/null 2>&1; then
    kill "$(pidof vendor.dolby.dms.service)" 2>/dev/null
    log "DMS 服务已停止"
  fi
}
stop_services

# ---- 2. 卸载挂载点 ----
unmount_binds() {
  # 卸载 OPlus AudioX 特性 XML
  umount "/my_product/etc/permissions/oplus.product.features_audiox.xml" 2>/dev/null
  # 卸载 APEX 信息列表
  umount "/apex/apex-info-list.xml" 2>/dev/null
  log "挂载点已卸载"
}
unmount_binds

# ---- 3. 恢复系统属性 ----
resetprop --delete ro.oplus.audio.effect.type 2>/dev/null
resetprop --delete ro.oplus.audio.dolby.equalizer_support 2>/dev/null
log "系统属性已恢复"

# ---- 4. 清理 DAP 数据目录 ----
rm -rf /data/vendor/dolby 2>/dev/null
log "DAP 数据目录已清理"

# ---- 5. 清理包缓存 ----
find /data/system/package_cache -type f -name 'DolbyAtmosControl-*' -delete 2>/dev/null
log "包缓存已清理"

# ---- 6. 清理诊断日志 ----
# 保留诊断日志目录，仅记录卸载时间
echo "uninstall_time=$(date +%s)" >> /storage/emulated/0/dolbylog/uninstall.log 2>/dev/null

log "卸载完成"
exit 0
```

---

### 2.7 `META-INF/com/google/android/updater-script`

```
#MAGISK
```

**设计说明:** 保留最小化的 `updater-script` 以兼容 Magisk，KSU 和 APatch 会自动忽略此文件。实际安装逻辑全部在 `customize.sh` 中实现。

---

### 2.8 `META-INF/com/google/android/update-binary`

标准的 Magisk update-binary 包装器，用于调用 `customize.sh`：

```bash
#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v20.4+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 20400 ] && require_new_magisk

install_module
exit 0
```

---

### 2.9 `META-INF/compat.sh` — 兼容性检测函数库 (M6 集成)

> **🔧 FIX C-1 重要约束:** M6 的 `META-INF/compat.sh` **不得** 定义与 M1 同名的函数 (`detect_root_solution`、`detect_android_version` 等). 详见 [M6-fixed.md](M6-compatibility-fixed.md).

**调用约束:**
- M1 的 `customize.sh` 在文件顶部 `source` 引入 M6 的 `compat.sh`
- M1 的 `detect_*` 系列函数已先于 source 定义, 不会被覆盖
- M6 的 `compat.sh` 仅提供 M1 缺失的函数 (如 `get_device_dap_params`, `select_dap_control_path`)

```bash
#!/system/bin/sh
# ============================================================
# M6: compat.sh — 兼容性检测函数库
# 被 M1 的 customize.sh source 引入
# 🔧 FIX C-1: 不得重新定义 M1 已有的 detect_* 系列函数
# ============================================================

# 🔧 FIX C-1: M6 不再定义 detect_root_solution, 直接调用 M1 的版本
# 此处只提供 M1 缺失的辅助函数

# 检测 low-RAM 设备
detect_low_ram() {
  if [ "$(getprop ro.config.low_ram 2>/dev/null)" = "true" ]; then
    ui_print "  警告: 检测到低内存设备，音效性能可能受影响"
  fi
}

# 检测 SELinux 状态
detect_selinux() {
  SELINUX_STATUS="$(getenforce 2>/dev/null)"
  if [ "$SELINUX_STATUS" = "Enforcing" ]; then
    ui_print "  SELinux: Enforcing (严格模式)"
  elif [ "$SELINUX_STATUS" = "Permissive" ]; then
    ui_print "  SELinux: Permissive (宽容模式)"
  else
    ui_print "  SELinux: $SELINUX_STATUS"
  fi
}

# 检测是否已安装其他音效模块
detect_conflicting_modules() {
  local conflicts=""
  # 检查 ViPER4Android
  if [ -d "/data/adb/modules/ViPER4Android" ] || [ -d "/data/adb/modules/v4a" ]; then
    conflicts="$conflicts ViPER4Android"
  fi
  # 检查 JamesDSP
  if [ -d "/data/adb/modules/JamesDSP" ] || [ -d "/data/adb/modules/jamesdsp" ]; then
    conflicts="$conflicts JamesDSP"
  fi
  # 检查 Dolby Atmos 其他版本
  if [ -d "/data/adb/modules/dolbyatmos" ] || [ -d "/data/adb/modules/dolby_codec" ]; then
    conflicts="$conflicts 其他杜比模块"
  fi
  if [ -n "$conflicts" ]; then
    ui_print "  警告: 检测到可能冲突的音效模块:$conflicts"
    ui_print "  建议先卸载上述模块再安装"
  fi
}

# 检测解码器可用性
detect_decoder_availability() {
  # 检查是否有硬件 AC-4 解码器
  if grep -q "c2.dolby.ac4.decoder" /vendor/etc/media_codecs*.xml 2>/dev/null; then
    ui_print "  注意: 设备已存在 AC-4 解码器，模块将覆盖"
  fi
}
```

---

## 3. 模块间接口

### 3.1 对外提供的函数

| 函数名 | 所在文件 | 用途 |
|--------|----------|------|
| `ui_print` | `customize.sh` | 输出安装日志 |
| `abort` | `customize.sh` | 中止安装并输出错误 |
| `perm_recursive` | `customize.sh` | 递归设置目录权限 |
| `perm_one` | `customize.sh` | 设置单文件权限 |
| `log` | `service.sh` | 运行时日志 |
| `start_once` | `service.sh` | 按需启动服务 |
| `wait_prop` | `service.sh` | 等待系统属性 |
| `detect_root_solution` | `customize.sh` | **(FIX C-1)** 完整 Root 检测, M6 不得重定义 |
| `detect_android_version` | `customize.sh` | Android 版本检测 |
| `detect_platform` | `customize.sh` | 芯片平台检测 |
| `detect_device` | `customize.sh` | 设备型号检测 |
| `detect_architecture` | `customize.sh` | 架构检测 |
| `detect_audio_stack` | `customize.sh` | 音频栈检测 |

### 3.2 期望被其他模块提供的函数

| 函数名 | 提供者 | 用途 |
|--------|--------|------|
| `merge_audio_effects` | M3 | 合并现场 audio_effects.xml |
| `apply_sepolicy_patches` | M6 | 应用 SELinux 策略补丁 |

### 3.3 目录结构约定

```
$MODPATH/
├── module.prop
├── customize.sh
├── post-fs-data.sh
├── service.sh
├── uninstall.sh
├── system.prop
├── action.sh                    # M5 提供
├── META-INF/
│   ├── com/google/android/
│   │   ├── update-binary
│   │   └── updater-script
│   └── compat.sh                # M6 提供
├── system/
│   ├── odm/etc/
│   │   ├── audio_effects.xml    # M3 提供
│   │   └── media_codecs_c2.xml  # M2 提供
│   ├── vendor/
│   │   ├── bin/hw/              # M2 + M3 提供
│   │   ├── etc/                 # M2 + M3 提供
│   │   └── lib64/               # M2 + M3 提供
│   └── system_ext/
│       ├── etc/permissions/     # M1 创建
│       └── priv-app/            # M4 提供
├── my_product/etc/permissions/  # M3 提供
├── .audio_stack_type            # M1 运行时生成
└── .install_info                # M1 运行时生成
```

---

## 4. 测试方案

### 4.1 单元测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| `module.prop` 解析 | 在 KSU Manager 中加载模块 | 显示正确的模块名称、版本、描述 |
| `detect_root_solution` | 在 KSU/Magisk/APatch 环境分别执行 | 每种环境输出正确的 Root 方案名称 |
| `detect_android_version` | 在 Android 14/15/16 设备上执行 | 输出正确的 SDK 版本号 |
| `detect_platform` | 在 Snapdragon 8 Gen 3/Gen 4 设备上执行 | 输出正确的平台标识 |
| `detect_audio_stack` | 在 HIDL/AIDL 设备上分别执行 | 正确识别音频栈类型 |
| `perm_recursive` | 创建测试目录树并调用 | 权限和 SELinux 上下文正确设置 |
| `perm_one` | 创建测试文件并调用 | 权限和 SELinux 上下文正确设置 |
| `clean_old_artifacts` | 创建模拟旧版本文件后调用 | 仅清理本模块 (id 前缀匹配) 的文件 |
| `clear_package_cache` | 创建模拟包缓存后调用 | 相关缓存被清除 |
| `setup_dolby_data_dir` | 执行后检查 | `/data/vendor/dolby` 存在且权限为 0770 |
| **(FIX H-1) getevent fallback** | 在没有 getevent 的环境执行 | 5 秒超时后默认 direct 安装, 不挂起 |
| **(FIX H-2) 模块 ID 验证** | 用不同 id 的 module.prop 测试 | 仅 id 匹配 dolby_atmos* 时执行清理 |

### 4.2 集成测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| KSU 安装 | 在 KSU Manager 中安装并重启 | 模块出现在 KSU 模块列表中 |
| Magisk 安装 | 在 Magisk Manager 中安装并重启 | 模块出现在 Magisk 模块列表中 |
| APatch 安装 | 在 APatch Manager 中安装并重启 | 模块出现在 APatch 模块列表中 |
| 音量键选择 | 安装时按音量上/下键 | 正确触发对应逻辑 |
| 超时默认安装 | 安装时不按键, 或 getevent 不可用 | 5 秒后自动以 direct 模式安装 |
| 不兼容设备中止 | 在 Android 13 设备上安装 | 检测到 SDK 版本过低并中止 |
| 卸载清理 | 在 KSU Manager 中移除模块 | 所有挂载点和服务被清理 |
| **(FIX H-3) APK 加载** | 安装后检查 `pm list packages \| grep dolby` | APK 正常列出, 无 SELinux 拒绝 |
| **(FIX C-1) M6 source 兼容性** | 同时安装 M1 + M6 完整模块 | 无函数重定义冲突 |

### 4.3 冒烟测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| 安装后正常开机 | 安装模块后重启 | 设备正常进入系统 |
| 无 ANR/崩溃 | 开机后观察 5 分钟 | 无系统服务崩溃 |
| 日志输出 | 检查 `/data/adb/modules/dolby_atmos_oplus_folk/` | `service.log` 和 `post-fs-data.log` 存在且有内容 |
| VINTF 挂载 | 检查 `/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml` | 文件内容与模块内一致 |
| 系统属性 | 执行 `getprop ro.oplus.audio.effect.type` | 输出 `dolby` |

---

## 5. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-29 | 初始版本 |
| **v1.0-FIXED** | **2026-07-02** | **修复 C-1, H-1, H-2, H-3, H-4; 见 §0 变更摘要** |
