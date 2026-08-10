import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import '../services/api_service.dart';

class JobDetailScreen extends StatefulWidget {
  final Map<String, dynamic> job;

  const JobDetailScreen({super.key, required this.job});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late Map<String, dynamic> _job;
  bool _isProcessing = false;
  String? _statusMessage;
  File? _capturedImage;
  String? _convertedAddress; // NEW: Store converted address
  bool _isLoadingAddress = false; // NEW: Track address loading state

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _convertCustomerLocationToAddress(); // NEW: Convert coordinates on load
  }

  /// NEW METHOD: Reverse geocode coordinates to readable address
  /// Reverse geocode coordinates to readable address
  Future<void> _convertCustomerLocationToAddress() async {
    // location_lat / location_lng may arrive as String from DRF DecimalField
    final lat = double.tryParse('${_job['location_lat']}');
    final lng = double.tryParse('${_job['location_lng']}');

    if (lat == null || lng == null) return;

    setState(() => _isLoadingAddress = true);

    try {
      final geocoding = Geocoding();
      final List<Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = [
          place.street,
          place.subLocality,
          place.locality,
          place.postalCode,
          place.country,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        if (mounted) setState(() => _convertedAddress = address);
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      // Leave _convertedAddress null so the UI falls back to the
      // address_text / district / state / pincode fields.
    } finally {
      if (mounted) setState(() => _isLoadingAddress = false);
    }
  }

  Future<Position> _getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(
        'Location services are off. Please enable GPS and try again.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission denied. This is required to start a job.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Please enable it in phone Settings.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _startJob() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      setState(() => _statusMessage = 'Opening camera...');
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (photo == null) {
        setState(() => _statusMessage = null);
        return;
      }

      setState(() {
        _capturedImage = File(photo.path);
        _statusMessage = 'Getting your location...';
      });

      final position = await _getCurrentLocation();

      setState(() => _statusMessage = 'Uploading...');
      await ApiService.uploadStartPhoto(
        bookingId: _job['id'],
        imageFile: File(photo.path),
        latitude: position.latitude,
        longitude: position.longitude,
      );

      setState(() {
        _job['status'] = 'IN_PROGRESS';
        _statusMessage = 'Job started successfully!';
      });
    } catch (e) {
      setState(
        () => _statusMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _completeJob() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      await ApiService.completeJob(_job['id']);
      setState(() {
        _job['status'] = 'COMPLETED';
        _statusMessage = 'Job marked as completed!';
      });
    } catch (e) {
      setState(
        () => _statusMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Hands the customer's number to the phone's dialler.
  Future<void> _callCustomer() async {
    final uri = Uri(scheme: 'tel', path: _customerPhone);
    try {
      final launched = await launchUrl(uri);
      if (!launched) throw Exception('no dialler');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the dialler. $_customerPhone')),
        );
      }
    }
  }

  /// Opens the customer's pinned location in Google Maps for navigation.
  Future<void> _navigateToCustomer() async {
    final lat = _job['location_lat'];
    final lng = _job['location_lng'];
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This customer has not pinned an exact location.'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open maps app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _job['status'];

    return Scaffold(
      appBar: AppBar(title: Text(_job['category_name'] ?? 'Job Detail')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _infoRow(Icons.person, 'Customer', _job['customer_name'] ?? '-'),

          // 1. What the customer typed when booking
          _infoRow(
            Icons.home_outlined,
            'Address (customer entered)',
            _customerGivenAddress,
          ),

          // 2. What the pinned GPS coordinates actually resolve to
          if (_hasCoordinates)
            _infoRow(
              Icons.my_location,
              'Pinned location (GPS)',
              _isLoadingAddress
                  ? 'Resolving address...'
                  : (_convertedAddress ??
                        'Could not resolve — ${_job['location_lat']}, ${_job['location_lng']}'),
            ),

          if (_customerPhone.isNotEmpty) ...[
            _infoRow(Icons.phone, 'Phone', _customerPhone),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OutlinedButton.icon(
                onPressed: _callCustomer,
                icon: const Icon(Icons.call),
                label: const Text('Call Customer'),
              ),
            ),
          ],
          if (_job['location_lat'] != null && _job['location_lng'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: OutlinedButton.icon(
                onPressed: _navigateToCustomer,
                icon: const Icon(Icons.directions),
                label: const Text('Navigate to Customer'),
              ),
            ),
          _infoRow(
            Icons.calendar_today,
            'Date & Time',
            '${_job['preferred_date']} at ${_job['preferred_time']}',
          ),
          _infoRow(
            Icons.notes,
            'Notes',
            (_job['notes'] as String?)?.isNotEmpty == true
                ? _job['notes']
                : 'None',
          ),
          _infoRow(
            Icons.currency_rupee,
            'Amount',
            '₹${_job['amount']} (${_job['payment_status']})',
          ),
          const SizedBox(height: 20),
          // Service form responses
          if (_hasFormData()) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.assignment, size: 20, color: Colors.deepOrange[400]),
                const SizedBox(width: 8),
                const Text(
                  'Customer Requirements',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._buildFormResponses(),
          ],

          const SizedBox(height: 20),

          if (_capturedImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                _capturedImage!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_statusMessage != null) ...[
            Text(
              _statusMessage!,
              style: TextStyle(
                color:
                    _statusMessage!.contains('success') ||
                        _statusMessage!.contains('completed')
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (status == 'ASSIGNED')
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startJob,
              icon: _isProcessing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(
                _isProcessing ? 'Please wait...' : 'Take Photo & Start Job',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blue,
              ),
            )
          else if (status == 'IN_PROGRESS')
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _completeJob,
              icon: _isProcessing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                _isProcessing ? 'Please wait...' : 'Mark Job Complete',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.green,
              ),
            )
          else if (status == 'COMPLETED')
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '✅ This job is completed.',
                  style: TextStyle(color: Colors.green, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasFormData() {
    final services = _job['services_json'];
    if (services is! List) return false;
    for (final svc in services) {
      final formData = svc['form_data'];
      if (formData is List && formData.isNotEmpty) return true;
    }
    return false;
  }

  List<Widget> _buildFormResponses() {
    final widgets = <Widget>[];
    final services = _job['services_json'];
    if (services is! List) return widgets;

    for (final svc in services) {
      final formData = svc['form_data'];
      if (formData is! List || formData.isEmpty) continue;

      // Service name header
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.deepOrange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.deepOrange.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                svc['name'] ?? 'Service',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...formData.map<Widget>((resp) {
                final title = resp['title'] ?? '';
                final answer = resp['answer'] ?? '';
                if (answer.toString().trim().isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        answer.toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  bool get _hasCoordinates =>
      _job['location_lat'] != null && _job['location_lng'] != null;

  /// Customer's contact number, empty when the booking carries none.
  String get _customerPhone => '${_job['customer_phone'] ?? ''}'.trim();

  /// The address the customer typed in when booking.
  String get _customerGivenAddress {
    final parts = [
      if ((_job['address_text'] as String?)?.isNotEmpty == true)
        _job['address_text'] as String
      else if ((_job['customer_address'] as String?)?.isNotEmpty == true)
        _job['customer_address'] as String,
      if ((_job['address_district'] as String?)?.isNotEmpty == true)
        _job['address_district'] as String,
      if ((_job['address_state'] as String?)?.isNotEmpty == true)
        _job['address_state'] as String,
      if ((_job['address_pincode'] as String?)?.isNotEmpty == true)
        _job['address_pincode'] as String,
    ];
    return parts.isEmpty ? 'Not provided' : parts.join(', ');
  }
}
