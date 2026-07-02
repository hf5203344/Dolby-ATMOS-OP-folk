# M6: 兼容性适配 — 详细设计文档 **[FIXED v1.0]**

> **版本:** v1.0-FIXED | **日期:** 2026-07-02 | **状态:** 详细设计 (含修复)
> **基础版本:** v1.0 (2026-06-29)
> **本版本变更:** 修复 [设计审查-v1.0.md](../../设计审查-v1.0.md) 中的 C-1, H-11

---

## 0. 本版本变更摘要 (v1.0-FIXED)

| # | 类型 | 章节 | 修复内容 |
|---|------|------|----------|
| C-1 | Critical | §1.3, §2 compat.sh | 删除 compat.sh 中与 M1 同名的 `detect_root_solution` 等函数, 改名为 `compat_detect_*` (调用 M1 已定义的函数) |
| H-11 | High | §2.1 detect_audio_stack | 多信号综合判断音频栈类型: 文件 + prop + dumpsys + AudioFlinger 枚举, 投票决定 |

---

## 1. 模块概述

### 1.1 职责

M6 提供跨设备、跨 Android 版本的兼容性适配层，职责包括：

- 检测设备型号、芯片平台、OEM 厂商
- 检测音频 HAL 栈类型（HIDL/AIDL）
- 检测 Root 方案
- 提供 SELinux 策略补丁
- 根据设备型号返回 DAP 参数调优配置

### 1.2 部署位置

```
$MODPATH/
└── META-INF/
    └── compat.sh                      # 兼容性函数库 (🔧 FIX C-1: 删除与 M1 重名函数)
```

`compat.sh` 由 M1 的 `customize.sh` 通过 `source` 引入。

### 1.3 🔧 FIX C-1: 与 M1 函数职责划分

**重要约束 (C-1):** M6 的 `compat.sh` **不得重新定义与 M1 customize.sh 同名的函数**. M6 仅提供 M1 缺失的辅助函数.

| 函数 | 定义位置 | 提供者 |
|------|----------|--------|
| `detect_root_solution` | customize.sh | **M1** (M6 不得重定义) |
| `detect_android_version` | customize.sh | **M1** (M6 不得重定义) |
| `detect_platform` | customize.sh | **M1** (M6 不得重定义) |
| `detect_device` | customize.sh | **M1** (M6 不得重定义) |
| `detect_architecture` | customize.sh | **M1** (M6 不得重定义) |
| `detect_audio_stack` | customize.sh | **M1** (M6 不得重定义) |
| `compat_detect_audio_stack_v2` | META-INF/compat.sh | **M6** (🔧 FIX H-11, 增强版) |
| `get_device_dap_params` | META-INF/compat.sh | **M6** (设备参数) |
| `apply_sepolicy_patches` | META-INF/compat.sh | **M6** (SELinux 补丁) |
| `select_dap_control_path` | META-INF/compat.sh | **M6** (DAP 控制路径选择) |
| `pre_install_check` | META-INF/compat.sh | **M6** (安装前检查) |

**调用约定:**
- M1 的 `customize.sh` 在文件顶部 `source` 引入 M6 的 `compat.sh`
- M1 的 `detect_*` 系列函数**先于 source 定义**, 不会被 M6 覆盖
- M6 提供 `compat_*` 前缀的辅助函数, 与 M1 互不冲突

---

## 2. `META-INF/compat.sh` — 兼容性函数库 **[FIXED C-1, H-11]**

