import 'package:flutter/material.dart';


enum StatusBadgeType { completed, pending, started }

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusBadgeType type;

  const StatusBadge({
    Key? key,
    required this.label,
    required this.type,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color textColor = type == StatusBadgeType.completed
        ? const Color(0xFF16A34A)
        : const Color(0xFFD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}
