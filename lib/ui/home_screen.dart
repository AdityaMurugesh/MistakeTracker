// Owner: Capture
// Landing screen. Big "+ Log a failure" button + recent-entries list.
//
// TODO:
//   - Watch EntryDao.watchAll() via a riverpod provider
//   - Render entries as a ListTile list (newest first)
//   - Tapping an entry navigates to entry_form.dart in edit mode
//   - Floating action button "+" opens entry_form.dart in create mode
//   - Empty state: "No entries yet — tap + to log your first failure."

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('MistakeTracker')),
      body: const Center(child: Text('TODO: entries list')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: navigate to EntryForm in create mode
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
