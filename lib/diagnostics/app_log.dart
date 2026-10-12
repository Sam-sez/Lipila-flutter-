import 'dart:collection';

/// Simple ring-buffer log visible from the Diagnostics screen.
///
/// Usage anywhere in the app:
///   AppLog.add('BLE', 'startScan called');
///
/// The BUILD_ID and mode are stamped on the very first line so every log
/// dump is self-identifying — you never have to guess which APK produced it.
class AppLog {
  AppLog._();

  static const int _maxLines = 500;
  static final Queue<String> _lines = Queue();

  /// Set once from main() before runApp().
  static String buildId = 'unknown';
  static String buildMode = 'unknown';

  /// Called from main() after build info is resolved.
  static void init() {
    add('BUILD', 'id=$buildId  mode=$buildMode');
  }

  static void add(String tag, String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    final line = '$ts [$tag] $message';
    if (_lines.length >= _maxLines) _lines.removeFirst();
    _lines.addLast(line);
    // Mirror to the Flutter debug console so adb logcat catches it too.
    // ignore: avoid_print
    print('LIPILA $line');
  }

  /// Full log as a single string, newest lines last.
  static String dump() => _lines.join('\n');

  static void clear() => _lines.clear();

  static List<String> get lines => List.unmodifiable(_lines);
}
