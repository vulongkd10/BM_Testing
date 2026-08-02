# DP-1 Playlist Scenario Test Cases

This directory contains test cases for validating and verifying DP-1 playlist documents across CLI, Feed Server, and Player implementations.

## Test Matrix Index

| ID | File | Category | `dp1 playlist validate` | `dp1 playlist verify` | `dp1 playlist publish` | Description / Feature Coverage |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **TC01** | [`tc_01_valid_minimal.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_01_valid_minimal.json) | Positive / Required Fields | **PASS** | **PASS** (Signed) | **PASS** (HTTP 201) | Minimal valid DP-1 playlist (`dpVersion`, `id`, `title`, 1 `item` with `id`, `source`, `duration`, `license`). |
| **TC02** | [`tc_02_valid_full_featured.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_02_valid_full_featured.json) | Positive / Advanced Optional | **PASS** | **PASS** (Signed) | **PASS** (HTTP 201) | Full featured playlist (`defaults`, `display`, `repro`, `provenance`, `curators`). |
| **TC03** | [`tc_03_invalid_missing_title.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_03_invalid_missing_title.json) | Negative / Required Field | **FAIL** | **FAIL** | N/A | Missing top-level required property `title`. |
| **TC04** | [`tc_04_invalid_empty_items.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_04_invalid_empty_items.json) | Negative / Array Bounds | **FAIL** | **FAIL** | N/A | Empty `items: []` array (violates `minItems: 1`). |
| **TC05** | [`tc_05_invalid_version_format.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_05_invalid_version_format.json) | Negative / Format Validation | **FAIL** | **FAIL** | N/A | Invalid `dpVersion: "1.1"` format (violates SemVer regex `^\d+\.\d+\.\d+$`). |
| **TC06** | [`tc_06_invalid_display_margin_unit.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_06_invalid_display_margin_unit.json) | Negative / Format Validation | **FAIL** | **FAIL** | N/A | Invalid margin unit `"10em"` in display preferences (allowed: `px`, `%`, `vw`, `vh`). |
| **TC07** | [`tc_07_invalid_display_scaling_enum.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_07_invalid_display_scaling_enum.json) | Negative / Enum Constraint | **FAIL** | **FAIL** | N/A | Invalid scaling mode `"zoom"` in display preferences (allowed: `"fit"`, `"fill"`, `"stretch"`, `"auto"`). |
| **TC08** | [`tc_08_invalid_provenance_missing_contract.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_08_invalid_provenance_missing_contract.json) | Negative / Conditional Schema | **FAIL** | **FAIL** | N/A | Provenance of type `"onChain"` missing mandatory `"contract"` block (`allOf/if/then`). |
| **TC09** | [`tc_09_invalid_missing_signatures.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_09_invalid_missing_signatures.json) | Negative / Schema Constraint | **FAIL** | **FAIL** | N/A | Unsigned document missing both `signatures` and legacy `signature` fields (`anyOf` condition). |
| **TC10** | [`tc_10_invalid_signature_payload_hash_mismatch.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_10_invalid_signature_payload_hash_mismatch.json) | Negative / Cryptographic | **PASS** | **FAIL** | N/A | Schema valid, but `payload_hash` and Base64url signature do not match the payload. |
| **TC11** | [`tc_11_valid_defaults_inheritance.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_11_valid_defaults_inheritance.json) | Positive / Inheritance | **PASS** | **PASS** (Signed) | **PASS** (HTTP 201) | Valid inheritance test vector where item inherits top-level `defaults` (display/duration/license). |
| **TC12** | [`tc_12_valid_legacy_signature.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_12_valid_legacy_signature.json) | Positive / Backward Compat | **PASS** | **FAIL** (Requires `--pubkey`) | N/A | Legacy single `"signature": "ed25519:..."` format for v1.0.x backward compatibility. |
| **TC13** | [`tc_13_invalid_missing_item_source.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_13_invalid_missing_item_source.json) | Negative / Item Required Field | **FAIL** | **FAIL** | N/A | Missing mandatory `source` URI in playlist item object. |
| **TC14** | [`tc_14_invalid_license_enum.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_14_invalid_license_enum.json) | Negative / Enum Constraint | **FAIL** | **FAIL** | N/A | Invalid license `"creative-commons"` (allowed: `"open"`, `"closed"`). |
| **TC15** | [`tc_15_valid_extensions_note_and_dynamic_query.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_15_valid_extensions_note_and_dynamic_query.json) | Positive / Extensions | **PASS** | **PASS** (Signed) | **PASS** (HTTP 201) | Exercises top-level & item-level `note` objects, `summary`, `coverImage`, item `ref`, and `dynamicQuery`. |
| **TC16** | [`tc_16_invalid_uuid_format.json`](file:///Users/longvu-macmini/Documents/BM/repos/dp1-cli/testing/scenarios/testcases/playlists/tc_16_invalid_uuid_format.json) | Negative / UUID Format | **FAIL** | **FAIL** | N/A | Invalid UUID string format `"invalid-uuid-12345"` on top-level `id`. |

---

## How to Run Test Suite

Using the automated runner script:

```bash
./testing/run_suite1_playlist_testing.sh
```

All 16 test cases in `testing/scenarios/testcases/playlists` are discovered automatically and evaluated against schema and cryptographic boundaries!
