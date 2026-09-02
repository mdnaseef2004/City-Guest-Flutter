import 'package:flutter/material.dart';
import '../models/guest_visit.dart';
import '../services/guest_service.dart';

class GuestProvider extends ChangeNotifier {
  List<GuestVisit> _guests = [];
  int _totalCount = 0;
  int _currentPage = 1;
  bool _isLoading = false;

  // Filters
  String _searchQuery = '';
  String? _selectedPlace;
  String? _selectedDistrict;
  String? _selectedState;
  String? _selectedCountry;
  String? _selectedPurpose;
  List<String> _selectedHandledBy = [];
  List<String> _selectedCreatedBy = [];
  String? _selectedDonationFilter;
  String? _startDate;
  String? _endDate;

  List<GuestVisit> get guests => _guests;
  int get totalCount => _totalCount;
  int get currentPage => _currentPage;
  bool get isLoading => _isLoading;

  String get searchQuery => _searchQuery;
  String? get selectedPlace => _selectedPlace;
  String? get selectedDistrict => _selectedDistrict;
  String? get selectedState => _selectedState;
  String? get selectedCountry => _selectedCountry;
  String? get selectedPurpose => _selectedPurpose;
  List<String> get selectedHandledBy => _selectedHandledBy;
  List<String> get selectedCreatedBy => _selectedCreatedBy;
  String? get selectedDonationFilter => _selectedDonationFilter;
  String? get startDate => _startDate;
  String? get endDate => _endDate;

  void setSearchQuery(String q, bool isSuperAdmin) {
    _searchQuery = q;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterPlace(String? p, bool isSuperAdmin) {
    _selectedPlace = p;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterDistrict(String? d, bool isSuperAdmin) {
    _selectedDistrict = d;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterState(String? s, bool isSuperAdmin) {
    _selectedState = s;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterCountry(String? c, bool isSuperAdmin) {
    _selectedCountry = c;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterPurpose(String? pur, bool isSuperAdmin) {
    _selectedPurpose = pur;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterHandledBy(List<String> h, bool isSuperAdmin) {
    _selectedHandledBy = h;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterCreatedBy(List<String> cb, bool isSuperAdmin) {
    _selectedCreatedBy = cb;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setFilterDonation(String? don, bool isSuperAdmin) {
    _selectedDonationFilter = don;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void setDateRange(String? start, String? end, bool isSuperAdmin) {
    _startDate = start;
    _endDate = end;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  void clearFilters(bool isSuperAdmin) {
    _searchQuery = '';
    _selectedPlace = null;
    _selectedDistrict = null;
    _selectedState = null;
    _selectedCountry = null;
    _selectedPurpose = null;
    _selectedHandledBy = [];
    _selectedCreatedBy = [];
    _selectedDonationFilter = null;
    _startDate = null;
    _endDate = null;
    _currentPage = 1;
    fetchGuests(isSuperAdmin);
  }

  Future<void> fetchGuests(bool isSuperAdmin, {int page = 1}) async {
    _isLoading = true;
    _currentPage = page;
    notifyListeners();

    try {
      final res = await GuestService.getGuests(
        search: _searchQuery,
        place: _selectedPlace,
        district: _selectedDistrict,
        state: _selectedState,
        country: _selectedCountry,
        purpose: _selectedPurpose,
        handledBy: _selectedHandledBy,
        createdBy: _selectedCreatedBy,
        donationFilter: _selectedDonationFilter,
        startDate: _startDate,
        endDate: _endDate,
        page: _currentPage,
        isSuperAdmin: isSuperAdmin,
      );

      _guests = res['data'] as List<GuestVisit>;
      _totalCount = res['total'] as int;
    } catch (e) {
      _guests = [];
      _totalCount = 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteGuest(String id, bool isSuperAdmin) async {
    await GuestService.deleteGuest(id);
    await fetchGuests(isSuperAdmin, page: _currentPage);
  }
}
