// lib/splash/splash_screen.dart
import 'package:flutter/material.dart';

/// 이미지 없이 'Accessory' 텍스트만 보여주는 커스텀 스플래시.
/// - 흰 배경 + 굵은 텍스트
/// - 살짝 페이드/스케일 인 애니메이션
/// - 하단에 가느다란 로딩 인디케이터
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
    ..forward();
  late final Animation<double> _fade =
  CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic);
  late final Animation<double> _scale =
  Tween(begin: 0.98, end: 1.0).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      fontSize: 100,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
      color: Colors.black,
    );

    const subStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.0,
      color: Colors.black54,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('K', style: titleStyle),
                  SizedBox(height: 6),
                  Text('JEWELRY & ACCESSORIES', style: subStyle),
                  SizedBox(height: 18),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
