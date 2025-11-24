// lib/core/loading.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LoadingController {
  final _progressCtrl = StreamController<double>.broadcast();
  final _labelCtrl = StreamController<String>.broadcast();
  final _thumbCtrl = StreamController<_Thumb>.broadcast();

  Stream<double> get progressStream => _progressCtrl.stream;
  Stream<String> get labelStream => _labelCtrl.stream;
  Stream<_Thumb> get thumbStream => _thumbCtrl.stream;

  void setProgress(double v) => _progressCtrl.add(v.clamp(0, 1));
  void stepPercent(double v, {String? label}) {
    setProgress(v);
    if (label != null) setLabel(label);
  }

  void setLabel(String text) => _labelCtrl.add(text);
  void setThumb({String? imageUrl, String? text}) {
    _thumbCtrl.add(_Thumb(imageUrl: imageUrl, text: text));
  }

  Future<void> dispose() async {
    await _progressCtrl.close();
    await _labelCtrl.close();
    await _thumbCtrl.close();
  }
}

class LoadingOverlay {
  static OverlayEntry? _entry;
  static LoadingController? _controller;

  /// ✅ 중복 떠있을 수 있는 모든 HUD를 강제 닫기
  static void hideAny() {
    if (_entry != null) {
      try {
        _entry!.remove();
      } catch (_) {}
      _entry = null;
    }
    try {
      _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

  /// HUD 띄우기
  static LoadingController show(
      BuildContext context, {
        String? label,
        String? thumbUrl,
        String? thumbText,
      }) {
    // 이미 떠있으면 먼저 정리(겹침 방지)
    hideAny();

    final controller = LoadingController();
    if (label != null) controller.setLabel(label);
    if (thumbUrl != null || thumbText != null) {
      controller.setThumb(imageUrl: thumbUrl, text: thumbText);
    }

    final entry =
    OverlayEntry(builder: (_) => _LoadingHUD(controller: controller));
    Overlay.of(context, rootOverlay: true).insert(entry);

    _entry = entry;
    _controller = controller;
    return controller;
  }

  /// HUD 닫기
  static Future<void> hide(BuildContext context, LoadingController c) async {
    if (_entry != null) {
      try {
        _entry!.remove();
      } catch (_) {}
      _entry = null;
    }
    await c.dispose();
    if (identical(_controller, c)) {
      _controller = null;
    }
  }

  /// (선택) 로딩 프리뷰 전달용
  static _PreviewData? _preview;
  static void setPreview(List<String> urls, {String? caption}) {
    _preview = _PreviewData(urls, caption: caption);
  }

  static _PreviewData? consumePreview() {
    final p = _preview;
    _preview = null;
    return p;
  }
}

class _PreviewData {
  final List<String> urls;
  final String? caption;
  _PreviewData(this.urls, {this.caption});
}

class _Thumb {
  final String? imageUrl;
  final String? text;
  const _Thumb({this.imageUrl, this.text});
}

class _LoadingHUD extends StatefulWidget {
  final LoadingController controller;
  const _LoadingHUD({required this.controller});
  @override
  State<_LoadingHUD> createState() => _LoadingHUDState();
}

class _LoadingHUDState extends State<_LoadingHUD> {
  static const double _kAutoHideThreshold = 0.40; // 40% 이상이면 자동 숨김

  final PageController _page = PageController();
  Timer? _slideTimer;
  Timer? _progressTimer;

  List<_Thumb> _slides = const [];
  _Thumb? _externalThumb;
  String _label = '처리 중…';

  // 🔢 목표(progressStream에서 온 값)와 실제로 화면에 보여주는 값 분리
  double _targetProgress = 0.0;
  double _displayProgress = 0.0; // 0.0 ~ 1.0

  @override
  void initState() {
    super.initState();
    widget.controller.progressStream.listen((v) {
      if (!mounted) return;
      setState(() {
        _targetProgress = v.clamp(0.0, 1.0);
      });
      _startProgressAnimation();
    });
    widget.controller.labelStream.listen((s) {
      if (!mounted) return;
      setState(() => _label = s);
    });
    widget.controller.thumbStream.listen((t) {
      if (!mounted) return;
      setState(() => _externalThumb = t);
    });

    _loadRandomSlides();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _progressTimer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _slideTimer?.cancel();
    _slideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _slides.isEmpty) return;
      final raw = _page.hasClients ? (_page.page ?? 0).round() : 0;
      final next = (raw + 1) % _slides.length;
      if (_page.hasClients) {
        _page.animateToPage(
          next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// 진행률을 1%씩 부드럽게 움직여주는 타이머
  void _startProgressAnimation() {
    _progressTimer ??=
        Timer.periodic(const Duration(milliseconds: 25), (timer) {
          if (!mounted) {
            timer.cancel();
            _progressTimer = null;
            return;
          }

          if (_displayProgress == _targetProgress) {
            // 목표에 도달했으면 100%일 때 자동 닫기(백업용)
            if (_displayProgress >= 0.999) {
              Future.microtask(() => LoadingOverlay.hideAny());
            }
            timer.cancel();
            _progressTimer = null;
            return;
          }

          setState(() {
            const step = 0.01; // 1%
            if (_displayProgress < _targetProgress) {
              _displayProgress =
                  (_displayProgress + step).clamp(0.0, _targetProgress);
            } else {
              _displayProgress =
                  (_displayProgress - step).clamp(_targetProgress, 1.0);
            }

            // 🔥 40% 이상 도달하면 HUD 자체를 숨겨서
            //     메인 화면이랑 안 겹치도록 처리
            if (_displayProgress >= _kAutoHideThreshold) {
              Future.microtask(() => LoadingOverlay.hideAny());
              timer.cancel();
              _progressTimer = null;
            }
          });
        });
  }

  Future<void> _loadRandomSlides() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get(const GetOptions(source: Source.serverAndCache));

      final rng = Random();
      final candidates = qs.docs.map((d) {
        final m = d.data();
        final url = (m['imageUrl'] ??
            ((m['images'] is List && m['images'].isNotEmpty)
                ? m['images'][0]
                : ''))
            .toString();
        final txt =
        (m['title'] ?? m['description'] ?? '').toString();
        return _Thumb(
          imageUrl: url.isEmpty ? null : url,
          text: txt,
        );
      }).where((t) => (t.imageUrl ?? '').isNotEmpty).toList();

      candidates.shuffle(rng);
      final pick = candidates.take(5).toList();

      // 홈에서 다시 쓸 수 있도록 프리뷰 저장
      LoadingOverlay.setPreview(
        pick.map((e) => e.imageUrl!).toList(),
        caption: pick.isNotEmpty ? pick.first.text : null,
      );

      if (!mounted) return;
      setState(() => _slides = pick);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    const ink = Color(0xff111111);
    final useExternal = _externalThumb?.imageUrl != null;

    final percent =
    (_displayProgress * 100).clamp(0, 100).toStringAsFixed(0);

    return Material(
      type: MaterialType.transparency,
      child: AbsorbPointer( // 🔒 HUD가 떠 있는 동안 아래 터치 완전 차단
        absorbing: true,
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -0.55),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRect(
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child: useExternal
                            ? _ThumbImage(url: _externalThumb!.imageUrl!)
                            : (_slides.isEmpty
                            ? const SizedBox()
                            : PageView.builder(
                          controller: _page,
                          itemCount: _slides.length,
                          itemBuilder: (_, i) =>
                              _ThumbImage(url: _slides[i].imageUrl!),
                        )),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (useExternal &&
                        (_externalThumb!.text ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _externalThumb!.text!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: line)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value:
                      _displayProgress <= 0 ? null : _displayProgress,
                      minHeight: 12,
                      backgroundColor: const Color(0xFFEDEDED),
                      color: ink,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbImage extends StatelessWidget {
  final String url;
  const _ThumbImage({required this.url});
  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
      const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
      loadingBuilder: (_, child, ev) {
        if (ev == null) return child;
        return const Center(
          child: CircularProgressIndicator(strokeWidth: 1.5),
        );
      },
    );
  }
}
