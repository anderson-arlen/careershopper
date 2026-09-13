import '../domain/chat_image.dart';
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/app_data_directory.dart';
import 'acp_client.dart';
import 'codex_session_storage.dart';
import 'acp_permission.dart';
import 'acp_tool_permissions.dart';
import 'acp_configuration.dart';

class AcpRunCancelled implements Exception {
  const AcpRunCancelled();
  @override
  String toString() => 'Interrupted by user.';
}

class AcpRunControl {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void checkCancelled() {
    if (isCancelled) throw const AcpRunCancelled();
  }
}

class AcpRunRequest {
  const AcpRunRequest({
    required this.executable,
    required this.arguments,
    required this.workOrderId,
    required this.prompt,
    this.resumedPrompt,
    this.jobId,
    this.permissionContext,
    this.jobUrl,
    this.existingSessionId,
    this.allowNewSessionIfUnsupported = false,
    this.scopedMcp = true,
    this.onSessionStarted,
    this.onSessionUpdate,
    this.configValues = const {},
    this.configure,
    this.configurationOnly = false,
    this.answerWriter = false,
    this.recruitingReviewer = false,
    this.control,
    this.images = const [],
  });

  final String executable;
  final List<String> arguments;
  final String workOrderId;
  final String? jobId;
  final String? permissionContext;
  final String? jobUrl;
  final String prompt;
  final String? resumedPrompt;
  final String? existingSessionId;
  final bool allowNewSessionIfUnsupported;
  final bool scopedMcp;
  final Map<String, Object> configValues;
  final AcpConfigure? configure;
  final bool configurationOnly;
  final bool answerWriter;
  final bool recruitingReviewer;
  final AcpRunControl? control;
  final List<ChatImage> images;
  final Future<void> Function(String sessionId)? onSessionStarted;
  final Future<void> Function(Map<String, Object?> update, bool replaying)?
  onSessionUpdate;
}

abstract interface class AcpAgentRunner {
  Future<void> run(AcpRunRequest request);
}

class StdioAcpAgentRunner implements AcpAgentRunner {
  const StdioAcpAgentRunner({
    this.dataDirectory,
    this.permissionPrompt,
    this.processEnvironment,
  });

  final Directory? dataDirectory;
  final Map<String, String>? processEnvironment;
  final AcpPermissionPrompt? permissionPrompt;

