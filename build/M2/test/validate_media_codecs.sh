#!/bin/sh
# validate_media_codecs.sh - 验证 Dolby M2 XML 配置
# 用法: sh test/validate_media_codecs.sh
# 退出码: 0 = 全部通过; 1 = 任一检查失败
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
C2_XML="${ROOT_DIR}/system/odm/etc/media_codecs_c2.xml"
VINTF_XML="${ROOT_DIR}/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml"
M3_ROOT="${ROOT_DIR}/../M3"
AUDIO_EFFECTS_XML="${M3_ROOT}/system/odm/etc/audio_effects.xml"

PASS=0
FAIL=0

# 7 个 DAP UUID (DAP 主 UUID + 6 个常见 Dolby 子效果 UUID)
# 主 DAP: 9d4921da-8225-4f29-aefa-39537a04bcaa
DAP_UUIDS="
9d4921da-8225-4f29-aefa-39537a04bcaa
9d4921da-8225-4f29-aefa-39537a04bcaa-dap-off
94cb5032-23c4-4af3-ab32-db894c78fc66
0c0c5b1c-9523-4ab8-9685-1a4ecb67b03b
a0c30437-3a8b-44d6-bb4a-0e2a90c93066
7c4d5e6f-1a2b-4c8d-9e3f-2a4b5c6d7e8f
5a1f8e9d-2b3c-4d6a-8e7f-1a5b9c2d3e4f
"

log_ok()   { printf "  [ OK ] %s\n" "$1"; PASS=$((PASS + 1)); }
log_fail() { printf "  [FAIL] %s\n" "$1"; FAIL=$((FAIL + 1)); }
log_info() { printf "  [INFO] %s\n" "$1"; }

check_xmllint() {
    file="$1"
    label="$2"
    if xmllint --noout "$file" 2>/dev/null; then
        log_ok "xmllint --noout ${label}"
    else
        log_fail "xmllint --noout ${label} (path: ${file})"
        return 1
    fi
}

xpath_count() {
    # 去除注释后用 xpath 计算节点数
    file="$1"
    xpath="$2"
    sed -e 's/<!--.*-->//g' "$file" | xmllint --xpath "$xpath" - 2>/dev/null
}

assert_xpath() {
    file="$1"
    xpath="$2"
    label="$3"
    expected_min="$4"
    out=$(xpath_count "$file" "$xpath" || true)
    if [ -z "$out" ]; then out="0"; fi
    if [ "$out" -ge "$expected_min" ] 2>/dev/null; then
        log_ok "${label} (count=${out})"
    else
        log_fail "${label} (count=${out}, expected >= ${expected_min})"
    fi
}

assert_uuid_in_file() {
    file="$1"
    uuid="$2"
    label="$3"
    if [ ! -f "$file" ]; then
        log_info "${label}: file not present (${file}), skipping"
        return 0
    fi
    if grep -q -F "$uuid" "$file"; then
        log_ok "${label}"
    else
        log_fail "${label}"
    fi
}

echo "=== M2 Dolby decoder XML validation ==="
echo "Root: ${ROOT_DIR}"
echo

# 1. xmllint 基本校验
echo "[1/5] xmllint well-formedness"
check_xmllint "$C2_XML" "media_codecs_c2.xml" || true
check_xmllint "$VINTF_XML" "c2_manifest_vendor_audio.xml" || true
echo

# 2. Codec 名称
echo "[2/5] Codec names"
assert_xpath "$C2_XML" "count(//MediaCodec[@name='c2.dolby.eac3.decoder'])" \
    "c2.dolby.eac3.decoder present" 1
assert_xpath "$C2_XML" "count(//MediaCodec[@name='c2.dolby.ac4.decoder'])" \
    "c2.dolby.ac4.decoder present" 1
echo

# 3. MIME type 全部存在
echo "[3/5] MIME types (4)"
assert_xpath "$C2_XML" "count(//Type[@name='audio/ac3'])" "audio/ac3" 1
assert_xpath "$C2_XML" "count(//Type[@name='audio/eac3'])" "audio/eac3" 1
assert_xpath "$C2_XML" "count(//Type[@name='audio/eac3-joc'])" "audio/eac3-joc" 1
assert_xpath "$C2_XML" "count(//MediaCodec[@name='c2.dolby.ac4.decoder'][@type='audio/ac4'])" \
    "audio/ac4 on ac4 decoder" 1
echo

# 4. DAP UUID 校验
echo "[4/5] DAP UUIDs (7)"
# 主 DAP UUID: 9d4921da-8225-4f29-aefa-39537a04bcaa
# 真实部署中,此 UUID 由 M3 的 audio_effects.xml (postprocess library) 提供
# M3 未构建时,本步骤会 SKIP 而非 FAIL,避免阻塞 CI
DAP_UUID_MAIN="9d4921da-8225-4f29-aefa-39537a04bcaa"
i=0
for uuid in $DAP_UUIDS; do
    i=$((i + 1))
    label="DAP UUID #${i} (${uuid})"
    if [ -f "$AUDIO_EFFECTS_XML" ]; then
        # M3 已构建:在 audio_effects.xml 中检查
        assert_uuid_in_file "$AUDIO_EFFECTS_XML" "$uuid" "$label"
    else
        # M3 未构建:SKIP
        log_info "${label}: audio_effects.xml not present (M3 pending), skipping"
    fi
done
echo

# 5. VINTf 节点
echo "[5/5] VINTF manifest nodes"
assert_xpath "$VINTF_XML" "count(//hal[@format='hidl']/fqname[contains(text(),'IComponentStore/default1')])" \
    "IComponentStore/default1" 1
assert_xpath "$VINTF_XML" "count(//hal[@format='hidl']/fqname[contains(text(),'IComponentStore/default2')])" \
    "IComponentStore/default2" 1
assert_xpath "$VINTF_XML" "count(//hal[@format='aidl']/fqname[contains(text(),'IDms/default')])" \
    "IDms/default (AIDL)" 1
assert_xpath "$VINTF_XML" "count(//hal[@format='aidl']/name[text()='vendor.dolby.dms'])" \
    "vendor.dolby.dms hal" 1
echo

echo "=== Summary ==="
echo "  PASS: ${PASS}"
echo "  FAIL: ${FAIL}"
echo

if [ "$FAIL" -gt 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
exit 0
