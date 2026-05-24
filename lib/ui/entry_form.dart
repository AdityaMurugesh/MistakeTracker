// Owner: Capture
// Capture / edit screen. The most important UX surface in the app.

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
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _what;
  late final TextEditingController _cause;
  late final TextEditingController _context;
  late final TextEditingController _costMinutes;
  late final TextEditingController _costMoney;
  late final TextEditingController _moodImpact;
  late final TextEditingController _solution;

  late DateTime _occurredAt;
  late int _severity;
  bool _dirty = false;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _what = TextEditingController(text: e?.what ?? '');
    _cause = TextEditingController(text: e?.cause ?? '');
    _context = TextEditingController(text: e?.context ?? '');
    _costMinutes =
        TextEditingController(text: e?.costMinutes?.toString() ?? '');
    _costMoney = TextEditingController(text: e?.costMoney?.toString() ?? '');
    _moodImpact = TextEditingController(text: e?.moodImpact ?? '');
    _solution = TextEditingController(text: e?.solution ?? '');
    _occurredAt = e?.occurredAt ?? DateTime.now();
    _severity = e?.severity ?? 3;

    for (final c in [
      _what,
      _cause,
      _context,
      _costMinutes,
      _costMoney,
      _moodImpact,
      _solution,
    ]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _what.dispose();
    _cause.dispose();
    _context.dispose();
    _costMinutes.dispose();
    _costMoney.dispose();
    _moodImpact.dispose();
    _solution.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final initialLocal = _occurredAt.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: initialLocal,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialLocal),
    );
    if (time == null) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _dirty = true;
    });
  }

  String? _validateRequired(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _validateOptionalNonNegativeInt(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null) return 'Must be a whole number';
    if (n < 0) return 'Must be ≥ 0';
    return null;
  }

  int? _parseOptionalInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  String? _orNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final dao = ref.read(entryDaoProvider);
    try {
      if (_isEdit) {
        final updated = widget.existing!.copyWith(
          what: _what.text.trim(),
          cause: _orNull(_cause.text),
          occurredAt: _occurredAt,
          context: _orNull(_context.text),
          severity: _severity,
          costMinutes: _parseOptionalInt(_costMinutes.text),
          costMoney: _parseOptionalInt(_costMoney.text),
          moodImpact: _orNull(_moodImpact.text),
          solution: _orNull(_solution.text),
        );
        await dao.update(updated);
      } else {
        final now = DateTime.now();
        final entry = Entry(
          what: _what.text.trim(),
          cause: _orNull(_cause.text),
          occurredAt: _occurredAt,
          context: _orNull(_context.text),
          severity: _severity,
          costMinutes: _parseOptionalInt(_costMinutes.text),
          costMoney: _parseOptionalInt(_costMoney.text),
          moodImpact: _orNull(_moodImpact.text),
          solution: _orNull(_solution.text),
          createdAt: now,
        );
        await dao.insert(entry);
      }
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't save entry: $e")),
      );
    }
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(entryDaoProvider).delete(id);
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't delete entry: $e")),
      );
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}'
        ' ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscardIfDirty()) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit entry' : 'Log a failure'),
          actions: [
            if (_isEdit)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : _delete,
              ),
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.check),
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
        body: _busy
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextFormField(
                      controller: _what,
                      decoration: const InputDecoration(
                        labelText: 'What happened *',
                        hintText: 'e.g. Skipped workout',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: _validateRequired,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cause,
                      decoration: const InputDecoration(
                        labelText: 'Cause',
                        hintText: 'Your guess at the trigger',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _busy ? null : _pickDateTime,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'When',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(_formatWhen(_occurredAt)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _context,
                      decoration: const InputDecoration(
                        labelText: 'Context',
                        hintText: 'Where, with whom',
                      ),
                      maxLines: 2,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text('Severity'),
                        const Spacer(),
                        Text('$_severity / 5'),
                      ],
                    ),
                    Slider(
                      value: _severity.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '$_severity',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _severity = v.round();
                                _dirty = true;
                              }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _costMinutes,
                            decoration: const InputDecoration(
                              labelText: 'Cost (minutes)',
                            ),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            validator: _validateOptionalNonNegativeInt,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _costMoney,
                            decoration: const InputDecoration(
                              labelText: 'Cost (money)',
                            ),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            validator: _validateOptionalNonNegativeInt,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _moodImpact,
                      decoration: const InputDecoration(
                        labelText: 'Mood impact',
                        hintText: 'e.g. anxious, frustrated',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _solution,
                      decoration: const InputDecoration(
                        labelText: 'My solution',
                        hintText: 'What you did, or what to do next time',
                      ),
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
