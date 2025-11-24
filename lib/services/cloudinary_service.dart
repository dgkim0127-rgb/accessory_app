// lib/services/cloudinary_service.dart
// ------------------------------------------------------------
// Cloudinary 업로드 서비스 (이미지 + 동영상 지원)
//
// - uploadImageBytes()  : resource_type = "image"
// - uploadVideoBytes()  : resource_type = "video"
//
// - Cloudinary unsigned upload 방식 사용
// ------------------------------------------------------------

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CloudinaryService {
  // ⚡ 너가 설정한 클라우드명 + 업로드 preset
  static const String _cloudName = 'dh1hsucpl';
  static const String _uploadPreset = 'accessory_app_upload';

  // 업로드 URL 생성기
  static Uri _imageUploadUri() =>
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

  static Uri _videoUploadUri() =>
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/video/upload');

  // ─────────────────────────────────────────────────────────────
  // 1) 이미지 업로드 (resource_type = "image")
  // ─────────────────────────────────────────────────────────────
  static Future<String> uploadImageBytes({
    required Uint8List data,
    required String fileName,
    String? folder,
  }) async {
    final request = http.MultipartRequest('POST', _imageUploadUri())
      ..fields['upload_preset'] = _uploadPreset;

    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        data,
        filename: fileName,
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = (json['secure_url'] ?? json['url'])?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('Cloudinary 응답에 URL이 없습니다: $body');
      }
      return url;
    } else {
      throw Exception(
        'Cloudinary 이미지 업로드 실패 (${response.statusCode}): $body',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2) 동영상 업로드 (resource_type = "video")
  // ─────────────────────────────────────────────────────────────
  static Future<String> uploadVideoBytes({
    required Uint8List data,
    required String fileName,
    String? folder,
  }) async {
    final request = http.MultipartRequest('POST', _videoUploadUri())
      ..fields['upload_preset'] = _uploadPreset;

    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        data,
        filename: fileName,
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final url = (json['secure_url'] ?? json['url'])?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('Cloudinary 응답에 URL이 없습니다: $body');
      }
      return url;
    } else {
      throw Exception(
        'Cloudinary 동영상 업로드 실패 (${response.statusCode}): $body',
      );
    }
  }
}
