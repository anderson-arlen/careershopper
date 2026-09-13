/// Five-field numeric cron schedules, interpreted in the computer's local time.
class SearchSchedule {
  SearchSchedule(String expression) : expression = expression.trim() {
    final fields = this.expression.split(RegExp(r'\s+'));
    if (fields.length != 5) {
      throw ArgumentError(
        'Use five cron fields: minute hour day month weekday.',
      );
    }
    minutes = _parse(fields[0], 0, 59);
    hours = _parse(fields[1], 0, 23);
    days = _parse(fields[2], 1, 31);
    months = _parse(fields[3], 1, 12);
    weekdays = _parse(fields[4], 0, 7).map((v) => v % 7).toSet();
    _anyDay = fields[2].startsWith('*');
    _anyWeekday = fields[4].startsWith('*');
  }

  final String expression;
  late final Set<int> minutes, hours, days, months, weekdays;
  late final bool _anyDay, _anyWeekday;

  static Set<int> _parse(String field, int min, int max) {
    final values = <int>{};
    for (final part in field.split(',')) {
      final stepped = part.split('/');
      if (stepped.length > 2) throw ArgumentError('Invalid cron field: $field');
      final step = stepped.length == 2 ? int.tryParse(stepped[1]) : 1;
      if (step == null || step < 1 || step > max - min + 1) {
        throw ArgumentError('Invalid cron step: $field');
      }
      final range = stepped[0].split('-');
      final int? start, end;
      if (stepped[0] == '*') {
        start = min;
        end = max;
      } else {
        start = int.tryParse(range[0]);
        end = range.length == 2
            ? int.tryParse(range[1])
            : stepped.length == 2
            ? max
            : start;
      }
      if (range.length > 2 ||
          start == null ||
          end == null ||
          start < min ||
          end > max ||
          start > end) {
        throw ArgumentError('Cron field must be within $min–$max: $field');
      }
      for (var value = start; value <= end; value += step) {
        values.add(value);
      }
    }
    return values;
  }

  DateTime nextAfter(DateTime instant) {
    final local = instant.toLocal();
    final sortedHours = hours.toList()..sort();
    final sortedMinutes = minutes.toList()..sort();
    // Eight years includes the longest gap between leap days around a century.
    for (var offset = 0; offset <= 366 * 8; offset++) {
      final day = DateTime(local.year, local.month, local.day + offset);
      if (!months.contains(day.month)) continue;
      final dayMatches = days.contains(day.day);
      final weekdayMatches = weekdays.contains(day.weekday % 7);
      final matches = _anyDay || _anyWeekday
          ? dayMatches && weekdayMatches
          : dayMatches || weekdayMatches;
      if (!matches) continue;
      for (final hour in sortedHours) {
        for (final minute in sortedMinutes) {
          final candidate = DateTime(
            day.year,
            day.month,
            day.day,
            hour,
            minute,
          );
          // Skip nonexistent local times during the spring DST transition.
          if (candidate.day == day.day &&
              candidate.hour == hour &&
              candidate.minute == minute &&
              candidate.isAfter(instant)) {
            return candidate.toUtc();
          }
        }
      }
    }
    throw ArgumentError(
      'Cron schedule has no occurrence in the next eight years.',
    );
  }
}
