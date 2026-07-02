# M2: 杜比解码器 — 详细设计文档 **[FIXED v1.0]**

> **版本:** v1.0-FIXED | **日期:** 2026-07-02 | **状态:** 详细设计 (含修复)
> **基础版本:** v1.0 (2026-06-29)
> **本版本变更:** 修复 [设计审查-v1.0.md](../../设计审查-v1.0.md) 中的 C-2, H-5

---

## 0. 本版本变更摘要 (v1.0-FIXED)

| # | 类型 | 章节 | 修复内容 |
|---|------|------|----------|
| C-2 | Critical | §2.4, §2.10 (新增) | 新增"二进制 SHA256 计算与校验流程", 提供 `verify_checksums.sh` 脚本, 替换原"待确认"标记 |
| H-5 | High | §2.3 | VINTF manifest 明确 `default2` → Qualcomm, `default1` → Dolby, 互不冲突 |

---

## 1. 模块概述

### 1.1 职责

M2 负责杜比全景声解码器的集成，包括：

- 提供 AC-3、E-AC-3、E-AC-3-JOC、AC-4 四种格式的软件解码器
- 通过 Codec2 HIDL 框架注册解码器到 Android MediaCodec 系统
- 声明 VINTF manifest 使解码服务可被系统发现
- 管理解码器原生库（.so）的部署和权限

### 1.2 依赖关系

| 方向 | 模块 | 说明 |
|------|------|------|
| 上游依赖 | M1 | 依赖 M1 的目录结构、权限设置、service.sh 服务启动 |
| 下游依赖 | 无 | M2 是独立功能模块 |

### 1.3 解码器能力矩阵

| 格式 | MIME Type | 最大声道 | 采样率 | 最大码率 | 解码器名称 |
|------|-----------|----------|--------|----------|-----------|
| AC-3 | `audio/ac3` | 6 | 32/44.1/48 kHz | 640 kbps | `c2.dolby.eac3.decoder` (alias of eac3) |
| E-AC-3 | `audio/eac3` | 8 | 32/44.1/48 kHz | 6144 kbps | `c2.dolby.eac3.decoder` |
| E-AC-3-JOC | `audio/eac3-joc` | 16 | 48 kHz | 6144 kbps | `c2.dolby.eac3.decoder` |
| AC-4 | `audio/ac4` | 16 | 48 kHz | 2688 kbps | `c2.dolby.ac4.decoder` |

---

## 2. 文件清单与实现

### 2.1 文件清单

```
system/
├── odm/etc/
│   └── media_codecs_c2.xml                            # 解码器注册配置
├── vendor/
│   ├── bin/hw/
│   │   └── vendor.dolby_sp.media.c2@1.0-service       # Codec2 HIDL 服务守护进程
│   ├── etc/vintf/manifest/
│   │   └── c2_manifest_vendor_audio.xml               # VINTF HAL 服务声明
│   └── lib64/
│       ├── libcodec2_soft_ac4dec_sp.so                # AC-4 软件解码器
│       ├── libcodec2_soft_ddpdec_sp.so                # Dolby Digital Plus (E-AC-3) 解码器
│       ├── libcodec2_soft_common.so                   # Codec2 通用辅助库
│       ├── libcodec2_store_dolby_sp.so                # 杜比组件存储
│       ├── libdeccfg_sp.so                            # 解码器配置
│       └── libYokiScale.so                            # Yoki 音频缩放
└── M2/
    └── checksums.txt                                  # 🔧 FIX C-2: SHA256 校验和文件
```

### 2.2 `media_codecs_c2.xml` — 解码器注册

