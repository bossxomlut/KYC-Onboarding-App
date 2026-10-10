import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/kyc_profile.dart';
import '../bloc/kyc_cubit.dart';
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

class _CapturePageState extends State<_CaptureView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<KycCubit>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _capture() async {
    final cubit = context.read<KycCubit>();
    final success = await cubit.capture(
      widget.kind,
      documentType: widget.kind == MediaKind.document
          ? context.read<CaptureSettingsCubit>().state
          : null,
    );
    if (success && mounted) context.go(cubit.state.profile!.nextStep.routePath);
  }

  Future<void> _retry() async {
    final cubit = context.read<KycCubit>();
    final success = await cubit.retryUpload(widget.kind);
    if (success && mounted) context.go(cubit.state.profile!.nextStep.routePath);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KycCubit, KycState>(
        builder: (context, state) {
          final isDocument = widget.kind == MediaKind.document;
          final draft = state.pendingCaptures[widget.kind];
          final canEdit = state.profile?.canEdit ?? false;
          return KycScaffold(
            title: isDocument ? 'ID document' : 'Selfie',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KycIntro(
                  step: isDocument ? 'Step 2 of 4' : 'Step 3 of 4',
                  title: isDocument
                      ? 'Your identity, clearly.'
                      : 'One quick selfie.',
                  description: isDocument
                      ? 'Place the entire document in frame. Keep every edge visible and avoid glare.'
                      : 'Face the camera in good light. Remove hats and sunglasses, and keep your face fully visible.',
                  icon: isDocument ? Icons.badge_outlined : Icons.face_outlined,
                ),
                const KycError(),
                if (isDocument)
                  BlocBuilder<CaptureSettingsCubit, DocumentType>(
                    builder: (context, type) =>
                        DropdownButtonFormField<DocumentType>(
                      key: const Key('document-type'),
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: 'Document type',
                      ),
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
                const SizedBox(height: 20),
                PrivatePhoto(
                  bytes: draft?.bytes ?? state.reviewMedia[widget.kind],
                  label: isDocument ? 'Document photo' : 'Selfie photo',
                ),
                const SizedBox(height: 20),
                if (state.busy) ...[
                  LinearProgressIndicator(value: state.uploadProgress),
                  const SizedBox(height: 12),
                  Text(
                    state.uploadProgress == null
                        ? 'Opening camera…'
                        : 'Uploading ${(state.uploadProgress! * 100).round()}%',
                  ),
                  const SizedBox(height: 16),
                ],
                if (draft != null) ...[
                  const Text(
                    'Your photo is kept privately on this device until upload succeeds. Retry when your connection returns.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('retry-upload'),
                    onPressed: state.busy || !canEdit ? null : _retry,
                    child: const Text('Retry upload'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  key: Key('capture-${widget.kind.name}'),
                  onPressed: state.busy || !canEdit ? null : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(draft == null ? 'Open camera' : 'Retake photo'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Photos must be JPEG or PNG, up to 10 MB. Camera access is required; enable it in device Settings if permission is denied.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );
}