```bash
#!/system/bin/sh
# ============================================================
# M6: compat.sh — 兼容性函数库
# 被 M1 customize.sh source 引入
#
# 🔧 FIX C-1: 不得重新定义 M1 已定义的 detect_* 函数
#             M6 仅提供 compat_* 前缀的辅助函数
# 🔧 FIX H-11: compat_detect_audio_stack_v2 使用多信号综合判断
# ============================================================

# ============================================================
# 1. 🔧 FIX H-11: 多信号音频栈检测
# ============================================================

# 单一信号检测 (返回 0 表示是 AIDL, 1 表示是 HIDL)
_signal_aidl_file() {
  # 信号 1: AIDL VINTF manifest 存在
  [ -f "/odm/etc/vintf/manifest/dvs-aidl-service.xml" ] && return 0
  [ -f "/vendor/etc/vintf/manifest/dvs-aidl-service.xml" ] && return 0
  return 1
}

_signal_aidl_lib() {
  # 信号 2: AIDL 音频配置库存在
  [ -f "/vendor/lib64/libaconfig_storage_read_api_cc.so" ] && return 0
  [ -f "/vendor/lib64/libaudiohal@aidl.so" ] && return 0
  return 1
}

_signal_aidl_prop() {
  # 信号 3: 系统属性暗示 AIDL
  case "$(getprop ro.audio.hal.implementation 2>/dev/null)" in
    *aidl*|*AIDL*) return 0 ;;
  esac
  case "$(getprop ro.vendor.audio.hal.implementation 2>/dev/null)" in
    *aidl*|*AIDL*) return 0 ;;
  esac
  return 1
}

_signal_aidl_dumpsys() {
  # 信号 4: dumpsys media.audio_flinger 显示 AIDL 服务
  if dumpsys media.audio_flinger 2>/dev/null | grep -q "IAudioFlinger.*AIDL"; then
    return 0
  fi
  if dumpsys media.audio_flinger 2>/dev/null | grep -qE "AudioFlinger.*Aidl"; then
    return 0
  fi
  return 1
}

_signal_hidl_vintf() {
  # 信号 5: HIDL VINTF manifest 存在
  [ -f "/vendor/etc/vintf/manifest/android.hardware.audio@5.0-service.xml" ] && return 0
  [ -f "/vendor/etc/vintf/manifest/android.hardware.audio@6.0-service.xml" ] && return 0
  [ -f "/vendor/etc/vintf/manifest/android.hardware.audio@7.0-service.xml" ] && return 0
  return 1
}

_signal_hidl_prop() {
  # 信号 6: 系统属性暗示 HIDL
  case "$(getprop ro.audio.hal.implementation 2>/dev/null)" in
    *hidl*|*HIDL*) return 0 ;;
  esac
  case "$(getprop ro.vendor.audio.hal.implementation 2>/dev/null)" in
    *hidl*|*HIDL*) return 0 ;;
  esac
  return 1
}

# 综合判断
compat_detect_audio_stack_v2() {
  local aidl_score=0
  local hidl_score=0
  local signals=""

  # 收集 AIDL 信号
  _signal_aidl_file && { aidl_score=$((aidl_score + 1)); signals="$signals file:AIDL "; }
  _signal_aidl_lib && { aidl_score=$((aidl_score + 1)); signals="$signals lib:AIDL "; }
  _signal_aidl_prop && { aidl_score=$((aidl_score + 1)); signals="$signals prop:AIDL "; }
  _signal_aidl_dumpsys && { aidl_score=$((aidl_score + 1)); signals="$signals dumpsys:AIDL "; }

  # 收集 HIDL 信号
  _signal_hidl_vintf && { hidl_score=$((hidl_score + 1)); signals="$signals file:HIDL "; }
  _signal_hidl_prop && { hidl_score=$((hidl_score + 1)); signals="$signals prop:HIDL "; }

  ui_print "  音频栈检测信号:$signals"
  ui_print "  AIDL 评分: $aidl_score, HIDL 评分: $hidl_score"

  # 决策
  if [ "$aidl_score" -gt "$hidl_score" ]; then
    echo "AIDL"
    return 0
  elif [ "$hidl_score" -gt "$aidl_score" ]; then
    echo "HIDL"
    return 0
  elif [ "$aidl_score" -gt 0 ] && [ "$hidl_score" -gt 0 ]; then
    # 评分相同但都有信号, 退化为使用 prop
    if [ "$(getprop ro.audio.hal.implementation 2>/dev/null)" = "" ]; then
      echo "MIXED"
    else
      echo "$(getprop ro.audio.hal.implementation 2>/dev/null)"
    fi
    return 0
  else
    # 都无信号, 尝试其他检测方法
    if dumpsys media.audio_flinger 2>/dev/null | head -20 | grep -q "aidl"; then
      echo "AIDL"
    else
      echo "UNKNOWN"
    fi
    return 0
  fi
}

# ============================================================
# 2. 设备参数查询
# ============================================================

# 🔧 FIX: 返回 key=value 格式, 便于调用方解析
# 格式: param1=value1\nparam2=value2\n...
compat_get_device_dap_params() {
  local DEVICE_NAME="$1"
  local PARAMS=""

  case "$DEVICE_NAME" in
    "PKG110")
      PARAMS="device_name=OnePlus ACE5
chipset=sm8650
platform_family=sm8650
dap_enabled_default=true
surround_virtualizer_default=50
dialog_enhancer_default=60
bass_enhancer_default=50
bt_max_sampling_rate=96000
support_ac4=true
support_eac3_joc=true
dms_aidl_compatible=true"
      ;;
    "PKG120")
      PARAMS="device_name=OnePlus ACE5 Pro
chipset=sm8750
platform_family=sm8750
dap_enabled_default=true
surround_virtualizer_default=55
dialog_enhancer_default=60
bass_enhancer_default=55
bt_max_sampling_rate=96000
support_ac4=true
support_eac3_joc=true
dms_aidl_compatible=true"
      ;;
    "PKG130")
      PARAMS="device_name=OnePlus ACE5 Pro Max
chipset=sm8750
platform_family=sm8750
dap_enabled_default=true
surround_virtualizer_default=55
dialog_enhancer_default=60
bass_enhancer_default=55
bt_max_sampling_rate=96000
support_ac4=true
support_eac3_joc=true
dms_aidl_compatible=true"
      ;;
    *)
      PARAMS="device_name=Unknown
chipset=unknown
platform_family=unknown
dap_enabled_default=true
surround_virtualizer_default=50
dialog_enhancer_default=50
bass_enhancer_default=50
bt_max_sampling_rate=48000
support_ac4=false
support_eac3_joc=false
dms_aidl_compatible=false"
      ui_print "  警告: 未知设备 $DEVICE_NAME, 使用默认参数"
      ;;
  esac

  echo "$PARAMS"
}

# 解析参数 (调用方使用)
compat_get_param() {
  local params="$1"
  local key="$2"
  echo "$params" | grep "^$key=" | head -1 | cut -d= -f2-
}

# ============================================================
# 3. SELinux 策略补丁
# ============================================================

compat_apply_sepolicy_patches() {
  local MODDIR="$1"
  local applied=0

  ui_print "  应用 SELinux 策略补丁..."

  # 补丁 1: 允许 DMS 服务访问 audioserver
  if magiskpolicy --live "allow vendor_dolby_dms_service audioserver:binder { call transfer }" 2>/dev/null; then
    applied=$((applied + 1))
  fi

  # 补丁 2: 允许 Codec2 HAL 服务访问 audioserver
  if magiskpolicy --live "allow vendor_dolby_codec2 audioserver:binder { call transfer }" 2>/dev/null; then
    applied=$((applied + 1))
  fi

  # 补丁 3: 允许 DAP 库被 audioserver 加载
  if magiskpolicy --live "allow audioserver vendor_file:file { read execute open }" 2>/dev/null; then
    applied=$((applied + 1))
  fi

  # 补丁 4: 允许 mediaserver 访问 Dolby 服务
  if magiskpolicy --live "allow mediaserver vendor_dolby_dms_service:service_manager find" 2>/dev/null; then
    applied=$((applied + 1))
  fi

  ui_print "  SELinux 策略: 已应用 $applied 个补丁"

  # 记录已应用补丁
  echo "sepolicy_patches_applied=$applied" >> "$MODDIR/.sepolicy_state" 2>/dev/null
}

# ============================================================
# 4. DAP 控制路径选择
# ============================================================

compat_select_dap_control_path() {
  local AUDIO_STACK="$1"
  local DEVICE_NAME="$2"
  local path=""

  case "$AUDIO_STACK" in
    "AIDL")
      # AIDL 音频栈, 使用 AudioEffect API + DMS AIDL
      path="audio_effect_aidl"
      ;;
    "HIDL")
      # HIDL 音频栈, 使用 AudioEffect API + 旧版 HIDL
      path="audio_effect_hidl"
      ;;
    "MIXED")
      # 混合, 优先尝试 AIDL, 失败时回退到 HIDL
      path="audio_effect_aidl_with_fallback"
      ;;
    *)
      # 未知, 尝试 AudioEffect 通用路径
      path="audio_effect_universal"
      ;;
  esac

  echo "$path"
}

# ============================================================
# 5. 安装前检查
# ============================================================

compat_pre_install_check() {
  local errors=""
  local warnings=""

  # 检查 1: 是否已安装其他 Dolby 模块
  for mod_dir in /data/adb/modules/*/; do
    [ -d "$mod_dir" ] || continue
    MOD_ID="$(grep '^id=' "$mod_dir/module.prop" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')"
    case "$MOD_ID" in
      dolby*|atmos*|dax*|daX*)
        if [ "$MOD_ID" != "dolby_atmos_oplus_folk" ]; then
          errors="$errors 已安装冲突模块: $MOD_ID ($mod_dir);"
        fi
        ;;
    esac
  done

  # 检查 2: system 完整性
  if [ ! -d "/system" ]; then
    errors="$errors /system 目录不存在;"
  fi

  # 检查 3: 必需的系统命令
  for cmd in mount getprop; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      errors="$errors 缺少命令: $cmd;"
    fi
  done

  # 检查 4: 推荐的命令
  for cmd in magiskpolicy; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warnings="$warnings 缺少推荐命令: $cmd (SELinux 补丁可能无法应用);"
    fi
  done

  # 输出
  if [ -n "$errors" ]; then
    ui_print "  安装前检查发现错误:$errors"
    return 1
  fi

  if [ -n "$warnings" ]; then
    ui_print "  安装前检查发现警告:$warnings"
  fi

  return 0
}

# ============================================================
# 6. 设备 DAP 参数读取 (从模块预设的 XML)
# ============================================================

compat_get_dap_params_for_device() {
  local DEVICE_NAME="$1"
  local MODDIR="$2"
  local DAP_PARAMS_XML=""

  # 优先从模块内多设备 XML 读取
  case "$DEVICE_NAME" in
    "PKG110"|"PKG120"|"PKG130")
      DAP_PARAMS_XML="$MODDIR/system/vendor/etc/dolby/multimedia_dolby_dax_dflt.xml"
      ;;
    *)
      DAP_PARAMS_XML="$MODDIR/system/vendor/etc/dolby/multimedia_dolby_dax_dflt.xml"
      ;;
  esac

  if [ -f "$DAP_PARAMS_XML" ]; then
    echo "$DAP_PARAMS_XML"
    return 0
  fi
  return 1
}

# ============================================================
# 7. 🔧 FIX C-1: 验证 M1 函数未被重定义
# ============================================================
# 这是一个调试辅助函数, 在 M1 customize.sh source compat.sh 后调用
# 确保 M1 的 detect_* 系列函数仍然可用

compat_verify_m1_functions() {
  local missing=""

  for func in detect_root_solution detect_android_version detect_platform \
              detect_device detect_architecture detect_audio_stack; do
    if ! type "$func" >/dev/null 2>&1; then
      missing="$missing $func"
    fi
  done

  if [ -n "$missing" ]; then
    ui_print "  ⚠ 警告: M1 缺少函数:$missing"
    return 1
  fi

  return 0
}
```

