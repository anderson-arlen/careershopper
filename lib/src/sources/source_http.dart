import 'dart:convert';

import 'package:http/http.dart' as http;

sealed class SourceRequestException implements Exception {
  const SourceRequestException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class SourceBackoffException extends SourceRequestException {
  const SourceBackoffException(super.message, {this.retryAfter});

  final Duration? retryAfter;
}

class SourceUnavailableException extends SourceRequestException {
  const SourceUnavailableException(super.message, {required this.reason});

  final String reason;
}

class SourceResponseException extends SourceRequestException {
  const SourceResponseException(super.message, {required this.statusCode});

  final int statusCode;
}

Future<Object?> fetchJson(
  http.Client client,
  Uri uri, {
  Map<String, String> headers = const {},
  Map<String, Object?>? jsonBody,
}) async {
  final body = await fetchText(
    client,
    uri,
    headers: {'accept': 'application/json', ...headers},
    jsonBody: jsonBody,
  );
  try {
    return jsonDecode(body);
  } on FormatException catch (error) {
    throw SourceResponseException(
      'Source returned invalid JSON: ${error.message}',
      statusCode: 200,
    );
  }
}

Future<String> fetchText(
  http.Client client,
  Uri uri, {
  Map<String, String> headers = const {},
  Map<String, Object?>? jsonBody,
}) async {
  final requestHeaders = {
    'accept': 'text/html,application/xhtml+xml,application/json;q=0.8',
    'user-agent': 'CareerShopper/0.1 (+local-first desktop application)',
    ...headers,
  };
  final response = jsonBody == null
      ? await client.get(uri, headers: requestHeaders)
      : await client.post(
          uri,
          headers: requestHeaders,
          body: jsonEncode(jsonBody),
        );
  if (response.bodyBytes.length > 20 * 1024 * 1024) {
    throw const SourceResponseException(
      'Source response exceeded the 20 MiB safety limit.',
      statusCode: 200,
    );
  }
  final body = utf8.decode(response.bodyBytes);
  if (response.statusCode == 429) {
    throw SourceBackoffException(
      'The source requested rate-limit backoff.',
      retryAfter: _retryAfter(response.headers['retry-after']),
    );
  }
  final lowerBody = body.toLowerCase();
  final isJson =
      body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[');
  if (!isJson &&
      (lowerBody.contains('captcha') ||
          lowerBody.contains('verify you are human') ||
          lowerBody.contains('access denied') ||
          lowerBody.contains('unusual traffic') ||
          lowerBody.contains('security challenge'))) {
    throw const SourceUnavailableException(
      'The source returned a CAPTCHA or explicit access block.',
      reason: 'blocked_or_captcha',
    );
  }
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw SourceUnavailableException(
      'The source denied access with HTTP ${response.statusCode}.',
      reason: 'access_denied',
    );
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw SourceResponseException(
      'Unexpected HTTP ${response.statusCode} from ${uri.host}.',
      statusCode: response.statusCode,
    );
  }
  return body;
}

Duration? _retryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value.trim());
  if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
  final date = DateTime.tryParse(value)?.toUtc();
  if (date == null) return null;
  final delay = date.difference(DateTime.now().toUtc());
  return delay.isNegative ? Duration.zero : delay;
}

Map<String, Object?> objectMap(Object? value, {String label = 'value'}) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('$label must be a JSON object.');
}

List<Map<String, Object?>> objectList(Object? value, {String label = 'value'}) {
  if (value is! List) throw FormatException('$label must be a JSON array.');
  return value
      .map((item) => objectMap(item, label: '$label item'))
      .toList(growable: false);
}
