import 'dart:async';

/// An agent permission request is data to show the user, never authorization.
typedef AcpPermissionPrompt =
    Future<String?> Function(
      Map<String, Object?> params,
      Future<void> cancelled,
    );

const acpPermissionCancelled = <String, Object?>{
  'outcome': {'outcome': 'cancelled'},
};

Future<Map<String, Object?>> requestAcpPermission(
  Map<String, Object?> params, {
  required AcpPermissionPrompt? prompt,
  required Future<void> cancelled,
}) async {
  final raw = params['options'];
  final options = raw is List ? raw.whereType<Map>().toList() : <Map>[];
  // Only options actually offered by the agent can be selected.
  final offered = options
      .where(
        (option) =>
            {
              'allow_once',
              'reject_once',
              'allow_always',
              'reject_always',
            }.contains(option['kind']) &&
            option['optionId'] is String,
      )
      .toList();
  if (offered.isEmpty ||
      options.map((o) => o['optionId']).toSet().length != options.length) {
    return acpPermissionCancelled;
  }
  if (prompt == null) {
    throw StateError(
      'The agent requested authorization, but no interactive approval prompt is available. Continue this work in the CareerShopper desktop app. Nothing was authorized.',
    );
  }
  var stopped = false;
  final cancellation = cancelled.then<String?>((_) {
    stopped = true;
    return null;
  });
  await Future<void>.value();
  if (stopped) return acpPermissionCancelled;
  final selected = await Future.any<String?>([
    prompt({...params, 'options': offered}, cancelled),
    cancellation,
  ]);
  if (stopped ||
      selected == null ||
      !offered.any((o) => o['optionId'] == selected)) {
    return acpPermissionCancelled;
  }
  return {
    'outcome': {'outcome': 'selected', 'optionId': selected},
  };
}
