// lib/widgets/post_overlay.dart  ✅ 최종
// - 화면에 보이는 게시물만 실제 로딩 (안 보이면 스켈레톤만)
// - 게시물 안의 모든 "이미지"를 프리로드 후 표시 → 슬라이드 시 로딩 없음
// - 동영상 URL(.mp4/.mov/.m4v/.webm)은 비디오 플레이어로 재생
// - 모바일: 기존 세로 리스트 레이아웃 유지
// - 웹 넓은 화면: 팝업 오버레이 (2/3 폭, 좌/우 게시물 화살표, 사진/정보 3:2 레이아웃)
// - 웹: 카드 전체 세로 길이 = 미디어 세로 길이 (흰 공백 최소화)
// - 모바일: 사진 안 좌/우 버튼 숨김(터치 슬라이드만)
// - 360° 뷰어 + 웨이브 스켈레톤
// - 💻 웹: 이미지 줌/InteractiveViewer 제거 → 스크롤 버벅임 크게 감소
// - 📱 앱: 예전처럼 두 손가락 줌 유지

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import 'package:accessory_app/utils/page_safe.dart';
import '../pages/brand_profile_page.dart';
import '../pages/edit_post_page.dart';
import '../services/like_service.dart';
import 'web_image.dart'; // 🔥 웹용 경량 이미지

// ───────────────────────── 공통 유틸 ─────────────────────────

bool _isVideoUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.m4v') ||
        path.endsWith('.webm');
  } catch (_) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.m4v') ||
        lower.contains('.webm');
  }
}

// 🔥 Cloudinary URL 최적화 (게시물 상세용 Version A)
// - 이미지 → f_auto,q_auto:eco,w_1080
//   * f_auto        : WebP/AVIF 변환 → 용량 절반 이하
//   * q_auto:eco    : 화질 유지하면서도 용량 80~90% 감소
//   * w_1080        : 1080px로 리사이즈 → 웹에서 버벅임 제거
// - 동영상 → q_auto:eco 유지
String _optimizeCloudinaryUrl(String url) {
  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return url; // Cloudinary 형식 아님

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  // 이미 최적화 파라미터 있으면 그대로
  if (after.startsWith('f_auto') || after.startsWith('q_auto')) {
    return url;
  }

  final bool isVideo = _isVideoUrl(url);

  if (isVideo) {
    // 🎬 동영상: eco 모드 → 용량 줄고 스트리밍 빠름
    return '$before'
        'q_auto:eco/'
        '$after';
  } else {
    // 🖼 이미지: eco + f_auto + w_1080 → KB 단위 + 화질 유지
    return '$before'
        'f_auto,q_auto:eco,w_1080/'
        '$after';
  }
}

// 🔥 Cloudinary Video URL 최적화 (영상 전용)
String _optimizeCloudinaryVideoUrl(String url) {
  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return url;

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  if (after.startsWith('q_auto') || after.startsWith('f_auto')) {
    return url;
  }

  return '$before'
      'q_auto:eco,f_auto/'
      '$after';
}

// 🔥 Cloudinary 비디오 썸네일 URL (0초 지점 프레임)
String _buildVideoThumbnailUrl(String url) {
  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return '';

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  final dot = after.lastIndexOf('.');
  final base = (dot > 0) ? after.substring(0, dot) : after;

  return '$before'
      'so_0,q_auto:eco,f_auto/'
      '$base.jpg';
}

// ───────────────────────── 미디어 엔트리 ─────────────────────────

enum _MediaKind { image, video }

class _MediaEntry {
  final _MediaKind kind;
  final String url; // 최종 URL
  final ImageProvider? imageProvider; // 이미지일 때만 사용

  _MediaEntry._(this.kind, this.url, this.imageProvider);

  factory _MediaEntry.image({required String url}) {
    final normalized = _optimizeCloudinaryUrl(url);
    return _MediaEntry._(
      _MediaKind.image,
      normalized,
      CachedNetworkImageProvider(normalized),
    );
  }

  factory _MediaEntry.video({required String url}) {
    final normalized = _optimizeCloudinaryVideoUrl(url);
    return _MediaEntry._(
      _MediaKind.video,
      normalized,
      null,
    );
  }
}

