import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import '../services/api_service.dart';
import '../widgets/slide_action.dart';

/// The vendor app's accent, matching the login, jobs list and notification
/// screens. Literal rather than `colorScheme.primary`, because the Material 3
/// scheme generated from the deepOrange seed comes out noticeably muted.
const Color _accent = Colors.deepOrange;

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
  String? _convertedAddress;
  bool _isLoadingAddress = false;

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _convertCustomerLocationToAddress();
  }

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

  // ----------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final status = '${_job['status']}';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: Text(
          _job['category_name'] ?? 'Job Detail',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildSummaryCard(status),
          const SizedBox(height: 12),
          _buildCustomerCard(),
          const SizedBox(height: 12),
          _buildLocationCard(),
          const SizedBox(height: 12),
          _buildScheduleCard(),

          if (_hasFormData()) ...[
            const SizedBox(height: 12),
            _buildRequirementsCard(),
          ],

          if (_capturedImage != null) ...[
            const SizedBox(height: 12),
            _buildPhotoCard(),
          ],

          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            _buildStatusMessage(),
          ],

          const SizedBox(height: 24),
          _buildAction(status),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ summary
  Widget _buildSummaryCard(String status) {
    final meta = _statusMeta(status);
    final paid = '${_job['payment_status']}'.toUpperCase() == 'PAID';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(meta.icon, size: 15, color: meta.color),
                    const SizedBox(width: 6),
                    Text(
                      meta.label,
                      style: TextStyle(
                        color: meta.color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '#${_job['id']}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Job value',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${_job['amount']}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (paid ? Colors.green : Colors.orange).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_job['payment_status']}',
                  style: TextStyle(
                    color: paid ? Colors.green.shade800 : Colors.orange.shade900,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ customer
  Widget _buildCustomerCard() {
    final name = '${_job['customer_name'] ?? '-'}';
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _accent.withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_customerPhone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _customerPhone,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (_customerPhone.isNotEmpty || _hasCoordinates) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (_customerPhone.isNotEmpty)
                  Expanded(
                    child: _actionChip(
                      icon: Icons.call_rounded,
                      label: 'Call',
                      color: Colors.green.shade700,
                      onTap: _callCustomer,
                    ),
                  ),
                if (_customerPhone.isNotEmpty && _hasCoordinates)
                  const SizedBox(width: 10),
                if (_hasCoordinates)
                  Expanded(
                    child: _actionChip(
                      icon: Icons.directions_rounded,
                      label: 'Navigate',
                      color: Colors.blue.shade700,
                      onTap: _navigateToCustomer,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ location
  Widget _buildLocationCard() {
    return _card(
      title: 'Location',
      icon: Icons.location_on_outlined,
      child: Column(
        children: [
          _detailRow(
            Icons.home_outlined,
            'Address given by customer',
            _customerGivenAddress,
          ),
          if (_hasCoordinates) ...[
            const SizedBox(height: 14),
            _detailRow(
              Icons.my_location_rounded,
              'Pinned location (GPS)',
              _isLoadingAddress
                  ? 'Resolving address...'
                  : (_convertedAddress ??
                        'Could not resolve — ${_job['location_lat']}, ${_job['location_lng']}'),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ schedule
  Widget _buildScheduleCard() {
    final notes = '${_job['notes'] ?? ''}'.trim();

    return _card(
      title: 'Schedule',
      icon: Icons.event_outlined,
      child: Column(
        children: [
          _detailRow(
            Icons.calendar_today_outlined,
            'Date & time',
            '${_job['preferred_date']} at ${_job['preferred_time']}',
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            _detailRow(Icons.sticky_note_2_outlined, 'Customer notes', notes),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------- requirements
  Widget _buildRequirementsCard() {
    return _card(
      title: 'Customer requirements',
      icon: Icons.assignment_outlined,
      child: Column(children: _buildFormResponses()),
    );
  }

  // ------------------------------------------------------------- photo
  Widget _buildPhotoCard() {
    return _card(
      title: 'Arrival photo',
      icon: Icons.photo_camera_outlined,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          _capturedImage!,
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  // ------------------------------------------------------ status message
  Widget _buildStatusMessage() {
    final message = _statusMessage!;
    final isGood =
        message.contains('success') ||
        message.contains('completed') ||
        message.endsWith('...');
    final color = isGood ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isGood ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- action
  Widget _buildAction(String status) {
    if (status == 'ASSIGNED') {
      return Column(
        children: [
          SlideAction(
            label: 'Slide to start job',
            processingLabel: 'Starting...',
            icon: Icons.camera_alt_rounded,
            color: Colors.blue,
            enabled: !_isProcessing,
            onConfirm: _startJob,
          ),
          const SizedBox(height: 10),
          Text(
            'Opens the camera and records your location',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    if (status == 'IN_PROGRESS') {
      return Column(
        children: [
          SlideAction(
            label: 'Slide to finish job',
            processingLabel: 'Finishing...',
            icon: Icons.check_rounded,
            color: Colors.green,
            enabled: !_isProcessing,
            onConfirm: _completeJob,
          ),
          const SizedBox(height: 10),
          Text(
            'This marks the job complete for the customer',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      );
    }

    if (status == 'COMPLETED') {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 22,
              ),
              SizedBox(width: 10),
              Text(
                'This job is completed',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ------------------------------------------------------------- pieces
  /// White rounded panel with an optional titled header.
  Widget _card({required Widget child, String? title, IconData? icon}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: _accent),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(fontSize: 14.5, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Label, colour and icon for each booking status.
  ({String label, Color color, IconData icon}) _statusMeta(String status) {
    switch (status) {
      case 'ASSIGNED':
        return (
          label: 'ASSIGNED',
          color: Colors.blue.shade700,
          icon: Icons.assignment_ind_outlined,
        );
      case 'IN_PROGRESS':
        return (
          label: 'IN PROGRESS',
          color: _accent,
          icon: Icons.timelapse_rounded,
        );
      case 'COMPLETED':
        return (
          label: 'COMPLETED',
          color: Colors.green.shade700,
          icon: Icons.check_circle_outline,
        );
      case 'CANCELLED':
        return (
          label: 'CANCELLED',
          color: Colors.red.shade700,
          icon: Icons.cancel_outlined,
        );
      default:
        return (
          label: status,
          color: Colors.grey.shade700,
          icon: Icons.info_outline,
        );
    }
  }

  /// What the customer answered, as the API groups it: one entry per service
  /// or form, each with its own {title, answer} rows. The server already drops
  /// blank answers and flattens multi-select lists into readable text.
  List<Map<String, dynamic>> get _formGroups {
    final groups = _job['form_groups'];
    if (groups is! List) return const [];

    return groups
        .whereType<Map>()
        .map(
          (group) => {
            'title': '${group['title'] ?? ''}',
            'responses': (group['responses'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (resp) => {
                    'title': '${resp['title'] ?? ''}',
                    'answer': '${resp['answer'] ?? ''}',
                  },
                )
                .toList(),
          },
        )
        .where((group) => (group['responses'] as List).isNotEmpty)
        .toList();
  }

  bool _hasFormData() => _formGroups.isNotEmpty;

  List<Widget> _buildFormResponses() {
    return _formGroups.map((group) {
      final responses = group['responses'] as List<Map<String, String>>;
      final title = group['title'] as String;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty) ...[
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 10),
            ],
            ...responses.map(
              (resp) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resp['title']!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      resp['answer']!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
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
