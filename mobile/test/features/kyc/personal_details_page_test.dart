import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kyc_onboarding/core/theme/app_theme.dart';
import 'package:kyc_onboarding/features/kyc/domain/entities/kyc_profile.dart';
import 'package:kyc_onboarding/features/kyc/domain/usecases/kyc_usecases.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/kyc_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/bloc/personal_details_form_cubit.dart';
import 'package:kyc_onboarding/features/kyc/presentation/pages/personal_details_page.dart';
import 'kyc_cubit_test.dart' show FakeKycRepository;

void main() {
  testWidgets('birth date opens a wheel picker without manual typing', (
    tester,
  ) async {
    await pumpDetails(tester);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('dateOfBirth')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.readOnly, isTrue);
    await openPicker(tester);
    expect(tester.testTextInput.isVisible, isFalse);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.mode, CupertinoDatePickerMode.date);
    expect(find.text('Select your date of birth'), findsOneWidget);
  });

  testWidgets('picker includes every valid age from 18 through 120', (
    tester,
  ) async {
    await pumpDetails(tester);
    await openPicker(tester);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    final now = DateTime.now();
    final minimum = picker.minimumDate!;
    final maximum = picker.maximumDate!;
    expect(detailsAt(minimum).validate(now), isEmpty);
    expect(detailsAt(maximum).validate(now), isEmpty);
    expect(
      detailsAt(
        DateTime(minimum.year, minimum.month, minimum.day - 1),
      ).validate(now),
      contains('dateOfBirth'),
    );
    expect(
      detailsAt(
        DateTime(maximum.year, maximum.month, maximum.day + 1),
      ).validate(now),
      contains('dateOfBirth'),
    );
  });

  testWidgets(
    'confirming updates the draft as ISO and displays a friendly date',
    (tester) async {
      await pumpDetails(tester);
      await openPicker(tester);
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(1995, 4, 15));
      await tester.tap(find.byKey(const Key('confirm-date-of-birth')));
      await tester.pumpAndSettle();
      expect(formCubit(tester).state.details.dateOfBirth, '1995-04-15');
      expect(find.text('15 April 1995'), findsOneWidget);
      await openPicker(tester);
      expect(
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .initialDateTime,
        DateTime(1995, 4, 15),
      );
    },
  );

  testWidgets(
    'cancel keeps the saved birth date and validation remains active',
    (tester) async {
      await pumpDetails(tester, initial: detailsAt(DateTime(1995, 4, 15)));
      final form = formCubit(tester);
      expect(form.validate(), isTrue);
      await openPicker(tester);
      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(1990, 1, 1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(form.state.details.dateOfBirth, '1995-04-15');
      expect(find.text('15 April 1995'), findsOneWidget);
      expect(form.validate(), isTrue);
    },
  );

  testWidgets('a selected date clears a missing-date error', (tester) async {
    await pumpDetails(tester);
    final form = formCubit(tester);
    expect(form.validate(), isFalse);
    await tester.pumpAndSettle();
    expect(form.state.errors, contains('dateOfBirth'));
    await openPicker(tester);
    await tester.tap(find.byKey(const Key('confirm-date-of-birth')));
    await tester.pumpAndSettle();
    expect(form.state.errors, isNot(contains('dateOfBirth')));
    expect(form.state.details.dateOfBirth, isNotEmpty);
  });
}

Future<void> pumpDetails(
  WidgetTester tester, {
  PersonalDetails? initial,
}) async {
  final repository = FakeKycRepository()
    ..profile = KycProfile(
      id: 'profile-demo',
      status: KycStatus.inProgress,
      nextStep: KycStep.personalDetails,
      personalDetails: initial,
    );
  final cubit = KycCubit(
    loadKyc: LoadKyc(repository),
    savePersonalDetails: SavePersonalDetails(repository),
    captureMedia: CaptureMedia(repository),
    uploadMedia: UploadMedia(repository),
    loadPrivateMedia: LoadPrivateMedia(repository),
    submitKyc: SubmitKyc(repository),
    resubmitKyc: ResubmitKyc(repository),
    recoverCapture: RecoverCapture(repository),
    discardLocalMedia: DiscardLocalMedia(repository),
  );
  final router = GoRouter(
    initialLocation: '/kyc/details',
    routes: [
      GoRoute(
        path: '/kyc/details',
        builder: (_, _) => const PersonalDetailsPage(),
      ),
    ],
  );
  addTearDown(() async {
    router.dispose();
    await cubit.close();
  });
  await cubit.load();
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openPicker(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('dateOfBirth')));
  await tester.tap(find.byKey(const Key('dateOfBirth')));
  await tester.pumpAndSettle();
}

PersonalDetailsFormCubit formCubit(WidgetTester tester) => tester
    .element(find.byKey(const Key('dateOfBirth')))
    .read<PersonalDetailsFormCubit>();

PersonalDetails detailsAt(DateTime date) => PersonalDetails(
  fullName: 'Demo User',
  dateOfBirth: date.toIso8601String().substring(0, 10),
  nationality: 'Vietnamese',
  address: '1 Demo Street',
  documentNumber: 'DEMO1234',
);
