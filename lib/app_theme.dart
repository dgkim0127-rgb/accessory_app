// lib/app_theme.dart
import 'package:flutter/material.dart';

// 🌟 1. 앱 전체에 적용될 '가운데서 통통 튀며 창이 뜨는' 애니메이션 정의
class PopUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const PopUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    // 1️⃣ 새 창이 뜰 때: 중앙에서 0.9배 크기로 시작해서 원래 크기(1.0)로 쫀득하게 커짐
    final scale = animation.drive(
      Tween<double>(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)),
    );

    // 2️⃣ 새 창이 뜰 때: 서서히 선명해짐 (투명도 0.0 -> 1.0)
    final opacity = animation.drive(
      Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)),
    );

    // 3️⃣ 내 위에 다른 창이 뜰 때: 현재 창이 뒤로 살짝 물러나는 입체적인 느낌 (1.0 -> 0.96)
    final secondaryScale = secondaryAnimation.drive(
      Tween<double>(begin: 1.0, end: 0.96).chain(CurveTween(curve: Curves.easeOutCubic)),
    );

    return ScaleTransition(
      scale: secondaryScale, // 내 위에 누가 뜰 때 뒤로 물러남
      child: FadeTransition(
        opacity: opacity,    // 팝업처럼 페이드 인
        child: ScaleTransition(
          scale: scale,      // 팝업처럼 쫀득하게 줌 인
          child: child,
        ),
      ),
    );
  }
}

// 🌟 2. 안드로이드, iOS 구분 없이 모두 '창이 뜨는 느낌'을 쓰도록 테마로 묶음
const _popUpTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: PopUpPageTransitionsBuilder(),
    TargetPlatform.iOS: PopUpPageTransitionsBuilder(),
    TargetPlatform.macOS: PopUpPageTransitionsBuilder(),
    TargetPlatform.windows: PopUpPageTransitionsBuilder(),
  },
);

// ─────────────── 라이트 모드 테마 ───────────────
ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.black,
      brightness: Brightness.light,
      surface: Colors.white,
      background: Colors.white,
      onSurface: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE6E6E6),
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(letterSpacing: -0.5, fontWeight: FontWeight.w800, color: Colors.black),
      bodyLarge: TextStyle(letterSpacing: 0.2, height: 1.5, color: Colors.black87),
      bodyMedium: TextStyle(letterSpacing: 0.1, color: Colors.black87),
    ),
    // ✅ 앱의 모든 페이지 이동에 팝업 애니메이션 장착!
    pageTransitionsTheme: _popUpTransitionsTheme,
  );
}

// ─────────────── 부드러운 다크 모드 테마 ───────────────
ThemeData buildSoftDarkTheme() {
  const bg = Color(0xFF121417);
  const surface = Color(0xFF1A1D22);
  const border = Color(0xFF2B2F36);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.white,
      brightness: Brightness.dark,
      background: bg,
      surface: surface,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: bg,
      indicatorColor: Color(0xFF2A2F38),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: surface,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(letterSpacing: -0.5, fontWeight: FontWeight.w800, color: Colors.white),
      bodyLarge: TextStyle(letterSpacing: 0.2, height: 1.5, color: Colors.white70),
      bodyMedium: TextStyle(letterSpacing: 0.1, color: Colors.white70),
    ),
    // ✅ 다크모드에도 팝업 애니메이션 장착!
    pageTransitionsTheme: _popUpTransitionsTheme,
  );
}