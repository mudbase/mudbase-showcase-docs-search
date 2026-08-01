/// The authenticated end-user - anonymous guest or real signed-in
/// "customer". Parsed from raw JSON rather than the bundled Dart SDK's
/// generated `User`/`LoginLocalUser200ResponseUser` models - those only type
/// `id`/`email`/`firstName`/`lastName`/`role`/`emailVerified` and silently
/// drop `customRole`/`isAnonymous` on deserialization (confirmed by reading
/// the generated model/serializer source under `mudbase-sdk/dart/lib/src/
/// model/`, same finding the sibling kanban/social/ecommerce Flutter apps
/// document). `isAnonymous`/`customRole` are exactly the two fields this
/// app's `isAuthenticated` gate (mirroring the web app's `useAuth.ts`) reads.
class MudbaseUser {
  const MudbaseUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.customRole,
    required this.emailVerified,
    required this.isAnonymous,
  });

  factory MudbaseUser.fromJson(Map<String, dynamic> json) {
    return MudbaseUser(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      customRole: json['customRole'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
      isAnonymous: json['isAnonymous'] as bool? ?? false,
    );
  }

  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String? customRole;
  final bool emailVerified;
  final bool isAnonymous;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? email : name;
  }

  /// Mirrors the web app's `useAuth().isAuthenticated`: a real, verified,
  /// signed-in account - distinct from the always-present anonymous guest
  /// session this app establishes so guests can browse the library.
  bool get isAuthenticated => !isAnonymous && customRole != null;
}
