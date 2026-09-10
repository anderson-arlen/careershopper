import 'dart:async';

/// Agent-provided ACP session controls. IDs and values are opaque to the client.
class AcpConfigOption {
  const AcpConfigOption({
    required this.id,
    required this.name,
    required this.type,
    required this.currentValue,
    this.description,
    this.category,
    this.choices = const [],
  });
  final String id;
  final String name;
  final String type;
  final Object currentValue;
  final String? description;
  final String? category;
  final List<AcpConfigChoice> choices;

  bool accepts(Object value) => type == 'boolean'
      ? value is bool
      : value is String && choices.any((choice) => choice.value == value);

  static List<AcpConfigOption> parse(Object? value) {
    if (value is! List) return const [];
    final result = <AcpConfigOption>[];
    for (final item in value.whereType<Map>()) {
      final id = item['id'];
      final name = item['name'];
      final type = item['type'];
      final current = item['currentValue'];
      if (id is! String ||
          name is! String ||
          !((type == 'select' && current is String) ||
              (type == 'boolean' && current is bool))) {
        continue;
      }
      final choices = <AcpConfigChoice>[];
      void addChoices(Object? values, [String? group]) {
        if (values is! List) return;
        for (final choice in values.whereType<Map>()) {
          if (choice['options'] is List) {
            addChoices(
              choice['options'],
              choice['name']?.toString() ?? choice['group']?.toString(),
            );
          } else if (choice['value'] is String && choice['name'] is String) {
            choices.add(
              AcpConfigChoice(
                choice['value'] as String,
                choice['name'] as String,
                group: group,
              ),
            );
          }
        }
      }

      addChoices(item['options']);
      result.add(
        AcpConfigOption(
          id: id,
          name: name,
          type: type as String,
          currentValue: current!,
          description: item['description']?.toString(),
          category: item['category']?.toString(),
          choices: choices,
        ),
      );
    }
    return result;
  }
}

class AcpConfigChoice {
  const AcpConfigChoice(this.value, this.name, {this.group});
  final String value;
  final String name;
  final String? group;
}

/// Valid only while the associated ACP connection is open.
class AcpConfigurationSession {
  AcpConfigurationSession(this.options, this.setOption);
  List<AcpConfigOption> options;
  final List<String> warnings = [];
  final Future<List<AcpConfigOption>> Function(String id, Object value)
  setOption;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void update(List<AcpConfigOption> value) {
    options = value;
    _changes.add(null);
  }

  Future<void> close() => _changes.close();
}

typedef AcpConfigure = Future<void> Function(AcpConfigurationSession session);