```xml
<?xml version="1.0" encoding="utf-8" ?>
<!--
    Dolby Atmos OnePlus folk popularization
    Codec2 解码器注册配置
    基于 PJD110 设备提取，适配 PKG110 (一加 ACE5)
-->
<Included>
    <Decoders>
        <!-- DOLBY_UDC: Dolby Digital / Dolby Digital Plus / Dolby Atmos -->
        <MediaCodec name="c2.dolby.eac3.decoder" >
            <Type name="audio/ac3">
                <Alias name="OMX.dolby.ac3.decoder" />
                <Limit name="channel-count" max="6" />
                <Limit name="sample-rate" ranges="32000,44100,48000" />
                <Limit name="bitrate" range="32000-640000" />
            </Type>
            <Type name="audio/eac3">
                <Alias name="OMX.dolby.eac3.decoder" />
                <Limit name="channel-count" max="8" />
                <Limit name="sample-rate" ranges="32000,44100,48000" />
                <Limit name="bitrate" range="32000-6144000" />
            </Type>
            <Type name="audio/eac3-joc">
                <Alias name="OMX.dolby.eac3-joc.decoder" />
                <Limit name="channel-count" max="16" />
                <Limit name="sample-rate" ranges="48000" />
                <Limit name="bitrate" range="32000-6144000" />
            </Type>
            <Attribute name="software-codec" />
        </MediaCodec>

        <!-- DOLBY_AC4: Dolby AC-4 -->
        <MediaCodec name="c2.dolby.ac4.decoder" type="audio/ac4">
            <Alias name="OMX.dolby.ac4.decoder" />
            <Limit name="channel-count" max="16" />
            <Limit name="sample-rate" ranges="48000" />
            <Limit name="bitrate" range="16000-2688000" />
            <Attribute name="software-codec" />
        </MediaCodec>
    </Decoders>
</Included>
```

**设计说明:**

- `<Attribute name="software-codec" />` 标记为软件解码器，Android 框架会优先使用硬件解码器（如果存在），仅在硬件不支持时回退到本模块
- `<Alias>` 标签提供 OMX 兼容别名，确保使用旧版 MediaCodec API 的应用也能发现解码器
- `<Limit>` 标签声明解码器能力边界，系统在创建解码器实例前会验证输入格式是否在范围内

---

### 2.3 `c2_manifest_vendor_audio.xml` — VINTF HAL 声明

**🔧 FIX H-5 重要变更:** 明确 `default1` / `default2` 实例指向, 避免 Codec2 框架解析歧义.

```xml
<!--
    Dolby Atmos OnePlus folk popularization
    VINTF manifest: Codec2 HIDL 服务声明
    🔧 FIX H-5: 明确 default 实例指向
        - default1 → Dolby Codec2 HIDL 服务 (本模块提供)
        - default2 → Qualcomm 音频 Codec2 服务 (系统原厂保留)
        - vendor.dolby.dms IDms/default → M3 音效模块的 DMS AIDL 服务
-->
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>android.hardware.media.c2</name>
        <transport>hwbinder</transport>
        <!-- 🔧 FIX H-5: 顺序声明, 后声明的优先匹配. Dolby 必须先注册为 default1 -->
        <fqname>@1.0::IComponentStore/default1</fqname>
        <fqname>@1.0::IComponentStore/default2</fqname>
    </hal>
    <hal format="aidl">
        <name>vendor.dolby.dms</name>
        <version>1</version>
        <fqname>IDms/default</fqname>
    </hal>
</manifest>
```

**🔧 FIX H-5 设计说明:**

| 实例 | 服务名 | 优先级 | 提供者 |
|------|--------|--------|--------|
| `default1` | Dolby Codec2 HIDL (vendor.dolby_sp.media.c2@1.0-service) | 优先 (后注册) | 本模块 |
| `default2` | Qualcomm 音频 Codec2 (vendor.qti.media.c2@1.0-service) | 备用 (先注册) | 系统原厂 |
| `IDms/default` | Dolby DMS AIDL (vendor.dolby.dms.service) | 唯一 | M3 |

**绑定规则 (在 service.sh 中):**
```bash
# 🔧 FIX H-5: 显式绑定 Dolby 守护进程到 default1
/vendor/bin/hw/vendor.dolby_sp.media.c2@1.0-service &
sleep 1

# 验证 default1 是 Dolby
lshal debug android.hardware.media.c2@1.0::IComponentStore/default1 | grep "interface descriptor" | grep -q "vendor.dolby" || \
  log "ERROR: default1 未绑定到 Dolby 守护进程"
```

