import 'dart:convert';

import 'package:logger/logger.dart';

/// FastAds Logger
///
/// Central logging utility for the FastAds package. Provides standardized
/// logging functions with proper formatting and levels.
class FastAdsLogger {
  static final Logger _logger = Logger(
    printer: _SimplePrinter(colors: true, printTime: false),
    level: Level.info,
  );

  /// Log an informational message
  static void info(String message, [dynamic data]) {
    _logger.i('[FastAds] 📋 $message${data != null ? " - $data" : ""}');
  }

  /// Log a debug message
  static void debug(String message, [dynamic data]) {
    _logger.d('[FastAds] 🔍 $message${data != null ? " - $data" : ""}');
  }

  /// Log a warning message
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w('[FastAds] ⚠️ $message${error != null ? " - $error" : ""}');
  }

  /// Log an error message
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(
      '[FastAds] ❌ $message${error != null ? " - $error" : ""}',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _SimplePrinter extends LogPrinter {
  static final levelPrefixes = {
    Level.trace: '[T]',
    Level.debug: '[D]',
    Level.info: '[I]',
    Level.warning: '[W]',
    Level.error: '[E]',
    Level.fatal: '[FATAL]',
  };

  final bool printTime;
  final bool colors;

  _SimplePrinter({this.printTime = false, this.colors = true});

  @override
  List<String> log(LogEvent event) {
    var messageStr = _stringifyMessage(event.message);
    var errorStr = event.error != null ? '  ERROR: ${event.error}' : '';
    var timeStr = printTime ? 'TIME: ${event.time.toIso8601String()}' : '';
    return ['${_labelFor(event.level)} $timeStr $messageStr$errorStr'];
  }

  String _labelFor(Level level) {
    var prefix = levelPrefixes[level]!;
    return prefix;
  }

  String _stringifyMessage(dynamic message) {
    final finalMessage = message is Function ? message() : message;
    if (finalMessage is Map || finalMessage is Iterable) {
      var encoder = const JsonEncoder.withIndent(null);
      return encoder.convert(finalMessage);
    } else {
      return finalMessage.toString();
    }
  }
}
