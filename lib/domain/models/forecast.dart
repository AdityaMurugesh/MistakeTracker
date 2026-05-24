// Owner: Insights
// Forward-looking projection from the rule engine. NOT a shared contract —
// only the engine writes these and only the Insights UI reads them, so it
// can evolve without 3-person sign-off.

enum ForecastKind { weekday, hour, weekdayHour }

class Forecast {
  final ForecastKind kind;

  /// The `what` this forecast is about (e.g. "missed workout").
  final String what;

  /// Concrete projected next time the pattern is likely to fire.
  /// Stored in UTC, displayed local.
  final DateTime nextAt;

  /// How many in-window past occurrences seed this forecast.
  final int basis;

  /// Optional explanation for the UI (e.g. "Mondays at 7 AM").
  final String basisLabel;

  const Forecast({
    required this.kind,
    required this.what,
    required this.nextAt,
    required this.basis,
    required this.basisLabel,
  });
}
