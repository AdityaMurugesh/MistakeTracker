// Owner: Reach & Data
// v1 SignalSource: emits NotificationTriggers from time-of-day patterns in the DB.
//
// TODO:
//   - Query EntryDao for the last 30 days
//   - Detect (what, day_of_week, hour) combinations occurring >=3 times
//   - For each detected pattern, emit a NotificationTrigger scheduled for
//     the next occurrence minus 1 hour
//   - Re-run on entry insert (listen to EntryDao.watchAll())

import 'signal_source.dart';
import '../data/entry_dao.dart';

class TimeSignal implements SignalSource {
  final EntryDao dao;
  TimeSignal(this.dao);

  @override
  Stream<NotificationTrigger> watch() {
    throw UnimplementedError();
  }
}