  @override
  Future<void> run(AcpRunRequest request) async {
    request.control?.checkCancelled();
    final codex = isCodexAcpAdapter(request.executable, request.arguments);
    List<AcpConfigOption> parseOptions(Object? values) => [
      for (final option in AcpConfigOption.parse(values))
        if (codex && option.id == 'mode')
          AcpConfigOption(
            id: option.id,
            name: option.name,
            type: option.type,
            currentValue: option.currentValue,
            description: 'CareerShopper requires user approval.',
            category: option.category,
            choices: option.choices
                .where((choice) => choice.value == 'read-only')
                .toList(),
          )
        else
          option,
    ];
    final dataDirectory = this.dataDirectory ?? careerShopperDataDirectory();
    final workspace = request.recruitingReviewer
        ? await Directory.systemTemp.createTemp('careershopper-review-')
        : await _workspace(dataDirectory);
    final mcpExecutable = _findMcpExecutable(dataDirectory);
    final environment = await codexSessionEnvironment(
      executable: request.executable,
      arguments: request.arguments,
      dataDirectory: dataDirectory,
      environment: processEnvironment ?? Platform.environment,
      existingSessionId: request.recruitingReviewer
          ? null
          : request.existingSessionId,
    );
    final toolPermissions = codex
        ? AcpToolPermissions(
            Directory(p.join(dataDirectory.path, 'agent-permissions')),
            [
              request.executable,
              request.arguments,
              mcpExecutable.path,
              workspace.path,
            ],
          )
        : null;
    final permissionCancellation = Completer<void>();
    var replaying = false;
    AcpConfigurationSession? configuration;
    String? activeSession;
    var prompting = false;
    var finished = false;
    Timer? cancelTimeout;
    late final AcpStdioClient client;
    client = await AcpStdioClient.start(
      executable: request.executable,
      arguments: request.arguments,
      workingDirectory: workspace.path,
      environment: {
        ...environment,
        if (request.answerWriter) 'CAREERSHOPPER_ANSWER_WRITER': '1',
        if (request.recruitingReviewer) 'CAREERSHOPPER_REVIEWER': '1',
      },
      permissionHandler: (params) async {
        if (request.control?.isCancelled == true ||
            request.recruitingReviewer ||
            (request.answerWriter && !_answerReadAllowed(params))) {
          return acpPermissionCancelled;
        }
        final call = params['toolCall'];
        final title = call is Map
            ? call['title']?.toString() ?? 'Tool request'
            : 'Tool request';
        var remembered = false;
        Future<String?> showPermission(
          Map<String, Object?> offered,
          Future<void> cancelled,
        ) async {
          await request.onSessionUpdate?.call({
            'update': {
              'sessionUpdate': 'permission_request',
              'title': 'Approval required: $title',
              'toolCall': call,
              'options': offered['options'],
              'workingDirectory': workspace.path,
            },
          }, false);
          return permissionPrompt!({
            ...offered,
            'workingDirectory': workspace.path,
            'conversationTitle':
                request.permissionContext ?? 'AI work ${request.workOrderId}',
          }, cancelled);
        }

        final cancelled = Future.any([
          permissionCancellation.future,
          if (request.control != null) request.control!.whenCancelled,
        ]);
        final result = toolPermissions == null
            ? await requestAcpPermission(
                params,
                prompt: permissionPrompt == null ? null : showPermission,
                cancelled: cancelled,
              )
            : await toolPermissions.resolve(
                params,
                prompt: permissionPrompt == null ? null : showPermission,
                cancelled: cancelled,
                onRemembered: () {
                  remembered = true;
                },
              );
        final outcome = result['outcome'] as Map;
        final selected = outcome['optionId'];
        final options = params['options'];
        final allowed =
            options is List &&
            options.whereType<Map>().any(
              (o) =>
                  o['optionId'] == selected &&
                  {'allow_once', 'allow_always'}.contains(o['kind']),
            );
        final selectedOption = options is List
            ? options
                  .whereType<Map>()
                  .where((o) => o['optionId'] == selected)
                  .firstOrNull
            : null;
        final selectedKind = selectedOption?['kind'];
        await request.onSessionUpdate?.call({
          'update': {
            'sessionUpdate': 'permission_decision',
            'toolCall': call,
            'optionId': selected,
            'optionKind': selectedKind,
            'remembered': remembered,
            'title':
                '${allowed ? (remembered
                          ? 'Allowed by saved permission'
                          : selected == 'allow_session'
                          ? 'Allowed for this session'
                          : selectedKind == 'allow_always'
                          ? 'Always allowed'
                          : 'Allowed once') : 'Denied or cancelled'}: $title',
          },
        }, false);
        return result;
      },
      notificationHandler: (method, params) async {
        if (method == 'session/update') {
          final update = params['update'];
          if (update is Map &&
              update['sessionUpdate'] == 'config_option_update') {
            configuration?.update(parseOptions(update['configOptions']));
          }
          await request.onSessionUpdate?.call(params, replaying);
        }
      },
    );
    unawaited(
      request.control?.whenCancelled.then((_) async {
        if (finished) return;
        if (prompting && activeSession != null) {
          try {
            client.cancelSession(activeSession);
          } on Object {
            await client.close();
            return;
          }
          // Give the agent time to save its session and acknowledge cancellation.
          cancelTimeout = Timer(const Duration(seconds: 5), () {
            unawaited(client.close());
          });
        } else {
          await client.close();
        }
      }),
    );
    try {
      request.control?.checkCancelled();
      final initialized = await client.initialize();
      final capabilities = initialized['agentCapabilities'];
      final promptCapabilities = capabilities is Map
          ? capabilities['promptCapabilities']
          : null;
      if (request.images.isNotEmpty &&
          (promptCapabilities is! Map || promptCapabilities['image'] != true)) {
        throw StateError(
          'This ACP agent does not support image messages. Choose an agent with image support. Your message and images were saved.',
        );
      }
      final mcpServers = <Map<String, Object?>>[
        if (!request.recruitingReviewer)
          _mcpServer(request, mcpExecutable, dataDirectory),
      ];
      String sessionId;
      Map<String, Object?> session;
      // A screening pass must never inherit a writer or previous reviewer session.
      final existingSessionId =
          request.recruitingReviewer ||
              (request.allowNewSessionIfUnsupported &&
                  !_supportsLoadSession(initialized))
          ? null
          : request.existingSessionId;
      if (existingSessionId case final existing?) {
        if (!_supportsLoadSession(initialized)) {
          throw StateError(
            'This ACP agent cannot resume sessions. Start a new chat instead.',
          );
        }
        sessionId = existing;
        replaying = true;
        session = await client.loadSession(
          sessionId: sessionId,
          workingDirectory: workspace.path,
          mcpServers: mcpServers,
        );
        replaying = false;
      } else {
        session = await client.newSession(
          workingDirectory: workspace.path,
          mcpServers: mcpServers,
        );
        final value = session['sessionId'];
        if (value is! String || value.isEmpty) {
          throw const FormatException('ACP agent returned no session ID.');
        }
        sessionId = value;
      }
      await request.onSessionStarted?.call(sessionId);
      Future<List<AcpConfigOption>> setOption(String id, Object value) async {
        final option = configuration!.options
            .where((option) => option.id == id)
            .firstOrNull;
        if (option == null || !option.accepts(value)) {
          throw StateError(
            'The agent no longer supports this setting. Reload agent settings.',
          );
        }
        final result = await client.setConfigOption(
          sessionId: sessionId,
          configId: id,
          value: value,
        );
        configuration.update(parseOptions(result['configOptions']));
        if (!configuration.options.any(
          (option) => option.id == id && option.currentValue == value,
        )) {
          throw StateError(
            'The agent did not accept the selected value for "$id".',
          );
        }
        return configuration.options;
      }

      configuration = AcpConfigurationSession(
        parseOptions(session['configOptions']),
        setOption,
      );
      // Model changes can replace the remaining choices. Always validate against
      // the latest response, and select the model before dependent settings.
      final configValues = {
        ...request.configValues,
        if (codex) 'mode': 'read-only',
      };
      final pending = configValues.keys.toList();
      pending.sort((a, b) {
        bool model(String id) => configuration!.options.any(
          (o) => o.id == id && o.category == 'model',
        );
        return (model(a) ? 0 : 1).compareTo(model(b) ? 0 : 1);
      });
      for (final id in pending) {
        final value = configValues[id]!;
        final option = configuration.options
            .where((option) => option.id == id)
            .firstOrNull;
        if (option == null || !option.accepts(value)) {
          if (codex && id == 'mode') {
            throw StateError('Codex ACP must support Ask for approval mode.');
          }
          if (request.configurationOnly) {
            configuration.warnings.add(
              'Saved setting "$id" is no longer available. Review the current choices before selecting Done.',
            );
            continue;
          }
          throw StateError(
            'Saved agent setting "$id" is unavailable. Open agent settings to choose a supported value.',
          );
        }
        if (option.currentValue != value) await setOption(id, value);
      }
      await request.configure?.call(configuration);
      if (request.configurationOnly) return;
      request.control?.checkCancelled();
      activeSession = sessionId;
      prompting = true;
      final result = await client.prompt(
        sessionId: sessionId,
        text: existingSessionId == null
            ? request.prompt
            : request.resumedPrompt ?? request.prompt,
        images: request.images,
      );
      request.control?.checkCancelled();
      final stopReason = result['stopReason'];
      if (stopReason != 'end_turn') {
        throw StateError('ACP agent stopped with reason: $stopReason.');
      }
    } on Object catch (error) {
      if (request.control?.isCancelled == true) throw const AcpRunCancelled();
      final diagnostics = client.diagnostics;
      if (diagnostics.isEmpty) rethrow;
      throw StateError(
        '$error\nAgent stderr (may include unrelated warnings):\n$diagnostics',
      );
    } finally {
      finished = true;
      permissionCancellation.complete();
      cancelTimeout?.cancel();
      await configuration?.close();
      await client.close();
      if (request.recruitingReviewer) await workspace.delete(recursive: true);
    }
  }

  bool _supportsLoadSession(Map<String, Object?> initialized) {
    final capabilities = initialized['agentCapabilities'];
    if (capabilities is! Map) return false;
    return capabilities['loadSession'] == true;
  }

  Map<String, Object?> _mcpServer(
    AcpRunRequest request,
    File executable,
    Directory dataDirectory,
  ) => {
    // A unique name prevents a globally configured CareerShopper MCP server
    // from shadowing this session-scoped instance and losing its work-order ID.
    'name': 'careershopper_session',
    'command': executable.path,
    'args': ['mcp'],
    'env': [
      if (request.scopedMcp)
        {'name': 'CAREERSHOPPER_WORK_ORDER_ID', 'value': request.workOrderId},
      {'name': 'CAREERSHOPPER_DATA_DIR', 'value': dataDirectory.path},
      if (request.answerWriter)
        {'name': 'CAREERSHOPPER_ANSWER_WRITER', 'value': '1'},
    ],
  };

  Future<Directory> _workspace(Directory dataDirectory) async {
    final workspace = Directory(p.join(dataDirectory.path, 'agent-workspace'));
    await workspace.create(recursive: true);
    return workspace;
  }

  File _findMcpExecutable(Directory dataDirectory) {
    final name = Platform.isWindows
        ? 'careershopper-agent.exe'
        : 'careershopper-agent';
    final candidates = [
      File(p.join(dataDirectory.path, 'agent-plugin', 'bin', name)),
      File(p.join(Directory.current.path, 'agent-plugin', 'bin', name)),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate;
    }
    throw StateError(
      'CareerShopper MCP helper is not installed. Run `make install`.',
    );
  }

  bool _answerReadAllowed(Map<String, Object?> params) {
    final call = params['toolCall'];
    final title = call is Map ? call['title'] : null;
    return (call is Map &&
            (call['kind'] == null ||
                ['read', 'other'].contains(call['kind']))) &&
        title is String &&
        RegExp(
          r'^(?:mcp[._])?careershopper_session[._](?:health_get|profile_get)$',
        ).hasMatch(title);
  }
}
