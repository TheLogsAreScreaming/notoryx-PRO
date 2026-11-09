# NOTORYX PRO accessibility audit

**Status: first pass, automated checks and code review only.** Audited 9 November 2026, on top of commit `1c0b159`.

**No screen reader, switch control or real-device large-text walk-through has been done yet.** This page reports what the code and automated tests show. It doesn't claim the app is accessible, and it isn't a conformance statement.

## Method

| Layer | How | Done? |
|---|---|---|
| 1. Pattern scan | `python3 tool/a11y_scan.py` from the repository root | Yes |
| 2. Automated tests | Flutter tap-size, label and contrast checks in widget tests | Partly: see below |
| 3. Review of scan results | Reading flagged places in context | Yes |
| 4. Screen reader | TalkBack on Android, VoiceOver on iOS and macOS | **Not yet** |
| 5. Large text and display on a device | Largest system text, bold text, reduce motion, each theme | **Not yet** |
| 6. People who use these tools | Feedback from disabled users | **Not yet** |

The scanner matches text patterns. A flagged line is a place to look, and an unflagged line isn't proof of correct behaviour.

## Scan results

| Check | Found | To review |
|---|---|---|
| Icon buttons without a tooltip | 16 | 0 |
| Floating buttons without a tooltip | 4 | 0 |
| Tap areas (`GestureDetector`) with no nearby label | 2 | 0 |
| `InkWell` with no nearby label or text | 1 | 0 |
| Images with no label | 0 | 0 |

| Pattern | Count | What it means here |
|---|---|---|
| Text scaling clamped or disabled | 0 | Nothing blocks system text size |
| Reduce-motion checks | 0 | The app has no custom animations of its own to slow down; Flutter's built-in ones haven't been checked |
| Bold-text checks | 0 | Whether bold text works hasn't been checked |
| `TextOverflow.ellipsis` | 4 | Names in two lists, a title and a log row can be cut off at large sizes |
| `FittedBox` | 0 | Nothing shrinks text to fit |
| Live regions | 1 | Only the distress beacon status, added by this audit |
| `Text` not translated | 13 | Reviewed: values, numbers and mesh names, not sentences |

## Automated test coverage

- Five main screens (Inbox, Nodes, Map, Radios, a conversation): tap size, labels and contrast in light and dark, and double-size text on a small phone.
- All eight themes across those screens: text contrast in light and dark.
- Places, Appearance, Auto-replies and App lock: tap size, labels and contrast in light and dark, and double-size text.

## Known problems

1. **The map is visual by nature.** It has a summary label, but the nodes on it aren't a usable list for a screen reader from that tab. The Nodes tab holds the same nodes as text.
2. **Few live announcements.** New messages, connection changes and delivery status aren't announced automatically and need checking with a screen reader.
3. **Long names can be cut off** at the largest text sizes in the four places above.
4. **Some sheets have no automated accessibility test**: distress beacon, field reports, scheduled messages, team setup, restore and MECP.

## Not measured

- Reading and focus order.
- Keyboard use on the Mac.
- Contrast and tap size on screens outside the list above.
- Spanish, which is machine-written.

## Next steps

1. Walk through with TalkBack and VoiceOver, starting with SOS and the beacon, sending a message, and connecting a radio.
2. Add the sheets above to the automated tests.
3. Update this page with the results, and name the device and OS versions used.
