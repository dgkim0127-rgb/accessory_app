// lib/pages/liked_user_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/post_overlay.dart';

class _CatTab {
  final String label;
  final String? code; // null=전체
  const _CatTab(this.label, this.code);
}

const _tabs = <_CatTab>[
  _CatTab('전체', null),
  _CatTab('반지', 'ring'),
  _CatTab('목걸이', 'necklace'),
  _CatTab('팔찌', 'bracelet'),
  _CatTab('귀걸이', 'earring'),
  _CatTab('기타', 'acc'),
];

class LikedUserDetailPage extends StatefulWidget {
  final String userUid;     // 대상 회원 uid
  final String userIdLabel; // 이메일 앞부분 등 화면 표기
  const LikedUserDetailPage({
    super.key,
    required this.userUid,
    required this.userIdLabel,
  });

  @override
  State<LikedUserDetailPage> createState() => _LikedUserDetailPageState();
}

class _LikedUserDetailPageState extends State<LikedUserDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String? _brandFilter; // null=전체

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // 좋아요 postId 스트림
  // 1) 상위 likes(userUid==X) → postId 필드
  // 2) 비어 있으면 legacy(users/{uid}/likes) 문서ID
  // ─────────────────────────────────────────────────────────────
  Stream<List<String>> _favPostIdsTop() {
    return FirebaseFirestore.instance
        .collection('likes')
        .where('userUid', isEqualTo: widget.userUid)
        .snapshots()
        .map((s) => s.docs
        .map((d) => (d.data()['postId'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList());
  }

  Stream<List<String>> _favPostIdsLegacy() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userUid)
        .collection('likes')
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }

  Stream<List<String>> _brandNamesStream() {
    return FirebaseFirestore.instance
        .collection('brands')
        .orderBy('nameKor')
        .snapshots()
        .map((s) => s.docs
        .map((d) => (d.data()['nameKor'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList());
  }

  // 게시물 로드(존재하는 것만, 최신순)
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchPostsByIds(
      List<String> ids) async {
    if (ids.isEmpty) return [];
    final posts = FirebaseFirestore.instance.collection('posts');

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _chunk(
        List<String> chunk) async {
      final qs = await posts
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.serverAndCache));
      return qs.docs;
    }

    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += 10) {
      final end = (i + 10 > ids.length) ? ids.length : i + 10;
      out.addAll(await _chunk(ids.sublist(i, end)));
    }

    // 최신순
    out.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      final da = ta is Timestamp ? ta.toDate() : DateTime(1970);
      final db = tb is Timestamp ? tb.toDate() : DateTime(1970);
      return db.compareTo(da);
    });

    // (주의) 고아 좋아요 정리는 '본인' 화면에서만 수행
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null && me == widget.userUid) {
      final existingIds = out.map((d) => d.id).toSet();
      final missing = ids.where((id) => !existingIds.contains(id)).toList();

      // top-level 정리
      if (missing.isNotEmpty) {
        final topLikes = FirebaseFirestore.instance.collection('likes');
        for (final pid in missing) {
          try { await topLikes.doc('${pid}_$me').delete(); } catch (_) {}
        }
      }
      // legacy 정리
      if (missing.isNotEmpty) {
        final likesCol = FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userUid)
            .collection('likes');
        for (final pid in missing) {
          try { await likesCol.doc(pid).delete(); } catch (_) {}
        }
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          '${widget.userIdLabel} 님이 좋아요한 게시물',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: StreamBuilder<List<String>>(
        stream: _brandNamesStream(),
        builder: (context, brandsSnap) {
          final brandsFromCollection = brandsSnap.data ?? const <String>[];

          // 1) top-level likes 먼저 감시
          return StreamBuilder<List<String>>(
            stream: _favPostIdsTop(),
            builder: (context, topIdsSnap) {
              final topIds = topIdsSnap.data ?? const <String>[];

              // 2) top-level 비어 있으면 legacy로 fallback
              final Stream<List<String>> idsStream = (topIdsSnap.hasData && topIds.isNotEmpty)
                  ? Stream.value(topIds)
                  : _favPostIdsLegacy();

              return StreamBuilder<List<String>>(
                stream: idsStream,
                builder: (context, idsSnap) {
                  final ids = idsSnap.data ?? const <String>[];

                  return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    future: _fetchPostsByIds(ids),
                    builder: (context, postSnap) {
                      final allDocs = postSnap.data ?? const [];
                      final isLoading = postSnap.connectionState == ConnectionState.waiting;

                      // 게시물에서 등장한 브랜드도 수집
                      final brandsFromPosts = {
                        for (final d in allDocs)
                          (d.data()['brand'] ?? '').toString().trim()
                      }..removeWhere((e) => e.isEmpty);

                      final brandNames = {...brandsFromCollection, ...brandsFromPosts}.toList()
                        ..sort((a, b) => a.compareTo(b));

                      final brandCount = <String, int>{};
                      for (final b in brandNames) {
                        brandCount[b] = 0;
                      }
                      for (final d in allDocs) {
                        final b = (d.data()['brand'] ?? '').toString();
                        if (b.isEmpty) continue;
                        brandCount[b] = (brandCount[b] ?? 0) + 1;
                      }

                      int countCat([String? cat]) => allDocs.where((d) {
                        final c = (d.data()['category'] ?? '').toString();
                        final b = (d.data()['brand'] ?? '').toString();
                        final okBrand = _brandFilter == null ? true : (b == _brandFilter);
                        final okCat = cat == null ? true : (c == cat);
                        return okBrand && okCat;
                      }).length;

                      final allCount = countCat(null);

                      return DefaultTabController(
                        length: _tabs.length,
                        child: CustomScrollView(
                          slivers: [
                            // 카테고리 집계 2줄
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                                child: Column(
                                  children: [
                                    Row(children: [
                                      _countCell('전체', allCount),
                                      _countCell('반지', countCat('ring')),
                                      _countCell('목걸이', countCat('necklace')),
                                    ]),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      _countCell('팔찌', countCat('bracelet')),
                                      _countCell('귀걸이', countCat('earring')),
                                      _countCell('기타', countCat('acc')),
                                    ]),
                                  ],
                                ),
                              ),
                            ),

                            // 브랜드 필터 칩
                            if (brandNames.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('브랜드',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16)),
                                      const SizedBox(height: 10),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: _brandChip(
                                                label: 'ALL',
                                                count: allCount,
                                                selected: _brandFilter == null,
                                                onTap: () => setState(() => _brandFilter = null),
                                              ),
                                            ),
                                            ...brandNames.map((b) => Padding(
                                              padding: const EdgeInsets.only(right: 6),
                                              child: _brandChip(
                                                label: b,
                                                count: brandCount[b] ?? 0,
                                                selected: _brandFilter == b,
                                                onTap: () => setState(() {
                                                  _brandFilter = (_brandFilter == b) ? null : b;
                                                }),
                                              ),
                                            )),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // 탭바
                            SliverToBoxAdapter(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: line),
                                    bottom: BorderSide(color: line),
                                  ),
                                ),
                                child: TabBar(
                                  controller: _tab,
                                  labelColor: Colors.black,
                                  unselectedLabelColor: Colors.black54,
                                  indicatorColor: Colors.black,
                                  tabs: _tabs
                                      .map((t) => Tab(
                                    child: Text(
                                      t.label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13),
                                    ),
                                  ))
                                      .toList(),
                                ),
                              ),
                            ),

                            // 탭 컨텐츠 → 3열 그리드
                            SliverFillRemaining(
                              child: TabBarView(
                                controller: _tab,
                                children: _tabs.map((t) {
                                  final filtered = allDocs.where((d) {
                                    final c = (d.data()['category'] ?? '').toString();
                                    final b = (d.data()['brand'] ?? '').toString();
                                    final okBrand = _brandFilter == null ? true : (b == _brandFilter);
                                    final okCat = t.code == null ? true : (c == t.code);
                                    return okBrand && okCat;
                                  }).toList();

                                  if (isLoading) {
                                    return const Center(
                                      child: CircularProgressIndicator(strokeWidth: 1.5),
                                    );
                                  }

                                  if (filtered.isEmpty) {
                                    return ListView(
                                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                                      children: const [_EmptyListPlaceholder()],
                                    );
                                  }

                                  return _LikedPostGrid(docs: filtered);
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _countCell(String label, int n) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _brandChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          border: Border.all(color: const Color(0xffe6e6e6)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                color: selected ? Colors.white70 : Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ 3열 그리드 + 썸네일 탭 시 PostOverlay
class _LikedPostGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _LikedPostGrid({required this.docs});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(3, 6, 3, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // 3열
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        childAspectRatio: 1, // 정사각
      ),
      itemCount: docs.length,
      itemBuilder: (_, i) {
        final d = docs[i];
        final m = d.data();
        final img = (m['imageUrl'] ?? '').toString();

        return InkWell(
          onTap: () => PostOverlay.show(context, docs: docs, startIndex: i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: img.isNotEmpty
                ? Image.network(
              img,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _BrokenThumb(),
              frameBuilder: (_, child, frame, __) =>
              frame == null ? const _ShimmerThumb() : child,
            )
                : const _BrokenThumb(),
          ),
        );
      },
    );
  }
}

// 플레이스홀더
class _BrokenThumb extends StatelessWidget {
  const _BrokenThumb();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF1F1F1),
      child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.black26)),
    );
  }
}

class _ShimmerThumb extends StatelessWidget {
  const _ShimmerThumb();
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFFF6F6F6));
  }
}

class _EmptyListPlaceholder extends StatelessWidget {
  const _EmptyListPlaceholder();

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line)),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
      child: const SizedBox(
        height: 120,
        child: Center(
          child: Text('표시할 게시물이 없습니다.',
              style: TextStyle(fontSize: 14, color: Colors.black54)),
        ),
      ),
    );
  }
}
