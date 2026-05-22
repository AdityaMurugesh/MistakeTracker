// SHARED CONTRACT — changes need 3-person sign-off.
// v1: TimeSignal implements this. v2 adds CalendarSignal, LocationSignal, FitnessSignal.
// Notifier consumes from any number of SignalSources.

class NotificationTrigger {
  final String title;
  final String body;
  final DateTime fireAt;
  final String tag; // unique id for de-duping / cancelling

  const NotificationTrigger({
    required this.title,
    required this.body,
    required this.fireAt,
    required this.tag,
  });
}

abstract class SignalSource {
  /// Stream of triggers this source wants the Notifier to schedule.
  Stream<NotificationTrigger> watch();
}
