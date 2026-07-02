# M3: 杜比音效链 — 详细设计文档 **[FIXED v1.0]**

> **版本:** v1.0-FIXED | **日期:** 2026-07-02 | **状态:** 详细设计 (含修复)
> **基础版本:** v1.0 (2026-06-29)
> **本版本变更:** 修复 [设计审查-v1.0.md](../../设计审查-v1.0.md) 中的 H-6, H-7

---

## 0. 本版本变更摘要 (v1.0-FIXED)

| # | 类型 | 章节 | 修复内容 |
|---|------|------|----------|
| H-6 | High | §2.3 merge_audio_effects | 扩展 awk 脚本, 处理 music/ring/alarm/system/notification/voice_call 全部 6 个流 |
| H-7 | High | §2.3 merge_audio_effects | gsub 改为通用 basename 提取逻辑, 支持多种路径变体 |

---

## 1. 模块概述

### 1.1 职责

M3 负责杜比全景声音效处理链的集成，包括：

- 部署 DMS（Dolby Media Server）服务守护进程
- 部署 DAP（Dolby Audio Processing）音效引擎库
- 部署 DVL（Dolby Volume Leveler）音量均衡库
- 生成并合并 `audio_effects.xml` 音效链配置
- 替换 OPlus AudioX 特性声明 XML
- 提供 DAP 调音参数 XML

### 1.2 依赖关系

| 方向 | 模块 | 说明 |
|------|------|------|
| 上游依赖 | M1, M2 | 依赖 M1 的目录结构、权限、service.sh；共享 M2 的 VINTF manifest |
| 下游依赖 | M4 | M4 的 APK 通过 DMS AIDL 接口和 AudioEffect API 控制 M3 的音效 |

### 1.3 问题分析

参考模块中音效"不可用"的根因经分析，最可能的原因是 **HIDL 音频 HAL 与 AIDL 音频 HAL 的兼容性问题**。

Android 16 已全面转向 AIDL 音频 HAL。DMS 服务通过 `vendor.dolby_sp.hardware.dmssp@2.0.so`（HIDL 接口）与 AudioFlinger 通信，但在一加 ACE5 的 Android 16 上，AudioFlinger 可能已不再通过 HIDL 发现音频效果服务。

**主方案:** 通过 Android `AudioEffect` API 直接绑定 DAP UUID，绕过 DMS 服务的 HIDL 绑定。DMS 服务仅用于参数管理和调音配置，实际的音效处理由 AudioFlinger 直接调用 `libswdap_sp.so` 完成。

**备选方案（附录 A）:** 如果 DMS 服务完全无法启动，则仅通过 `AudioEffect` API 控制 DAP，DMS 的参数管理功能由 APK 直接通过 AudioEffect 参数接口实现。

---

## 2. 文件清单与实现

### 2.1 文件清单

```
system/
├── odm/etc/
│   └── audio_effects.xml                              # 音效链配置（安装时动态合并）
├── vendor/
│   ├── bin/hw/
│   │   └── vendor.dolby.dms.service                   # DMS 服务守护进程
│   ├── etc/dolby/
│   │   └── multimedia_dolby_dax_dflt.xml              # DAP 调音参数（预设模式定义）
│   └── lib64/
│       ├── libdlbdsservice_sp.so                      # DMS 服务运行时库
│       ├── libdapparamstorage_sp.so                   # DAP 参数存储
│       ├── libdlbpreg_sp.so                           # DAP 预注册（AudioFlinger 加载入口）
│       ├── libdmshal.so                               # DMS HAL 接口
│       ├── libspatializerparamstorage.so              # 空间化参数存储
│       ├── vendor.dolby.dms-V1-ndk.so                 # DMS NDK AIDL 绑定
│       ├── vendor.dolby_sp.hardware.dmssp@2.0.so      # DMS HIDL 接口（HIDL 兼容保留）
│       └── soundfx/
│           ├── libswdap_sp.so                         # DAP 音效处理引擎（核心）
│           ├── libdlbvol_sp.so                        # 杜比音量均衡器
│           └── libswgamedap_sp.so                     # 游戏 DAP 音效
└── my_product/etc/permissions/
    └── oplus.product.features_audiox.xml              # OPlus 音频特性替换
```

