// lib/widgets/post_overlay.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:accessory_app/utils/page_safe.dart';
import '../pages/brand_profile_page.dart';
import '../pages/edit_post_page.dart';
import '../services/like_service.dart';

class PostOverlay extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final int initialIndex;

  const PostOverlay({
    super.key,
    required this.docs,
    required this.initialIndex,
  });

  static Future<void> show(
      BuildContext context, {
        required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        required int startIndex,
      }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            PostOverlay(docs: docs, initialIndex: startIndex),
        transitionsBuilder: (_, anim, __, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(anim);
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  @override
  State<PostOverlay> createState() => _PostOverlayState();
}

class _PostOverlayState extends State<PostOverlay> {
  bool _isAdmin = false;
  bool _isZooming = false;

  late final int _initial;
  late final List<QueryDocumentSnapshot<Map<String, dynamic>>> _list;

  final ItemScrollController _itemScrollCtrl = ItemScrollController();
  final ItemPositionsListener _posListener = ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    _initial = widget.initialIndex.clamp(0, widget.docs.length - 1);
    _list =
    List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(widget.docs);
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get();
      final role = (snap.data()?['role'] ?? 'user').toString().toLowerCase();
      if (mounted) setState(() => _isAdmin = role == 'admin' || role == 'super');
    } catch (_) {}
  }

  void _handleDeleted(String docId) {
    setState(() {
      _list.removeWhere((d) => d.id == docId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('게시물이 삭제되었습니다.')),
    );
    if (_list.isEmpty) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // 상단 바
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 22,
                  ),
                  const SizedBox(width: 4),
                  const Text('게시물',
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                ],
              ),
            ),
            // 본문
            Expanded(
              child: _list.isEmpty
                  ? const Center(child: Text('표시할 게시물이 없어요'))
                  : ScrollConfiguration(
                behavior: const _DragEverywhere(),
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollCtrl,
                  itemPositionsListener: _posListener,
                  initialScrollIndex: _initial,
                  initialAlignment: 0.08,
                  physics: _isZooming
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  itemCount: _list.length,
                  itemBuilder: (_, idx) {
                    final doc = _list[idx];
                    return _PostCard(
                      doc: doc,
                      isAdmin: _isAdmin,
                      onZoomingChanged: (z) {
                        if (mounted) setState(() => _isZooming = z);
                      },
                      onDeleted: _handleDeleted,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();
  @override
  Set<PointerDeviceKind> get dragDevices =>
      {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
}

/// 개별 게시물 카드
class _PostCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAdmin;
  final ValueChanged<bool> onZoomingChanged;
  final ValueChanged<String> onDeleted;

  const _PostCard({
    super.key,
    required this.doc,
    required this.isAdmin,
    required this.onZoomingChanged,
    required this.onDeleted,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  late Map<String, dynamic> data;
  late List<String> images;

  bool _liked = false;
  StreamSubscription? _likeSub;

  @override
  void initState() {
    super.initState();
    data = Map<String, dynamic>.from(widget.doc.data());

    final v = data['images'];
    if (v is List && v.isNotEmpty) {
      images = v.map((e) => e.toString()).toList();
    } else {
      final one = (data['imageUrl'] ?? '').toString();
      images = one.isEmpty ? const [] : [one];
    }

    // 좋아요 실시간 반영 (현재 로그인 사용자가 좋아요 했는지)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _likeSub = LikeService.instance
          .watchLiked(widget.doc.id)
          .listen((v) => mounted ? setState(() => _liked = v) : null);
    }
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  Future<void> _onEdit() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditPostPage(postId: widget.doc.id, initialData: data),
      ),
    );

    if (updated == true) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.doc.id)
            .get();
        if (snap.exists) {
          setState(() {
            data = Map<String, dynamic>.from(snap.data()!);
            final v = data['images'];
            if (v is List && v.isNotEmpty) {
              images = v.map((e) => e.toString()).toList();
            } else {
              final one = (data['imageUrl'] ?? '').toString();
              images = one.isEmpty ? const [] : [one];
            }
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _onDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제할까요?'),
        content: const Text('이 게시물은 삭제 후 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.doc.id)
          .delete();
      if (!mounted) return;
      widget.onDeleted(widget.doc.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  Widget _titleAndHeart(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title.isNotEmpty ? title : '제목 없음',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            splashRadius: 22,
            onPressed: () async {
              final u = FirebaseAuth.instance.currentUser;
              if (u == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('로그인이 필요합니다.')),
                );
                return;
              }
              final prev = _liked;
              setState(() => _liked = !prev); // 낙관적 UI
              try {
                await LikeService.instance.toggle(widget.doc.id);
              } catch (e) {
                if (!mounted) return;
                setState(() => _liked = prev); // 실패 롤백
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('좋아요 처리 실패: $e')),
                );
              }
            },
            icon: Icon(
              _liked ? Icons.favorite : Icons.favorite_border,
              color: _liked ? Colors.redAccent : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color line = Color(0xFFE6E6E6);

    final title = (data['title'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();
    final createdAt = data['createdAt'];

    final brandKor = (data['brand'] ?? '').toString();
    final brandEng = (data['brandEng'] ?? '').toString();
    final logoUrl = (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BrandHeader(
          brandKor: brandKor,
          brandEng: brandEng,
          logoUrl: logoUrl,
          createdAt: createdAt,
          isAdmin: widget.isAdmin,
          onEdit: widget.isAdmin ? _onEdit : null,
          onDelete: widget.isAdmin ? _onDelete : null,
        ),
        _MultiImageZoomCarousel(
          urls: images,
          onAnyZoomingChanged: widget.onZoomingChanged,
        ),
        _titleAndHeart(title),
        if (desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
            child: Text(desc, style: const TextStyle(fontSize: 14, height: 1.35)),
          )
        else
          const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0x11000000)),
      ],
    );
  }
}

/// 여러 장 이미지 + 각 장 원본 비율 컨테이너 + 확대 시 부모 스크롤 잠금
class _MultiImageZoomCarousel extends StatefulWidget {
  final List<String> urls;
  final ValueChanged<bool> onAnyZoomingChanged;

  const _MultiImageZoomCarousel({
    required this.urls,
    required this.onAnyZoomingChanged,
  });

  @override
  State<_MultiImageZoomCarousel> createState() =>
      _MultiImageZoomCarouselState();
}

class _MultiImageZoomCarouselState extends State<_MultiImageZoomCarousel> {
  final PageController _pager = PageController();
  int _index = 0;
  bool _pageZooming = false;

  final Map<int, double> _ratios = {};
  double get _currentRatio {
    final r = _ratios[_index];
    if (r == null || r.isNaN || r.isInfinite) return 4 / 5;
    return r.clamp(0.25, 4.0);
  }

  @override
  void initState() {
    super.initState();
    _resolveAll();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _resolveAll() {
    for (int i = 0; i < widget.urls.length; i++) {
      final url = widget.urls[i];
      if (url.isEmpty) continue;
      final img = Image.network(url);
      final stream = img.image.resolve(const ImageConfiguration());
      late final ImageStreamListener sub;
      sub = ImageStreamListener((info, _) {
        final raw = (info.image.width / info.image.height).toDouble();
        final safe = (raw.isNaN || raw.isInfinite) ? (4 / 5) : raw;
        if (mounted) setState(() => _ratios[i] = safe.clamp(0.25, 4.0));
        stream.removeListener(sub);
      }, onError: (_, __) {
        if (mounted) setState(() => _ratios[i] = 4 / 5);
        stream.removeListener(sub);
      });
      stream.addListener(sub);
    }
  }

  void _handleZoomChanged(bool z) {
    if (_pageZooming == z) return;
    setState(() => _pageZooming = z);
    widget.onAnyZoomingChanged(z);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = width / _currentRatio;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          child: PageView.builder(
            controller: _pager,
            physics: _pageZooming
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: widget.urls.length,
            itemBuilder: (_, i) => _TwoFingerZoomImage(
              url: widget.urls[i],
              onZoomingChanged: _handleZoomChanged,
            ),
          ),
        ),
        if (widget.urls.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Dots(controller: _pager, count: widget.urls.length),
          ),
      ],
    );
  }
}

/// 두 손가락 확대/이동 + 손 떼면 자연 복귀
class _TwoFingerZoomImage extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomingChanged;

  const _TwoFingerZoomImage({
    required this.url,
    required this.onZoomingChanged,
  });

  @override
  State<_TwoFingerZoomImage> createState() => _TwoFingerZoomImageState();
}

