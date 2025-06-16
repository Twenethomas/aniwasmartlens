// lib/utils/_throttler.dart
import 'dart:async';
import 'package:flutter/foundation.dart'; // For VoidCallback

/// A utility class to throttle function calls.
/// This prevents a function from being called too frequently.
/// If the function is called again within the specified `milliseconds`,
/// the previous pending call is cancelled and a new one is scheduled.
class Throttler {
  final int milliseconds;
  DateTime? _lastRun;
  Timer? _timer;

  /// Creates a Throttler instance.
  /// [milliseconds]: The minimum time that must pass between successful `run` calls.
  Throttler({required this.milliseconds});

  /// Runs the provided [action] if enough time has passed since the last run.
  /// If not enough time has passed, it schedules the action to run after the delay.
  void run(VoidCallback action) {
    if (_lastRun == null ||
        DateTime.now().difference(_lastRun!) >
            Duration(milliseconds: milliseconds)) {
      _lastRun = DateTime.now();
      action();
    } else {
      _timer?.cancel(); // Cancel previous delayed call if still pending
      _timer = Timer(Duration(milliseconds: milliseconds), () {
        _lastRun = DateTime.now();
        action();
      });
    }
  }

  /// Disposes the throttler, cancelling any pending timers.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
