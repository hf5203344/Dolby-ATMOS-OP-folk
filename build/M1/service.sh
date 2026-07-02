#!/system/bin/sh
# ============================================================
# M1: service.sh — 系统启动后延迟执行
# 执行时机: 系统完全启动后 (boot_completed)
# 功能: 启动 DMS 服务、Codec2 HAL 服务、挂载绑定
# ============================================================
# shellcheck disable=SC3043  # local is supported in dash and busybox ash
# shellcheck disable=SC2010  # ls -Zd/-lZ output is consumed only by grep, no filenames
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

# 等待系统属性
wait_prop() {
  local prop="$1" value="$2" limit="$3" i=0
  while [ "$i" -lt "$limit" ]; do
    [ "$(getprop "$prop" 2>/dev/null)" = "$value" ] && return 0
    sleep 1
    i=$((i + 1))
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
  if mount --bind "$MODULE_FEATURE_XML" "$LIVE_FEATURE_XML" 2>/dev/null; then
    log "AudioX 特性 XML 挂载成功"
  else
    log "AudioX 特性 XML 挂载失败，跳过"
  fi
fi

# ---- 4. 验证 VINTF 挂载 ----
if ! same_file_overlay "$MODULE_VINTF" "$VENDOR_VINTF"; then
  log "VINTF manifest 未正确挂载，退出"
  exit 0
fi
if ! context_has "$VENDOR_VINTF" "vendor_configs_file"; then
  log "VINTF manifest SELinux 上下文不匹配，退出"
  exit 0
fi
log "VINTF manifest 挂载验证通过"

# ---- 5. 等待 APEX 信息加载 ----
i=0
while [ "$i" -lt 60 ] && [ ! -f "$APEX_INFO_ORIG" ]; do
  sleep 1
  i=$((i + 1))
done

if [ -f "$APEX_INFO_ORIG" ]; then
  rm -f "$APEX_INFO_MOD" 2>/dev/null
  cp -p "$APEX_INFO_ORIG" "$APEX_INFO_MOD" 2>/dev/null || cp "$APEX_INFO_ORIG" "$APEX_INFO_MOD" 2>/dev/null
  chmod 0644 "$APEX_INFO_MOD" 2>/dev/null
  mount --bind "$APEX_INFO_MOD" "$APEX_INFO_ORIG" 2>/dev/null
  touch "$APEX_INFO_MOD" "$APEX_INFO_ORIG" 2>/dev/null
  log "APEX 信息列表挂载完成"
fi

# ---- 6. 等待系统服务就绪 ----
if ! wait_prop "init.svc.servicemanager" "running" 60; then
  log "servicemanager 未就绪，退出"
  exit 0
fi
if ! wait_prop "init.svc.hwservicemanager" "running" 60; then
  log "hwservicemanager 未就绪，退出"
  exit 0
fi
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
