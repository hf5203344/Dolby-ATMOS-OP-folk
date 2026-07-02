# M5: 诊断工具 — 详细设计文档 **[FIXED v1.0]**

> **版本:** v1.0-FIXED | **日期:** 2026-07-02 | **状态:** 详细设计 (含修复)
> **基础版本:** v1.0 (2026-06-29)
> **本版本变更:** 修复 [设计审查-v1.0.md](../../设计审查-v1.0.md) 中的 H-4, H-10

---

## 0. 本版本变更摘要 (v1.0-FIXED)

| # | 类型 | 章节 | 修复内容 |
|---|------|------|----------|
| H-4 | High | §3 action.sh | 删除与 M1 service.sh 重复的 `clean_probe` 调用, action.sh 改为只读模式 |
| H-10 | High | §3 action.sh | `set -e` 改为 `set +e`, 关键步骤改用显式错误处理, 集成 M2 SHA256 校验 |

---

## 1. 模块概述

### 1.1 职责

M5 提供诊断工具 `action.sh`，由 KSU/Magisk Manager 的"操作"按钮触发，执行：

- 收集模块运行环境的完整状态信息
- 捕获 DAP/Codec2/DMS 服务的运行日志
- 验证关键文件完整性 (包括 **M2 SHA256 校验**)
- 生成可分享的诊断报告

### 1.2 触发方式

KSU/Magisk Manager 中点击模块的"操作"按钮时，调用 `$MODPATH/action.sh`：

```bash
sh $MODPATH/action.sh
```

脚本执行后输出诊断报告路径，用户可手动分享。

### 1.3 输出文件

诊断报告生成到 `/storage/emulated/0/dolbylog/dolby_diag_YYYYMMDD_HHMMSS.txt`，同时保留最近 10 份报告（自动清理旧报告）。

---

## 2. 文件清单

```
$MODPATH/
├── action.sh                          # 主诊断脚本 (🔧 FIX H-10: set +e)
├── tools/
│   ├── diag_helpers.sh                # 公共函数库
│   ├── collect_logs.sh                # 日志收集
│   ├── check_services.sh              # 服务检查
│   └── verify_checksums.sh            # M2 SHA256 校验 (FIX C-2)
└── .diag_state                        # 诊断运行状态 (临时)
```

---

## 3. `action.sh` — 主诊断脚本 **[FIXED H-4, H-10]**

**🔧 FIX H-4 关键变更:** 移除原 action.sh 中 `clean_probe` 的调用, 因为 M1 的 `service.sh` 已经负责清理. action.sh 改为纯只读, 不修改任何运行时状态.

**🔧 FIX H-10 关键变更:** `set -e` 改为 `set +e`. 任一阶段失败不中止, 而是记录错误并继续. 同时集成 M2 SHA256 校验 (FIX C-2).

