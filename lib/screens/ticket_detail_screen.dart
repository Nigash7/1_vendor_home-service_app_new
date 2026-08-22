import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// One support conversation. The vendor's own messages sit on the right,
/// support's replies on the left.
class TicketDetailScreen extends StatefulWidget {
  final int ticketId;

  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Map<String, dynamic>? _ticket;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTicket();
  }

  Future<void> _loadTicket() async {
    try {
      final ticket = await ApiService.getTicketDetail(widget.ticketId);
      if (mounted) {
        setState(() {
          _ticket = ticket;
          _isLoading = false;
        });
        _scrollToBottom();
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

  void _scrollToBottom() {
    // Runs after the list has been laid out with the new messages.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      await ApiService.addTicketMessage(
        ticketId: widget.ticketId,
        message: text,
      );
      _messageController.clear();
      await _loadTicket();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isClosed => '${_ticket?['status']}' == 'CLOSED';

  @override
  Widget build(BuildContext context) {
    final messages = _ticket?['messages'] as List<dynamic>? ?? const [];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F8),
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_ticket?['subject'] ?? 'Ticket'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
            if (_ticket != null)
              Text(
                '#${_ticket!['id']} · ${_ticket!['status_display'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? _buildError()
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) =>
                        _buildBubble(messages[index]),
                  ),
                ),
                _buildComposer(),
              ],
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
            ElevatedButton(onPressed: _loadTicket, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(dynamic msg) {
    final isSupport = msg['is_support'] == true;

    return Align(
      alignment: isSupport ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isSupport ? Colors.white : Colors.deepOrange,
          borderRadius: BorderRadius.circular(16),
          border: isSupport
              ? Border.all(color: const Color(0xFFEDEDF2))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${msg['message'] ?? ''}',
              style: TextStyle(
                color: isSupport ? Colors.black87 : Colors.white,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isSupport ? 'Support' : 'You',
              style: TextStyle(
                color: isSupport ? Colors.black45 : Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: _isClosed
                      ? 'Reply to reopen this ticket...'
                      : 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.deepOrange,
              child: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
