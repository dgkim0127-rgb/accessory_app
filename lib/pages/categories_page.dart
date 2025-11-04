// lib/pages/categories_page.dart  ✅ 최종 (관리 목록 콤팩트 / 재확인 제거)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'brand_profile_page.dart' as bp;

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    super.key,
    this.isAdmin = false,
    this.onOpenBrand,
  });

  final void Function({
  required String brandKor,
  String? brandEng,
  bool isAdmin,
  String? initialCategory,
  })? onOpenBrand;

  final bool isAdmin;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  int _selected = 0; // 0=전체, 1..=브랜드
  bool _roleLoaded = false;
  bool _roleIsAdmin = false;

  // 게시물 카운트 Future 캐시
  final Map<String, Future<int>> _postCountFutures = {};

  static const _subs = <_SubCat>[
    _SubCat(label: 'ALL', subtitle: '전체', code: null),
    _SubCat(label: '목걸이', code: 'necklace', image: 'assets/icons/necklace.png'),
    _SubCat(label: '반지', code: 'ring', image: 'assets/icons/ring.png'),
    _SubCat(label: '귀걸이', code: 'earring', image: 'assets/icons/earring.png'),
    _SubCat(label: '팔찌', code: 'bracelet', image: 'assets/icons/bracelet.png'),
    _SubCat(label: 'ACC', subtitle: '기타', code: 'acc'),
  ];

  @override
  void initState() {
    super.initState();
    _watchAuthAndRole();
  }

  void _watchAuthAndRole() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        if (mounted) setState(() { _roleLoaded = true; _roleIsAdmin = false; });
        return;
      }
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));
        final roleRaw = (snap.data()?['role'] ?? 'user').toString().toLowerCase();
        final isAdmin = roleRaw == 'admin' || roleRaw == 'super';
        if (mounted) setState(() { _roleLoaded = true; _roleIsAdmin = isAdmin; });
      } catch (_) {
        if (mounted) setState(() { _roleLoaded = true; _roleIsAdmin = false; });
      }
    });
  }

  bool get _effectiveIsAdmin => widget.isAdmin || _roleIsAdmin;

  // ── 브랜드 스트림
  Stream<List<_BrandDoc>> _brandsStream() async* {
    try {
      yield* FirebaseFirestore.instance
          .collection('brands')
          .orderBy('rank')
          .snapshots()
          .map((s) {
        final list = s.docs.map((d) {
          final m = d.data();
          final kor  = (m['nameKor'] ?? '').toString().trim();
          final eng  = (m['nameEng'] ?? '').toString().trim();
          final rank = (m['rank'] is int) ? (m['rank'] as int) : 1000000000;
          return _BrandDoc(
            id: d.id,
            kor: kor.isEmpty ? '이름 없음' : kor,
            eng: eng,
            rank: rank,
          );
        }).toList();
        list.sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.kor.compareTo(b.kor));
        return list;
      });
    } catch (_) {
      yield const <_BrandDoc>[];
    }
  }

  Future<List<_BrandDoc>> _fetchBrandsOrderedOnce() async {
    final qs = await FirebaseFirestore.instance
        .collection('brands')
        .orderBy('rank')
        .get(const GetOptions(source: Source.server));
    final list = qs.docs.map((d) {
      final m = d.data();
      final kor  = (m['nameKor'] ?? '').toString().trim();
      final eng  = (m['nameEng'] ?? '').toString().trim();
      final rank = (m['rank'] is int) ? (m['rank'] as int) : 1000000000;
      return _BrandDoc(id: d.id, kor: kor.isEmpty ? '이름 없음' : kor, eng: eng, rank: rank);
    }).toList();
    list.sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.kor.compareTo(b.kor));
    return list;
  }

  // ✅ 서버 집계 호출 (named parameter 사용)
  Future<int> _countPostsForBrand(String brandId) async {
    try {
      final agg = await FirebaseFirestore.instance
          .collection('posts')
          .where('brandId', isEqualTo: brandId)
          .count()
          .get(source: AggregateSource.server);
      return agg.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _addBrand(String kor, String eng) async {
    final korTrim = kor.trim();
    final engTrim = eng.trim();
    if (korTrim.isEmpty) {
      _toast('브랜드 한글명을 입력하세요.');
      return;
    }
    final korLower = korTrim.toLowerCase();
    final engLower = engTrim.toLowerCase();

    final dup = await FirebaseFirestore.instance
        .collection('brands')
        .where('nameKorLower', isEqualTo: korLower)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (dup.docs.isNotEmpty) {
      _toast('이미 존재하는 브랜드입니다.');
      return;
    }

    final last = await FirebaseFirestore.instance
        .collection('brands')
        .orderBy('rank', descending: true)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    final nextRank = last.docs.isEmpty
        ? 10
        : (((last.docs.first.data()['rank'] ?? 0) as int) + 10);

    await FirebaseFirestore.instance.collection('brands').add({
      'nameKor': korTrim,
      'nameEng': engTrim,
      'nameKorLower': korLower,
      'nameEngLower': engLower,
      'rank': nextRank,
      'postsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    _toast('브랜드가 추가되었습니다.');
  }

  Future<void> _deleteBrandStrict(_BrandDoc b) async {
    try {
      final ref = FirebaseFirestore.instance.collection('brands').doc(b.id);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
        }
        final data = (snap.data() as Map<String, dynamic>?) ?? {};
        final pc = (data['postsCount'] is int) ? data['postsCount'] as int : 0;

        final agg = await FirebaseFirestore.instance
            .collection('posts')
            .where('brandId', isEqualTo: b.id)
            .count()
            .get(source: AggregateSource.server);
        final live = agg.count ?? 0;

        if (pc > 0 || live > 0) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
            message: 'posts exist',
          );
        }

        if (!data.containsKey('postsCount') || data['postsCount'] == null) {
          tx.set(ref, {'postsCount': 0}, SetOptions(merge: true));
        }
        tx.delete(ref);
      });

      final check = await FirebaseFirestore.instance
          .collection('brands')
          .doc(b.id)
          .get(const GetOptions(source: Source.server));

      if (!check.exists) {
        _toast('브랜드가 삭제되었습니다. ✅');
        _postCountFutures.remove(b.id);
        setState(() {});
      } else {
        _toast('삭제가 지연 중입니다. 잠시 후 다시 시도해주세요.');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _toast('권한이 없습니다. 관리자만 삭제할 수 있어요.');
      } else if (e.code == 'failed-precondition') {
        _toast('삭제 불가: 이 브랜드에 게시물이 남아있습니다.');
      } else if (e.code == 'not-found') {
        _toast('이미 삭제되었거나 존재하지 않습니다.');
      } else {
        _toast('삭제 실패: ${e.message ?? e.code}');
      }
    } catch (e) {
      _toast('삭제 실패: $e');
    }
  }

  Future<void> _reorderAndPersist(List<_BrandDoc> items, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);

    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance.collection('brands');

    for (int i = 0; i < items.length; i++) {
      final targetRank = (i + 1) * 10;
      if (items[i].rank != targetRank) {
        batch.update(col.doc(items[i].id), {'rank': targetRank});
      }
    }
    await batch.commit();
  }

  void _openBrand(String kor, String eng, {String? initialCategory}) {
    if (widget.onOpenBrand != null) {
      widget.onOpenBrand!(
        brandKor: kor,
        brandEng: eng.isNotEmpty ? eng : null,
        isAdmin: _effectiveIsAdmin,
        initialCategory: initialCategory,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => bp.BrandProfilePage(
          brandKor: kor,
          brandEng: eng,
          isAdmin: _effectiveIsAdmin,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  void _openAll({String? initialCategory}) {
    if (widget.onOpenBrand != null) {
      widget.onOpenBrand!(
        brandKor: 'ALL',
        brandEng: 'All Brands',
        isAdmin: _effectiveIsAdmin,
        initialCategory: initialCategory,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => bp.BrandProfilePage(
          brandKor: 'ALL',
          brandEng: 'All Brands',
          isAdmin: _effectiveIsAdmin,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  // ── 브랜드 관리 시트
  Future<void> _showManageBrandsSheet() async {
    if (!_effectiveIsAdmin) {
      _toast('관리자 전용 기능입니다.');
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        final korC = TextEditingController();
        final engC = TextEditingController();

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.82,
                  child: Column(
                    children: [
                      // 헤더
                      Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        child: const Text('브랜드 관리 (드래그하여 순서 변경)',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ),
                      const Divider(height: 1),

                      // 목록(스트림) → ReorderableListView (콤팩트 셀)
                      Expanded(
                        child: StreamBuilder<List<_BrandDoc>>(
                          stream: _brandsStream(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
                            }
                            final items = List<_BrandDoc>.from(snap.data ?? const <_BrandDoc>[]);
                            if (items.isEmpty) {
                              return const Center(
                                child: Text('등록된 브랜드가 없습니다.', style: TextStyle(color: Colors.black54)),
                              );
                            }

                            return ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              itemCount: items.length,
                              onReorder: (oldIndex, newIndex) =>
                                  _reorderAndPersist(items, oldIndex, newIndex),
                              proxyDecorator: (child, index, anim) =>
                                  Material(elevation: 3, child: child),
                              itemBuilder: (_, i) {
                                final b = items[i];
                                return FutureBuilder<int>(
                                  key: ValueKey('brand_${b.id}'),
                                  future: _postCountFutures[b.id] ??= _countPostsForBrand(b.id),
                                  builder: (_, cntSnap) {
                                    final waiting = cntSnap.connectionState == ConnectionState.waiting;
                                    final error = cntSnap.hasError;
                                    final cnt = cntSnap.data ?? 0;
                                    final canDelete = !waiting && !error && cnt == 0;

                                    // ✅ 콤팩트 셀: 세로 여백 축소, 한 줄 정보 배치
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: const Color(0xffe6e6e6)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.drag_handle, color: Colors.black45, size: 18),
                                          const SizedBox(width: 6),
                                          // 이름/랭크/카운트 정보를 한 줄로
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    b.eng.isNotEmpty
                                                        ? '${b.kor}  (${b.eng})'
                                                        : b.kor,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '#${b.rank}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black38,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  waiting
                                                      ? '확인 중…'
                                                      : (error ? '확인 실패' : '게시물 $cnt개'),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: waiting
                                                        ? Colors.black38
                                                        : (error
                                                        ? Colors.redAccent
                                                        : (cnt == 0 ? Colors.black38 : Colors.redAccent)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                            padding: EdgeInsets.zero,
                                            tooltip: canDelete ? '삭제' : '게시물이 있어 삭제 불가',
                                            onPressed: canDelete ? () => _deleteBrandStrict(b) : null,
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                              color: canDelete ? Colors.redAccent : Colors.grey,
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
                        ),
                      ),

                      const Divider(height: 1),

                      // 추가 폼
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Column(
                          children: [
                            TextField(
                              controller: korC,
                              decoration: const InputDecoration(
                                labelText: '브랜드명 (한글)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: engC,
                              decoration: const InputDecoration(
                                labelText: '브랜드명 (원문)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) async {
                                await _addBrand(korC.text, engC.text);
                                korC.clear();
                                engC.clear();
                                setSheet(() {}); // 포커스 유지용 noop
                              },
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.black,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                    ),
                                    onPressed: () async {
                                      await _addBrand(korC.text, engC.text);
                                      korC.clear();
                                      engC.clear();
                                      setSheet(() {});
                                    },
                                    child: const Text('추가'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('닫기', style: TextStyle(color: Colors.black54)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const sideBg = Color(0xfffafafa);
    const line   = Color(0xffe6e6e6);
    const leftWidth = 120.0;

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              // ◀ 왼쪽: 전체 + Firestore 브랜드 목록
              Container(
                width: leftWidth,
                color: sideBg,
                child: StreamBuilder<List<_BrandDoc>>(
                  stream: _brandsStream(),
                  builder: (context, snap) {
                    final brands = snap.data ?? const <_BrandDoc>[];

                    return ListView.separated(
                      itemCount: brands.length + 1,
                      separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xffeeeeee)),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final sel = _selected == 0;
                          return InkWell(
                            onTap: () => setState(() => _selected = 0),
                            onDoubleTap: () => _openAll(initialCategory: null),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: sel ? Colors.black : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                '전체',
                                style: TextStyle(
                                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                                  fontSize: 14,
                                  color: sel ? Colors.black : Colors.black54,
                                ),
                              ),
                            ),
                          );
                        }

                        final b = brands[i - 1];
                        final sel = _selected == i;
                        return InkWell(
                          onTap: () => setState(() => _selected = i),
                          onDoubleTap: () => _openBrand(b.kor, b.eng, initialCategory: null),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: sel ? Colors.black : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.kor,
                                  style: TextStyle(
                                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                    fontSize: 13.5,
                                    color: sel ? Colors.black : Colors.black87,
                                  ),
                                ),
                                if (b.eng.isNotEmpty)
                                  Text(
                                    b.eng,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: sel ? Colors.black54 : Colors.black38,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const VerticalDivider(width: 1, color: line),

              // ▶ 오른쪽: 카테고리
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subs.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (_, i) {
                    final s = _subs[i];
                    return InkWell(
                      onTap: () async {
                        if (_selected == 0) {
                          _openAll(initialCategory: s.code);
                        } else {
                          final ordered = await _fetchBrandsOrderedOnce();
                          final idx = _selected - 1;
                          if (idx < 0 || idx >= ordered.length) return;
                          final b = ordered[idx];
                          _openBrand(b.kor, b.eng, initialCategory: s.code);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: line),
                        ),
                        child: Center(
                          child: s.image != null
                              ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(s.image!, width: 36, height: 36, fit: BoxFit.contain),
                              const SizedBox(height: 10),
                              Text(
                                s.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          )
                              : Text(
                            s.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          if (_effectiveIsAdmin)
            Positioned(
              right: 16,
              bottom: 16,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8D8D8D),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(56, 30),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  elevation: 0,
                ),
                onPressed: _showManageBrandsSheet,
                child:
                const Text('관리', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),

          if (!_roleLoaded)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
              ),
            ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _BrandDoc {
  final String id;
  final String kor;
  final String eng;
  final int rank;
  _BrandDoc({required this.id, required this.kor, required this.eng, required this.rank});
}

class _SubCat {
  final String label;
  final String? subtitle;
  final String? code;
  final String? image;
  const _SubCat({required this.label, this.subtitle, this.code, this.image});
}
