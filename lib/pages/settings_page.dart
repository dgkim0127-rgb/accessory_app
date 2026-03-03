// lib/pages/settings_page.dart ✅ 프리미엄 디자인 & 다크모드 대응 완료
import 'package:flutter/material.dart';
import '../core/app_settings_scope.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        title: Text(
          '설정',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1,
              color: theme.dividerTheme.color ?? Colors.transparent
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        children: [
          Text(
            '화면 설정',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // 🌟 프리미엄 카드 디자인 적용
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black45 : Colors.black.withOpacity(0.04),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ],
              border: Border.all(
                  color: theme.dividerTheme.color ?? Colors.transparent,
                  width: 0.5
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: settings,
              builder: (_, __) {
                final percent = (settings.textScale * 100).round();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.text_fields, size: 22, color: cs.onSurface.withOpacity(0.7)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '글자 크기 $percent%',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '기본 100% ~ 최대 140%',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(0.4),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 🌟 세련된 커스텀 슬라이더
                    SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: cs.onSurface,
                        inactiveTrackColor: cs.onSurface.withOpacity(0.1),
                        thumbColor: cs.onSurface,
                        overlayColor: cs.onSurface.withOpacity(0.1),
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                      ),
                      child: Slider(
                        value: settings.textScale,
                        min: 1.0,
                        max: 1.4,
                        divisions: 8,
                        onChanged: (v) => settings.setTextScale(v),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 🌟 직관적인 미리보기 영역
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2F38) : const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '미리보기',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '르네 주얼리의 다양한 컬렉션\n반지 / 목걸이 / 귀걸이 / 팔찌',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                              height: 1.5,
                              fontSize: 14 * settings.textScale, // 스케일에 따라 즉각적으로 크기가 변함
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}