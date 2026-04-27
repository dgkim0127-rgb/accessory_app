// lib/widgets/post_overlay.dart ✅ 최종
// - 디자인은 기존 코드 유지
// - 모바일 게시물 넘김은 세로 한 장씩
// - 게시물 안에서 바로 핀치 줌
// - 더블탭 없음
// - 두 손가락 닿는 순간 바로 줌 가능
// - 손을 떼면 원본으로 자동 복귀
// - 확대 시 게시물 틀 밖으로도 보이게 처리
// - 줌 중에는 부모/자식 PageView 스크롤 충돌 방지
// - 빈 공간(허공)에서도 두 손가락 줌 가능
// - PhotoView 제거
// - InteractiveViewer 제거
// - ✅ 손가락 기준 위치에서 확대
// - ✅ 우측 하단으로 쏠리는 현상 보정
// - ✅ 게시물 틀 밖으로 자연스럽게 확대 (PostCard 최상단 오버레이 레이어)
// - ✅ 확대 시작 시 사진이 살짝 아래로 내려가는 현상 보정

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../pages/brand_profile_page.dart';
import '../pages/edit_post_page.dart';
import '../services/like_service.dart';
import 'web_image.dart';

bool _isVideoUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.mp4') ||
      lower.contains('.mov') ||
      lower.contains('.m4v') ||
      lower.contains('.webm');
}

String _optimizeCloudinaryUrl(String url) {
  if (url.isEmpty || !url.contains('/upload/')) return url;
  if (url.contains('f_auto') || url.contains('q_auto') || url.contains('w_')) {
    return url;
  }

  const marker = '/upload/';
  final idx = url.indexOf(marker);
  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  if (_isVideoUrl(url)) return '${before}f_auto,q_auto:good/$after';
  return '${before}f_auto,q_auto:good,w_1440/$after';
}

String _optimizeCloudinaryVideoUrl(String url) {
  if (url.isEmpty || !url.contains('/upload/')) return url;
  if (url.contains('f_auto') || url.contains('q_auto')) return url;

  const marker = '/upload/';
  final idx = url.indexOf(marker);
  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  return '${before}f_auto,q_auto:good/$after';
}

enum _MediaKind { image, video }

class _MediaEntry {
  final _MediaKind kind;
  final String url;
  final ImageProvider? provider;

  const _MediaEntry._(this.kind, this.url, this.provider);

  factory _MediaEntry.image(String url) {
    final u = _optimizeCloudinaryUrl(url);
    return _MediaEntry._(
      _MediaKind.image,
      u,
      CachedNetworkImageProvider(u),
    );
  }

  factory _MediaEntry.video(String url) {
    final u = _optimizeCloudinaryVideoUrl(url);
    return _MediaEntry._(_MediaKind.video, u, null);
  }
}

class _ZoomOverlayData {
  final ImageProvider provider;
  final BoxFit fit;
  final double scale;
  final Offset offset;

  const _ZoomOverlayData({
    required this.provider,
    required this.fit,
    required this.scale,
    required this.offset,
  });
}

class PostOverlay extends StatelessWidget {
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
      }) async {
    if (kIsWeb) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.20),
          transitionDuration: const Duration(milliseconds: 160),
          reverseTransitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (_, __, ___) =>
              PostOverlay(docs: docs, initialIndex: startIndex),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            child: child,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostOverlay(docs: docs, initialIndex: startIndex),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PostOverlayBody(docs: docs, initialIndex: initialIndex);
  }
}

class _PostOverlayBody extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final int initialIndex;

  const _PostOverlayBody({
    required this.docs,
    required this.initialIndex,
  });

  @override
  State<_PostOverlayBody> createState() => _PostOverlayBodyState();
}

class _PostOverlayBodyState extends State<_PostOverlayBody> {
  late final PageController _pageController;

  bool _zooming = false;
  int _activeIndex = 0;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _activeIndex =
        widget.initialIndex.clamp(0, (widget.docs.length - 1).clamp(0, 1 << 30));
    _pageController = PageController(initialPage: _activeIndex);
    _checkAdmin();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;

