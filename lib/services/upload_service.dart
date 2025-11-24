// lib/services/upload_service.dart
// ------------------------------------------------------------
// Cloudinary 업로드 서비스 (이미지 + 360° + 동영상)
//
// ⭐ 이미지/스핀 이미지는 그대로 원본 업로드
// ⭐ 동영상만 사전 압축 후 Cloudinary(video) 업로드
// ------------------------------------------------------------

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import 'cloudinary_service.dart';

class UploadService {
  UploadService._();

  static String _extFromName(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0 || i == name.length - 1) return 'jpg';
    return name.substring(i + 1).toLowerCase();
  }

  // ─────────────────────────────────────────────────────────────
  // 1) 이미지 업로드
  // ─────────────────────────────────────────────────────────────
  static Future<String> uploadImage({
    required String postId,
    required String brandKor,
    required int index,
    required XFile file,
  }) async {
    final sw = Stopwatch()..start();

    final Uint8List bytes = await file.readAsBytes();
    final ext = _extFromName(file.name);
    final String folder = 'posts/$brandKor/$postId/images';
    final String fileName = 'main_${postId}_$index.$ext';

    final String url = await CloudinaryService.uploadImageBytes(
      data: bytes,
      fileName: fileName,
      folder: folder,
    );

    sw.stop();

    print(
      '[CLOUDINARY] main[$index] '
          '${sw.elapsedMilliseconds} ms, '
          '${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB',
    );

    return url;
  }

  // ─────────────────────────────────────────────────────────────
  // 2) 썸네일 업로드 (원본 그대로)
  // ─────────────────────────────────────────────────────────────
  static Future<String> uploadImageThumb({
    required String postId,
    required String brandKor,
    required int index,
    required XFile file,
  }) async {
    final sw = Stopwatch()..start();

    final Uint8List bytes = await file.readAsBytes();
    final ext = _extFromName(file.name);
    final String folder = 'posts/$brandKor/$postId/thumbs';
    final String fileName = 'thumb_${postId}_$index.$ext';

    final String url = await CloudinaryService.uploadImageBytes(
      data: bytes,
      fileName: fileName,
      folder: folder,
    );

    sw.stop();

    print(
      '[CLOUDINARY] thumb[$index] '
          '${sw.elapsedMilliseconds} ms, '
          '${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB',
    );

    return url;
  }

  // ─────────────────────────────────────────────────────────────
  // 3) 360° 이미지 업로드
  // ─────────────────────────────────────────────────────────────
  static Future<String> uploadSpinImage({
    required String postId,
    required String brandKor,
    required int index,
    required XFile file,
  }) async {
    final sw = Stopwatch()..start();

    final Uint8List bytes = await file.readAsBytes();
    final ext = _extFromName(file.name);
    final String folder = 'posts/$brandKor/$postId/spin';
    final String fileName = 'spin_${postId}_$index.$ext';

    final String url = await CloudinaryService.uploadImageBytes(
      data: bytes,
      fileName: fileName,
      folder: folder,
    );

    sw.stop();

    print(
      '[CLOUDINARY] spin[$index] '
          '${sw.elapsedMilliseconds} ms, '
          '${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB',
    );

    return url;
  }

  // ─────────────────────────────────────────────────────────────
  // 4) 동영상 업로드 (🔥 압축 → Cloudinary video 업로드)
  // ─────────────────────────────────────────────────────────────
  static Future<String> uploadVideo({
    required String postId,
    required String brandKor,
    required int index,
    required XFile file,
  }) async {
    final sw = Stopwatch()..start();

    Uint8List bytes;

    if (kIsWeb) {
      // 웹은 video_compress 동작 안함 → 원본 업로드
      bytes = await file.readAsBytes();
    } else {
      // 모바일(Android/iOS): 720p 압축 후 업로드
      final compressed = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality, // 필요하면 LowQuality 추천
        deleteOrigin: false,
      );

      if (compressed?.file != null) {
        bytes = await compressed!.file!.readAsBytes();
      } else {
        bytes = await file.readAsBytes();
      }
    }

    // Cloudinary video folder
    final String folder = 'posts/$brandKor/$postId/videos';
    final String fileName = 'video_${postId}_$index.mp4';

    final String url = await CloudinaryService.uploadVideoBytes(
      data: bytes,
      fileName: fileName,
      folder: folder,
    );

    sw.stop();

    print(
      '[CLOUDINARY] video[$index] ${sw.elapsedMilliseconds} ms, '
          '${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB (compressed)',
    );

    return url;
  }
}