**🔧 FIX C-1 验证清单:**

| 检查项 | 状态 |
|--------|------|
| compat.sh 不定义 `detect_root_solution` | ✅ |
| compat.sh 不定义 `detect_android_version` | ✅ |
| compat.sh 不定义 `detect_platform` | ✅ |
| compat.sh 不定义 `detect_device` | ✅ |
| compat.sh 不定义 `detect_architecture` | ✅ |
| compat.sh 不定义 `detect_audio_stack` | ✅ |
| 改用 `compat_*` 前缀避免冲突 | ✅ |
| 提供 `compat_verify_m1_functions` 调试 | ✅ |

**🔧 FIX H-11 关键变更说明:**

| 维度 | 修复前 | 修复后 |
|------|--------|--------|
| 信号数量 | 1 个文件存在性 | **6 个信号**: 文件、库、prop、dumpsys、HIDL prop |
| 决策方式 | 单一文件 → 决定类型 | **多信号投票**: AIDL 分数 vs HIDL 分数 |
| 边界处理 | 无 | 处理"信号都无"和"信号都同分"的情况 |
| 调试能力 | 无 | 输出所有信号和分数, 便于故障排查 |
| 函数命名 | `detect_audio_stack` (冲突) | `compat_detect_audio_stack_v2` (无冲突) |
| M1 中的 `detect_audio_stack` | 与 M6 冲突 | **保留原 M1 版本** (简单, 用于 quick check) |
| 高级检测 | 无 | M6 的 `compat_detect_audio_stack_v2` 用于深入检测 |
| 调用方式 | M1 直接 echo | M1 可调用 `compat_detect_audio_stack_v2` 覆盖 |

