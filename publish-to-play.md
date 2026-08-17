## Publish-to-Play thin-slice spec — Suite 1 → Suite 3 (source of truth)

**Status:** Design agreed for first implementation  
**Scope:** CLI-origin publish → FF1 playback only  
**Owners:** @jollyjoker992 (Suite 1), @lpopo0856 (Suite 3)  
**Out of scope (this slice):** Suite 2 (indexer build), Suite 4 (app/controller), relayer path, multi-item advance, soak tests

This comment is the **source of truth** for the first wired implementation. Suites 1 and 3 run as one pipeline with a shared handoff contract.

---

### System under test

```
[Suite 1]  dp1-cli → dp1-feed-v2          (publish boundary)
              ↓ published_playlist_url
[Suite 3]  hub WS → feral-controld → FF1   (playback boundary)
```

---

## Suite 1 — Static playlist publish round-trip (`P2P-S1`)

| Field | Value |
|-------|-------|
| **Steward** | @jollyjoker992 |
| **Boundary** | DP-1 protocol correctness + `dp1-cli` → `dp1-feed-v2` contract |
| **Proves** | A pre-built, signed DP-1 v1.1.0 playlist can be validated, published, fetched from the feed, and re-verified |
| **Does not prove** | Indexer resolution, ff-cli build, app cast, relayer, device playback |

### Fixture (wired run — v1)

| ID | File | Validation path | Exercises |
|----|------|-----------------|-----------|
| **C01** | `core-static.json` | Core (`ParseAndValidatePlaylist`) | `id` / `slug` / `created`, 2 static items, mixed `license`, simple `display`, Ed25519 `curator` sig |

> **E01** (`extension-static.json`) remains a **parallel Suite-1-only daily check** in v1. It is **not** passed to Suite 3 until C01→Suite 3 is stable.

### Steps

| Step | Action | Pass condition |
|------|--------|----------------|
| S1-1 | `dp1 playlist validate` on C01 | Exit 0; no schema errors |
| S1-2 | `dp1 playlist verify` on C01 | Exit 0; signatures valid |
| S1-3 | `dp1 playlist publish` → feed | HTTP **201 Created**; response includes playlist `id` |
| S1-4 | `GET /api/v1/playlists/{id}` | HTTP 200; body matches published playlist |
| S1-5 | `dp1 playlist verify` on fetched body | Exit 0; signatures still valid after round-trip |

### Failure attribution

| Failing step | Likely boundary |
|--------------|-----------------|
| S1-1 or S1-2 | DP-1 schema / signing / fixture drift |
| S1-3 | `dp1-cli` publish client or feed POST handler |
| S1-4 or S1-5 | `dp1-feed-v2` storage or GET semantics |

### Handoff output (Suite 1 → Suite 3)

On pass, Suite 1 **must** emit:

| Field | Description |
|-------|-------------|
| `playlist_id` | DP-1 playlist `id` from publish response |
| `playlist_url` | `{FEED_BASE}/api/v1/playlists/{id}` |
| `fixture_id` | `C01` |
| `published_at` | ISO-8601 timestamp |
| `feed_base` | Feed environment used |

---

## Suite 3 — FF1 device playback round-trip (`P2P-S3`)

| Field | Value |
|-------|-------|
| **Steward** | @lpopo0856 |
| **Boundary** | `feral-controld` / FF1 player |
| **Proves** | A feed-published playlist can be cast to a real FF1 and playback is confirmed from structured logs |
| **Transport** | Local hub WebSocket (`ws://<device>:1111`, `enableHub=true`) — same `commandrouter` as production, cloud-independent for daily determinism |
| **Does not prove** | Relayer handoff, app/controller path, multi-item advance, rotation/scaling |

### Preconditions (environment)

| Requirement | Notes |
|-------------|-------|
| Dedicated staging FF1 | Pinned `device_id`, always-on, `enableHub=true` |
| `feral-controld` log contract | 3 stable, greppable log lines (below) |
| Network reachability | CI runner can reach device hub WS + journald |
| Default playlist fixture | Distinct from C01, for reset-first |

### Log contract (pass-gate assertions)

| # | Log `msg` | Fields | Nature |
|---|-----------|--------|--------|
| L1 | `Display playlist command received` | `playlist_url` | Per-cast |
| L2 | `Playback verified` | `playlist_id`, `ok: true` | Per-cast — player sync ack |
| L3 | `Playlist switched` | `from`, `to` | On **playlist-identity change** (not play-state transition) |

**Diagnostic (not pass-gate):** `Processing/Fetching playlist from URL`, `Playback verification failed: player did not respond with ok`, hub `/metrics` (`playback_start_failures_total`, `art_playback_duration_seconds_total`).

### Steps

| Step | Action | Pass condition |
|------|--------|----------------|
| S3-0 | Read `playlist_url` from Suite 1 handoff | Handoff present and valid |
| S3-1 | Cast `CMD_DISPLAY_DEFAULT_PLAYLIST` via hub WS | Device reaches stable non-target state |
| S3-2 | Cast target `playlist_url` via hub WS (`CMD_DISPLAY_PLAYLIST`) | Command accepted |
| S3-3 | Within **N = 60s**, assert log sequence L1 → L2 → L3 | All three present; `playlist_url` / `to` match target |
| S3-4 | Capture supporting evidence | CDP screenshot + `PlayerStatus` JSON + metrics snapshot |

