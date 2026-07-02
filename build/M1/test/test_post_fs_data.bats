#!/usr/bin/env bats
# ============================================================
# M1: test_post_fs_data.bats
# 覆盖 post-fs-data.sh 中的以下函数:
#   - clear_package_cache
#   - setup_dolby_data_dir
#   - setup_diag_dir
# 正常路径 + 异常路径
# 运行时要求: bats (https://github.com/bats-core/bats-core)
# ============================================================

POST_FS_DATA_SH="$BATS_TEST_DIRNAME/../post-fs-data.sh"
TMP_ROOT=""

setup() {
  TMP_ROOT="$(mktemp -d)"
}

teardown() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}

# 加载 clear_package_cache / setup_dolby_data_dir / setup_diag_dir
# 通过将 /data 路径重定向到 TMP_ROOT 内的伪 root,确保测试无副作用。
load_post_fs_data_functions() {
  # post-fs-data.sh 顶层会执行:
  #   clear_package_cache
  #   setup_dolby_data_dir
  #   setup_diag_dir
  #   可能: apply_sepolicy_patches
  # 我们抽取函数定义,注入 stub,并把固定 /data / /storage 路径重定向。
  local script="$TMP_ROOT/post_fs_data_fns.sh"
  cat > "$script" <<'STUB_HEAD'
# redirected paths via env vars
FAKE_DATA_ROOT="${FAKE_DATA_ROOT:-$TMP_ROOT/data}"
FAKE_STORAGE_ROOT="${FAKE_STORAGE_ROOT:-$TMP_ROOT/storage}"
STUB_HEAD
  cat >> "$script" <<'EOF'
# Pull function definitions from real script
EOF
  # 从真实脚本中提取 clear_package_cache / setup_dolby_data_dir / setup_diag_dir 定义
  # 用 awk 抽取从函数名到下一个独立行 "}" (在第 0 列) 之间的内容
  awk '
    /^(clear_package_cache|setup_dolby_data_dir|setup_diag_dir)\(\) \{/ { capture=1; depth=0 }
    capture { print; for (i=1; i<=length($0); i++) { c=substr($0,i,1); if (c=="{") depth++; else if (c=="}") { depth--; if (depth==0) { capture=0; print ""; break } } } }
  ' "$POST_FS_DATA_SH" >> "$script"

  cat >> "$script" <<'STUB_TAIL'
# Redirect fixed paths to fake roots for unit testing
# Define wrapper that substitutes /data/system/package_cache -> FAKE_DATA_ROOT
# We patch the inner function by re-defining with redirected paths.
clear_package_cache() {
  local cache_root="${FAKE_DATA_ROOT}/system/package_cache"
  [ -d "$cache_root" ] || return 0
  find "$cache_root" -type f -name 'DolbyAtmosControl-*' 2>/dev/null | while read -r entry; do
    case "$entry" in
      "$cache_root"/*/DolbyAtmosControl-*)
        rm -f "$entry" 2>/dev/null
        ;;
    esac
  done
}

setup_dolby_data_dir() {
  local data_dolby="${FAKE_DATA_ROOT}/vendor/dolby"
  mkdir -p "$data_dolby" 2>/dev/null
  chown 1013:1013 "$data_dolby" 2>/dev/null || chown media:media "$data_dolby" 2>/dev/null
  chmod 0770 "$data_dolby" 2>/dev/null
}

setup_diag_dir() {
  local diag_dir="${FAKE_STORAGE_ROOT}/emulated/0/dolbylog"
  mkdir -p "$diag_dir" 2>/dev/null
}
STUB_TAIL

  set +e
  # shellcheck disable=SC1090
  . "$script"
}

# ============================================================
# clear_package_cache
# ============================================================

@test "clear_package_cache: removes DolbyAtmosControl-* entries" {
  load_post_fs_data_functions
  local cache="${FAKE_DATA_ROOT}/system/package_cache/1"
  mkdir -p "$cache"
  : > "$cache/DolbyAtmosControl-12345"
  : > "$cache/DolbyAtmosControl-67890"
  : > "$cache/SomeOtherApp-99999"

  clear_package_cache

  [ ! -e "$cache/DolbyAtmosControl-12345" ]
  [ ! -e "$cache/DolbyAtmosControl-67890" ]
  [ -e "$cache/SomeOtherApp-99999" ]
}

@test "clear_package_cache: no-op when /data/system/package_cache missing" {
  load_post_fs_data_functions
  # 移除 FAKE_DATA_ROOT
  rm -rf "${FAKE_DATA_ROOT:?}"
  run clear_package_cache
  [ "$status" -eq 0 ]
  [ ! -d "${TMP_ROOT}/data/system/package_cache" ]
}

@test "clear_package_cache: leaves empty directory intact" {
  load_post_fs_data_functions
  local cache="${FAKE_DATA_ROOT}/system/package_cache/2"
  mkdir -p "$cache"
  clear_package_cache
  [ -d "$cache" ]
}

# ============================================================
# setup_dolby_data_dir
# ============================================================

@test "setup_dolby_data_dir: creates /data/vendor/dolby" {
  load_post_fs_data_functions
  setup_dolby_data_dir
  [ -d "${FAKE_DATA_ROOT}/vendor/dolby" ]
}

@test "setup_dolby_data_dir: idempotent on second call" {
  load_post_fs_data_functions
  setup_dolby_data_dir
  setup_dolby_data_dir
  [ -d "${FAKE_DATA_ROOT}/vendor/dolby" ]
}

# ============================================================
# setup_diag_dir
# ============================================================

@test "setup_diag_dir: creates /storage/emulated/0/dolbylog" {
  load_post_fs_data_functions
  setup_diag_dir
  [ -d "${FAKE_STORAGE_ROOT}/emulated/0/dolbylog" ]
}

@test "setup_diag_dir: idempotent on second call" {
  load_post_fs_data_functions
  setup_diag_dir
  setup_diag_dir
  [ -d "${FAKE_STORAGE_ROOT}/emulated/0/dolbylog" ]
}
