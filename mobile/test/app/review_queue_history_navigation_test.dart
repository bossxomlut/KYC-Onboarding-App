import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';

import 'system_back_test.dart' show pumpApp;

void main() {
  testWidgets(
    'completed profile history uses toolbar Back to return to the review list',
    (tester) async {
      final (_, router) = await pumpApp(
        tester,
        location: '/reviews',
        role: UserRole.superAdmin,
      );
      router.push<void>('/reviews/applicant/history?from=queue');
      await tester.pumpAndSettle();
      expect(find.text('Back to review queue'), findsNothing);
      expect(find.text('Back to current review'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/reviews');
      expect(find.text('Review profiles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
