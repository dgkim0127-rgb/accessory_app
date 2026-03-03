// lib/services/upload_service.dart
// ------------------------------------------------------------
// Cloudinary 업로드 서비스 (이미지 + 360° + 동영상)
//
// ✅ 최종 목표
// - 이미지/스핀: 원본 그대로 업로드 (화질 저하 X)
// - 동영상: 모바일에서만 720p 압축 후 업로드
// ------------------------------------------------------------

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
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
  // 1) 이미지 업로드 (원본 그대로)
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
    final folder = 'posts/$brandKor/$postId/images';
    final fileName = 'main_${postId}_$index.$ext';

    final url = await CloudinaryService.uploadImageBytes(
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
  // 2) 360° 이미지 업로드 (원본 그대로)
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
    final folder = 'posts/$brandKor/$postId/spin';
    final fileName = 'spin_${postId}_$index.$ext';

    final url = await CloudinaryService.uploadImageBytes(
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
  // 3) 동영상 업로드 (모바일만 압축)
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
      // 웹: video_compress 동작 안함 → 원본 업로드
      bytes = await file.readAsBytes();
    } else {
      // 모바일(Android/iOS): 720p 압축 후 업로드 (속도/용량 개선)
      final compressed = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (compressed?.file != null) {
        bytes = await compressed!.file!.readAsBytes();
      } else {
        bytes = await file.readAsBytes();
      }
    }

    final folder = 'posts/$brandKor/$postId/videos';
    final fileName = 'video_${postId}_$index.mp4';

    final url = await CloudinaryService.uploadVideoBytes(
      data: bytes,
      fileName: fileName,
      folder: folder,
    );

    sw.stop();
    print(
      '[CLOUDINARY] video[$index] '
          '${sw.elapsedMilliseconds} ms, '
          '${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB',
    );
    return url;
  }
}
