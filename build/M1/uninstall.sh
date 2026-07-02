#!/system/bin/sh
# ============================================================
# M1: uninstall.sh — 卸载清理脚本
# 执行时机: 模块被移除时 (KSU/Magisk 调用)
# 功能: 恢复原始配置、清理残留文件
# ============================================================
# shellcheck disable=SC3043  # local is supported in dash and busybox ash
# shellcheck disable=SC2034  # MODDIR is set by Magisk/KSU; uninstaller logs to fixed path
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
