import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.displayName,
    required this.email,
    this.photoUrl,
  });

  final String id;
  final String displayName;
  final String email;
  final String? photoUrl;

  @override
  List<Object?> get props => [id, displayName, email, photoUrl];
}
