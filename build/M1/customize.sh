#!/system/bin/sh
# ============================================================
# M1: customize.sh — Dolby Atmos 模块安装脚本
# 兼容: KSU / Magisk / APatch
# 功能: 兼容性检测、音量键选择、文件权限、audio_effects 合并
# ============================================================
# shellcheck disable=SC3043  # local is supported in dash and busybox ash

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
COMPAT_SCRIPT="$MODPATH/META-INF/compat.sh"
# shellcheck disable=SC1090  # source path is provided by M6 at packaging time
if [ -f "$COMPAT_SCRIPT" ]; then
  . "$COMPAT_SCRIPT"
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
  # ROOT_VER / ROOT_VER_CODE are recorded in .install_info via caller
  echo "$ROOT_VER" > "$MODPATH/.root_ver" 2>/dev/null
  echo "$ROOT_VER_CODE" > "$MODPATH/.root_ver_code" 2>/dev/null
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
  echo "$PLATFORM_FAMILY" > "$MODPATH/.platform_family" 2>/dev/null
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
  echo "$IS_OPLUS" > "$MODPATH/.is_oplus" 2>/dev/null
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
ui_print "等待 10 秒后默认直接安装..."

KEY_CLICK=""
TIMEOUT=10
while [ "$TIMEOUT" -gt 0 ] && [ -z "$KEY_CLICK" ]; do
  if command -v getevent >/dev/null 2>&1; then
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

clean_old_artifacts() {
  local modpath="$1"
  # 清理旧版 APK 残留
  rm -rf "$modpath/system/system_ext/priv-app/daxapp" 2>/dev/null
  rm -rf "$modpath/system/system_ext/priv-app/daxcontroller" 2>/dev/null
  # 清理探针文件
  rm -rf "$modpath/.probe_lock" "$modpath/.probe_tmp" 2>/dev/null
  rm -f "$modpath/last_probe.txt" "$modpath/last_probe.raw.log" 2>/dev/null
  rm -f "$modpath/boot_probe_state.txt" "$modpath/boot_process_context.txt" 2>/dev/null
  rm -f "$modpath/boot_service_stdout.txt" "$modpath/boot_service_stderr.txt" 2>/dev/null
  rm -f "$modpath/boot_dms_stdout.txt" "$modpath/boot_dms_stderr.txt" 2>/dev/null
  # 清理旧版权限文件
  rm -f "$modpath/system/system_ext/etc/permissions/com.flyfish233.daxapp.xml" 2>/dev/null
  rm -f "$modpath/system/system_ext/etc/permissions/com.flyfish233.daxcontroller.xml" 2>/dev/null
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
# VINTf manifest
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
# APK 文件
perm_one "$SYSTEM_EXT_PRIV_APP/DolbyAtmosControl/DolbyAtmosControl.apk" 0 0 0644 "u:object_r:system_file:s0"

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
