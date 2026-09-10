import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/database.dart';

const acpRegistryUrl =
    'https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json';

class AcpRegistryAgent {
  const AcpRegistryAgent({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.distribution,
    this.repository,
    this.icon,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final Uri? repository;
  final Uri? icon;
  final Map<String, Object?> distribution;

  factory AcpRegistryAgent.fromJson(Map<String, Object?> json) {
    final distribution = json['distribution'];
    if (distribution is! Map) {
      throw const FormatException('ACP registry agent has no distribution.');
    }
    return AcpRegistryAgent(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      version: _requiredString(json, 'version'),
      description: _requiredString(json, 'description'),
      repository: Uri.tryParse(json['repository']?.toString() ?? ''),
      icon: Uri.tryParse(json['icon']?.toString() ?? ''),
      distribution: distribution.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }
}

class AcpRegistrySnapshot {
  const AcpRegistrySnapshot({
    required this.agents,
    required this.fetchedAt,
    required this.fromCache,
  });

  final List<AcpRegistryAgent> agents;
  final DateTime fetchedAt;
  final bool fromCache;
}

class AcpLaunchSpec {
  const AcpLaunchSpec({
    required this.executable,
    required this.arguments,
    required this.distributionType,
  });

  final String executable;
  final List<String> arguments;
  final String distributionType;
}

abstract interface class AcpRegistryStore {
  Future<AcpRegistrySnapshot> fetchRegistry({bool refresh = false});
}

class AcpRegistryRepository implements AcpRegistryStore {
  AcpRegistryRepository(this.database, {http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.parse(acpRegistryUrl);

  final CareerShopperDatabase database;
  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<AcpRegistrySnapshot> fetchRegistry({bool refresh = false}) async {
    final cached = await (database.select(
      database.acpRegistryCache,
    )..where((row) => row.id.equals('official-v1'))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (!refresh &&
        cached != null &&
        now.difference(cached.fetchedAt) < const Duration(hours: 3)) {
      return _parse(cached.payloadJson, cached.fetchedAt, fromCache: true);
    }

    try {
      final response = await _client
          .get(_endpoint)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('ACP Registry returned HTTP ${response.statusCode}.');
      }
      final snapshot = _parse(response.body, now, fromCache: false);
      await database
          .into(database.acpRegistryCache)
          .insertOnConflictUpdate(
            AcpRegistryCacheCompanion.insert(
              id: 'official-v1',
              payloadJson: response.body,
              fetchedAt: now,
            ),
          );
      return snapshot;
    } on Object {
      if (cached != null) {
        return _parse(cached.payloadJson, cached.fetchedAt, fromCache: true);
      }
      rethrow;
    }
  }

  AcpRegistrySnapshot _parse(
    String payload,
    DateTime fetchedAt, {
    required bool fromCache,
  }) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map || decoded['agents'] is! List) {
      throw const FormatException('Invalid ACP Registry response.');
    }
    final agents =
        (decoded['agents'] as List)
            .map((value) {
              if (value is! Map) {
                throw const FormatException(
                  'Invalid ACP Registry agent entry.',
                );
              }
              return AcpRegistryAgent.fromJson(
                value.map((key, item) => MapEntry(key.toString(), item)),
              );
            })
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    return AcpRegistrySnapshot(
      agents: agents,
      fetchedAt: fetchedAt,
      fromCache: fromCache,
    );
  }
}

String _requiredString(Map<String, Object?> values, String key) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('ACP Registry $key must be a non-empty string.');
  }
  return value.trim();
}