---

## 3. 调用流程

### 3.1 M1 customize.sh 的 source 流程

```
M1 customize.sh 执行
    │
    ├─[1]─→ M1 定义 detect_root_solution, detect_android_version,
    │        detect_platform, detect_device, detect_architecture, detect_audio_stack
    │
    ├─[2]─→ source "$MODPATH/META-INF/compat.sh"
    │        (M6 提供 compat_* 前缀的函数, 不重定义 M1 函数)
    │
    ├─[3]─→ compat_verify_m1_functions  # 调试用, 验证 M1 函数仍在
    │
    ├─[4]─→ detect_root_solution  # 调用 M1 的版本
    │        detect_android_version
    │        detect_platform
    │        detect_device
    │        detect_architecture
    │        detect_audio_stack  # M1 简单版
    │
    └─[5]─→ (高级检测) compat_detect_audio_stack_v2  # 必要时调用 M6 增强版
```

### 3.2 设备参数决策流程

```
detect_device (M1) → DEVICE_NAME=PKG110
    │
    └─→ compat_get_device_dap_params "$DEVICE_NAME"
            │
            └─→ 返回 key=value 格式参数表
                    │
                    └─→ compat_get_param "$params" "dms_aidl_compatible"
                            → true (用于决定 DAP 控制路径)
```

