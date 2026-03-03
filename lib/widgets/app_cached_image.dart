// lib/widgets/app_cached_image.dart ✅ 최종 (화질저하 유발 코드 제거/정리)
// ✅ 변경점
// - 예전: w_1080 고정 + q_auto:eco 고정 → 상세에서도 뭉개져 보일 수 있음
// - 최종: 목적별(sizeHint)로 URL을 변환해서 불러옴 (thumb/medium/slider)
// - memCacheWidth/Height는 "메모리 절약"일 뿐 원본 화질을 강제로 낮추진 않지만,
//   너무 작은 값이면 확대 시 뭉개져 보여서 목적별로 맞춤.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/cloudinary_image_utils.dart';

enum AppImageHint {
  thumb,  // 그리드 썸네일
  medium, // 상세
  slider, // 상단 슬라이더
  original, // 변환 없이(권장X)
}

class AppCachedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  /// ✅ 어떤 용도로 쓰는지 힌트
  final AppImageHint hint;

  const AppCachedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.hint = AppImageHint.medium,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _errorBox();

    final optimizedUrl = _pickUrlByHint(url, hint);
    final cache = _cacheSizeByHint(hint);

    final img = CachedNetworkImage(
      imageUrl: optimizedUrl,
      fit: fit,
      width: width,
      height: height,

      // ✅ 확대/선명도 체감에 직접 영향
      memCacheWidth: cache.$1,
      memCacheHeight: cache.$2,

      fadeInDuration: const Duration(milliseconds: 160),
      fadeOutDuration: const Duration(milliseconds: 120),

      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
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

  String _pickUrlByHint(String raw, AppImageHint h) {
    switch (h) {
      case AppImageHint.thumb:
        return buildThumbUrl(raw);
      case AppImageHint.slider:
        return buildSliderUrl(raw);
      case AppImageHint.medium:
        return buildMediumUrl(raw);
      case AppImageHint.original:
        return raw;
    }
  }

  /// (memCacheWidth, memCacheHeight)
  (int?, int?) _cacheSizeByHint(AppImageHint h) {
    switch (h) {
      case AppImageHint.thumb:
        return (480, 480);
      case AppImageHint.slider:
        return (900, 900);
      case AppImageHint.medium:
        return (1600, 1600);
      case AppImageHint.original:
        return (null, null); // 원본은 캐시 제한 안 둠(메모리 부담)
    }
  }
}
