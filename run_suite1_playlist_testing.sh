#!/usr/bin/env bash
# ==============================================================================
# Suite 1 — Automated Playlist Scenario Test Suite Runner
# Runs all testcases in testing/scenarios/testcases/playlists using testing/.env secrets
# Generates Handoff JSON & Markdown Test Report at testing/scenarios/testcases/playlists/test_results/
# ==============================================================================

set -euo pipefail

# Locate repository root and testing directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
TESTCASES_DIR="${SCRIPT_DIR}/scenarios/testcases/playlists"
RESULTS_DIR="${TESTCASES_DIR}/test_results"
WORK_DIR="${SCRIPT_DIR}/active_test_workspace"

# Terminal color codes for clear QA output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[SUITE-1 TEST] $1${NC}"
}

log_pass() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

log_fail() {
    echo -e "${RED}  ✗ $1${NC}" >&2
}

log_step() {
    echo -e "${YELLOW}[STEP] $1${NC}"
}

# ------------------------------------------------------------------------------
# Preflight Check: Generate & Load Environment Variables & Secrets
# ------------------------------------------------------------------------------
GEN_ENV_SCRIPT="${SCRIPT_DIR}/generate_env_file.sh"
if [[ -f "${GEN_ENV_SCRIPT}" ]]; then
    log_info "Running ${GEN_ENV_SCRIPT}..."
    bash "${GEN_ENV_SCRIPT}"
fi

log_info "Loading environment variables from ${ENV_FILE}"
if [[ ! -f "${ENV_FILE}" ]]; then
    echo -e "${RED}[ERROR] .env file not found at ${ENV_FILE}${NC}" >&2
    exit 1
fi

# Source .env file
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# Verify required secrets and variables
: "${DP1_FEED_BASE_URL:?Missing DP1_FEED_BASE_URL in .env}"
: "${DP1_PRIVATE_KEY:?Missing DP1_PRIVATE_KEY in .env}"
: "${DP1_CURATOR_KID:?Missing DP1_CURATOR_KID in .env}"

BIN="${REPO_ROOT}/dp1"

# Ensure CLI binary is built
if [[ ! -x "${BIN}" ]]; then
    log_info "Building dp1 CLI binary..."
    (cd "${REPO_ROOT}" && go build -o dp1 .)
fi

mkdir -p "${WORK_DIR}"
mkdir -p "${RESULTS_DIR}"

log_info "Environment loaded successfully."
log_info "Target Feed: ${DP1_FEED_BASE_URL}"
log_info "Curator DID Key: ${DP1_CURATOR_KID}"
echo "------------------------------------------------------------------------"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# JSON results buffer file
RESULTS_BUFFER="${WORK_DIR}/results_buffer.json"
echo "[]" > "${RESULTS_BUFFER}"

# Clean up working directory on exit
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# Helper function to append JSON test result
append_result() {
    local json_obj="$1"
    python3 -c "
import json, sys
data = json.loads(sys.argv[1])
with open('${RESULTS_BUFFER}', 'r+') as f:
    arr = json.load(f)
    arr.append(data)
    f.seek(0)
    json.dump(arr, f, indent=2)
    f.truncate()
" "$json_obj"
}

# Helper function to sanitize JSON strings for python
escape_json_val() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))"
}

