class EventModel {
  final String id;
  final String eventName;
  final String eventPlace;
  final int membersCount;
  final String organizedBy;
  final DateTime eventDate;
  final String handledBy;
  final String? remarks;
  final String? createdBy;
  final DateTime createdAt;

  EventModel({
    required this.id,
    required this.eventName,
    required this.eventPlace,
    required this.membersCount,
    required this.organizedBy,
    required this.eventDate,
    required this.handledBy,
    this.remarks,
    this.createdBy,
    required this.createdAt,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      id: json['id']?.toString() ?? '',
      eventName: json['event_name'] ?? '',
      eventPlace: json['event_place'] ?? '',
      membersCount: json['members_count'] ?? 0,
      organizedBy: json['organized_by'] ?? '',
      eventDate: json['event_date'] != null
          ? DateTime.parse(json['event_date'])
          : DateTime.now(),
      handledBy: json['handled_by'] ?? '',
      remarks: json['remarks'],
      createdBy: json['created_by']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_name': eventName,
      'event_place': eventPlace,
      'members_count': membersCount,
      'organized_by': organizedBy,
      'event_date': eventDate.toIso8601String().split('T')[0],
      'handled_by': handledBy,
      'remarks': remarks,
      if (createdBy != null) 'created_by': createdBy,
    };
  }
}
