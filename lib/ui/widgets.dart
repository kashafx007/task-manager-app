/// Small reusable widgets shared by several screens.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Soft gingham (checked) background with a centred, width-limited child.
class CutePage extends StatelessWidget {
  const CutePage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      color: c.bg,
      child: CustomPaint(
        painter: _GinghamPainter(c.stripeA, c.stripeB),
        child: child,
      ),
    );
  }
}

class _GinghamPainter extends CustomPainter {
  _GinghamPainter(this.vertical, this.horizontal);
  final Color vertical;
  final Color horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 30.0;
    const stripe = 15.0;
    final vPaint = Paint()..color = vertical;
    final hPaint = Paint()..color = horizontal;
    for (double x = 0; x < size.width; x += cell) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, size.height), vPaint);
    }
    for (double y = 0; y < size.height; y += cell) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, stripe), hPaint);
    }
  }

  @override
  bool shouldRepaint(_GinghamPainter old) =>
      old.vertical != vertical || old.horizontal != horizontal;
}

/// Rounded card used for sections in forms and settings.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.padding});
  final String? title;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.text),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// A pill-shaped choice chip in the app's style.
class CuteChoiceChip extends StatelessWidget {
  const CuteChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: c.primary,
      backgroundColor: c.card,
      side: BorderSide(color: selected ? c.primary : c.border),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: selected ? c.onPrimary : c.text,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }
}

/// Emoji + message shown when a list is empty.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.emoji, required this.title, required this.subtitle});
  final String emoji;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center, style: TextStyle(color: c.subtext, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
