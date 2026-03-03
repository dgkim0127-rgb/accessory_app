// lib/widgets/post_overlay.dart ✅ 최종 (웹 인스타 레이아웃 + 흰색 톤 고정)
// - 웹(>=1000): 인스타그램 스타일(가운데 카드 + 좌측 미디어 + 우측 패널 + X + 좌/우 이동)
//   ✅ 단, 검정색은 다크모드 때문이라 했으니: 웹도 "항상 흰색 톤"으로 고정
// - 모바일: 흰색 꽉찬 화면 + AppBar 뒤로 고정 + 미디어 영역 AspectRatio(안보임 버그 해결)
// - 브랜드 옆 ⋯(관리자만): 수정/삭제
// - 좋아요 옆 ⋯ 없음
// - 일반 등급: 품번(itemCode) 숨김(관리자만)
// - 사진: 원본 비율 유지(안 잘림) -> BoxFit.contain
// - Like watch: doc 바뀌면 재구독(didUpdateWidget)

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
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
  if (url.contains('f_auto') || url.contains('q_auto') || url.contains('w_')) return url;

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
    return _MediaEntry._(_MediaKind.image, u, CachedNetworkImageProvider(u));
  }

  factory _MediaEntry.video(String url) {
    final u = _optimizeCloudinaryVideoUrl(url);
    return _MediaEntry._(_MediaKind.video, u, null);
  }
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
    // ✅ 웹: 오버레이(딤) / 모바일: 일반 페이지
    if (kIsWeb) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          // ✅ 흰 톤 카드가 잘 보이도록: 아주 연한 딤
          barrierColor: Colors.black.withValues(alpha: 0.20),
          transitionDuration: const Duration(milliseconds: 160),
          reverseTransitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (_, __, ___) => PostOverlay(docs: docs, initialIndex: startIndex),
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
  final ItemScrollController _scrollCtrl = ItemScrollController();
  final ItemPositionsListener _posListener = ItemPositionsListener.create();

  bool _zooming = false;
  int _activeIndex = 0;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _activeIndex =
        widget.initialIndex.clamp(0, (widget.docs.length - 1).clamp(0, 1 << 30));
    _posListener.itemPositions.addListener(_onPositions);
    _checkAdmin();
  }

  @override
  void dispose() {
    _posListener.itemPositions.removeListener(_onPositions);
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

  void _onPositions() {
    final positions = _posListener.itemPositions.value;
    if (positions.isEmpty) return;

    int best = _activeIndex;
    double bestScore = double.infinity;

    for (final p in positions) {
      final center = (p.itemLeadingEdge + p.itemTrailingEdge) / 2.0;
      final score = (center - 0.5).abs();
      if (score < bestScore) {
        bestScore = score;
        best = p.index;
      }
    }

    if (best != _activeIndex && mounted) {
      setState(() => _activeIndex = best);
    }
  }

  void _goTo(int idx) {
    if (!_scrollCtrl.isAttached) return;
    final target = idx.clamp(0, widget.docs.length - 1);
    _scrollCtrl.scrollTo(
      index: target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  void _goPrev() => _goTo(_activeIndex - 1);
  void _goNext() => _goTo(_activeIndex + 1);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isWebDesktop = kIsWeb && mq.size.width >= 1000;

    // ✅ 웹 데스크탑: 인스타그램 스타일(하지만 흰색 톤 고정)
    if (isWebDesktop) {
      final doc = widget.docs[_activeIndex];

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 바깥 클릭 닫기
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _zooming ? null : () => Navigator.pop(context),
              ),
            ),
            Center(
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
          ],
        ),
      );
    }

    // ✅ 모바일: 흰색 꽉찬 페이지 + AppBar 뒤로
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
      body: ScrollablePositionedList.builder(
        itemScrollController: _scrollCtrl,
        itemPositionsListener: _posListener,
        initialScrollIndex: widget.initialIndex.clamp(
          0,
          (widget.docs.length - 1).clamp(0, 1 << 30),
        ),
        initialAlignment: 0.08,
        physics: _zooming
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        itemCount: widget.docs.length,
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

/// ───────────────────────── 웹(인스타그램 스타일, 라이트 톤 고정) ─────────────────────────

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
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Material(
              color: Colors.white,
              child: Row(
                children: [
                  // 좌측: 미디어(흰 배경 + contain)
                  Expanded(
                    flex: 7,
                    child: Container(
                      color: const Color(0xFFF6F6F6),
                      child: _PostCard(
                        doc: doc,
                        isAdmin: isAdmin,
                        onZoomingChanged: onZoomingChanged,
                        onDeleted: onDeleted,
                        isWebInstagram: true, // 미디어만
                      ),
                    ),
                  ),
                  // 우측: 패널(화이트)
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

          // 닫기(X)
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close, color: Colors.black),
              splashRadius: 22,
            ),
          ),

          if (onPrev != null)
            Positioned(
              left: -8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _WebArrowButtonLight(icon: Icons.chevron_left, onTap: onPrev!),
              ),
            ),
          if (onNext != null)
            Positioned(
              right: -8,
              top: 0,
              bottom: 0,
              child: Center(
                child: _WebArrowButtonLight(icon: Icons.chevron_right, onTap: onNext!),
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
  const _WebArrowButtonLight({required this.icon, required this.onTap});

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

  Future<void> _openMoreMenu() async {
    if (!widget.isAdmin) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('수정'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;

    if (selected == 'edit') {
      final updated = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditPostPage(postId: widget.doc.id, initialData: data),
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

    if (selected == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('삭제'),
          content: const Text('정말 삭제할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );

      if (ok == true) {
        try {
          await FirebaseFirestore.instance.collection('posts').doc(widget.doc.id).delete();
          if (!mounted) return;
          widget.onDeleted();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brandKor = (data['brand'] ?? '').toString().trim();
    final brandEng = (data['brandEng'] ?? '').toString().trim();
    final logoUrl = (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString().trim();

    final title = (data['title'] ?? '').toString();
    final code = (data['itemCode'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();

    return Column(
      children: [
        // 헤더(브랜드 + ⋯)
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.10))),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
                backgroundImage: logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brandKor.isEmpty ? 'ALL' : brandKor,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (brandEng.isNotEmpty)
                        Text(
                          brandEng,
                          style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.isAdmin)
                IconButton(
                  onPressed: _openMoreMenu,
                  icon: const Icon(Icons.more_horiz, color: Colors.black87),
                  splashRadius: 18,
                ),
            ],
          ),
        ),

        // 본문(스크롤)
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? '(제목 없음)' : title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, height: 1.25),
                  ),
                  // ✅ 관리자만 품번 표시
                  if (widget.isAdmin && code.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      code,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.55),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (desc.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      desc,
                      style: TextStyle(color: Colors.black.withValues(alpha: 0.88), height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // 하단 액션(좋아요)
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.10))),
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
                style: TextStyle(color: Colors.black.withValues(alpha: 0.90), fontWeight: FontWeight.w700),
              ),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }
}

/// ───────────────────────── 공통 포스트 카드 (모바일/웹좌측) ─────────────────────────
/// isWebInstagram=true: 미디어만(좌측 큰 화면)
/// false: 모바일 카드 형태(브랜드/좋아요/본문)

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
      if (one.isNotEmpty) out.add(_isVideoUrl(one) ? _MediaEntry.video(one) : _MediaEntry.image(one));
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

  Future<void> _openMoreMenuMobile() async {
    if (!widget.isAdmin) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('수정'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || selected == null) return;

    if (selected == 'edit') {
      final updated = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditPostPage(postId: widget.doc.id, initialData: data),
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

    if (selected == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('삭제'),
          content: const Text('정말 삭제할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );

      if (ok == true) {
        try {
          await FirebaseFirestore.instance.collection('posts').doc(widget.doc.id).delete();
          if (!mounted) return;
          widget.onDeleted();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 웹 인스타 좌측: 미디어만
    if (widget.isWebInstagram) {
      return _MediaCarousel(
        media: media,
        onZoomingChanged: widget.onZoomingChanged,
        contain: true,
        darkBg: false, // ✅ 흰 톤
        isMobileFrame: false,
      );
    }

    // ✅ 모바일 카드
    final brandKor = (data['brand'] ?? '').toString().trim();
    final brandEng = (data['brandEng'] ?? '').toString().trim();
    final logoUrl = (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString().trim();

    final title = (data['title'] ?? '').toString();
    final code = (data['itemCode'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BrandRowMobile(
          brandKor: brandKor.isEmpty ? 'ALL' : brandKor,
          brandEng: brandEng,
          logoUrl: logoUrl,
          showMore: widget.isAdmin,
          onMore: _openMoreMenuMobile,
          isAdmin: widget.isAdmin,
        ),
        // ✅ 모바일 안보임 버그 해결: AspectRatio 프레임
        _MediaCarousel(
          media: media,
          onZoomingChanged: widget.onZoomingChanged,
          contain: true,
          darkBg: false,
          isMobileFrame: true,
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
              const Text('좋아요', style: TextStyle(fontWeight: FontWeight.w700)),
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
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3),
              ),
              // ✅ 관리자만 품번 표시
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
                Text(desc, style: const TextStyle(fontSize: 14, height: 1.5)),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _BrandRowMobile extends StatelessWidget {
  final String brandKor;
  final String brandEng;
  final String logoUrl;
  final bool showMore;
  final VoidCallback onMore;
  final bool isAdmin;

  const _BrandRowMobile({
    required this.brandKor,
    required this.brandEng,
    required this.logoUrl,
    required this.showMore,
    required this.onMore,
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
                backgroundImage: logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                child: logoUrl.isEmpty ? const Icon(Icons.store, size: 18, color: Colors.black54) : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(brandKor, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
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
                IconButton(
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz),
                  color: Colors.black87,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ───────────────────────── 미디어 캐러셀 (모바일 높이 제약) ─────────────────────────

class _MediaCarousel extends StatefulWidget {
  final List<_MediaEntry> media;
  final ValueChanged<bool> onZoomingChanged;
  final bool contain;
  final bool darkBg;
  final bool isMobileFrame;

  const _MediaCarousel({
    required this.media,
    required this.onZoomingChanged,
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

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) {
      return const SizedBox(
        height: 280,
        child: Center(child: Icon(Icons.broken_image_outlined, size: 44)),
      );
    }

    final fit = widget.contain ? BoxFit.contain : BoxFit.cover;
    final bg = widget.darkBg ? const Color(0xFF0E0E0E) : const Color(0xFFF6F6F6);

    final content = Container(
      color: bg,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pager,
            itemCount: widget.media.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) {
              final m = widget.media[i];

              if (m.kind == _MediaKind.video) {
                return _VideoPlayerView(url: m.url, fitContain: widget.contain);
              }

              if (kIsWeb) {
                return WebImage(url: m.url, fit: fit);
              }

              return _TwoFingerZoomImage(
                provider: m.provider!,
                onZoomingChanged: widget.onZoomingChanged,
                fit: fit,
              );
            },
          ),
          if (widget.media.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                          color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.isMobileFrame) {
      return AspectRatio(aspectRatio: 4 / 5, child: content);
    }
    return SizedBox.expand(child: content);
  }
}

class _VideoPlayerView extends StatefulWidget {
  final String url;
  final bool fitContain;
  const _VideoPlayerView({required this.url, required this.fitContain});

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
      _vc..setLooping(true)..setVolume(0.0);
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
        child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2)),
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

class _TwoFingerZoomImage extends StatefulWidget {
  final ImageProvider provider;
  final ValueChanged<bool> onZoomingChanged;
  final BoxFit fit;

  const _TwoFingerZoomImage({
    required this.provider,
    required this.onZoomingChanged,
    required this.fit,
  });

  @override
  State<_TwoFingerZoomImage> createState() => _TwoFingerZoomImageState();
}

class _TwoFingerZoomImageState extends State<_TwoFingerZoomImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _ac;

  Animation<Matrix4>? _reset;
  bool _zooming = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() {
        if (_reset != null) _tc.value = _reset!.value;
      });
  }

  @override
  void dispose() {
    _ac.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _setZooming(bool z) {
    if (_zooming == z) return;
    _zooming = z;
    widget.onZoomingChanged(z);
  }

  void _resetBack() {
    _ac.stop();
    _reset = Matrix4Tween(begin: _tc.value, end: Matrix4.identity())
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_ac);
    _ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _tc,
      minScale: 1.0,
      maxScale: 4.0,
      onInteractionStart: (_) => _setZooming(true),
      onInteractionEnd: (_) {
        _setZooming(false);
        _resetBack();
      },
      child: Image(image: widget.provider, fit: widget.fit, filterQuality: FilterQuality.low),
    );
  }
}