---

## 4. 模块间接口

### 4.1 对 M1 的接口

| 接口 | 说明 |
|------|------|
| `source` | M1 customize.sh 在文件顶部 source M6 compat.sh |
| `detect_*` 函数 | M1 调用自身定义的函数 (M6 不得重定义) |
| `compat_*` 函数 | M1 在需要高级检测时调用 |

### 4.2 对 M3 的接口

| 接口 | 说明 |
|------|------|
| `compat_get_device_dap_params` | M3 在生成 `multimedia_dolby_dax_dflt.xml` 时使用 |
| `compat_select_dap_control_path` | M3 选择 DAP 控制路径 (AIDL/HIDL/MIXED) |
| `compat_apply_sepolicy_patches` | M3 在 service.sh 启动 DMS 前调用 |

### 4.3 对 M5 的接口

| 接口 | 说明 |
|------|------|
| `compat_verify_m1_functions` | M5 在诊断报告中包含此验证结果 |

---

## 5. 测试方案

### 5.1 单元测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| **🔧 FIX C-1** 加载顺序验证 | M1 先定义函数, 后 source compat.sh | 6 个 M1 函数均可调用 |
| **🔧 FIX C-1** 兼容性函数验证 | source compat.sh 后 type compat_* | 全部 8 个 compat_* 函数存在 |
| **🔧 FIX C-1** M6 未定义 M1 函数 | grep M6 compat.sh 中的 M1 函数名 | 0 处匹配 |
| **🔧 FIX H-11** 多信号投票 | 设置不同信号组合, 调用 compat_detect_audio_stack_v2 | 评分高的胜出 |
| **🔧 FIX H-11** AIDL 信号全有 | 模拟所有 AIDL 信号 | 返回 AIDL |
| **🔧 FIX H-11** HIDL 信号全有 | 模拟所有 HIDL 信号 | 返回 HIDL |
| **🔧 FIX H-11** 混合信号 | AIDL=2, HIDL=2 | 退化为 prop 读取 |
| **🔧 FIX H-11** 无信号 | 所有信号都缺失 | 返回 UNKNOWN |
| compat_get_device_dap_params | 传入 PKG110/PKG120/PKG130/Unknown | 返回对应的 key=value 表 |
| compat_get_param | 解析 dap_enabled_default | 提取出值 |
| compat_select_dap_control_path | 传入 AIDL/HIDL/MIXED/UNKNOWN | 返回对应路径 |
| compat_pre_install_check | 在干净环境/有冲突模块环境 | 返回 0/1, 错误信息正确 |
| compat_apply_sepolicy_patches | 在测试环境运行 | 返回已应用数量, 写入 .sepolicy_state |

