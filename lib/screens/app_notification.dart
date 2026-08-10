import 'package:flutter/material.dart';

/// One notification as returned by GET /api/notifications/
class AppNotification {
  final int id;
  final String event;
  final String category;
  final String title;
  final String body;
  final int? bookingId;
  final String route;
  final Map<String, dynamic> data;
  final String imageUrl;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.event,
    required this.category,
    required this.title,
    required this.body,
    this.bookingId,
    this.route = '',
    this.data = const {},
    this.imageUrl = '',
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as int,
      event: json['event']?.toString() ?? '',
      category: json['category']?.toString() ?? 'SYSTEM',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      bookingId: json['booking'] as int?,
      route: json['route']?.toString() ?? '',
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      imageUrl: json['image_url']?.toString() ?? '',
      isRead: json['is_read'] == true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    event: event,
    category: category,
    title: title,
    body: body,
    bookingId: bookingId,
    route: route,
    data: data,
    imageUrl: imageUrl,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );

  // ----------------------------------------------------------- presentation
  IconData get icon {
    switch (category) {
      case 'BOOKING':
        return Icons.event_available_outlined;
      case 'PAYMENT':
        return Icons.account_balance_wallet_outlined;
      case 'PROMO':
        return Icons.local_offer_outlined;
      case 'REVIEW':
        return Icons.star_outline;
      case 'ACCOUNT':
        return Icons.person_outline;
      default:
        return Icons.notifications_none;
    }
  }

  Color get accent {
    switch (category) {
      case 'BOOKING':
        return const Color(0xFF2563EB);
      case 'PAYMENT':
        return const Color(0xFF059669);
      case 'PROMO':
        return const Color(0xFFEA580C);
      case 'REVIEW':
        return const Color(0xFFCA8A04);
      case 'ACCOUNT':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF64748B);
    }
  }

  /// "2m ago" / "3h ago" / "Yesterday" / "12 Jul"
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    const months = [
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
    return '${createdAt.day} ${months[createdAt.month - 1]}';
  }
}

/// One page of results plus the global unread count the API returns alongside.
class NotificationPage {
  final List<AppNotification> items;
  final int totalCount;
  final int unreadCount;
  final bool hasMore;

  const NotificationPage({
    required this.items,
    required this.totalCount,
    required this.unreadCount,
    required this.hasMore,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) {
    final results = (json['results'] as List?) ?? const [];
    return NotificationPage(
      items: results
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: json['count'] as int? ?? results.length,
      unreadCount: json['unread_count'] as int? ?? 0,
      hasMore: json['next'] != null,
    );
  }
}
