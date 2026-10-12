import 'package:flutter/material.dart';

import '../theme.dart';

/// A full-width button, far larger than the 48dp minimum touch target.
///
/// Users who cannot see the screen find buttons by touch, so the main
/// actions are made big enough to hit without aiming. The screen reader
/// label is set explicitly, so TalkBack reads exactly [semanticLabel]
/// rather than guessing from the icon and text.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.icon,
    this.colour = AppColours.primary,
    this.height = 88,
    this.fontSize = 24,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final IconData? icon;
  final Color colour;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: semanticLabel ?? label,
        // The tap must live on this node: excludeSemantics hides the
        // button's own tap action from TalkBack, so without this a
        // double-tap would do nothing.
        onTap: onPressed,
        excludeSemantics: true,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: colour,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade400,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: fontSize + 8),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
