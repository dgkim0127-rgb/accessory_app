// lib/services/thumbnail_service.dart
// ------------------------------------------------------------
// 🚀 초경량 GPU-FRIENDLY 썸네일 생성 버전 (최종)
// - maxSize: 512px (기존 800px → GPU 안정성 + 로딩속도 개선)
// - JPEG 품질: 70 (기존 80 → 용량 절반 수준)
// - 모바일: compute()로 백그라운드 처리해서 UI 멈춤 방지
// - 웹: image 패키지로 직접 리사이즈 (안정성 향상)
// ------------------------------------------------------------

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart' show kIsWeb;

class ThumbnailService {
  ThumbnailService._();

  /// 🖼️ 원본 → 512px GPU-Friendly 썸네일
  static Future<Uint8List> generateThumbnailBytes({
    required Uint8List data,

    /// 🔥 800px → 512px 로 안정성 + 속도 ↑
    int maxSize = 512,
  }) async {
    if (kIsWeb) {
      // ------------------------------------------------------------
      // 웹은 isolate 불가능 → 메인 스레드에서 처리
      // 하지만 maxSize 512px이기 때문에 안정적
      // ------------------------------------------------------------
      final decoded = img.decodeImage(data);
      if (decoded == null) return data;

      final resized = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? maxSize : null,
        height: decoded.height >= decoded.width ? maxSize : null,

        /// 🔥 linear → cubic (더 선명하고 안정적)
        interpolation: img.Interpolation.cubic,
      );

      return Uint8List.fromList(
        img.encodeJpg(resized, quality: 70), // 품질 ↓ → 크기 ↓ → 속도 ↑
      );
    }

    // ------------------------------------------------------------
    // 모바일은 compute() → UI 멈춤 방지
    // ------------------------------------------------------------
    return compute(_backgroundTask, {
      'data': data,
      'max': maxSize,
    });
  }
}

/// 🧠 모바일 백그라운드용 isolate
Uint8List _backgroundTask(Map args) {
  final Uint8List data = args['data'];
  final int maxSize = args['max'];

  final decoded = img.decodeImage(data);
  if (decoded == null) return data;

  final resized = img.copyResize(
    decoded,
    width: decoded.width > decoded.height ? maxSize : null,
    height: decoded.height >= decoded.width ? maxSize : null,
    interpolation: img.Interpolation.cubic, // 선명하고 부드러움
  );

  // 품질 70 → 속도 매우 빠름
  return Uint8List.fromList(
    img.encodeJpg(resized, quality: 70),
  );
}
