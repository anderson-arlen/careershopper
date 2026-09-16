import 'dart:convert';

String? formatEmploymentType(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim().replaceAllMapped(
    RegExp(
      r'full[\s_-]*time|part[\s_-]*time|contract|internship',
      caseSensitive: false,
    ),
    (match) =>
        switch (match[0]!.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '')) {
          'fulltime' => 'Full-time',
          'parttime' => 'Part-time',
          'contract' => 'Contract',
          _ => 'Internship',
        },
  );
}

String? formatCompensation(
  num? minimum,
  num? maximum,
  String? currency, {
  String? period,
}) {
  if (minimum == null && maximum == null) return null;
  String amount(num value) => value
      .toString()
      .replaceFirst(RegExp(r'\.0$'), '')
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(\.|$))'), (m) => '${m[1]},');
  final range = minimum == maximum
      ? amount(minimum!)
      : minimum == null
      ? 'Up to ${amount(maximum!)}'
      : maximum == null
      ? 'From ${amount(minimum)}'
      : '${amount(minimum)} – ${amount(maximum)}';
  return '${currency == null || currency.isEmpty ? '' : '$currency '}$range · ${period ?? 'pay period not specified'}';
}

String? compensationFromJson(String? value) {
  if (value == null) return null;
  final data = jsonDecode(value) as Map<String, dynamic>;
  final text = data['text'] as String?;
  if (text != null && text.trim().isNotEmpty) return text.trim();
  return formatCompensation(
    data['minimum'] as num?,
    data['maximum'] as num?,
    data['currency'] as String?,
  );
}

String? indeedEmploymentType(Map<String, dynamic> record) {
  final attributes = record['attributes'];
  if (attributes is! List) return null;
  final types = attributes
      .whereType<Map>()
      .map((a) => a['label'])
      .whereType<String>()
      .where(
        (label) => const {
          'full-time',
          'part-time',
          'contract',
          'internship',
          'temporary',
          'permanent',
          'seasonal',
        }.contains(label.toLowerCase()),
      )
      .toSet();
  return types.isEmpty ? null : types.join(' · ');
}

String? indeedCompensationText(Map<String, dynamic> record) {
  final compensation = record['compensation'];
  if (compensation is! Map) return null;
  final salary = compensation['baseSalary'];
  if (salary is! Map || salary['range'] is! Map) return null;
  final range = salary['range'] as Map;
  final period = switch (salary['unitOfWork']) {
    'YEAR' => 'per year',
    'MONTH' => 'per month',
    'WEEK' => 'per week',
    'DAY' => 'per day',
    'HOUR' => 'per hour',
    _ => null,
  };
  return formatCompensation(
    range['min'] is num ? range['min'] as num : null,
    range['max'] is num ? range['max'] as num : null,
    compensation['currencyCode'] is String
        ? compensation['currencyCode'] as String
        : null,
    period: period,
  );
}
