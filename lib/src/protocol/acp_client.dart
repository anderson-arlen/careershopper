import '../domain/chat_image.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef AcpPermissionHandler =
    Future<Map<String, Object?>> Function(Map<String, Object?> params);
typedef AcpNotificationHandler =
    Future<void> Function(String method, Map<String, Object?> params);

class AcpRpcError implements Exception {
  const AcpRpcError(this.code, this.message, [this.data]);

  final int code;
  final String message;
  final Object? data;

  @override
  String toString() => 'ACP error $code: $message';
}

class AcpStdioClient {
  AcpStdioClient._(
    this._process, {
    required this.executable,
    required this._permissionHandler,
    required this._notificationHandler,
  }) {
    _stdoutSubscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_receiveLine, onError: _failAll, onDone: _onStdoutClosed);
    _stderrSubscription = _process.stderr
        .transform(utf8.decoder)
        .listen(_captureStderr);
    unawaited(_watchExit());
  }

  static Future<AcpStdioClient> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required AcpPermissionHandler permissionHandler,
    AcpNotificationHandler? notificationHandler,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    return AcpStdioClient._(
      process,
      executable: executable,
      permissionHandler: permissionHandler,
      notificationHandler: notificationHandler,
    );
  }

  final Process _process;
  final String executable;
  final AcpPermissionHandler _permissionHandler;
  final AcpNotificationHandler? _notificationHandler;
  final Map<Object, Completer<Object?>> _pending = {};
  final Map<String, Map<String, Object?>> _toolCalls = {};
  final StringBuffer _stderr = StringBuffer();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  Future<void> _messageQueue = Future.value();
  var _nextId = 0;
  bool _closing = false;

  String get diagnostics => _stderr.toString().trim();

  Future<Map<String, Object?>> initialize() async {
    final result = await _request('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': <String, Object?>{
        'session': {
          'configOptions': {'boolean': <String, Object?>{}},
        },
      },
      'clientInfo': {
        'name': 'careershopper',
        'title': 'CareerShopper',
        'version': '0.1.0-dev.1',
      },
    });
    final response = _object(result, 'initialize result');
    if (response['protocolVersion'] != 1) {
      throw StateError(
        'The selected agent does not support stable ACP protocol v1.',
      );
    }
    return response;
  }

  Future<Map<String, Object?>> newSession({
    required String workingDirectory,
    required List<Map<String, Object?>> mcpServers,
  }) async {
    final result = await _request('session/new', {
      'cwd': workingDirectory,
      'mcpServers': mcpServers,
    });
    return _object(result, 'session/new result');
  }

  Future<Map<String, Object?>> loadSession({
    required String sessionId,
    required String workingDirectory,
    required List<Map<String, Object?>> mcpServers,
  }) async {
    final result = await _request('session/load', {
      'sessionId': sessionId,
      'cwd': workingDirectory,
      'mcpServers': mcpServers,
    });
    return _object(result, 'session/load result');
  }

  Future<Map<String, Object?>> setConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  }) async => _object(
    await _request('session/set_config_option', {
      'sessionId': sessionId,
      'configId': configId,
      if (value is bool) 'type': 'boolean',
      'value': value,
    }),
    'session/set_config_option result',
  );

  Future<Map<String, Object?>> prompt({
    required String sessionId,
    required String text,
    List<ChatImage> images = const [],
  }) async {
    final result = await _request('session/prompt', {
      'sessionId': sessionId,
      'prompt': [
        if (text.isNotEmpty) {'type': 'text', 'text': text},
        for (final image in images) image.toContentBlock(),
      ],
    });
    return _object(result, 'session/prompt result');
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _failAll(StateError('ACP connection closed.'));
    await _process.stdin.close();
    _process.kill();
    await Future.wait([
      _stdoutSubscription.cancel(),
      _stderrSubscription.cancel(),
    ]);
  }

  void cancelSession(String sessionId) => _send({
    'jsonrpc': '2.0',
    'method': 'session/cancel',
    'params': {'sessionId': sessionId},
  });

  Future<Object?> _request(String method, Map<String, Object?> params) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return completer.future.timeout(
      method == 'session/prompt'
          ? const Duration(minutes: 20)
          : const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('ACP request timed out: $method');
      },
    );
  }

  void _send(Map<String, Object?> message) {
    if (_closing) throw StateError('ACP connection is closed.');
    _process.stdin.writeln(jsonEncode(message));
  }

  void _receiveLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line);
      if (decoded is List) {
        for (final message in decoded) {
          if (message is Map) {
            _enqueueMessage(_stringMap(message));
          }
        }
      } else if (decoded is Map) {
        _enqueueMessage(_stringMap(decoded));
      } else {
        throw const FormatException('ACP message is not an object.');
      }
    } on Object catch (error) {
      _failAll(error);
    }
  }

  void _enqueueMessage(Map<String, Object?> message) {
    _messageQueue = _messageQueue
        .then((_) => _handleMessage(message))
        .catchError((Object error, StackTrace stackTrace) {
          _failAll(error, stackTrace);
        });
  }

  Future<void> _handleMessage(Map<String, Object?> message) async {
    final id = message['id'];
    final method = message['method'];
    if (method is String) {
      if (id == null) {
        if (method == 'session/update') {
          _rememberToolCall(_object(message['params'], '$method params'));
        }
        final handler = _notificationHandler;
        if (handler != null) {
          await handler(method, _object(message['params'], '$method params'));
        }
        return;
      }
      try {
        final params = _object(message['params'], '$method params');
        final Object? result;
        if (method == 'session/request_permission') {
          result = await _permissionHandler(_permissionContext(params));
        } else {
          throw const AcpRpcError(
            -32601,
            'CareerShopper did not advertise this client method.',
          );
        }
        _send({'jsonrpc': '2.0', 'id': id, 'result': result});
      } on AcpRpcError catch (error) {
        _send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': error.code, 'message': error.message},
        });
      }
      return;
    }

    final completer = _pending.remove(id);
    if (completer == null) return;
    final error = message['error'];
    if (error is Map) {
      final values = _stringMap(error);
      completer.completeError(
        AcpRpcError(
          values['code'] is int ? values['code']! as int : -32603,
          values['message']?.toString() ?? 'Unknown ACP error.',
          values['data'],
        ),
      );
    } else {
      completer.complete(message['result']);
    }
  }

  String? _toolKey(Object? sessionId, Object? toolCallId) =>
      sessionId is String && toolCallId is String
      ? jsonEncode([sessionId, toolCallId])
      : null;

  void _rememberToolCall(Map<String, Object?> params) {
    final update = params['update'];
    if (update is! Map ||
        !{'tool_call', 'tool_call_update'}.contains(update['sessionUpdate'])) {
      return;
    }
    final key = _toolKey(params['sessionId'], update['toolCallId']);
    if (key == null) return;
    if ({'completed', 'failed'}.contains(update['status'])) {
      _toolCalls.remove(key);
      return;
    }
    _toolCalls[key] = {
      ...?_toolCalls[key],
      for (final entry in update.entries)
        if (entry.value != null && entry.key != 'sessionUpdate')
          entry.key.toString(): entry.value,
    };
  }

  Map<String, Object?> _permissionContext(Map<String, Object?> params) {
    final call = params['toolCall'];
    if (call is! Map) return params;
    final key = _toolKey(params['sessionId'], call['toolCallId']);
    final previous = key == null ? null : _toolCalls[key];
    if (previous == null) return params;
    // Permission payloads are often partial ToolCallUpdates. Join only the
    // same session and call; current fields replace earlier values verbatim.
    return {
      ...params,
      'toolCall': {
        ...previous,
        for (final entry in call.entries)
          if (entry.value != null) entry.key.toString(): entry.value,
      },
    };
  }

  void _captureStderr(String chunk) {
    if (_stderr.length >= 12000) return;
    _stderr.write(chunk);
  }

  Future<void> _watchExit() async {
    final exitCode = await _process.exitCode;
    if (!_closing && _pending.isNotEmpty) {
      final detail = diagnostics;
      _failAll(
        ProcessException(
          executable,
          const [],
          detail.isEmpty
              ? 'ACP agent exited unexpectedly.'
              : 'ACP agent exited unexpectedly: $detail',
          exitCode,
        ),
      );
    }
  }

  void _onStdoutClosed() {
    if (!_closing && _pending.isNotEmpty) {
      _failAll(StateError('ACP agent closed its protocol stream.'));
    }
  }

  void _failAll(Object error, [StackTrace? stackTrace]) {
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is Map) return _stringMap(value);
  throw FormatException('$label must be an object.');
}

Map<String, Object?> _stringMap(Map<dynamic, dynamic> value) =>
    value.map((key, item) => MapEntry(key.toString(), item));
