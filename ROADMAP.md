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
    - **13a. MeshCore** (in review): radio settings (name, power, frequency/bandwidth/SF/CR, position, auto-add, sharing position), adverts, restart, the radio's own command line (protocol 14), repeater and room server login, status and command line. Telemetry history with battery charge estimates comes later.
    - **13b. Meshtastic**: radio and module settings, remote admin of other nodes, telemetry history.
14. **Unread counts, notifications, mute**, and regional presets for both protocols.

## Later

- Two radios connected at once in the UI (the model allows it from step 6).
- Foreign-traffic detection: spot a MeshCore network from the MeshCore RX log while using Meshtastic, and the reverse where the radio reports raw packets.
- Emergency messages compatible with MECP rather than a new format.
- Contacts beyond the radio's limit (app keeps everyone heard, swaps favourites onto the radio).
- MQTT observer feeds for both meshes.
- Bridging a MeshCore channel and a Meshtastic channel when both radios are connected: opt-in, every bridged message labelled, rate-limited, and never direct messages unless the user turns that on for a contact.
- Translations beyond English.

## Won't build

- Accounts, sign-in or subscriptions.
- Automatically merging people across the two meshes.
- Bridging direct messages by default.
- Firmware updating, before 1.0.
