import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LanPingResult {
  const LanPingResult({
    required this.success,
    this.latencyMs,
    this.errorMessage,
    this.serverData,
  });

  final bool success;
  final int? latencyMs;
  final String? errorMessage;
  final Map<String, dynamic>? serverData;
}

/// HTTP client utilities for communicating with a Host POS station.
class LanDatabaseClient {
  /// Tests connectivity and measures latency to a Host POS station.
  static Future<LanPingResult> testConnection(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final cleanHost = host.trim().replaceAll(RegExp(r'^https?://'), '');
    if (cleanHost.isEmpty) {
      return const LanPingResult(
        success: false,
        errorMessage: 'Host IP address cannot be empty',
      );
    }

    final stopwatch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final uri = Uri.http('$cleanHost:$port', '/status');
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      stopwatch.stop();

      if (response.statusCode == HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        return LanPingResult(
          success: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          serverData: data,
        );
      } else {
        return LanPingResult(
          success: false,
          errorMessage: 'Server responded with HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      stopwatch.stop();
      return LanPingResult(
        success: false,
        errorMessage: 'Connection failed: $e',
      );
    } finally {
      client.close();
    }
  }

  /// Authenticates credentials directly against the Host station via HTTP POST.
  /// Returns the user data map on success, or null if credentials are wrong /
  /// host is unreachable. Instant — no sync cycle needed.
  static Future<Map<String, dynamic>?> authenticateOnHost({
    required String host,
    required int port,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final cleanHost = host.trim().replaceAll(RegExp(r'^https?://'), '');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.http('$cleanHost:$port', '/auth');
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      final body = jsonEncode({'username': username, 'password': password});
      request.headers.contentLength = utf8.encode(body).length;
      request.write(body);
      final response = await request.close().timeout(timeout);
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.ok) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        if (data['success'] == true) {
          return data['user'] as Map<String, dynamic>?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[LanDatabaseClient] authenticateOnHost error: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
