import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AuthResult {
  final bool ok;
  final Map<String, dynamic>? user;
  final String? walletStatus;
  final bool? newlyAssigned;

  AuthResult({
    required this.ok,
    this.user,
    this.walletStatus,
    this.newlyAssigned,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      ok: json['ok'] == true,
      user: (json['user'] is Map)
          ? Map<String, dynamic>.from(json['user'] as Map)
          : null,
      walletStatus: json['wallet_status'] as String?,
      newlyAssigned: json['newly_assigned'] as bool?,
    );
  }
}

class AuthException implements Exception {
  final int statusCode;
  final String error;

  AuthException(this.statusCode, this.error);

  @override
  String toString() => 'AuthException($statusCode): $error';
}

class AuthApi {
  final String baseUrl;
  final http.Client _client;

  AuthApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  Future<AuthResult> authTelegram({required String initData}) async {
    final uri =
        Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/auth/telegram');
    final resp = await _client
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'initData': initData}),
        )
        .timeout(const Duration(seconds: 30));

    final body =
        resp.body.isNotEmpty ? jsonDecode(resp.body) : <String, dynamic>{};

    if (resp.statusCode == 200) {
      if (body is Map<String, dynamic>) {
        return AuthResult.fromJson(body);
      }
      if (body is Map) {
        return AuthResult.fromJson(Map<String, dynamic>.from(body));
      }
      throw AuthException(resp.statusCode, 'bad_response');
    }

    final err = (body is Map && body['error'] is String)
        ? body['error'] as String
        : 'auth_failed';
    throw AuthException(resp.statusCode, err);
  }

  static String resolveBaseUrl() {
    final defineBotApiUrl = const String.fromEnvironment('BOT_API_URL').trim();
    final defineAiBackendUrl =
        const String.fromEnvironment('AI_BACKEND_URL').trim();

    final envBotApiUrl = _readEnv('BOT_API_URL');
    final envAiBackendUrl = _readEnv('AI_BACKEND_URL');

    final localDefault = _localDefaultBotApiUrl();

    return _normalizeHttpUrl(
      envBotApiUrl
          .ifEmpty(envAiBackendUrl)
          .ifEmpty(defineBotApiUrl)
          .ifEmpty(defineAiBackendUrl)
          .ifEmpty(localDefault)
          .trim(),
    );
  }

  static String _readEnv(String key) {
    try {
      return (dotenv.env[key] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static String _normalizeHttpUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    final hasScheme =
        value.startsWith('http://') || value.startsWith('https://');
    if (hasScheme) return value;
    return 'https://$value';
  }

  static String _localDefaultBotApiUrl() {
    final host = Uri.base.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return 'http://127.0.0.1:8080';
    }
    return '';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
