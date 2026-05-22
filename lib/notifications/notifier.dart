// Owner: Reach & Data
// Glue between SignalSources and flutter_local_notifications.
//
// TODO:
//   - init()                    — request permissions, configure tz, init plugin
//   - register(SignalSource)    — subscribe to its stream, schedule each trigger
//   - cancel(String tag)        — cancel a previously scheduled notification
//   - Handle Android 13+ POST_NOTIFICATIONS permission gracefully (banner in settings)

import 'signal_source.dart';

class Notifier {
  Future<void> init() async {
    throw UnimplementedError();
  }

  void register(SignalSource source) {
    throw UnimplementedError();
  }

  Future<void> cancel(String tag) async {
    throw UnimplementedError();
  }
}
