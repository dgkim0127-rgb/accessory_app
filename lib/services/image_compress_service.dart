// lib/services/image_compress_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// 사진만 가볍게 줄여서 업로드하기 위한 압축 서비스
class ImageCompressService {
  static const int _defaultMaxWidth = 1600;
  static const int _defaultMaxHeight = 1600;
  static const int _defaultQuality = 75; // 0~100 (70~80 정도가 무난)

  /// XFile(카메라/갤러리에서 고른 사진)을 받아서
  /// - 최대 1600px 정도로 리사이즈
  /// - JPEG 품질 75% 정도로 압축
  /// 해서 Uint8List 로 돌려줌.
  static Future<Uint8List> compressXFile(
      XFile file, {
        int maxWidth = _defaultMaxWidth,
        int maxHeight = _defaultMaxHeight,
        int quality = _defaultQuality,
      }) async {
    final originalBytes = await file.readAsBytes();

    try {
      final result = await FlutterImageCompress.compressWithList(
        originalBytes,
        quality: quality,
        minWidth: maxWidth,
        minHeight: maxHeight,
        format: CompressFormat.jpeg, // 확실하게 jpeg로 맞춤
      );
      return Uint8List.fromList(result);
    } catch (_) {
      // 혹시 웹이나 특정 환경에서 오류가 나도
      // 앱이 죽지 않도록 → 원본 그대로 업로드
      return originalBytes;
    }
  }
}
