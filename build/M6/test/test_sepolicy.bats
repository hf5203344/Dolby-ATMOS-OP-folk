#!/usr/bin/env bats
# ============================================================
# M6: test_sepolicy.bats
# 验证 sepolicy.rule 内容
# ============================================================

SEPOLICY_RULE=""
COMPAT_SH=""
STUB_BIN=""

setup() {
  local base
  base="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SEPOLICY_RULE="$base/META-INF/sepolicy.rule"
  COMPAT_SH="$base/META-INF/compat.sh"

  # 为 apply_sepolicy_patches 测试创建 stub bin
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
}

# ============================================================
# 文件存在性
# ============================================================

@test "sepolicy.rule file exists" {
  [ -f "$SEPOLICY_RULE" ]
}

@test "sepolicy.rule is not empty" {
  [ -s "$SEPOLICY_RULE" ]
}

# ============================================================
# 关键字覆盖 (4 类 allow 规则)
# ============================================================

@test "sepolicy.rule contains audioserver rule (DMS<->AudioFlinger)" {
  grep -q "audioserver" "$SEPOLICY_RULE"
}

@test "sepolicy.rule contains audioserver_service rule" {
  grep -q "audioserver_service" "$SEPOLICY_RULE"
}

@test "sepolicy.rule contains mediacodec rule (C2<->MediaCodec)" {
  grep -q "mediacodec" "$SEPOLICY_RULE"
}

@test "sepolicy.rule contains mediacodec_service rule" {
  grep -q "mediacodec_service" "$SEPOLICY_RULE"
}

@test "sepolicy.rule contains audio_device rule (DMS<->audio chr_file)" {
  grep -q "audio_device" "$SEPOLICY_RULE"
}

@test "sepolicy.rule contains vendor_data_file rule (DMS data dir)" {
  grep -q "vendor_data_file" "$SEPOLICY_RULE"
}

@test "sepolicy.rule uses vendor_dolby_dms_service as source" {
  grep -q "vendor_dolby_dms_service" "$SEPOLICY_RULE"
}

@test "sepolicy.rule uses vendor_dolby_sp_media_c2_1_0_service (@ -> _)" {
  # 设计要求: @ 符号在 SELinux type 名中要写成下划线
  grep -q "vendor_dolby_sp_media_c2_1_0_service" "$SEPOLICY_RULE"
}

@test "sepolicy.rule uses allow syntax (magiskpolicy compatible)" {
  # magiskpolicy 语法以 allow 开头
  grep -E "^allow " "$SEPOLICY_RULE"
}

@test "sepolicy.rule has at least 4 allow lines" {
  local count
  count=$(grep -cE "^allow " "$SEPOLICY_RULE" || true)
  [ "$count" -ge 4 ]
}

@test "sepolicy.rule does not use raw @ in allow type name" {
  # 反向检查: 确认 allow 语句中 @1_0 已转义为 _1_0
  # 仅检查以 allow 开头的行,忽略注释
  if grep -E "^allow [^;]*media_c2@1_0_service" "$SEPOLICY_RULE"; then
    return 1
  fi
}

# ============================================================
# 行为: apply_sepolicy_patches 在 magiskpolicy 缺失时不报错
# ============================================================

@test "apply_sepolicy_patches works when magiskpolicy missing (skip gracefully)" {
  local moddir="$BATS_TEST_TMPDIR/moddir"
  mkdir -p "$moddir/META-INF"
  cp "$SEPOLICY_RULE" "$moddir/META-INF/sepolicy.rule"

  # 关键: 不在 STUB_BIN 中创建 magiskpolicy 工具
  export PATH="$STUB_BIN:/usr/bin:/bin"
  . "$COMPAT_SH"
  run apply_sepolicy_patches "$moddir"
  [ "$status" -eq 0 ]
}

@test "apply_sepolicy_patches works when moddir has no patch file" {
  local moddir="$BATS_TEST_TMPDIR/moddir_nopatch"
  mkdir -p "$moddir/META-INF"
  # 不放 sepolicy.rule

  export PATH="$STUB_BIN:/usr/bin:/bin"
  . "$COMPAT_SH"
  run apply_sepolicy_patches "$moddir"
  [ "$status" -eq 0 ]
}

@test "apply_sepolicy_patches works with empty MODDIR" {
  export PATH="$STUB_BIN:/usr/bin:/bin"
  . "$COMPAT_SH"
  run apply_sepolicy_patches ""
  [ "$status" -eq 0 ]
}

@test "apply_sepolicy_patches succeeds when magiskpolicy returns 0" {
  local moddir="$BATS_TEST_TMPDIR/moddir_ok"
  mkdir -p "$moddir/META-INF"
  cp "$SEPOLICY_RULE" "$moddir/META-INF/sepolicy.rule"

  # 创建返回 0 的 magiskpolicy stub
  cat > "$STUB_BIN/magiskpolicy" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$STUB_BIN/magiskpolicy"

  export PATH="$STUB_BIN:/usr/bin:/bin"
  . "$COMPAT_SH"
  run apply_sepolicy_patches "$moddir"
  [ "$status" -eq 0 ]
}

@test "apply_sepolicy_patches still returns 0 when magiskpolicy fails" {
  local moddir="$BATS_TEST_TMPDIR/moddir_fail"
  mkdir -p "$moddir/META-INF"
  cp "$SEPOLICY_RULE" "$moddir/META-INF/sepolicy.rule"

  # magiskpolicy 失败时函数应优雅退出
  cat > "$STUB_BIN/magiskpolicy" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$STUB_BIN/magiskpolicy"

  export PATH="$STUB_BIN:/usr/bin:/bin"
  . "$COMPAT_SH"
  run apply_sepolicy_patches "$moddir"
  [ "$status" -eq 0 ]
}
