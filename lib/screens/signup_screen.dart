import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import 'vendor_status_screen.dart';

/// Self-registration for a new vendor. Collects the same details an admin
/// would enter on the dashboard, except the ones only an admin may decide
/// (verification status and availability).
///
/// A successful submission does NOT log the vendor in — the account waits on
/// PENDING until an admin verifies it.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _serviceAreaController = TextEditingController();
  final _addressController = TextEditingController();

  List<dynamic> _categories = [];
  final Set<int> _selectedCategoryIds = {};
  bool _loadingCategories = true;
  String? _categoriesError;

  File? _idProof;
  File? _addressProof;
  File? _tradeCertificate;

  double? _latitude;
  double? _longitude;
  bool _capturingLocation = false;

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _serviceAreaController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.getServiceCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesError = e.toString().replaceFirst('Exception: ', '');
        _loadingCategories = false;
      });
    }
  }

  Future<void> _pickDocument(void Function(File) onPicked) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
    );
    if (picked != null) setState(() => onPicked(File(picked.path)));
  }

  Future<void> _captureLocation() async {
    setState(() => _capturingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not get location.')));
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryIds.isEmpty) {
      setState(() => _errorMessage = 'Select at least one service category.');
      return;
    }
    if (_idProof == null) {
      setState(() => _errorMessage = 'An ID proof document is required.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.signup(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        passwordConfirm: _confirmController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        categoryIds: _selectedCategoryIds.toList(),
        serviceArea: _serviceAreaController.text.trim(),
        address: _addressController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        idProof: _idProof!,
        addressProof: _addressProof,
        tradeCertificate: _tradeCertificate,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VendorStatusScreen.justSubmitted(
            username: _usernameController.text.trim(),
            message:
                'Your application has been submitted. You will be able to log '
                'in once an admin has verified your profile.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------- Small building blocks ----------

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.deepOrange),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepOrange, width: 2),
      ),
      filled: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.deepOrange.shade800,
        letterSpacing: 0.3,
      ),
    ),
  );

  String? _required(String? value, String label) =>
      (value == null || value.trim().isEmpty) ? 'Please enter your $label' : null;

  Widget _documentTile({
    required String label,
    required String subtitle,
    required File? file,
    required void Function(File) onPicked,
    required VoidCallback onCleared,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: file != null ? Colors.green.shade300 : Colors.grey.shade300,
        ),
      ),
      child: ListTile(
        leading: Icon(
          file != null ? Icons.check_circle : Icons.upload_file_outlined,
          color: file != null ? Colors.green.shade600 : Colors.grey.shade600,
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          file != null ? file.path.split(Platform.pathSeparator).last : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: file != null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: onCleared,
              )
            : const Icon(Icons.chevron_right),
        onTap: () => _pickDocument(onPicked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create vendor account'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1A2E), const Color(0xFF16213E)]
                : [const Color(0xFFFFF3E0), const Color(0xFFFFE0B2)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your profile is reviewed by an admin before you can '
                        'log in and receive jobs.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),

                      _sectionTitle('LOGIN CREDENTIALS'),
                      TextFormField(
                        controller: _usernameController,
                        decoration: _decoration(
                          'Username',
                          Icons.person_outline,
                          hint: 'Used to log in',
                        ),
                        validator: (v) => _required(v, 'username'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration:
                            _decoration('Password', Icons.lock_outline).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (v.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscurePassword,
                        decoration: _decoration(
                          'Confirm password',
                          Icons.lock_reset_outlined,
                        ),
                        validator: (v) => v != _passwordController.text
                            ? 'Passwords do not match'
                            : null,
                      ),

                      _sectionTitle('YOUR DETAILS'),
                      TextFormField(
                        controller: _firstNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration('First name', Icons.badge_outlined),
                        validator: (v) => _required(v, 'first name'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lastNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _decoration(
                          'Last name (optional)',
                          Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: _decoration('Phone number', Icons.phone_outlined),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Please enter your phone number';
                          if (value.length < 10) {
                            return 'Enter a valid phone number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _decoration(
                          'Email (optional)',
                          Icons.email_outlined,
                        ),
                      ),

                      _sectionTitle('WORK DETAILS'),
                      Text(
                        'Which services do you provide?',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingCategories)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_categoriesError != null)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _categoriesError!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _loadingCategories = true;
                                  _categoriesError = null;
                                });
                                _loadCategories();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _categories.map<Widget>((c) {
                            final id = c['id'] as int;
                            final selected = _selectedCategoryIds.contains(id);
                            return FilterChip(
                              label: Text('${c['name']}'),
                              selected: selected,
                              selectedColor: Colors.deepOrange.shade100,
                              checkmarkColor: Colors.deepOrange.shade800,
                              onSelected: (on) => setState(() {
                                on
                                    ? _selectedCategoryIds.add(id)
                                    : _selectedCategoryIds.remove(id);
                              }),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _serviceAreaController,
                        decoration: _decoration(
                          'Service area',
                          Icons.map_outlined,
                          hint: 'Area / zone / pincode you cover',
                        ),
                        validator: (v) => _required(v, 'service area'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 3,
                        decoration: _decoration(
                          'Address (optional)',
                          Icons.home_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _capturingLocation ? null : _captureLocation,
                        icon: _capturingLocation
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _latitude != null
                                    ? Icons.check_circle_outline
                                    : Icons.my_location,
                              ),
                        label: Text(
                          _latitude != null
                              ? 'Location saved '
                                    '(${_latitude!.toStringAsFixed(4)}, '
                                    '${_longitude!.toStringAsFixed(4)})'
                              : 'Use my current location (optional)',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: Colors.deepOrange,
                          side: const BorderSide(color: Colors.deepOrange),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),

                      _sectionTitle('VERIFICATION DOCUMENTS'),
                      _documentTile(
                        label: 'ID proof *',
                        subtitle: 'Aadhaar, PAN, driving licence…',
                        file: _idProof,
                        onPicked: (f) => _idProof = f,
                        onCleared: () => setState(() => _idProof = null),
                      ),
                      _documentTile(
                        label: 'Address proof',
                        subtitle: 'Optional',
                        file: _addressProof,
                        onPicked: (f) => _addressProof = f,
                        onCleared: () => setState(() => _addressProof = null),
                      ),
                      _documentTile(
                        label: 'Trade certificate',
                        subtitle: 'Optional',
                        file: _tradeCertificate,
                        onPicked: (f) => _tradeCertificate = f,
                        onCleared: () =>
                            setState(() => _tradeCertificate = null),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Submit application',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
