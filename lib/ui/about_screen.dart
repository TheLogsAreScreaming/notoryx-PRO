import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

/// Where the app's source code is published, as the GPL asks.
final sourceUrl = Uri.parse(
  'https://github.com/TheLogsAreScreaming/notoryx-PRO',
);

/// Where the privacy policy is published.
final privacyUrl = Uri.parse('https://meshmayhem.org/privacy/notoryx-pro/');

bool _registered = false;

/// Adds licences Flutter can't find by itself: native libraries and data
/// the app ships that aren't Dart packages. Safe to call more than once.
void registerExtraLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(
    () => Stream.fromIterable([
      const LicenseEntryWithLineBreaks(
        ['NOTORYX PRO'],
        '''
NOTORYX PRO is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

Source code: https://github.com/TheLogsAreScreaming/notoryx-PRO''',
      ),
      const LicenseEntryWithLineBreaks(
        ['MECP labels'],
        '''
Emergency code labels and their translations come from the MECP project (https://github.com/mecp-org/MECP), (c) the MECP contributors, licensed under Creative Commons Attribution 4.0 International (https://creativecommons.org/licenses/by/4.0/). The protocol itself is CC0.''',
      ),
      const LicenseEntryWithLineBreaks(
        ['SQLite3MultipleCiphers'],
        '''
MIT License. Copyright (c) 2019-2025 Ulrich Telle.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

SQLite itself is in the public domain.''',
      ),
      const LicenseEntryWithLineBreaks(
        ['OpenStreetMap'],
        '''
Map data (c) OpenStreetMap contributors, available under the Open Database License (https://www.openstreetmap.org/copyright).''',
      ),
    ]),
  );
}

/// Version, source code, privacy policy and open-source licences.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key, this.version});

  /// Replaceable in tests; read from the installed app otherwise.
  final Future<String>? version;

  static Future<String> _installed() async {
    final i = await PackageInfo.fromPlatform();
    return '${i.version} (${i.buildNumber})';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final version = this.version ?? _installed();
    return Scaffold(
      appBar: AppBar(title: Text(l.aboutTitle)),
      body: FutureBuilder<String>(
        future: version,
        builder: (context, snap) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.appTitle),
              subtitle: Text(l.aboutVersion(snap.data ?? '…')),
            ),
            ListTile(
              title: Text(l.aboutDisclaimerTitle),
              subtitle: Text(l.aboutDisclaimer),
            ),
            ListTile(
              key: const Key('about-source'),
              leading: const Icon(Icons.code),
              title: Text(l.aboutSource),
              subtitle: Text(l.aboutSourceHelp),
              onTap: () => launchUrl(sourceUrl),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l.aboutPrivacy),
              onTap: () => launchUrl(privacyUrl),
            ),
            ListTile(
              key: const Key('about-licences'),
              leading: const Icon(Icons.gavel_outlined),
              title: Text(l.aboutLicences),
              onTap: () {
                registerExtraLicenses();
                showLicensePage(
                  context: context,
                  applicationName: l.appTitle,
                  applicationVersion: snap.data,
                  applicationLegalese: l.aboutLegalese,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
