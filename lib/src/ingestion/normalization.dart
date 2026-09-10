import 'dart:convert';

import 'package:crypto/crypto.dart';

const _knownTrackingParameters = <String>{
  'fbclid',
  'gclid',
  'mc_cid',
  'mc_eid',
};

Uri canonicalizeJobUrl(Uri input) {
  final normalizedParameters = <String, List<String>>{};
  final sortedKeys =
      input.queryParametersAll.keys
          .where(
            (key) =>
                !key.toLowerCase().startsWith('utm_') &&
                !_knownTrackingParameters.contains(key.toLowerCase()),
          )
          .toList()
        ..sort();

  for (final key in sortedKeys) {
    normalizedParameters[key] = [...input.queryParametersAll[key]!]..sort();
  }

  final isDefaultPort =
      (input.scheme.toLowerCase() == 'https' && input.port == 443) ||
      (input.scheme.toLowerCase() == 'http' && input.port == 80);
  var path = input.path.isEmpty ? '/' : input.path;
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  return Uri(
    scheme: input.scheme.toLowerCase(),
    userInfo: input.userInfo,
    host: input.host.toLowerCase(),
    port: isDefaultPort
        ? null
        : input.hasPort
        ? input.port
        : null,
    path: path,
    queryParameters: normalizedParameters.isEmpty ? null : normalizedParameters,
  );
}

String normalizeEmployerName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s*([.,&-])\s*'), (match) => match.group(1)!);

String normalizeContent(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String contentHash(String value) =>
    sha256.convert(utf8.encode(normalizeContent(value))).toString();
