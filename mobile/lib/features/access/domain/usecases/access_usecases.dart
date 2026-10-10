import '../../../../core/domain/result.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../kyc/domain/entities/kyc_profile.dart';
import '../entities/access_entities.dart';
import '../repositories/access_repository.dart';

/// A related set of administrative actions; presentation receives only this
/// domain contract and never reaches through to HTTP or repositories.
class AccessUseCases {
  const AccessUseCases(this._repository);
  final AccessRepository _repository;
  Future<Result<User>> currentUser() => _repository.currentUser();
  Future<Result<RoleRequest?>> ownRequest() => _repository.ownRequest();
  Future<Result<RoleRequest>> requestReviewer(String reason) {
    final text = reason.trim();
    if (text.length < 10 || text.length > 1000) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'VALIDATION',
            message: 'Explain your request in 10–1000 characters.',
          ),
        ),
      );
    }
    return _repository.requestReviewer(text);
  }

  Future<Result<PageResult<ManagedUser>>> users({int offset = 0}) =>
      _repository.users(offset: offset);
  Future<Result<User>> createUser({
    required String email,
    required String password,
    required UserRole role,
  }) {
    if (role == UserRole.superAdmin) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'VALIDATION',
            message: 'The super admin account is protected.',
          ),
        ),
      );
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) ||
        email.trim().length > 254) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'VALIDATION',
            message: 'Enter a valid email address.',
          ),
        ),
      );
    }
    if (password.length < 12 ||
        password.length > 128 ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'VALIDATION',
            message:
                'Use 12–128 characters with uppercase, lowercase and a number.',
          ),
        ),
      );
    }
    return _repository.createUser(
      email: email.trim().toLowerCase(),
      password: password,
      role: role,
    );
  }

  Future<Result<User>> changeRole(
    String userId,
    UserRole role, {
    String? reason,
  }) {
    if (role == UserRole.superAdmin) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'VALIDATION',
            message: 'The super admin account is protected.',
          ),
        ),
      );
    }
    return _repository.changeRole(userId, role, reason: reason);
  }

  Future<Result<PageResult<RoleRequest>>> requests({int offset = 0}) =>
      _repository.requests(offset: offset);
  Future<Result<RoleRequest>> decideRequest(
    String requestId,
    RoleRequestStatus decision, {
    String? reason,
  }) {
    if (decision == RoleRequestStatus.pending) {
      return Future.value(
        const Failure(
          AppFailure(code: 'VALIDATION', message: 'Choose approve or reject.'),
        ),
      );
    }
    return _repository.decideRequest(
      requestId,
      decision,
      reason: reason?.trim(),
    );
  }

  Future<Result<PageResult<ReviewSummary>>> reviewQueue({int offset = 0}) =>
      _repository.reviewQueue(offset: offset);
  Future<Result<ReviewDetail>> reviewDetail(String userId) =>
      _repository.reviewDetail(userId);
  Future<Result<KycProfile>> decideProfile(
    String userId,
    ReviewDecision decision, {
    String? actorId,
    String? reason,
    List<KycStep> requiredSteps = const [],
  }) {
    if (actorId == userId) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'SELF_REVIEW',
            message: 'You cannot review your own profile.',
          ),
        ),
      );
    }
    if (decision == ReviewDecision.rejected &&
        ((reason?.trim().length ?? 0) < 3 ||
            (reason?.trim().length ?? 0) > 1000 ||
            requiredSteps.isEmpty ||
            requiredSteps.any(
              (step) => ![
                KycStep.personalDetails,
                KycStep.document,
                KycStep.selfie,
              ].contains(step),
            ))) {
      return Future.value(
        const Failure(
          AppFailure(
            code: 'VALIDATION',
            message:
                'Give a reason (3–1000 characters) and select at least one step to update.',
          ),
        ),
      );
    }
    return _repository.decideProfile(
      userId,
      decision,
      reason: reason?.trim(),
      requiredSteps: requiredSteps,
    );
  }

  // Kept in the domain facade so byte loading remains behind a use case.
  Future<Result<List<int>>> media(String userId, MediaKind kind) async {
    final result = await _repository.reviewMedia(userId, kind);
    return switch (result) {
      Success(:final value) => Success(value),
      Failure(:final error) => Failure(error),
    };
  }
}
