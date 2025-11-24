// lib/splash/splash_screen.dart
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // 🔥 더 빠르게: 1.4초에 한 번씩 좌→우로 흐름
  late final AnimationController _controller =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      fontSize: 100,
      fontWeight: FontWeight.w800,
      color: Colors.black,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('K', style: titleStyle),
            const SizedBox(height: 12),
            _FlowTextWithUnderline(
              text: 'CATALOG',
              controller: _controller,
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────
// 텍스트 + 밑줄 묶음
// ──────────────────────────────
class _FlowTextWithUnderline extends StatelessWidget {
  final String text;
  final AnimationController controller;

  const _FlowTextWithUnderline({
    required this.text,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final letters = text.split('');

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < letters.length; i++)
              _FlowLetter(
                char: letters[i],
                index: i,
                total: letters.length,
                controller: controller,
              )
          ],
        ),
        const SizedBox(height: 8),
        _FlowUnderline(
          length: letters.length,
          controller: controller,
        ),
      ],
    );
  }
}

// ──────────────────────────────
// 글자 하나 애니메이션 (좌→우 흐름 + 부드러운 그라데이션)
// ──────────────────────────────
class _FlowLetter extends StatelessWidget {
  final String char;
  final int index;
  final int total;
  final AnimationController controller;

  const _FlowLetter({
    required this.char,
    required this.index,
    required this.total,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // head: 0 → total+1 로 이동하는 "하이라이트 위치"
        final head = controller.value * (total + 1);
        final dist = head - index.toDouble(); // 이 글자와 하이라이트 사이 거리

        // 🔥 falloff 폭 (값을 키우면 하이라이트가 더 넓게 퍼짐)
        const double range = 1.4;

        // -range ~ 0 ~ +range 에서 부드럽게 밝아졌다 어두워지는 형태
        double k = 1.0 - (dist.abs() / range);
        if (k < 0) k = 0;
        if (k > 1) k = 1;

        // k: 0(기본) → 1(하이라이트)
        final opacity = 0.3 + 0.7 * k;
        final scale = 0.94 + 0.10 * k;
        final color = Color.lerp(
          Colors.grey.shade400,
          Colors.black,
          k,
        )!;

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                char,
                style: TextStyle(
                  fontSize: 15,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────
// 밑줄도 같은 헤드 기준으로 좌→우 흐름
// ──────────────────────────────
class _FlowUnderline extends StatelessWidget {
  final int length;
  final AnimationController controller;

  const _FlowUnderline({
    required this.length,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: length * 14.0,
      height: 4,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final t = controller.value;
          final underlineWidth = length * 14.0;

          // 글자 하이라이트 head와 맞춰서 왼→오른쪽으로 이동
          final activeX = t * underlineWidth;

          return CustomPaint(
            painter: _UnderlinePainter(activeX),
          );
        },
      ),
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  final double activeX;
  _UnderlinePainter(this.activeX);

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2;

    final activePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.6;

    // 기본 밑줄
    canvas.drawLine(
      Offset(0, 0),
      Offset(size.width, 0),
      basePaint,
    );

    // 🔥 하이라이트 구간: head 주변만 살짝 더 진하게
    const waveWidth = 26.0;
    double start = activeX - waveWidth / 2;
    double end = activeX + waveWidth / 2;

    if (start < 0) start = 0;
    if (end > size.width) end = size.width;

    canvas.drawLine(
      Offset(start, 0),
      Offset(end, 0),
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _UnderlinePainter oldDelegate) =>
      oldDelegate.activeX != activeX;
}
