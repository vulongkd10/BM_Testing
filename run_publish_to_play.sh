#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator: Publish-to-Play Full Pipeline
# Runs Suite 1 (Static Playlist Publish) -> Handoff -> Suite 3 (FF1 Device Playback)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTCASES_DIR="${SCRIPT_DIR}/scenarios/testcases/playlists"
RESULTS_DIR="${TESTCASES_DIR}/test_results"
WORK_DIR="${SCRIPT_DIR}/active_test_workspace"
mkdir -p "${RESULTS_DIR}" "${WORK_DIR}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PUBLISH-TO-PLAY] $1${NC}"; }
log_pass() { echo -e "${GREEN}  ✓ $1${NC}"; }
log_fail() { echo -e "${RED}  ✗ $1${NC}" >&2; }
log_step() { echo -e "${YELLOW}[STEP] $1${NC}"; }

echo -e "${BLUE}========================================================================${NC}"
echo -e "${BLUE}      PUBLISH-TO-PLAY FULL PIPELINE: SUITE 1 (PUBLISH) -> SUITE 3 (PLAY) ${NC}"
echo -e "${BLUE}========================================================================${NC}"

# ------------------------------------------------------------------------------
# STEP 1: RUN SUITE 1 (Publish Round-Trip)
# ------------------------------------------------------------------------------
log_step "STAGE 1: Executing Suite 1 (Publish Round-Trip)..."

S1_FAILED=0
"${SCRIPT_DIR}/run_suite1_playlist_testing.sh" || S1_FAILED=1

if [[ ${S1_FAILED} -ne 0 ]]; then
    log_fail "SUITE 1 FAILED! (Boundary Attribution: publish/feed)"
    log_info "Skipping Suite 3 playback execution per publish-to-play spec rules."
    echo "========================================================================"
    echo "  RUN FAILED AT BOUNDARY: publish/feed                                  "
    echo "========================================================================"
    exit 1
fi

log_pass "STAGE 1 PASSED: Suite 1 completed cleanly and emitted Handoff Contract."

# ------------------------------------------------------------------------------
# STEP 2: RUN SUITE 3 (FF1 Device Playback Round-Trip)
# ------------------------------------------------------------------------------
log_step "STAGE 2: Executing Suite 3 (FF1 Device Playback Round-Trip)..."

S3_FAILED=0
"${SCRIPT_DIR}/run_suite3_playback_testing.sh" || S3_FAILED=1

if [[ ${S3_FAILED} -ne 0 ]]; then
    log_fail "SUITE 3 FAILED! (Boundary Attribution: device/playback)"
    echo "========================================================================"
    echo "  RUN FAILED AT BOUNDARY: device/playback                               "
    echo "========================================================================"
    exit 1
fi

log_pass "STAGE 2 PASSED: Suite 3 verified FF1 playback log contract L1 -> L2 -> L3."

# ------------------------------------------------------------------------------
# STEP 3: MASTER RUN MANIFEST GENERATION
# ------------------------------------------------------------------------------
RUN_MANIFEST_FILE="${RESULTS_DIR}/publish_to_play_run_manifest.json"
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat <<EOF > "${RUN_MANIFEST_FILE}"
{
  "run_manifest_version": "1",
  "pipeline": "Publish-to-Play",
  "overall_status": "PASS",
  "generated_at": "${GENERATED_AT}",
  "suite_1": {
    "status": "PASS",
    "handoff": "suite1_playlist_handoff.json"
  },
  "suite_3": {
    "status": "PASS",
    "handoff": "suite3_playback_handoff.json"
  }
}
EOF

log_info "Master Run Manifest saved to ${RUN_MANIFEST_FILE}"

echo -e "${GREEN}========================================================================${NC}"
echo -e "${GREEN}  PUBLISH-TO-PLAY FULL PIPELINE PASSED (SUITE 1 + SUITE 3 GREEN)        ${NC}"
echo -e "${GREEN}========================================================================${NC}"
