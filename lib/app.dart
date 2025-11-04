import 'package:flutter/material.dart';

/// E-ink(블랙&화이트, 각진) 전역 테마
ThemeData buildEInkTheme() {
  const borderGrey = Color(0xFFE6E6E6);

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
  );

  return base.copyWith(
    colorScheme: const ColorScheme.light(
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.black,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.white,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.w400,
        fontSize: 18,
        letterSpacing: 0.2,
      ),
    ),
    // 버튼: 전부 각진
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        side: const BorderSide(color: borderGrey),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    // 로그인 입력 같은 밑줄 필드 스타일(필요 화면에서만 사용 가능)
    inputDecorationTheme: const InputDecorationTheme(
      border: UnderlineInputBorder(borderSide: BorderSide(color: borderGrey)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderGrey)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black)),
      hintStyle: TextStyle(color: Colors.black54),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      indicatorColor: Colors.transparent, // 선택 인디케이터 없애기
      height: 64,
      // ✅ 아이콘: 기본은 회색, 선택 시 검정
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? Colors.black : Colors.black54,
          size: 24,
        );
      }),
      // 라벨은 숨기지만 혹시 대비 대비용
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(color: Colors.black54, fontSize: 0),
      ),
    ),
    dividerColor: borderGrey,
  );
}
