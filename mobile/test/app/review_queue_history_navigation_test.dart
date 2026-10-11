import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_onboarding/features/auth/domain/entities/user.dart';

import 'system_back_test.dart' show pumpApp;

void main() {
  testWidgets('completed profile history returns to the review list', (
    tester,
  ) async {
    final (_, router) = await pumpApp(
      tester,
      location: '/reviews/applicant/history?from=queue',
      role: UserRole.superAdmin,
    );
    expect(find.text('Back to review queue'), findsOneWidget);
    expect(find.text('Back to current review'), findsNothing);
    await tester.tap(find.text('Back to review queue'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reviews');
    expect(find.text('Review profiles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
