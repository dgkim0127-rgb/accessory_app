// lib/widgets/post_media_carousel.dart  ✅ 최종
//
// 기능:
// - 이미지 / 360° 이미지를 한 캐러셀에서 보여줌
// - CachedNetworkImage + Cloudinary 최적화로 빠른 로딩 + 캐시
// - 두 손가락(또는 휠+드래그) 줌 유지 (InteractiveViewer)
// - 확대 중에는 좌우 슬라이드 잠금 → 상위 스크롤과 충돌 방지
// - 우측 상단 "현재 / 전체" 표시 + 하단 점(dot) 인디케이터

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

enum MediaKind { image, spin360 }

class MediaItem {
  final MediaKind kind;
  final String url;

  const MediaItem({
    required this.kind,
    required this.url,
  });
}

/// 게시물 안에서 사용하는 미디어 캐러셀
class PostMediaCarousel extends StatefulWidget {
  final String postId;
  final List<MediaItem> items;
  final int initialIndex;

  /// 확대/축소 상태를 바깥(예: PostOverlay)으로 알려주기 위한 콜백
  final ValueChanged<bool>? onZoomChanged;

  const PostMediaCarousel({
    super.key,
    required this.postId,
    required this.items,
    this.initialIndex = 0,
    this.onZoomChanged,
  });

  @override
  State<PostMediaCarousel> createState() => _PostMediaCarouselState();
}

class _PostMediaCarouselState extends State<PostMediaCarousel>
    with AutomaticKeepAliveClientMixin {
  late final PageController _pageController;
  int _currentIndex = 0;
  bool _zooming = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    // 360° 이미지 미리 캐시 (로딩 체감 속도 ↑)
    for (final item in widget.items) {
      if (item.kind == MediaKind.spin360) {
        precacheImage(CachedNetworkImageProvider(item.url), context);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setZooming(bool z) {
    if (_zooming == z) return;
    setState(() => _zooming = z);
    widget.onZoomChanged?.call(z);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                physics: _zooming
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final isSpin = item.kind == MediaKind.spin360;
                  return _ZoomableCachedImage(
                    url: item.url,
                    isSpin: isSpin,
                    onZoomingChanged: _setZooming,
                  );
                },
              ),
              if (widget.items.length > 1)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.items.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Dots(
              count: widget.items.length,
              currentIndex: _currentIndex,
            ),
          ),
      ],
    );
  }
}

/// 두 손가락 확대/이동 + 손 떼면 자연 복귀 + CachedNetworkImage 사용
class _ZoomableCachedImage extends StatefulWidget {
  final String url;
  final bool isSpin;
  final ValueChanged<bool> onZoomingChanged;

  const _ZoomableCachedImage({
    required this.url,
    required this.isSpin,
    required this.onZoomingChanged,
  });

  @override
  State<_ZoomableCachedImage> createState() => _ZoomableCachedImageState();
}

class _ZoomableCachedImageState extends State<_ZoomableCachedImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _resetTween;

  bool _zooming = false;
  static const double _zoomThreshold = 1.005;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )
      ..addListener(() {
        if (_resetTween != null) _tc.value = _resetTween!.value;
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _setZooming(false);
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _setZooming(bool z) {
    if (_zooming == z) return;
    setState(() => _zooming = z);
    widget.onZoomingChanged(z);
  }

  void _animateBack() {
    _anim.stop();
    _resetTween = Matrix4Tween(
      begin: _tc.value,
      end: Matrix4.identity(),
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_anim);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    final optimizedUrl = _optimizeCloudinaryDetailUrl(url);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        final was = _pointers;
        _pointers++;
        if (was < 2 && _pointers >= 2) _setZooming(true);
      },
      onPointerUp: (_) {
        _pointers = (_pointers - 1).clamp(0, 10);
        if (_pointers <= 0) _animateBack();
      },
      onPointerCancel: (_) {
        _pointers = (_pointers - 1).clamp(0, 10);
        if (_pointers <= 0) _animateBack();
      },
      child: LayoutBuilder(
        builder: (_, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return ClipRect(
            child: InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(99999),
              minScale: 1.0,
              maxScale: 4.0,
              panEnabled:
              _pointers >= 2 || _tc.value.getMaxScaleOnAxis() > 1.0,
              scaleEnabled: _pointers >= 2,
              clipBehavior: Clip.hardEdge,
              onInteractionStart: (_) => _setZooming(true),
              onInteractionUpdate: (_) {
                final s = _tc.value.getMaxScaleOnAxis();
                _setZooming(s > _zoomThreshold || _pointers >= 2);
              },
              onInteractionEnd: (_) {
                if (_pointers == 0) _animateBack();
              },
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: optimizedUrl,
                      fit: BoxFit.contain,
                      memCacheWidth: 1200,
                      placeholder: (context, _) => const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, size: 40),
                      ),
                    ),
                    if (widget.isSpin)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.threesixty,
                                  size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                '360°',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int currentIndex;
  const _Dots({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 7 : 5.5,
          height: active ? 7 : 5.5,
          decoration: BoxDecoration(
            color: active
                ? Colors.black
                : const Color.fromRGBO(0, 0, 0, 0.25),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

// 게시물 상세용 Cloudinary 최적화
// - f_auto,q_auto:eco,w_1080 → 고해상도 유지 + 용량 KB~수백KB
String _optimizeCloudinaryDetailUrl(String url) {
  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return url;

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  if (after.startsWith('f_auto') || after.startsWith('q_auto')) {
    return url;
  }

  return '$before'
      'f_auto,q_auto:eco,w_1080/'
      '$after';
}
