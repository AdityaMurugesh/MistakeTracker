// Owner: Reach & Data
// Read all entries, write JSON (and optionally CSV) to a temp file, hand to share sheet.
//
// TODO:
//   - exportJson() -> File   (writes to a temp dir, returns path)
//   - exportCsv() -> File    (optional v1 nice-to-have)
//   - shareLatestExport()    (uses share_plus to hand the file to the OS share sheet)
//   - On failure, fall back to writing into Downloads/ with a confirmation

import 'dart:io';
import 'entry_dao.dart';

class ExportService {
  final EntryDao dao;
  ExportService(this.dao);

  Future<File> exportJson() async {
    throw UnimplementedError();
  }

  Future<void> shareLatestExport() async {
    throw UnimplementedError();
  }
}
