import 'package:flutter/material.dart';


class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool useGradient;
  final double height;

  const GradientButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.enabled = true,
    this.useGradient = true,
    this.height = 52,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isActive = enabled && onPressed != null;

    final BoxDecoration decoration;
    if (!isActive) {
      decoration = BoxDecoration(
        color: const Color(0xFFDCDCE6),
        borderRadius: BorderRadius.circular(16),
      );
    } else if (useGradient) {
      decoration = BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D4BC3), Color(0xFF5A3E8E)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x595A3E8E),
            blurRadius: 45,
            offset: Offset(0, 18),
          ),
        ],
      );
    } else {
      decoration = BoxDecoration(
        color: const Color(0xFF7262C2),
        borderRadius: BorderRadius.circular(16),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isActive ? onPressed : null,
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : const Color(0xFF9A9AB0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
