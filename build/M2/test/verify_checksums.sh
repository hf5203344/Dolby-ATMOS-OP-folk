#!/bin/sh
# verify_checksums.sh - 校验 Dolby M2 二进制 SHA256
# 用法: sh test/verify_checksums.sh
# 退出码: 0 = 全部 OK / SKIP; 1 = 任一 FAIL
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECKSUMS_FILE="${ROOT_DIR}/checksums.txt"

if [ ! -f "$CHECKSUMS_FILE" ]; then
    echo "ERROR: checksums.txt not found at ${CHECKSUMS_FILE}"
    exit 1
fi

# 检查 checksums.txt 是否还含 PENDING 占位
PENDING_COUNT=$(grep -c -E '^#\s*PENDING:' "$CHECKSUMS_FILE" || true)
ACTIVE_COUNT=$(grep -c -v -E '^\s*#' "$CHECKSUMS_FILE" | grep -v '^$' || true)
ACTIVE_COUNT=$(grep -E -v '^\s*(#|$)' "$CHECKSUMS_FILE" | wc -l | tr -d ' ')

if [ "$ACTIVE_COUNT" -eq 0 ]; then
    # 所有行都是注释 / PENDING 占位 -> SKIP
    echo "SKIP: binaries not yet extracted (all entries are PENDING placeholders)"
    echo "      see .binaries_pending for the extraction checklist"
    exit 0
fi

# 存在真实校验记录 -> 走 sha256sum 验证
PASS=0
FAIL=0
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

# 提取非注释行写入临时文件
grep -E -v '^\s*(#|$)' "$CHECKSUMS_FILE" > "$TMPFILE"

# 1. 路径修正:checksums.txt 中的相对路径以 ROOT_DIR 为基准
cd "$ROOT_DIR"

while IFS= read -r line; do
    # 格式: <sha256>  <filename> (双空格分隔)
    expected_sha=$(printf '%s\n' "$line" | awk '{print $1}')
    file_path=$(printf '%s\n' "$line" | awk '{print $2}')

    if [ -z "$expected_sha" ] || [ -z "$file_path" ]; then
        continue
    fi

    if [ ! -f "$file_path" ]; then
        echo "  [FAIL] ${file_path} (file not found)"
        FAIL=$((FAIL + 1))
        continue
    fi

    actual_sha=$(sha256sum "$file_path" | awk '{print $1}')
    if [ "$actual_sha" = "$expected_sha" ]; then
        echo "  [ OK ] ${file_path}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${file_path}"
        echo "         expected: ${expected_sha}"
        echo "         actual:   ${actual_sha}"
        FAIL=$((FAIL + 1))
    fi
done < "$TMPFILE"

echo
echo "=== Summary ==="
echo "  OK:   ${PASS}"
echo "  FAIL: ${FAIL}"
echo

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo "OK"
exit 0
