import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../core/utils.dart';
import '../../models/visited_place.dart';
import '../../providers/auth_provider.dart';
import '../../services/guest_service.dart';
import '../../services/notification_service.dart';
import '../../services/thank_you_message_service.dart';

class AddGuestView extends StatefulWidget {
  const AddGuestView({super.key});

  @override
  State<AddGuestView> createState() => _AddGuestViewState();
}

class _AddGuestViewState extends State<AddGuestView> {
  final _formKey = GlobalKey<FormState>();

  final _guestNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _occupationController = TextEditingController();
  final _placeController = TextEditingController();
  final _districtController = TextEditingController();
  final _purposeController = TextEditingController();
  final _donationController = TextEditingController();
  final _receiptNoController = TextEditingController();
  final _pickedFromController = TextEditingController();
  final _handledByController = TextEditingController();
  final _remarksController = TextEditingController();

  String? _selectedState;
  String? _selectedCountry;
  bool _isInternational = false;
  File? _guestPhoto;
  bool _isSaving = false;

  final List<VisitedPlaceInput> _visitedPlaces = [];

  @override
  void initState() {
    super.initState();
    final profile = Provider.of<AuthProvider>(context, listen: false).profile;
    if (profile != null) {
      _handledByController.text = profile.name;
    }
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _phoneController.dispose();
    _occupationController.dispose();
    _placeController.dispose();
    _districtController.dispose();
    _purposeController.dispose();
    _donationController.dispose();
    _receiptNoController.dispose();
    _pickedFromController.dispose();
    _handledByController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      setState(() {
        _guestPhoto = File(pickedFile.path);
      });
    }
  }

  void _addVisitedPlaceField() {
    setState(() {
      _visitedPlaces.add(VisitedPlaceInput());
    });
  }

  void _removeVisitedPlaceField(int index) {
    setState(() {
      _visitedPlaces.removeAt(index);
    });
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      AppUtils.showSnackBar(context, 'Please fill in all required fields', isError: true);
      return;
    }

    final donation = double.tryParse(_donationController.text.trim()) ?? 0.0;
    if (donation > 0 && _receiptNoController.text.trim().isEmpty) {
      AppUtils.showSnackBar(context, 'Receipt No is required when Donation Amount is entered', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Check duplicate guest
      final isDuplicate = await GuestService.checkDuplicateGuest(_guestNameController.text.trim());
      if (isDuplicate && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Duplicate Entry Detected'),
            content: Text('A guest named "${_guestNameController.text.trim()}" was already recorded today by you. Add anyway?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add Anyway')),
            ],
          ),
        );
        if (proceed != true) {
          setState(() => _isSaving = false);
          return;
        }
      }

      // Upload photo if selected
      String? photoUrl;
      if (_guestPhoto != null) {
        photoUrl = await GuestService.uploadGuestPhoto(_guestPhoto!);
      }

      final places = _visitedPlaces
          .where((vp) => vp.placeController.text.trim().isNotEmpty)
          .map((vp) => VisitedPlace(
                visitedPlace: vp.placeController.text.trim(),
                timeIn: vp.timeInController.text.trim(),
                timeOut: vp.timeOutController.text.trim(),
              ))
          .toList();

      final savedName = _guestNameController.text.trim();
      final savedPhone = _phoneController.text.trim();

      await GuestService.addGuest(
        guestName: savedName,
        phoneNumber: savedPhone,
        occupation: _occupationController.text.trim(),
        photoUrl: photoUrl,
        place: _placeController.text.trim(),
        district: _districtController.text.trim(),
        state: _selectedState,
        country: _selectedCountry,
        isInternational: _isInternational,
        purpose: _purposeController.text.trim(),
        donationAmount: donation,
        receiptNo: _receiptNoController.text.trim(),
        pickedFrom: _pickedFromController.text.trim(),
        handledBy: _handledByController.text.trim(),
        remarks: _remarksController.text.trim(),
        visitedPlaces: places,
      );

      if (mounted) {
        final currentAdminName = Provider.of<AuthProvider>(context, listen: false).profile?.name ?? 'Admin';
        final placeStr = _placeController.text.trim();

        // Show loud popup notification banner with sound
        NotificationService.showNotificationPopup(
          context,
          title: 'Guest Recorded Successfully!',
          message: '$savedName has been saved to database.',
          icon: Icons.person_add_alt_1_rounded,
        );

        // Store notification for Super Admins in Notification Centre
        NotificationService.notifyGuestAdded(
          adminName: currentAdminName,
          guestName: savedName,
          place: placeStr,
        );

        _resetForm();
        ThankYouMessageService.showThankYouDialog(
          context,
          guestName: savedName,
          phoneNumber: savedPhone,
        );
      }
    } catch (e) {
      if (mounted) AppUtils.showSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _guestNameController.clear();
    _phoneController.clear();
    _occupationController.clear();
    _placeController.clear();
    _districtController.clear();
    _purposeController.clear();
    _donationController.clear();
    _receiptNoController.clear();
    _pickedFromController.clear();
    _remarksController.clear();
    setState(() {
      _selectedState = null;
      _selectedCountry = null;
      _isInternational = false;
      _guestPhoto = null;
      _visitedPlaces.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final districts = _selectedState != null
        ? AppConstants.districtsByState[_selectedState] ?? []
        : <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Add New Guest Visit')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Upload Section
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickPhoto,
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        backgroundImage: _guestPhoto != null ? FileImage(_guestPhoto!) : null,
                        child: _guestPhoto == null
                            ? const Icon(Icons.camera_alt_outlined, size: 36, color: AppColors.primary)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library),
                      label: Text(_guestPhoto == null ? 'Add Guest Photo' : 'Change Photo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Form Inputs Grid
              TextFormField(
                controller: _guestNameController,
                decoration: const InputDecoration(
                  labelText: 'Guest Name *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: _isInternational ? 'Phone Number' : 'Phone Number *',
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                validator: (v) => !_isInternational && (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _occupationController,
                decoration: const InputDecoration(
                  labelText: 'Occupation / Profession',
                  prefixIcon: Icon(Icons.work_outline),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _placeController,
                decoration: const InputDecoration(
                  labelText: 'Full Address / Place *',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // International Toggle
              CheckboxListTile(
                title: const Text('International Guest'),
                subtitle: const Text('Select country instead of Indian state'),
                value: _isInternational,
                onChanged: (val) {
                  setState(() {
                    _isInternational = val ?? false;
                    _selectedState = null;
                    _selectedCountry = null;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),

              // State / Country Dropdown
              if (!_isInternational) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedState,
                  decoration: const InputDecoration(
                    labelText: 'State *',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                  items: AppConstants.indianStates.map((st) {
                    return DropdownMenuItem(value: st, child: Text(st, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (st) {
                    setState(() {
                      _selectedState = st;
                      _districtController.clear();
                    });
                  },
                  validator: (v) => !_isInternational && v == null ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                if (districts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('district_dropdown_$_selectedState'),
                    value: districts.contains(_districtController.text) ? _districtController.text : null,
                    decoration: const InputDecoration(
                      labelText: 'District *',
                      prefixIcon: Icon(Icons.my_location),
                    ),
                    items: districts.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (d) {
                      setState(() {
                        _districtController.text = d ?? '';
                      });
                    },
                    validator: (v) => !_isInternational && (v == null || v.trim().isEmpty) ? 'Required' : null,
                  )
                else
                  TextFormField(
                    controller: _districtController,
                    decoration: const InputDecoration(
                      labelText: 'District *',
                      prefixIcon: Icon(Icons.my_location),
                    ),
                    validator: (v) => !_isInternational && (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
              ] else ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedCountry,
                  decoration: const InputDecoration(
                    labelText: 'Country *',
                    prefixIcon: Icon(Icons.public),
                  ),
                  items: AppConstants.countries.map((c) {
                    return DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (c) => setState(() => _selectedCountry = c),
                  validator: (v) => _isInternational && v == null ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 16),

              TextFormField(
                controller: _purposeController,
                decoration: const InputDecoration(
                  labelText: 'Purpose of Visit *',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _donationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Donation Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _receiptNoController,
                decoration: const InputDecoration(
                  labelText: 'Receipt No (Required if donation entered)',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 24),

              // Multiple Visited Places Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Visited Places List',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    onPressed: _addVisitedPlaceField,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Place'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _visitedPlaces.length,
                itemBuilder: (context, index) {
                  final item = _visitedPlaces[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: item.placeController,
                              decoration: const InputDecoration(labelText: 'Visited Place Name'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _removeVisitedPlaceField(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetForm,
                      child: const Text('Clear Form'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submitForm,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Save Record'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class VisitedPlaceInput {
  final TextEditingController placeController = TextEditingController();
  final TextEditingController timeInController = TextEditingController();
  final TextEditingController timeOutController = TextEditingController();
}
