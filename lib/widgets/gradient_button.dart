import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.width,
    this.height = 50,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final radius = borderRadius ?? BorderRadius.circular(12);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: isEnabled ? AppTheme.primaryGradient : null,
        color: isEnabled ? null : AppTheme.textHint,
        borderRadius: radius,
        boxShadow: isEnabled
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Container(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            alignment: Alignment.center,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GradientButtonWithIcon extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final bool isLoading;

  const GradientButtonWithIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.width,
    this.height = 50,
    this.borderRadius,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      onPressed: isLoading ? null : onPressed,
      width: width,
      height: height,
      borderRadius: borderRadius,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
    );
  }
}
