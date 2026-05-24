// Owner: Reach & Data
// Read all entries, write JSON (and optionally CSV) to a temp file, hand to share sheet.

import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'entry_dao.dart';
// Entry model imported through the DAO when needed.

class ExportService {
  final EntryDao dao;
  ExportService(this.dao);

  /// Export entries to a timestamped JSON file and return the File object.
  Future<File> exportJson() async {
    final entries = await dao.getAll();
    final now = DateTime.now().toUtc();
    final meta = {
      'exportedAt': now.toIso8601String(),
      'app': 'MistakeTracker',
      'version': '0.1.0',
      'schemaVersion': 1,
      'entryCount': entries.length,
    };

    final payload = {
      ...meta,
      'entries': entries.map((e) => e.toMap()).toList(),
    };

    final dir = await getTemporaryDirectory();
    final safeTs = now.toIso8601String().replaceAll(':', '-');
    final fileName = 'mistaketracker_export_$safeTs.json';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  /// Export then invoke the platform share sheet for the generated file.
  Future<void> shareLatestExport() async {
    try {
      final file = await exportJson();
      // Some share_plus versions expose different APIs; call dynamically and fall back to sharing text.
      final shareApi = Share as dynamic;
      try {
        await shareApi.shareFiles([file.path], text: 'MistakeTracker export');
      } catch (e) {
        await Share.share('MistakeTracker export available: ${file.path}');
      }
    } catch (e) {
      // Bubble up so UI can show an error message
      rethrow;
    }
  }
}
