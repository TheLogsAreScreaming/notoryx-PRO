# NOTORYX PRO roadmap

One pull request per step. Each step lands with tests and a green CI before the next starts. Steps 1–9 get to a first test build that connects both radio types.

Priorities from the competitive analysis ([docs/competitive/](docs/competitive/), PR #4) are marked **P0**–**P2** where they change a step.

## Phase 1: foundations

1. **Project setup** (done): starter app, CI, independence check, docs. License: **GPL-3.0**.
2. **Platform folders** (done): commit Android, iPhone and Mac folders with Bluetooth, USB, network and notification permissions; blue NOTORYX PRO icon.
3. **Radio link layer** (done): one `RadioLink` interface with Bluetooth, USB serial and TCP links, a scanner that tells MeshCore and Meshtastic radios apart, and a redacted connection log.
   - **3b. Auto-reconnect on every link** (done, P0): a reconnect supervisor for Bluetooth, USB and TCP with backoff, a "Try now" option and every step in the connection log. Acceptance: a dropped TCP connection, an unplugged-and-replugged USB radio and Bluetooth turned off and on all recover by themselves.

## Phase 2: two protocols

4. **MeshCore codec and session** (done) from the MeshCore companion protocol docs: frames, command queue (one command at a time), pushes. **Firmware gate** (P0): refuses firmware below protocol 3 before writing anything, and checks newer features by protocol code.
5. **Meshtastic codec and session** (done) from the Meshtastic protobufs: `ToRadio`/`FromRadio`, `want_config` handshake, heartbeat, BLE characteristics and the `0x94 0xC3` serial/TCP framing. **Firmware gate** (P0): read the firmware version from the device metadata and refuse unsupported versions with a clear message.
6. **Common mesh model** (done): `MeshNetwork`, `Node`, `Channel`, `Message`, `DeliveryState` and a protocol tag on each, so screens never branch on protocol internals. A **`radioId` on everything**, so one MeshCore and one Meshtastic radio can be connected at once (P2). Someone seen on both meshes stays two identities unless the user links them.
7. **Data store** (done; drift/SQLite): radios, nodes, channels, messages per radio; schema migrations tested from day one. **Path facts on every message** (P0): hops, SNR, RSSI, route (direct or flood) and whether it came via MQTT, plus the `radioId`.

## Phase 3: first test build

8. **Core screens** (done): connect (both protocols), a unified inbox by person and channel with a protocol badge per thread, conversation, node list. **Every UI string through `gen_l10n`** from the start (P1; English first).
9. **Messaging that works** (done; test 1 published): send/receive on both with delivery ticks and **retries matching the official apps** (P0): MeshCore direct attempts, then reset path, then flood; Meshtastic `want_ack` with resend. A **message path card** showing how each message arrived (P1). **First test build (0.1.0-test.1)** published to notoryx-PRO-releases, tried on a real MeshCore and a real Meshtastic radio.

## Phase 4: what sets it apart

10. **Unified map** (done): both meshes' nodes, signal bars from SNR, MeshCore routes drawn through known repeaters, and offline use of every tile you've viewed. Downloading whole areas isn't offered for openstreetmap.org tiles (their tile policy forbids bulk downloads); a tile source that allows it can add that later.
11. **Diagnostics** (done): live packet log for both meshes, noise floor / channel activity chart, trace route (MeshCore trace path, Meshtastic traceroute) with each hop's signal, line of sight with Fresnel zone and Earth bulge (no terrain data), and delivery hints explaining why a message may not have arrived (P1). Saving trace results comes later.
12. **Verified senders** (done): confirm a node's key by scanning its QR code (MeshCore and Meshtastic contact formats) or comparing fingerprints; direct messages proven by encryption from a verified key get a badge, a changed key is flagged, and posts under a name another node also uses are flagged. Channel posts can't be proven on either mesh, so they never get the badge.
13. **Radio and node admin**, split in two because each half is large:
    - **13a. MeshCore** (done): radio settings (name, power, frequency/bandwidth/SF/CR, position, auto-add, sharing position), adverts, restart, the radio's own command line (protocol 14), repeater and room server login, status and command line. Telemetry history with battery charge estimates comes later.
    - **13b. Meshtastic** (done): your radio's names, role, LoRa (region, preset, slot, hops, power, MQTT), position and telemetry settings, saved as one batch with the session passkey and only what changed; the same screen for another node over the mesh (public-key admin; the node must list your key); restart; telemetry history (battery, voltage, channel and airtime load, temperature, humidity, pressure) kept 14 days for every Meshtastic node, with charts.
14. **Unread counts, notifications, mute**, and regional presets for both protocols (done): unread counts per conversation and on the Inbox tab, mark read / mark all read, mute for an hour, 8 hours, a week or until unmuted, one notification per conversation (direct and channel messages can be turned off separately; tapping opens the conversation), MeshCore presets (27 suggested by the MeshCore project, 27 local meshes with nearby ones first), Meshtastic standard setup per region, and a warning when a Meshtastic radio has no region.

## Phase 5: done since the first test builds

Everything here is merged and in a published test build, but none of it has been tried on real radios yet except where noted.

15. **Several radios at once** (done, #19): up to four radios from either mesh.
16. **Contacts beyond the radio's limit** (done, #20), **channels** (done, #21: create, join, leave and share by QR code or link) and the **Meshtastic Bluetooth fix** (#22; confirmed on a real radio with test 3.1).
17. **Background connection, search, delete and export** (done, #23 and #24).
18. **MECP emergency messages** (done, #25), with labels in 20 languages (#29).
19. **Other-mesh traffic, MQTT feeds and channel bridging** (done, #26–#28): bridging is opt-in, labelled and rate-limited.
20. **Spanish** (done, #29; machine-written, needs a native speaker's review).
21. **Meshtastic module settings, fixed position, MeshCore path-hash setting and saved traces** (done, #30–#33).
22. **Accessibility** (done, #34 and #50–#51): contrast, labels and large text checks, and a published first-pass audit in [docs/ACCESSIBILITY_AUDIT.md](docs/ACCESSIBILITY_AUDIT.md). No screen reader walk-through yet.
23. **Meshtastic FromNum ID fix** (done, #36): test 4 couldn't connect over Bluetooth because of a typo in one ID. Not yet confirmed on a real radio.
24. **Eight themes** (done, #37), **restore from export** (#38) and a **real MAYDAY through mute** (#39).
25. **SALUTE and 9-Line reports** (done, #40), a **manually started distress beacon** (#41), **forwarding and scheduled messages** (#42) and **airtime savers** (#43: Plus Codes, paced remote settings).
26. **Places** (done, #44: GPX, geofences, link planner), **team setup sharing** (#45), **auto-replies** (#46) and **App lock** (#47).
27. **Optional encryption of saved messages** (done, #49), with Android cloud backup turned off.
28. **Google Play groundwork** (done, #48: signed, obfuscated bundle, API 36, privacy policy) and a **Windows build** (#52; compiles, never run).

## Phase 6: now

29. **About screen** with licences and the source link (#55).
30. **Demo mode** with a pretend radio, for store reviewers, screenshots and people without a radio yet.
31. **Windows notifications** and **USB radios on Windows**.
32. **More languages** (machine-written, each needing a native speaker's review).
33. **Multi-radio polish** from testing.

## Waiting on the owner

- Real-radio tests of everything above, on Android first, then Mac and Windows.
- Google Play account and its 14-day closed test.
- Apple developer enrollment, then a notarized Mac download and TestFlight on iPhone. The app has never run on a real iPhone.
- A decision on the GPL licence before any App Store submission: the Meshtastic protocol definitions are GPL-3.0.

## Later

- Firmware updating, after 1.0.
- Code signing for the Windows download.

## Won't build

- Accounts, sign-in or subscriptions.
- Automatically merging people across the two meshes.
- Bridging direct messages by default.
- Firmware updating, before 1.0.
