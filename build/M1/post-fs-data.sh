#!/system/bin/sh
# ============================================================
# M1: post-fs-data.sh — 数据分区挂载后执行
# 执行时机: /data 分区挂载后，Zygote 启动前
# 功能: 清理包缓存、创建运行时目录
# ============================================================
# shellcheck disable=SC3043  # local is supported in dash and busybox ash
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
  local diag_dir="/storage/emulated/0/dolbylog"
  mkdir -p "$diag_dir" 2>/dev/null && log "诊断日志目录已创建: $diag_dir"
}

setup_diag_dir

# ---- 4. SELinux 策略调整 (如果 M6 提供) ----
if type apply_sepolicy_patches >/dev/null 2>&1; then
  apply_sepolicy_patches "$MODDIR"
  log "SELinux 策略补丁已应用"
fi

log "post-fs-data 执行完成"
exit 0
