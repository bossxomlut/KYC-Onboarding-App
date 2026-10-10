import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/current_route.dart';
import '../../../../core/widgets/form_field_label.dart';
import '../../../../core/widgets/identity_brand.dart';
import '../bloc/kyc_cubit.dart';
import '../bloc/personal_details_form_cubit.dart';
import '../widgets/date_of_birth_field.dart';
import '../widgets/kyc_scaffold.dart';

class PersonalDetailsPage extends StatelessWidget {
  const PersonalDetailsPage({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PersonalDetailsFormCubit(
      context.read<KycCubit>().state.profile?.personalDetails,
    ),
    child: const _PersonalDetailsForm(),
  );
}

class _PersonalDetailsForm extends StatelessWidget {
  const _PersonalDetailsForm();
  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, flow) =>
        BlocBuilder<PersonalDetailsFormCubit, PersonalDetailsFormState>(
          builder: (context, form) => KycScaffold(
            title: 'Personal details',
            bottomBar: (flow.profile?.canEdit ?? false)
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PrivacyNote(
                        text: 'Your progress is saved when you continue.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const Key('save-details'),
                        onPressed: flow.busy
                            ? null
                            : () async {
                                final formCubit = context
                                    .read<PersonalDetailsFormCubit>();
                                if (!formCubit.validate()) return;
                                final cubit = context.read<KycCubit>();
                                final success = await cubit.saveDetails(
                                  formCubit.state.details,
                                );
                                if (success &&
                                    context.mounted &&
                                    isCurrentRoute(context)) {
                                  context.go(
                                    cubit.state.profile!.nextStep.routePath,
                                  );
                                }
                              },
                        child: flow.busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save and continue'),
                      ),
                    ],
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const KycIntro(
                  step: 'Step 1 of 4',
                  title: 'Let’s get to know you.',
                  description: 'Use the details on your ID.',
                  icon: Icons.person_outline,
                ),
                const KycError(),
                if (!(flow.profile?.canEdit ?? false)) ...[
                  const Text(
                    'This profile is currently locked. Refresh the verification status to continue.',
                  ),
                  TextButton(
                    onPressed: () => context.go('/kyc/status'),
                    child: const Text('View status'),
                  ),
                ] else ...[
                  _field(
                    context,
                    form,
                    'fullName',
                    'Full name',
                    form.details.fullName,
                    autofillHints: const [AutofillHints.name],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DateOfBirthField(
                      value: form.details.dateOfBirth,
                      errorText: form.errors['dateOfBirth'],
                      enabled: !flow.busy,
                      onChanged: (date) => context
                          .read<PersonalDetailsFormCubit>()
                          .update('dateOfBirth', date),
                    ),
                  ),
                  _field(
                    context,
                    form,
                    'nationality',
                    'Nationality',
                    form.details.nationality,
                    hint: 'Vietnamese',
                  ),
                  _field(
                    context,
                    form,
                    'address',
                    'Residential address',
                    form.details.address,
                    autofillHints: const [AutofillHints.fullStreetAddress],
                    lines: 2,
                  ),
                  _field(
                    context,
                    form,
                    'documentNumber',
                    'Document number',
                    form.details.documentNumber,
                    capitalization: TextCapitalization.characters,
                  ),
                ],
              ],
            ),
          ),
        ),
  );
  Widget _field(
    BuildContext context,
    PersonalDetailsFormState form,
    String field,
    String label,
    String value, {
    TextInputType? keyboard,
    String? hint,
    List<String>? autofillHints,
    int lines = 1,
    TextCapitalization capitalization = TextCapitalization.words,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FormFieldLabel(
      label: label,
      child: Semantics(
        label: label,
        child: TextFormField(
          key: Key(field),
          initialValue: value,
          onChanged: (value) =>
              context.read<PersonalDetailsFormCubit>().update(field, value),
          decoration: InputDecoration(
            hintText: hint,
            errorText: form.errors[field],
          ),
          keyboardType: keyboard,
          autofillHints: autofillHints,
          maxLines: lines,
          minLines: 1,
          textCapitalization: capitalization,
          enabled: !context.read<KycCubit>().state.busy,
        ),
      ),
    ),
  );
}
