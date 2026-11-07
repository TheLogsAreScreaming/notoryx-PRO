# NOTORYX PRO roadmap

One pull request per step. Each step lands with tests and a green CI before the next starts. Steps 1–9 get to a first test build that connects both radio types.

## Phase 1: foundations

1. **Project setup** (done): starter app, CI, independence check, docs.
2. **Platform folders** (done): commit Android, iPhone and Mac folders with Bluetooth, USB, network and notification permissions; blue NOTORYX PRO icon.
3. **Radio link layer** (done) shared by both protocols: one `RadioLink` interface with Bluetooth, USB serial and TCP links, a scanner that tells MeshCore and Meshtastic radios apart, and a redacted connection log.

## Phase 2: two protocols

4. **MeshCore codec and session** (done) from the MeshCore companion protocol docs: frames, command queue (one command at a time), pushes.
5. **Meshtastic codec and session** from the Meshtastic protobufs: `ToRadio`/`FromRadio`, `want_config` handshake, heartbeat, BLE characteristics and the `0x94 0xC3` serial/TCP framing.
6. **Common mesh model**: `MeshNetwork`, `Node`, `Channel`, `Message`, `DeliveryState` and a protocol tag on each, so screens never branch on protocol internals.
7. **Data store** (drift/SQLite): radios, nodes, channels, messages per radio; schema migrations tested from day one.

## Phase 3: first test build

8. **Core screens**: connect (both protocols), unified inbox with a protocol badge per thread, conversation, node list.
9. **Messaging that works**: send/receive on both, delivery ticks, retries with flood fallback (MeshCore) and `want_ack` (Meshtastic), auto-reconnect. **First test build (0.1.0-test.1)** published to notoryx-PRO-releases.

## Phase 4: what sets it apart

10. **Unified map** with offline tiles, both meshes' nodes, signal bars from SNR and hops, and path drawing.
11. **Diagnostics**: live RX packet log, noise floor chart, trace path with saved routes, line of sight with Fresnel zone.
12. **Verified senders**: confirm a contact's key by QR or in person; channel posts from verified keys get a badge, and name clashes are flagged.
13. **Radio and node admin**: radio settings for both, MeshCore repeater/room login and CLI terminal, Meshtastic remote admin, telemetry history charts with battery charge estimates.
14. **Unread counts, notifications, mute**, and regional presets for both protocols.

## Later

- Contacts beyond the radio's limit (app keeps everyone heard, swaps favourites onto the radio).
- MQTT observer feeds for both meshes.
- Bridging: relay a message between a MeshCore channel and a Meshtastic channel when both radios are connected (opt-in, clearly labeled).
- Translations.
