// lib/utils/cloudinary_image_utils.dart ✅ 최종
//
// ✅ 목적
// - Cloudinary URL이면 "/upload/" 뒤에 변환 파라미터를 삽입해서
//   "적당히 선명 + 느려지지 않게" 로딩 최적화
//
// ✅ 규칙(이번 최종 세팅)
// - thumb  : 480x480, q_auto:eco (그리드)
// - slider : 900x900, q_auto:good (홈 상단 슬라이더)
// - medium : 1600px, q_auto:good (상세 화면용)  ← 원본까지는 안 가고 “적당히 선명”
// - original: 변환 없이 원본(필요할 때만)
//
// ⚠️ 이미 변환이 붙어 있는 URL(f_auto/q_auto/w_/h_/c_)이면 그대로 둠

String _applyCloudinaryTransform(String url, String transform) {
  if (url.isEmpty) return url;

  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return url;

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  // 이미 변환이 붙어있으면 그대로 (중복 변환 방지)
  if (after.startsWith('f_auto') ||
      after.startsWith('q_auto') ||
      after.startsWith('w_') ||
      after.startsWith('h_') ||
      after.startsWith('c_')) {
    return url;
  }

  return '$before$transform$after';
}

/// ✅ 홈 그리드/리스트: 480 정사각 + eco (빠름)
String buildThumbUrl(String url) {
  return _applyCloudinaryTransform(
    url,
    'f_auto,q_auto:eco,w_480,h_480,c_fill,g_auto/',
  );
}

/// ✅ 홈 상단 슬라이더: 900 정사각 + good (선명)
String buildSliderUrl(String url) {
  return _applyCloudinaryTransform(
    url,
    'f_auto,q_auto:good,w_900,h_900,c_fill,g_auto/',
  );
}

/// ✅ 상세 화면: 1600px 제한 + good (원본급 느낌인데 너무 무겁진 않게)
/// - 세로/가로 긴 사진도 비율 유지하려고 h 지정 안 함
String buildMediumUrl(String url) {
  return _applyCloudinaryTransform(
    url,
    'f_auto,q_auto:good,w_1600,c_limit/',
  );
}

/// ✅ 정말 원본이 필요할 때만 사용(기본은 쓰지 말기)
String buildOriginalUrl(String url) => url;
