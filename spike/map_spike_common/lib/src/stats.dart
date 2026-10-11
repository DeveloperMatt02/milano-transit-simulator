/// Collects samples (milliseconds) and reports percentiles.
class SampleStats {
  final List<double> _samples = [];

  int get count => _samples.length;

  void add(double value) => _samples.add(value);

  void clear() => _samples.clear();

  /// Nearest-rank percentile, [p] in 0..100; null without samples.
  double? percentile(double p) {
    if (_samples.isEmpty) return null;
    final sorted = List<double>.of(_samples)..sort();
    final rank = ((p / 100) * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// Share of samples strictly above [threshold], 0..1; null without samples.
  double? shareAbove(double threshold) {
    if (_samples.isEmpty) return null;
    return _samples.where((s) => s > threshold).length / _samples.length;
  }
}
