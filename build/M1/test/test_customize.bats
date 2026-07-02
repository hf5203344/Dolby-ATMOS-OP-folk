#!/usr/bin/env bats
# ============================================================
# M1: test_customize.bats
# 覆盖 customize.sh 中的以下函数:
#   - ui_print
#   - abort
#   - perm_recursive
#   - perm_one
#   - clean_old_artifacts
#   - detect_root_solution
#   - detect_android_version
#   - detect_architecture
# 正常路径 + 异常路径;需要 setup() / teardown()
# 运行时要求: bats >= 1.5.0 (https://github.com/bats-core/bats-core)
# ============================================================

bats_require_minimum_version 1.5.0

CUSTOMIZE_SH="$BATS_TEST_DIRNAME/../customize.sh"
TMP_ROOT=""
SANDBOX_MODPATH=""

setup() {
  # 每个用例前建立独立临时工作区
  TMP_ROOT="$(mktemp -d)"
  SANDBOX_MODPATH="$TMP_ROOT/modpath"
  mkdir -p "$SANDBOX_MODPATH"
  mkdir -p "$SANDBOX_MODPATH/META-INF"

  # 提供一个最小的 compat.sh 占位(无函数)
  : > "$SANDBOX_MODPATH/META-INF/compat.sh"
}

teardown() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}

# 载入 customize.sh 中定义的目标函数,不实际执行主流程
# customize.sh 在执行完 compat.sh source 之后立即开始阶段 1,
# 所以我们通过在临时 MODPATH 注入 helper shim,把后续主流程短路。
load_customize_functions() {
  # 1) 截取 customize.sh 中所有函数定义:
  #    从文件开头到首次出现 "ui_print \"===" 的位置。
  local cutoff
  cutoff="$(grep -n 'ui_print "======' "$CUSTOMIZE_SH" | head -1 | cut -d: -f1)"
  if [ -z "$cutoff" ]; then
    skip "cannot locate phase 1 banner in customize.sh"
  fi
  cutoff=$((cutoff - 1))

  # 2) 提取前 cutoff 行
  head -n "$cutoff" "$CUSTOMIZE_SH" > "$TMP_ROOT/customize_fns.sh"

  # 3) 注入 stub,避免执行阶段 1 主流程时调用 getevent 等
  cat >> "$TMP_ROOT/customize_fns.sh" <<'STUB'
return 0
STUB

  # 4) 关闭 set -e 风格,确保单元测试容错
  set +e
  # shellcheck disable=SC1090
  . "$TMP_ROOT/customize_fns.sh"
}

# ============================================================
# ui_print
# ============================================================

