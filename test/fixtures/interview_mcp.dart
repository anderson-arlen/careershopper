import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:careershopper/src/protocol/mcp_server.dart';
import 'package:careershopper/src/storage/database.dart';

Future<Map<String, Object?>> interviewMcp(
  CareerShopperDatabase database,
  String name,
  Map<String, Object?> args, {
  String? orderId,
  bool answerWriter = false,
  String method = 'tools/call',
}) async {
  final output = StreamController<List<int>>();
  final sink = IOSink(output.sink);
  final response = output.stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map((s) => (jsonDecode(s) as Map).cast<String, Object?>())
      .toList();
  await McpServer(
    database,
    workOrderId: orderId,
    answerWriter: answerWriter,
  ).serve(
    input: Stream.value(
      utf8.encode(
        '${jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': method == 'tools/call' ? {'name': name, 'arguments': args} : args,
        })}\n',
      ),
    ),
    output: sink,
  );
  await sink.close();
  return (await response).single;
}

Map<String, Object?> mcpContent(Map<String, Object?> response) =>
    ((response['result'] as Map)['structuredContent'] as Map)
        .cast<String, Object?>();