class _TwoFingerZoomImageState extends State<_TwoFingerZoomImage>
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
    _anim =
    AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
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
              panEnabled: _pointers >= 2 || _tc.value.getMaxScaleOnAxis() > 1.0,
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
                child: url.isNotEmpty
                    ? Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image, size: 40)),
                  loadingBuilder: (_, child, ev) =>
                  ev == null ? child : const Center(child: CircularProgressIndicator()),
                )
                    : const Center(child: Icon(Icons.broken_image, size: 40)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final PageController controller;
  final int count;
  const _Dots({required this.controller, required this.count});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final page = controller.safePageDouble;
        return Wrap(
          spacing: 6,
          children: List.generate(count, (i) {
            final active = (i - page).abs() < 0.5;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: active ? 7 : 5.5,
              height: active ? 7 : 5.5,
              decoration: BoxDecoration(
                color: active ? Colors.black : const Color.fromRGBO(0, 0, 0, 0.25),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// 브랜드 헤더 (아이콘 + 이름 + 날짜 + ⋮)
/// 브랜드 헤더 (아이콘 + 이름 + 날짜 + ⋮: 수정/삭제)
class _BrandHeader extends StatelessWidget {
  final String brandKor;
  final String brandEng;
  final String logoUrl;
  final dynamic createdAt;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _BrandHeader({
    required this.brandKor,
    required this.brandEng,
    required this.logoUrl,
    required this.createdAt,
    required this.isAdmin,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE6E6E6);
    final dateStr = (createdAt is Timestamp) ? _humanize((createdAt as Timestamp).toDate()) : '';
    final displayKor = brandKor.isEmpty ? 'ALL' : brandKor;

    Future<void> _openBrandProfile(BuildContext ctx) async {
      // 게시물에서 들어올 때 영문/로고가 비어 있으면 brands 컬렉션에서 보강
      String nameEng = brandEng;
      String logo = logoUrl;

      if (nameEng.isEmpty || logo.isEmpty) {
        try {
          final qs = await FirebaseFirestore.instance
              .collection('brands')
              .where('nameKor', isEqualTo: displayKor)
              .limit(1)
              .get(const GetOptions(source: Source.serverAndCache));
          if (qs.docs.isNotEmpty) {
            final m = qs.docs.first.data();
            nameEng = (m['nameEng'] ?? nameEng).toString();
            logo    = (m['logoUrl'] ?? logo).toString();
          }
        } catch (_) {
          // 조회 실패해도 기존 값으로 진행
        }
      }

      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => BrandProfilePage(
            brandKor: displayKor,
            brandEng: nameEng,   // ← 항상 채워서 전달
            isAdmin: isAdmin,
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => _openBrandProfile(context),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0x11000000),
                  backgroundImage: (logoUrl.isNotEmpty) ? NetworkImage(logoUrl) : null,
                  child: (logoUrl.isEmpty)
                      ? const Icon(Icons.store, color: Colors.black54)
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayKor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onSelected: (v) {
              if (v == 'edit' && isAdmin && onEdit != null) onEdit!();
              if (v == 'delete' && isAdmin && onDelete != null) onDelete!();
            },
            itemBuilder: (context) => [
              if (isAdmin) const PopupMenuItem(value: 'edit', child: Text('수정')),
              if (isAdmin) const PopupMenuItem(value: 'delete', child: Text('삭제', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
    );
  }

  static String _humanize(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    String _2(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}.${_2(dt.month)}.${_2(dt.day)}';
  }
}
