import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../utils/tender_format.dart';

/// Submit or revise a bid: the price, how the work will run, how long it
/// takes, and the stages the vendor wants paid at.
///
/// The same screen does both jobs — a vendor has one bid per tender and
/// revises it, so a separate "edit" screen would only duplicate this one.
class SubmitBidScreen extends StatefulWidget {
  final int tenderId;
  final String tenderTitle;
  final dynamic expectedBudget;

  /// The vendor's current bid, when they are revising rather than quoting
  /// for the first time.
  final Map<String, dynamic>? existingBid;

  const SubmitBidScreen({
    super.key,
    required this.tenderId,
    required this.tenderTitle,
    this.expectedBudget,
    this.existingBid,
  });

  @override
  State<SubmitBidScreen> createState() => _SubmitBidScreenState();
}

class _MilestoneDraft {
  final TextEditingController title;
  final TextEditingController amount;

  _MilestoneDraft({String title = '', String amount = ''})
    : title = TextEditingController(text: title),
      amount = TextEditingController(text: amount);

  void dispose() {
    title.dispose();
    amount.dispose();
  }
}

class _SubmitBidScreenState extends State<SubmitBidScreen> {
  final _formKey = GlobalKey<FormState>();

  final _amount = TextEditingController();
  final _workPlan = TextEditingController();
  final _timelineDays = TextEditingController();
  final _notes = TextEditingController();

  final List<_MilestoneDraft> _milestones = [];
  bool _isSaving = false;

  bool get _isRevising => widget.existingBid != null;

  @override
  void initState() {
    super.initState();

    final bid = widget.existingBid;
    if (bid != null) {
      _amount.text = _asWholeNumber(bid['amount']);
      _workPlan.text = '${bid['work_plan'] ?? ''}';
      _timelineDays.text = bid['timeline_days'] == null
          ? ''
          : '${bid['timeline_days']}';
      _notes.text = '${bid['notes'] ?? ''}';

      for (final milestone in (bid['milestones'] as List?) ?? const []) {
        _milestones.add(
          _MilestoneDraft(
            title: '${milestone['title'] ?? ''}',
            amount: _asWholeNumber(milestone['amount']),
          ),
        );
      }
    }

    // Rebuild as the numbers change so the running total below the milestone
    // list stays honest while the vendor types.
    _amount.addListener(_refresh);
  }

