/// Retry backoff utility for sync operations
/// Provides exponential backoff delays: [1, 1, 2, 5, 5, 5, 10] seconds
class RetryBackoff {
  static const List<int> _delays = [1, 1, 2, 5, 5, 5, 10]; // seconds
  int _currentIndex = 0;

  /// Get wait duration for current index, then advance
  /// Stays on last value (10s) after reaching end
  Duration getWaiting() {
    // Get duration for current index
    final duration = Duration(seconds: _delays[_currentIndex]);

    // Advance index if not at max
    if (_currentIndex < _delays.length - 1) {
      _currentIndex++;
    }

    // Return the duration we got before incrementing
    return duration;
  }

  /// Reset to first value
  void reset() {
    _currentIndex = 0;
  }
}