      final snap =
      await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final role = (snap.data()?['role'] ?? 'user').toString().toLowerCase();

      if (!mounted) return;
      setState(() => _isAdmin = role == 'admin' || role == 'super');
    } catch (_) {}
  }

  void _goTo(int idx) {
    if (widget.docs.isEmpty) return;
    final target = idx.clamp(0, widget.docs.length - 1);

    final isWebDesktop = kIsWeb && MediaQuery.of(context).size.width >= 1000;

    if (isWebDesktop) {
      if (target != _activeIndex && mounted) {
        setState(() => _activeIndex = target);
      }
      return;
    }

    if (!_pageController.hasClients) return;

    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _goPrev() => _goTo(_activeIndex - 1);
  void _goNext() => _goTo(_activeIndex + 1);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isWebDesktop = kIsWeb && mq.size.width >= 1000;

    if (isWebDesktop) {
      final doc = widget.docs[_activeIndex];

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _zooming ? null : () => Navigator.pop(context),
              ),
            ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: _WebInstagramLikeViewerLight(
                  doc: doc,
                  isAdmin: _isAdmin,
                  onClose: () => Navigator.pop(context),
                  onPrev: _activeIndex > 0 ? _goPrev : null,
                  onNext: _activeIndex < widget.docs.length - 1 ? _goNext : null,
                  onZoomingChanged: (z) {
                    if (mounted) setState(() => _zooming = z);
                  },
                  onDeleted: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: _zooming
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: widget.docs.length,
        onPageChanged: (idx) {
          if (!mounted) return;
          setState(() => _activeIndex = idx);
        },
        itemBuilder: (_, idx) {
          return _PostCard(
            doc: widget.docs[idx],
            isAdmin: _isAdmin,
            onZoomingChanged: (z) {
              if (mounted) setState(() => _zooming = z);
            },
            onDeleted: () => Navigator.pop(context),
            isWebInstagram: false,
          );
        },
      ),
    );
  }
}

class _WebInstagramLikeViewerLight extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAdmin;
  final VoidCallback onClose;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<bool> onZoomingChanged;
  final VoidCallback onDeleted;

  const _WebInstagramLikeViewerLight({
    required this.doc,
    required this.isAdmin,
    required this.onClose,
    required this.onPrev,
    required this.onNext,
    required this.onZoomingChanged,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    final cardW = (w * 0.72).clamp(860.0, 1100.0);
    final cardH = (h * 0.86).clamp(560.0, 820.0);

    return SizedBox(
      width: cardW,
      height: cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Material(
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Container(
                      color: const Color(0xFFF6F6F6),
                      child: _PostCard(
                        doc: doc,
                        isAdmin: isAdmin,
                        onZoomingChanged: onZoomingChanged,
                        onDeleted: onDeleted,
                        isWebInstagram: true,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Container(
                      color: Colors.white,
                      child: _WebRightPanelLight(
                        doc: doc,
                        isAdmin: isAdmin,
                        onDeleted: onDeleted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -6,
            left: -56,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onClose,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.close, color: Colors.black, size: 22),
                ),
              ),
            ),
          ),
          if (onPrev != null)
            Positioned(
              left: -22,
              top: 0,
              bottom: 0,
              child: Center(
                child: _WebArrowButtonLight(
                  icon: Icons.chevron_left,
                  onTap: onPrev!,
                ),
              ),
            ),
          if (onNext != null)
            Positioned(
              right: -22,
              top: 0,
              bottom: 0,
              child: Center(
                child: _WebArrowButtonLight(
                  icon: Icons.chevron_right,
                  onTap: onNext!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WebArrowButtonLight extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _WebArrowButtonLight({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.90),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: Colors.black87, size: 30),
        ),
      ),
    );
  }
}

class _WebRightPanelLight extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAdmin;
  final VoidCallback onDeleted;

  const _WebRightPanelLight({
    required this.doc,
    required this.isAdmin,
    required this.onDeleted,
  });

  @override
  State<_WebRightPanelLight> createState() => _WebRightPanelLightState();
}