  @override
  void dispose() {
    _amount.removeListener(_refresh);
    _amount.dispose();
    _workPlan.dispose();
    _timelineDays.dispose();
    _notes.dispose();
    for (final milestone in _milestones) {
      milestone.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// '1400000.00' -> '1400000', so the field does not show trailing zeros the
  /// vendor then has to delete.
  String _asWholeNumber(dynamic value) {
    final parsed = double.tryParse('${value ?? ''}');
    return parsed == null ? '' : parsed.truncate().toString();
  }

  double get _bidAmount => double.tryParse(_amount.text.trim()) ?? 0;

  double get _milestoneTotal => _milestones.fold(
    0,
    (sum, m) => sum + (double.tryParse(m.amount.text.trim()) ?? 0),
  );

  /// How far the quote sits from what the customer budgeted.
  double get _difference {
    final budget = double.tryParse('${widget.expectedBudget ?? ''}') ?? 0;
    return _bidAmount - budget;
  }

  void _addMilestone() {
    setState(() => _milestones.add(_MilestoneDraft()));
  }

  void _removeMilestone(int index) {
    final removed = _milestones.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // A payment plan that does not add up to the quote is the kind of thing a
    // customer spots and a vendor loses the job over, so ask first.
    final total = _milestoneTotal;
    if (_milestones.isNotEmpty && (total - _bidAmount).abs() >= 1) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Milestones do not add up'),
          content: Text(
            'Your stages total ${tenderMoney(total)}, but you are quoting '
            '${tenderMoney(_bidAmount)}.\n\n'
            'The customer sees both. Send it anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Let me fix it'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final milestones = <Map<String, dynamic>>[];
    for (final draft in _milestones) {
      final title = draft.title.text.trim();
      if (title.isEmpty) continue;
      milestones.add({
        'title': title,
        'amount': draft.amount.text.trim().isEmpty
            ? '0'
            : draft.amount.text.trim(),
      });
    }

    setState(() => _isSaving = true);
    try {
      final timeline = int.tryParse(_timelineDays.text.trim());
      if (_isRevising) {
        await ApiService.reviseBid(
          tenderId: widget.tenderId,
          amount: _amount.text.trim(),
          workPlan: _workPlan.text.trim(),
          timelineDays: timeline,
          notes: _notes.text.trim(),
          milestones: milestones,
        );
      } else {
        await ApiService.submitBid(
          tenderId: widget.tenderId,
          amount: _amount.text.trim(),
          workPlan: _workPlan.text.trim(),
          timelineDays: timeline,
          notes: _notes.text.trim(),
          milestones: milestones,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isRevising
                ? 'Your bid has been updated.'
                : 'Bid sent. The customer will be notified.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tenderBg,
      appBar: AppBar(
        title: Text(_isRevising ? 'Revise your bid' : 'Submit a bid'),
        backgroundColor: tenderAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: tenderAccent,
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
                : Text(_isRevising ? 'Update bid' : 'Send bid'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.tenderTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),

            // ------------------------------------------------------ price
            TenderCardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Your price',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Budget ${tenderMoney(widget.expectedBudget)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      prefixText: '₹ ',
                      hintText: '0',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final value = int.tryParse((v ?? '').trim());
                      if (value == null || value <= 0) {
                        return 'Enter the amount you are quoting.';
                      }
                      return null;
                    },
                  ),
                  if (_bidAmount > 0 && widget.expectedBudget != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _difference == 0
                          ? 'Exactly on their budget.'
                          : _difference > 0
                          ? '${tenderMoney(_difference)} above their budget.'
                          : '${tenderMoney(_difference.abs())} below their budget.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _difference > 0
                            ? Colors.red.shade600
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),
            // ------------------------------------------------- plan + time
            TenderCardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How you will do it',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The customer compares this against every other quote, '
                    'so specifics win work.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _workPlan,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Three phases — foundation, structure, '
                          'finishing. Own labour, materials at cost.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _timelineDays,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Days you need',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _buildMilestones(),

            const SizedBox(height: 12),
            TenderCardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Anything else',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Warranty, what is excluded, site conditions…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestones() {
    final total = _milestoneTotal;
    final mismatch =
        _milestones.isNotEmpty && _bidAmount > 0 && (total - _bidAmount).abs() >= 1;

    return TenderCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment stages',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional. Break the job into stages and the customer releases '
            'payment as each one is done.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),

          for (var i = 0; i < _milestones.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _milestones[i].title,
                      decoration: InputDecoration(
                        labelText: 'Stage ${i + 1}',
                        hintText: 'e.g. Foundation',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _milestones[i].amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => _refresh(),
                      decoration: const InputDecoration(
                        prefixText: '₹',
                        hintText: '0',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeMilestone(i),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: Colors.grey.shade600,
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),

          if (_milestones.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Stages total',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                const Spacer(),
                Text(
                  tenderMoney(total),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: mismatch ? Colors.red.shade600 : Colors.black87,
                  ),
                ),
              ],
            ),
            if (mismatch)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'This does not match your quote of ${tenderMoney(_bidAmount)}.',
                  style: TextStyle(fontSize: 11.5, color: Colors.red.shade600),
                ),
              ),
            const SizedBox(height: 10),
          ],

          OutlinedButton.icon(
            onPressed: _addMilestone,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a stage'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tenderAccent,
              side: const BorderSide(color: tenderAccent),
            ),
          ),
        ],
      ),
    );
  }
}
