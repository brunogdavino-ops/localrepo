import 'package:flutter/material.dart';

class ArteziProgressBar extends StatelessWidget {
  final double progress;

  const ArteziProgressBar({
    super.key,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final widthFactor = progress.clamp(0.0, 1.0);

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFFE3E3EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6D4BC3), Color(0xFF5A3E8E)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
