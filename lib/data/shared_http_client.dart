import 'dart:async';

import 'package:http/http.dart' as http;

/// One HTTP client shared by every open [TiebaApi], so pages reuse warm
/// connections. It is closed 30 seconds after the last user releases it.
abstract final class SharedHttpClient {
  static http.Client? _client;
  static int _users = 0;
  static Timer? _idleTimer;

  static http.Client acquire() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _users++;
    return _client ??= http.Client();
  }

  static void release() {
    if (--_users != 0) return;
    // Keep connections warm between routes without retaining them forever.
    _idleTimer = Timer(const Duration(seconds: 30), () {
      _client?.close();
      _client = null;
      _idleTimer = null;
    });
  }
}
