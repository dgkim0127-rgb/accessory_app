// lib/utils/page_safe.dart
import 'package:flutter/widgets.dart';

/// PageView가 attach되기 전 .page 접근으로 나는 assertion을 막아주는 안전 래퍼
extension SafePageController on PageController {
  /// attach 전에도 안전하게 현재 페이지(double)
  double get safePageDouble {
    if (hasClients && positions.isNotEmpty) {
      return page ?? initialPage.toDouble();
    }
    return initialPage.toDouble();
  }

  /// attach 전에도 안전하게 현재 페이지(int)
  int get safePageIndex => safePageDouble.round();

  /// attach 되었을 때만 animateToPage 수행
  Future<void> safeAnimateToPage(
      int page, {
        Duration duration = const Duration(milliseconds: 300),
        Curve curve = Curves.easeOutCubic,
      }) async {
    if (hasClients && positions.isNotEmpty) {
      await animateToPage(page, duration: duration, curve: curve);
    }
  }
}