```bash
#!/system/bin/sh
# ============================================================
# M5: action.sh — 杜比模块诊断工具
# 触发: KSU/Magisk Manager 的"操作"按钮
# 输出: /storage/emulated/0/dolbylog/dolby_diag_*.txt
#
# 🔧 FIX H-4: 移除 clean_probe 调用 (由 M1 service.sh 负责)
# 🔧 FIX H-10: set +e, 关键步骤显式错误处理
# ============================================================

# 🔧 FIX H-10: 不要 set -e. 诊断工具的目标是"尽可能收集信息",
# 任何阶段失败都不应中止后续采集
set +e

# ---- 常量定义 ----
MODDIR="${0%/*}"
DIAG_DIR="/storage/emulated/0/dolbylog"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="$DIAG_DIR/dolby_diag_${TIMESTAMP}.txt"
LOG_FILE="$DIAG_DIR/dolby_diag_${TIMESTAMP}.raw.log"
ERRORS=0
WARNINGS=0
PASSES=0

# ---- 阶段 0: 初始化 ----
mkdir -p "$DIAG_DIR" 2>/dev/null

# 清理旧报告, 仅保留最近 10 份
clean_old_reports() {
  cd "$DIAG_DIR" 2>/dev/null || return
  ls -1t dolby_diag_*.txt 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
  ls -1t dolby_diag_*.raw.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
}
clean_old_reports

# 创建报告文件
: > "$REPORT_FILE"
: > "$LOG_FILE"

# ---- 公共函数 ----

# 写入报告
log() {
  local level="$1"
  shift
  local msg="$(date '+%H:%M:%S') [$level] $@"
  echo "$msg" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
}

# 写入小节标题
section() {
  echo "" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
  echo "============================================" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
  echo " $1" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
  echo "============================================" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
}

# 写入子节
subsection() {
  echo "" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
  echo "--- $1 ---" | tee -a "$REPORT_FILE" "$LOG_FILE" 2>/dev/null
}

# 检查通过
check_pass() {
  PASSES=$((PASSES + 1))
  log "PASS" "$@"
}

# 检查失败
check_fail() {
  ERRORS=$((ERRORS + 1))
  log "FAIL" "$@"
}

# 检查警告
check_warn() {
  WARNINGS=$((WARNINGS + 1))
  log "WARN" "$@"
}

# 检查某个命令的退出码
check_cmd() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    check_pass "$desc"
  else
    check_fail "$desc (命令: $*)"
  fi
}

# 输出到原始日志
raw() {
  echo "$@" >> "$LOG_FILE" 2>/dev/null
}

# 执行命令并捕获输出
run_capture() {
  local desc="$1"
  local cmd="$2"
  log "CMD" "$desc"
  echo "  命令: $cmd" >> "$LOG_FILE" 2>/dev/null
  eval "$cmd" >> "$LOG_FILE" 2>&1
}

# ---- 报告头部 ----
log "INFO" "Dolby Atmos OnePlus folk popularization 诊断报告"
log "INFO" "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
log "INFO" "模块目录: $MODDIR"
log "INFO" "报告文件: $REPORT_FILE"
log "INFO" "原始日志: $LOG_FILE"
log "INFO" "🔧 FIX H-4: 本脚本不修改运行时状态 (只读)"
log "INFO" "🔧 FIX H-10: set +e 模式, 失败不中止, 最大化信息收集"

# ============================================================
# 阶段 1: 系统信息
# ============================================================
section "阶段 1: 系统信息"

subsection "设备信息"
{
  echo "制造商:    $(getprop ro.product.manufacturer 2>/dev/null)"
  echo "型号:      $(getprop ro.product.model 2>/dev/null)"
  echo "代号:      $(getprop ro.product.device 2>/dev/null)"
  echo "芯片:      $(getprop ro.board.platform 2>/dev/null)"
  echo "CPU ABI:   $(getprop ro.product.cpu.abi 2>/dev/null)"
  echo "内核:      $(uname -r 2>/dev/null)"
  echo "SELinux:   $(getenforce 2>/dev/null)"
} >> "$REPORT_FILE"
cat "$REPORT_FILE" | tail -8 | tee -a "$LOG_FILE" >/dev/null

subsection "Android 版本"
{
  echo "Android:   $(getprop ro.build.version.release 2>/dev/null)"
  echo "SDK:       $(getprop ro.build.version.sdk 2>/dev/null)"
  echo "安全补丁:   $(getprop ro.build.version.security_patch 2>/dev/null)"
} >> "$REPORT_FILE"

subsection "Root 信息"
{
  echo "KSU:       ${KSU:-未设置}"
  echo "KSU 版本:  ${KSU_VER:-未设置}"
  echo "KSU 代码:  ${KSU_VER_CODE:-未设置}"
  echo "Magisk:    ${MAGISK_VER:-未设置}"
  echo "APatch:    ${APATCH:-未设置}"
} >> "$REPORT_FILE"

# ============================================================
# 阶段 2: 安装信息
# ============================================================
section "阶段 2: 安装信息"

subsection "模块元数据"
if [ -f "$MODDIR/module.prop" ]; then
  cat "$MODDIR/module.prop" >> "$REPORT_FILE" 2>&1
  check_pass "module.prop 可读"
else
  check_fail "module.prop 不可读"
fi

subsection "安装信息"
if [ -f "$MODDIR/.install_info" ]; then
  cat "$MODDIR/.install_info" >> "$REPORT_FILE" 2>&1
  check_pass "安装信息存在"
else
  check_warn "无安装信息 (可能为旧版本)"
fi

subsection "音频栈类型"
if [ -f "$MODDIR/.audio_stack_type" ]; then
  AUDIO_STACK="$(cat "$MODDIR/.audio_stack_type" 2>/dev/null)"
  log "INFO" "检测到的音频栈: $AUDIO_STACK"
  check_pass "音频栈类型: $AUDIO_STACK"
else
  check_warn "未检测到音频栈类型"
fi

# ============================================================
# 阶段 3: 服务状态
# ============================================================
section "阶段 3: 服务状态"

subsection "杜比相关服务"
for service in \
  "vendor.dolby_sp.media.c2@1.0-service" \
  "vendor.dolby.dms.service" \
  "vendor.dolby.dms.IDms/default"; do
  if pidof "$service" >/dev/null 2>&1; then
    PID=$(pidof "$service")
    check_pass "服务运行中: $service (PID: $PID)"
  else
    check_fail "服务未运行: $service"
  fi
done

subsection "服务绑定"
run_capture "DMS AIDL 服务注册" "service list 2>/dev/null | grep -i dolby"
if service list 2>/dev/null | grep -q "vendor.dolby.dms.IDms"; then
  check_pass "DMS AIDL 服务已注册"
else
  check_fail "DMS AIDL 服务未注册"
fi

# ============================================================
# 阶段 4: 文件完整性 (含 M2 SHA256 校验)
# ============================================================
section "阶段 4: 文件完整性"

subsection "4.1 关键 .so 库存在性"
LIBS=(
  "$MODDIR/system/vendor/bin/hw/vendor.dolby_sp.media.c2@1.0-service"
  "$MODDIR/system/vendor/bin/hw/vendor.dolby.dms.service"
  "$MODDIR/system/vendor/lib64/libcodec2_soft_ac4dec_sp.so"
  "$MODDIR/system/vendor/lib64/libcodec2_soft_ddpdec_sp.so"
  "$MODDIR/system/vendor/lib64/libcodec2_soft_common.so"
  "$MODDIR/system/vendor/lib64/libcodec2_store_dolby_sp.so"
  "$MODDIR/system/vendor/lib64/libdeccfg_sp.so"
  "$MODDIR/system/vendor/lib64/libYokiScale.so"
  "$MODDIR/system/vendor/lib64/soundfx/libswdap_sp.so"
  "$MODDIR/system/vendor/lib64/soundfx/libdlbvol_sp.so"
  "$MODDIR/system/vendor/lib64/soundfx/libswgamedap_sp.so"
  "$MODDIR/system/vendor/lib64/vendor.dolby.dms-V1-ndk.so"
  "$MODDIR/system/vendor/lib64/vendor.dolby_sp.hardware.dmssp@2.0.so"
  "$MODDIR/system/vendor/lib64/libdlbdsservice_sp.so"
  "$MODDIR/system/vendor/lib64/libdapparamstorage_sp.so"
  "$MODDIR/system/vendor/lib64/libdlbpreg_sp.so"
  "$MODDIR/system/vendor/lib64/libdmshal.so"
  "$MODDIR/system/vendor/lib64/libspatializerparamstorage.so"
)
for lib in "${LIBS[@]}"; do
  if [ -f "$lib" ]; then
    SIZE=$(stat -c '%s' "$lib" 2>/dev/null)
    check_pass "$(basename "$lib") (size: $SIZE)"
  else
    check_fail "$(basename "$lib") 缺失"
  fi
done

subsection "4.2 SHA256 校验 (M2 集成, FIX C-2)"
# 🔧 FIX C-2: 集成 M2 SHA256 校验
if [ -f "$MODDIR/checksums.txt" ] && [ -f "$MODDIR/tools/verify_checksums.sh" ]; then
  log "INFO" "运行 SHA256 校验..."
  CHECK_RESULT="$(sh "$MODDIR/tools/verify_checksums.sh" "$MODDIR/checksums.txt" "$MODDIR/system/vendor/lib64" 2>&1)"
  echo "$CHECK_RESULT" >> "$REPORT_FILE"
  if echo "$CHECK_RESULT" | grep -q "通过.*0 个文件失败"; then
    check_pass "所有 .so 库 SHA256 校验通过"
  elif echo "$CHECK_RESULT" | grep -qE "(MISMATCH|MISSING)"; then
    check_fail ".so 库 SHA256 校验失败, 文件可能被篡改"
  else
    check_warn "SHA256 校验结果未明确"
  fi
else
  check_warn "未找到 checksums.txt 或 verify_checksums.sh, 跳过 SHA256 校验"
fi

subsection "4.3 配置文件"
for cfg in \
  "$MODDIR/system/vendor/etc/dolby/multimedia_dolby_dax_dflt.xml" \
  "$MODDIR/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml" \
  "$MODDIR/system/odm/etc/audio_effects.xml" \
  "$MODDIR/system/odm/etc/media_codecs_c2.xml" \
  "$MODDIR/my_product/etc/permissions/oplus.product.features_audiox.xml"; do
  if [ -f "$cfg" ]; then
    check_pass "$(basename "$cfg") 存在"
  else
    check_fail "$(basename "$cfg") 缺失"
  fi
done

# ============================================================
# 阶段 5: 运行时挂载点
# ============================================================
section "阶段 5: 运行时挂载点"

subsection "挂载状态"
run_capture "挂载点列表" "mount 2>/dev/null | grep -E 'dolby|vintf|audiox|apex-info' | head -20"
run_capture "AudioX 挂载" "ls -lZ /my_product/etc/permissions/oplus.product.features_audiox.xml 2>/dev/null"
run_capture "VINTF 挂载" "ls -lZ /vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml 2>/dev/null"
run_capture "APEX 挂载" "ls -lZ /apex/apex-info-list.xml 2>/dev/null"

# ============================================================
# 阶段 6: logcat 日志
# ============================================================
section "阶段 6: logcat 日志"

subsection "DAP 相关日志 (最近 100 行)"
log "INFO" "收集 DAP logcat 日志..."
timeout 5 logcat -d -t 100 *:S DlbDap:V vendor.dolby*:V DolbyAtmos*:V 2>/dev/null >> "$LOG_FILE"
if [ -s "$LOG_FILE" ]; then
  LINES=$(wc -l < "$LOG_FILE")
  log "INFO" "DAP logcat 已写入 (共 $LINES 行)"
else
  log "WARN" "DAP logcat 无数据"
fi

subsection "Codec2 HAL 日志 (最近 50 行)"
timeout 5 logcat -d -t 50 *:S Codec2:D C2Store:V 2>/dev/null >> "$LOG_FILE"

# ============================================================
# 阶段 7: AudioFlinger 状态
# ============================================================
section "阶段 7: AudioFlinger 状态"

subsection "已注册效果"
run_capture "dumpsys media.audio_flinger" "dumpsys media.audio_flinger 2>/dev/null | grep -A2 -i 'effect' | head -50"

subsection "DAP 效果实例"
run_capture "DAP 效果" "dumpsys media.audio_policy 2>/dev/null | grep -B1 -A3 -i 'dolby\\|dap' | head -30"

# ============================================================
# 阶段 8: 进程信息
# ============================================================
section "阶段 8: 进程信息"

run_capture "Dolby 进程" "ps -A 2>/dev/null | grep -i 'dolby\\|dms\\|c2' | grep -v grep | head -20"

# ============================================================
# 阶段 9: Tombstone/ANR
# ============================================================
section "阶段 9: Tombstone/ANR"

subsection "Tombstone"
TOMBSTONE_FILES="$(find /data/tombstones -maxdepth 1 -name 'tombstone_*' -type f 2>/dev/null | head -3)"
if [ -n "$TOMBSTONE_FILES" ]; then
  log "INFO" "最近的 tombstone 文件:"
  for tf in $TOMBSTONE_FILES; do
    if [ -r "$tf" ]; then
      log "INFO" "  $tf ($(stat -c '%s' "$tf" 2>/dev/null) bytes)"
    else
      check_warn "tombstone 文件不可读: $tf"
    fi
  done
else
  log "INFO" "无 tombstone 文件"
fi

subsection "ANR"
ANR_FILES="$(find /data/anr -name 'anr_*' -type f 2>/dev/null | head -3)"
if [ -n "$ANR_FILES" ]; then
  log "INFO" "最近的 ANR 文件:"
  for af in $ANR_FILES; do
    if [ -r "$af" ]; then
      log "INFO" "  $af ($(stat -c '%s' "$af" 2>/dev/null) bytes)"
    fi
  done
else
  log "INFO" "无 ANR 文件"
fi

# ============================================================
# 阶段 10: 总结
# ============================================================
section "阶段 10: 总结"

log "INFO" "诊断完成!"
log "INFO" "通过: $PASSES, 失败: $ERRORS, 警告: $WARNINGS"
log "INFO" "报告文件: $REPORT_FILE"
log "INFO" "原始日志: $LOG_FILE"
log "INFO" ""
log "INFO" "如需分享, 可使用以下命令:"
log "INFO" "  cat $REPORT_FILE"
log "INFO" "或打开文件管理器, 进入 $DIAG_DIR"

if [ "$ERRORS" -gt 0 ]; then
  log "INFO" ""
  log "INFO" "⚠ 检测到 $ERRORS 个问题, 建议:"
  log "INFO" "  1. 重启设备, 重新触发服务启动"
  log "INFO" "  2. 检查 KSU/Magisk 日志"
  log "INFO" "  3. 在 GitHub 提交 issue, 附上本报告"
  exit 1
else
  log "INFO" ""
  log "INFO" "✓ 未检测到严重问题"
  exit 0
fi
```

