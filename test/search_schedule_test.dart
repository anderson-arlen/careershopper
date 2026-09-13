import 'package:careershopper/src/domain/search_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily schedule uses local wall time and advances at the boundary', () {
    final schedule = SearchSchedule('30 9 * * *');
    expect(
      schedule.nextAfter(DateTime(2026, 9, 12, 9)),
      DateTime(2026, 9, 12, 9, 30).toUtc(),
    );
    expect(
      schedule.nextAfter(DateTime(2026, 9, 12, 9, 30)),
      DateTime(2026, 9, 13, 9, 30).toUtc(),
    );
  });

  test('lists, ranges, and steps support multiple weekday runs', () {
    final schedule = SearchSchedule('0 9,17 * * 1-5');
    expect(
      schedule.nextAfter(DateTime(2026, 9, 11, 9)),
      DateTime(2026, 9, 11, 17).toUtc(),
    );
    expect(
      schedule.nextAfter(DateTime(2026, 9, 11, 17)),
      DateTime(2026, 9, 14, 9).toUtc(),
    );
    expect(
      SearchSchedule(
        '*/30 8-10/2 * * *',
      ).nextAfter(DateTime(2026, 9, 12, 8, 30)),
      DateTime(2026, 9, 12, 10).toUtc(),
    );
  });

  test('month/day and weekday follow cron OR semantics and Sunday aliases', () {
    expect(
      SearchSchedule('0 9 1 * 1').nextAfter(DateTime(2026, 9, 12)),
      DateTime(2026, 9, 14, 9).toUtc(),
    );
    for (final sunday in [0, 7]) {
      expect(
        SearchSchedule('0 9 * * $sunday').nextAfter(DateTime(2026, 9, 12)),
        DateTime(2026, 9, 13, 9).toUtc(),
      );
    }
    expect(
      SearchSchedule('0 9 29 2 *').nextAfter(DateTime(2026, 9, 12)),
      DateTime(2028, 2, 29, 9).toUtc(),
    );
  });

  test('rejects malformed and impossible schedules', () {
    for (final expression in [
      '',
      '* * * *',
      '60 9 * * *',
      '0 24 * * *',
      '*/0 * * * *',
      '0 9 * 13 *',
      '0 9 * * 8',
      '0 9 30 2 *',
    ]) {
      expect(
        () => SearchSchedule(expression).nextAfter(DateTime(2026)),
        throwsArgumentError,
        reason: expression,
      );
    }
  });

  test('DST gaps are skipped and repeated local times occur once', () {
    // Run this suite with TZ=America/Denver to exercise these transitions.
    if (DateTime(2026, 1).timeZoneOffset == DateTime(2026, 7).timeZoneOffset) {
      return;
    }
    expect(
      SearchSchedule('30 2 * * *').nextAfter(DateTime(2026, 3, 8)),
      DateTime(2026, 3, 9, 2, 30).toUtc(),
    );
    final repeated = SearchSchedule('30 1 * * *');
    final first = repeated.nextAfter(DateTime(2026, 11, 1));
    expect(repeated.nextAfter(first), DateTime(2026, 11, 2, 1, 30).toUtc());
  });
}
