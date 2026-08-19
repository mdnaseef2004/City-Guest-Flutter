import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils.dart';
import '../../providers/auth_provider.dart';
import '../../services/event_service.dart';

class AddEventView extends StatefulWidget {
  const AddEventView({super.key});

  @override
  State<AddEventView> createState() => _AddEventViewState();
}

class _AddEventViewState extends State<AddEventView> {
  final _formKey = GlobalKey<FormState>();

  final _eventNameController = TextEditingController();
  final _eventPlaceController = TextEditingController();
  final _membersCountController = TextEditingController();
  final _organizedByController = TextEditingController();
  final _handledByController = TextEditingController();
  final _remarksController = TextEditingController();

  DateTime _eventDate = DateTime.now();
  bool _isSaving = false;

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
    _eventNameController.dispose();
    _eventPlaceController.dispose();
    _membersCountController.dispose();
    _organizedByController.dispose();
    _handledByController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await EventService.addEvent(
        eventName: _eventNameController.text.trim(),
        eventPlace: _eventPlaceController.text.trim(),
        membersCount: int.tryParse(_membersCountController.text.trim()) ?? 0,
        organizedBy: _organizedByController.text.trim(),
        eventDate: _eventDate,
        handledBy: _handledByController.text.trim(),
        remarks: _remarksController.text.trim(),
      );

      if (mounted) {
        AppUtils.showSnackBar(context, 'Event added successfully!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) AppUtils.showSnackBar(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Event')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _eventNameController,
                decoration: const InputDecoration(labelText: 'Event Name *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _eventPlaceController,
                decoration: const InputDecoration(labelText: 'Event Place *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _membersCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Members Count *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _organizedByController,
                decoration: const InputDecoration(labelText: 'Organized By *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Event Date *'),
                subtitle: Text(AppUtils.formatDate(_eventDate)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _eventDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) setState(() => _eventDate = date);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _handledByController,
                decoration: const InputDecoration(labelText: 'Handled By *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _submitForm,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Event'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
