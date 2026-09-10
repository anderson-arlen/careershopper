import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final log = File(args.first);
  Object? promptId;
  void reply(Object? id, Object result) => stdout.writeln(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  );
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    await log.writeAsString('$line\n', mode: FileMode.append);
    final request = jsonDecode(line) as Map;
    switch (request['method']) {
      case 'initialize':
        reply(request['id'], {
          'protocolVersion': 1,
          'agentCapabilities': {'loadSession': true},
        });
      case 'session/new':
      case 'session/load':
        reply(request['id'], {'sessionId': 'fixture-session'});
      case 'session/prompt':
        promptId = request['id'];
        stdout.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'session/update',
            'params': {
              'sessionId': 'fixture-session',
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'Working'},
              },
            },
          }),
        );
      case 'session/cancel':
        if (!args.contains('ignore-cancel')) {
          reply(promptId, {'stopReason': 'cancelled'});
        }
    }
  }
}
