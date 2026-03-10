// lib/pages/home_page.dart ✅ 최신 코드
// - 게시물 순서: 최신순 유지
// - 수정한 게시물은 sortKey 기준으로 최상단
// - 랜덤으로 바뀌는 건 게시물 "모양(높이)"만
// - 새로고침/재진입 시 높이만 다시 랜덤 배정
// - 상세 오버레이는 기존 그대로 사용

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../core/announcement_popup_manager.dart';
import '../utils/cloudinary_image_utils.dart';
import '../widgets/post_overlay.dart';

const int _kInitialMobile = 20;
const int _kInitialWeb = 40;

const int _kMoreMobile = 40;
const int _kMoreWeb = 80;

class HomePage extends StatefulWidget {
  final bool isAdmin;
  const HomePage({super.key, this.isAdmin = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const int _kBase = 10000;

  late final PageController _pageCtrl = PageController(
    viewportFraction: kIsWeb ? 0.7 : 0.85,
    initialPage: _kBase,
  );

  final ScrollController _scrollCtrl = ScrollController();

  Timer? _timer;
  final Set<String> _prefetchedThumbs = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _adminDocs = [];
  Timer? _saveDebounce;
  bool _forcedServerOnce = false;

  bool _isReorderMode = false;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  DocumentSnapshot<Map<String, dynamic>>? _last;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;

  final ValueNotifier<int> _currentPageNotifier = ValueNotifier<int>(0);

  // ✅ 새로고침/재진입 시 카드 높이만 다시 랜덤
  final Map<String, double> _liveTileHeights = {};

  int get _initialPageSize => kIsWeb ? _kInitialWeb : _kInitialMobile;
  int get _morePageSize => kIsWeb ? _kMoreWeb : _kMoreMobile;

  @override
  void initState() {
    super.initState();
    _startAuto();
    _scrollCtrl.addListener(_onScroll);
    _pageCtrl.addListener(() {
      if (_pageCtrl.page != null) {
        _currentPageNotifier.value = _pageCtrl.page!.round() % 4;
      }
    });
    _resetAndLoad();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _timer?.cancel();
    _pageCtrl.dispose();
    _scrollCtrl.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Query<Map<String, dynamic>> _baseQuery() {
    return FirebaseFirestore.instance
        .collection('posts')
        .orderBy('sortKey', descending: true);
  }

  Future<void> _resetAndLoad() async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = true;
      _docs.clear();
      _adminDocs.clear();
      _last = null;
      _liveTileHeights.clear(); // ✅ 모양만 다시 랜덤
    });

    if (!_forcedServerOnce) {
      _forcedServerOnce = true;
      _baseQuery()
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .catchError((_) {});
    }

    await _loadInitial();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadInitial() async {
    try {
      try {
        final cacheQs = await _baseQuery()
            .limit(_initialPageSize)
            .get(const GetOptions(source: Source.cache));

        final cacheItems = cacheQs.docs;
        if (mounted && cacheItems.isNotEmpty) {
          setState(() {
            _docs
              ..clear()
              ..addAll(cacheItems);
            _last = cacheItems.last;
            _hasMore = cacheItems.length >= _initialPageSize;
          });
          _afterDocsChanged();
        }
      } catch (_) {}

      final serverQs = await _baseQuery()
          .limit(_initialPageSize)
          .get(const GetOptions(source: Source.serverAndCache));
      final items = serverQs.docs;

      if (!mounted) return;

      setState(() {
        _docs
          ..clear()
          ..addAll(items);
        _last = items.isNotEmpty ? items.last : null;
        _hasMore = items.length >= _initialPageSize;
      });

      _afterDocsChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('불러오기 실패: $e')));
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    if (_last == null) return;

    setState(() => _loadingMore = true);

    try {
      final qs = await _baseQuery()
          .startAfterDocument(_last!)
          .limit(_morePageSize)
          .get();
      final items = qs.docs;

      if (!mounted) return;

      setState(() {
        _docs.addAll(items);
        _last = items.isNotEmpty ? items.last : _last;
        _hasMore = items.length >= _morePageSize;
        _loadingMore = false;
      });

      _afterDocsChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('추가 로드 실패: $e')));
    }
  }

  void _afterDocsChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchThumbs(_docs);
      _seedMissingSortKeys(_docs);
    });

    if (widget.isAdmin) {
      _adminDocs = List.of(_docs);
    }
  }

  Future<void> _refresh() async {
    await _resetAndLoad();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  void _startAuto() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageCtrl.hasClients) return;
      final current = (_pageCtrl.page ?? _kBase.toDouble()).round();
      _pageCtrl.animateToPage(
        current + 1,
        duration: const Duration(milliseconds: 800),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  String _pickThumbRaw(Map<String, dynamic> data) {
    final a = (data['thumbUrl'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    final b = (data['thumbnailUrl'] ?? '').toString().trim();
    if (b.isNotEmpty) return b;
    final list = data['thumbImages'];
    if (list is List && list.isNotEmpty) {
      final u = (list.first ?? '').toString().trim();
      if (u.isNotEmpty) return u;
    }
    return (data['imageUrl'] ?? '').toString().trim();
  }

  String _pickSliderRaw(Map<String, dynamic> data) {
    final m = (data['mediumUrl'] ?? '').toString().trim();
    if (m.isNotEmpty) return m;
    final list = data['mediumImages'];
    if (list is List && list.isNotEmpty) {
      final u = (list.first ?? '').toString().trim();
      if (u.isNotEmpty) return u;
    }
    final raw = (data['imageUrl'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    return (data['thumbnailUrl'] ?? '').toString().trim();
  }

  void _prefetchThumbs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (!mounted) return;
    for (final d in docs.take(12)) {
      final raw = _pickThumbRaw(d.data());
      if (raw.isEmpty) continue;
      final url = buildThumbUrl(raw);
      if (_prefetchedThumbs.add(url)) {
        precacheImage(CachedNetworkImageProvider(url), context);
      }
    }
  }

  Future<void> _seedMissingSortKeys(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (!widget.isAdmin) return;

    final batch = FirebaseFirestore.instance.batch();
    bool hasWork = false;

    for (final d in docs) {
      final data = d.data();
      if (data['sortKey'] == null) {
        int base = DateTime.now().millisecondsSinceEpoch;
        final createdAt = data['createdAt'];
        if (createdAt is Timestamp) base = createdAt.millisecondsSinceEpoch;
        batch.update(d.reference, {'sortKey': base});
        hasWork = true;
      }
    }

    if (!hasWork) return;
    try {
      await batch.commit();
    } catch (_) {}
  }

  List<_SlideItem> _buildSlidesFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return _buildPlaceholderSlides();

    int tsOf(dynamic v) => v is Timestamp ? v.millisecondsSinceEpoch : 0;

    QueryDocumentSnapshot<Map<String, dynamic>>? popular;
    QueryDocumentSnapshot<Map<String, dynamic>>? recent;
    QueryDocumentSnapshot<Map<String, dynamic>>? updated;

    int bestCreated = -1;
    for (final d in docs) {
      final c = tsOf(d.data()['createdAt']);
      if (c > bestCreated) {
        bestCreated = c;
        recent = d;
      }
    }
    recent ??= docs.first;

    int maxLikes = -1;
    for (final d in docs) {
      final likes = d.data()['likes'] ?? 0;
      final likesInt = likes is int ? likes : int.tryParse(likes.toString()) ?? 0;
      if (likesInt > maxLikes) {
        maxLikes = likesInt;
        popular = d;
      }
    }
    popular ??= recent;

    int bestUpdated = -1;
    for (final d in docs) {
      int t = tsOf(d.data()['updatedAt']);
      if (t == 0) t = tsOf(d.data()['createdAt']);
      if (t > bestUpdated) {
        bestUpdated = t;
        updated = d;
      }
    }
    updated ??= recent;

    final pool = docs.take(min(20, docs.length)).toList();
    final randomDoc = pool[Random().nextInt(pool.length)];

    String pickSliderImage(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final raw = _pickSliderRaw(d.data());
      if (raw.isEmpty) return '';
      return buildSliderUrl(raw);
    }

    String titleOf(QueryDocumentSnapshot<Map<String, dynamic>> d, String fallback) {
      final t = (d.data()['title'] ?? '').toString().trim();
      return t.isNotEmpty ? t : fallback;
    }

    return [
      _SlideItem(
        label: titleOf(popular!, '인기 컬렉션'),
        subLabel: '인기 컬렉션 · 지금 가장 핫한 주얼리',
        imageUrl: pickSliderImage(popular),
        doc: popular,
      ),
      _SlideItem(
        label: titleOf(recent!, '신상 컬렉션'),
        subLabel: '신상 컬렉션 · 방금 올라온 새로운 디자인',
        imageUrl: pickSliderImage(recent),
        doc: recent,
      ),
      _SlideItem(
        label: titleOf(updated!, '업데이트'),
        subLabel: '업데이트 · 새롭게 단장한 게시물',
        imageUrl: pickSliderImage(updated),
        doc: updated,
      ),
      _SlideItem(
        label: titleOf(randomDoc, '추천 컬렉션'),
        subLabel: '추천 컬렉션 · 르네가 추천하는 주얼리',
        imageUrl: pickSliderImage(randomDoc),
        doc: randomDoc,
      ),
    ];
  }

  List<_SlideItem> _buildPlaceholderSlides() => const [
    _SlideItem(label: '인기 컬렉션', subLabel: '인기 게시물', imageUrl: '', doc: null),
    _SlideItem(label: '신상 컬렉션', subLabel: '최근 게시물', imageUrl: '', doc: null),
    _SlideItem(label: '업데이트', subLabel: '수정된 게시물', imageUrl: '', doc: null),
    _SlideItem(label: '추천 컬렉션', subLabel: '랜덤 게시물', imageUrl: '', doc: null),
  ];

  void _scheduleSaveSortKeys(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> ordered) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final batch = FirebaseFirestore.instance.batch();
        for (int i = 0; i < ordered.length; i++) {
          batch.update(ordered[i].reference, {'sortKey': now - i});
        }
        await batch.commit();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('순서 저장됨')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('순서 저장 실패: $e')));
        }
      }
    });
  }

  // ✅ 순서는 안 바꾸고, 카드 높이만 랜덤
  double _heightForDoc(String docId) {
    if (_liveTileHeights.containsKey(docId)) {
      return _liveTileHeights[docId]!;
    }

    final value = 180.0 + Random().nextInt(180);
    _liveTileHeights[docId] = value;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = theme.scaffoldBackgroundColor;
    final skeletonColor =
    isDark ? const Color(0xFF2A2F38) : const Color(0xFFE0E0E0);
    final errorBgColor =
    isDark ? const Color(0xFF1A1D22) : Colors.black12;

    return AnnouncementPopupManager(
      child: Scaffold(
        backgroundColor: bgColor,
        floatingActionButton: widget.isAdmin
            ? FloatingActionButton.extended(
          onPressed: () => setState(() => _isReorderMode = !_isReorderMode),
          elevation: 4,
          icon: Icon(_isReorderMode ? Icons.check : Icons.swap_vert, size: 20),
          label: Text(
            _isReorderMode ? '정렬 완료' : '순서 변경',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
        )
            : null,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            final double slideHeight =
            kIsWeb ? min(width * 0.5, 500.0) : width * 1.0;

            final slides =
            _docs.isNotEmpty ? _buildSlidesFromDocs(_docs) : _buildPlaceholderSlides();
            final int slideCount = slides.isEmpty ? 1 : slides.length;

            final slider = SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 10),
                child: Column(
                  children: [
                    SizedBox(
                      width: width,
                      height: slideHeight,
                      child: Listener(
                        onPointerDown: (_) => _timer?.cancel(),
                        onPointerUp: (_) => _startAuto(),
                        onPointerCancel: (_) => _startAuto(),
                        child: ScrollConfiguration(
                          behavior: const _DragScrollBehavior(),
                          child: PageView.builder(
                            controller: _pageCtrl,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (context, raw) {
                              final idx = raw % slideCount;
                              final item = slides[idx];

                              return AnimatedBuilder(
                                animation: _pageCtrl,
                                builder: (context, child) {
                                  double pageOffset = 0.0;
                                  double scaleValue = 1.0;

                                  if (_pageCtrl.position.haveDimensions) {
                                    pageOffset =
                                        (_pageCtrl.page ?? raw.toDouble()) - raw;
                                    scaleValue = (1 - (pageOffset.abs() * 0.12))
                                        .clamp(0.85, 1.0);
                                  }

                                  return Center(
                                    child: Transform.scale(
                                      scale: scaleValue,
                                      child: GestureDetector(
                                        onTap: () {
                                          if (item.doc != null && _docs.isNotEmpty) {
                                            final startIndex = _docs.indexWhere(
                                                  (d) => d.id == item.doc!.id,
                                            );

                                            if (startIndex >= 0) {
                                              PostOverlay.show(
                                                context,
                                                docs: _docs,
                                                startIndex: startIndex,
                                              );
                                            } else {
                                              PostOverlay.show(
                                                context,
                                                docs: [item.doc!],
                                                startIndex: 0,
                                              );
                                            }
                                          }
                                        },
                                        child: ConstrainedBox(
                                          constraints:
                                          const BoxConstraints(maxWidth: 800),
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(24),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isDark
                                                      ? Colors.black54
                                                      : Colors.black.withOpacity(0.15),
                                                  blurRadius: 20,
                                                  offset: const Offset(0, 10),
                                                )
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(24),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  if (item.imageUrl.isNotEmpty)
                                                    Transform.translate(
                                                      offset: Offset(
                                                          pageOffset * width * 0.2, 0),
                                                      child: CachedNetworkImage(
                                                        imageUrl: item.imageUrl,
                                                        fit: BoxFit.cover,
                                                        fadeInDuration:
                                                        const Duration(milliseconds: 150),
                                                        placeholder: (_, __) =>
                                                            ColoredBox(color: skeletonColor),
                                                        errorWidget: (_, __, ___) =>
                                                            ColoredBox(color: errorBgColor),
                                                      ),
                                                    )
                                                  else
                                                    ColoredBox(color: skeletonColor),
                                                  Positioned(
                                                    left: 16,
                                                    right: 16,
                                                    bottom: 20,
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(16),
                                                      child: BackdropFilter(
                                                        filter: ImageFilter.blur(
                                                            sigmaX: 12, sigmaY: 12),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 20, vertical: 16),
                                                          decoration: BoxDecoration(
                                                            color: isDark
                                                                ? Colors.black.withOpacity(0.3)
                                                                : Colors.white.withOpacity(0.2),
                                                            border: Border.all(
                                                              color: Colors.white.withOpacity(0.3),
                                                              width: 0.5,
                                                            ),
                                                          ),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Row(
                                                                children: [
                                                                  Container(
                                                                    width: 6,
                                                                    height: 6,
                                                                    decoration: BoxDecoration(
                                                                      color: isDark
                                                                          ? Colors.white
                                                                          : Colors.black,
                                                                      shape: BoxShape.circle,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(width: 8),
                                                                  Text(
                                                                    item.subLabel,
                                                                    style: TextStyle(
                                                                      color: isDark
                                                                          ? Colors.white
                                                                          .withOpacity(0.9)
                                                                          : Colors.black87,
                                                                      fontSize: 13,
                                                                      fontWeight: FontWeight.w700,
                                                                      letterSpacing: 0.5,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              const SizedBox(height: 6),
                                                              Text(
                                                                item.label,
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  color: isDark
                                                                      ? Colors.white
                                                                      : Colors.black,
                                                                  fontSize: 26,
                                                                  fontWeight: FontWeight.w900,
                                                                  letterSpacing: -0.5,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ValueListenableBuilder<int>(
                      valueListenable: _currentPageNotifier,
                      builder: (context, currentIndex, child) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(slideCount, (index) {
                            final isActive = index == currentIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: isActive ? 24 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? (isDark ? Colors.white : Colors.black)
                                    : (isDark ? Colors.white24 : Colors.black26),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );

            final int crossAxisCount =
            (!kIsWeb || width < 600) ? 2 : (width >= 1200 ? 5 : 4);

            Widget gridSliver;
            final bool showMasonry = !widget.isAdmin || !_isReorderMode;

            if (_loading && _docs.isEmpty) {
              gridSliver = SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 10,
                  childCount: 6,
                  itemBuilder: (context, i) {
                    final randomHeight = 180.0 + Random(i).nextInt(160);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: randomHeight,
                          decoration: BoxDecoration(
                            color: skeletonColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          margin: const EdgeInsets.only(right: 40),
                          decoration: BoxDecoration(
                            color: skeletonColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            } else if (_docs.isEmpty) {
              gridSliver = SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('게시물이 없습니다.', style: theme.textTheme.bodyMedium),
                ),
              );
            } else if (!showMasonry) {
              final list = _adminDocs;
              gridSliver = SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                sliver: SliverToBoxAdapter(
                  child: ReorderableGridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: list.length,
                    dragWidgetBuilder: (index, child) =>
                        _JellyDragProxy(child: child),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        final item = list.removeAt(oldIndex);
                        list.insert(newIndex, item);
                        _docs
                          ..clear()
                          ..addAll(list);
                      });
                      _scheduleSaveSortKeys(list);
                    },
                    itemBuilder: (context, i) {
                      final d = list[i];
                      final raw = _pickThumbRaw(d.data());
                      final img = raw.isEmpty
                          ? 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800'
                          : buildThumbUrl(raw);

                      return ReorderableDelayedDragStartListener(
                        index: i,
                        key: ValueKey(d.id),
                        child: _FadedTile(
                          onTap: () =>
                              PostOverlay.show(context, docs: list, startIndex: i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  ColoredBox(color: skeletonColor),
                              errorWidget: (_, __, ___) =>
                                  ColoredBox(color: errorBgColor),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            } else {
              gridSliver = SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 24,
                  crossAxisSpacing: 12,
                  childCount: _docs.length,
                  itemBuilder: (context, i) {
                    final data = _docs[i].data();
                    final docId = _docs[i].id;

                    final raw = _pickThumbRaw(data);
                    final img = raw.isEmpty
                        ? 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800'
                        : buildThumbUrl(raw);

                    final title = (data['title'] ?? '').toString();
                    final randomHeight = _heightForDoc(docId);

                    return _FadedTile(
                      onTap: () =>
                          PostOverlay.show(context, docs: _docs, startIndex: i),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: randomHeight,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: isDark ? Colors.black45 : Colors.black12,
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.cover,
                                fadeInDuration:
                                const Duration(milliseconds: 150),
                                placeholder: (_, __) =>
                                    ColoredBox(color: skeletonColor),
                                errorWidget: (_, __, ___) =>
                                    ColoredBox(color: errorBgColor),
                              ),
                            ),
                          ),
                          if (title.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurface,
                                  height: 1.3,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              color: isDark ? Colors.white : Colors.black,
              backgroundColor: bgColor,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                slivers: [
                  slider,
                  gridSliver,
                  if (_loadingMore)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  if (!_hasMore && _docs.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            '마지막 게시물입니다.',
                            style: TextStyle(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SlideItem {
  final String label;
  final String subLabel;
  final String imageUrl;
  final QueryDocumentSnapshot<Map<String, dynamic>>? doc;
  const _SlideItem({
    required this.label,
    required this.subLabel,
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
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutBack,
        scale: _down ? 0.96 : 1.0,
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

class _JellyDragProxy extends StatefulWidget {
  final Widget child;
  const _JellyDragProxy({required this.child});

  @override
  State<_JellyDragProxy> createState() => _JellyDragProxyState();
}

class _JellyDragProxyState extends State<_JellyDragProxy>
    with TickerProviderStateMixin {
  late final AnimationController _popC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.12)
      .animate(CurvedAnimation(parent: _popC, curve: Curves.easeOutBack));

  late final AnimationController _wiggleC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  )..repeat(reverse: true);

  late final Animation<double> _wiggle = Tween<double>(begin: -0.017, end: 0.017)
      .animate(CurvedAnimation(parent: _wiggleC, curve: Curves.easeInOut));

  @override
  void dispose() {
    _popC.dispose();
    _wiggleC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_popC, _wiggleC]),
      builder: (_, __) {
        return Transform.rotate(
          angle: _wiggle.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Material(
              color: Colors.transparent,
              elevation: 12,
              shadowColor: Colors.black.withOpacity(0.28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}