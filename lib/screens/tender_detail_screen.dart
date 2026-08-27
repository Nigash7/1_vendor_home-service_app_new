import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../utils/tender_format.dart';
import 'submit_bid_screen.dart';

/// Everything a vendor needs to decide whether to quote: the brief, the
/// drawings, the customer's budget, and how many others are already bidding.
class TenderDetailScreen extends StatefulWidget {
  final int tenderId;

  const TenderDetailScreen({super.key, required this.tenderId});

  @override
  State<TenderDetailScreen> createState() => _TenderDetailScreenState();
}

class _TenderDetailScreenState extends State<TenderDetailScreen> {
  Map<String, dynamic>? _tender;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final tender = await ApiService.getTenderDetail(widget.tenderId);
      if (!mounted) return;
      setState(() {
        _tender = tender;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openBidForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SubmitBidScreen(
          tenderId: widget.tenderId,
          tenderTitle: '${_tender?['title'] ?? ''}',
          expectedBudget: _tender?['expected_budget'],
          existingBid: _tender?['my_bid'] == null
              ? null
              : Map<String, dynamic>.from(_tender!['my_bid']),
        ),
      ),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _withdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw your bid?'),
        content: const Text(
          'The customer will no longer see your quote. You can bid again '
          'while the tender is still open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      await ApiService.withdrawBid(widget.tenderId);
      _changed = true;
      _snack('Bid withdrawn.');
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _call(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('Could not open the dialler.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: tenderBg,
        appBar: AppBar(
          title: Text(_tender?['code']?.toString() ?? 'Tender'),
          backgroundColor: tenderAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        bottomNavigationBar: _buildBidBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _errorState()
            : RefreshIndicator(onRefresh: _load, child: _content()),
      ),
    );
  }

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(
              backgroundColor: tenderAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );

  /// The bid action, sized to whatever the vendor can actually do right now.
  Widget? _buildBidBar() {
    final tender = _tender;
    if (tender == null) return null;

    final myBid = tender['my_bid'];
    final biddingOpen = tender['is_bidding_open'] == true;
    final bidStatus = myBid == null ? null : '${myBid['status']}';

    if (bidStatus == 'ACCEPTED') {
      return SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade50,
          child: Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: Colors.green.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You won this project. Open it from the Projects tab to '
                  'start work.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (bidStatus == 'REJECTED') {
      return SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Text(
            'The customer went with another vendor this time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      );
    }

    if (!biddingOpen) {
      return SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Text(
            'This tender is no longer accepting bids.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      );
    }

    final hasLiveBid = bidStatus == 'SUBMITTED';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            if (hasLiveBid) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _isBusy ? null : _withdraw,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Withdraw'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _openBidForm,
                icon: Icon(hasLiveBid ? Icons.edit_outlined : Icons.gavel_rounded),
                label: Text(hasLiveBid ? 'Revise your bid' : 'Submit a bid'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tenderAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final tender = _tender!;
    final myBid = tender['my_bid'];
    final customerPhone = '${tender['customer_phone'] ?? ''}';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        // ------------------------------------------------ headline + budget
        TenderCardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${tender['title'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TenderPill(style: tenderStatusStyle('${tender['status']}')),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  tender['project_type_display'],
                  tender['category_name'],
                  tender['subcategory_name'],
                ].where((v) => v != null).join(' · '),
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tenderAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer budget',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tenderMoney(tender['expected_budget']),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: tenderAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Bids so far',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tender['bid_count'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ------------------------------------------------------- your bid
        if (myBid != null) ...[
          const SizedBox(height: 12),
          TenderCardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Your bid',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TenderPill(style: bidStatusStyle('${myBid['status']}')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tenderMoney(myBid['amount']),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (myBid['timeline_days'] != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'in ${myBid['timeline_days']} days',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
                if ((myBid['milestones'] as List?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Your payment plan',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final milestone in myBid['milestones'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${milestone['title']}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          Text(
                            tenderMoney(milestone['amount']),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],

        // ---------------------------------------------------------- brief
        const SizedBox(height: 12),
        TenderCardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What they need',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '${tender['description'] ?? ''}',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
              if ('${tender['requirements'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Requirements',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${tender['requirements']}',
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ],
              const SizedBox(height: 14),
              if (tender['area_sqft'] != null)
                _row('Built-up area', '${tender['area_sqft']} sq ft'),
              if (tender['preferred_start_date'] != null)
                _row(
                  'Wants to start',
                  tenderDate(tender['preferred_start_date']),
                ),
              if (tender['duration_days'] != null)
                _row('Expected duration', '${tender['duration_days']} days'),
              if (tender['bid_deadline'] != null)
                _row('Bidding closes', tenderDate(tender['bid_deadline'])),
            ],
          ),
        ),

        // ----------------------------------------------------- attachments
        if ((tender['attachments'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          TenderCardShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Drawings & photos',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: (tender['attachments'] as List).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final attachment = tender['attachments'][index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: attachment['is_image'] == true
                            ? Image.network(
                                '${attachment['file']}',
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _fileTile(attachment),
                              )
                            : _fileTile(attachment),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],

        // -------------------------------------------------------- location
        const SizedBox(height: 12),
        TenderCardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Site',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                '${tender['location_label'] ?? '—'}',
                style: const TextStyle(fontSize: 13.5),
              ),
              if ('${tender['address_text'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${tender['address_text']}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
              // The number only arrives once this vendor has won — until then
              // the server withholds it.
              if (customerPhone.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _call(customerPhone),
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: Text('Call ${tender['customer_name'] ?? 'customer'}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tenderAccent,
                    side: const BorderSide(color: tenderAccent),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Contact details are shared once the customer '
                        'accepts your bid.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _fileTile(dynamic attachment) => Container(
    width: 96,
    height: 96,
    color: tenderBg,
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.insert_drive_file_outlined, color: Colors.grey.shade600),
        const SizedBox(height: 6),
        Text(
          '${attachment['filename'] ?? 'File'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
