// Port of agent-device/src/platforms/perf-utils.ts

/// Rounds a number to the nearest tenth of a percent.
double roundPercent(double value) {
  return (value * 10).round() / 10;
}

/// Rounds a number to one decimal place (alias for [roundPercent]).
double roundOneDecimal(double value) {
  return roundPercent(value);
}
