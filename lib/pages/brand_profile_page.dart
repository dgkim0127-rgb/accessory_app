// lib/pages/brand_profile_page.dart ✅ 웹 반응형(최대 6열) + 4:5 비율 + 중앙 정렬 적용
import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../widgets/post_overlay.dart';
import '../utils/cloudinary_image_utils.dart';

class BrandProfilePage extends StatefulWidget {
  final String brandKor;
  final String brandEng;
  final bool isAdmin;
  final String? initialCategory;

  const BrandProfilePage({
    super.key,
    required this.brandKor,
    required this.brandEng,
    this.isAdmin = false,
    this.initialCategory,
  });

  @override
  State<BrandProfilePage> createState() => _BrandProfilePageState();
}

class _BrandProfilePageState extends State<BrandProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  static const _tabs = <_CatTab>[
    _CatTab(label: '전체', code: null, icon: Icons.grid_view_rounded),
    _CatTab(label: '반지', code: 'ring', asset: 'assets/icons/ring.png'),
    _CatTab(label: '목걸이', code: 'necklace', asset: 'assets/icons/necklace.png'),
    _CatTab(label: '팔찌', code: 'bracelet', asset: 'assets/icons/bracelet.png'),
    _CatTab(label: '귀걸이', code: 'earring', asset: 'assets/icons/earring.png'),
    _CatTab(label: '기타', code: 'acc', icon: Icons.more_horiz_rounded),
  ];

  int _indexForCode(String? code) {
    final i = _tabs.indexWhere((t) => t.code == code);
    return i < 0 ? 0 : i;
  }

  bool get _isAllBrand => widget.brandKor.trim().toUpperCase() == 'ALL';

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _indexForCode(widget.initialCategory),
    );
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _initial() {
    if (_isAllBrand) return 'A';
    final eng = widget.brandEng.trim();
    if (eng.isNotEmpty) return eng.characters.first.toUpperCase();
    final kor = widget.brandKor.trim();
    return kor.isNotEmpty ? kor.characters.first.toUpperCase() : 'B';
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('posts');
    if (!_isAllBrand) {
      q = q.where('brand', isEqualTo: widget.brandKor);
    }
    return q;
  }

  Future<int> _count({String? cat}) async {
    final base = _baseQuery();
    if (cat == null) {
      final agg = await base.count().get();
      return agg.count ?? 0;
    }
    final qNew = base.where('categories', arrayContains: cat);
    final qOld = base.where('category', isEqualTo: cat);
    final s1 = await qNew.get();
    final s2 = await qOld.get();
    final ids = <String>{};
    for (final d in s1.docs) ids.add(d.id);
    for (final d in s2.docs) ids.add(d.id);
    return ids.length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final line = theme.dividerTheme.color ?? Colors.transparent;
    final appBarTitle = _isAllBrand ? 'ALL COLLECTIONS' : widget.brandEng.toUpperCase();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: cs.onSurface),
        title: Text(
          appBarTitle,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: cs.onSurface,
            letterSpacing: 1.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: line),
        ),
      ),
      body: Center(
        // 🌟 웹에서 너무 넓게 퍼지지 않도록 최대 너비 제한
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── 프로필 헤더 ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Row(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _initial(),
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: cs.onSurface),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isAllBrand ? '전체 컬렉션' : widget.brandKor,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            FutureBuilder<int>(
                              future: _count(cat: null),
                              builder: (context, snap) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'TOTAL ${snap.data ?? 0}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface.withOpacity(0.5),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 아이콘 + 숫자 탭바 ──
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: line.withOpacity(0.5), width: 0.5),
                      bottom: BorderSide(color: line, width: 0.5),
                    ),
                  ),
                  child: FutureBuilder<List<int>>(
                    future: Future.wait<int>(_tabs.map((t) => _count(cat: t.code))),
                    builder: (context, snap) {
                      final counts = snap.data ?? List.filled(_tabs.length, 0);

                      return TabBar(
                        controller: _tab,
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        labelColor: cs.onSurface,
                        unselectedLabelColor: cs.onSurface.withOpacity(0.25),
                        indicatorColor: cs.onSurface,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: Colors.transparent,
                        tabs: List.generate(_tabs.length, (idx) {
                          final t = _tabs[idx];
                          final isSel = _tab.index == idx;
                          final count = counts[idx];

                          return Tab(
                            height: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (t.asset != null)
                                  Image.asset(
                                    t.asset!,
                                    width: 24,
                                    height: 24,
                                    color: isSel ? cs.onSurface : cs.onSurface.withOpacity(0.25),
                                  )
                                else
                                  Icon(t.icon, size: 24),
                                const SizedBox(height: 6),
                                Text(
                                  '$count',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSel ? FontWeight.w900 : FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        onTap: (index) => setState(() {}),
                      );
                    },
                  ),
                ),
              ),

              // ── 반응형 그리드 컨텐츠 ──
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tab,
                  children: _tabs.map((t) => _BrandFixedGrid(
                    brandKor: widget.brandKor,
                    category: t.code,
                    theme: theme,
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatTab {
  final String label;
  final String? code;
  final IconData? icon;
  final String? asset;
  const _CatTab({required this.label, required this.code, this.icon, this.asset});
}

// 🌟 반응형 3~6열 4:5 비율 고정 그리드 위젯
class _BrandFixedGrid extends StatelessWidget {
  final String brandKor;
  final String? category;
  final ThemeData theme;

  const _BrandFixedGrid({required this.brandKor, this.category, required this.theme});

  bool get _isAllBrand => brandKor.trim().toUpperCase() == 'ALL';

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection('posts');
    if (!_isAllBrand) q = q.where('brand', isEqualTo: brandKor);
    return q;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _docsStream() {
    final base = _baseQuery();
    if (category == null) return base.snapshots().map((snap) => snap.docs);
    final s1 = base.where('categories', arrayContains: category).snapshots();
    return s1.asyncMap((a) async {
      final b = await base.where('category', isEqualTo: category).get();
      final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in a.docs) map[d.id] = d;
      for (final d in b.docs) map[d.id] = d;
      return map.values.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _docsStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onSurface));
        }
        final docs = snap.data ?? [];
        if (docs.isEmpty) {
          return Center(child: Text('게시물이 없습니다.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))));
        }

        int _sortVal(Map<String, dynamic> m) {
          final sk = m['sortKey'];
          if (sk is int) return sk;
          final ts = m['createdAt'];
          return ts is Timestamp ? ts.millisecondsSinceEpoch : 0;
        }
        final sorted = [...docs]..sort((a, b) => _sortVal(b.data()).compareTo(_sortVal(a.data())));

        // 🌟 화면 너비에 따라 열 개수를 계산하는 LayoutBuilder
        return LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;

              // 600px 미만(모바일): 3열
              // 900px 미만: 4열
              // 1200px 미만: 5열
              // 그 이상: 6열
              int crossAxisCount = 3;
              if (width >= 1200) {
                crossAxisCount = 6;
              } else if (width >= 900) {
                crossAxisCount = 5;
              } else if (width >= 600) {
                crossAxisCount = 4;
              }

              return GridView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 60),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 1.5,
                  crossAxisSpacing: 1.5,
                  childAspectRatio: 0.8, // ✅ 4:5 비율 고정
                ),
                itemCount: sorted.length,
                itemBuilder: (ctx, i) {
                  final doc = sorted[i];
                  final d = doc.data();
                  final img = buildThumbUrl((d['thumbUrl'] ?? d['imageUrl'] ?? '').toString());

                  return InkWell(
                    onTap: () => PostOverlay.show(context, docs: sorted, startIndex: i),
                    child: CachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 100),
                      placeholder: (_, __) => Container(color: isDark ? const Color(0xFF2A2F38) : const Color(0xFFE0E0E0)),
                      errorWidget: (_, __, ___) => Container(color: isDark ? const Color(0xFF1A1D22) : Colors.black12),
                    ),
                  );
                },
              );
            }
        );
      },
    );
  }
}