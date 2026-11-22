# App icon

NOTORYX PRO uses the NOTORYX **BLACKOUT** mark: the steel eagle-N emblem on a
black plate. Each NOTORYX app shows a different set of emblem parts in frost
or gunmetal, so the apps still look different side by side.

| File | Used for |
|---|---|
| `notoryx-pro-icon.png` | Full icon (1024 x 1024, no transparency): Android legacy launcher icons and iPhone icons |
| `notoryx-pro-icon-foreground.png` | Android adaptive icon foreground (432 x 432 = 108 dp at xxxhdpi, emblem inside the 66 dp safe zone, so no inset) |
| `notoryx-pro-icon-background.png` | Android adaptive icon background (432 x 432) |
| `notoryx-pro-icon-monochrome.png` | Android 13+ themed (monochrome) icon (432 x 432) |
| `notoryx-pro-icon-macos.png` | Mac app icon (1024 x 1024, Apple grid: 824 plate, 100 margin) |

The Windows icon is `windows/runner/resources/app_icon.ico` (16 to 256 px).

To change the icon, resize these files into the platform folders at the sizes
the existing files already have:

- Android: `android/app/src/main/res/mipmap-*/ic_launcher.png` (48 to 192 px)
  and `drawable-*/ic_launcher_{foreground,background,monochrome}.png`
  (108 to 432 px); `mipmap-anydpi-v26/ic_launcher.xml` ties the layers together.
- iPhone: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (20 to 1024 px).
- Mac: `macos/Runner/Assets.xcassets/AppIcon.appiconset/` (16 to 1024 px).
