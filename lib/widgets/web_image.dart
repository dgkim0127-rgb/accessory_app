// lib/widgets/web_image.dart
// 웹용 가벼운 이미지 위젯 (사실 앱에서도 그대로 써도 됨)

import 'package:flutter/material.dart';

class WebImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  const WebImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,         // 프레임 전환 시 덜 깜빡이게
      filterQuality: FilterQuality.low, // 디코딩 부담 줄이기
    );
  }
}
