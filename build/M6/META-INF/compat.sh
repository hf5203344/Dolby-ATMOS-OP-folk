#!/system/bin/sh
# ============================================================
# M6: compat.sh — 兼容性检测函数库
# 被 M1 的 customize.sh 在安装时 source 引入
# ============================================================
#
# 本文件为 M6 模块的核心函数库,提供设备/兼容性/多机型适配能力
# 严格使用 POSIX sh 编写,目标运行时为 Android /system/bin/sh (mksh)
# 所有函数先定义再被调用 (POSIX sh 要求)
#
# 依赖 (由调用方 source 之前注入):
#   - getprop : Android getprop 命令
#   - dumpsys : Android dumpsys 命令
#   - magiskpolicy : SELinux 策略工具
#   - command : POSIX 标准命令
#
# 调用方需提供的回调:
#   - ui_print : 自定义输出函数 (M1 的 install_module 环境提供)
#
# Android /system/bin/sh 实际为 mksh,支持 local 局部变量
# 故针对 POSIX 严格模式的 SC3043 (local 未定义) 警告可安全忽略
# shellcheck disable=SC3043

# ============================================================
# 1. 设备信息函数 (5)
# ============================================================

# 获取设备型号
get_device_model() {
  getprop ro.product.model 2>/dev/null || echo "unknown"
}

# 获取设备代号
get_device_code() {
  getprop ro.product.device 2>/dev/null || echo "unknown"
}

# 获取芯片平台
get_platform() {
  local plat
  plat=$(getprop ro.board.platform 2>/dev/null)
  if [ -n "$plat" ]; then
    echo "$plat"
    return 0
  fi
  plat=$(getprop ro.hardware 2>/dev/null)
  if [ -n "$plat" ]; then
    echo "$plat"
    return 0
  fi
  echo "unknown"
}

# 获取 Android SDK 版本
get_sdk_version() {
  local sdk
  sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  if [ -n "$sdk" ]; then
    echo "$sdk"
  else
    echo "0"
  fi
}

# 获取 Android 版本
get_android_version() {
  getprop ro.build.version.release 2>/dev/null || echo "unknown"
}

# ============================================================
# 2. 兼容性检测函数 (5)
# ============================================================

# 检测 Root 方案
detect_root_solution() {
  if [ -n "$KSU" ]; then
    echo "KSU"
  elif [ -n "$APATCH" ]; then
    echo "APatch"
  elif [ -n "$MAGISK_VER" ]; then
    echo "Magisk"
  else
    echo "Unknown"
  fi
}

