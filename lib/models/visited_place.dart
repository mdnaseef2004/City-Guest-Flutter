class VisitedPlace {
  final String? id;
  final String? guestVisitId;
  final String visitedPlace;
  final String? visitDate;
  final String? timeIn;
  final String? timeOut;

  VisitedPlace({
    this.id,
    this.guestVisitId,
    required this.visitedPlace,
    this.visitDate,
    this.timeIn,
    this.timeOut,
  });

  factory VisitedPlace.fromJson(Map<String, dynamic> json) {
    return VisitedPlace(
      id: json['id']?.toString(),
      guestVisitId: json['guest_visit_id']?.toString(),
      visitedPlace: json['visited_place'] ?? '',
      visitDate: json['visit_date']?.toString(),
      timeIn: json['time_in']?.toString(),
      timeOut: json['time_out']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (guestVisitId != null) 'guest_visit_id': guestVisitId,
      'visited_place': visitedPlace,
      'visit_date': visitDate,
      'time_in': timeIn,
      'time_out': timeOut,
    };
  }
}
