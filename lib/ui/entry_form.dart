// Owner: Capture
// Capture / edit screen. Day 2: placeholder that saves a hardcoded entry.
// Day 3 replaces this body with the real fields (what / cause / occurredAt /
// context / severity / costs / mood / solution).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/entry.dart';
import '../state/providers.dart';

class EntryForm extends ConsumerStatefulWidget {
  final Entry? existing; // null = create, non-null = edit
  const EntryForm({super.key, this.existing});

  @override
  ConsumerState<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryForm> {
  bool _busy = false;

  Future<void> _saveSample() async {
    setState(() => _busy = true);
    final now = DateTime.now();
    final entry = Entry(
      what: 'Sample failure',
      occurredAt: now,
      createdAt: now,
    );
    await ref.read(entryDaoProvider).insert(entry);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteExisting() async {
    final id = widget.existing?.id;
    if (id == null) return;
    setState(() => _busy = true);
    await ref.read(entryDaoProvider).delete(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit entry' : 'Log a failure'),
      ),
      body: Center(
        child: _busy
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEdit
                          ? 'Editing: ${widget.existing!.what}'
                          : 'Day-2 placeholder. Saves a hardcoded "Sample failure" entry; Day 3 swaps this for the real form.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (!isEdit)
                      FilledButton(
                        onPressed: _saveSample,
                        child: const Text('Save sample entry'),
                      ),
                    if (isEdit)
                      OutlinedButton.icon(
                        onPressed: _deleteExisting,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
