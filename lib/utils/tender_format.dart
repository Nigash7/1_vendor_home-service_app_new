import 'package:flutter/material.dart';

/// Formatting and status styling shared by the tender screens.
///
/// Hand-rolled rather than using intl, because the vendor app does not depend
/// on it — the same reason JobsListScreen formats its own dates.

const tenderAccent = Colors.deepOrange;
const tenderBg = Color(0xFFF6F6F8);
const tenderBorder = Color(0xFFEDEDF2);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// '1400000' -> '₹14,00,000', using Indian digit grouping. Anything
/// unparseable comes back as an em dash — a missing figure is normal here.
String tenderMoney(dynamic amount) {
  final value = double.tryParse('${amount ?? ''}');
  if (value == null) return '—';

  final negative = value < 0;
  var text = value.abs().truncate().toString();

  // Last three digits, then pairs: 12,34,567.
  if (text.length > 3) {
    final head = text.substring(0, text.length - 3);
    final tail = text.substring(text.length - 3);
    final grouped = head.replaceAllMapped(
      RegExp(r'(\d)(?=(\d\d)+$)'),
      (m) => '${m[1]},',
    );
    text = '$grouped,$tail';
  }

  return '${negative ? '−' : ''}₹$text';
}

/// '2026-08-26' -> '26 Aug 2026'.
String tenderDate(dynamic raw) {
  final parsed = DateTime.tryParse('${raw ?? ''}'.trim());
  if (parsed == null) return '—';
  return '${parsed.day} ${_months[parsed.month - 1]} ${parsed.year}';
}

/// '2026-08-26T10:30:00Z' -> '26 Aug, 10:30 AM'.
String tenderDateTime(dynamic raw) {
  final parsed = DateTime.tryParse('${raw ?? ''}'.trim())?.toLocal();
  if (parsed == null) return '—';

  final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final minute = parsed.minute.toString().padLeft(2, '0');
  final meridiem = parsed.hour < 12 ? 'AM' : 'PM';

  return '${parsed.day} ${_months[parsed.month - 1]}, '
      '$hour12:$minute $meridiem';
}

/// 'Closes in 3 days' / 'Closing today' / null when there is no deadline.
/// The thing a vendor scanning the list needs before anything else.
String? tenderDeadlineHint(dynamic rawDeadline) {
  final deadline = DateTime.tryParse('${rawDeadline ?? ''}'.trim());
  if (deadline == null) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(deadline.year, deadline.month, deadline.day);
  final days = target.difference(today).inDays;

  if (days < 0) return 'Bidding closed';
  if (days == 0) return 'Closing today';
  if (days == 1) return 'Closes tomorrow';
  return 'Closes in $days days';
}

/// Whether a deadline is close enough to push, for the urgency styling.
bool tenderDeadlineIsUrgent(dynamic rawDeadline) {
  final deadline = DateTime.tryParse('${rawDeadline ?? ''}'.trim());
  if (deadline == null) return false;

  final now = DateTime.now();
  final days = DateTime(
    deadline.year,
    deadline.month,
    deadline.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  return days >= 0 && days <= 2;
}

class TenderStatusStyle {
  final String label;
  final Color color;
  final IconData icon;

  const TenderStatusStyle(this.label, this.color, this.icon);
}

/// Tender status, as the vendor should read it.
TenderStatusStyle tenderStatusStyle(String? status) {
  switch (status) {
    case 'OPEN':
      return TenderStatusStyle(
        'Open for bids',
        Colors.blue.shade700,
        Icons.campaign_rounded,
      );
    case 'AWARDED':
      return TenderStatusStyle(
        'Awarded',
        Colors.indigo.shade600,
        Icons.handshake_rounded,
      );
    case 'IN_PROGRESS':
      return TenderStatusStyle(
        'In progress',
        Colors.purple.shade600,
        Icons.construction_rounded,
      );
    case 'COMPLETED':
      return TenderStatusStyle(
        'Completed',
        Colors.green.shade700,
        Icons.check_circle_outline_rounded,
      );
    case 'CANCELLED':
      return TenderStatusStyle(
        'Cancelled',
        Colors.red.shade600,
        Icons.cancel_outlined,
      );
    default:
      return TenderStatusStyle(
        status ?? 'Unknown',
        Colors.grey,
        Icons.help_outline_rounded,
      );
  }
}

/// A bid's own state — what happened to the vendor's quote.
TenderStatusStyle bidStatusStyle(String? status) {
  switch (status) {
    case 'SUBMITTED':
      return TenderStatusStyle(
        'Waiting on customer',
        Colors.blue.shade700,
        Icons.hourglass_top_rounded,
      );
    case 'ACCEPTED':
      return TenderStatusStyle(
        'You won',
        Colors.green.shade700,
        Icons.emoji_events_rounded,
      );
    case 'REJECTED':
      return TenderStatusStyle(
        'Not selected',
        Colors.grey.shade600,
        Icons.do_not_disturb_on_outlined,
      );
    case 'WITHDRAWN':
      return TenderStatusStyle(
        'Withdrawn',
        Colors.grey.shade600,
        Icons.undo_rounded,
      );
    default:
      return TenderStatusStyle(
        status ?? 'Unknown',
        Colors.grey,
        Icons.help_outline_rounded,
      );
  }
}

/// The pill used on cards and headers.
class TenderPill extends StatelessWidget {
  final TenderStatusStyle style;
  final bool compact;

  const TenderPill({super.key, required this.style, this.compact = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 13 : 16, color: style.color),
          const SizedBox(width: 5),
          Text(
            style.label,
            style: TextStyle(
              color: style.color,
              fontSize: compact ? 11.5 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The white bordered card the vendor app uses everywhere.
class TenderCardShell extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  const TenderCardShell({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tenderBorder),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: content,
      ),
    );
  }
}
