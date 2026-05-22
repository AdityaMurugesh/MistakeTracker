// Owner: Capture
// Capture / edit screen. The most important UX surface in the app.
//
// TODO fields (in order on the form):
//   - what          (required, text)
//   - cause         (optional, text)
//   - occurredAt    (auto-filled now, editable via date+time picker)
//   - context       (optional, multi-line text)
//   - severity      (1..5 slider, default 3)
//   - costMinutes   (optional, int)
//   - costMoney     (optional, int)
//   - moodImpact    (optional, text or short enum)
//   - solution      (optional, multi-line text — "my solution")
//
// On save: build Entry, call EntryDao.insert/update via provider, pop back to home.
// On cancel: confirm if any field is dirty.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/entry.dart';

class EntryForm extends ConsumerStatefulWidget {
  final Entry? existing; // null = create, non-null = edit
  const EntryForm({super.key, this.existing});

  @override
  ConsumerState<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryForm> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Log a failure' : 'Edit entry')),
      body: const Center(child: Text('TODO: form fields')),
    );
  }
}
