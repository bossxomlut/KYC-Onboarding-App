import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/kyc_scaffold.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KycCubit>().loadReviewMedia();
    });
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final profile = state.profile;
      final details = profile?.personalDetails;
      return KycScaffold(
        title: 'Review & submit',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KycIntro(
              step: 'Step 4 of 4',
              title: 'Everything look right?',
              description:
                  'Check your details and photos before sending your profile for verification.',
              icon: Icons.fact_check_outlined,
            ),
            KycError(onRetry: () => context.read<KycCubit>().loadReviewMedia()),
            if (state.busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            _heading(
              'Personal details',
              profile?.canEdit ?? false,
              () => context.go('/kyc/details'),
            ),
            if (details == null)
              const Text('Personal details are incomplete.')
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detail('Full name', details.fullName),
                      _detail('Date of birth', details.dateOfBirth),
                      _detail('Nationality', details.nationality),
                      _detail('Residential address', details.address),
                      _detail('Document number', details.documentNumber),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            _heading(
              'ID document',
              profile?.canEdit ?? false,
              () => context.go('/kyc/document'),
            ),
            if (profile?.document?.documentType != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(profile!.document!.documentType!.label),
              ),
            PrivatePhoto(
              bytes: state.reviewMedia[MediaKind.document],
              label: 'Your private document photo',
            ),
            const SizedBox(height: 20),
            _heading(
              'Selfie',
              profile?.canEdit ?? false,
              () => context.go('/kyc/selfie'),
            ),
            PrivatePhoto(
              bytes: state.reviewMedia[MediaKind.selfie],
              label: 'Your private selfie photo',
            ),
            const SizedBox(height: 24),
            const Text(
              'By submitting, you confirm that these details are accurate. You can follow the review result from your home screen.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('submit-kyc'),
              onPressed: state.busy || !(profile?.canSubmit ?? false)
                  ? null
                  : () async {
                      final cubit = context.read<KycCubit>();
                      final success = await cubit.submit();
                      if (success && context.mounted) {
                        context.go('/kyc/status');
                      }
                    },
              child: const Text('Submit for verification'),
            ),
          ],
        ),
      );
    },
  );
  Widget _heading(String title, bool editable, VoidCallback onEdit) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (editable) TextButton(onPressed: onEdit, child: const Text('Edit')),
    ],
  );
  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );
}