**为什么不交换 default1/default2 顺序:**
- Android 框架默认优先使用 `default1`, 但 IComponentStore 注册顺序决定实际服务
- 解决方案: service.sh 启动顺序保证 Dolby 守护进程先启动, 并验证绑定

---

### 2.4 解码器原生库映射

**🔧 FIX C-2:** 以下 SHA256 必须由构建流程计算, 写入 `M2/checksums.txt`, **不允许手工填写**. 计算流程见 §2.10.

| 文件 | 大小（参考） | SHA256 | 用途 |
|------|-------------|--------|------|
| `libcodec2_soft_ac4dec_sp.so` | ~2.5 MB | 见 `checksums.txt` | AC-4 解码器核心实现 |
| `libcodec2_soft_ddpdec_sp.so` | ~1.8 MB | 见 `checksums.txt` | Dolby Digital Plus / E-AC-3-JOC 解码器 |
| `libcodec2_soft_common.so` | ~200 KB | 见 `checksums.txt` | Codec2 通用辅助函数 |
| `libcodec2_store_dolby_sp.so` | ~300 KB | 见 `checksums.txt` | 杜比 Codec2 组件存储 |
| `libdeccfg_sp.so` | ~150 KB | 见 `checksums.txt` | 解码器运行时配置 |
| `libYokiScale.so` | ~500 KB | 见 `checksums.txt` | Yoki 音频缩放库 |

### 2.5 Codec2 HIDL 服务守护进程

`vendor.dolby_sp.media.c2@1.0-service` 是一个预编译的 ELF 可执行文件，负责：

1. 通过 HIDL `android.hardware.media.c2@1.0::IComponentStore` 接口注册解码器
2. 加载 `libcodec2_store_dolby_sp.so` 作为组件存储后端
3. 响应 MediaCodec 框架的解码器查询和实例化请求
4. 管理解码器生命周期（创建、配置、解码、释放）

**启动参数:** 无需额外参数，由 `service.sh` 直接调用：

```bash
/vendor/bin/hw/vendor.dolby_sp.media.c2@1.0-service &
```

**运行验证:**

```bash
# 检查服务是否启动
pidof vendor.dolby_sp.media.c2@1.0-service

# 检查 HIDL 服务注册
lshal debug android.hardware.media.c2@1.0::IComponentStore/default1

# 检查解码器列表
dumpsys media.codec2 | grep -A5 "dolby"
```

---

### 2.10 🔧 FIX C-2: 二进制 SHA256 计算与校验流程

**问题:** 原文档"待确认"的 SHA256 阻塞了 Phase 4 集成测试.

**解决方案:** 在构建阶段自动计算, 运行时强制校验. 任何文件篡改都会被检测.

#### 2.10.1 构建期: `tools/compute_checksums.sh`

```bash
#!/bin/bash
# ============================================================
# M2 工具: compute_checksums.sh
# 在构建机上运行, 计算所有 .so 二进制的 SHA256, 写入 checksums.txt
# 用法: ./compute_checksums.sh /path/to/dolby_ref/ > checksums.txt
# ============================================================
set -euo pipefail

REF_DIR="${1:-/data/user/work/dolby_ref}"
OUT_FILE="${2:-checksums.txt}"

if [ ! -d "$REF_DIR" ]; then
  echo "ERROR: 引用目录不存在: $REF_DIR" >&2
  exit 1
fi

# 6 个核心 .so
FILES=(
  "libcodec2_soft_ac4dec_sp.so"
  "libcodec2_soft_ddpdec_sp.so"
  "libcodec2_soft_common.so"
  "libcodec2_store_dolby_sp.so"
  "libdeccfg_sp.so"
  "libYokiScale.so"
)

{
  echo "# Dolby Atmos OnePlus folk popularization"
  echo "# SHA256 校验和文件"
  echo "# 生成时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "# 生成主机: $(hostname)"
  echo "# 引用源: $REF_DIR"
  echo "# 算法: SHA256"
  echo ""
  echo "# 文件名                                   SHA256"
  echo "# ---------------------------------------- ----------------------------------------"
  for f in "${FILES[@]}"; do
    FILE_PATH="$REF_DIR/system/vendor/lib64/$f"
    if [ ! -f "$FILE_PATH" ]; then
      echo "ERROR: 文件不存在: $FILE_PATH" >&2
      exit 1
    fi
    SHA=$(sha256sum "$FILE_PATH" | awk '{print $1}')
    SIZE=$(stat -c '%s' "$FILE_PATH")
    printf "%-40s %s  size=%d\n" "$f" "$SHA" "$SIZE"
  done
} > "$OUT_FILE"

echo "✓ SHA256 已写入 $OUT_FILE"
cat "$OUT_FILE"
```

