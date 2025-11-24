// lib/widgets/app_cached_image.dart
// ------------------------------------------------------------
// 공통 이미지 로더 위젯
// - cached_network_image 기반
// - 로딩 인디케이터 / 에러 위젯 기본 제공
// - BoxFit / width / height / radius 커스터마이징 가능
// - Cloudinary 이미지면 f_auto,q_auto:eco,w_1080 적용해서
//   용량을 KB 단위까지 줄이면서 화질 최대한 유지
// ------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AppCachedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  const AppCachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _errorBox();
    }

    final optimizedUrl = _optimizeCloudinaryImageUrl(url);

    final img = CachedNetworkImage(
      imageUrl: optimizedUrl,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: 1080,
      memCacheHeight: 1080,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 120),

      // 로딩 중 위젯
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),

      // 실패 시 위젯
      errorWidget: (_, __, ___) => _errorBox(),
    );

    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: img,
      );
    }
    return img;
  }

  Widget _errorBox() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Colors.black38,
          size: 24,
        ),
      ),
    );
  }
}

// Cloudinary 이미지 URL 최적화 (f_auto + q_auto:eco + w_1080)
// → 화질은 유지하면서도 용량을 KB 단위까지 내림
String _optimizeCloudinaryImageUrl(String url) {
  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return url; // Cloudinary 형식이 아니면 그대로

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  // 이미 변환 파라미터가 붙어 있으면 그대로 사용
  if (after.startsWith('f_auto') || after.startsWith('q_auto')) {
    return url;
  }

  return '$before'
      'f_auto,q_auto:eco,w_1080/'
      '$after';
}
