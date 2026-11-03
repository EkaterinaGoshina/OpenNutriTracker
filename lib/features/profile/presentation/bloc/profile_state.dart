part of 'profile_bloc.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();
}

class ProfileInitial extends ProfileState {
  @override
  List<Object> get props => [];
}

class ProfileLoadingState extends ProfileState {
  @override
  List<Object?> get props => [];
}

class ProfileLoadedState extends ProfileState {
  final UserBMIEntity userBMI;
  final UserEntity userEntity;

  // Granular unit preferences. Height (cm/ft) and body weight (kg/lb/st) are
  // chosen independently of the food unit preference.
  final BodyWeightUnit bodyWeightUnit;
  final bool usesImperialHeightUnits;

  const ProfileLoadedState({
    required this.userBMI,
    required this.userEntity,
    required this.bodyWeightUnit,
    required this.usesImperialHeightUnits,
  });

  @override
  List<Object?> get props => [
        userBMI,
        userEntity,
        bodyWeightUnit,
        usesImperialHeightUnits,
      ];
}
