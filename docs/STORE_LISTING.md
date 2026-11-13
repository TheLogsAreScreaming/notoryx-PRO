# NOTORYX PRO store listing kit

Text and answers for Google Play and the App Store, written from what the code does. Check every answer against the build you actually upload; the forms are legal statements by the developer, not by this document.

Last checked against `main` on 13 November 2026 (version 0.11.0, test 11).

## Basics

| Field | Value |
|---|---|
| App name | NOTORYX PRO |
| Android package | `com.bastionmesh.notoryx_pro` |
| Apple bundle ID | `com.bastionmesh.notoryxPro` |
| Category | Communication (Play and App Store) |
| Price | Free, no in-app purchases, no ads |
| Privacy policy | https://meshmayhem.org/privacy/notoryx-pro/ |
| Support contact | bastionappsupport@gmail.com |
| Source code | https://github.com/TheLogsAreScreaming/notoryx-PRO (GPL-3.0) |
| Languages | English, Spanish, French, German (all but English machine-written) |

## Store text

**App Store subtitle** (30 characters max)
> Off-grid mesh radio messaging

**Play short description** (80 characters max)
> Message over MeshCore and Meshtastic LoRa radios, with no phone signal needed.

**App Store promotional text** (170 characters max)
> One app for MeshCore and Meshtastic radios. Message, map and manage your mesh off-grid. Try the built-in demo first: no radio needed.

**Full description** (Play limit 4000, App Store 4000)

> NOTORYX PRO talks to your LoRa mesh radio over Bluetooth, USB or Wi-Fi, so you can message people when there's no phone signal. It works with both MeshCore and Meshtastic radios, and can use several at once.
>
> You need a compatible radio to send messages. To look around first, open Radios and choose "Try a demo without a radio".
>
> MESSAGING
> • Direct messages and channels on both meshes, with delivery ticks and automatic retries
> • See how each message travelled: hops, signal and route
> • Search, forward, schedule and export messages; restore from an export
> • Verify contacts by QR code, with a warning if their key changes
>
> MAP AND PLACES
> • Every node with a position on one map, with signal bars and routes
> • Import and export GPX waypoints and tracks
> • Geofences that notify you when a node enters or leaves
> • A link planner and line-of-sight check (open-ground estimates)
>
> RADIO TOOLS
> • Radio settings and remote admin for MeshCore and Meshtastic
> • Packet log, noise floor, airtime and trace route
> • Share channels and radio settings with your team by QR code or file
>
> EMERGENCY TOOLS
> • MECP emergency messages, SALUTE and 9-Line report templates
> • A distress beacon you start by hand, with a practice mode
> NOTORYX PRO is not an emergency service and doesn't replace 911. Mesh messages can be delayed or lost, and nobody may be listening.
>
> PRIVACY
> • No account, no ads, no analytics. Messages stay on your phone.
> • Optional App lock and encryption of saved messages
>
> Free and open source under the GNU GPL v3.

Keep claims to what's in the build. Don't add "secure", "encrypted messaging" or "works anywhere" without qualifying them: mesh encryption depends on the protocol and channel, and range depends on terrain.

**App Store keywords** (100 characters max, comma-separated, no spaces needed)
> lora,mesh,meshtastic,meshcore,off-grid,radio,offline,messaging,hiking,emergency,sos,gps,map

Check you may use the names "Meshtastic" and "MeshCore" in keywords and text. They describe compatibility, but both are other projects' names.

## Review notes (both stores)

Paste into App Review Information / Play's app access notes:

> NOTORYX PRO needs a LoRa mesh radio (MeshCore or Meshtastic) to send messages. Reviewers can use the whole app without one: open the Radios tab and tap "Try a demo without a radio". The demo uses a simulated radio inside the app, a separate temporary database, and never transmits.
>
> No account or login is needed.
>
> Emergency features (MECP messages, report templates, distress beacon) only send over the user's own radio. The app shows that it is not an emergency service. The beacon is started by hand behind a second confirmation, has a practice mode, and stops by itself.
>
> Auto-replies are off until the user turns them on, never answer emergency messages, and are limited to 10 per hour.

## Google Play: Data safety form

