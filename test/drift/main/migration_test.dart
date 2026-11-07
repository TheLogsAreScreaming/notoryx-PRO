// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:notoryx_pro/store/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = MeshDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('v1 messages survive the upgrade with 0 attempts', () async {
    const old = v1.MessagesData(
      id: 1,
      radioId: 'meshcore:aa',
      conversation: 'meshcore:aa/ch/0',
      outgoing: 1,
      body: 'hello',
      sentAt: 1762500000,
      receivedAt: 1762500001,
      delivery: 'delivered',
      roundTripMs: 1450,
      hops: 2,
      snr: 6.5,
      route: 'flood',
      viaMqtt: 0,
      nativeId: 85,
      isReaction: 0,
    );
    const upgraded = v2.MessagesData(
      id: 1,
      radioId: 'meshcore:aa',
      conversation: 'meshcore:aa/ch/0',
      outgoing: 1,
      body: 'hello',
      sentAt: 1762500000,
      receivedAt: 1762500001,
      delivery: 'delivered',
      roundTripMs: 1450,
      hops: 2,
      snr: 6.5,
      route: 'flood',
      viaMqtt: 0,
      nativeId: 85,
      isReaction: 0,
      attempts: 0,
    );
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: MeshDatabase.new,
      createItems: (batch, oldDb) => batch.insertAll(oldDb.messages, [old]),
      validateItems: (newDb) async {
        expect(await newDb.select(newDb.messages).get(), [upgraded]);
      },
    );
  });
}