# 检测是否为 OPlus 设备
is_oplus_device() {
  local oem
  oem=$(getprop ro.product.manufacturer 2>/dev/null)
  case "$oem" in
    *OnePlus*|*oneplus*|*OPPO*|*oplus*|*Oplus*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 检测音频 HAL 栈类型
detect_audio_stack() {
  if [ -e "/vendor/lib64/libaconfig_storage_read_api_cc.so" ] || \
     [ -e "/odm/etc/vintf/manifest/dvs-aidl-service.xml" ]; then
    echo "AIDL"
  else
    echo "HIDL"
  fi
}

# 检测是否已安装冲突模块
detect_conflicts() {
  local conflicts=""
  local mod_dir="/data/adb/modules"

  # 检查 ViPER4Android
  if [ -d "$mod_dir/ViPER4Android" ] || [ -d "$mod_dir/v4a" ]; then
    conflicts="$conflicts ViPER4Android"
  fi

  # 检查 JamesDSP
  if [ -d "$mod_dir/JamesDSP" ] || [ -d "$mod_dir/jamesdsp" ]; then
    conflicts="$conflicts JamesDSP"
  fi

  # 检查其他杜比模块
  if [ -d "$mod_dir/dolbyatmos" ]; then
    conflicts="$conflicts DolbyAtmos(other)"
  fi
  if [ -d "$mod_dir/dolby_codec" ]; then
    conflicts="$conflicts DolbyCodec(other)"
  fi
  if [ -d "$mod_dir/dolbycodec2hidl" ]; then
    conflicts="$conflicts DolbyCodec2HIDL(reference)"
  fi

  # 检查 Audio Modification Library
  if [ -d "$mod_dir/aml" ]; then
    conflicts="$conflicts AML"
  fi

  # 检查 Audio Compatibility Patch
  if [ -d "$mod_dir/acp" ]; then
    conflicts="$conflicts ACP"
  fi

  echo "$conflicts"
}

# 检测是否存在硬件杜比解码器
detect_hardware_dolby() {
  # 兼容 glob 无匹配情况: sh -e 在 set -e 模式下会因为 set -- 不匹配而失败
  # 因此先收集再 grep,避免在 set -e 模式下出错
  if ls /vendor/etc/media_codecs*.xml >/dev/null 2>&1; then
    if grep -q "c2.dolby" /vendor/etc/media_codecs*.xml 2>/dev/null; then
      echo "yes"
    else
      echo "no"
    fi
  else
    echo "no"
  fi
}

# ============================================================
# 3. 安装前综合检测 (1)
# ============================================================

# pre_install_check
# 输出: ui_print 行,警告/错误信息
# 返回: error 数 (0=通过, >0=错误数)
# 依赖: ui_print 由调用方定义
pre_install_check() {
  local errors=0
  local sdk
  local cpu_abi
  local conflicts

  # 3.1 SDK 版本检查
  sdk=$(get_sdk_version)
  if [ "$sdk" -lt 34 ] 2>/dev/null; then
    if type ui_print >/dev/null 2>&1; then
      ui_print "  错误: Android 版本过低 (SDK $sdk, 最低要求 SDK 34)"
    fi
    errors=$((errors + 1))
  fi

  # 3.2 架构检查
  cpu_abi=$(getprop ro.product.cpu.abi 2>/dev/null)
  if [ "$cpu_abi" != "arm64-v8a" ]; then
    if type ui_print >/dev/null 2>&1; then
      ui_print "  错误: 不支持的 CPU 架构 ($cpu_abi)"
    fi
    errors=$((errors + 1))
  fi

  # 3.3 冲突模块检查
  conflicts=$(detect_conflicts)
  if [ -n "$conflicts" ]; then
    if type ui_print >/dev/null 2>&1; then
      ui_print "  警告: 检测到可能冲突的模块:$conflicts"
      ui_print "  建议先卸载上述模块"
    fi
  fi

  # 3.4 硬件解码器检查
  if [ "$(detect_hardware_dolby)" = "yes" ]; then
    if type ui_print >/dev/null 2>&1; then
      ui_print "  注意: 设备已存在硬件杜比解码器,模块将覆盖"
    fi
  fi

  # 3.5 非 OPlus 设备警告
  if ! is_oplus_device; then
    if type ui_print >/dev/null 2>&1; then
      ui_print "  警告: 非一加/OPPO 设备,兼容性未验证"
    fi
  fi

  return $errors
}

# ============================================================
# 4. SELinux 策略补丁 (1)
# ============================================================

# apply_sepolicy_patches
# 入参: $1 = MODDIR (模块根目录)
# 通过 magiskpolicy --live --apply 注入策略;工具不存在时优雅跳过
apply_sepolicy_patches() {
  local MODDIR="$1"
  local patch_file

  if [ -z "$MODDIR" ]; then
    return 0
  fi

  patch_file="$MODDIR/META-INF/sepolicy.rule"

  if [ ! -f "$patch_file" ]; then
    return 0
  fi

  # 使用 magiskpolicy 注入策略
  if command -v magiskpolicy >/dev/null 2>&1; then
    if magiskpolicy --live --apply "$patch_file" 2>/dev/null; then
      if type ui_print >/dev/null 2>&1; then
        ui_print "  SELinux 策略补丁已应用"
      fi
    fi
  fi
  # 缺工具或失败时优雅跳过,无任何输出
  return 0
}

# ============================================================
# 5. 多机型参数 (1)
# ============================================================

# get_device_dap_params
# 输出: 多行 key=value 形式的 DAP 参数
get_device_dap_params() {
  local device_code

  device_code=$(get_device_code)

  case "$device_code" in
    "PKG110")
      # 一加 ACE5
      echo "speaker_channels=2"
      echo "headphone_channels=2"
      echo "bt_max_sampling_rate=48000"
      ;;
    "PKG120"|"PKG130")
      # 一加 ACE5 Pro (待确认)
      echo "speaker_channels=2"
      echo "headphone_channels=2"
      echo "bt_max_sampling_rate=96000"
      ;;
    *)
      # 默认参数
      echo "speaker_channels=2"
      echo "headphone_channels=2"
      echo "bt_max_sampling_rate=48000"
      ;;
  esac
}

# ============================================================
# 6. 运行时适配 (3)
# ============================================================

# select_dap_control_path
# 根据音频栈类型选择 DAP 控制路径
select_dap_control_path() {
  local audio_stack
  local ctrl_path

  audio_stack=$(detect_audio_stack)

  case "$audio_stack" in
    "AIDL")
      # Android 16+ AIDL 音频栈
      ctrl_path="audioeffect_primary_dms_fallback"
      ;;
    "HIDL")
      # HIDL 音频栈 (Android 14-15)
      ctrl_path="dms_hidl_primary_audioeffect_fallback"
      ;;
    *)
      ctrl_path="audioeffect_only"
      ;;
  esac

  echo "$ctrl_path"
}

# check_dap_runtime
# 检测运行时 DAP 可用性
check_dap_runtime() {
  # 检查 AudioFlinger 中是否注册了 DAP 效果
  if dumpsys media.audio_flinger 2>/dev/null | grep -q "9d4921da-8225-4f29-aefa-39537a04bcaa"; then
    echo "available"
  else
    echo "unavailable"
  fi
}

# check_decoder_runtime
# 检测运行时解码器可用性
check_decoder_runtime() {
  if dumpsys media.codec2 2>/dev/null | grep -q "c2.dolby"; then
    echo "available"
  else
    echo "unavailable"
  fi
}
