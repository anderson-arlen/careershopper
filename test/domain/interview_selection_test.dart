import 'dart:math';
import 'package:careershopper/src/domain/interview.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/interview_data.dart';

Map<String, Object?> question(
  String id, [
  List<String> dependencies = const [],
]) => {
  ...interviewQuestion(),
  'id': id,
  'prompt': 'Prompt $id',
  'depends_on': dependencies,
};

void main() {
  test(
    'difficulty suitability precedes novelty while dependencies stay intact',
    () {
      final bank = [
        {...question('easy'), 'difficulty': 2},
        {...question('hard'), 'difficulty': 5},
        {
          ...question('follow', ['easy']),
          'difficulty': 2,
        },
      ];
      final easy = randomizedInterviewQuestions(
        bank,
        {'prompt easy': 10},
        random: Random(1),
        difficulty: 2,
      );
      expect(easy.map((q) => q['id']), ['easy', 'follow', 'hard']);
      final hard = randomizedInterviewQuestions(
        bank,
        {},
        random: Random(1),
        difficulty: 5,
      );
      expect(hard.map((q) => q['id']), ['hard', 'easy', 'follow']);
    },
  );

  test(
    'random orders vary while every prerequisite precedes its dependent',
    () {
      final bank = [
        question('a'),
        question('b'),
        question('c', ['a']),
        question('d', ['b', 'c']),
      ];
      final orders = <String>{};
      for (var seed = 0; seed < 30; seed++) {
        final result = randomizedInterviewQuestions(
          bank,
          {},
          random: Random(seed),
        );
        final ids = result.map((q) => q['id']).toList();
        expect(ids.toSet(), {'a', 'b', 'c', 'd'});
        expect(ids.indexOf('a'), lessThan(ids.indexOf('c')));
        expect(ids.indexOf('c'), lessThan(ids.indexOf('d')));
        expect(ids.indexOf('b'), lessThan(ids.indexOf('d')));
        orders.add(ids.join(','));
      }
      expect(orders.length, greaterThan(1));
    },
  );
  test(
    'novelty chooses among eligible questions without breaking prerequisites',
    () {
      final bank = [
        question('old'),
        question('new'),
        question('dependent', ['old']),
      ];
      final result = randomizedInterviewQuestions(bank, {
        'prompt old': 3,
      }, random: Random(1));
      expect(result.map((q) => q['id']), ['new', 'old', 'dependent']);
    },
  );
  test(
    'missing, archived, foreign-stage and cyclic prerequisites are rejected',
    () {
      for (final bank in [
        [
          question('a', ['missing']),
        ],
        [
          question('a', ['a']),
        ],
        [
          question('a', ['b']),
          question('b', ['a']),
        ],
        [
          question('a', ['b']),
          {...question('b'), 'archived': true},
        ],
        [
          question('a', ['b']),
          {...question('b'), 'stage_id': 'other'},
        ],
      ]) {
        expect(
          () => validateInterviewQuestionDependencies(bank),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'bank targets cover several sessions independently of practice length',
    () {
      expect(interviewQuestionTarget({'duration_minutes': 20}), 40);
      expect(interviewQuestionTarget({'duration_minutes': 60}), 60);
      expect(interviewQuestionTarget({'duration_minutes': 90}), 90);
    },
  );
}