Answers follow from the code and `docs/PRIVACY.md`. "Collected" in Play's sense means sent off the device to the developer or a third party.

| Question | Answer | Why |
|---|---|---|
| Does the app collect or share user data? | **No** | Nothing goes to the developer. Messages go over the user's own radio to other mesh users, which Play treats as user-initiated communication, not collection. |
| Data encrypted in transit? | Answer only if you answer Yes above | |
| Account deletion | Not applicable | No accounts |

Things a reviewer may ask about, and the honest answers:
- **Map tiles**: downloaded from OpenStreetMap, which sees the device's IP address and the map area. This is a request to a third party, not data the app collects.
- **MQTT feeds**: only connect to a broker the user adds.
- **QR scanning**: Google ML Kit runs on the device and may send Google diagnostics. Play's guidance treats on-device SDK diagnostics as the SDK's own disclosure; mention it if asked.

## Google Play: other declarations

| Declaration | Answer |
|---|---|
| Foreground service type | **connectedDevice**: keeps the Bluetooth, USB or Wi-Fi connection to the user's radio alive while the screen is off, only when "Stay connected in the background" is on. Play asks for a short video showing it; record the persistent notification appearing after connecting a radio. |
| Location permission | Requested only on Android 11 and earlier, which require it for Bluetooth scanning. The app never reads the phone's location. Declare "Bluetooth device scanning on older Android versions". |
| Biometric | Only for App lock, checked by the system. |
| Target audience | 13 and over; not designed for children. |
| Content rating (IARC) | Users can communicate with each other (messages); no user-generated public content hosted by the developer; no violence, gambling or purchases. Emergency tools aren't "medical advice". |
| Ads | No |
| News app | No |
| Government app | No |

New personal developer accounts must run a **closed test with at least 12 testers for 14 days** before production. The signed bundle is in the release workflow's `play-bundle` artifact.

## Apple: App Privacy (nutrition label)

| Question | Answer |
|---|---|
| Do you or your partners collect data? | **No: Data Not Collected** |
| Tracking | No (the privacy manifest says the same) |

## Apple: permissions and modes to check before the first upload

| Item | State | Action |
|---|---|---|
| Bluetooth | `NSBluetoothAlwaysUsageDescription` set | None |
| Camera | Set (QR codes) | None |
| Face ID | Set (App lock) | None |
| Local network | Set (Wi-Fi radios) | None |
| **Location** | `NSLocationWhenInUseUsageDescription` says the app "shows where you are on the map", but **the app never reads the phone's location** | Before the first upload: remove the key, or change it to say what's true. If the upload then reports a missing purpose string, a library references location APIs and the key must stay with honest wording. |
| Background mode | `bluetooth-central` | Justify as: keeps the radio connection for incoming messages and the user's distress beacon. iOS may still suspend the app; don't promise background sending in the store text. |
| Export compliance | `ITSAppUsesNonExemptEncryption` = false (PR 63) | Standard encryption only. The US may expect a yearly self-classification report for mass-market encryption; check BIS guidance. |
| Privacy manifest | `PrivacyInfo.xcprivacy` (PR 63) | None |

**Licence**: the App Store question about GPL-3.0 is still open (the Meshtastic protocol definitions are GPL-3.0). Settle it before submitting to the App Store. Google Play has no such conflict.

## Age rating (Apple)

Answer "None" to every content category. Under "Unrestricted web access": No. Under "Messaging and chat with other users": the app lets users message each other over radio, so the rating questions about user communication apply; the expected result is 12+ or 17+ depending on Apple's current questionnaire. Pick the answer that matches; don't understate it.

## Screenshots

`tool/store_screenshots` (once added) renders these from demo mode at each store's sizes. Planned set, in order:

1. Inbox with both meshes (Blaze theme, light)
2. A conversation with delivery ticks and a reply
3. Map with nodes and a route
4. Places: geofence and GPX track on the map
5. Diagnostics: packet log and noise floor
6. MECP emergency message composer (practice)
7. Themes picker
8. Night Ops theme (dark)

Play: phone 1080×1920 or larger; 7" and 10" tablet optional. App Store: 6.9" (1320×2868) and 6.5" (1284×2778) iPhone; 13" iPad only if iPad is supported.
