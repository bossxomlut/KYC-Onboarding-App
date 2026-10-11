import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/form_field_label.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
import '../widgets/capture_preparation.dart';
import '../widgets/kyc_scaffold.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key, required this.kind});
  final MediaKind kind;
  @override
  Widget build(BuildContext context) {
    final state = context.read<KycCubit>().state;
    return BlocProvider(
      create: (_) => CaptureSettingsCubit(
        state.pendingCaptures[MediaKind.document]?.documentType ??
            state.profile?.document?.documentType ??
            DocumentType.passport,
      ),
      child: _CaptureView(kind: kind),
    );
  }
}

class CaptureSettingsCubit extends Cubit<DocumentType> {
  CaptureSettingsCubit(super.initialState);
  void select(DocumentType type) => emit(type);
}

class _CaptureView extends StatefulWidget {
  const _CaptureView({required this.kind});
  final MediaKind kind;
  @override
  State<_CaptureView> createState() => _CapturePageState();
}

class _CapturePageState extends State<_CaptureView> {
  Future<void> _capture() async {
    final cubit = context.read<KycCubit>();
    await cubit.capture(
      widget.kind,
      documentType: widget.kind == MediaKind.document
          ? context.read<CaptureSettingsCubit>().state
          : null,
    );
  }

  Future<void> _retry() async {
    await context.read<KycCubit>().retryUpload(widget.kind);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
    builder: (context, state) {
      final isDocument = widget.kind == MediaKind.document;
      final profile = state.profile;
      final draft = state.pendingCaptures[widget.kind];
      final canEdit = profile?.canEdit ?? false;
      final uploaded = isDocument ? profile?.document : profile?.selfie;
      final previewBytes = draft?.bytes ?? state.reviewMedia[widget.kind];
      final step = isDocument ? KycStep.document : KycStep.selfie;
      final canContinue =
          !state.busy &&
          canEdit &&
          draft == null &&
          uploaded != null &&
          profile!.nextStep.index > step.index;
      return KycScaffold(
        title: isDocument ? 'ID document' : 'Selfie',
        signatureHeader: KycSignatureIntro(
          currentStep: isDocument ? 2 : 3,
          title: isDocument ? 'Your identity, clearly.' : 'One quick selfie.',
          description: isDocument
              ? 'Keep every edge visible and avoid glare.'
              : 'Look straight at the camera in good light.',
        ),
        bottomBar: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (draft != null) ...[
              FilledButton(
                key: const Key('retry-upload'),
                onPressed: state.busy || !canEdit ? null : _retry,
                child: const Text('Retry upload'),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: Key('capture-${widget.kind.name}'),
              onPressed: state.busy || !canEdit ? null : _capture,
              icon: const Icon(Icons.camera_alt_outlined, size: 22),
              label: Text(
                draft != null || uploaded != null
                    ? 'Retake photo'
                    : 'Open camera',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: Key('continue-${widget.kind.name}'),
              onPressed: canContinue
                  ? () => context.pushReplacement(profile.nextStep.routePath)
                  : null,
              child: const Text('Continue'),
            ),
            const SizedBox(height: 12),
            Text(
              'JPEG or PNG · Up to 10 MB',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.muted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KycError(),
            if (isDocument)
              BlocBuilder<CaptureSettingsCubit, DocumentType>(
                builder: (context, type) => FormFieldLabel(
                  label: 'Document type',
                  child: Semantics(
                    label: 'Document type',
                    child: DropdownButtonFormField<DocumentType>(
                      key: const Key('document-type'),
                      initialValue: type,
                      style: Theme.of(context).textTheme.bodyMedium,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      decoration: const InputDecoration(),
                      items: DocumentType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.label),
                            ),
                          )
                          .toList(),
                      onChanged: state.busy || !canEdit
                          ? null
                          : (type) {
                              if (type != null) {
                                context.read<CaptureSettingsCubit>().select(
                                  type,
                                );
                              }
                            },
                    ),
                  ),
                ),
              ),
            if (isDocument) const SizedBox(height: 14),
            PrivatePhoto(
              bytes: previewBytes,
              label: isDocument ? 'Document photo' : 'Selfie photo',
              aspectRatio: isDocument && previewBytes == null ? 1.6 : 4 / 3,
              placeholder: CapturePreparation(
                isDocument: isDocument,
                hasUploadedPhoto: uploaded != null,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CaptureTip(
                    icon: isDocument ? Icons.crop_free : Icons.face_outlined,
                    text: isDocument
                        ? 'Keep all edges visible'
                        : 'Keep your face visible',
                  ),
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 26, color: AppTheme.border),
                const SizedBox(width: 16),
                Expanded(
                  child: _CaptureTip(
                    icon: isDocument
                        ? Icons.light_mode_outlined
                        : Icons.visibility_outlined,
                    text: isDocument
                        ? 'Use good lighting'
                        : 'Remove hats and sunglasses',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (state.busy) ...[
              LinearProgressIndicator(value: state.uploadProgress),
              const SizedBox(height: 12),
              Text(switch (state.operation) {
                KycOperation.capturing => 'Opening camera…',
                KycOperation.uploading =>
                  'Uploading ${((state.uploadProgress ?? 0) * 100).round()}%',
                KycOperation.loadingProfile => 'Loading your profile…',
                KycOperation.loadingMedia => 'Loading photos…',
                _ => 'Saving your progress…',
              }),
              const SizedBox(height: 16),
            ],
            if (draft != null) ...[
              const Text(
                'Your photo is kept privately on this device until upload succeeds. Retry when your connection returns.',
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      );
    },
  );
}

class _CaptureTip extends StatelessWidget {
  const _CaptureTip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppTheme.primary, size: 24),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.ink, fontSize: 11),
        ),
      ),
    ],
  );
}
