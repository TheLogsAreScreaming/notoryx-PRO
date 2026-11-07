# NOTORYX PRO

**One app for MeshCore and Meshtastic LoRa radios.** Part of the **NOTORYX** off-grid communications family. **No Towers. No Limits.**

NOTORYX PRO talks to both kinds of radio from the same app: connect a MeshCore companion and a Meshtastic node, and chat, map and manage both from one place.

Downloads are published in **[notoryx-PRO-releases](https://github.com/TheLogsAreScreaming/notoryx-PRO-releases)**, not here.

## Status: just started

There's no test build yet. See [ROADMAP.md](ROADMAP.md) for the build order and [docs/research.md](docs/research.md) for what other MeshCore and Meshtastic apps do and where this one aims to do better.

## What makes it different

- **Both meshes, one app.** MeshCore and Meshtastic radios side by side, each speaking its own protocol, with one inbox, one map and one node list.
- **Free and open.** No paid timers, no feature paywalls, source in this repository.
- **Clean-room code.** Written from the published MeshCore companion protocol and the Meshtastic protobuf definitions. No code is copied from other client apps; CI checks for meshcore-open code on every pull request.
- **Pro diagnostics on every platform.** Live packet log, noise floor, signal bars, line of sight and telemetry history on Android and Mac as well as iPhone.
- **Trust you can see.** Verified-sender badges for contacts whose keys you've confirmed.
- **Built for the backcountry.** Offline maps, connection health you can see, and automatic reconnect.

## App IDs

| Platform | ID |
|---|---|
| Android | `com.bastionmesh.notoryx_pro` |
| iPhone / Mac | `com.bastionmesh.notoryxPro` |

These differ from NOTORYX Core, NOTORYX Independent and NOTORYX Connect, so all of them can be installed together.

## Building

CI is the build loop (`.github/workflows/ci.yml`): format, analyze, tests, the independence check and a debug Android build. Locally:

```bash
flutter pub get
flutter test
```

## License

NOTORYX PRO is free software under the [GNU General Public License v3.0](LICENSE). The Meshtastic protocol definitions it uses are GPL-3.0 too, so the app as a whole is GPL-3.0: anyone can use, study, share and change it, and anyone who shares a changed version must share its source under the same license.
