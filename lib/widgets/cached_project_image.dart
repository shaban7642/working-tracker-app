import 'package:flutter/material.dart';

/// Project image widget with fallback to letter initial.
/// Uses Flutter's built-in Image.network which has in-memory caching via ImageCache.
class CachedProjectImage extends StatelessWidget {
  final String? imageUrl;
  final String projectName;
  final double size;
  final double borderRadius;
  final bool isActive;
  final Color? activeColor;

  /// Track URLs that have already failed to avoid log spam on rebuilds.
  static final Set<String> _failedUrls = {};

  const CachedProjectImage({
    super.key,
    required this.imageUrl,
    required this.projectName,
    this.size = 64,
    this.borderRadius = 11,
    this.isActive = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildFallback();
    }

    // Skip network request for URLs known to fail
    if (_failedUrls.contains(imageUrl)) {
      return _buildFallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).toInt(), // Cache at 2x for retina
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildLoading();
        },
        errorBuilder: (context, error, stackTrace) {
          _failedUrls.add(imageUrl!);
          debugPrint('Failed to load project image for "$projectName": $error');
          debugPrint('URL: $imageUrl');
          return _buildFallback();
        },
      ),
    );
  }

  Widget _buildLoading() {
    final effectiveActiveColor = activeColor ?? const Color(0xFF4CAF50);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isActive
            ? effectiveActiveColor.withValues(alpha: 0.2)
            : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: SizedBox(
          width: size * 0.3,
          height: size * 0.3,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: isActive ? effectiveActiveColor : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback() {
    final effectiveActiveColor = activeColor ?? const Color(0xFF4CAF50);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isActive
            ? effectiveActiveColor.withValues(alpha: 0.2)
            : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Text(
          projectName.isNotEmpty ? projectName[0].toUpperCase() : 'P',
          style: TextStyle(
            fontSize: size * 0.375,
            fontWeight: FontWeight.bold,
            color: isActive ? effectiveActiveColor : Colors.white70,
          ),
        ),
      ),
    );
  }
}