#### 2.10.2 校验期: `tools/verify_checksums.sh`

```bash
#!/bin/sh
# ============================================================
# M2 工具: verify_checksums.sh
# 在设备上或构建机运行, 验证 .so 文件 SHA256 与 checksums.txt 一致
# 退出码: 0=全部匹配, 1=有文件不匹配或缺失
# ============================================================
set +e

CHECKSUMS_FILE="${1:-./checksums.txt}"
LIB_DIR="${2:-./system/vendor/lib64}"

if [ ! -f "$CHECKSUMS_FILE" ]; then
  echo "ERROR: 校验和文件不存在: $CHECKSUMS_FILE" >&2
  exit 1
fi

if [ ! -d "$LIB_DIR" ]; then
  echo "ERROR: 库目录不存在: $LIB_DIR" >&2
  exit 1
fi

ERRORS=0
CHECKED=0

# 解析 checksums.txt (忽略注释行和空行)
while IFS= read -r line; do
  # 跳过注释和空行
  case "$line" in
    \#*|"") continue ;;
  esac

  # 格式: filename  sha256  size=NNNN
  FILE_NAME=$(echo "$line" | awk '{print $1}')
  EXPECTED_SHA=$(echo "$line" | awk '{print $2}')

  if [ -z "$FILE_NAME" ] || [ -z "$EXPECTED_SHA" ]; then
    continue
  fi

  FILE_PATH="$LIB_DIR/$FILE_NAME"

  if [ ! -f "$FILE_PATH" ]; then
    echo "  ✗ MISSING: $FILE_NAME" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi

  ACTUAL_SHA=$(sha256sum "$FILE_PATH" 2>/dev/null | awk '{print $1}')

  if [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
    echo "  ✓ OK: $FILE_NAME"
    CHECKED=$((CHECKED + 1))
  else
    echo "  ✗ MISMATCH: $FILE_NAME" >&2
    echo "    expected: $EXPECTED_SHA" >&2
    echo "    actual:   $ACTUAL_SHA" >&2
    ERRORS=$((ERRORS + 1))
  fi
done < "$CHECKSUMS_FILE"

echo ""
echo "检查完成: $CHECKED 个文件通过, $ERRORS 个文件失败"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
exit 0
```

#### 2.10.3 `checksums.txt` 格式示例

```
# Dolby Atmos OnePlus folk popularization
# SHA256 校验和文件
# 生成时间: 2026-07-02T10:00:00Z
# 生成主机: buildbot
# 引用源: /data/user/work/dolby_ref/
# 算法: SHA256

# 文件名                                   SHA256
# ---------------------------------------- ----------------------------------------
libcodec2_soft_ac4dec_sp.so               a1b2c3d4e5f6...  size=2621440
libcodec2_soft_ddpdec_sp.so               f6e5d4c3b2a1...  size=1887436
libcodec2_soft_common.so                  1234567890ab...  size=204800
libcodec2_store_dolby_sp.so               fedcba098765...  size=307200
libdeccfg_sp.so                           abcdef123456...  size=153600
libYokiScale.so                           9876543210fe...  size=512000
```

#### 2.10.4 集成到 M5 诊断工具 (action.sh)

M5 阶段 4 (文件完整性校验) 增加 SHA256 检查:

```bash
# 在 M5 阶段 4 中添加 (详见 M5-fixed.md)
log "--- 4.1 SHA256 校验 ---"
if [ -f "$MODDIR/checksums.txt" ]; then
  sh "$MODDIR/tools/verify_checksums.sh" "$MODDIR/checksums.txt" "$MODDIR/system/vendor/lib64" >> "$REPORT_FILE" 2>&1
  if [ $? -eq 0 ]; then
    check_pass "所有 .so 库 SHA256 校验通过"
  else
    check_fail ".so 库 SHA256 校验失败, 文件可能被篡改"
  fi
else
  check_warn "未找到 checksums.txt, 跳过 SHA256 校验"
fi
log ""
```

