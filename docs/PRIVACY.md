# NOTORYX PRO privacy policy

NOTORYX PRO is a client for LoRa mesh radios (MeshCore and Meshtastic). It has no accounts. Its developer receives data only if you turn on the optional Community moderation feature and send a report or appeal. It contains no advertising, analytics or crash-reporting SDK.

## Stored on your phone
Messages, contacts, channels, node details, telemetry, saved places and settings are kept in the app's private storage. The app opts out of Android's cloud backup, so this data isn't copied to Google backup. You can choose to encrypt saved messages; the key stays on your phone, and if it is lost the messages can't be recovered.

## What leaves your phone, and when
- **Over your radio:** messages, node information and any position you choose to share are sent over the air through your radio. Other mesh users and anyone listening can receive them. Channels and direct messages are protected only as far as the mesh protocol and your channel settings provide.
- **Map tiles:** when you view the map, the app downloads tiles from OpenStreetMap's servers, which receive your IP address and the areas requested.
- **Radio over Wi-Fi:** if you connect to a radio by address, the app talks directly to that address.
- **MQTT feeds:** only if you add a broker, the app connects to the broker you chose and it receives your IP address and connection details.
- **Sharing and export:** files and text leave the app only when you share or save them yourself. Exports aren't encrypted, and a team setup includes your channel keys.
- **Community moderation:** off unless you turn it on (menu → Community moderation). While it is on, the app downloads the moderators' advisory ban lists (node IDs and case numbers only) from sentinel-relay.meshmayhem.org every few hours. When you report a node, it sends that node's ID and name, the reason you pick, your optional note and, if you leave it ticked, the one message you reported (at most 280 characters). An appeal sends the case number, your statement and any contact you give. NOTORYX moderators read reports and appeals; your own name, node ID and location are not sent with a report, but the relay receives your IP address. Turning it off deletes the downloaded lists and any unsent reports.
- **Automatic sending:** only if you turn them on, auto-replies and a distress beacon send messages through your radio by themselves. A beacon includes your radio's position when known.

## Permissions
- **Bluetooth:** to find and connect to your radio.
- **Location:** Android versions before 12 require it for Bluetooth scanning. The app does not read your phone's GPS.
- **Camera:** to scan QR codes, only while the scanner is open.
- **Fingerprint, face or passcode:** only if you turn on App lock. The check happens in your phone's system, and the app never sees the result beyond pass or fail.
- **Notifications and foreground service:** to alert you to messages and keep the radio connected in the background when you turn that on.

QR codes are read on your phone by Google's ML Kit barcode component, which may send Google device and usage diagnostics. It does not send camera images.

## Children
The app is not directed at children under 13.

Questions or requests: bastionappsupport@gmail.com

Effective date: November 12, 2026
