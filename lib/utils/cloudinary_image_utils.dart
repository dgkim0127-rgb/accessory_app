// lib/utils/cloudinary_image_utils.dart
//
// Cloudinary URL 에서 썸네일 / 미디엄 사이즈 변환을 만들기 위한 헬퍼.
// URL 안에 "/upload/" 구간을 찾아서 그 뒤에 변환 파라미터를 삽입하는 방식.
// (Cloudinary가 아니라면 원본 URL 그대로 리턴됨)

String _applyCloudinaryTransform(String url, String transform) {
  if (url.isEmpty) return url;

  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) {
    // Cloudinary 형식이 아니면 그대로 사용
    return url;
  }

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  // 이미 변환 파라미터가 붙어 있으면 그대로 둔다
  if (after.startsWith('f_auto') ||
      after.startsWith('q_auto') ||
      after.startsWith('w_') ||
      after.startsWith('h_')) {
    return url;
  }

  return '$before$transform$after';
}

/// 홈 피드/그리드용 작은 썸네일
String buildThumbUrl(String url) {
  return _applyCloudinaryTransform(
    url,
    // 정사각형 400 x 400, 자동 포맷, 저품질
    'w_400,h_400,c_fill,f_auto,q_auto:low/',
  );
}

/// 상세 화면용 중간 사이즈 (예: 1280px)
String buildMediumUrl(String url) {
  return _applyCloudinaryTransform(
    url,
    'w_1280,f_auto,q_auto/',
  );
}