#### 2.10.5 何时计算 SHA256

| 阶段 | 何时计算 | 计算者 |
|------|----------|--------|
| Phase 0 (文档定稿) | 参考模块首次可用时, 立即计算 | 构建工程师 |
| Phase 1 (M2 实施) | 集成到 ZIP 包前 | CI 流水线 |
| Phase 4 (集成测试) | 每次发版前 | CI 流水线 |

**禁止行为:**
- ❌ 手工填写 SHA256 (易错)
- ❌ 复用旧版本 SHA256 (新版本可能不兼容)
- ❌ 在文档中硬编码 SHA256 (版本变化时不会更新)

---

## 3. 解码流程

### 3.1 解码器发现与选择流程

```
┌─────────────────────────────────────────────────────────────────┐
│ 应用请求解码 (MediaCodec.createDecoderByType("audio/ac4"))     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ MediaCodec 框架查询 Codec2 组件存储                             │
│ 1. 读取 /vendor/etc/media_codecs_c2.xml                        │
│ 2. 读取 /odm/etc/media_codecs_c2.xml (模块覆盖)                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ HIDL 服务发现 (hwservicemanager)                                │
│ 1. 查询 android.hardware.media.c2@1.0::IComponentStore/default1│
│ 2. 验证 default1 已绑定到 Dolby 守护进程 (FIX H-5)              │
│ 3. 返回 vendor.dolby_sp.media.c2@1.0-service                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 组件存储返回解码器信息                                          │
│ c2.dolby.ac4.decoder: audio/ac4, max 16ch, 48kHz, software     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ Codec2 框架创建解码器实例                                       │
│ 1. 加载 libcodec2_soft_ac4dec_sp.so                            │
│ 2. 调用 C2Component::init() 初始化                             │
│ 3. 调用 C2Component::setParameters() 配置                      │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ 解码循环                                                        │
│ C2Component::queue() → process() → onWorkDone()                │
│ 输入: 编码的 AC-4 bitstream                                     │
│ 输出: PCM 16-bit interleaved                                    │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 解码器实例化关键代码路径

```
MediaCodec.createByCodecName("c2.dolby.ac4.decoder")
  → CCodec::initiateAllocateComponent()
    → IComponentStore::createComponent("c2.dolby.ac4.decoder", ...)
      → libcodec2_store_dolby_sp.so: CreateComponent()
        → new C2SoftAc4Dec()  (libcodec2_soft_ac4dec_sp.so)
          → C2SoftAc4Dec::init()
            → 注册 input/output C2Port
            → 设置 supported sample rates, channel counts, bitrates