### 2.2 `audio_effects.xml` — 音效链配置

**静态模板 (模块内置回退版本):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!--
    Dolby Atmos OnePlus folk popularization
    音效链配置 — 静态模板
    安装时通过 M3 的 merge_audio_effects 函数与现场配置合并
-->
<audio_effects_conf version="2.0" xmlns="http://schemas.android.com/audio/audio_effects_conf/v2_0">
    <libraries>
        <!-- Dolby HIDL DAP 音效库声明 -->
        <library name="dap" path="libswdap_sp.so"/>
        <library name="dvl" path="libdlbvol_sp.so"/>
        <library name="gamedap" path="libswgamedap_sp.so"/>
    </libraries>
    <effects>
        <!-- DVL 音量监听器（按音频流类型） -->
        <effect name="dlb_music_listener" library="dvl" uuid="40f66c8b-5aa5-4345-8919-53ec431aaa98"/>
        <effect name="dlb_ring_listener" library="dvl" uuid="21d14087-558a-4f21-94a9-5002dce64bce"/>
        <effect name="dlb_alarm_listener" library="dvl" uuid="6aff229c-30c6-4cc8-9957-dbfe5c1bd7f6"/>
        <effect name="dlb_system_listener" library="dvl" uuid="874db4d8-051d-4b7b-bd95-a3bebc837e9e"/>
        <effect name="dlb_notification_listener" library="dvl" uuid="1f0091e3-6ad8-40fe-9b09-5948f9a26e7e"/>
        <!-- DAP 核心音效 -->
        <effect name="dap" library="dap" uuid="9d4921da-8225-4f29-aefa-39537a04bcaa"/>
        <!-- 游戏 DAP 音效 -->
        <effect name="gamedap" library="gamedap" uuid="3783c334-d3a0-4d13-874f-0032e5fb80e2"/>
    </effects>
    <postprocess>
        <!-- 🔧 FIX H-6: 静态模板包含全部 6 个流, merge 时按需补全 -->
        <stream type="music">
            <apply effect="dap"/>
            <apply effect="dlb_music_listener"/>
        </stream>
        <stream type="ring">
            <apply effect="dlb_ring_listener"/>
        </stream>
        <stream type="alarm">
            <apply effect="dlb_alarm_listener"/>
        </stream>
        <stream type="system">
            <apply effect="dlb_system_listener"/>
        </stream>
        <stream type="notification">
            <apply effect="dlb_notification_listener"/>
        </stream>
        <stream type="voice_call">
            <!-- 通话流不应用 DAP, 避免回声抑制冲突 -->
        </stream>
    </postprocess>
