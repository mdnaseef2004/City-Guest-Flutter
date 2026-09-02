import 'visited_place.dart';

class GuestVisit {
  final String id;
  final String guestName;
  final String phoneNumber;
  final String? occupation;
  final String? photoUrl;
  final String place;
  final String district;
  final String? state;
  final String? country;
  final bool isInternational;
  final String purpose;
  final double donationAmount;
  final String? receiptNo;
  final String? donationTo;
  final String? pickedFrom;
  final String? pickedDate;
  final String? pickedTime;
  final String? guestReturned;
  final String? returnDate;
  final String? returnTime;
  final String? handledBy;
  final String? remarks;
  final String? pdfUrl;
  final String createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final List<VisitedPlace> visitedPlaces;

  GuestVisit({
    required this.id,
    required this.guestName,
    required this.phoneNumber,
    this.occupation,
    this.photoUrl,
    required this.place,
    required this.district,
    this.state,
    this.country,
    this.isInternational = false,
    required this.purpose,
    this.donationAmount = 0.0,
    this.receiptNo,
    this.donationTo,
    this.pickedFrom,
    this.pickedDate,
    this.pickedTime,
    this.guestReturned,
    this.returnDate,
    this.returnTime,
    this.handledBy,
    this.remarks,
    this.pdfUrl,
    required this.createdBy,
    this.createdByName,
    required this.createdAt,
    this.visitedPlaces = const [],
  });

  factory GuestVisit.fromJson(Map<String, dynamic> json) {
    List<VisitedPlace> places = [];
    if (json['visited_places'] != null && json['visited_places'] is List) {
      places = (json['visited_places'] as List)
          .map((vp) => VisitedPlace.fromJson(vp))
          .toList();
    }

    String? creatorName;
    if (json['profiles'] != null && json['profiles'] is Map) {
      creatorName = json['profiles']['name'];
    }

    return GuestVisit(
      id: json['id']?.toString() ?? '',
      guestName: json['guest_name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      occupation: json['occupation'],
      photoUrl: json['photo_url'],
      place: json['place'] ?? '',
      district: json['district'] ?? '',
      state: json['state'],
      country: json['country'],
      isInternational: json['is_international'] ?? false,
      purpose: json['purpose'] ?? '',
      donationAmount: (json['donation_amount'] ?? 0).toDouble(),
      receiptNo: json['receipt_no'],
      donationTo: json['donation_to'],
      pickedFrom: json['picked_from'],
      pickedDate: json['picked_date']?.toString(),
      pickedTime: json['picked_time']?.toString(),
      guestReturned: json['guest_returned'],
      returnDate: json['return_date']?.toString(),
      returnTime: json['return_time']?.toString(),
      handledBy: json['handled_by'],
      remarks: json['remarks'],
      pdfUrl: json['pdf_url'],
      createdBy: json['created_by']?.toString() ?? '',
      createdByName: creatorName,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      visitedPlaces: places,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guest_name': guestName,
      'phone_number': phoneNumber,
      'occupation': occupation,
      'photo_url': photoUrl,
      'place': place,
      'district': district,
      'state': state,
      'country': country,
      'is_international': isInternational,
      'purpose': purpose,
      'donation_amount': donationAmount,
      'receipt_no': receiptNo,
      'donation_to': donationTo,
      'picked_from': pickedFrom,
      'picked_date': pickedDate,
      'picked_time': pickedTime,
      'guest_returned': guestReturned,
      'return_date': returnDate,
      'return_time': returnTime,
      'handled_by': handledBy,
      'remarks': remarks,
      'pdf_url': pdfUrl,
      'created_by': createdBy,
    };
  }
}
