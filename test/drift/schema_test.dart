import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/store/database.dart';

import 'main/generated/schema.dart';

// When the schema changes: bump schemaVersion, then run
//   dart run drift_dev make-migrations
// which saves the new version in drift_schemas/ and regenerates
// test/drift/main/generated/. Add a test here for each upgrade path.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the database matches the saved schema for its version', () async {
    final schema = await verifier.schemaAt(1);
    final db = MeshDatabase(schema.newConnection());
    expect(db.schemaVersion, 1, reason: 'add an upgrade test for v2');
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });
}
