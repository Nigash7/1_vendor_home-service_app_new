import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Which way the thumb travels to confirm.
enum SlideDirection { leftToRight, rightToLeft }

/// A slide-to-confirm track, used for starting and finishing a job.
///
/// A deliberate gesture rather than a tap, because both actions are one-way:
/// starting opens the camera and stamps a geotagged photo, finishing closes
/// the job out. Neither should be reachable by a stray press in someone's
/// pocket or a mis-tap while holding a phone on site.
class SlideAction extends StatefulWidget {
  final String label;

  /// Shown while [onConfirm] is running.
  final String processingLabel;
  final IconData icon;
  final Color color;

  /// Awaited, so the track stays locked until the work finishes and springs
  /// back on its own if the action was cancelled or failed.
  final Future<void> Function() onConfirm;

  final bool enabled;
  final SlideDirection direction;

  const SlideAction({
    super.key,
    required this.label,
    required this.onConfirm,
    this.processingLabel = 'Please wait...',
    this.icon = Icons.chevron_right_rounded,
    this.color = Colors.blue,
    this.enabled = true,
    this.direction = SlideDirection.leftToRight,
  });

  @override
  State<SlideAction> createState() => _SlideActionState();
}

class _SlideActionState extends State<SlideAction>
    with SingleTickerProviderStateMixin {
  static const _trackHeight = 62.0;
  static const _thumbInset = 5.0;
  static const _confirmAt = 0.85; // fraction of the track that commits

  late final AnimationController _springBack;
  late final Animation<double> _springCurve;

  double _drag = 0;
  double _maxDrag = 1;

  /// Where the thumb was when the finger lifted — the spring animates from
  /// here back to zero.
  double _dragAtRelease = 0;
  bool _busy = false;

  double get _thumbSize => _trackHeight - (_thumbInset * 2);
  double get _progress => (_drag / _maxDrag).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _springBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _springCurve = CurvedAnimation(parent: _springBack, curve: Curves.easeOut);
    _springBack.addListener(() {
      setState(() => _drag = _dragAtRelease * (1 - _springCurve.value));
    });
  }

  @override
  void dispose() {
    _springBack.dispose();
    super.dispose();
  }

  bool get _locked => _busy || !widget.enabled;

  void _onDragUpdate(DragUpdateDetails details) {
    if (_locked) return;
    final delta = widget.direction == SlideDirection.leftToRight
        ? details.delta.dx
        : -details.delta.dx;
    setState(() => _drag = (_drag + delta).clamp(0.0, _maxDrag));
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_locked) return;

    if (_progress < _confirmAt) {
      _slideHome();
      return;
    }

    // Committed — pin the thumb to the end and run the action.
    setState(() {
      _drag = _maxDrag;
      _busy = true;
    });
    HapticFeedback.mediumImpact();

    try {
      await widget.onConfirm();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _slideHome();
      }
    }
  }

  void _slideHome() {
    _dragAtRelease = _drag;
    _springBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final leftToRight = widget.direction == SlideDirection.leftToRight;
    final tint = widget.enabled ? widget.color : Colors.grey;

    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = constraints.maxWidth - _thumbSize - (_thumbInset * 2);
        if (_maxDrag <= 0) _maxDrag = 1;

        return Container(
          height: _trackHeight,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_trackHeight / 2),
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: Stack(
            children: [
              // The track fills in behind the thumb as it travels.
              Positioned(
                left: leftToRight ? 0 : null,
                right: leftToRight ? null : 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: _drag + _thumbSize + (_thumbInset * 2),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                  ),
                ),
              ),

              // Label, fading out as the thumb covers it.
              Center(
                child: Opacity(
                  opacity: (1 - (_progress * 1.6)).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!leftToRight) ...[
                        Icon(Icons.keyboard_double_arrow_left_rounded,
                            size: 19, color: tint),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _busy ? widget.processingLabel : widget.label,
                        style: TextStyle(
                          color: tint,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (leftToRight) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.keyboard_double_arrow_right_rounded,
                            size: 19, color: tint),
                      ],
                    ],
                  ),
                ),
              ),

              // Draggable thumb.
              Positioned(
                left: leftToRight ? _thumbInset + _drag : null,
                right: leftToRight ? null : _thumbInset + _drag,
                top: _thumbInset,
                child: GestureDetector(
                  onHorizontalDragUpdate: _onDragUpdate,
                  onHorizontalDragEnd: _onDragEnd,
                  child: Container(
                    height: _thumbSize,
                    width: _thumbSize,
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(15),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Icon(widget.icon, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
