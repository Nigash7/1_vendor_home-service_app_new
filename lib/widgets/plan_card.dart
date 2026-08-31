import 'package:flutter/material.dart';

/// One subscription tier, drawn the same way on the signup screen and on the
/// subscription screen so a vendor recognises what they picked.
///
/// The card renders whatever `/api/subscriptions/plans/` returns, so a tier an
/// admin adds tomorrow shows up without a change here.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    this.selected = false,
    this.isCurrent = false,
    this.badge,
    this.action,
    this.onTap,
  });

  final Map<String, dynamic> plan;

  /// Ticked on the signup screen. Not the same as [isCurrent].
  final bool selected;

  /// The plan the vendor is actually on.
  final bool isCurrent;

  /// Overrides the default corner label ("Current plan" / "Recommended").
  final String? badge;

  /// Button row under the features, e.g. "Request upgrade".
  final Widget? action;

  final VoidCallback? onTap;

  bool get _isFree => plan['is_free'] == true;

  String get _priceLabel {
    if (_isFree) return 'Free';
    // The API sends a decimal string; trailing '.00' is noise on a card.
    final raw = '${plan['price'] ?? '0'}';
    final trimmed = raw.contains('.')
        ? raw.replaceFirst(RegExp(r'\.?0+$'), '')
        : raw;
    return '₹$trimmed';
  }

  List<String> get _features =>
      (plan['features'] as List?)?.map((f) => '$f').toList() ?? const [];

  @override
  Widget build(BuildContext context) {
    final highlighted = selected || isCurrent;
    final accent = isCurrent ? Colors.green.shade700 : Colors.deepOrange;

    final label = badge ??
        (isCurrent ? 'Current plan' : (plan['is_default'] == true ? 'Included' : null));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted ? accent : const Color(0xFFEDEDF2),
            width: highlighted ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onTap != null) ...[
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? accent : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan['name'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if ('${plan['description'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${plan['description']}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _priceLabel,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    if (!_isFree)
                      Text(
                        '${plan['billing_period_display'] ?? ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (label != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
            if (_features.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 15,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: action),
            ],
          ],
        ),
      ),
    );
  }
}
