class Profile {
  final String id;
  final String name;
  final String email;
  final String role; // 'super_admin' | 'sub_admin'
  final bool isActive;
  final String? profilePicture;
  final String? dateOfBirth;
  final String? phoneNumber;
  final DateTime createdAt;

  Profile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.profilePicture,
    this.dateOfBirth,
    this.phoneNumber,
    required this.createdAt,
  });

  bool get isSuperAdmin {
    final cleanEmail = email.trim().toLowerCase();

    // Official Super Admin account emails
    final superAdminEmails = {
      'mdnaseef2004@gmail.com',
      'shaheenmohammed554@gmail.com',
      'mampadanmujeeb@gmail.com',
    };

    return role == 'super_admin' || superAdminEmails.contains(cleanEmail);
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'sub_admin',
      isActive: json['is_active'] ?? true,
      profilePicture: json['profile_picture']?.toString(),
      dateOfBirth: json['date_of_birth']?.toString(),
      phoneNumber: json['phone_number']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'is_active': isActive,
      'profile_picture': profilePicture,
      'date_of_birth': dateOfBirth,
      'phone_number': phoneNumber,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