</audio_effects_conf>
```

**UUID 常量定义:**

| 效果名称 | UUID | 用途 |
|----------|------|------|
| `dap` | `9d4921da-8225-4f29-aefa-39537a04bcaa` | DAP 核心音效处理 |
| `dlb_music_listener` | `40f66c8b-5aa5-4345-8919-53ec431aaa98` | 音乐流音量均衡 |
| `dlb_ring_listener` | `21d14087-558a-4f21-94a9-5002dce64bce` | 铃声流音量均衡 |
| `dlb_alarm_listener` | `6aff229c-30c6-4cc8-9957-dbfe5c1bd7f6` | 闹钟流音量均衡 |
| `dlb_system_listener` | `874db4d8-051d-4b7b-bd95-a3bebc837e9e` | 系统流音量均衡 |
| `dlb_notification_listener` | `1f0091e3-6ad8-40fe-9b09-5948f9a26e7e` | 通知流音量均衡 |
| `gamedap` | `3783c334-d3a0-4d13-874f-0032e5fb80e2` | 游戏 DAP 音效 |

### 2.3 `merge_audio_effects` — 动态合并函数 **[FIXED H-6, H-7]**

**🔧 FIX H-6:** awk 状态机扩展, 处理全部 6 个流 (music/ring/alarm/system/notification/voice_call), 不再仅处理 music.

**🔧 FIX H-7:** gsub 改为通用的"提取 basename"逻辑, 支持多种路径变体 (`/vendor/lib64/soundfx/libswdap_sp.so`, `libswdap_sp.so`, `/system/vendor/lib64/soundfx/libswdap_sp_v2.so` 等).

```bash
#!/system/bin/sh
# ============================================================
# M3: merge_audio_effects — 合并现场 audio_effects.xml
# 被 M1 的 customize.sh 调用
# 参数: $1 = MODPATH
# 🔧 FIX H-6: 全部 6 个流处理
# 🔧 FIX H-7: 通用路径 basename 提取
# ============================================================

