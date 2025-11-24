// lib/pages/home_page.dart  ✅ 최종 (A안: 360px 썸네일 + Cloudinary 강한 압축)
// - 슬라이더와 그리드가 같은 Firestore 스냅샷을 사용 → 중복 쿼리 제거
// - 스냅샷 도착하는 순간, 인기/최신/추천/랜덤 슬라이드 이미지 즉시 표시
// - 로딩 전에는 슬라이더/그리드 둘 다 스켈레톤 박스만 보여줌 (하얀 화면 X)
// - 썸네일: Cloudinary 360x360, f_auto + q_auto:low (강한 압축)

import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/loading.dart';
import '../widgets/post_overlay.dart';
import '../core/announcement_popup_manager.dart';

// Firestore에서 한 번에 가져올 게시물 수
const int _kMaxDocsMobile = 60;
const int _kMaxDocsWeb = 120;

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _kBase = 10000;

  late final PageController _pageCtrl = PageController(
    viewportFraction: 1.0,
    initialPage: _kBase,
  );

  Timer? _timer;

  // 로딩 화면에서 봤던 사진 (있으면 슬라이더 첫 장으로 사용)
  _SlideItem? _previewSlide;

  // 프리캐시한 썸네일 목록
  final Set<String> _prefetchedThumbs = {};

  @override
  void initState() {
    super.initState();

    final preview = LoadingOverlay.consumePreview();
    if (preview != null && preview.urls.isNotEmpty) {
      _previewSlide = _SlideItem(
        label: '로딩에서 봤던 사진',
        imageUrl: _optimizeCloudinaryUrl(preview.urls.first),
        doc: null, // 단일 URL만 있는 경우 → 탭해도 아무 동작 안 함
      );
    }

    _startAuto();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  void _startAuto() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageCtrl.hasClients) return;
      final current = (_pageCtrl.page ?? _kBase.toDouble()).round();
      _pageCtrl.animateToPage(
        current + 1,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOut,
      );
    });
  }

  // 슬라이드 탭 시 동작
  Future<void> _openSlide(_SlideItem item) async {
    // 로딩에서 본 사진, doc 없는 플레이스홀더는 탭해도 아무 동작 없음
    if (item.doc == null) return;

    try {
      await PostOverlay.show(
        context,
        docs: [item.doc!],
        startIndex: 0,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('불러오기 실패: $e')));
    }
  }

  // 썸네일 프리캐시 (첫 화면에 보일 가능성 높은 9개만)
  void _prefetchThumbs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (!mounted) return;
    final targets = docs.take(9).toList();

    for (final d in targets) {
      final data = d.data();
      final raw =
      (data['thumbnailUrl'] ?? data['imageUrl'] ?? '').toString().trim();
      if (raw.isEmpty) continue;

      final url = _optimizeCloudinaryUrl(raw);
      if (_prefetchedThumbs.contains(url)) continue;
      _prefetchedThumbs.add(url);

      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  // Firestore docs 로부터 인기/최신/추천/랜덤 슬라이드 구성
  List<_SlideItem> _buildSlidesFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final list = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    if (list.isEmpty) {
      return _buildPlaceholderSlides();
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? popular;
    QueryDocumentSnapshot<Map<String, dynamic>>? recent;
    QueryDocumentSnapshot<Map<String, dynamic>>? featured;
    QueryDocumentSnapshot<Map<String, dynamic>>? randomDoc;

    // 최신: 이미 createdAt desc 로 정렬된 상태라고 가정 → 첫 번째
    recent = list.first;

    // 인기: likes 가 가장 큰 것
    int maxLikes = -1;
    for (final d in list) {
      final data = d.data();
      final likes = (data['likes'] ?? 0);
      final likesInt =
      likes is int ? likes : int.tryParse(likes.toString()) ?? 0;
      if (likesInt > maxLikes) {
        maxLikes = likesInt;
        popular = d;
      }
      // 추천: featured == true 중 첫 번째
      if (featured == null && data['featured'] == true) {
        featured = d;
      }
    }

    // 랜덤: 앞쪽 20개 정도에서 랜덤 선택
    final pool = list.take(min(20, list.length)).toList();
    randomDoc = pool[Random().nextInt(pool.length)];

    final out = <_SlideItem>[];

    void addDoc(QueryDocumentSnapshot<Map<String, dynamic>>? d, String label) {
      if (d == null) return;
      final data = d.data();
      final raw = (data['thumbnailUrl'] ??
          data['imageUrl'] ??
          'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800')
          .toString();
      final img = _optimizeCloudinaryUrl(raw);

      out.add(
        _SlideItem(
          label: label,
          imageUrl: img,
          doc: d,
        ),
      );
    }

    // 0. 로딩에서 본 사진이 있으면 맨 앞에
    if (_previewSlide != null) {
      out.add(_previewSlide!);
    }

    // 1. 인기 / 최신 / 추천 / 랜덤
    addDoc(popular ?? recent, '인기 게시물');
    addDoc(recent, '최신 게시물');
    addDoc(featured ?? recent, '추천 게시물');
    addDoc(randomDoc ?? recent, '랜덤 게시물');

    // 중복 제거 + 최대 5개까지만
    final seenIds = <String>{};
    final unique = <_SlideItem>[];

    for (final s in out) {
      final id = s.doc?.id ?? 'no_doc_${s.label}_${s.imageUrl}';
      if (seenIds.add(id)) {
        unique.add(s);
      }
    }

    if (unique.isEmpty) {
      return _buildPlaceholderSlides();
    }

    return unique.take(5).toList();
  }

  // Firestore 데이터가 아직 없을 때 보여줄 기본 슬라이드 (색 박스 + 라벨)
  List<_SlideItem> _buildPlaceholderSlides() {
    return [
      _SlideItem(label: '인기 게시물', imageUrl: '', doc: null),
      _SlideItem(label: '최신 게시물', imageUrl: '', doc: null),
      _SlideItem(label: '추천 게시물', imageUrl: '', doc: null),
      _SlideItem(label: '랜덤 게시물', imageUrl: '', doc: null),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnnouncementPopupManager(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('posts')
              .orderBy('createdAt', descending: true)
              .limit(kIsWeb ? _kMaxDocsWeb : _kMaxDocsMobile)
              .snapshots(),
          builder: (context, snap) {
            final width = MediaQuery.of(context).size.width;
            final square = width * 0.7;

            // ───────── 슬라이드 데이터 구성 ─────────
            final docs = snap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final hasData = snap.hasData && docs.isNotEmpty;

            if (hasData) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _prefetchThumbs(docs);
              });
            }

            final slides =
            hasData ? _buildSlidesFromDocs(docs) : _buildPlaceholderSlides();

            // ───────── 슬라이더 Sliver ─────────
            final slider = SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Center(
                  child: SizedBox(
                    width: width,
                    height: square,
                    child: Listener(
                      onPointerDown: (_) => _timer?.cancel(),
                      onPointerUp: (_) => _startAuto(),
                      child: ScrollConfiguration(
                        behavior: const _DragScrollBehavior(),
                        child: PageView.builder(
                          controller: _pageCtrl,
                          physics: const PageScrollPhysics(),
                          pageSnapping: true,
                          itemBuilder: (context, raw) {
                            final len = slides.isEmpty ? 1 : slides.length;
                            final idx = slides.isEmpty ? 0 : raw % len;
                            final item = slides[idx];

                            return Center(
                              child: SizedBox(
                                width: square,
                                height: square,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(0),
                                  child: GestureDetector(
                                    onTap: () => _openSlide(item),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (item.imageUrl.isEmpty)
                                        // Firestore 데이터 오기 전: 단순 색 박스
                                          Container(
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFF111111),
                                                  Color(0xFF222222),
                                                ],
                                              ),
                                            ),
                                          )
                                        else
                                          CachedNetworkImage(
                                            imageUrl: item.imageUrl,
                                            fit: BoxFit.cover,
                                            fadeInDuration:
                                            const Duration(milliseconds: 80),
                                            placeholder: (_, __) =>
                                                Container(color: Colors.grey[200]),
                                            errorWidget: (_, __, ___) => Container(
                                              color: Colors.grey[200],
                                              child: const Icon(
                                                Icons.broken_image_outlined,
                                                color: Colors.black38,
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          left: 12,
                                          top: 12,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            color:
                                            item.label == '로딩에서 봤던 사진'
                                                ? Colors.black87
                                                : Colors.black54,
                                            child: Text(
                                              item.label,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );

            // ───────── 그리드 Sliver ─────────
            int crossAxisCount;
            if (!kIsWeb) {
              crossAxisCount = 3;
            } else {
              if (width >= 1200) {
                crossAxisCount = 6;
              } else if (width >= 900) {
                crossAxisCount = 5;
              } else if (width >= 600) {
                crossAxisCount = 4;
              } else {
                crossAxisCount = 3;
              }
            }

            Widget gridSliver;

            if (!hasData) {
              // 데이터 오기 전: 스켈레톤 그리드
              const skeletonCount = 12;
              gridSliver = SliverPadding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, i) {
                      return const ColoredBox(
                        color: Color(0xFFE0E0E0),
                      );
                    },
                    childCount: skeletonCount,
                  ),
                ),
              );
            } else if (docs.isEmpty) {
              gridSliver = const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('게시물이 없습니다. 아래로 당겨서 새로고침')),
              );
            } else {
              gridSliver = SliverPadding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, i) {
                      final data = docs[i].data();
                      final raw = (data['thumbnailUrl'] ??
                          data['imageUrl'] ??
                          'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800')
                          .toString();
                      final img = _optimizeCloudinaryUrl(raw);

                      return _FadedTile(
                        onTap: () =>
                            PostOverlay.show(context, docs: docs, startIndex: i),
                        child: CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          fadeInDuration:
                          const Duration(milliseconds: 80),
                          placeholder: (_, __) =>
                          const ColoredBox(color: Color(0xFFE0E0E0)),
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: Colors.black12,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.black38,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              displacement: 36,
              color: Colors.black,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  slider,
                  gridSliver,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// 슬라이더 아이템
class _SlideItem {
  final String label;
  final String imageUrl; // '' 이면 플레이스홀더
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;

  _SlideItem({
    required this.label,
    required this.imageUrl,
    required this.doc,
  });
}

class _FadedTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _FadedTile({required this.child, required this.onTap});

  @override
  State<_FadedTile> createState() => _FadedTileState();
}

class _FadedTileState extends State<_FadedTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _pressed ? 0.78 : 1.0,
        child: widget.child,
      ),
    );
  }
}

class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

// ───────────────────────── Cloudinary URL 최적화 ─────────────────────────
// 썸네일용: 360x360, 자동 포맷 + 강한 품질 압축(q_auto:low)
String _optimizeCloudinaryUrl(String url) {
  const marker = '/upload/';
  final idx = url.indexOf(marker);
  if (idx == -1) return url;

  final before = url.substring(0, idx + marker.length);
  final after = url.substring(idx + marker.length);

  // 이미 f_auto/q_auto 등이 붙어 있으면 그대로 사용
  if (after.startsWith('f_auto') || after.startsWith('q_auto')) {
    return url;
  }

  // 🔥 강한 압축: q_auto:low + 360x360 정사각 썸네일
  return '$before'
      'f_auto,q_auto:low,w_360,h_360,c_fill,g_auto/'
      '$after';
}
