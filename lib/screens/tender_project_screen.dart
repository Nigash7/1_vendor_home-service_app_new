import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../utils/tender_format.dart';

/// Running a project the vendor won: start it, post progress, mark stages
/// done as they are reached, and finish.
///
/// The single action that matters at this moment sits at the top, because a
/// vendor opens this on site with one hand.
class TenderProjectScreen extends StatefulWidget {
  final int tenderId;

  const TenderProjectScreen({super.key, required this.tenderId});

  @override
  State<TenderProjectScreen> createState() => _TenderProjectScreenState();
}

class _TenderProjectScreenState extends State<TenderProjectScreen> {
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

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _isBusy = true);
    try {
      await action();
      _changed = true;
      _snack(success);
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _start() => _run(
    () => ApiService.startTenderProject(widget.tenderId),
    'Project started. The customer has been told.',
  );

  Future<void> _complete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark this project complete?'),
        content: const Text(
          'The customer will be asked to review your work. Make sure every '
          'stage is finished first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(
      () => ApiService.completeTenderProject(widget.tenderId),
      'Project marked as complete.',
    );
  }

  Future<void> _reachMilestone(Map<String, dynamic> milestone) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${milestone['title']}" done?'),
        content: Text(
          'The customer is asked to release ${tenderMoney(milestone['amount'])} '
          'for this stage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark done'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run(
      () => ApiService.reachTenderMilestone(milestone['id']),
      'Stage marked done. The customer has been notified.',
    );
  }

  Future<void> _postUpdate() async {
    final result = await showModalBottomSheet<_ProgressDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProgressSheet(),
    );
    if (result == null) return;

    await _run(
      () => ApiService.postTenderProgress(
        tenderId: widget.tenderId,
        message: result.message,
        percentComplete: result.percentComplete,
        images: result.images,
      ),
      'Update posted.',
    );
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
          title: Text(_tender?['code']?.toString() ?? 'Project'),
          backgroundColor: tenderAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        floatingActionButton: _tender?['status'] == 'IN_PROGRESS'
            ? FloatingActionButton.extended(
                onPressed: _isBusy ? null : _postUpdate,
                backgroundColor: tenderAccent,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Post update'),
              )
            : null,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
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
              )
            : RefreshIndicator(onRefresh: _load, child: _content()),
      ),
    );
  }

  Widget _content() {
    final tender = _tender!;
    final status = '${tender['status']}';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // ------------------------------------------------------- headline
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
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TenderPill(style: tenderStatusStyle(status)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Agreed price',
                      tenderMoney(tender['final_amount']),
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      'Payment',
                      _paymentLabel(tender['payment_status']),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        _buildPrimaryAction(status),

        // ------------------------------------------------------- customer
        TenderCardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Customer & site',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '${tender['customer_name'] ?? ''}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${tender['address_text'] ?? ''}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              if ('${tender['location_label'] ?? ''}'.isNotEmpty)
                Text(
                  '${tender['location_label']}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              if ('${tender['customer_phone'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _call('${tender['customer_phone']}'),
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: Text('Call ${tender['customer_phone']}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tenderAccent,
                    side: const BorderSide(color: tenderAccent),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),
        _buildMilestones(tender, status),
        _buildProgress(tender),
      ],
    );
  }

  /// Start, finish, or nothing — whichever the project is waiting on.
  Widget _buildPrimaryAction(String status) {
    if (status == 'AWARDED') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isBusy ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start this project'),
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
      );
    }

    if (status == 'IN_PROGRESS') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isBusy ? null : _complete,
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Mark project complete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green.shade700,
              side: BorderSide(color: Colors.green.shade400),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildMilestones(Map<String, dynamic> tender, String status) {
    final milestones = (tender['milestones'] as List?) ?? const [];
    if (milestones.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TenderCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment stages',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final raw in milestones)
              _milestoneRow(Map<String, dynamic>.from(raw), status),
          ],
        ),
      ),
    );
  }

  Widget _milestoneRow(Map<String, dynamic> milestone, String tenderStatus) {
    final milestoneStatus = '${milestone['status']}';
    final isPaid = milestoneStatus == 'PAID';
    final isReached = milestoneStatus == 'REACHED';

    final color = isPaid
        ? Colors.green.shade700
        : isReached
        ? Colors.orange.shade700
        : Colors.grey.shade500;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPaid
                ? Icons.check_circle_rounded
                : isReached
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${milestone['title'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isPaid
                      ? 'Paid'
                      : isReached
                      ? 'Waiting on the customer to release payment'
                      : 'Not started',
                  style: TextStyle(fontSize: 11.5, color: color),
                ),
                // A stage can only be claimed while the project is running —
                // the same rule the server enforces.
                if (!isPaid && !isReached && tenderStatus == 'IN_PROGRESS')
                  TextButton(
                    onPressed: _isBusy ? null : () => _reachMilestone(milestone),
                    style: TextButton.styleFrom(
                      foregroundColor: tenderAccent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Mark this stage done'),
                  ),
              ],
            ),
          ),
          Text(
            tenderMoney(milestone['amount']),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(Map<String, dynamic> tender) {
    final updates = (tender['progress_updates'] as List?) ?? const [];
    if (updates.isEmpty) return const SizedBox.shrink();

    return TenderCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your updates',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final update in updates) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    tenderDateTime(update['created_at']),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                if (update['percent_complete'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tenderAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${update['percent_complete']}%',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: tenderAccent,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${update['message'] ?? ''}',
              style: const TextStyle(fontSize: 13.5),
            ),
            if ((update['photos'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: (update['photos'] as List).length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      '${update['photos'][index]['image']}',
                      width: 74,
                      height: 74,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 74,
                        height: 74,
                        color: tenderBg,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const Divider(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ],
  );

  String _paymentLabel(dynamic status) {
    switch (status) {
      case 'PAID':
        return 'Fully paid';
      case 'PARTIAL':
        return 'Part paid';
      default:
        return 'Nothing yet';
    }
  }
}

/// What the progress sheet hands back.
class _ProgressDraft {
  final String message;
  final int? percentComplete;
  final List<File> images;

  const _ProgressDraft({
    required this.message,
    required this.percentComplete,
    required this.images,
  });
}

/// Composing one progress update. Kept as a sheet so a vendor standing on
/// site can post in a few taps without losing sight of the project.
class _ProgressSheet extends StatefulWidget {
  const _ProgressSheet();

  @override
  State<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends State<_ProgressSheet> {
  final _message = TextEditingController();
  final _percent = TextEditingController();
  final List<File> _images = [];

  @override
  void dispose() {
    _message.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool fromCamera}) async {
    final picker = ImagePicker();
    if (fromCamera) {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (shot != null) setState(() => _images.add(File(shot.path)));
      return;
    }
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isNotEmpty) {
      setState(() => _images.addAll(picked.map((x) => File(x.path))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Post an update',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'The customer sees this straight away.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Footings poured, curing until Thursday.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _percent,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Percent complete (optional)',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            _images[index],
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _images.removeAt(index)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(fromCamera: true),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tenderAccent,
                      side: const BorderSide(color: tenderAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(fromCamera: false),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tenderAccent,
                      side: const BorderSide(color: tenderAccent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final message = _message.text.trim();
                  if (message.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Write a line about what has been done.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _ProgressDraft(
                      message: message,
                      percentComplete: int.tryParse(_percent.text.trim()),
                      images: _images,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: tenderAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Post update'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
