// lib/pages/brand_profile_page.dart
// ✅ 브랜드 아이콘 → 이니셜 원
// ✅ 카테고리 탭(목걸이, 반지 등)은 아이콘 없이 텍스트만
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/post_overlay.dart';

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
    _CatTab(label: '전체', code: null),
    _CatTab(label: '반지', code: 'ring'),
    _CatTab(label: '목걸이', code: 'necklace'),
    _CatTab(label: '팔찌', code: 'bracelet'),
    _CatTab(label: '귀걸이', code: 'earring'),
    _CatTab(label: '기타', code: 'acc'),
  ];

  int _indexForCode(String? code) {
    final i = _tabs.indexWhere((t) => t.code == code);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _indexForCode(widget.initialCategory),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<int> _count({String? cat}) async {
    Query<Map<String, dynamic>> base =
    FirebaseFirestore.instance.collection('posts');

    if (widget.brandKor.trim().toUpperCase() != 'ALL') {
      base = base.where('brand', isEqualTo: widget.brandKor);
    }
    if (cat != null) base = base.where('category', isEqualTo: cat);

    final agg = await base.count().get();
    return agg.count ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    final isAll = widget.brandKor.trim().toUpperCase() == 'ALL';
    final titleKor = isAll ? 'ALL' : widget.brandKor;
    final titleEng = isAll ? '' : widget.brandEng;

    // ✅ 이니셜 생성 (영문 우선)
    String _initial() {
      if (isAll) return 'A';
      final eng = widget.brandEng.trim();
      if (eng.isNotEmpty) return eng.characters.first.toUpperCase();
      final kor = widget.brandKor.trim();
      return kor.isNotEmpty ? kor.characters.first.toUpperCase() : 'B';
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleKor, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (titleEng.isNotEmpty)
              Text(titleEng,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
        centerTitle: false,
      ),

      body: CustomScrollView(
        slivers: [
          // ── 헤더: 이니셜 원 + 카테고리 카운트
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ✅ 브랜드 이니셜 원
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xffd6d6d6),
                      border: Border.all(color: line),
                    ),
                    child: Text(
                      _initial(),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 카운트 6칸 (2줄)
                  Expanded(
                    child: FutureBuilder<List<int>>(
                      future: Future.wait<int>([
                        _count(cat: null),
                        _count(cat: 'ring'),
                        _count(cat: 'necklace'),
                        _count(cat: 'bracelet'),
                        _count(cat: 'earring'),
                        _count(cat: 'acc'),
                      ]),
                      builder: (context, snap) {
                        final counts = snap.data ?? const [0, 0, 0, 0, 0, 0];

                        Widget cell(String label, int n) => Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$n',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(label,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54)),
                            ],
                          ),
                        );

                        return Column(
                          children: [
                            Row(children: [
                              cell('전체', counts[0]),
                              cell('반지', counts[1]),
                              cell('목걸이', counts[2]),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              cell('팔찌', counts[3]),
                              cell('귀걸이', counts[4]),
                              cell('기타', counts[5]),
                            ]),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 탭바 (텍스트만)
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
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ))
                    .toList(),
              ),
            ),
          ),

          // ── 탭 컨텐츠: 3열 이미지 그리드
          SliverFillRemaining(
            child: TabBarView(
              controller: _tab,
              children: _tabs
                  .map(
                    (t) => _BrandPostGridImagesOnly(
                  brandKor: widget.brandKor,
                  category: t.code,
                ),
              )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatTab {
  final String label;
  final String? code;
  const _CatTab({required this.label, required this.code});
}

class _BrandPostGridImagesOnly extends StatelessWidget {
  final String brandKor;
  final String? category;
  const _BrandPostGridImagesOnly({required this.brandKor, this.category});

  Query<Map<String, dynamic>> _query() {
    Query<Map<String, dynamic>> q =
    FirebaseFirestore.instance.collection('posts');
    if (brandKor.trim().toUpperCase() != 'ALL') {
      q = q.where('brand', isEqualTo: brandKor);
    }
    if (category != null) {
      q = q.where('category', isEqualTo: category);
    }
    return q;
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query().snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(strokeWidth: 1.5));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(
              child: Text('게시물이 없습니다.', style: TextStyle(color: Colors.black54)));
        }

        final docs = [...snap.data!.docs]..sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final da = (ta is Timestamp) ? ta.toDate() : DateTime(1970);
          final db = (tb is Timestamp) ? tb.toDate() : DateTime(1970);
          return db.compareTo(da);
        });

        return GridView.builder(
          padding: EdgeInsets.zero,
          itemCount: docs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
            childAspectRatio: 1,
          ),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final d = doc.data();
            final img = (d['imageUrl'] ?? '').toString();

            return InkWell(
              onTap: () {
                PostOverlay.show(context, docs: docs, startIndex: i);
              },
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: line, width: 1),
                    right: BorderSide(color: line, width: 1),
                    bottom: BorderSide(color: line, width: 1),
                    left: BorderSide(color: line, width: 1),
                  ),
                ),
                child: (img.isNotEmpty)
                    ? Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.black26),
                  ),
                )
                    : const Center(
                    child: Icon(Icons.image_not_supported,
                        color: Colors.black26)),
              ),
            );
          },
        );
      },
    );
  }
}
