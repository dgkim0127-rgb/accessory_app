// lib/services/cloudinary_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Cloudinary 업로드 서비스 (이미지/비디오)
/// ✅ Unsigned Upload Preset 방식
/// - 클라이언트(Flutter/Web)에서 안전하게 업로드 가능
/// - API Key / API Secret 사용하지 않음
class CloudinaryService {
  CloudinaryService._();

  // ✅ 네 Cloudinary 정보로 고정 (스크린샷 기준)
  static const String cloudName = 'dh1hsucpl';
  static const String uploadPreset = 'accessory_app_upload';

  static Uri _imageUploadUri() =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  static Uri _videoUploadUri() =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/video/upload');

  /// 이미지 bytes 업로드 (unsigned)
  static Future<String> uploadImageBytes({
    required Uint8List data,
    required String fileName,
    required String folder,
  }) async {
    final req = http.MultipartRequest('POST', _imageUploadUri());
    req.fields['upload_preset'] = uploadPreset;
    req.fields['folder'] = folder;

    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        data,
        filename: fileName,
      ),
    );

    final res = await req.send();
    final body = await res.stream.bytesToString();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Cloudinary image upload failed: ${res.statusCode} $body');
    }

    final jsonMap = json.decode(body) as Map<String, dynamic>;
    final url = (jsonMap['secure_url'] ?? jsonMap['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('Cloudinary image upload: no url in response');
    return url;
  }

  /// 비디오 bytes 업로드 (unsigned)
  static Future<String> uploadVideoBytes({
    required Uint8List data,
    required String fileName,
    required String folder,
  }) async {
    final req = http.MultipartRequest('POST', _videoUploadUri());
    req.fields['upload_preset'] = uploadPreset;
    req.fields['folder'] = folder;

    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        data,
        filename: fileName,
      ),
    );

    final res = await req.send();
    final body = await res.stream.bytesToString();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Cloudinary video upload failed: ${res.statusCode} $body');
    }

    final jsonMap = json.decode(body) as Map<String, dynamic>;
    final url = (jsonMap['secure_url'] ?? jsonMap['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('Cloudinary video upload: no url in response');
    return url;
  }
}
