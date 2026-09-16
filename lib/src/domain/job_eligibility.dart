const unmetJobRequirementsSchema = {
  'type': 'array',
  'maxItems': 50,
  'description':
      'Confirmed unmet mandatory qualifications, independently excluding automatic Inbox placement. Required even when empty. Preferred qualifications and unknown applicant qualifications are not blockers. Honor explicitly allowed equivalent experience. Quote saved posting evidence and cite current confirmed applicant facts.',
  'items': {
    'type': 'object',
    'properties': {
      'requirement': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
      'posting_evidence': {'type': 'string', 'minLength': 1, 'maxLength': 4000},
      'applicant_evidence': {
        'type': 'string',
        'minLength': 1,
        'maxLength': 4000,
      },
      'fact_revision_ids': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 50,
        'items': {'type': 'string'},
      },
    },
    'required': [
      'requirement',
      'posting_evidence',
      'applicant_evidence',
      'fact_revision_ids',
    ],
    'additionalProperties': false,
  },
};

List<Map<String, Object?>> validateUnmetJobRequirements(
  Object? value, {
  required String posting,
  required Set<String> factRevisionIds,
}) {
  if (value is! List || value.length > 50) {
    throw const FormatException(
      'Submit unmet_requirements as an array; use [] only after checking for confirmed unmet mandatory qualifications.',
    );
  }
  String normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final result = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map ||
        item.keys.toSet().difference({
          'requirement',
          'posting_evidence',
          'applicant_evidence',
          'fact_revision_ids',
        }).isNotEmpty) {
      throw const FormatException('Invalid unmet requirement object.');
    }
    for (final field in [
      'requirement',
      'posting_evidence',
      'applicant_evidence',
    ]) {
      if (item[field] is! String ||
          (item[field] as String).trim().isEmpty ||
          (item[field] as String).length >
              (field == 'requirement' ? 2000 : 4000)) {
        throw FormatException(
          'Each unmet requirement needs nonempty $field within its length limit.',
        );
      }
    }
    if (!normalize(
      posting,
    ).contains(normalize(item['posting_evidence'] as String))) {
      throw const FormatException(
        'posting_evidence must quote the saved job title or description exactly.',
      );
    }
    final ids = item['fact_revision_ids'];
    if (ids is! List ||
        ids.isEmpty ||
        ids.length > 50 ||
        ids.any((id) => id is! String || !factRevisionIds.contains(id))) {
      throw const FormatException(
        'Each unmet requirement must cite current confirmed applicant fact revision IDs from profile_get.',
      );
    }
    result.add(Map<String, Object?>.from(item));
  }
  return result;
}