```

---

## 4. 模块间接口

### 4.1 对 M1 的依赖

| 接口 | 说明 |
|------|------|
| 目录结构 | M2 的文件部署在 `$MODPATH/system/vendor/` 和 `$MODPATH/system/odm/` |
| 权限设置 | 依赖 M1 的 `perm_recursive` / `perm_one` 设置文件权限和 SELinux 上下文 |
| 服务启动 | 依赖 M1 的 `service.sh` 调用 `start_once` 启动 Codec2 HAL 守护进程 |
| 环境变量 | 依赖 `$MODPATH` 和 `$MODDIR` 定位模块文件 |

### 4.2 对 M3 的接口

| 接口 | 说明 |
|------|------|
| VINTF manifest | M2 的 `c2_manifest_vendor_audio.xml` 包含 DMS AIDL 服务声明，M3 依赖此声明 |
| 共享库 | `libYokiScale.so` 和 `libdeccfg_sp.so` 被 M3 的 DAP 引擎间接引用 |

### 4.3 对 M6 的接口

| 接口 | 说明 |
|------|------|
| 解码器可用性检测 | M6 在安装时检测设备是否已有硬件 AC-4 解码器，M2 提供覆盖策略 |

---

## 5. 测试方案

### 5.1 单元测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| **🔧 FIX C-2** SHA256 校验 | 运行 `verify_checksums.sh` | 所有 6 个 .so 校验通过 |
| **🔧 FIX C-2** SHA256 篡改检测 | 修改任一 .so 后运行 `verify_checksums.sh` | 该 .so 报告 MISMATCH, 退出码 1 |
| **🔧 FIX C-2** SHA256 缺失检测 | 删除任一 .so 后运行 | 该 .so 报告 MISSING, 退出码 1 |
| **🔧 FIX H-5** default1 绑定 | `lshal debug .../default1` | 返回 Dolby 守护进程 descriptor |
| **🔧 FIX H-5** default2 保留 | `lshal debug .../default2` | 返回 Qualcomm 守护进程 descriptor |
| Codec2 服务启动 | 安装模块后重启，执行 `pidof vendor.dolby_sp.media.c2@1.0-service` | 返回有效 PID |
| HIDL 服务注册 | 执行 `lshal debug android.hardware.media.c2@1.0::IComponentStore/default1` | 返回服务信息，无错误 |
| 解码器列表 | 执行 `dumpsys media.codec2 \| grep "c2.dolby"` | 列出 `c2.dolby.ac4.decoder` 和 `c2.dolby.eac3.decoder` |
| 解码器属性 | 执行 `dumpsys media.codec2 c2.dolby.ac4.decoder` | 显示正确的 MIME type、声道数、采样率范围 |
| AC-4 解码 | 使用 `mediapc` 工具或 CTS 测试套件 | 解码成功，输出 PCM 数据 |

### 5.2 集成测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| VLC 播放 AC-4 视频 | 在 VLC 中打开 AC-4 编码的 MKV 文件 | 有声音输出，无 crash |
| MX Player 播放 E-AC-3 | 在 MX Player 中使用 HW+ 解码器播放 | 有声音输出，音视频同步 |
| 系统 MediaCodec 列表 | 执行 `adb shell dumpsys media.codec2` | 杜比解码器出现在列表中，状态为已注册 |
| 与其他解码器共存 | 同时播放 AAC 和 AC-4 音频 | 两个解码器独立工作，互不干扰 |
| 解码器卸载 | 移除模块后执行 `dumpsys media.codec2` | 杜比解码器不再出现 |
| **🔧 FIX H-5** Dolby/Qualcomm 共存 | 同时启用 Dolby 和系统音频 | 两个解码器都注册, Dolby 优先 |

### 5.3 性能测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| AC-4 16ch CPU 占用 (Snapdragon 8 Gen 3) | 播放 16 声道 AC-4 内容，使用 `top -p $(pidof vendor.dolby_sp.media.c2@1.0-service)` 监控 | CPU 占用 < 15% |
| E-AC-3-JOC CPU 占用 (Snapdragon 8 Gen 3) | 播放带 Atmos 的 E-AC-3-JOC 内容 | CPU 占用 < 10% |
| 内存占用 (PSS) | `dumpsys meminfo $(pidof vendor.dolby_sp.media.c2@1.0-service)` | PSS < 100 MB |
| 解码延迟 | 使用 `mediapc` 工具测量 | 延迟 < 50ms |

### 5.4 兼容性测试

| 测试项 | 测试方法 | 通过标准 |
|--------|----------|----------|
| Android 14 兼容 | 在 Android 14 设备上安装 | 解码器正常工作 |
| Android 15 兼容 | 在 Android 15 设备上安装 | 解码器正常工作 |
| Android 16 兼容 | 在一加 ACE5 (Android 16) 上安装 | 解码器正常工作 |
| Magisk 兼容 | 通过 Magisk 安装 | 解码器正常工作 |
| APatch 兼容 | 通过 APatch 安装 | 解码器正常工作 |

---

## 6. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v1.0 | 2026-06-29 | 初始版本，基于参考模块 dolbycodec2hidl H1.32 解码器组件 |
| **v1.0-FIXED** | **2026-07-02** | **修复 C-2 (SHA256 流程), H-5 (default1/default2 明确); 见 §0 变更摘要** |
