# NOTORYX PRO: competitive strategy and roadmap check

Researched 2026-11-07 against `main` d283be7 (step 2 done, PR #2 = step 3). Evidence: [COMPETITIVE_ANALYSIS.md](COMPETITIVE_ANALYSIS.md), [FEATURE_MATRIX.md](FEATURE_MATRIX.md). Abbreviations: **MCL** mesh-client, **MW** Mesh World, **OV** OverMesh. Everything here is a proposal for `ROADMAP.md`; nothing in this PR changes code.

## 1. Competitive advantage opportunities

| Opportunity | Why it is open | How PRO gets there |
|---|---|---|
| **Trusted dual-protocol phone app** | MW is closed, paid and Bluetooth-only; MCL and OV are desktop/server | Free, open, BLE + USB + TCP from step 3 |
| **People and places, not protocols** | MCL uses a protocol switcher | Step 6 common model; protocol shown as a badge only |
| **Explain every message** | Users ask for hops/RF/MQTT on both sides | Store path facts per message from step 7; show them in step 9, not step 10 |
| **Reliability parity with official apps** | A dual app weaker on either half loses users | Retries, reconnect on all transports, SQLite from day one |
| **Lessons already learned in NOTORYX Core, Connect and Independent** | Competitors repeat SharedPreferences, BT-only reconnect, opaque failures | Apply them as acceptance criteria (below) |

## 2. Competitor weakness report

| # | Weakness | Affected | Evidence | PRO answer | Priority |
|---|---|---|---|---|---|
| W1 | Phone dual app untrusted | MW | 1.7★, email + subscription | No account, open license, public CI | P0 |
| W2 | Bluetooth-only | MW | Review: "Bluetooth should not be the only option" | PR #2 already adds USB + TCP | P0 |
| W3 | Protocol-first UI | MCL | Protocol rail | Unified inbox and map | P1 |
| W4 | Desktop/server only | MCL, OV | READMEs | Phone first, desktop from the same Flutter code | P1 |
| W5 | Bluetooth drops | MCL (#426, #1142), official apps | notoryx-core PR 217 §3 | Reconnect supervisor + connection log on every transport (Independent's design worked) | P0 |
| W6 | Opaque delivery failures | All MeshCore apps | MeshCore #1834 etc. (PR 217) | Delivery diagnosis per message | P1 |

## 3. Innovation research

| Concept | Elsewhere? | Needs firmware change? | Effort | Notes |
|---|---|---|---|---|
| Unified inbox by person/channel | OV partly | No | M | A contact seen on both meshes stays two identities unless the user links them; never auto-merge |
| Cross-protocol foreign-traffic detection | MCL | No for MeshCore RX log; Meshtastic needs a radio that reports raw RX (unclear) | M | Tells users "there's a MeshCore network here too" |
| Two radios at once | OV (MeshCore) | No | M | One MeshCore + one Meshtastic radio is the PRO use case; plan it in step 3/6 so the model allows it |
| Opt-in bridge MC ↔ MT | Server bridges | No | L | Needs two radios; label bridged messages; rate-limit; never bridge DMs by default |
| Verified senders | MeshCore Companion (web) | No | M | Step 12 as planned |
| Delivery diagnosis sheet | No | No | M | Same as notoryx-core P1 |
| Structured emergency text | MCL (MECP) | No | S | Interop with MECP rather than inventing a format |
| Firmware update | MTA, MCO | No | L | Don't plan before 1.0 |

## 4. Plan audit

### 4.1 What the roadmap gets right
One `RadioLink`; protocol codecs from public docs; drift store at step 7; a common model so screens never branch on protocol; one PR per step with tests; the clean-room CI check.

### 4.2 What the roadmap is missing (proposed changes)

| Gap | Why it matters | Proposed change |
|---|---|---|
| License not chosen | Step 5 compiles GPL-3.0 protobufs | Decide before step 5 (GPL-3.0 is the simple fit) |
| Reconnect only mentioned in step 9 | Core's reconnect is Bluetooth-only to this day | Step 3 acceptance: reconnect + connection log on BLE, USB and TCP |
| Path facts shown only at step 10 | Users judge a mesh app by "did it arrive and how" | Step 7 schema stores hops, SNR, RSSI, route, via-MQTT; step 9 shows them |
| No firmware-version gate | Old firmware fails silently on both sides | Step 4/5: read firmware version, refuse unsupported versions with a clear message |
| One radio at a time assumed | The PRO user often carries one radio of each | Step 6 model: `radioId` on everything; step 8 UI can come later |
| Translations "later" | Retrofitting strings is expensive | Step 8: all UI strings through `gen_l10n` (English only at first) |
| Admin in one step | MeshCore repeater CLI and Meshtastic remote admin are each large | Split step 13 into 13a (MeshCore) and 13b (Meshtastic) |

### 4.3 Reuse without copying
Independent (`notoryx-core-independent`) already solved BLE scan prefixes, USB on Android (vendored `usb_serial`), retries and reconnect. PRO's clean-room rule forbids copying its code too; reuse the **lessons**, recorded as acceptance criteria.

## 5. Prioritised roadmap (mapped to ROADMAP.md steps)

### P0: before the first test build
| ID | Item | Step | Acceptance | Tests |
|---|---|---|---|---|
| P0-1 | Choose the license | before 5 | `LICENSE` committed; README states it | — |
| P0-2 | Reconnect + connection log on all three links | 3 | Unplug/replug USB, drop TCP, BLE off/on: all recover, log shows each step | Fake link tests with scripted drops |
| P0-3 | Firmware version gate (both protocols) | 4, 5 | Unsupported version shows a message, no writes | Codec fixtures |
| P0-4 | Path facts in the schema | 7 | Messages store hops/SNR/RSSI/route/via-MQTT | Migration test from schema v1 |
| P0-5 | Retries parity | 9 | MeshCore: direct attempts, then reset path, then flood; Meshtastic: `want_ack` with resend | Scripted radio tests, then a real-radio check of each |

### P1: high impact
| ID | Item | Step | Effort |
|---|---|---|---|
| P1-1 | Unified inbox by person/channel with protocol badge | 8 | M |
| P1-2 | Message path card | 9 | S |
| P1-3 | Delivery diagnosis sheet | 9–11 | M |
| P1-4 | Strings through `gen_l10n` | 8 | S |
| P1-5 | Unified map with offline tiles | 10 | M |

### P2: differentiators
- Two radios at once (one per protocol). **M**
- Foreign-traffic detection on MeshCore RX log. **M**
- Verified senders (step 12). **M**
- MECP-compatible emergency messages. **S**
- Split admin into 13a MeshCore / 13b Meshtastic. **L**

### P3: long-term
- Opt-in MC ↔ MT bridge with labels and rate limits. **L**
- MQTT observer feeds for both meshes. **M**
- Firmware update. **L**

## 6. Top 25 recommended improvements

1. P0-1 License before step 5
2. P0-2 Reconnect on all links (step 3)
3. Merge PR #2 once reconnect criteria are met
4. P0-4 Path facts in the schema
5. P0-5 Retries parity
6. P0-3 Firmware version gate
7. P1-1 Unified inbox
8. P1-2 Message path card
9. P1-4 `gen_l10n` from step 8
10. P1-3 Delivery diagnosis sheet
11. P1-5 Unified map with offline tiles
12. `radioId` on every record (two-radio ready)
13. First test build (step 9) on both a MeshCore and a Meshtastic radio
14. Releases README progress table kept current
15. Signal bars from SNR and hops (step 10)
16. Live RX log + noise floor (step 11)
17. Line of sight / Fresnel (step 11)
18. Verified senders (step 12)
19. MeshCore repeater login + CLI (13a)
20. Meshtastic remote admin (13b)
21. Unread, mute, notifications (step 14)
22. Regional presets for both (step 14)
23. Two radios at once
24. Foreign-traffic detection
25. Opt-in bridge

## 7. Quick wins

- Add the reconnect and firmware-gate acceptance criteria to `ROADMAP.md` steps 3–5 now.
- Add path-fact columns to the step 7 schema plan.
- Pick the license.
- Mark MeshApp and MeshConsole in `docs/research.md` as unverified.

## 8. Innovation backlog

| Concept | Open question |
|---|---|
| Bridge | Loop prevention and airtime on both meshes; legal labelling |
| Identity linking across meshes | How to let users link without spoofing risk |
| Foreign-traffic detection on Meshtastic | Does any companion API expose raw RX of non-Meshtastic LoRa? |
| Reticulum as a third protocol | Worth it on phones? MCL shows demand on desktop |

**Do not build:** accounts or subscriptions; auto-merging contacts across meshes; bridging DMs by default; voice/photos over LoRa.

## 9. Strategic scoring

PRO has no features yet, so it is scored on its **plan** and marked "planned". Scale 0–10; confidence H = source, M = README/notes, L = store listing.

| Area | PRO today | PRO after step 14 (planned) | mesh-client | Mesh World | OverMesh |
|---|---|---|---|---|---|
| Ease of use | 0 | 8 | 6 (M) | 5 (L) | 6 (M) |
| Messaging | 0 | 8 | 8 (M) | 6 (L) | 7 (M) |
| Connectivity reliability | 1 (H) | 8 | 6 (M) | 4 (L) | ? |
| Mapping | 0 | 8 | 6 (M) | 8 (L) | 7 (M) |
| Network diagnostics | 0 | 8 | 9 (M) | 4 (L) | 7 (M) |
| Advanced features | 0 | 7 | 9 (M) | 6 (L) | 6 (M) |
| Performance | ? | 8 | ? | ? | ? |
| Accessibility | ? | 7 | ? | ? | ? |
| Privacy and security | 8 (H) | 9 | 8 (M) | 3 (L) | 7 (M) |
| Overall | 1 | 8 | 7 | 5 | 6 |

"After step 14" is a target, not a measurement.

## 10. Executive summary

- **Strongest competitor:** mesh-client (capability, desktop). On phones, only Mesh World does both, and its reviews are poor.
- **What they do better today:** everything. PRO has no features yet. mesh-client's diagnostics and MQTT are the bar.
- **What PRO already does better:** clean-room independence enforced in CI, public CI, no account, a plan that starts with SQLite and a shared link layer.
- **Biggest market gap:** a trusted, free, phone-first app for both meshes.
- **Build first:** finish step 3 with reconnect on all links; choose the license before step 5.
- **Don't build:** accounts, subscriptions, auto-merged identities, default DM bridging.
- **Five actions now:**
  1. Choose the license.
  2. Add reconnect and connection-log acceptance to step 3 (PR #2) before merging.
  3. Add firmware-version gates to steps 4 and 5.
  4. Put path facts and `radioId` into the step 7 schema.
  5. Route all UI strings through `gen_l10n` from step 8.
