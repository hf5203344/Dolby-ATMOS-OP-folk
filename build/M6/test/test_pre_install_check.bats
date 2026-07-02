#!/usr/bin/env bats
# ============================================================
# M6: test_pre_install_check.bats
# 单独覆盖 pre_install_check 的 5 个分支
# ============================================================

COMPAT_SH=""
STUB_BIN=""
UI_LOG=""

setup() {
  COMPAT_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/META-INF/compat.sh"
  [ -f "$COMPAT_SH" ] || skip "compat.sh not found at $COMPAT_SH"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"

  # 创建真实 Android 路径(在 CI 容器中不存在)
  mkdir -p /vendor/etc /vendor/lib64 /odm/etc/vintf/manifest /data/adb/modules 2>/dev/null

  # ui_print stub: 写入日志文件 (避免 run 在子 shell 中变量丢失)
  UI_LOG="$BATS_TEST_TMPDIR/ui.log"
  : > "$UI_LOG"
  ui_print() {
    printf '%s\n' "$*" >> "$UI_LOG"
  }
  export -f ui_print
  export UI_LOG
}

teardown() {
  rm -rf /vendor /odm /data/adb 2>/dev/null
  unset KSU APATCH MAGISK_VER
}

# 写入 getprop stub,只对指定 key 返回 value
write_getprop_multi_stub() {
  local out="$STUB_BIN/getprop"
  {
    echo "#!/bin/sh"
    echo 'case "$1" in'
    for kv in "$@"; do
      local k="${kv%%=*}"
      local v="${kv#*=}"
      echo "  \"$k\") echo \"$v\" ;;"
    done
    echo 'esac'
    echo 'echo ""'
  } > "$out"
  chmod +x "$out"
}

# ============================================================
# 分支 1: SDK < 34 (error=1)
# ============================================================

@test "pre_install_check branch1: SDK<34 returns error=1" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=33" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 1 ]
  grep -q "Android 版本过低" "$UI_LOG"
}

@test "pre_install_check branch1: SDK=30 (Android 11) error=1" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=30" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 1 ]
}

# ============================================================
# 分支 2: ABI != arm64-v8a (error=1)
# ============================================================

@test "pre_install_check branch2: ABI armeabi-v7a error=1" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=35" \
    "ro.product.cpu.abi=armeabi-v7a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 1 ]
  grep -q "CPU 架构" "$UI_LOG"
}

@test "pre_install_check branch2: ABI x86_64 error=1" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=35" \
    "ro.product.cpu.abi=x86_64" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 1 ]
}

# ============================================================
# 分支 3: 两者都失败 (error=2)
# ============================================================

@test "pre_install_check branch3: SDK<34 AND ABI wrong error=2" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=30" \
    "ro.product.cpu.abi=x86" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 2 ]
  grep -q "Android 版本过低" "$UI_LOG"
  grep -q "CPU 架构" "$UI_LOG"
}

@test "pre_install_check branch3: SDK=29 + ABI=x86_64 error=2" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=29" \
    "ro.product.cpu.abi=x86_64" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 2 ]
}

# ============================================================
# 分支 4: 冲突模块 (warn, 不增 error)
# ============================================================

@test "pre_install_check branch4: conflict modules warn but error=0" {
  mkdir -p /data/adb/modules/ViPER4Android /data/adb/modules/JamesDSP
  write_getprop_multi_stub \
    "ro.build.version.sdk=35" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 0 ]
  grep -q "警告: 检测到可能冲突" "$UI_LOG"
  grep -q "ViPER4Android" "$UI_LOG"
  grep -q "JamesDSP" "$UI_LOG"
}

@test "pre_install_check branch4: conflict+SDK bad = error=1 not 2" {
  mkdir -p /data/adb/modules/dolbyatmos
  write_getprop_multi_stub \
    "ro.build.version.sdk=33" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 1 ]  # 冲突是 warn, 不计入 error
}

# ============================================================
# 分支 5: 全部正常 (error=0)
# ============================================================

@test "pre_install_check branch5: all good OnePlus arm64 SDK35 error=0" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=35" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 0 ]
}

@test "pre_install_check branch5: all good OPPO arm64 SDK34 error=0" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=34" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OPPO"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 0 ]
}

@test "pre_install_check branch5: non-OPlus arm64 SDK35 error=0 (only warn)" {
  write_getprop_multi_stub \
    "ro.build.version.sdk=35" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=samsung"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 0 ]
  grep -q "非一加/OPPO 设备" "$UI_LOG"
}

@test "pre_install_check branch5: with hardware dolby shows notice but error=0" {
  cat > /vendor/etc/media_codecs_c2.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<MediaCodecs>
  <Codec name="c2.dolby.eac3.decoder"/>
</MediaCodecs>
XML
  write_getprop_multi_stub \
    "ro.build.version.sdk=35" \
    "ro.product.cpu.abi=arm64-v8a" \
    "ro.product.manufacturer=OnePlus"
  export PATH="$STUB_BIN:$PATH"
  . "$COMPAT_SH"
  run pre_install_check
  [ "$status" -eq 0 ]
  grep -q "硬件杜比解码器" "$UI_LOG"
}
