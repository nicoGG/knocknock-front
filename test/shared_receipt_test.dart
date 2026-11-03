import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nocknock/features/notes/data/e2ee_crypto.dart';
import 'package:nocknock/features/notes/data/shared_receipt_store.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/finance/financial_entry_editor.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'financial_improvements_test.dart' as fixtures;

class _Keys implements SecureKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('staged PDF survives removal of the temporary source, is encrypted and is erased on removal', () async {
    final dir = await Directory.systemTemp.createTemp();
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/receipt');
    final data = utf8.encode('%PDF-1.7 confidential');
    await source.writeAsBytes(data);
    final keys = _Keys();
    SharedReceiptStore open() =>
        SharedReceiptStore(keys: keys, directory: () async => dir);
    await open().stage('abc', source.path);
    await source.delete();
    final stored = File('${dir.path}/pending-receipts/abc');
    expect(
      latin1.decode(await stored.readAsBytes()),
      isNot(contains(base64Encode(data))),
    );
    final attachment = await open().read('abc');
    expect(attachment.isPdf, isTrue);
    expect(base64Decode(attachment.dataBase64!), data);
    await open().remove('abc');
    expect(await stored.exists(), isFalse);
    expect(keys.values, isEmpty);
  });

  testWidgets(
    'shared image opens as an editable expense, explicit save keeps receipt and confirmed amount',
    (tester) async {
      await initializeDateFormatting('es_CL');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('cl.nocknock/receipt_scanner');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => 'TOTAL CLP 15.990',
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      NoteDraft? saved;
      const receipt = NoteAttachment(
        id: 'r',
        name: 'Boleta.png',
        mimeType: 'image/png',
        sizeBytes: 68,
        dataBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFinancialEntryEditor(
                  context: context,
                  list: fixtures.list(),
                  author: 'Nico',
                  initialReceipt: receipt,
                  onSave: (draft) async {
                    saved = draft;
                  },
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.tap(find.text('Usar total'));
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('financial-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saved?.financialEntry?.amountMinor, 15990);
      expect(saved?.photoAttachments, [receipt]);
    },
  );
}