### 5.2 集成测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| **🔧 FIX C-1** M1 + M6 共存 | 安装完整模块 (M1 + M6) | install.sh 不报函数冲突 |
| **🔧 FIX C-1** M6 单独使用 | 模拟仅 source compat.sh, 不加载 M1 | M1 函数未定义, 报告 WARN |
| **🔧 FIX H-11** PKG110 检测 | 在 ACE5 上运行 | AIDL 评分 >= 3, 返回 AIDL |
| **🔧 FIX H-11** 一加 12 (假设 HIDL) | 模拟 HIDL 环境 | HIDL 评分 >= 2, 返回 HIDL |
| **🔧 FIX H-11** 未知设备 | 模拟完全无信号环境 | 返回 UNKNOWN, 不崩溃 |
| SELinux 补丁 | 在 Magisk 环境运行 compat_apply_sepolicy_patches | 已应用数量 >= 3 |

### 5.3 多机型测试矩阵

| 设备 | 芯片 | 音频栈 | 预期结果 |
|------|------|--------|----------|
| OnePlus ACE5 (PKG110) | sm8650 | AIDL | AIDL 评分 4, HIDL 评分 0 → AIDL |
| OnePlus ACE5 Pro (PKG120) | sm8750 | AIDL | AIDL 评分 4, HIDL 评分 0 → AIDL |
| OnePlus 12 (CPH2583) | sm8650 | HIDL | AIDL 评分 0, HIDL 评分 2 → HIDL |
| 模拟无信号环境 | - | - | 返回 UNKNOWN, UI 警告 |
| 模拟 MIXED 环境 | - | AIDL+HIDL 各 2 分 | 退化为 prop 读取 |

---

## 6. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-29 | 初始版本 |
| **v1.0-FIXED** | **2026-07-02** | **修复 C-1 (删除与 M1 重名函数), H-11 (多信号综合判断); 见 §0 变更摘要** |
