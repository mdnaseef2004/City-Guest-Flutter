class GuestAssignment {
  final String id;
  final String guestName;
  final String? notes;
  final String assignedTo;
  final String? assignedToName;
  final String assignedBy;
  final String? assignedByName;
  final String status; // 'pending' | 'in_progress' | 'completed'
  final DateTime? dueDate;
  final bool isUrgent;
  final DateTime createdAt;

  GuestAssignment({
    required this.id,
    required this.guestName,
    this.notes,
    required this.assignedTo,
    this.assignedToName,
    required this.assignedBy,
    this.assignedByName,
    required this.status,
    this.dueDate,
    this.isUrgent = false,
    required this.createdAt,
  });

  factory GuestAssignment.fromJson(Map<String, dynamic> json) {
    String? assignedToName;
    if (json['profiles_assigned_to'] != null && json['profiles_assigned_to'] is Map) {
      assignedToName = json['profiles_assigned_to']['name'];
    }

    String? assignedByName;
    if (json['profiles_assigned_by'] != null && json['profiles_assigned_by'] is Map) {
      assignedByName = json['profiles_assigned_by']['name'];
    }

    return GuestAssignment(
      id: json['id']?.toString() ?? '',
      guestName: json['guest_name'] ?? '',
      notes: json['notes'],
      assignedTo: json['assigned_to']?.toString() ?? '',
      assignedToName: assignedToName,
      assignedBy: json['assigned_by']?.toString() ?? '',
      assignedByName: assignedByName,
      status: json['status'] ?? 'pending',
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      isUrgent: json['is_urgent'] ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}