**🔧 FIX H-4 关键变更说明:**

| 项 | 修复前 | 修复后 |
|----|--------|--------|
| action.sh 中的 `clean_probe` | 存在, 删除探针残留文件 | **删除** (由 M1 service.sh 负责) |
| 报告头部 | 无 FIX 标记 | 显式标注 "本脚本不修改运行时状态 (只读)" |
| 与 M1 service.sh 关系 | 重复操作, 可能冲突 | 严格只读, 不冲突 |

**🔧 FIX H-10 关键变更说明:**

| 项 | 修复前 | 修复后 |
|----|--------|--------|
| `set -e` | 头部 `set -e`, 任一命令失败立即 exit | **删除**, 改为 `set +e` |
| 阶段失败处理 | 中止, 后续阶段不执行 | 记录错误, 继续后续阶段 |
| grep 返回值 | `grep` 找不到匹配返回 1, 触发 set -e | 配合 `set +e` + 显式 `if grep -q` 判断 |
| 退出码 | 任何错误都 exit 1 | 仅当 `ERRORS > 0` 时 exit 1, 否则 exit 0 |
| 集成 M2 SHA256 校验 | 无 | 阶段 4.2 集成 (FIX C-2) |

---

## 4. 输出格式

诊断报告格式为纯文本，包含：

