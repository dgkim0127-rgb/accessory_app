// lib/pages/home_page.dart  ✅ 최종: 홈 스스로도 팝업 매니저로 감쌈
import 'dart:async';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/loading.dart';
import '../widgets/post_overlay.dart';
import '../core/announcement_popup_manager.dart'; // ← 추가

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
  List<_SlideItem> _slides = [];

  @override
  void initState() {
    super.initState();
    _loadSlides();
    _startAuto();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _loadSlides();
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
      if (!_pageCtrl.hasClients || _slides.isEmpty) return;
      final next = (_pageCtrl.page ?? _kBase.toDouble()).round() + 1;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _firstOf(Query<Map<String, dynamic>> q) async {
    try {
      final s = await q.limit(1).get();
      if (s.docs.isEmpty) return null;
      return s.docs.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSlides() async {
    final fs = FirebaseFirestore.instance;

    final popularDoc =
    await _firstOf(fs.collection('posts').orderBy('likes', descending: true));
    final recentDoc =
    await _firstOf(fs.collection('posts').orderBy('createdAt', descending: true));

    QueryDocumentSnapshot<Map<String, dynamic>>? featuredDoc;
    try {
      final f = await fs
          .collection('posts')
          .where('featured', isEqualTo: true)
          .limit(1)
          .get();
      if (f.docs.isNotEmpty) featuredDoc = f.docs.first;
    } catch (_) {}

    List<QueryDocumentSnapshot<Map<String, dynamic>>> pool = [];
    try {
      final p = await fs.collection('posts').limit(20).get();
      pool = p.docs;
    } catch (_) {}

    final seen = <String>{};
    final out = <_SlideItem>[];

    void addDoc(QueryDocumentSnapshot<Map<String, dynamic>>? d, String label) {
      if (d == null) return;
      if (seen.add(d.id)) out.add(_SlideItem.fromDoc(d, label));
    }

    addDoc(popularDoc, '인기 게시물');
    addDoc(recentDoc, '최신 게시물');
    addDoc(featuredDoc, '추천 게시물');

    if (pool.isNotEmpty) {
      final remain = pool.where((d) => !seen.contains(d.id)).toList();
      if (remain.isNotEmpty) {
        final r = remain[Random().nextInt(remain.length)];
        addDoc(r, '랜덤 게시물');
      }
    }

    if (out.length < 4) {
      try {
        final more = await fs
            .collection('posts')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();
        for (final d in more.docs) {
          if (out.length >= 4) break;
          if (seen.add(d.id)) out.add(_SlideItem.fromDoc(d, '최신 게시물'));
        }
      } catch (_) {}
    }

    while (out.length < 4) {
      out.add(_SlideItem(
        id: 'dummy_${out.length}',
        title: '샘플 게시물',
        imageUrl:
        'https://images.unsplash.com/photo-1526170375885-4d8ecf77b99f?w=800',
        label: '샘플 게시물',
      ));
    }

    final preview = LoadingOverlay.consumePreview();
    if (preview != null && preview.urls.isNotEmpty) {
      out.insert(
        0,
        _SlideItem(
          id: 'preview_loading_photo',
          title: preview.caption ?? '로딩 중 봤던 게시물',
          imageUrl: preview.urls.first,
          label: '로딩에서 봤던 사진',
        ),
      );
    }

    if (!mounted) return;
    setState(() => _slides = out.take(5).toList());
  }

  Future<void> _openSlide(String postId) async {
    if (postId == 'preview_loading_photo') return;
    try {
      final qs = await FirebaseFirestore.instance
          .collection('posts')
          .where(FieldPath.documentId, isEqualTo: postId)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('게시물을 찾을 수 없습니다.')));
        return;
      }
      await PostOverlay.show(context, docs: qs.docs, startIndex: 0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('불러오기 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final square = width * 0.7;

    final slider = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(
          child: _slides.isEmpty
              ? const SizedBox(
              height: 220, child: Center(child: CircularProgressIndicator()))
              : SizedBox(
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
                    if (_slides.isEmpty) return const SizedBox.shrink();
                    final idx = raw % _slides.length;
                    final item = _slides[idx];

                    return Center(
                      child: SizedBox(
                        width: square,
                        height: square,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(0),
                          child: GestureDetector(
                            onTap: () => _openSlide(item.id),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  item.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: Colors.grey[200]),
                                ),
                                Positioned(
                                  left: 12,
                                  top: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    color: item.label == '로딩에서 봤던 사진'
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

    final grid = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('게시물이 없습니다. 아래로 당겨서 새로고침')),
          );
        }
        final docs = snap.data!.docs;

        return SliverPadding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, i) {
                final data = docs[i].data();
                final img = (data['imageUrl'] ??
                    'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800')
                    .toString();
                return _FadedTile(
                  onTap: () => PostOverlay.show(context, docs: docs, startIndex: i),
                  child: Image.network(img, fit: BoxFit.cover),
                );
              },
              childCount: docs.length,
            ),
          ),
        );
      },
    );

    // 🔒 홈 자체에서도 팝업 매니저로 한 번 더 감싸서 반드시 뜨게 함
    return AnnouncementPopupManager(
      // 필요하면 잠깐 켜서 확인
      // forceTest: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: RefreshIndicator(
          onRefresh: _refresh,
          displacement: 36,
          color: Colors.black,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [slider, grid],
          ),
        ),
      ),
    );
  }
}

class _SlideItem {
  final String id;
  final String title;
  final String imageUrl;
  final String label;
  _SlideItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.label,
  });

  factory _SlideItem.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      String label,
      ) {
    final m = doc.data();
    return _SlideItem(
      id: doc.id,
      title: (m['title'] ?? '제목 없음').toString(),
      imageUrl: (m['imageUrl'] ??
          'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800')
          .toString(),
      label: label,
    );
  }
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