// ───────────────────────── 오버레이 전체 ─────────────────────────

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
      }) async {
    _warmupFirstPostImages(context, docs, startIndex);

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, __, ___) =>
            PostOverlay(docs: docs, initialIndex: startIndex),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  /// 처음 여는 게시물의 이미지 몇 장만 살짝 예열 (백그라운드)
  static Future<void> _warmupFirstPostImages(
      BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      int startIndex,
      ) async {
    if (docs.isEmpty) return;

    final safeIndex = startIndex.clamp(0, docs.length - 1);
    final doc = docs[safeIndex];
    final data = doc.data();

    final urls = <String>[];

    final vImgs = data['images'];
    if (vImgs is List && vImgs.isNotEmpty) {
      urls.addAll(vImgs.map((e) => e.toString()).where((e) => e.isNotEmpty));
    } else {
      final one = (data['imageUrl'] ?? '').toString();
      if (one.isNotEmpty) urls.add(one);
    }

    for (final u in urls.where((e) => !_isVideoUrl(e)).take(3)) {
      final img = Image.network(
        _optimizeCloudinaryUrl(u),
        filterQuality: FilterQuality.low,
      );
      try {
        await precacheImage(img.image, context);
      } catch (_) {}
    }
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

  int _activePostIndex = 0;
  Set<int> _visibleIndices = {};

  final Map<int, bool> _prefetchedPosts = {};

  @override
  void initState() {
    super.initState();
    _initial = widget.initialIndex.clamp(0, widget.docs.length - 1);
    _list =
    List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(widget.docs);
    _activePostIndex = _initial;
    _visibleIndices = {_initial};
    _checkAdmin();

    _prefetchAround(_initial);

    _posListener.itemPositions.addListener(_handleItemPositions);
  }

  Future<void> _prefetchPost(int index) async {
    if (_prefetchedPosts[index] == true) return;
    if (index < 0 || index >= _list.length) return;

    _prefetchedPosts[index] = true;

    final data = _list[index].data();
    final urls = <String>[];
    final vImgs = data['images'];
    if (vImgs is List && vImgs.isNotEmpty) {
      urls.addAll(vImgs.map((e) => e.toString()).where((e) => e.isNotEmpty));
    } else {
      final one = (data['imageUrl'] ?? '').toString();
      if (one.isNotEmpty) urls.add(one);
    }

    for (final u in urls.where((e) => !_isVideoUrl(e))) {
      final img = Image.network(
        _optimizeCloudinaryUrl(u),
        filterQuality: FilterQuality.low,
        cacheWidth: 1080,
      );
      precacheImage(img.image, context).catchError((_) {});
    }
  }

  void _prefetchAround(int index) {
    _prefetchPost(index);
    _prefetchPost(index - 1);
    _prefetchPost(index + 1);
  }

  bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  void _handleItemPositions() {
    final positions = _posListener.itemPositions.value;
    if (positions.isEmpty) return;

    int bestIndex = _activePostIndex;
    double bestScore = double.infinity;
    final visible = <int>{};

    for (final pos in positions) {
      final leading = pos.itemLeadingEdge;
      final trailing = pos.itemTrailingEdge;

      if (trailing <= 0 || leading >= 1) continue;
      visible.add(pos.index);

      final center = (leading + trailing) / 2.0;
      final score = (center - 0.5).abs();
      if (score < bestScore) {
        bestScore = score;
        bestIndex = pos.index;
      }
    }

    if (!mounted) return;
    if (visible.isEmpty) return;

    final needUpdateIndex = bestIndex != _activePostIndex;
    final needUpdateVisible = !_setEquals(_visibleIndices, visible);

    if (needUpdateIndex || needUpdateVisible) {
      setState(() {
        _activePostIndex = bestIndex;
        _visibleIndices = visible;
      });

      _prefetchAround(bestIndex);
    }
  }

  Future<void> _checkAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final role = (snap.data()?['role'] ?? 'user').toString().toLowerCase();
      if (mounted) {
        setState(() => _isAdmin = role == 'admin' || role == 'super');
      }
    } catch (_) {}
  }

  void _handleDeleted(String docId) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('게시물이 삭제되었습니다.')),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _goToPost(int index) {
    if (index < 0 || index >= _list.length) return;
    if (!mounted) return;

    setState(() {
      _activePostIndex = index;
      _visibleIndices = {index};
    });

    _prefetchAround(index);

    if (!kIsWeb && _itemScrollCtrl.isAttached) {
      _itemScrollCtrl.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
  }

  void _goNextPost() => _goToPost(_activePostIndex + 1);
  void _goPrevPost() => _goToPost(_activePostIndex - 1);

  Widget _buildMobileContent(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
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
                  const Text(
                    '게시물',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
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
                      : const _FasterScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  itemCount: _list.length,
                  itemBuilder: (_, idx) {
                    final doc = _list[idx];
                    final isVisible = _visibleIndices.contains(idx);

                    return RepaintBoundary(
                      child: _PostCard(
                        doc: doc,
                        isAdmin: _isAdmin,
                        isPostActive: idx == _activePostIndex,
                        isVisible: isVisible,
                        onZoomingChanged: (z) {
                          if (mounted) {
                            setState(() => _isZooming = z);
                          }
                        },
                        onDeleted: _handleDeleted,
                      ),
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

  Widget _buildWebContent(BuildContext context) {
    if (_list.isEmpty) {
      return Material(
        color: Colors.black.withOpacity(0.55),
        child: const Center(
          child: Text(
            '표시할 게시물이 없어요',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final doc = _list[_activePostIndex];

    return Material(
      color: Colors.black.withOpacity(0.55),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.66,
                child: Material(
                  color: Colors.white,
                  child: _PostCard(
                    doc: doc,
                    isAdmin: _isAdmin,
                    isPostActive: true,
                    isVisible: true,
                    onZoomingChanged: (z) {
                      if (mounted) {
                        setState(() => _isZooming = z);
                      }
                    },
                    onDeleted: _handleDeleted,
                  ),
                ),
              ),
            ),
            if (_list.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _PostNavArrow(
                  icon: Icons.chevron_left,
                  enabled: _activePostIndex > 0,
                  onTap: _activePostIndex > 0 ? _goPrevPost : null,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _PostNavArrow(
                  icon: Icons.chevron_right,
                  enabled: _activePostIndex < _list.length - 1,
                  onTap: _activePostIndex < _list.length - 1 ? _goNextPost : null,
                ),
              ),
            ],
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                splashRadius: 22,
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    final bool useDesktopWebLayout =
        kIsWeb && mq.size.width >= 1000 && mq.size.height >= 600;

    if (useDesktopWebLayout) {
      return _buildWebContent(context);
    }

    return _buildMobileContent(context);
  }
}

class _PostNavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _PostNavArrow({
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.white.withOpacity(0.95),
        shape: const CircleBorder(),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, size: 26),
          color: enabled ? Colors.black87 : Colors.black26,
          onPressed: enabled ? onTap : null,
        ),
      ),
    );
  }
}

class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

// ───────────────────────── 개별 게시물 카드 ─────────────────────────

class _PostCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isAdmin;
  final bool isPostActive;
  final bool isVisible;
  final ValueChanged<bool> onZoomingChanged;
  final ValueChanged<String> onDeleted;

  const _PostCard({
    super.key,
    required this.doc,
    required this.isAdmin,
    required this.isPostActive,
    required this.isVisible,
    required this.onZoomingChanged,
    required this.onDeleted,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  late Map<String, dynamic> data;

  late List<_MediaEntry> _media;
  late List<String> _spinImages;

  bool _liked = false;
  StreamSubscription? _likeSub;

  bool _prefetchingImages = false;
  bool _imagesPrefetched = false;

  bool _spinPrefetched = false;

  double? _webMediaHeight;

  @override
  void initState() {
    super.initState();
    data = Map<String, dynamic>.from(widget.doc.data());
    _extractMedia();
    _setupLikeWatcher();
  }

  @override
  void didUpdateWidget(covariant _PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      data = Map<String, dynamic>.from(widget.doc.data());
      _extractMedia();
      _webMediaHeight = null;

      _prefetchingImages = false;
      _imagesPrefetched = false;
    }
  }

  void _extractMedia() {
    final media = <_MediaEntry>[];

    // 1) images / imageUrl
    final vImgs = data['images'];
    if (vImgs is List && vImgs.isNotEmpty) {
      for (final raw in vImgs) {
        final u = raw.toString();
        if (u.isEmpty) continue;

        if (_isVideoUrl(u)) {
          media.add(_MediaEntry.video(url: u));
        } else {
          media.add(_MediaEntry.image(url: u));
        }
      }
    } else {
      final one = (data['imageUrl'] ?? '').toString();
      if (one.isNotEmpty) {
        if (_isVideoUrl(one)) {
          media.add(_MediaEntry.video(url: one));
        } else {
          media.add(_MediaEntry.image(url: one));
        }
      }
    }

    // 2) videos 배열
    final vVideos = data['videos'];
    if (vVideos is List && vVideos.isNotEmpty) {
      for (final raw in vVideos) {
        final u = raw.toString();
        if (u.isEmpty) continue;
        media.add(_MediaEntry.video(url: u));
      }
    }

    _media = media;

    final vSpin = data['spinImages'];
    if (vSpin is List && vSpin.isNotEmpty) {
      _spinImages =
          vSpin.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } else {
      _spinImages = const [];
    }

    _spinPrefetched = false;
  }

  void _setupLikeWatcher() {
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

  String _humanizeDate(dynamic createdAt) {
    if (createdAt is! Timestamp) return '';
    final dt = createdAt.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    String _2(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}.${_2(dt.month)}.${_2(dt.day)}';
  }

  Future<void> _onEdit() async {
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
            .get();
        if (snap.exists) {
          setState(() {
            data = Map<String, dynamic>.from(snap.data()!);
            _extractMedia();
            _imagesPrefetched = false;
            _prefetchingImages = false;
            _webMediaHeight = null;
          });
        }
      } catch (_) {}
    }
  }

  Future<bool> _showDeleteConfirmSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0x22000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const Icon(Icons.delete_outline,
                    size: 40, color: Colors.black87),
                const SizedBox(height: 12),
                const Text(
                  '게시물을 삭제할까요?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '삭제 후에는 되돌릴 수 없어요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side:
                          const BorderSide(color: Color(0xFFE0E0E0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('삭제'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result == true;
  }

  Future<void> _onDelete() async {
    final ok = await _showDeleteConfirmSheet();
    if (!ok) return;

    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.doc.id)
          .delete();
      if (!mounted) return;
      widget.onDeleted(widget.doc.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }

  Future<void> _toggleLike() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }
    final prev = _liked;
    setState(() => _liked = !prev);
    try {
      await LikeService.instance.toggle(widget.doc.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _liked = prev);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('좋아요 처리 실패: $e')),
      );
    }
  }

  void _openSpinViewer() {
    if (_spinImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 360° 이미지가 없습니다.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpinViewerPage(
          images: _spinImages,
          title: (data['title'] ?? '').toString(),
        ),
      ),
    );
  }

  Widget _titleHeartAnd360(String title) {
    final hasSpin = _spinImages.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title.isNotEmpty ? title : '제목 없음',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasSpin)
            IconButton(
              splashRadius: 22,
              tooltip: '360° 보기',
              onPressed: _openSpinViewer,
              icon: const Icon(Icons.threesixty),
            ),
          IconButton(
            splashRadius: 22,
            onPressed: _toggleLike,
            icon: Icon(
              _liked ? Icons.favorite : Icons.favorite_border,
              color: _liked ? Colors.redAccent : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLayout(
      BuildContext context, {
        required Widget mediaSection,
        required String brandKor,
        required String brandEng,
        required String logoUrl,
        required dynamic createdAt,
        required String title,
        required String desc,
        required String itemCode,
      }) {
    final displayKor = brandKor.isEmpty ? 'ALL' : brandKor;
    final dateStr = _humanizeDate(createdAt);

    Future<void> _openBrandProfile() async {
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
            logo = (m['logoUrl'] ?? logo).toString();
          }
        } catch (_) {}
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BrandProfilePage(
            brandKor: displayKor,
            brandEng: nameEng,
            isAdmin: widget.isAdmin,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final mediaWidth = totalWidth * 3 / 5;

        final mediaHeight = (_webMediaHeight ?? 400.0);
        final cardHeight = mediaHeight + 32;

        return SizedBox(
          height: cardHeight,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: mediaWidth,
                  height: mediaHeight,
                  child: mediaSection,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: mediaHeight,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '브랜드',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: _openBrandProfile,
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 11,
                                  backgroundColor: const Color(0x11000000),
                                  backgroundImage: logoUrl.isNotEmpty
                                      ? NetworkImage(logoUrl)
                                      : null,
                                  child: logoUrl.isEmpty
                                      ? const Icon(
                                    Icons.store,
                                    size: 14,
                                    color: Colors.black54,
                                  )
                                      : null,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    displayKor,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            title.isNotEmpty ? title : '제목 없음',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: desc.isNotEmpty
                                ? SingleChildScrollView(
                              child: Text(
                                desc,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            )
                                : const SizedBox.shrink(),
                          ),

// 🔥 관리자 전용 품번 표시
                          if (widget.isAdmin && itemCode.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  '품번',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SelectableText(
                                  itemCode,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (_spinImages.isNotEmpty)
                                InkWell(
                                  onTap: _openSpinViewer,
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.threesixty,
                                            size: 20,
                                            color: Colors.black87),
                                        SizedBox(height: 2),
                                        Text(
                                          '360도',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              IconButton(
                                splashRadius: 22,
                                onPressed: _toggleLike,
                                icon: Icon(
                                  _liked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color:
                                  _liked ? Colors.redAccent : Colors.black,
                                ),
                              ),
                              if (widget.isAdmin)
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert,
                                      color: Colors.black87, size: 20),
                                  onSelected: (v) {
                                    if (v == 'edit') _onEdit();
                                    if (v == 'delete') _onDelete();
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                        value: 'edit', child: Text('수정')),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        '삭제',
                                        style:
                                        TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    final logoUrl =
    (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString();

    final itemCode = (data['itemCode'] ?? '').toString();

    // 사진 / 동영상 영역 위젯 만들기
    Widget mediaSection;
    if (!widget.isVisible) {
      mediaSection = const _SkeletonMediaPlaceholder();
    } else if (_media.isNotEmpty) {
      mediaSection = _MediaCarousel(
        key: ValueKey('${widget.doc.id}_media'),
        media: _media,
        onAnyZoomingChanged: widget.onZoomingChanged,
        onHeightResolved: (h) {
          if (!mounted) return;
          if (!kIsWeb) return;
          if (_webMediaHeight == null || (_webMediaHeight! - h).abs() > 1) {
            setState(() => _webMediaHeight = h);
          }
        },
      );
    } else {
      mediaSection = Container(
        height: 260,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: line)),
        ),
        child: const Icon(Icons.broken_image, size: 40),
      );
    }

    final mq = MediaQuery.of(context);
    final bool useDesktopWebLayout =
        kIsWeb && mq.size.width >= 1000 && mq.size.height >= 600;

    if (useDesktopWebLayout) {
      return _buildWebLayout(
        context,
        mediaSection: mediaSection,
        brandKor: brandKor,
        brandEng: brandEng,
        logoUrl: logoUrl,
        createdAt: createdAt,
        title: title,
        desc: desc,
        itemCode: itemCode,
      );
    }

    // 모바일 + 작은 웹창: 세로 레이아웃
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
        mediaSection,
        _titleHeartAnd360(title),

        // 🔥 모바일에서도 관리자만 품번 표시
        if (widget.isAdmin && itemCode.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                const Text(
                  '품번',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  itemCode,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

        if (desc.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
            child: Text(
              desc,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          )
        else
          const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0x11000000)),
      ],
    );
  }
}

// ───────────────────────── 스켈레톤 + 웨이브 ─────────────────────────

class _SkeletonMediaPlaceholder extends StatelessWidget {
  const _SkeletonMediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    const Color line = Color(0xFFE6E6E6);
    final width = MediaQuery.of(context).size.width;

    const double minSize = 220;
    const double maxSize = 520;
    final double size = width.clamp(minSize, maxSize).toDouble();

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: _Shimmer(
        child: Center(
          child: Container(
            width: size,
            height: size,
            color: const Color(0xFFDDDDDD),
          ),
        ),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = const Color(0xFFCCCCCC);
    final midColor = const Color(0xFFE4E4E4);
    final highlight = const Color(0xFFF8F8F8);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final double t = _ctrl.value;

        const double dx = 2.2;
        const double dy = 1.5;

        final Alignment begin = Alignment(
          -dx + 2 * dx * t,
          -dy + 2 * dy * t,
        );
        final Alignment end = Alignment(
          dx + 2 * dx * t,
          dy + 2 * dy * t,
        );

        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: begin,
              end: end,
              colors: [baseColor, highlight, midColor],
              stops: const [0.15, 0.5, 0.85],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ───────────────────────── 이미지/비디오 캐러셀 ─────────────────────────

class _MediaCarousel extends StatefulWidget {
  final List<_MediaEntry> media;
  final ValueChanged<bool> onAnyZoomingChanged;

  // 웹 카드 높이를 맞추기 위해, 계산된 이미지 높이를 알려주는 콜백
  final ValueChanged<double>? onHeightResolved;

  const _MediaCarousel({
    super.key,
    required this.media,
    required this.onAnyZoomingChanged,
    this.onHeightResolved,
  });

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  final PageController _pager = PageController();
  int _index = 0;
  bool _pageZooming = false;

  double? _aspectRatio; // width / height

  @override
  void initState() {
    super.initState();

    if (widget.media.isNotEmpty) {
      final firstImage = widget.media.firstWhere(
            (m) => m.kind == _MediaKind.image,
        orElse: () => widget.media.first,
      );
      if (firstImage.kind == _MediaKind.image) {
        _loadAspectRatio(firstImage.url);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _prefetchNeighbor(0);
        _prefetchNeighbor(1);
      });
    }
  }

  void _prefetchNeighbor(int idx) {
    if (idx < 0 || idx >= widget.media.length) return;

    final m = widget.media[idx];
    if (m.kind != _MediaKind.image) return;

    final provider = m.imageProvider;
    if (provider == null) return;

    precacheImage(provider, context).catchError((_) {});
  }

  void _loadAspectRatio(String url) {
    final img = Image.network(_optimizeCloudinaryUrl(url));
    final stream = img.image.resolve(const ImageConfiguration());
    stream.addListener(
      ImageStreamListener((info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          setState(() {
            _aspectRatio = w / h;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _handleZoomChanged(bool z) {
    if (_pageZooming == z) return;
    setState(() => _pageZooming = z);
    widget.onAnyZoomingChanged(z);
  }

  void _goPrev() {
    if (_index <= 0) return;
    _pager.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _goNext() {
    if (_index >= widget.media.length - 1) return;
    _pager.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMulti = widget.media.length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final screenH = MediaQuery.of(context).size.height;

        const double minHeight = 220;
        const double maxHeight = 520;

        double height;

        if (_aspectRatio != null) {
          final raw = width / _aspectRatio!;
          final maxAllowed = screenH * 0.9;
          height = raw.clamp(minHeight, maxAllowed);
        } else {
          final rawHeight = width;
          height = rawHeight.clamp(minHeight, maxHeight);
        }

        if (kIsWeb && widget.onHeightResolved != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onHeightResolved!(height);
          });
        }

        final canPrev = _index > 0;
        final canNext = _index < widget.media.length - 1;

        final imageStack = ScrollConfiguration(
          behavior: const _DragEverywhere(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  controller: _pager,
                  physics: _pageZooming
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (i) {
                    setState(() => _index = i);

                    final m = widget.media[i];
                    if (m.kind == _MediaKind.image) {
                      _loadAspectRatio(m.url);
                    }

                    _prefetchNeighbor(i);
                    _prefetchNeighbor(i + 1);
                    _prefetchNeighbor(i - 1);
                  },
                  itemCount: widget.media.length,
                  itemBuilder: (_, i) {
                    final m = widget.media[i];

                    if (m.kind == _MediaKind.video) {
                      return _VideoPlayerView(
                        url: m.url,
                        onZoomingChanged: _handleZoomChanged,
                      );
                    }

                    return _TwoFingerZoomImage(
                      url: m.url,
                      imageProvider: m.imageProvider!,
                      onZoomingChanged: _handleZoomChanged,
                    );
                  },
                ),

                // 좌우 화살표: 웹에서만
                if (hasMulti && !_pageZooming && kIsWeb)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _MediaArrowButton(
                      icon: Icons.chevron_left,
                      enabled: canPrev,
                      onTap: canPrev ? _goPrev : null,
                    ),
                  ),
                if (hasMulti && !_pageZooming && kIsWeb)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _MediaArrowButton(
                      icon: Icons.chevron_right,
                      enabled: canNext,
                      onTap: canNext ? _goNext : null,
                    ),
                  ),

                // 오른쪽 위 "현재/전체"
                if (hasMulti)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.media.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                // 점 인디케이터: 웹일 때는 사진 안에
                if (hasMulti && kIsWeb)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _Dots(
                        controller: _pager,
                        count: widget.media.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        if (kIsWeb) {
          return imageStack;
        }

        // 모바일: 아래에 점 따로
        return Column(
          children: [
            imageStack,
            if (hasMulti)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _Dots(
                  controller: _pager,
                  count: widget.media.length,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MediaArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _MediaArrowButton({
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.black.withOpacity(0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: enabled ? Colors.white : Colors.white54,
          onPressed: enabled ? onTap : null,
        ),
      ),
    );
  }
}
// ───────────────────────── 비디오 플레이어 ─────────────────────────

// ───────────────────────── 비디오 플레이어 (심플/안정 버전) ─────────────────────────

class _VideoPlayerView extends StatefulWidget {
  final String url;
  final ValueChanged<bool>? onZoomingChanged; // 지금은 안 쓰지만 시그니처 유지

  const _VideoPlayerView({
    required this.url,
    this.onZoomingChanged,
  });

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));

    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      await _controller.initialize();
      if (!mounted) return;

      // 🔇 항상 무음 + 🔁 무한 반복
      _controller
        ..setVolume(0.0)
        ..setLooping(true);

      // ✅ 초기화 직후 자동 재생
      await _controller.play();

      setState(() {
        _initialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(
        child: Icon(
          Icons.error_outline,
          size: 40,
          color: Colors.black54,
        ),
      );
    }

    if (!_initialized) {
      return const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.black,
          ),
        ),
      );
    }

    // 🔥 완전 기본 패턴: 비율맞춰서 딱 맞게 출력 + 자동재생
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio == 0
          ? 16 / 9
          : _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }
}


// ───────────────────────── 두 손가락 확대 이미지 ─────────────────────────

class _TwoFingerZoomImage extends StatefulWidget {
  final String url;
  final ImageProvider imageProvider;
  final ValueChanged<bool> onZoomingChanged;

  const _TwoFingerZoomImage({
    required this.url,
    required this.imageProvider,
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
    // 💻 웹: 줌 없이 가벼운 이미지 위젯만 사용 → 스크롤 버벅임 감소
    if (kIsWeb) {
      return Center(
        child: WebImage(
          url: widget.url,
          fit: BoxFit.contain,
        ),
      );
    }

    // 📱 앱: 기존 두 손가락 줌 유지
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
                child: Image(
                  image: widget.imageProvider,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
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
                color: active
                    ? Colors.black
                    : const Color.fromRGBO(0, 0, 0, 0.25),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

// ───────────────────────── 360도 뷰어 ─────────────────────────

class SpinViewerPage extends StatelessWidget {
  final List<String> images;
  final String title;

  const SpinViewerPage({
    super.key,
    required this.images,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final displayTitle = title.isEmpty ? '360° 보기' : '$title - 360°';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Text(
          displayTitle,
          style: const TextStyle(color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SpinImageViewer(
        images: images,
      ),
    );
  }
}

class SpinImageViewer extends StatefulWidget {
  final List<String> images;
  final double dragSensitivity;

  const SpinImageViewer({
    super.key,
    required this.images,
    this.dragSensitivity = 2,
  });

  @override
  State<SpinImageViewer> createState() => _SpinImageViewerState();
}

class _SpinImageViewerState extends State<SpinImageViewer> {
  int _index = 0;
  double _accumulatedDx = 0;

  bool _startedPrecache = false;
  bool _readyFirstFrame = false;
  int _loadedCount = 0;

  final List<Image> _frames = [];

  double _progress = 0.0;
  int _percent = 0;
  Timer? _timer;

  bool _zoomed = false;
  Offset _panOffset = Offset.zero;

  bool get _hasImages => widget.images.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedPrecache && _hasImages) {
      _startedPrecache = true;
      _initFirstFrameAndPrecache();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initFirstFrameAndPrecache() async {
    _frames.clear();
    _loadedCount = 0;
    _progress = 0;
    _percent = 0;
    setState(() {});

    final total = widget.images.length;
    if (total == 0) return;

    final firstUrl = _optimizeCloudinaryUrl(widget.images.first);
    final firstImg = Image.network(
      firstUrl,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      cacheWidth: 640,
    );
    _frames.add(firstImg);
    _readyFirstFrame = true;
    _loadedCount = 1;
    _setProgress(total == 0 ? 1.0 : (_loadedCount / total));

    if (mounted) setState(() {});

    for (int i = 0; i < total; i++) {
      final url = _optimizeCloudinaryUrl(widget.images[i]);
      final img = Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: 640,
      );

      if (i < _frames.length) {
        _frames[i] = img;
      } else {
        _frames.add(img);
      }

      precacheImage(img.image, context).then((_) {
        if (!mounted) return;
        _loadedCount++;
        _setProgress(total == 0 ? 1.0 : (_loadedCount / total));
      }).catchError((_) {
        if (!mounted) return;
        _loadedCount++;
        _setProgress(total == 0 ? 1.0 : (_loadedCount / total));
      });
    }
  }

  void _setProgress(double v) {
    v = v.clamp(0.0, 1.0);
    _progress = v;
    final target = (v * 100).round();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_percent == target) {
        t.cancel();
      } else {
        setState(() {
          if (_percent < target) {
            _percent++;
          } else {
            _percent--;
          }
        });
      }
    });

    if (mounted) setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_hasImages) return;

    if (_zoomed) {
      setState(() {
        _panOffset += details.delta;
      });
      return;
    }

    final frameCount = _frames.length;
    if (frameCount == 0) return;

    _accumulatedDx += details.delta.dx;

    if (_accumulatedDx.abs() >= widget.dragSensitivity) {
      final dir = _accumulatedDx > 0 ? -1 : 1;
      _accumulatedDx = 0;

      setState(() {
        _index = (_index + dir) % frameCount;
        if (_index < 0) _index += frameCount;
      });
    }
  }

  void _toggleZoom() {
    setState(() {
      if (_zoomed) {
        _zoomed = false;
        _panOffset = Offset.zero;
      } else {
        _zoomed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasImages) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Colors.black,
        ),
      );
    }

    if (!_readyFirstFrame || _frames.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.black,
          ),
        ),
      );
    }

    final frameCount = _frames.length;
    final img = _frames[_index.clamp(0, frameCount - 1)];

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onTap: _toggleZoom,
      child: Container(
        color: Colors.white,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.8,
            heightFactor: 0.8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Transform.translate(
                    offset: _zoomed ? _panOffset : Offset.zero,
                    child: AnimatedScale(
                      scale: _zoomed ? 2.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: img,
                    ),
                  ),
                ),
                if (_percent < 100)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '로드 중... ${_percent}%',
                        style: const TextStyle(
                            color: Colors.black, fontSize: 10),
                      ),
                    ),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.threesixty,
                            color: Colors.black, size: 16),
                        SizedBox(width: 4),
                        Text(
                          '드래그 회전 / 확대 시 드래그로 이동',
                          style: TextStyle(
                              color: Colors.black, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 스크롤 속도 살짝 올리는 물리
class _FasterScrollPhysics extends ClampingScrollPhysics {
  const _FasterScrollPhysics({super.parent});

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * 1.6);
  }

  @override
  _FasterScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FasterScrollPhysics(parent: buildParent(ancestor));
  }
}

// ───────────────────────── 브랜드 헤더 (모바일용) ─────────────────────────

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
    final dateStr = (createdAt is Timestamp)
        ? _humanize((createdAt as Timestamp).toDate())
        : '';
    final displayKor = brandKor.isEmpty ? 'ALL' : brandKor;

    Future<void> _openBrandProfile(BuildContext ctx) async {
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
            logo = (m['logoUrl'] ?? logo).toString();
          }
        } catch (_) {}
      }

      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => BrandProfilePage(
            brandKor: displayKor,
            brandEng: nameEng,
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
                  backgroundImage:
                  (logoUrl.isNotEmpty) ? NetworkImage(logoUrl) : null,
                  child: (logoUrl.isEmpty)
                      ? const Icon(Icons.store, color: Colors.black54)
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayKor,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    if (dateStr.isNotEmpty)
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
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
              if (isAdmin)
                const PopupMenuItem(value: 'edit', child: Text('수정')),
              if (isAdmin)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    '삭제',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
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