```
HH:MM:SS [INFO] Dolby Atmos OnePlus folk popularization 诊断报告
HH:MM:SS [INFO] 生成时间: 2026-07-02 10:00:00
HH:MM:SS [INFO] 模块目录: /data/adb/modules/dolby_atmos_oplus_folk
...

============================================
 阶段 1: 系统信息
============================================

--- 设备信息 ---
制造商:    OnePlus
型号:      PKG110
...

--- 检查结果 ---
HH:MM:SS [PASS] 模块元数据可读
HH:MM:SS [FAIL] 服务 vendor.dolby.dms.service 未运行
HH:MM:SS [WARN] 未找到 checksums.txt
...

HH:MM:SS [INFO] 诊断完成!
HH:MM:SS [INFO] 通过: 25, 失败: 2, 警告: 1
HH:MM:SS [INFO] 报告文件: /storage/emulated/0/dolbylog/dolby_diag_20260702_100000.txt
```

---

## 5. 测试方案

### 5.1 单元测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| **🔧 FIX H-10** 阶段失败不中止 | 模拟阶段 4 失败 (缺失文件) | 阶段 5/6/7/8/9/10 仍执行 |
| **🔧 FIX H-10** grep 失败不退出 | 模拟 logcat 无匹配 | 不退出, 记录 WARN |
| **🔧 FIX H-10** 退出码正确 | 所有 PASS | 退出码 0 |
| **🔧 FIX H-10** 失败退出码 | 1 个 FAIL | 退出码 1 |
| **🔧 FIX H-4** 不删除探针文件 | 预设探针文件, 运行 action.sh | 文件保留 |
| **🔧 FIX H-4** 报告头部 FIX 标记 | 检查报告头部 | 显示 "本脚本不修改运行时状态" |
| **FIX C-2 集成** SHA256 校验存在 | 检查 reports/dolby_diag_*.txt | 含 SHA256 校验结果 |
| 报告生成 | 在 KSU Manager 中点击"操作" | 报告文件出现在 /storage/emulated/0/dolbylog/ |
| 旧报告清理 | 预先创建 15 份报告 | 仅保留最近 10 份 |

### 5.2 集成测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| 服务正常时的诊断 | 服务正常运行时执行 action.sh | 报告 0 错误 |
| DMS 故障诊断 | kill DMS 服务后执行 action.sh | 报告 1 错误, 提示重启 |
| Codec2 HAL 故障诊断 | 阻止 Codec2 启动 | 报告 1 错误, 提示重新安装 |
| **🔧 FIX C-2** SHA256 篡改检测 | 修改任一 .so 后执行 | 报告 1 错误, 显示 MISMATCH |

### 5.3 性能测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| 诊断总耗时 | 多次执行取平均值 | < 30 秒 |
| 报告大小 | 检查输出文件大小 | < 5 MB (避免占满存储) |
| logcat 收集耗时 | 检查阶段 6 耗时 | < 5 秒 (timeout 5) |

---

## 6. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-29 | 初始版本 |
| **v1.0-FIXED** | **2026-07-02** | **修复 H-4 (删除 clean_probe), H-10 (set +e + 集成 SHA256); 见 §0 变更摘要** |
