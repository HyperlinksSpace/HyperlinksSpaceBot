import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../api/auth_api.dart';

class AiChatService {
  static const String _unavailableText = 'AI service unavailable';

  Future<String> ask({
    required List<Map<String, String>> messages,
  }) async {
    final localDefaultUrl = _localDefaultBotApiUrl();
    final localDefaultKey = _localDefaultBotApiKey();

    final defineBotApiUrl = const String.fromEnvironment('BOT_API_URL').trim();
    final defineBotApiKey = const String.fromEnvironment('BOT_API_KEY').trim();
    final defineInnerCallsKey =
        const String.fromEnvironment('INNER_CALLS_KEY').trim();

    // Prefer AuthApi cache (from /api/config in prod), then .env, --dart-define, local default
    final envBotApiUrl = AuthApi.resolveBaseUrl().ifEmpty(_readEnv('BOT_API_URL'));
    final envInnerCallsKey = _readEnv('INNER_CALLS_KEY');
    final envBotApiKey = _readEnv('BOT_API_KEY');
    final envApiKey = _readEnv('API_KEY');

    final botApiUrl = _normalizeHttpUrl(
      envBotApiUrl
          .ifEmpty(defineBotApiUrl)
          .ifEmpty(localDefaultUrl)
          .trim(),
    );
    final botApiKey = envInnerCallsKey
        .ifEmpty(envBotApiKey)
        .ifEmpty(envApiKey)
        .ifEmpty(defineInnerCallsKey)
        .ifEmpty(defineBotApiKey)
        .ifEmpty(localDefaultKey)
        .trim();
    if (botApiUrl.isNotEmpty && botApiKey.isNotEmpty) {
      debugPrint(
        '[AiChatService] direct BOT API url=$botApiUrl keySet=${botApiKey.isNotEmpty} messages=${messages.length}',
      );
      try {
        return await _callBotApiDirect(
          botApiUrl: botApiUrl,
          botApiKey: botApiKey,
          messages: messages,
        );
      } catch (e) {
        debugPrint('[AiChatService] direct BOT API failed: $e');
        // If direct endpoint fails, try proxy before returning fallback text.
        try {
          return await _callProxy(messages: messages);
        } catch (proxyError) {
          debugPrint('[AiChatService] proxy fallback failed: $proxyError');
          return _unavailableText;
        }
      }
    }
    debugPrint('[AiChatService] proxy API url=${_resolveProxyEndpoint()}');
    try {
      return await _callProxy(messages: messages);
    } catch (e) {
      debugPrint('[AiChatService] proxy API failed: $e');
      return _unavailableText;
    }
  }

  Future<String> _callProxy({
    required List<Map<String, String>> messages,
  }) async {
    final uri = _resolveProxyEndpoint();
    final response = await http
        .post(
          uri,
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'messages': messages}),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw Exception('AI proxy failed with status ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid AI proxy response payload');
    }
    final text = (decoded['response'] ?? '').toString().trim();
    if (text.isEmpty) {
      throw Exception('Empty AI response');
    }
    return text;
  }

  Future<String> _callBotApiDirect({
    required String botApiUrl,
    required String botApiKey,
    required List<Map<String, String>> messages,
  }) async {
    final uri =
        Uri.parse('${botApiUrl.replaceAll(RegExp(r"/+$"), "")}/api/chat');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': botApiKey,
          },
          body: jsonEncode({
            'messages': messages,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw Exception('BOT API failed with status ${response.statusCode}');
    }
    debugPrint(
      '[AiChatService] BOT API response status=${response.statusCode} bytes=${response.bodyBytes.length}',
    );
    return _extractResponseFromNdjson(response.body);
  }

  String _extractResponseFromNdjson(String body) {
    var finalResponse = '';
    final lines = body.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      try {
        final parsed = jsonDecode(line);
        if (parsed is Map<String, dynamic>) {
          final responseText = (parsed['response'] ?? '').toString().trim();
          if (responseText.isNotEmpty) {
            finalResponse = responseText;
            continue;
          }
          final token = (parsed['token'] ?? '').toString();
          if (token.isNotEmpty && finalResponse.isEmpty) {
            finalResponse += token;
          }
        }
      } catch (_) {
        // Ignore malformed chunks.
      }
    }
    if (finalResponse.trim().isEmpty) {
      throw Exception('Empty AI response');
    }
    return finalResponse;
  }

  Uri _resolveProxyEndpoint() {
    final explicit = _readEnv('AI_PROXY_URL');
    if (explicit.isNotEmpty) {
      return Uri.parse(_normalizeHttpUrl(explicit));
    }
    return Uri.base.resolve('/api/ai');
  }

  String _normalizeHttpUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    final hasScheme =
        value.startsWith('http://') || value.startsWith('https://');
    if (hasScheme) return value;
    return 'https://$value';
  }

  String _readEnv(String key) {
    try {
      return (dotenv.env[key] ?? '').trim();
    } catch (_) {
      // flutter_dotenv throws NotInitializedError when .env is missing.
      return '';
    }
  }

  String _localDefaultBotApiUrl() {
    final host = Uri.base.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return 'http://127.0.0.1:8080';
    }
    return '';
  }

  String _localDefaultBotApiKey() {
    final host = Uri.base.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost') {
      return 'local-dev-inner-calls-key';
    }
    return '';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