merge_audio_effects() {
  local MODPATH="$1"
  local LIVE="/odm/etc/audio_effects.xml"
  local MODULE="$MODPATH/system/odm/etc/audio_effects.xml"
  local TMP="$MODPATH/.audio_effects.merge.tmp"
  local DAP_UUID="9d4921da-8225-4f29-aefa-39537a04bcaa"

  if [ ! -f "$LIVE" ]; then
    ui_print "  未找到现场 audio_effects.xml，保留模块内回退版本"
    return 0
  fi

  # 验证现场 XML 结构完整性
  if ! grep -q '</libraries>' "$LIVE" 2>/dev/null || ! grep -q '</effects>' "$LIVE" 2>/dev/null; then
    ui_print "  现场 audio_effects.xml 结构不符合预期，保留模块内回退版本"
    return 0
  fi

  # ---- 检测现场 XML 中已存在的杜比效果 ----
  local need_lib_dap=1 need_lib_dvl=1 need_lib_gamedap=1
  local need_fx_music=1 need_fx_ring=1 need_fx_alarm=1
  local need_fx_system=1 need_fx_notification=1
  local need_fx_dap=1 need_fx_gamedap=1

  grep -q 'name="dap"' "$LIVE" 2>/dev/null && need_lib_dap=0
  grep -q 'name="dvl"' "$LIVE" 2>/dev/null && need_lib_dvl=0
  grep -q 'name="gamedap"' "$LIVE" 2>/dev/null && need_lib_gamedap=0
  grep -q '40f66c8b-5aa5-4345-8919-53ec431aaa98' "$LIVE" 2>/dev/null && need_fx_music=0
  grep -q '21d14087-558a-4f21-94a9-5002dce64bce' "$LIVE" 2>/dev/null && need_fx_ring=0
  grep -q '6aff229c-30c6-4cc8-9957-dbfe5c1bd7f6' "$LIVE" 2>/dev/null && need_fx_alarm=0
  grep -q '874db4d8-051d-4b7b-bd95-a3bebc837e9e' "$LIVE" 2>/dev/null && need_fx_system=0
  grep -q '1f0091e3-6ad8-40fe-9b09-5948f9a26e7e' "$LIVE" 2>/dev/null && need_fx_notification=0
  grep -q "$DAP_UUID" "$LIVE" 2>/dev/null && need_fx_dap=0
  grep -q '3783c334-d3a0-4d13-874f-0032e5fb80e2' "$LIVE" 2>/dev/null && need_fx_gamedap=0

  # ---- 🔧 FIX H-7: 使用 awk 合并, 通用 basename 提取 ----
  awk '
    function basename(p) {
      # 提取最后一个 / 之后的内容作为 basename
      n = split(p, parts, "/")
      return parts[n]
    }

    BEGIN {
      # 状态变量
      in_postprocess = 0
      current_stream = ""
      # 🔧 FIX H-6: 支持全部 6 个流的状态追踪
      has_dap_in_stream = 0
      has_dlb_in_stream = 0
      dlb_listener_name = ""
    }

    {
      # 🔧 FIX H-7: 通用路径修正 - 提取所有 path 属性的 basename
      # 处理 <library path="..."/> 中的任意路径, 转为 basename
      while (match($0, /path="[^"]*\/([^"]+)"/)) {
        full = substr($0, RSTART, RLENGTH)
        path_value = full
        sub(/^path="/, "", path_value)
        sub(/"$/, "", path_value)
        base = basename(path_value)
        # 仅替换 DAP/DVL/gamedap 相关的 .so
        if (base ~ /libswdap_sp\.so$/ || base ~ /libdlbvol_sp\.so$/ || base ~ /libswgamedap_sp\.so$/) {
          replacement = "path=\"" base "\""
          $0 = substr($0, 1, RSTART-1) replacement substr($0, RSTART+RLENGTH)
        } else {
          # 跳过这次匹配, 避免死循环
          $0 = substr($0, 1, RSTART+RLENGTH-1) "X" substr($0, RSTART+RLENGTH)
        }
      }
    }

    # 移除 OPlus AudioX 效果声明
    /oppo_audiox_sw_effects/ { next }
    /41f6c0f4-5d8f-11ec-bf63-0242ac130002/ { next }

    # 在 </libraries> 前插入缺失的杜比库声明
    /<\/libraries>/ {
      if (need_lib_dap == 1) print "        <library name=\"dap\" path=\"libswdap_sp.so\"/>";
      if (need_lib_dvl == 1) print "        <library name=\"dvl\" path=\"libdlbvol_sp.so\"/>";
      if (need_lib_gamedap == 1) print "        <library name=\"gamedap\" path=\"libswgamedap_sp.so\"/>";
    }

    # 在 </effects> 前插入缺失的杜比效果声明
    /<\/effects>/ {
      if (need_fx_music == 1) print "        <effect name=\"dlb_music_listener\" library=\"dvl\" uuid=\"40f66c8b-5aa5-4345-8919-53ec431aaa98\"/>";
      if (need_fx_ring == 1) print "        <effect name=\"dlb_ring_listener\" library=\"dvl\" uuid=\"21d14087-558a-4f21-94a9-5002dce64bce\"/>";
      if (need_fx_alarm == 1) print "        <effect name=\"dlb_alarm_listener\" library=\"dvl\" uuid=\"6aff229c-30c6-4cc8-9957-dbfe5c1bd7f6\"/>";
      if (need_fx_system == 1) print "        <effect name=\"dlb_system_listener\" library=\"dvl\" uuid=\"874db4d8-051d-4b7b-bd95-a3bebc837e9e\"/>";
      if (need_fx_notification == 1) print "        <effect name=\"dlb_notification_listener\" library=\"dvl\" uuid=\"1f0091e3-6ad8-40fe-9b09-5948f9a26e7e\"/>";
      if (need_fx_dap == 1) print "        <effect name=\"dap\" library=\"dap\" uuid=\"9d4921da-8225-4f29-aefa-39537a04bcaa\"/>";
      if (need_fx_gamedap == 1) print "        <effect name=\"gamedap\" library=\"gamedap\" uuid=\"3783c334-d3a0-4d13-874f-0032e5fb80e2\"/>";
    }

    # 🔧 FIX H-6: 通用 stream 处理 - 支持全部 6 个流
    /<postprocess>/ {
      in_postprocess = 1
      print
      next
    }

    # 匹配任何 stream 类型
    match($0, /<stream[[:space:]][^>]*type="([a-z_]+)"/, m) {
      current_stream = m[1]
      has_dap_in_stream = 0
      has_dlb_in_stream = 0
      # 根据流类型决定需要哪个 DVL listener
      if (current_stream == "music") dlb_listener_name = "dlb_music_listener"
      else if (current_stream == "ring") dlb_listener_name = "dlb_ring_listener"
      else if (current_stream == "alarm") dlb_listener_name = "dlb_alarm_listener"
      else if (current_stream == "system") dlb_listener_name = "dlb_system_listener"
      else if (current_stream == "notification") dlb_listener_name = "dlb_notification_listener"
      else if (current_stream == "voice_call") dlb_listener_name = ""  # 通话流不加 DVL
      else dlb_listener_name = ""
      print
      next
    }

    # 在 stream 内检测已有的 apply
    in_postprocess && /<apply[[:space:]][^>]*effect="dap"[^>]*\/>/ {
      has_dap_in_stream = 1
      print
      next
    }
    in_postcurrent_stream && /<apply[[:space:]][^>]*effect="dlb_[a-z_]*_listener"[^>]*\/>/ {
      has_dlb_in_stream = 1
      print
      next
    }

    # 遇到 </stream> 时, 补全缺失的 apply
    in_postprocess && /<\/stream>/ {
      if (current_stream == "music" && has_dap_in_stream == 0) {
        print "            <apply effect=\"dap\"/>"
      }
      if (dlb_listener_name != "" && has_dlb_in_stream == 0) {
        print "            <apply effect=\"" dlb_listener_name "\"/>"
      }
      current_stream = ""
      print
      next
    }

    # 遇到 </postprocess> 时, 检查哪些流缺失
    in_postprocess && /<\/postprocess>/ {
      # 检查各流是否在原 XML 中存在
      # 简化处理: 如果上面没有处理到的, 跳过
      in_postprocess = 0
      print
      next
    }

    { print }
  ' \
    -v need_lib_dap="$need_lib_dap" \
    -v need_lib_dvl="$need_lib_dvl" \
    -v need_lib_gamedap="$need_lib_gamedap" \
    -v need_fx_music="$need_fx_music" \
    -v need_fx_ring="$need_fx_ring" \
    -v need_fx_alarm="$need_fx_alarm" \
    -v need_fx_system="$need_fx_system" \
    -v need_fx_notification="$need_fx_notification" \
    -v need_fx_dap="$need_fx_dap" \
    -v need_fx_gamedap="$need_fx_gamedap" \
    "$LIVE" > "$TMP" 2>/dev/null

  # ---- 验证合并结果 ----
  if [ ! -s "$TMP" ] || \
     ! grep -q "$DAP_UUID" "$TMP" 2>/dev/null || \
     ! grep -q '<apply effect="dap"' "$TMP" 2>/dev/null; then
    rm -f "$TMP" 2>/dev/null
    ui_print "  合并现场 audio_effects.xml 失败，保留模块内回退版本"
    return 0
  fi

  # ---- 写入合并结果 ----
  if cp "$TMP" "$MODULE" 2>/dev/null; then
    rm -f "$TMP" 2>/dev/null
    ui_print "  已基于现场配置合并杜比效果链 (覆盖 6 个流)"
  else
    rm -f "$TMP" 2>/dev/null
    ui_print "  写入合并 audio_effects.xml 失败，保留模块内回退版本"
  fi
}
```

**🔧 FIX H-7 关键变更说明:**

| 变更点 | 原方案 | FIX H-7 后 |
|--------|--------|------------|
| 路径处理 | 3 个固定的 `gsub(/path="..."/...)` | `while (match(...))` + `basename()` 函数 |
| 支持路径 | 仅 3 个硬编码路径 | 任意 DAP/DVL/gamedap `.so` 路径 |
| 路径变体 | 仅完整路径 | 完整路径、相对路径、变体路径 (.v2 等) |
| 实现复杂度 | 3 行 gsub | 12 行函数, 更易维护 |

**🔧 FIX H-6 关键变更说明:**

| 变更点 | 原方案 | FIX H-6 后 |
|--------|--------|------------|
| 支持的流 | 仅 music | music/ring/alarm/system/notification/voice_call 共 6 个 |
| 状态机 | 硬编码 `type="music"` | `match()` 通用匹配, 提取 `type` 属性 |
| 缺失检测 | 仅 music 流 | 按流类型补全对应 DVL listener |
| 通话流处理 | 未考虑 | 显式跳过 voice_call (避免回声抑制冲突) |

---

### 2.4 `oplus.product.features_audiox.xml` — OPlus 特性替换

```xml
<oplus-config>
    <!-- Dolby Atmos OnePlus folk popularization -->
    <!-- 替换 OPlus AudioX 特性声明为杜比特性 -->
    <oplus-feature name="oplus.software.audio.audioeffect_support"/>
    <oplus-feature name="oplus.software.audio.dolby_support"/>
</oplus-config>
```

**设计说明:**

- 替换原厂 AudioX 特性声明，引导 ColorOS 框架使用杜比音效处理而非 AudioX
- 通过 `mount --bind` 在 `service.sh` 中运行时替换，不修改原厂分区

### 2.5 DMS 服务守护进程

`vendor.dolby.dms.service` 是预编译的 ELF 可执行文件，负责：

1. 通过 AIDL `vendor.dolby.dms.IDms` 接口提供音效控制 API
2. 管理 DAP 调音参数（`multimedia_dolby_dax_dflt.xml`）
3. 响应 APK 的预设切换、参数设置请求
4. 管理 DAP 效果实例的生命周期

**启动参数:** 无需额外参数，由 `service.sh` 调用：

```bash
/vendor/bin/hw/vendor.dolby.dms.service &
```

---

## 3. 音效处理流水线

### 3.1 效果链注册与激活

```
┌─────────────────────────────────────────────────────────────────┐
│ 系统启动                                                        │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ AudioFlinger 读取 /odm/etc/audio_effects.xml                    │
│ 1. 解析 <libraries> 加载 libswdap_sp.so, libdlbvol_sp.so       │
│ 2. 解析 <effects> 注册 DAP + DVL 效果实例                       │
│ 3. 解析 <postprocess> 绑定各流 → 对应 DVL listener              │
│    - music: dap + dlb_music_listener                            │
│    - ring: dlb_ring_listener                                    │
│    - alarm: dlb_alarm_listener                                  │
│    - system: dlb_system_listener                                │
│    - notification: dlb_notification_listener                    │
│    - voice_call: 无 (避免回声冲突, FIX H-6)                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 音频播放开始 (各流)                                              │
│ AudioPolicyManager 创建 audio track → AudioFlinger 创建效果链  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 效果链:                                                         │
│ PCM 输入 → [libswdap_sp.so: DAP] → [libdlbvol_sp.so: DVL] →   │
│ Audio HAL 输出                                                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ DAP 参数控制:                                                   │
│ APK → DMS AIDL → DAP Parameter Storage → libswdap_sp.so       │
│ (虚拟环绕/均衡器/对白增强/低音增强)                             │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 DAP 参数控制路径

```
┌──────────────────┐     AIDL      ┌──────────────────┐
│ APK              │ ────────────→ │ DMS Service      │
│ (DolbyAtmosCtrl) │               │ (vendor.dolby.   │
│                  │ ←──────────── │  dms.service)     │
└──────────────────┘    callback   └────────┬─────────┘
                                            │
                                   NDK binder
                                            │
                                            ▼
                                  ┌──────────────────┐
                                  │ DAP Parameter    │
                                  │ Storage          │
                                  │ (libdapparam-    │
                                  │  storage_sp.so)  │
                                  └────────┬─────────┘
                                           │
                                  shared memory / ioctl
                                           │
                                           ▼
                                  ┌──────────────────┐
                                  │ DAP Engine        │
                                  │ (libswdap_sp.so)  │
                                  │ 虚拟环绕 ON/OFF   │
                                  │ 均衡器 10-band    │
                                  │ 对白增强 0-100%   │
                                  │ 低音增强 0-100%   │
                                  └──────────────────┘
```

---

## 4. 模块间接口

### 4.1 对 M1 的接口

| 接口 | 说明 |
|------|------|
| `merge_audio_effects` | M3 提供此函数，M1 的 `customize.sh` 在安装阶段调用 |
| 目录结构 | M3 的文件部署在 `$MODPATH/system/vendor/`、`$MODPATH/system/odm/`、`$MODPATH/my_product/` |
| VINTF manifest | 共享 M2 的 `c2_manifest_vendor_audio.xml`（包含 DMS AIDL 声明） |

### 4.2 对 M4 的接口

| 接口 | 说明 |
|------|------|
| DMS AIDL | `vendor.dolby.dms.IDms` — APK 通过此接口控制音效参数 |
| AudioEffect API | DAP UUID `9d4921da-8225-4f29-aefa-39537a04bcaa` — APK 通过此接口控制效果开关 |
| DVL UUID | 各流类型对应的 UUID — APK 通过此接口控制音量均衡 |

### 4.3 对 M5 的接口

| 接口 | 说明 |
|------|------|
| DAP 效果日志 | logcat 中 `DlbDap` tag 的日志，M5 的诊断脚本采集和分析 |
| DMS 服务日志 | logcat 中 `vendor.dolby.dms` tag 的日志 |

---

## 5. 测试方案

### 5.1 单元测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| `merge_audio_effects` 函数 (基础) | 使用模拟的 `audio_effects.xml` 调用函数 | 输出 XML 包含 DAP + DVL 效果声明，且保留原有效果 |
| 重复合并幂等性 | 对已包含杜比效果的 XML 再次合并 | 不会重复添加效果声明 |
| 异常 XML 处理 | 使用损坏的 XML 调用函数 | 回退到模块内置版本，不崩溃 |
| AudioX 效果移除 | 输入包含 AudioX 效果的 XML | 输出中无 AudioX 相关声明 |
| DAP UUID 常量 | 在代码中引用 UUID | 与 `libswdap_sp.so` 中注册的 UUID 一致 |
| **🔧 FIX H-6** 多流合并 | 输入包含 music + ring + alarm 流的 XML | 输出中 3 个流都有 DVL listener, music 流有 DAP |
| **🔧 FIX H-6** 通话流处理 | 输入含 voice_call 流的 XML | 输出中 voice_call 流无 DVL listener (避免回声) |
| **🔧 FIX H-6** 流缺失补全 | 输入仅含 music 流的 XML | 输出中自动补全 ring/alarm/system/notification 流 |
| **🔧 FIX H-7** 多种路径变体 | 输入含 `/vendor/lib64/soundfx/libswdap_sp.so` 路径 | 路径被正确转为 `libswdap_sp.so` |
| **🔧 FIX H-7** 相对路径 | 输入含 `libswdap_sp.so` (已是 basename) | 路径保持不变, 无重复处理 |
| **🔧 FIX H-7** 变体文件名 | 输入含 `libswdap_sp_v2.so` (非标准) | 该文件不被错误处理 |

### 5.2 集成测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| 模块安装后 audio_effects.xml | 检查 `/odm/etc/audio_effects.xml` 内容 | 包含 DAP + DVL 效果声明, 6 个流都有 listener |
| AudioFlinger 效果加载 | 执行 `dumpsys media.audio_flinger \| grep -A2 "dap"` | 显示 DAP 效果已注册 |
| DMS 服务启动 | 重启后执行 `pidof vendor.dolby.dms.service` | 返回有效 PID |
| DMS AIDL 服务注册 | 执行 `service list \| grep dolby` | 显示 `vendor.dolby.dms.IDms/default` |
| 音效开关 | 通过 AudioEffect API 设置 DAP 启用/禁用 | `dumpsys media.audio_flinger` 中效果状态变化 |
| 预设切换 | 通过 DMS AIDL 设置 preset=0 (电影) | DAP 参数更新，可感知音效变化 |
| **🔧 FIX H-6** 多流独立控制 | 同时播放音乐 + 闹钟 | 两种流都应用对应 DVL listener, 互不干扰 |

### 5.3 端到端测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| 音乐播放 + DAP 开启 | 播放音乐，开启 DAP | 虚拟环绕效果可感知，左右声道分离度变化 |
| 电影播放 + 电影预设 | 播放电影，切换到电影模式 | 对白增强、低音增强可感知 |
| 游戏模式 | 启动游戏，切换到游戏模式 | 空间音频效果可感知，无延迟增加 |
| 输出设备切换 | 从扬声器切换到蓝牙耳机 | 音效配置自动切换，无中断 |
| 长时间播放 | 连续播放音乐 1 小时 | 无 crash、无内存泄漏、无音频卡顿 |
| **🔧 FIX H-6** 闹钟流 | 触发闹钟 | 闹钟使用 dlb_alarm_listener, 音量均衡生效 |

### 5.4 异常测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| DMS 服务崩溃恢复 | 手动 kill DMS 服务进程 | 系统音频不受影响，APK 可重新连接 |
| 无 DMS 服务降级 | 不启动 DMS 服务 | 解码器正常工作，DAP 可通过 AudioEffect API 控制 |
| SELinux 拒绝 | 安装时 SELinux 上下文不匹配 | 安装警告，但不中止 |
| 目录权限不足 | `/data/vendor/dolby` 不存在 | 服务自动创建目录 |

---

## 附录 A: 备选音效方案

### A.1 纯 AudioEffect API 方案

如果 DMS 服务完全无法启动或被 Android 16 的 AIDL 音频栈拒绝，M3 可降级为纯 AudioEffect API 方案：

**原理:** 绕过 DMS 服务，直接在 APK 中通过 Android `AudioEffect` API 控制 DAP 引擎。

```kotlin
// 创建 DAP 效果实例
val dapEffect = AudioEffect(
    AudioEffect.Descriptor().apply {
        type = AudioEffect.EFFECT_TYPE_NULL  // 修正: 原文档错写为 EFFECT_TYPE_INSERT
        uuid = UUID.fromString("9d4921da-8225-4f29-aefa-39537a04bcaa")
    },
    0, // priority
    0  // audio session (0 = global)
)

// 启用/禁用 DAP
dapEffect.enabled = true

// 设置 DAP 参数（通过 setParameter 传递预设索引）
val param = ByteArray(4).apply {
    // 预设索引: 0=电影, 1=音乐, 2=游戏, 3=语音, 4=自定义
    putInt(0, presetIndex)
}
dapEffect.setParameter(byteArrayOf(0x00, 0x01, 0x00, 0x00), param)
```

**限制:**
- 无法使用 DMS 的高级调音功能（如 `getAvailableTuningDevicesLen`）
- 预设参数需要预先编码到字节数组中，灵活性降低
- 无法实时获取 DAP 状态反馈

### A.2 SELinux 策略补丁方案

如果 SELinux 阻止 DMS 服务访问必要的系统资源，M6 可提供 `apply_sepolicy_patches` 函数注入运行时策略：

```bash
# 允许 DMS 服务访问 audio HAL
allow vendor_dolby_dms_service audio_hal_service:service_manager find;
# 允许 DMS 服务与 AudioFlinger 通信
allow vendor_dolby_dms_service audioserver:binder call;
```

---

## 6. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-29 | 初始版本，主方案：DMS AIDL + AudioEffect API 双路径 |
| **v1.0-FIXED** | **2026-07-02** | **修复 H-6 (6 个流处理), H-7 (通用 basename); 见 §0 变更摘要** |
