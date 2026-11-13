# Vendored flutter_libserialport

A copy of [flutter_libserialport](https://pub.dev/packages/flutter_libserialport) 0.6.0 (MIT) with its bundled [libserialport](https://sigrok.org/wiki/Libserialport) source (LGPL-3.0).

Changed: only the Windows plugin is kept. The published Android part uses `jcenter()`, which current Gradle removed, and its macOS part needs a CocoaPod built with automake and libtool. NOTORYX PRO only uses it for USB radios on Windows; Android has its own USB code.
