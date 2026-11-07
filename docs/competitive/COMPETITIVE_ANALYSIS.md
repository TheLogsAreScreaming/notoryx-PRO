# NOTORYX PRO: competitive intelligence report

Researched 2026-11-07 against NOTORYX PRO `main` d283be7 (roadmap step 2 of 14) with PR #2 (step 3, radio links) in review. This is a research document: no app code was changed. It extends [docs/research.md](../research.md) with verified versions, more dual-protocol rivals and a roadmap check.

Companion files: [FEATURE_MATRIX.md](FEATURE_MATRIX.md) / [feature_matrix.json](feature_matrix.json) (34 rows) and [COMPETITIVE_ROADMAP.md](COMPETITIVE_ROADMAP.md).

## 0. Method and limits

- NOTORYX PRO has ~30 lines of app code today, so the "internal audit" is an audit of the **plan** (`ROADMAP.md`) and the foundations (CI, independence check, platform folders), not of features.
- Competitors: GitHub API on 2026-11-07, READMEs, release notes and App Store listings. No competitor was installed. Reddit and Play reviews were not retrieved.
- The single-protocol halves are covered in depth elsewhere: MeshCore in notoryx-core PR 217, Meshtastic in notoryx-connect PR 130. This report focuses on **apps that do both**, and on the bar each half must clear.
- MeshCore and Meshtastic are different protocols (different framing, routing, crypto and limits). Nothing here assumes a feature carries over unchanged.

## 1. Ecosystem map: multi-protocol clients

| App | Developer | Platforms | Protocols | License | Latest verified | Activity |
|---|---|---|---|---|---|---|
| **Mesh World** | Meshworld LLC | iPhone/iPad | Meshtastic, MeshCore | Proprietary, subscription | 2.0.3 ([App Store](https://apps.apple.com/us/app/mesh-world/id6747457936)) | 1.7★ from 3 ratings |
| **mesh-client** | Colorado-Mesh (volunteers) | Windows, macOS, Linux (Electron) | Meshtastic, MeshCore, Reticulum | GPL-3.0 | [v6.6.0, 2026-11-03](https://github.com/Colorado-Mesh/mesh-client) | 146★, pushed 2026-11-07 |
| **OverMesh** | Slofi | Self-hosted web dashboard | Meshtastic, MeshCore | MIT | v2.0 (README; no GitHub release) | [119★, pushed 2026-11-06](https://github.com/Slofi/overmesh) |
| **mesh-bridge / Ura-mesh** | ximi87 | Server | Bridges MT ↔ MC (+ Telegram) | MIT | no releases | [0★, new](https://github.com/ximi87/mesh-bridge) |
| **MeshCrossway** | Renbrant | ESP32 hardware | Portable MT/MC communicator | MIT | — | [24★](https://github.com/Renbrant/MeshCrossway) |
| **CrowPanel dual boot** | kgiannadakis | Standalone touch device | MT or MC (dual boot) | GPL-3.0 | — | [17★](https://github.com/kgiannadakis/CrowPanel-DHE04005D) |
| MeshApp, MeshConsole | — | — | MT + MC | — | — | Listed in `docs/research.md`; **not verified** in this pass |

**Bar for each half (best single-protocol apps):** MeshCore official v1.51.0 and MeshCore One v1.6.2; Meshtastic Android v2.8.3 and Meshtastic Apple v2.7.27.

## 2. Profiles

### 2.1 mesh-client: the most capable multi-protocol client
- **Strengths:**
  - BLE, USB and TCP for both protocols, plus MQTT for both.
  - SQLite history with retention limits.
  - RF/MQTT transport indicator on each message.
  - A cross-protocol signal analyzer that spots "foreign" LoRa traffic.
  - MECP structured emergency text.
  - Saved MQTT profiles.
  - Full Meshtastic module config and local admin (reboot-to-OTA, DFU).
  - Reticulum support with LXMF.
- **Weaknesses:**
  - Desktop only (no phone).
  - Bluetooth issues in its tracker (#426, #1142 per notoryx-core PR 217).
  - A very large surface, run by volunteers.
- **Takeaway:** it is the feature bar for diagnostics. NOTORYX PRO wins by being a **phone** app with the same honesty.

### 2.2 Mesh World: the only phone app that does both
- **Strengths (listing):** dual protocol, satellite/terrain/3D maps, offline maps, custom routing through MeshCore repeaters, waypoints, AR view.
- **Weaknesses (reviews):** email required, subscription billing, Bluetooth-only ("Bluetooth should not be the only option"), 1.7★.
- **Takeaway:** the phone dual-protocol slot is effectively empty of a *trusted* app.

### 2.3 OverMesh: unified dashboard
- **Strengths:** MT and MC side by side, hop and route badges on MeshCore messages, path visualisation on the map, multi-radio MeshCore, bot support, per-radio history.
- **Weaknesses:** self-hosted server (not a phone companion), no GitHub releases.
- **Takeaway:** shows that "nodes and map look the same for both protocols" is achievable and liked.

### 2.4 Bridges (mesh-bridge, Ura-mesh, MeshCrossway)
- New, small projects. They show demand for MT ↔ MC relaying, but they are server- or hardware-based.
- Any in-app bridge must be opt-in, clearly labelled, and careful about airtime and loops.

## 3. Recurring weaknesses (multi-protocol)

1. **No trustworthy phone app for both meshes** (Mesh World reviews; others are desktop/server).
2. **Bluetooth-only or desktop-only** connectivity.
3. **Two mental models**: protocol switchers (mesh-client rail) force users to think in protocols instead of people and places.
4. **Accounts and paywalls** (Mesh World).
5. **Single-protocol bars are high**: the official apps ship retries, maps, admin and firmware updates. A dual app that is weaker on either half loses those users.

## 4. Plan audit (summary)

Detail in [COMPETITIVE_ROADMAP.md §4](COMPETITIVE_ROADMAP.md#4-plan-audit).

- **Good foundations:** clean-room rule enforced by `tools/check_independence.py` in CI; Android, iOS and macOS folders committed with permissions (PR #1); CI builds Android and Apple; a single `RadioLink` for both protocols (PR #2); drift/SQLite planned from day one (step 7). That avoids the SharedPreferences problem in Core and Connect.
- **Gaps in the plan:**
  - The license is not chosen, and step 5 (Meshtastic protobufs, GPL-3.0) depends on it.
  - No firmware-version gate.
  - No "two radios at once".
  - No cross-protocol foreign-traffic detection.
  - Auto-reconnect isn't required on every transport.
  - Translations come late.
  - Remote admin of other Meshtastic nodes and MeshCore repeaters is bundled into one step (13).

## 5. Answers in brief

- **Strongest competitor:** mesh-client on capability (desktop), Mesh World on platform (phone).
- **The gap NOTORYX PRO fills:** a free, open, phone-first app for both meshes. It should look the same for both, explain every message path, and be as reliable as the official app on each side.
