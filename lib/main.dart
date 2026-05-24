import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await seedIfDebugAndEmpty();
  runApp(const ProviderScope(child: MistakeTrackerApp()));
}
