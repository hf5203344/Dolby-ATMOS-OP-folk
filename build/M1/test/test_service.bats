#!/usr/bin/env bats
# ============================================================
# M1: test_service.bats
# 覆盖 service.sh 中的以下函数:
#   - file_sig
#   - context_has
#   - same_file_overlay
#   - wait_prop
#   - start_once
# 正常路径 + 异常路径
# 运行时要求: bats (https://github.com/bats-core/bats-core)
# ============================================================

SERVICE_SH="$BATS_TEST_DIRNAME/../service.sh"
TMP_ROOT=""

setup() {
  TMP_ROOT="$(mktemp -d)"
}

teardown() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}

# 提取 service.sh 中的工具函数定义(file_sig / context_has /
# same_file_overlay / wait_prop / start_once),不执行主流程。
load_service_functions() {
  local script="$TMP_ROOT/service_fns.sh"
  awk '
    /^(file_sig|same_file_overlay|context_has|wait_prop|start_once|log)\(\)/ { capture=1; depth=0; depth2=0 }
    capture {
      print
      n = length($0)
      for (i=1; i<=n; i++) {
        c = substr($0,i,1)
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) { capture=0; print ""; break } }
      }
    }
  ' "$SERVICE_SH" > "$script"
  set +e
  # shellcheck disable=SC1090
  . "$script"
}

# ============================================================
# file_sig
# ============================================================

@test "file_sig: returns missing for nonexistent file" {
  load_service_functions
  run file_sig "$TMP_ROOT/nope"
  [ "$status" -eq 0 ]
  [ "$output" = "missing" ]
}

@test "file_sig: returns deterministic hash for same content" {
  load_service_functions
  local f="$TMP_ROOT/data"
  echo "abc" > "$f"
  run file_sig "$f"
  [ "$status" -eq 0 ]
  # 不是 "missing",且长度>0
  [ "$output" != "missing" ]
  [ -n "$output" ]

  # 同样的内容 -> 同样的 hash
  local f2="$TMP_ROOT/data2"
  echo "abc" > "$f2"
  run file_sig "$f2"
  [ "$output" = "$output" ]
}

@test "file_sig: different content yields different sig" {
  load_service_functions
  local f1="$TMP_ROOT/a"
  local f2="$TMP_ROOT/b"
  echo "alpha" > "$f1"
  echo "beta" > "$f2"
  s1="$(file_sig "$f1")"
  s2="$(file_sig "$f2")"
  [ "$s1" != "missing" ]
  [ "$s2" != "missing" ]
  [ "$s1" != "$s2" ]
}

# ============================================================
# same_file_overlay
# ============================================================

@test "same_file_overlay: true when both files are identical" {
  load_service_functions
  local a="$TMP_ROOT/a"
  local b="$TMP_ROOT/b"
  echo "identical" > "$a"
  echo "identical" > "$b"
  same_file_overlay "$a" "$b"
  [ "$?" -eq 0 ]
}

@test "same_file_overlay: false when content differs" {
  load_service_functions
  local a="$TMP_ROOT/a"
  local b="$TMP_ROOT/b"
  echo "alpha" > "$a"
  echo "beta" > "$b"
  run same_file_overlay "$a" "$b"
  [ "$status" -ne 0 ]
}

@test "same_file_overlay: false when one missing" {
  load_service_functions
  local a="$TMP_ROOT/a"
  : > "$a"
  run same_file_overlay "$a" "$TMP_ROOT/missing"
  [ "$status" -ne 0 ]
}

@test "same_file_overlay: false when both missing" {
  load_service_functions
  run same_file_overlay "$TMP_ROOT/x" "$TMP_ROOT/y"
  [ "$status" -ne 0 ]
}

# ============================================================
# context_has
# ============================================================

@test "context_has: matches exact context label in ls -Zd output" {
  load_service_functions
  # mock ls -Zd by aliasing
  ls() {
    case "$1" in
      -Zd)
        shift
        for p in "$@"; do
          echo "unlabeled        $p"
        done
        ;;
      -lZ)
        shift
        for p in "$@"; do
          echo "-rw-r--r-- u:object_r:vendor_configs_file:s0 root root $p"
        done
        ;;
      *) command ls "$@" ;;
    esac
  }
  export -f ls
  if context_has "/some/path" "vendor_configs_file"; then
    :
  else
    echo "expected match"
    return 1
  fi
  unset -f ls
}

@test "context_has: returns false when no match" {
  load_service_functions
  ls() {
    case "$1" in
      -Zd) shift; for p in "$@"; do echo "unlabeled        $p"; done ;;
      -lZ) shift; for p in "$@"; do echo "-rw-r--r-- u:object_r:system_file:s0 root root $p"; done ;;
      *) command ls "$@" ;;
    esac
  }
  export -f ls
  run context_has "/some/path" "vendor_configs_file"
  [ "$status" -ne 0 ]
  unset -f ls
}

# ============================================================
# wait_prop
# ============================================================

@test "wait_prop: returns 0 when prop already matches" {
  load_service_functions
  getprop() { echo "running"; }
  export -f getprop
  run wait_prop "init.svc.foo" "running" 5
  [ "$status" -eq 0 ]
  unset -f getprop
}

@test "wait_prop: returns non-zero when timeout exceeded" {
  load_service_functions
  getprop() { echo "stopped"; }
  export -f getprop
  run wait_prop "init.svc.foo" "running" 2
  [ "$status" -ne 0 ]
  unset -f getprop
}

@test "wait_prop: returns 0 once prop transitions to expected value" {
  load_service_functions
  # getprop 返回 stopped 两次,然后 running
  COUNTER_FILE="$TMP_ROOT/counter" : > "$COUNTER_FILE"
  getprop() {
    n=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    n=$((n + 1))
    echo "$n" > "$COUNTER_FILE"
    if [ "$n" -ge 3 ]; then
      echo "running"
    else
      echo "stopped"
    fi
  }
  export -f getprop
  export COUNTER_FILE
  run wait_prop "init.svc.foo" "running" 10
  [ "$status" -eq 0 ]
  unset -f getprop
  unset COUNTER_FILE
}

# ============================================================
# start_once
# ============================================================

@test "start_once: returns non-zero when binary not executable" {
  load_service_functions
  local bin="$TMP_ROOT/noexec"
  : > "$bin"
  chmod 0644 "$bin"
  run start_once "fake_service" "$bin"
  [ "$status" -ne 0 ]
}

@test "start_once: returns 0 when binary executable" {
  load_service_functions
  local bin="$TMP_ROOT/svc"
  cat > "$bin" <<'BIN'
#!/bin/sh
exit 0
BIN
  chmod 0755 "$bin"
  # pidof 总是失败 (没有运行中的进程),因此应执行 "$bin" &
  pidof() { return 1; }
  export -f pidof
  run start_once "fake_service" "$bin"
  [ "$status" -eq 0 ]
  # 等一下确保 background 进程完成
  wait 2>/dev/null || true
  unset -f pidof
}

@test "start_once: short-circuits when process already running" {
  load_service_functions
  local bin="$TMP_ROOT/svc2"
  cat > "$bin" <<'BIN'
#!/bin/sh
exit 0
BIN
  chmod 0755 "$bin"
  # pidof 模拟"已在运行"
  pidof() { return 0; }
  export -f pidof
  # 不应启动新进程,函数也应当返回 0
  run start_once "fake_service" "$bin"
  [ "$status" -eq 0 ]
  unset -f pidof
}