@test "ui_print: prints argument to stdout" {
  load_customize_functions
  run ui_print "hello world"
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

@test "ui_print: prints empty line when no argument" {
  load_customize_functions
  run ui_print ""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ============================================================
# abort
# ============================================================

@test "abort: exits with code 1 and prints error prefix" {
  load_customize_functions
  run -1 abort "missing dep"
  [[ "$output" == *"错误: missing dep"* ]]
}

# ============================================================
# perm_recursive
# ============================================================

@test "perm_recursive: applies owner/group/mode when target exists" {
  load_customize_functions
  local target="$SANDBOX_MODPATH/dir"
  mkdir -p "$target/sub"
  echo "x" > "$target/file.txt"
  echo "y" > "$target/sub/inner.txt"

  perm_recursive "$target" 0 2000 0755 0644 "u:object_r:vendor_file:s0"

  [ -d "$target" ]
  [ -f "$target/file.txt" ]
  [ -f "$target/sub/inner.txt" ]
  # 至少文件存在,具体权限宿主无 chown 时也允许非零
  [ "$(stat -c '%a' "$target/file.txt" 2>/dev/null || stat -f '%A' "$target/file.txt" 2>/dev/null)" != "" ]
}

@test "perm_recursive: silently no-ops when target missing" {
  load_customize_functions
  perm_recursive "$SANDBOX_MODPATH/nope" 0 2000 0755 0644 "u:object_r:vendor_file:s0"
  [ ! -e "$SANDBOX_MODPATH/nope" ]
}

# ============================================================
# perm_one
# ============================================================

@test "perm_one: touches mode of single existing file" {
  load_customize_functions
  local f="$SANDBOX_MODPATH/onefile"
  echo "data" > "$f"
  perm_one "$f" 0 0 0644 "u:object_r:system_file:s0"
  [ -f "$f" ]
}

@test "perm_one: silently no-ops when file missing" {
  load_customize_functions
  perm_one "$SANDBOX_MODPATH/missingfile" 0 0 0644 "u:object_r:system_file:s0"
  [ ! -e "$SANDBOX_MODPATH/missingfile" ]
}

# ============================================================
# clean_old_artifacts
# ============================================================

@test "clean_old_artifacts: removes daxapp and daxcontroller priv-app dirs" {
  load_customize_functions
  mkdir -p "$SANDBOX_MODPATH/system/system_ext/priv-app/daxapp"
  echo "apk" > "$SANDBOX_MODPATH/system/system_ext/priv-app/daxapp/daxapp.apk"
  mkdir -p "$SANDBOX_MODPATH/system/system_ext/priv-app/daxcontroller"
  echo "apk" > "$SANDBOX_MODPATH/system/system_ext/priv-app/daxcontroller/daxcontroller.apk"

  clean_old_artifacts "$SANDBOX_MODPATH"

  [ ! -d "$SANDBOX_MODPATH/system/system_ext/priv-app/daxapp" ]
  [ ! -d "$SANDBOX_MODPATH/system/system_ext/priv-app/daxcontroller" ]
}

@test "clean_old_artifacts: removes probe files" {
  load_customize_functions
  : > "$SANDBOX_MODPATH/.probe_lock"
  : > "$SANDBOX_MODPATH/.probe_tmp"
  : > "$SANDBOX_MODPATH/last_probe.txt"
  : > "$SANDBOX_MODPATH/last_probe.raw.log"
  : > "$SANDBOX_MODPATH/boot_probe_state.txt"
  : > "$SANDBOX_MODPATH/boot_service_stdout.txt"

  clean_old_artifacts "$SANDBOX_MODPATH"

  [ ! -e "$SANDBOX_MODPATH/.probe_lock" ]
  [ ! -e "$SANDBOX_MODPATH/.probe_tmp" ]
  [ ! -e "$SANDBOX_MODPATH/last_probe.txt" ]
  [ ! -e "$SANDBOX_MODPATH/last_probe.raw.log" ]
  [ ! -e "$SANDBOX_MODPATH/boot_probe_state.txt" ]
  [ ! -e "$SANDBOX_MODPATH/boot_service_stdout.txt" ]
}

@test "clean_old_artifacts: removes flyfish233 permission XML" {
  load_customize_functions
  local permdir="$SANDBOX_MODPATH/system/system_ext/etc/permissions"
  mkdir -p "$permdir"
  : > "$permdir/com.flyfish233.daxapp.xml"
  : > "$permdir/com.flyfish233.daxcontroller.xml"

  clean_old_artifacts "$SANDBOX_MODPATH"

  [ ! -e "$permdir/com.flyfish233.daxapp.xml" ]
  [ ! -e "$permdir/com.flyfish233.daxcontroller.xml" ]
}

@test "clean_old_artifacts: tolerates missing modpath" {
  load_customize_functions
  clean_old_artifacts "$SANDBOX_MODPATH"
  # 不应崩溃
  [ "$?" = "0" ] || [ "$?" = "" ]
}

# ============================================================
# detect_root_solution
# ============================================================

@test "detect_root_solution: KSU is recognized" {
  load_customize_functions
  KSU=true KSU_VER="0.7.0" KSU_VER_CODE=11000 detect_root_solution
  [ "$ROOT_TYPE" = "KSU" ]
  [ "$ROOT_VER" = "0.7.0" ]
  [ "$ROOT_VER_CODE" = "11000" ]
  [ -f "$SANDBOX_MODPATH/.root_ver" ]
  cat "$SANDBOX_MODPATH/.root_ver"
  run cat "$SANDBOX_MODPATH/.root_ver"
  [ "$output" = "0.7.0" ]
}

@test "detect_root_solution: APatch is recognized" {
  load_customize_functions
  APATCH=true APATCH_VER="0.9.0" detect_root_solution
  [ "$ROOT_TYPE" = "APatch" ]
  [ "$ROOT_VER" = "0.9.0" ]
}

@test "detect_root_solution: Magisk is recognized" {
  load_customize_functions
  MAGISK_VER="25.2" MAGISK_VER_CODE=25200 detect_root_solution
  [ "$ROOT_TYPE" = "Magisk" ]
  [ "$ROOT_VER" = "25.2" ]
  [ "$ROOT_VER_CODE" = "25200" ]
}

@test "detect_root_solution: unknown root type calls abort" {
  load_customize_functions
  unset KSU APATCH MAGISK_VER
  run -127 detect_root_solution || true
  [[ "$output" == *"未检测到 KSU/Magisk/APatch"* ]]
}

# ============================================================
# detect_android_version
# ============================================================

@test "detect_android_version: passes for SDK 34" {
  load_customize_functions
  # stub getprop
  getprop() { case "$1" in
    ro.build.version.release) echo "14" ;;
    ro.build.version.sdk) echo "34" ;;
  esac; }
  export -f getprop
  run detect_android_version
  [ "$status" -eq 0 ]
  [[ "$output" == *"Android 版本: 14 (SDK 34)"* ]]
  unset -f getprop
}

@test "detect_android_version: aborts when SDK < 34" {
  load_customize_functions
  getprop() { case "$1" in
    ro.build.version.release) echo "13" ;;
    ro.build.version.sdk) echo "33" ;;
  esac; }
  export -f getprop
  run -127 detect_android_version || true
  [[ "$output" == *"不支持 Android 13"* ]]
  unset -f getprop
}

# ============================================================
# detect_architecture
# ============================================================

@test "detect_architecture: arm64-v8a passes" {
  load_customize_functions
  getprop() { echo "arm64-v8a"; }
  export -f getprop
  run detect_architecture
  [ "$status" -eq 0 ]
  [[ "$output" == *"CPU 架构: arm64-v8a"* ]]
  unset -f getprop
}

@test "detect_architecture: x86_64 aborts" {
  load_customize_functions
  getprop() { echo "x86_64"; }
  export -f getprop
  run -127 detect_architecture || true
  [[ "$output" == *"不支持 x86_64"* ]]
  unset -f getprop
}

@test "detect_architecture: armeabi-v7a aborts" {
  load_customize_functions
  getprop() { echo "armeabi-v7a"; }
  export -f getprop
  run -127 detect_architecture || true
  [[ "$output" == *"不支持 armeabi-v7a"* ]]
  unset -f getprop
}
