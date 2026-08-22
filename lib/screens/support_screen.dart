import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'ticket_detail_screen.dart';

/// The vendor's Help & Support inbox: every ticket they have raised, and the
/// way in to raise a new one. Replies come back from the admin dashboard.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<dynamic> _tickets = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final tickets = await ApiService.getMyTickets();
      if (mounted) {
        setState(() {
          _tickets = tickets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openNewTicket() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateTicketScreen()),
    );
    if (created == true) _loadTickets();
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'OPEN':
        return Colors.orange.shade800;
      case 'IN_PROGRESS':
        return Colors.blue.shade700;
      case 'RESOLVED':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicket,
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Ticket'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError()
          : RefreshIndicator(
              onRefresh: _loadTickets,
              child: _tickets.isEmpty ? _buildEmpty() : _buildList(),
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadTickets, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    // Wrapped in a scrollable so pull-to-refresh still works when empty.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Icon(Icons.support_agent, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No support tickets yet.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Stuck on a job or a payout? Tap "New Ticket".',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _tickets.length,
      itemBuilder: (context, index) {
        final ticket = _tickets[index];
        final status = '${ticket['status'] ?? 'OPEN'}';
        final messages = ticket['messages'] as List<dynamic>? ?? const [];
        final lastMsg = messages.isNotEmpty ? messages.last : null;
        final hasSupportReply = lastMsg != null && lastMsg['is_support'] == true;
        final color = statusColor(status);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDEDF2)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TicketDetailScreen(ticketId: ticket['id']),
                ),
              );
              _loadTickets();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${ticket['subject'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${ticket['status_display'] ?? status}',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (lastMsg != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${hasSupportReply ? 'Support: ' : ''}${lastMsg['message'] ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasSupportReply
                            ? Colors.black87
                            : Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '#${ticket['id']} · ${ticket['category_display'] ?? ''}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (hasSupportReply)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'New reply',
                            style: TextStyle(
                              color: Colors.deepOrange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- Create Ticket Screen ----------

class CreateTicketScreen extends StatefulWidget {
  /// Pre-attach the ticket to a job when it is raised from a job screen.
  final int? bookingId;

  const CreateTicketScreen({super.key, this.bookingId});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  /// Mirrors SupportTicket.VENDOR_CATEGORIES on the server. Refreshed from
  /// /support/categories/ so a server-side change doesn't need an app release.
  List<Map<String, String>> _categories = const [
    {'value': 'JOB', 'label': 'Job / Assignment Issue'},
    {'value': 'PAYOUT', 'label': 'Payout Issue'},
    {'value': 'PAYMENT', 'label': 'Payment Issue'},
    {'value': 'ACCOUNT', 'label': 'Account Issue'},
    {'value': 'APP', 'label': 'App / Technical Issue'},
    {'value': 'OTHER', 'label': 'Other'},
  ];
  String _category = 'JOB';
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.getTicketCategories();
      if (!mounted || categories.isEmpty) return;
      setState(() {
        _categories = categories
            .map<Map<String, String>>(
              (c) => {'value': '${c['value']}', 'label': '${c['label']}'},
            )
            .toList();
        if (!_categories.any((c) => c['value'] == _category)) {
          _category = _categories.first['value']!;
        }
      });
    } catch (_) {
      // The built-in list is a fine fallback — don't block the vendor.
    }
  }

  Future<void> _submit() async {
    if (_subjectController.text.trim().isEmpty ||
        _messageController.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ApiService.createTicket(
        subject: _subjectController.text.trim(),
        category: _category,
        message: _messageController.text.trim(),
        bookingId: widget.bookingId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('New Support Ticket'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'What is this about?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: _categories
                .map(
                  (c) => DropdownMenuItem(
                    value: c['value'],
                    child: Text(c['label']!),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 16),
          const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Brief summary of your issue',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Message', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'Describe your issue in detail. Include the booking number if it is about a job.',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit Ticket'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Support usually replies within one working day.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
