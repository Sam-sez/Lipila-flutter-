import 'package:flutter/material.dart';
import '../theme/lipila_theme.dart';

/// The Quick Actions button style. Ported from the web app's .action-btn,
/// but tuned down from an earlier overly-thick first pass — subtle raised
/// look, not a cartoonish 3D shelf.
class LipilaActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool secondary;

  const LipilaActionButton({
    super.key, required this.label, required this.onTap, this.secondary = false,
  });

  @override
  State<LipilaActionButton> createState() => _LipilaActionButtonState();
}

class _LipilaActionButtonState extends State<LipilaActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.secondary
        ? [const Color(0xFF3A2718), LipilaColors.espresso, const Color(0xFF1E0F02)]
        : [LipilaColors.emberLight, LipilaColors.ember, LipilaColors.emberDeep];
    final shadowColor = widget.secondary ? const Color(0xFF1E0F02) : LipilaColors.emberDeep;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(color: shadowColor, offset: const Offset(0, 2)),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3)),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFFFFF9F2), fontWeight: FontWeight.w700, fontSize: 15,
              ),
            ),
            const Text('›', style: TextStyle(color: Color(0xFFFFF9F2), fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
