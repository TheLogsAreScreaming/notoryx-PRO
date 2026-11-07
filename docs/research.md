# What other apps do (November 2026)

A survey of MeshCore and multi-protocol clients, used to decide what NOTORYX PRO should do better. Sources: [awesome-meshcore](https://github.com/samuk/awesome-meshcore) and the [mesh-sn.de app comparison](https://mesh-sn.de/en/news/details/meshcore-companion-apps-at-a-glance-meshcore-meshos-and-meshcore-one-for-ios-and-android).

## Main MeshCore apps

| App | Strengths | Weak spots |
|---|---|---|
| Official MeshCore app | Every platform, biggest community, frequent releases, map, coverage and line-of-sight tools | Closed source; paid wait timer on remote repeater admin; reported silent iOS Bluetooth drops; no RX log |
| MeshCore One (iOS) | Deepest diagnostics: RX log, noise floor, trace path, Fresnel line of sight, repeater CLI, telemetry history | iPhone/iPad only, English only, mostly AI-built, no security review |
| MeshOS (Android) | Signal bars, map path viewer, Google-free, manages mixed hardware | Closed source, Android only, partial reactions/blocking/notifications |
| Meshcore Open and forks | Open source, free, many languages | Mostly the same code base; forks add images, compression, wardriving |

## Multi-protocol apps

- **mesh-client** (Electron): MeshCore, Meshtastic and Reticulum on desktop.
- **MeshApp**, **MeshConsole**: MeshCore and Meshtastic with telemetry or web/CLI views.

None of these is a full mobile app for both meshes. That's the gap NOTORYX PRO fills.

## Ideas worth taking (built our own way)

| Idea | Seen in |
|---|---|
| Signed / verified channel posts against name spoofing | MeshCore Companion (web) |
| Live RX log, noise floor, Fresnel line of sight, repeater CLI | MeshCore One |
| Signal bars per contact, path drawn on map | MeshOS |
| Contacts beyond the radio's limit | KIEKR |
| Offline maps | Nelos, Meshcore SAR |
| One-packet images, text compression | MCO Advanced |
| Several radios at once | mcIRC |
