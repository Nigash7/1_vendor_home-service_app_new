import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';

/// Where the vendor's earnings get sent.
///
/// Shows what is on file, and lets them replace it. The account number is
/// never displayed in full — the server only ever sends back the last four —
/// so changing it means typing the whole thing again, twice. That is
/// deliberate: a wrong digit here does not fail loudly, it quietly pays a
/// stranger.
class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _accountController = TextEditingController();
  final _confirmController = TextEditingController();
  final _ifscController = TextEditingController();
  final _bankController = TextEditingController();
  final _branchController = TextEditingController();
  final _upiController = TextEditingController();
  String _accountType = 'SAVINGS';

  Map<String, dynamic>? _account;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _nameController, _accountController, _confirmController,
      _ifscController, _bankController, _branchController, _upiController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await ApiService.getBankAccount();
      if (!mounted) return;
      setState(() {
        _account = data['has_account'] == true
            ? Map<String, dynamic>.from(data['account'])
            : null;
        _isLoading = false;
        // Nothing on file yet, so go straight to the form rather than showing
        // an empty screen they have to tap through.
        _isEditing = _account == null;
      });
      if (_account != null) _prefillFromAccount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Everything except the account number, which we do not have in full.
  void _prefillFromAccount() {
    _nameController.text = '${_account?['account_holder_name'] ?? ''}';
    _ifscController.text = '${_account?['ifsc_code'] ?? ''}';
    _bankController.text = '${_account?['bank_name'] ?? ''}';
    _branchController.text = '${_account?['branch_name'] ?? ''}';
    _upiController.text = '${_account?['upi_id'] ?? ''}';
    _accountType = '${_account?['account_type'] ?? 'SAVINGS'}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.saveBankAccount(
        accountHolderName: _nameController.text.trim(),
        accountNumber: _accountController.text.trim(),
        confirmAccountNumber: _confirmController.text.trim(),
        ifscCode: _ifscController.text.trim().toUpperCase(),
        bankName: _bankController.text.trim(),
        branchName: _branchController.text.trim(),
        accountType: _accountType,
        upiId: _upiController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _account = Map<String, dynamic>.from(result['account']);
        _isSaving = false;
        _isEditing = false;
      });
      // Clear the typed number from memory — it has served its purpose and
      // there is no reason to leave it sitting in a controller.
      _accountController.clear();
      _confirmController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result['detail']}'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('Payout Account'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_account != null && !_isEditing) ..._buildSummary(),
                if (_isEditing) ..._buildForm(),
              ],
            ),
    );
  }

  // ------------------------------------------------------------- summary

  List<Widget> _buildSummary() {
    final isVerified = _account?['is_verified'] == true;

    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance, color: Colors.deepOrange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_account?['bank_name'] ?? 'Bank account'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _verifiedChip(isVerified),
              ],
            ),
            const SizedBox(height: 16),
            _summaryRow('Account holder', '${_account?['account_holder_name'] ?? ''}'),
            _summaryRow('Account number', '${_account?['account_number'] ?? ''}'),
            _summaryRow('IFSC', '${_account?['ifsc_code'] ?? ''}'),
            _summaryRow('Type', '${_account?['account_type_display'] ?? ''}'),
            if ('${_account?['upi_id'] ?? ''}'.isNotEmpty)
              _summaryRow('UPI', '${_account?['upi_id']}'),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (!isVerified)
        _notice(
          icon: Icons.schedule,
          background: const Color(0xFFFFF8E1),
          border: const Color(0xFFFFE082),
          iconColor: const Color(0xFFF57C00),
          text: 'Our team is checking these details. Your earnings are safe '
              'in the meantime — verification only has to happen once.',
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () {
          _prefillFromAccount();
          _accountController.clear();
          _confirmController.clear();
          setState(() => _isEditing = true);
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Change payout account'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.deepOrange,
          side: const BorderSide(color: Colors.deepOrange),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Changing this means we check the new account before your next '
        'payout. If you did not make a change you see here, contact support.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    ];
  }

  Widget _verifiedChip(bool isVerified) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isVerified ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isVerified ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Text(
        isVerified ? 'Verified' : 'Pending check',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isVerified ? Colors.green.shade800 : Colors.orange.shade900,
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- form

  List<Widget> _buildForm() {
    final isFirstTime = _account == null;

    return [
      _notice(
        icon: Icons.lock_outline,
        background: const Color(0xFFE8F0FE),
        border: const Color(0xFFC6DAFC),
        iconColor: const Color(0xFF1967D2),
        text: isFirstTime
            ? 'Add the account where you want your earnings sent. We check '
                'the details once before your first payout.'
            : 'Enter the full account number again. We only store the last '
                'four digits in a form we can show you, so there is nothing '
                'to pre-fill.',
      ),
      const SizedBox(height: 16),
      Form(
        key: _formKey,
        child: _card(
          child: Column(
            children: [
              _field(
                controller: _nameController,
                label: 'Account holder name',
                hint: 'Exactly as it appears at the bank',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v ?? '').trim().length < 3
                    ? 'Enter the full name on the account'
                    : null,
              ),
              _field(
                controller: _accountController,
                label: 'Account number',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(18),
                ],
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.length < 9) {
                    return 'An account number is at least 9 digits';
                  }
                  return null;
                },
              ),
              _field(
                controller: _confirmController,
                label: 'Confirm account number',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                // Pasting defeats the point of asking twice.
                enableInteractiveSelection: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(18),
                ],
                validator: (v) => (v ?? '').trim() != _accountController.text.trim()
                    ? 'The account numbers do not match'
                    : null,
              ),
              _field(
                controller: _ifscController,
                label: 'IFSC code',
                hint: 'e.g. SBIN0001234',
                icon: Icons.account_balance_outlined,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                  LengthLimitingTextInputFormatter(11),
                  _UpperCaseFormatter(),
                ],
                validator: (v) {
                  final value = (v ?? '').trim().toUpperCase();
                  if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(value)) {
                    return 'That IFSC does not look right';
                  }
                  return null;
                },
              ),
              _field(
                controller: _bankController,
                label: 'Bank name (optional)',
                icon: Icons.business_outlined,
                textCapitalization: TextCapitalization.words,
              ),
              _field(
                controller: _branchController,
                label: 'Branch (optional)',
                icon: Icons.place_outlined,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _accountType,
                decoration: const InputDecoration(
                  labelText: 'Account type',
                  prefixIcon: Icon(Icons.savings_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'SAVINGS', child: Text('Savings')),
                  DropdownMenuItem(value: 'CURRENT', child: Text('Current')),
                ],
                onChanged: (v) => setState(() => _accountType = v ?? 'SAVINGS'),
              ),
              const SizedBox(height: 16),
              _field(
                controller: _upiController,
                label: 'UPI id (optional)',
                hint: 'yourname@bank — used for smaller payouts',
                icon: Icons.qr_code,
              ),
            ],
          ),
        ),
      ),
      if (_errorMessage != null) ...[
        const SizedBox(height: 12),
        _notice(
          icon: Icons.error_outline,
          background: const Color(0xFFFDECEA),
          border: const Color(0xFFF5C6CB),
          iconColor: Colors.red.shade700,
          text: _errorMessage!,
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(isFirstTime ? 'Save payout account' : 'Update account'),
      ),
      if (!isFirstTime) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isSaving
              ? null
              : () => setState(() {
                    _isEditing = false;
                    _errorMessage = null;
                  }),
          child: const Text('Cancel'),
        ),
      ],
    ];
  }

  // ------------------------------------------------------------- helpers

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool enableInteractiveSelection = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        textCapitalization: textCapitalization,
        enableInteractiveSelection: enableInteractiveSelection,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDEDF2)),
      ),
      child: child,
    );
  }

  Widget _notice({
    required IconData icon,
    required Color background,
    required Color border,
    required Color iconColor,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the IFSC field upper-case as it is typed, so what the vendor sees
/// matches what gets sent.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
