class VorynProfile {
  const VorynProfile({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.vorynId,
    required this.phone,
    required this.phoneVerified,
  });

  final String uid;
  final String? email;
  final String fullName;
  final String? vorynId;
  final String? phone;
  final bool phoneVerified;

  factory VorynProfile.fromMap(Map<String, dynamic> map) {
    return VorynProfile(
      uid: map['uid'] as String? ?? map['id'] as String? ?? '',
      email: map['email'] as String?,
      fullName: map['full_name'] as String? ?? '',
      vorynId: map['voryn_id'] as String?,
      phone: map['phone'] as String?,
      phoneVerified: map['phone_verified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'full_name': fullName,
    'voryn_id': vorynId,
    'phone': phone,
    'phone_verified': phoneVerified,
  };
}