class _WebRightPanelLightState extends State<_WebRightPanelLight> {
  late Map<String, dynamic> data;
  bool liked = false;
  StreamSubscription? _likeSub;

  @override
  void initState() {
    super.initState();
    data = Map<String, dynamic>.from(widget.doc.data());
    _watchLike();
  }

  @override
  void didUpdateWidget(covariant _WebRightPanelLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      data = Map<String, dynamic>.from(widget.doc.data());
      _watchLike();
    }
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  void _watchLike() {
    _likeSub?.cancel();
    _likeSub = null;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => liked = false);
      return;
    }

    _likeSub = LikeService.instance.watchLiked(widget.doc.id).listen((v) {
      if (!mounted) return;
      setState(() => liked = v);
    });
  }

  Future<void> _toggleLike() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final prev = liked;
    setState(() => liked = !prev);
    try {
      await LikeService.instance.toggle(widget.doc.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => liked = prev);
    }
  }

  Future<void> _handleMenuAction(String value) async {
    if (!mounted) return;

    if (value == 'edit') {
      await _editPost();
      return;
    }

    if (value == 'delete') {
      await _confirmDelete();
      return;
    }
  }

  Future<void> _editPost() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPostPage(
          postId: widget.doc.id,
          initialData: data,
        ),
      ),
    );

    if (updated == true) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.doc.id)
            .get(const GetOptions(source: Source.server));

        if (snap.exists && mounted) {
          setState(() => data = Map<String, dynamic>.from(snap.data()!));
        }
      } catch (_) {}
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('이 게시물을 정말 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.redAccent),
            ),
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
      widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brandKor = (data['brand'] ?? '').toString().trim();
    final brandEng = (data['brandEng'] ?? '').toString().trim();
    final logoUrl =
    (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString().trim();

    final title = (data['title'] ?? '').toString();
    final code = (data['itemCode'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
                backgroundImage:
                logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                child: logoUrl.isEmpty
                    ? const Icon(Icons.store, color: Colors.black54, size: 16)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BrandProfilePage(
                          brandKor: brandKor.isEmpty ? 'ALL' : brandKor,
                          brandEng: brandEng,
                          isAdmin: widget.isAdmin,
                        ),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brandKor.isEmpty ? 'ALL' : brandKor,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (brandEng.isNotEmpty)
                        Text(
                          brandEng,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.isAdmin)
                PopupMenuButton<String>(
                  tooltip: '더보기',
                  color: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  position: PopupMenuPosition.under,
                  onSelected: _handleMenuAction,
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('수정'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(
                        '삭제',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8, right: 2),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.more_horiz,
                        color: Colors.black87,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 18, 12),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: double.infinity,
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.black),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title.isEmpty ? '(제목 없음)' : title,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (widget.isAdmin && code.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            code,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.55),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      if (desc.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            desc,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.88),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.black.withValues(alpha: 0.10),
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _toggleLike,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                color: liked ? Colors.redAccent : Colors.black,
                iconSize: 24,
                splashRadius: 18,
              ),
              Text(
                '좋아요',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.90),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAdmin;
  final ValueChanged<bool> onZoomingChanged;
  final VoidCallback onDeleted;
  final bool isWebInstagram;

  const _PostCard({
    required this.doc,
    required this.isAdmin,
    required this.onZoomingChanged,
    required this.onDeleted,
    required this.isWebInstagram,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  late Map<String, dynamic> data;
  late List<_MediaEntry> media;

  bool liked = false;
  StreamSubscription? _likeSub;

  _ZoomOverlayData? _overlayData;
  final GlobalKey _mediaAreaKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    data = Map<String, dynamic>.from(widget.doc.data());
    media = _buildMedia(data);
    _watchLike();
  }

  @override
  void didUpdateWidget(covariant _PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      data = Map<String, dynamic>.from(widget.doc.data());
      media = _buildMedia(data);
      _watchLike();
      _overlayData = null;
    }
  }

  @override
  void dispose() {
    _likeSub?.cancel();
    super.dispose();
  }

  List<_MediaEntry> _buildMedia(Map<String, dynamic> m) {
    final out = <_MediaEntry>[];

    final imgs = m['images'];
    if (imgs is List && imgs.isNotEmpty) {
      for (final e in imgs) {
        final u = (e ?? '').toString().trim();
        if (u.isEmpty) continue;
        out.add(_isVideoUrl(u) ? _MediaEntry.video(u) : _MediaEntry.image(u));
      }
    } else {
      final one = (m['imageUrl'] ?? '').toString().trim();
      if (one.isNotEmpty) {
        out.add(
          _isVideoUrl(one) ? _MediaEntry.video(one) : _MediaEntry.image(one),
        );
      }
    }

    final vids = m['videos'];
    if (vids is List && vids.isNotEmpty) {
      for (final e in vids) {
        final u = (e ?? '').toString().trim();
        if (u.isEmpty) continue;
        out.add(_MediaEntry.video(u));
      }
    }

    return out;
  }

  void _watchLike() {
    _likeSub?.cancel();
    _likeSub = null;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => liked = false);
      return;
    }

    _likeSub = LikeService.instance.watchLiked(widget.doc.id).listen((v) {
      if (!mounted) return;
      setState(() => liked = v);
    });
  }

  Future<void> _toggleLike() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final prev = liked;
    setState(() => liked = !prev);
    try {
      await LikeService.instance.toggle(widget.doc.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => liked = prev);
    }
  }

  Future<void> _handleMobileMenuAction(String value) async {
    if (!mounted) return;

    if (value == 'edit') {
      await _editMobilePost();
      return;
    }

    if (value == 'delete') {
      await _confirmMobileDelete();
      return;
    }
  }

  Future<void> _editMobilePost() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPostPage(
          postId: widget.doc.id,
          initialData: data,
        ),
      ),
    );

    if (updated == true) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.doc.id)
            .get(const GetOptions(source: Source.server));

        if (snap.exists && mounted) {
          setState(() {
            data = Map<String, dynamic>.from(snap.data()!);
            media = _buildMedia(data);
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _confirmMobileDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('이 게시물을 정말 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.redAccent),
            ),
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
      widget.onDeleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }

  void _handleOverlayChanged(_ZoomOverlayData? data) {
    if (!mounted) return;
    setState(() {
      _overlayData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isWebInstagram) {
      return _MediaCarousel(
        media: media,
        onZoomingChanged: widget.onZoomingChanged,
        onOverlayChanged: _handleOverlayChanged,
        contain: true,
        darkBg: false,
        isMobileFrame: false,
      );
    }

    final brandKor = (data['brand'] ?? '').toString().trim();
    final brandEng = (data['brandEng'] ?? '').toString().trim();
    final logoUrl =
    (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString().trim();

    final title = (data['title'] ?? '').toString();
    final code = (data['itemCode'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BrandRowMobile(
              brandKor: brandKor.isEmpty ? 'ALL' : brandKor,
              brandEng: brandEng,
              logoUrl: logoUrl,
              showMore: widget.isAdmin,
              onMenuSelected: _handleMobileMenuAction,
              isAdmin: widget.isAdmin,
            ),
            Container(
              key: _mediaAreaKey,
              clipBehavior: Clip.none,
              child: _MediaCarousel(
                media: media,
                onZoomingChanged: widget.onZoomingChanged,
                onOverlayChanged: _handleOverlayChanged,
                contain: true,
                darkBg: false,
                isMobileFrame: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _toggleLike,
                    icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                    color: liked ? Colors.redAccent : Colors.black,
                    iconSize: 26,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '좋아요',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '(제목 없음)' : title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (widget.isAdmin && code.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      code,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                  if (desc.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      desc,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ),
        if (_overlayData != null)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, rootConstraints) {
                  final mediaBox =
                  _mediaAreaKey.currentContext?.findRenderObject()
                  as RenderBox?;
                  final rootBox = context.findRenderObject() as RenderBox?;

                  if (mediaBox == null || !mediaBox.hasSize) {
                    return const SizedBox.shrink();
                  }

                  final mediaTopLeft =
                  mediaBox.localToGlobal(Offset.zero, ancestor: rootBox);
                  final mediaSize = mediaBox.size;
                  final d = _overlayData!;

                  const double _zoomOverlayYOffset = 150.0;

                  return OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: rootConstraints.maxWidth,
                    maxWidth: double.infinity,
                    minHeight: rootConstraints.maxHeight,
                    maxHeight: double.infinity,
                    child: Transform(
                      alignment: Alignment.topLeft,
                      transform: Matrix4.identity()
                        ..translate(
                          mediaTopLeft.dx + d.offset.dx,
                          mediaTopLeft.dy + d.offset.dy - _zoomOverlayYOffset,
                        )
                        ..scale(d.scale, d.scale),
                      child: SizedBox(
                        width: mediaSize.width,
                        height: mediaSize.height,
                        child: Image(
                          image: d.provider,
                          fit: d.fit,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _BrandRowMobile extends StatelessWidget {
  final String brandKor;
  final String brandEng;
  final String logoUrl;
  final bool showMore;
  final ValueChanged<String> onMenuSelected;
  final bool isAdmin;

  const _BrandRowMobile({
    required this.brandKor,
    required this.brandEng,
    required this.logoUrl,
    required this.showMore,
    required this.onMenuSelected,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BrandProfilePage(
                brandKor: brandKor,
                brandEng: brandEng,
                isAdmin: isAdmin,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
                backgroundImage:
                logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                child: logoUrl.isEmpty
                    ? const Icon(
                  Icons.store,
                  size: 18,
                  color: Colors.black54,
                )
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brandKor,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  if (brandEng.trim().isNotEmpty)
                    Text(
                      brandEng.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.40),
                        letterSpacing: 0.8,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (showMore)
                PopupMenuButton<String>(
                  tooltip: '더보기',
                  color: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  position: PopupMenuPosition.under,
                  onSelected: onMenuSelected,
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('수정'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(
                        '삭제',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz, color: Colors.black87),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaCarousel extends StatefulWidget {
  final List<_MediaEntry> media;
  final ValueChanged<bool> onZoomingChanged;
  final ValueChanged<_ZoomOverlayData?> onOverlayChanged;
  final bool contain;
  final bool darkBg;
  final bool isMobileFrame;

  const _MediaCarousel({
    required this.media,
    required this.onZoomingChanged,
    required this.onOverlayChanged,
    required this.contain,
    required this.darkBg,
    required this.isMobileFrame,
  });

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  final PageController _pager = PageController();
  int _idx = 0;
  bool _childZooming = false;

  final Map<int, double> _aspectRatioCache = {};

  @override
  void initState() {
    super.initState();
    _preloadCurrentAspectRatio();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _setChildZooming(bool value) {
    if (_childZooming == value) return;
    setState(() => _childZooming = value);
    widget.onZoomingChanged(value);

    if (!value) {
      widget.onOverlayChanged(null);
    }
  }

  void _setOverlayData(_ZoomOverlayData? data) {
    widget.onOverlayChanged(data);
  }

  void _goPrevPhoto() {
    if (_childZooming) return;
    if (!_pager.hasClients || _idx <= 0) return;
    _pager.animateToPage(
      _idx - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _goNextPhoto() {
    if (_childZooming) return;
    if (!_pager.hasClients || _idx >= widget.media.length - 1) return;
    _pager.animateToPage(
      _idx + 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _preloadCurrentAspectRatio() {
    if (widget.media.isEmpty) return;
    _resolveAspectRatio(_idx);
    if (_idx - 1 >= 0) _resolveAspectRatio(_idx - 1);
    if (_idx + 1 < widget.media.length) _resolveAspectRatio(_idx + 1);
  }

  Future<void> _resolveAspectRatio(int index) async {
    if (_aspectRatioCache.containsKey(index)) return;
    if (index < 0 || index >= widget.media.length) return;

    final m = widget.media[index];

    try {
      if (m.kind == _MediaKind.video) {
        final controller = VideoPlayerController.networkUrl(Uri.parse(m.url));
        await controller.initialize();
        final size = controller.value.size;
        final ratio =
        (size.width > 0 && size.height > 0) ? size.width / size.height : 1.0;
        await controller.dispose();

        if (!mounted) return;
        setState(() {
          _aspectRatioCache[index] = ratio.clamp(0.4, 3.0);
        });
        return;
      }

      final completer = Completer<ImageInfo>();
      final stream = m.provider!.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;

      listener = ImageStreamListener(
            (ImageInfo info, bool _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
          stream.removeListener(listener);
        },
      );

      stream.addListener(listener);

      final info = await completer.future;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      final ratio = (w > 0 && h > 0) ? w / h : 1.0;

      if (!mounted) return;
      setState(() {
        _aspectRatioCache[index] = ratio.clamp(0.4, 3.0);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aspectRatioCache[index] = 1.0;
      });
    }
  }

  double _currentAspectRatio() => _aspectRatioCache[_idx] ?? 1.0;

  double _mobileHeight(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final ratio = _currentAspectRatio();

    double width = screenW;
    width = width.clamp(280.0, 900.0);

    double height = width / ratio;

    final maxHeight = screenW * 1.15;
    const minHeight = 220.0;

    return height.clamp(minHeight, maxHeight);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) {
      return const SizedBox(
        height: 280,
        child: Center(
          child: Icon(Icons.broken_image_outlined, size: 44),
        ),
      );
    }

    final fit = widget.contain ? BoxFit.contain : BoxFit.cover;

    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _pager,
            physics: _childZooming
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.media.length,
            onPageChanged: (i) {
              setState(() => _idx = i);
              widget.onOverlayChanged(null);
              _preloadCurrentAspectRatio();
            },
            itemBuilder: (_, i) {
              final m = widget.media[i];

              if (m.kind == _MediaKind.video) {
                return _VideoPlayerView(
                  url: m.url,
                  fitContain: widget.contain,
                );
              }

              if (kIsWeb) {
                return WebImage(url: m.url, fit: fit);
              }

              return _InlineZoomableMediaImage(
                provider: m.provider!,
                fit: fit,
                onZoomingChanged: _setChildZooming,
                onOverlayChanged: i == _idx ? _setOverlayData : (_) {},
              );
            },
          ),
        ),
        if (kIsWeb && widget.media.length > 1 && !_childZooming && _idx > 0)
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: _InnerPhotoArrowButton(
                icon: Icons.chevron_left,
                onTap: _goPrevPhoto,
              ),
            ),
          ),
        if (kIsWeb &&
            widget.media.length > 1 &&
            !_childZooming &&
            _idx < widget.media.length - 1)
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: _InnerPhotoArrowButton(
                icon: Icons.chevron_right,
                onTap: _goNextPhoto,
              ),
            ),
          ),
        if (widget.media.length > 1 && !_childZooming)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.media.length, (i) {
                      final active = i == _idx;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 14 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.isMobileFrame) {
      final h = _mobileHeight(context);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: h,
        clipBehavior: Clip.none,
        child: SizedBox(
          width: double.infinity,
          height: h,
          child: content,
        ),
      );
    }

    return SizedBox.expand(child: content);
  }
}

class _InlineZoomableMediaImage extends StatefulWidget {
  final ImageProvider provider;
  final BoxFit fit;
  final ValueChanged<bool> onZoomingChanged;
  final ValueChanged<_ZoomOverlayData?> onOverlayChanged;

  const _InlineZoomableMediaImage({
    required this.provider,
    required this.fit,
    required this.onZoomingChanged,
    required this.onOverlayChanged,
  });

  @override
  State<_InlineZoomableMediaImage> createState() =>
      _InlineZoomableMediaImageState();
}
class _InlineZoomableMediaImageState extends State<_InlineZoomableMediaImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _resetController;

  Animation<double>? _scaleAnim;
  Animation<Offset>? _offsetAnim;

  double _scale = 1.0;
  Offset _offset = Offset.zero;

  double _startScale = 1.0;
  Offset _normalizedOffset = Offset.zero;

  int _pointerCount = 0;
  bool _zooming = false;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();

    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
      if (!mounted) return;
      setState(() {
        _scale = _scaleAnim?.value ?? 1.0;
        _offset = _offsetAnim?.value ?? Offset.zero;
      });
      _pushOverlay();
    });

    _resetController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _setZooming(false);
        widget.onOverlayChanged(null);
      }
    });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _setZooming(bool value) {
    if (_zooming == value) return;
    _zooming = value;
    widget.onZoomingChanged(value);
  }

  void _pushOverlay() {
    if (!_zooming || _lastSize == Size.zero) {
      widget.onOverlayChanged(null);
      return;
    }

    widget.onOverlayChanged(
      _ZoomOverlayData(
        provider: widget.provider,
        fit: widget.fit,
        scale: _scale,
        offset: _offset,
      ),
    );
  }

  void _animateReset() {
    _scaleAnim = Tween<double>(
      begin: _scale,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _resetController,
        curve: Curves.easeOutCubic,
      ),
    );

    _offsetAnim = Tween<Offset>(
      begin: _offset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _resetController,
        curve: Curves.easeOutCubic,
      ),
    );

    _resetController
      ..stop()
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final targetW =
    (mq.size.width * mq.devicePixelRatio).clamp(1200.0, 3000.0).round();
    final optimizedProvider = ResizeImage(widget.provider, width: targetW);

    return LayoutBuilder(
      builder: (context, constraints) {
        _lastSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            _pointerCount++;
            if (_pointerCount >= 2) {
              _resetController.stop();
              _setZooming(true);
              _pushOverlay();
            }
          },
          onPointerUp: (_) {
            _pointerCount = (_pointerCount - 1).clamp(0, 10);
            if (_pointerCount < 2 && _zooming) {
              _animateReset();
            }
          },
          onPointerCancel: (_) {
            _pointerCount = 0;
            if (_zooming) {
              _animateReset();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onScaleStart: (details) {
              if (_pointerCount < 2) return;

              _resetController.stop();
              _startScale = _scale;
              _normalizedOffset =
                  (details.localFocalPoint - _offset) / _scale;

              _setZooming(true);
              _pushOverlay();
            },
            onScaleUpdate: (details) {
              if (_pointerCount < 2) return;

              double nextScale = (_startScale * details.scale).clamp(1.0, 4.0);
              Offset nextOffset =
                  details.localFocalPoint - (_normalizedOffset * nextScale);

              if (nextScale <= 1.001) {
                nextScale = 1.0;
                nextOffset = Offset.zero;
              }

              setState(() {
                _scale = nextScale;
                _offset = nextOffset;
              });

              _setZooming(true);
              _pushOverlay();
            },
            onScaleEnd: (_) {
              if (_pointerCount < 2 && _zooming) {
                _animateReset();
              }
            },
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Opacity(
                opacity: _zooming ? 0.0 : 1.0,
                child: Image(
                  image: optimizedProvider,
                  fit: widget.fit,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InnerPhotoArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _InnerPhotoArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.32),
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _VideoPlayerView extends StatefulWidget {
  final String url;
  final bool fitContain;

  const _VideoPlayerView({
    required this.url,
    required this.fitContain,
  });

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _vc;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _init();
  }

  Future<void> _init() async {
    try {
      await _vc.initialize();
      _vc
        ..setLooping(true)
        ..setVolume(0.0);
      await _vc.play();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !_vc.value.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final child = SizedBox(
      width: _vc.value.size.width,
      height: _vc.value.size.height,
      child: VideoPlayer(_vc),
    );

    return widget.fitContain
        ? FittedBox(fit: BoxFit.contain, child: child)
        : FittedBox(fit: BoxFit.cover, child: child);
  }
}