### Pass definition

**PASS** = within 60s, for the **same** `playlist_id`:

1. L1: `playlist_url` == Suite 1 `playlist_url`
2. L2: `ok: true`
3. L3: `to` == Suite 1 `playlist_url`

### Failure attribution

| Symptom | Likely boundary |
|---------|-----------------|
| S3-0 fails (no handoff) | Orchestrator / Suite 1 did not complete |
| No L1 | Hub / command routing |
| L1 present, stuck after dp1 `Processing/Fetching` | Playlist resolution (device-side fetch) |
| `Playback verification failed` or no L2 | FF1 player |
| L2 ok, no L3 | Player render (acked but content didn't switch) |
| L3 `to` mismatch | Wrong playlist played |

### Suite 3 outputs

| Field | Description |
|-------|-------------|
| `playback_verified` | `true` / `false` |
| `log_assertions` | Which of L1/L2/L3 passed, with timestamps |
| `screenshot_path` | CDP wall capture |
| `player_status` | `PlayerStatus` JSON at assert time |
| `metrics_delta` | Before/after hub metrics |
| `journal_window` | Path to captured journald excerpt |

---

## Wiring — how the suites connect

### Orchestration model

One **run** = one **Run Manifest** flowing through both suites sequentially. Suite 3 never publishes its own fixture.

```
┌─────────────────────────────────────────────────────────┐
│  Run Manifest (created at start, updated per suite)     │
├─────────────────────────────────────────────────────────┤
│  run_id, started_at, environment, overall_status      │
│  suite_1: { status, steps[], handoff{} }              │
│  suite_3: { status, steps[], evidence{} }             │
└─────────────────────────────────────────────────────────┘
```

### Handoff contract (sole coupling between suites)

Suite 3 starts only if `suite_1.status == passed` and `suite_1.handoff` is populated.

```json
{
  "handoff_version": "1",
  "playlist_id": "<from S1-3>",
  "playlist_url": "<FEED_BASE>/api/v1/playlists/<id>",
  "fixture_id": "C01",
  "feed_base": "<staging feed URL>",
  "published_at": "<ISO-8601>"
}
```

**Seamlessness rules:**

- Suite 3 receives `playlist_url` — not a local file, not a re-built playlist.
- One published playlist per run (C01). No re-publish in Suite 3.
- If Suite 1 fails → Suite 3 is **skipped** (not failed).
- If Suite 1 passes but Suite 3 fails → overall run **failed** at boundary `device/playback`.

### Run sequence

```
START → Create Run Manifest
  → SUITE 1 (S1-1..S1-5) → write handoff
      → on fail: SKIP suite 3 → REPORT
  → SUITE 3 (S3-0..S3-4)
      → on fail → REPORT
  → REPORT (always): write manifest, upload artifacts, set CI conclusion
END
```

### Reset-first (required)

Suite 3 **must** cast a default/blank playlist (S3-1) before the target (S3-2). Without this, casting a playlist already on screen is a no-op and L3 never fires → false pass risk.

---

## Expectations per run

### Overall outcomes

| Outcome | Condition | CI result | Boundary |
|---------|-----------|-----------|----------|
| **PASS** | Suite 1 + Suite 3 passed | Green | — |
| **FAIL — publish** | Suite 1 failed | Red | `publish/feed` |
| **FAIL — playback** | Suite 1 passed, Suite 3 failed | Red | `device/playback` |
| **INFRA** | Runner/device unreachable, secrets missing | Red | `infra` |

### Timing budget

| Phase | Budget |
|-------|--------|
| Suite 1 (S1-1..S1-5) | ≤ 30s |
| Suite 3 reset (S3-1) | ≤ 30s |
| Suite 3 playback assert (S3-3) | ≤ 60s |
| Evidence capture (S3-4) | ≤ 15s |
| **Total run** | ≤ 3 min (excluding CI setup) |

### Feature snapshot (what this slice claims)

- DP-1 v1.1.0 core validation path (C01)
- `dp1-cli` validate / verify / publish against live feed
- Feed round-trip (POST → GET → re-verify signatures)
- Hub-direct cast of a feed URL to a real FF1
- `feral-controld` playlist switch + player ack

**Not claimed:** extension-composed playlists (E01 wired path), indexer build, app cast, relayer, dynamic queries, multi-item loop.

---

## CI pipeline

| Field | Value |
|-------|-------|
| **Workflow** | `publish-to-play-smoke` |
| **Trigger** | `cron: 0 7 * * *` (daily 07:00 UTC) + `workflow_dispatch` |
| **Runner** | Self-hosted or VPN-connected — must reach staging FF1 hub + journald |
| **Concurrency** | `max-parallel: 1` per device |
| **Timeout** | 10 min job-level |
| **Required on PRs** | No (nightly only in v1; promote after 2 weeks green) |

### Stages

```
Setup → Suite 1 (publish) → Suite 3 (play) → Report
```

| Stage | Gate | On failure |
|-------|------|------------|
| **Setup** | Secrets present; hub WS connect + `/metrics` 200 | `infra`; skip both suites |
| **Suite 1** | S1-1..S1-5 pass | `publish/feed`; skip Suite 3 |
| **Suite 3** | S3-0..S3-4 pass | `device/playback` |
| **Report** | Always runs | Upload artifacts; set check conclusion |

### Secrets / environment

| Secret / var | Used by | Purpose |
|--------------|---------|---------|
| `SMOKE_CURATOR_SIGNING_KEY` | Suite 1 | Sign C01 fixture |
| `DP1_FEED_BASE_URL` | Suite 1 | Staging feed endpoint |
| `SMOKE_FF1_HUB_WS` | Suite 3 | e.g. `ws://10.x.x.x:1111` |
| `SMOKE_FF1_DEVICE_ID` | Suite 3 | Pinned device |
| `SMOKE_FF1_SSH_HOST` | Suite 3 | journald access |
| `SMOKE_FF1_CDP_URL` | Suite 3 | Screenshot capture |

Feed = **staging**. Device = **staging FF1** pinned build. Both recorded in manifest `environment` block.

---

## Reporting

### Outputs (every run)

| Output | Location | Format | Retention |
|--------|----------|--------|-----------|
| **Run Manifest** | `reports/{run_id}/manifest.json` | JSON | 90 days |
| **Human summary** | `reports/{run_id}/summary.md` | Markdown | 90 days |
| **CI artifacts** | GHA `upload-artifact` | Zip of `reports/{run_id}/` | 30 days |
| **GitHub Step Summary** | `$GITHUB_STEP_SUMMARY` | Markdown table | Per-run |
| **Issue comment** | This issue (on failure, v1) | Markdown | Permanent |

### Run Manifest (final shape)

```json
{
  "run_id": "2026-07-08T07:00:00Z",
  "workflow": "publish-to-play-smoke",
  "slice": "S1+S3",
  "environment": {
    "feed": "staging",
    "device_id": "smoke-ff1-staging",
    "ff1_build": "<pinned image tag>"
  },
  "overall_status": "passed | failed | infra_error",
  "failed_boundary": null,
  "duration_ms": 95000,
  "suite_1": {
    "status": "passed",
    "fixture": "C01",
    "steps": [
      { "id": "S1-1", "status": "passed", "duration_ms": 1200 },
      { "id": "S1-3", "status": "passed", "duration_ms": 2100, "playlist_id": "…" }
    ],
    "handoff": { "playlist_url": "…", "playlist_id": "…", "fixture_id": "C01" }
  },
  "suite_3": {
    "status": "passed",
    "steps": [
      { "id": "S3-3", "status": "passed", "duration_ms": 8500,
        "assertions": { "L1": true, "L2": true, "L3": true } }
    ],
    "evidence": {
      "screenshot": "reports/…/wall.png",
      "player_status": "reports/…/player_status.json",
      "journal_excerpt": "reports/…/journal.jsonl"
    }
  }
}
```

### Failure artifacts (required on non-pass)

- Full Run Manifest
- Suite 1: fixture + CLI stdout/stderr; feed GET body on S1-4/5 fail
- Suite 3: `journalctl -u feral-controld -o json` for test window
- Suite 3: CDP screenshot at timeout
- Suite 3: `PlayerStatus` JSON
- Suite 3: hub `/metrics` before/after

---

## Expansion hooks (designed in, not built yet)

| Future addition | How it plugs in |
|-----------------|-----------------|
| **E01 wired** | Alternate fixture selector; same handoff shape |
| **Suite 2** | Replaces Suite 1 publish source (`source: indexer-build`); same handoff |
| **Suite 4** | New `suite_4` block; reads same `handoff.playlist_id`; Suite 3 → `observe` mode |
| **Relayer path** | New transport flag on Suite 3; same log assertions |

---

## Acceptance criteria (design sign-off)

- [ ] Suite 1 steps S1-1..S1-5 and pass conditions
- [ ] Suite 3 steps S3-0..S3-4, log contract L1/L2/L3, 60s window
- [ ] Handoff contract (`playlist_url` is sole coupling)
- [ ] Reset-first requirement in Suite 3
- [ ] CI runner placement and secrets list
- [ ] Run Manifest schema and report output locations
- [ ] Failure boundary vocabulary: `publish/feed`, `device/playback`, `infra`
- [ ] C01 as wired fixture; E01 as parallel Suite-1-only check

---

## Open decisions

| # | Decision | Recommendation |
|---|----------|----------------|
| 1 | Harness repo | `feral-file/feral-file` (co-located with this issue) |
| 2 | Staging feed URL | Document in manifest `environment.feed` |
| 3 | FF1 runner | Self-hosted runner on staging network |
| 4 | Failure notification | Issue comment on failure (v1) |
| 5 | E01 in daily cron | Parallel job, separate manifest, no Suite 3 |