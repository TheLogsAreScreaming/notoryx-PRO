# NOTORYX PRO: master feature comparison matrix (target vs today)

Researched 2026-11-07 (NOTORYX PRO `main` d283be7 = roadmap step 2; PR #2 = step 3 radio links, in review). Machine-readable copy: [`feature_matrix.json`](feature_matrix.json).

## How to read this

- NOTORYX PRO is at roadmap step 2 of 14, so most NX cells are M. The "Evidence / note" column names the roadmap step that plans the feature.
- Competitor cells are I/S/F/M only when a primary source (README, release notes, store listing) says so; otherwise U.
- MCO and MTA are the best single-protocol apps. They show the bar each protocol half has to clear.
- No competitor app was installed and tested hands-on for this report.

| Code | Meaning |
|---|---|
| I | Implemented |
| P | Partial |
| M | Missing |
| S | Superior |
| F | Inferior |
| U | Unverified |
| NA | Not applicable |
| O | In open PR |

**Apps:** **NX** = NOTORYX PRO (main d283be7); **MW** = Mesh World 2.0.3 (iOS); **MCL** = mesh-client v6.6.0 (desktop); **OV** = OverMesh v2.0 (self-hosted web); **MCO** = MeshCore official v1.51.0; **MTA** = Meshtastic Android v2.8.3

**NOTORYX PRO (main d283be7) totals (34 rows):** 28 missing, 4 in open pr, 1 implemented, 1 partial

## Protocols and connectivity

| Feature | NX | MW | MCL | OV | MCO | MTA | Evidence / note |
|---|---|---|---|---|---|---|---|
| MeshCore companion protocol | M | I | I | I | I | NA | Step 4 |
| Meshtastic PhoneAPI | M | I | I | I | NA | I | Step 5 |
| Bluetooth LE | O | I | I | U | I | I | PR #2 (step 3) |
| USB serial | O | M | I | U | I | I | PR #2; Mesh World review asks for serial/HTTP |
| Wi-Fi / TCP | O | M | I | U | I | I | PR #2 |
| Scanner tells MeshCore and Meshtastic radios apart | O | U | I | U | NA | NA | PR #2 |
| Two radios connected at once | M | U | U | I | U | U | OverMesh "multi-radio MeshCore support"; not on NX roadmap yet |
| Auto-reconnect on every transport | M | U | U | U | I | I | Step 9; Core's reconnect is Bluetooth-only, so test all three |

## Messaging

| Feature | NX | MW | MCL | OV | MCO | MTA | Evidence / note |
|---|---|---|---|---|---|---|---|
| Unified inbox with protocol badge | M | U | P | I | NA | NA | Step 8; mesh-client uses a protocol switcher rail, OverMesh shows MT and MC together |
| Delivery ticks and retries (flood fallback / want_ack) | M | I | I | I | I | I | Step 9 |
| Durable SQLite history | M | U | I | P | U | I | Step 7 (drift); mesh-client "local SQLite storage with retention limits" |
| RF / MQTT / hops on each message | M | U | I | I | U | I | Step 10; OverMesh hop badges, mesh-client transport indicator |
| Verified senders (key confirmed by QR) | M | U | U | U | U | U | Step 12 |
| Structured emergency messages | M | U | I | U | U | U | mesh-client MECP; not on NX roadmap |
| Cross-protocol bridge (MC channel ↔ MT channel) | M | U | U | U | NA | NA | NX "Later"; separate bridge projects exist (ximi87/mesh-bridge, Renbrant/MeshCrossway hardware) |

## Maps and diagnostics

| Feature | NX | MW | MCL | OV | MCO | MTA | Evidence / note |
|---|---|---|---|---|---|---|---|
| Unified map with both meshes | M | I | U | I | NA | NA | Step 10 |
| Offline tiles | M | I | U | I | U | U | Step 10; Mesh World and OverMesh list offline maps |
| Path drawn on the map | M | I | U | I | I | U | Step 10; Mesh World "custom path routing through MeshCore repeaters" |
| Live RX log, noise floor | M | U | I | I | U | U | Step 11; mesh-client diagnostics |
| Foreign LoRa traffic detection | M | U | I | U | NA | NA | mesh-client "Cross-Protocol Signal Analyzer"; not on NX roadmap |
| Line of sight / Fresnel | M | U | U | U | I | I | Step 11; MTA Site Planner on phone |
| Trace path with saved routes | M | U | I | I | I | I | Step 11 |

## Admin and config

| Feature | NX | MW | MCL | OV | MCO | MTA | Evidence / note |
|---|---|---|---|---|---|---|---|
| Radio settings for both protocols | M | I | I | I | NA | NA | Step 13 |
| MeshCore repeater/room login and CLI | M | U | I | U | P | NA | Step 13; official app puts a paid wait timer on remote admin |
| Meshtastic remote admin | M | U | P | U | NA | I | Step 13; mesh-client admin is local radio only |
| Firmware update | M | U | P | U | U | I | Not planned; mesh-client offers reboot-to-OTA / DFU only |
| MQTT observer feeds | M | U | I | I | U | I | NX "Later" |
| Regional presets for both | M | U | P | U | I | I | Step 14 |

## Platform, privacy and distribution

| Feature | NX | MW | MCL | OV | MCO | MTA | Evidence / note |
|---|---|---|---|---|---|---|---|
| Android | M | M | NA | NA | I | I | Step 2 committed the folder; first APK at step 9 |
| iOS | M | I | NA | NA | I | NA | Platform folder committed; no build yet |
| Desktop | M | M | I | P | I | I | macOS folder committed; OverMesh runs in a browser |
| No account / no email | I | F | I | I | U | I | Mesh World review: email required, subscription |
| Open source | P | M | I | I | M | I | NX source is public but has no license yet, so it is not legally open source (blocks step 5: protobufs are GPL-3.0) |
| Translations | M | U | I | U | I | I | NX "Later" |
