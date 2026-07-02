#!/usr/bin/env bats
#
# test_decoder_xml.bats - Dolby M2 解码器 XML 测试
# 覆盖: 2 份 XML xmllint 零错误,关键节点 XPath 断言,损坏 XML 拒绝
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    ROOT_DIR="$(cd "$TEST_DIR/.." && pwd)"
    C2_XML="${ROOT_DIR}/system/odm/etc/media_codecs_c2.xml"
    VINTF_XML="${ROOT_DIR}/system/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml"
    VALIDATE_SH="${TEST_DIR}/validate_media_codecs.sh"
}

# 工具:去除注释后用 xpath 计算节点数
xpath_count() {
    local file="$1"
    local xpath="$2"
    sed -e 's/<!--.*-->//g' "$file" | xmllint --xpath "$xpath" - 2>/dev/null
}

# ---------------------------------------------------------------
# 1. 文件存在性
# ---------------------------------------------------------------

@test "M2 file: media_codecs_c2.xml exists" {
    [ -f "$C2_XML" ]
}

@test "M2 file: c2_manifest_vendor_audio.xml exists" {
    [ -f "$VINTF_XML" ]
}

# ---------------------------------------------------------------
# 2. xmllint well-formed
# ---------------------------------------------------------------

@test "xmllint: media_codecs_c2.xml has zero errors" {
    run xmllint --noout "$C2_XML"
    [ "$status" -eq 0 ]
}

@test "xmllint: c2_manifest_vendor_audio.xml has zero errors" {
    run xmllint --noout "$VINTF_XML"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------
# 3. media_codecs_c2.xml 关键节点
# ---------------------------------------------------------------

@test "c2 XML: c2.dolby.eac3.decoder present" {
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.eac3.decoder'])")" -eq 1 ]
}

@test "c2 XML: c2.dolby.ac4.decoder present" {
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.ac4.decoder'])")" -eq 1 ]
}

@test "c2 XML: 4 MIME types (audio/ac3, audio/eac3, audio/eac3-joc, audio/ac4) all present" {
    [ "$(xpath_count "$C2_XML" "count(//Type[@name='audio/ac3'])")" -eq 1 ]
    [ "$(xpath_count "$C2_XML" "count(//Type[@name='audio/eac3'])")" -eq 1 ]
    [ "$(xpath_count "$C2_XML" "count(//Type[@name='audio/eac3-joc'])")" -eq 1 ]
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.ac4.decoder'][@type='audio/ac4'])")" -eq 1 ]
}

@test "c2 XML: eac3 decoder declares software-codec attribute" {
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.eac3.decoder']/Attribute[@name='software-codec'])")" -eq 1 ]
}

@test "c2 XML: ac4 decoder declares software-codec attribute" {
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.ac4.decoder']/Attribute[@name='software-codec'])")" -eq 1 ]
}

@test "c2 XML: 4 MIME types all have OMX alias" {
    # audio/ac3, audio/eac3, audio/eac3-joc on eac3 decoder
    [ "$(xpath_count "$C2_XML" "count(//Type[@name='audio/ac3']/Alias[starts-with(@name,'OMX.')])")" -eq 1 ]
    [ "$(xpath_count "$C2_XML" "count(//Type[@name='audio/eac3']/Alias[starts-with(@name,'OMX.')])")" -eq 1 ]
    [ "$(xpath_count "$C2_XML" "count(//Type[@name='audio/eac3-joc']/Alias[starts-with(@name,'OMX.')])")" -eq 1 ]
    # audio/ac4 on ac4 decoder (Alias 是 MediaCodec 的子元素)
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.ac4.decoder']/Alias[starts-with(@name,'OMX.')])")" -eq 1 ]
}

@test "c2 XML: eac3 decoder declares 3 Limit tags (channel-count, sample-rate, bitrate)" {
    [ "$(xpath_count "$C2_XML" "count(//MediaCodec[@name='c2.dolby.eac3.decoder']/Type/Limit)")" -ge 3 ]
}

# ---------------------------------------------------------------
# 4. c2_manifest_vendor_audio.xml 关键节点
# ---------------------------------------------------------------

@test "vintf: HIDL IComponentStore default1 declared" {
    [ "$(xpath_count "$VINTF_XML" "count(//hal[@format='hidl']/fqname[contains(text(),'IComponentStore/default1')])")" -eq 1 ]
}

@test "vintf: HIDL IComponentStore default2 declared" {
    [ "$(xpath_count "$VINTF_XML" "count(//hal[@format='hidl']/fqname[contains(text(),'IComponentStore/default2')])")" -eq 1 ]
}

@test "vintf: AIDL IDms default declared" {
    [ "$(xpath_count "$VINTF_XML" "count(//hal[@format='aidl']/fqname[contains(text(),'IDms/default')])")" -eq 1 ]
}

@test "vintf: vendor.dolby.dms AIDL hal name" {
    [ "$(xpath_count "$VINTF_XML" "count(//hal[@format='aidl']/name[text()='vendor.dolby.dms'])")" -eq 1 ]
}

@test "vintf: android.hardware.media.c2 HIDL hal name" {
    [ "$(xpath_count "$VINTF_XML" "count(//hal[@format='hidl']/name[text()='android.hardware.media.c2'])")" -eq 1 ]
}

# ---------------------------------------------------------------
# 5. validate_media_codecs.sh 集成测试
# ---------------------------------------------------------------

@test "validate_media_codecs.sh: returns 0 on success" {
    run sh "$VALIDATE_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

# ---------------------------------------------------------------
# 6. 损坏 XML 必须被 xmllint 拒绝
# ---------------------------------------------------------------

@test "xmllint: rejects malformed XML (missing </Decoders>)" {
    BAD_XML=$(mktemp --suffix=.xml)
    cat > "$BAD_XML" <<'EOF'
<?xml version="1.0" encoding="utf-8" ?>
<Included>
    <Decoders>
        <MediaCodec name="broken.decoder" >
            <Type name="audio/test">
                <Limit name="channel-count" max="2" />
EOF
    # 文件故意缺少 </Type></MediaCodec></Decoders></Included> 闭合
    run xmllint --noout "$BAD_XML"
    rm -f "$BAD_XML"
    [ "$status" -ne 0 ]
}

@test "xmllint: rejects XML with unclosed MediaCodec tag" {
    BAD_XML=$(mktemp --suffix=.xml)
    cat > "$BAD_XML" <<'EOF'
<?xml version="1.0" encoding="utf-8" ?>
<Included>
    <Decoders>
        <MediaCodec name="broken.decoder">
        </Decoders>
</Included>
EOF
    run xmllint --noout "$BAD_XML"
    rm -f "$BAD_XML"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------
# 7. 占位文件存在性
# ---------------------------------------------------------------

@test "M2 file: .binaries_pending exists" {
    [ -f "${ROOT_DIR}/.binaries_pending" ]
}

@test "M2 file: checksums.txt exists with PENDING placeholders" {
    [ -f "${ROOT_DIR}/checksums.txt" ]
    grep -q "PENDING" "${ROOT_DIR}/checksums.txt"
}

@test "M2 file: checksums.txt lists 7 entries (6 .so + 1 service)" {
    # 统计 PENDING 条目数
    count=$(grep -c -E '^#\s*PENDING:' "${ROOT_DIR}/checksums.txt")
    [ "$count" -eq 7 ]
}
