import 'package:careershopper/src/domain/job_statistics.dart';
import 'package:careershopper/src/features/statistics/application_sankey.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Sankey handles empty, complete, and thin flows in a narrow window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(440, 750));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final stats in [
        const JobStatistics(found: 0, applied: 0, interviewed: 0, offers: 0),
        const JobStatistics(found: 1, applied: 1, interviewed: 1, offers: 1),
        const JobStatistics(
          found: 100000,
          applied: 3,
          interviewed: 2,
          offers: 1,
          sources: {
            'indeed': 90000,
            'manual': 5000,
            'ashby': 3000,
            'lever': 1000,
            'greenhouse': 1000,
          },
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ApplicationSankey(statistics: stats),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sankey-found')), findsOneWidget);
        expect(find.text('Inbox'), findsOneWidget);
        expect(find.text('Not applied'), findsNothing);
        expect(find.byIcon(Icons.schedule), findsNWidgets(4));
        expect(
          find.byKey(const ValueKey('sankey-offer_waiting')),
          findsOneWidget,
        );
        final scroll = tester.widget<SingleChildScrollView>(
          find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        );
        expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
        await tester.drag(
          find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
          const Offset(-600, 0),
        );
        await tester.pumpAndSettle();
        expect(scroll.controller!.offset, greaterThan(0));
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final label = tester.getRect(
          find.byKey(const ValueKey('sankey-offer_waiting')),
        );
        expect(label.left, greaterThanOrEqualTo(0));
        expect(label.right, lessThanOrEqualTo(440));
        expect(
          tester
              .widget<Scrollbar>(find.byType(Scrollbar).first)
              .thumbVisibility,
          true,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