# ------------------------------------------------------------------------------
# Discover and Execute All Test Cases in testcases directory
# ------------------------------------------------------------------------------
shopt -s nullglob
TEST_FILES=("${TESTCASES_DIR}"/*.json)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] No JSON playlist test cases found in ${TESTCASES_DIR}${NC}" >&2
    exit 1
fi

echo -e "${BLUE}Found ${#TEST_FILES[@]} test cases to run.${NC}\n"

for TEST_FILE in "${TEST_FILES[@]}"; do
    FILENAME=$(basename "${TEST_FILE}")
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "${YELLOW}========================================================================${NC}"
    echo -e "${YELLOW}Running Test Case [${TOTAL_TESTS}/${#TEST_FILES[@]}]: ${FILENAME}${NC}"
    echo -e "${YELLOW}========================================================================${NC}"

    # Prepare working file with environment variable substitution ($DP1_CURATOR_KID)
    WORKING_FILE="${WORK_DIR}/${FILENAME}"
    sed "s|\$DP1_CURATOR_KID|${DP1_CURATOR_KID}|g" "${TEST_FILE}" > "${WORKING_FILE}"

    TEST_FAILED=0
    LOG_DETAILS=""

    # Determine expectation categories based on filename or inline test metadata
    if [[ "${FILENAME}" =~ tampered|payload_hash_mismatch|invalid_signature ]]; then
        # ----------------------------------------------------------------------
        # Category: Tampered / Signature Mismatch (Validate: PASS, Verify: FAIL)
        # ----------------------------------------------------------------------
        log_step "Validation Check: Expecting PASS..."
        VAL_OUT=$("${BIN}" playlist validate "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist validate "${WORKING_FILE}" > /dev/null 2>&1; then
            log_pass "Schema Validation Passed as expected."
            LOG_DETAILS+="✓ Schema Validation Passed as expected.\n"
        else
            log_fail "Schema Validation Failed unexpectedly."
            LOG_DETAILS+="✗ Schema Validation Failed unexpectedly.\nCLI Output:\n${VAL_OUT}\n"
            TEST_FAILED=1
        fi

        log_step "Signature Verification Check: Expecting FAIL (Tampered Signature)..."
        VER_OUT=$("${BIN}" playlist verify "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist verify "${WORKING_FILE}" > /dev/null 2>&1; then
            log_fail "Signature Verification Passed unexpectedly on tampered signature."
            LOG_DETAILS+="✗ Signature Verification Passed unexpectedly on tampered signature.\nCLI Output:\n${VER_OUT}\n"
            TEST_FAILED=1
        else
            log_pass "Signature Verification Failed as expected (caught tampered signature)."
            LOG_DETAILS+="✓ Signature Verification Failed as expected (caught tampered signature).\nCLI Error Caught:\n${VER_OUT}\n"
        fi

        ESCAPED_LOG=$(echo -e "${LOG_DETAILS}" | escape_json_val)
        if [[ ${TEST_FAILED} -eq 0 ]]; then
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"tampered_signature\", \"status\": \"PASS\", \"schema_validated\": true, \"signature_verified\": false, \"expected_verification\": \"FAIL\", \"logs\": ${ESCAPED_LOG}}"
        else
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"tampered_signature\", \"status\": \"FAIL\", \"logs\": ${ESCAPED_LOG}}"
        fi

    elif [[ "${FILENAME}" =~ legacy ]]; then
        # ----------------------------------------------------------------------
        # Category: Legacy Signature v1.0 (Validate: PASS, Verify: FAIL without --pubkey)
        # ----------------------------------------------------------------------
        log_step "Validation Check: Expecting PASS..."
        VAL_OUT=$("${BIN}" playlist validate "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist validate "${WORKING_FILE}" > /dev/null 2>&1; then
            log_pass "Schema Validation Passed as expected for legacy playlist."
            LOG_DETAILS+="✓ Schema Validation Passed as expected for legacy playlist.\n"
        else
            log_fail "Schema Validation Failed unexpectedly."
            LOG_DETAILS+="✗ Schema Validation Failed unexpectedly.\nCLI Output:\n${VAL_OUT}\n"
            TEST_FAILED=1
        fi

        log_step "Signature Verification Check: Expecting FAIL (Requires --pubkey for legacy)..."
        VER_OUT=$("${BIN}" playlist verify "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist verify "${WORKING_FILE}" > /dev/null 2>&1; then
            log_fail "Signature Verification Passed unexpectedly without --pubkey."
            LOG_DETAILS+="✗ Signature Verification Passed unexpectedly without --pubkey.\n"
            TEST_FAILED=1
        else
            log_pass "Signature Verification Failed as expected without --pubkey."
            LOG_DETAILS+="✓ Signature Verification Failed as expected without --pubkey.\nCLI Error Caught:\n${VER_OUT}\n"
        fi

        ESCAPED_LOG=$(echo -e "${LOG_DETAILS}" | escape_json_val)
        if [[ ${TEST_FAILED} -eq 0 ]]; then
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"legacy_v1.0\", \"status\": \"PASS\", \"schema_validated\": true, \"signature_verified\": false, \"note\": \"legacy signature requires --pubkey\", \"logs\": ${ESCAPED_LOG}}"
        else
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"legacy_v1.0\", \"status\": \"FAIL\", \"logs\": ${ESCAPED_LOG}}"
        fi

    elif [[ "${FILENAME}" =~ invalid ]]; then
        # ----------------------------------------------------------------------
        # Category: Schema Invalid Testcases (Validate: FAIL)
        # ----------------------------------------------------------------------
        log_step "Validation Check: Expecting FAIL (Schema Violation)..."
        VAL_OUT=$("${BIN}" playlist validate "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist validate "${WORKING_FILE}" > /dev/null 2>&1; then
            log_fail "Schema Validation Passed unexpectedly on invalid payload."
            LOG_DETAILS+="✗ Schema Validation Passed unexpectedly on invalid payload.\n"
            TEST_FAILED=1
        else
            log_pass "Schema Validation Failed as expected."
            LOG_DETAILS+="✓ Schema Validation Failed as expected.\nSchema Error Caught:\n${VAL_OUT}\n"
        fi

        ESCAPED_LOG=$(echo -e "${LOG_DETAILS}" | escape_json_val)
        if [[ ${TEST_FAILED} -eq 0 ]]; then
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"negative_schema\", \"status\": \"PASS\", \"schema_validated\": false, \"expected_validation\": \"FAIL\", \"logs\": ${ESCAPED_LOG}}"
        else
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"negative_schema\", \"status\": \"FAIL\", \"logs\": ${ESCAPED_LOG}}"
        fi

    else
        # ----------------------------------------------------------------------
        # Category: Valid Playlist Testcases (Validate: PASS, Verify: PASS, Publish: PASS)
        # ----------------------------------------------------------------------
        FRESH_UUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
        SHORT_UUID="${FRESH_UUID:0:8}"
        FRESH_SLUG="test-${SHORT_UUID}"

        # Update ID & Slug dynamically so each test run publishes deterministically
        python3 -c "
import json, sys
with open('${WORKING_FILE}', 'r+') as f:
    data = json.load(f)
    data['id'] = '${FRESH_UUID}'
    data['slug'] = '${FRESH_SLUG}'
    f.seek(0)
    json.dump(data, f, indent=2)
    f.truncate()
" 2>/dev/null || true

        log_step "Signing playlist dynamically with curator key from .env..."
        SIGN_OUT=$("${BIN}" playlist sign "${WORKING_FILE}" -o "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist sign "${WORKING_FILE}" -o "${WORKING_FILE}" > /dev/null 2>&1; then
            log_pass "Signed playlist dynamically."
            LOG_DETAILS+="✓ Signed playlist dynamically.\n"
        else
            log_fail "Failed to sign playlist dynamically."
            LOG_DETAILS+="✗ Failed to sign playlist dynamically.\nOutput:\n${SIGN_OUT}\n"
            TEST_FAILED=1
        fi

        log_step "Validation Check: Expecting PASS..."
        VAL_OUT=$("${BIN}" playlist validate "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist validate "${WORKING_FILE}" > /dev/null 2>&1; then
            log_pass "Schema Validation Passed."
            LOG_DETAILS+="✓ Schema Validation Passed.\n"
        else
            log_fail "Schema Validation Failed."
            LOG_DETAILS+="✗ Schema Validation Failed.\nValidation Error:\n${VAL_OUT}\n"
            TEST_FAILED=1
        fi

        log_step "Signature Verification Check: Expecting PASS..."
        VER_OUT=$("${BIN}" playlist verify "${WORKING_FILE}" 2>&1 || true)
        if "${BIN}" playlist verify "${WORKING_FILE}" > /dev/null 2>&1; then
            log_pass "Signature Verification Passed."
            LOG_DETAILS+="✓ Signature Verification Passed.\n"
        else
            log_fail "Signature Verification Failed."
            LOG_DETAILS+="✗ Signature Verification Failed.\nVerification Error:\n${VER_OUT}\n"
            TEST_FAILED=1
        fi

        log_step "Feed Publish Check: Expecting HTTP 201 Created..."
        PUBLISH_RESP=$("${BIN}" --json playlist publish "${WORKING_FILE}" --feed-url "${DP1_FEED_BASE_URL}" 2>/dev/null || true)
        PLAYLIST_ID=$(echo "${PUBLISH_RESP}" | python3 -c "import sys, json; print(json.load(sys.stdin)['response']['id'])" 2>/dev/null || true)

        if [[ -n "${PLAYLIST_ID}" ]]; then
            log_pass "Published to Feed successfully (HTTP 201). Playlist ID: ${PLAYLIST_ID}"
            LOG_DETAILS+="✓ Published to Feed successfully (HTTP 201). Playlist ID: ${PLAYLIST_ID}\n"

            # GET from Feed & verify remote signature
            PLAYLIST_URL="${DP1_FEED_BASE_URL}/api/v1/playlists/${PLAYLIST_ID}"
            log_step "Remote Fetch & Re-verify Check: GET ${PLAYLIST_URL}..."
            HTTP_CODE=$(curl -s -o "${WORK_DIR}/remote_fetched.json" -w "%{http_code}" "${PLAYLIST_URL}")

            if [[ "${HTTP_CODE}" -eq 200 ]]; then
                log_pass "HTTP 200 OK received from Feed server."
                LOG_DETAILS+="✓ HTTP 200 OK received from Feed server.\n"
                REMOTE_VER_OUT=$("${BIN}" playlist verify "${PLAYLIST_URL}" 2>&1 || true)
                if "${BIN}" playlist verify "${PLAYLIST_URL}" > /dev/null 2>&1; then
                    log_pass "Remote URL Signature Re-verification Passed."
                    LOG_DETAILS+="✓ Remote URL Signature Re-verification Passed.\n"
                    ESCAPED_LOG=$(echo -e "${LOG_DETAILS}" | escape_json_val)
                    append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"positive_publish\", \"status\": \"PASS\", \"playlist_id\": \"${PLAYLIST_ID}\", \"playlist_url\": \"${PLAYLIST_URL}\", \"schema_validated\": true, \"signature_verified\": true, \"remote_reverified\": true, \"logs\": ${ESCAPED_LOG}}"
                else
                    log_fail "Remote URL Signature Re-verification Failed."
                    LOG_DETAILS+="✗ Remote URL Signature Re-verification Failed.\nRemote Error:\n${REMOTE_VER_OUT}\n"
                    TEST_FAILED=1
                fi
            else
                log_fail "Feed GET returned status ${HTTP_CODE}"
                LOG_DETAILS+="✗ Feed GET returned status ${HTTP_CODE}\nResponse:\n$(cat "${WORK_DIR}/remote_fetched.json")\n"
                TEST_FAILED=1
            fi
        else
            log_fail "Feed Publish Failed or could not extract Playlist ID."
            LOG_DETAILS+="✗ Feed Publish Failed.\nPublish Output:\n${PUBLISH_RESP}\n"
            echo "${PUBLISH_RESP}"
            TEST_FAILED=1
        fi

        if [[ ${TEST_FAILED} -ne 0 ]]; then
            ESCAPED_LOG=$(echo -e "${LOG_DETAILS}" | escape_json_val)
            append_result "{\"testcase\": \"${FILENAME}\", \"category\": \"positive_publish\", \"status\": \"FAIL\", \"logs\": ${ESCAPED_LOG}}"
        fi
    fi

    if [[ ${TEST_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}Result: PASS (${FILENAME})${NC}\n"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}Result: FAIL (${FILENAME})${NC}\n"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# ------------------------------------------------------------------------------
# Handoff Contract Output Generation (JSON & Markdown)
# ------------------------------------------------------------------------------
HANDOFF_FILE="${RESULTS_DIR}/suite1_playlist_handoff.json"
REPORT_MD_FILE="${RESULTS_DIR}/test_report.md"
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c '
import sys, json

buffer_file = sys.argv[1]
handoff_file = sys.argv[2]
report_md_file = sys.argv[3]
feed_base = sys.argv[4]
generated_at = sys.argv[5]
total_tests = int(sys.argv[6])
passed_tests = int(sys.argv[7])
failed_tests = int(sys.argv[8])

with open(buffer_file, "r") as f:
    results = json.load(f)

handoff = {
    "handoff_version": "1",
    "suite": "P2P-S1-PLAYLISTS",
    "feed_base": feed_base,
    "generated_at": generated_at,
    "summary": {
        "total_testcases": total_tests,
        "passed_testcases": passed_tests,
        "failed_testcases": failed_tests
    },
    "results": results
}

# Write Handoff JSON
with open(handoff_file, "w") as f:
    json.dump(handoff, f, indent=2)

# Write Markdown Test Report
md = []
md.append("# 🧪 Playlist Scenario Test Suite Execution Report\n")
md.append(f"**Execution Timestamp**: `{generated_at}`\\\n")
md.append(f"**Target Feed Server**: `{feed_base}`\\\n")
md.append(f"**Test Suite**: `Suite 1 — Playlist Scenario Test Vectors`\\\n")
md.append(f"**Handoff Contract File**: [`suite1_playlist_handoff.json`](file://{handoff_file})\n")
md.append("---\n")
md.append("## 📊 Execution Summary\n")
md.append("| Metric | Value |")
md.append("| :--- | :---: |")
md.append(f"| **Total Testcases** | `{total_tests}` |")
md.append(f"| **Passed** | `{passed_tests}` |")
md.append(f"| **Failed** | `{failed_tests}` |")
rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
md.append(f"| **Pass Rate** | **{rate:.1f}%** |\n")
md.append("---\n")
md.append("## 📋 Test Matrix Execution Results\n")
md.append("| ID | Testcase File | Category | Status | Resource / Details |")
md.append("| :--- | :--- | :--- | :---: | :--- |")

for idx, r in enumerate(results, start=1):
    tc = r.get("testcase", "")
    cat = r.get("category", "")
    st = r.get("status", "FAIL")
    st_icon = "🟢 PASS" if st == "PASS" else "🔴 FAIL"
    url = r.get("playlist_url", r.get("note", r.get("expected_validation", r.get("expected_verification", "N/A"))))
    md.append(f"| {idx} | `{tc}` | `{cat}` | {st_icon} | {url} |")

md.append("\n---\n")
md.append("## 🔍 Detailed Testcase Logs & Failure Diagnostics\n")

for idx, r in enumerate(results, start=1):
    tc = r.get("testcase", "")
    st = r.get("status", "FAIL")
    logs = r.get("logs", "No log captured.")
    st_icon = "🟢 PASS" if st == "PASS" else "🔴 FAIL"
    md.append(f"### {idx}. {st_icon}: `{tc}`\n")
    md.append("```text")
    md.append(logs.strip())
    md.append("```\n")

with open(report_md_file, "w") as f:
    f.write("\n".join(md))
' "${RESULTS_BUFFER}" "${HANDOFF_FILE}" "${REPORT_MD_FILE}" "${DP1_FEED_BASE_URL}" "${GENERATED_AT}" "${TOTAL_TESTS}" "${PASSED_TESTS}" "${FAILED_TESTS}"

log_info "Suite 1 Playlist Handoff Contract saved to ${HANDOFF_FILE}"
log_info "Markdown Test Execution Report saved to ${REPORT_MD_FILE}"
echo ""
cat "${HANDOFF_FILE}"
echo ""

# ------------------------------------------------------------------------------
# Final Test Summary Output
# ------------------------------------------------------------------------------
echo "========================================================================"
echo "                  PLAYLIST SCENARIO SUITE SUMMARY                       "
echo "========================================================================"
echo "Total Testcases Evaluated: ${TOTAL_TESTS}"
echo -e "Passed:                    ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed:                    ${RED}${FAILED_TESTS}${NC}"
echo "========================================================================"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    echo -e "${GREEN}ALL PLAYLIST SCENARIO TESTCASES PASSED SUCCESSFULLY!${NC}"
    exit 0
else
    echo -e "${RED}SOME PLAYLIST SCENARIO TESTCASES FAILED. CHECK LOGS ABOVE.${NC}"
    exit 1
fi
