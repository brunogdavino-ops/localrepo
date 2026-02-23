import 'package:flutter/material.dart';

class ArteziAnswerIconButton extends StatelessWidget {
  final IconData icon;
  final Color? stateColor;
  final bool selected;
  final VoidCallback onTap;
  final double selectedFillOpacity;
  final double selectedBorderOpacity;

  const ArteziAnswerIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.stateColor,
    this.selected = false,
    this.selectedFillOpacity = 0.12,
    this.selectedBorderOpacity = 0.20,
  });

  @override
  Widget build(BuildContext context) {
    final color = stateColor ?? const Color(0xFF9AA0B2);
    final bool hasState = stateColor != null;

    final Color background = selected && hasState
        ? color.withValues(alpha: selectedFillOpacity)
        : Colors.white.withValues(alpha: 0.96);

    final Color border = selected && hasState
        ? color.withValues(alpha: selectedBorderOpacity)
        : const Color.fromRGBO(57, 48, 110, 0.10);

    final Color iconColor = selected && hasState ? color : const Color(0xFF9AA0B2);

    return SizedBox(
      width: 34,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Icon(
              icon,
              size: 17,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
