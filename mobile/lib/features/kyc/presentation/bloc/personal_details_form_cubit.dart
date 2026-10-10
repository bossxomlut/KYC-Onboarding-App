import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/kyc_profile.dart';

class PersonalDetailsFormState extends Equatable {
  const PersonalDetailsFormState(this.details, {this.errors = const {}});
  final PersonalDetails details;
  final Map<String, String> errors;
  @override
  List<Object?> get props => [details, errors];
}

/// Page-scoped form draft; backend progress remains owned by the KYC flow.
class PersonalDetailsFormCubit extends Cubit<PersonalDetailsFormState> {
  PersonalDetailsFormCubit(PersonalDetails? initial)
      : super(
          PersonalDetailsFormState(
            initial ??
                const PersonalDetails(
                  fullName: '',
                  dateOfBirth: '',
                  nationality: '',
                  address: '',
                  documentNumber: '',
                ),
          ),
        );
  void update(String field, String value) {
    final d = state.details;
    emit(
      PersonalDetailsFormState(
        PersonalDetails(
          fullName: field == 'fullName' ? value : d.fullName,
          dateOfBirth: field == 'dateOfBirth' ? value : d.dateOfBirth,
          nationality: field == 'nationality' ? value : d.nationality,
          address: field == 'address' ? value : d.address,
          documentNumber: field == 'documentNumber' ? value : d.documentNumber,
        ),
        errors: {...state.errors}..remove(field),
      ),
    );
  }

  bool validate() {
    final errors = state.details.validate(DateTime.now());
    emit(
      PersonalDetailsFormState(state.details, errors: Map.unmodifiable(errors)),
    );
    return errors.isEmpty;
  }
}
