// lib/pages/categories_page.dart ✅ 최종 (쫀득한 터치 애니메이션 + 프리미엄 둥근 사이드바)
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
        if (mounted) {
          setState(() {
            _roleLoaded = true;
            _roleIsAdmin = false;
          });
        }
        return;
      }
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.server));
        final roleRaw = (snap.data()?['role'] ?? 'user').toString().toLowerCase();
        final isAdmin = roleRaw == 'admin' || roleRaw == 'super';
        if (mounted) {
          setState(() {
            _roleLoaded = true;
            _roleIsAdmin = isAdmin;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _roleLoaded = true;
            _roleIsAdmin = false;
          });
        }
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
          final kor = (m['nameKor'] ?? '').toString().trim();
          final eng = (m['nameEng'] ?? '').toString().trim();
          final rank = (m['rank'] is int) ? (m['rank'] as int) : 1000000000;
          return _BrandDoc(
            id: d.id,
            kor: kor.isEmpty ? '이름 없음' : kor,
            eng: eng,
            rank: rank,
          );
        }).toList();
        list.sort((a, b) =>
        a.rank != b.rank ? a.rank.compareTo(b.rank) : a.kor.compareTo(b.kor));
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
      final kor = (m['nameKor'] ?? '').toString().trim();
      final eng = (m['nameEng'] ?? '').toString().trim();
      final rank = (m['rank'] is int) ? (m['rank'] as int) : 1000000000;
      return _BrandDoc(
        id: d.id,
        kor: kor.isEmpty ? '이름 없음' : kor,
        eng: eng,
        rank: rank,
      );
    }).toList();
    list.sort((a, b) =>
    a.rank != b.rank ? a.rank.compareTo(b.rank) : a.kor.compareTo(b.kor));
    return list;
  }

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
    final nextRank =
    last.docs.isEmpty ? 10 : (((last.docs.first.data()['rank'] ?? 0) as int) + 10);

    await FirebaseFirestore.instance.collection('brands').add({
      'nameKor': korTrim,
      'nameEng': engTrim,
      'nameKorLower': korLower,
      'nameEngLower': engLower,
      'rank': nextRank,
      'postsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _toast('브랜드가 추가되었습니다.');
  }

  Future<void> _updateBrandName(_BrandDoc b, String newKor, String newEng) async {
    final korTrim = newKor.trim();
    final engTrim = newEng.trim();

    if (korTrim.isEmpty) {
      _toast('브랜드 한글명은 비울 수 없어요.');
      return;
    }

    final korLower = korTrim.toLowerCase();
    final engLower = engTrim.toLowerCase();

    final dup = await FirebaseFirestore.instance
        .collection('brands')
        .where('nameKorLower', isEqualTo: korLower)
        .limit(1)
        .get(const GetOptions(source: Source.server));

    if (dup.docs.isNotEmpty && dup.docs.first.id != b.id) {
      _toast('이미 존재하는 브랜드명입니다.');
      return;
    }

    await FirebaseFirestore.instance.collection('brands').doc(b.id).set({
      'nameKor': korTrim,
      'nameEng': engTrim,
      'nameKorLower': korLower,
      'nameEngLower': engLower,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _toast('브랜드명이 수정되었습니다.');
  }

  Future<void> _showEditBrandDialog(_BrandDoc b) async {
    final korC = TextEditingController(text: b.kor == '이름 없음' ? '' : b.kor);
    final engC = TextEditingController(text: b.eng);
    final theme = Theme.of(context);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.scaffoldBackgroundColor,
          title: Text('브랜드명 편집', style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: korC,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '브랜드명 (한글)',
                  labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: engC,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: '브랜드명 (원문)',
                  labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.onSurface,
                foregroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await _updateBrandName(b, korC.text, engC.text);
              },
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
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

  Future<void> _reorderAndPersist(
      List<_BrandDoc> items, int oldIndex, int newIndex) async {
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

  Future<void> _showManageBrandsSheet() async {
    if (!_effectiveIsAdmin) {
      _toast('관리자 전용 기능입니다.');
      return;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                      Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          '브랜드 관리 (드래그하여 순서 변경)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface),
                        ),
                      ),
                      Divider(height: 1, color: theme.dividerTheme.color),
                      Expanded(
                        child: StreamBuilder<List<_BrandDoc>>(
                          stream: _brandsStream(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.colorScheme.onSurface));
                            }
                            final items = List<_BrandDoc>.from(snap.data ?? const <_BrandDoc>[]);
                            if (items.isEmpty) {
                              return Center(
                                child: Text('등록된 브랜드가 없습니다.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
                              );
                            }

                            return ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              itemCount: items.length,
                              onReorder: (oldIndex, newIndex) =>
                                  _reorderAndPersist(items, oldIndex, newIndex),
                              proxyDecorator: (child, index, anim) => Material(
                                elevation: 8,
                                color: Colors.transparent,
                                shadowColor: Colors.black26,
                                child: child,
                              ),
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

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1A1D22) : Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: theme.dividerTheme.color ?? Colors.transparent),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isDark ? Colors.black45 : Colors.black.withOpacity(0.04),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.drag_indicator, color: theme.colorScheme.onSurface.withOpacity(0.3), size: 20),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  b.eng.isNotEmpty ? '${b.kor}  (${b.eng})' : b.kor,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: theme.colorScheme.onSurface),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Text('#${b.rank}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.4))),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      waiting ? '확인 중…' : (error ? '확인 실패' : '게시물 $cnt개'),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w500,
                                                        color: waiting
                                                            ? theme.colorScheme.onSurface.withOpacity(0.4)
                                                            : (error || cnt > 0 ? Colors.redAccent : theme.colorScheme.onSurface.withOpacity(0.4)),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: '편집',
                                            onPressed: () => _showEditBrandDialog(b),
                                            icon: Icon(Icons.edit_outlined, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                                          ),
                                          IconButton(
                                            tooltip: canDelete ? '삭제' : '게시물이 있어 삭제 불가',
                                            onPressed: canDelete ? () => _deleteBrandStrict(b) : null,
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                              color: canDelete ? Colors.redAccent : theme.colorScheme.onSurface.withOpacity(0.2),
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
                      Divider(height: 1, color: theme.dividerTheme.color),
                      Container(
                        color: isDark ? const Color(0xFF16181C) : const Color(0xFFF9F9F9),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        child: Column(
                          children: [
                            TextField(
                              controller: korC,
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                labelText: '새 브랜드명 (한글)',
                                labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                filled: true,
                                fillColor: theme.scaffoldBackgroundColor,
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: engC,
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                labelText: '새 브랜드명 (원문)',
                                labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                filled: true,
                                fillColor: theme.scaffoldBackgroundColor,
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) async {
                                await _addBrand(korC.text, engC.text);
                                korC.clear();
                                engC.clear();
                                setSheet(() {});
                              },
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.colorScheme.onSurface,
                                      foregroundColor: theme.scaffoldBackgroundColor,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () async {
                                      await _addBrand(korC.text, engC.text);
                                      korC.clear();
                                      engC.clear();
                                      setSheet(() {});
                                    },
                                    child: const Text('추가하기', style: TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                                  ),
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text('닫기', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontWeight: FontWeight.w600)),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final sideBg = isDark ? const Color(0xFF16181C) : const Color(0xFFF9F9F9);
    final dividerColor = theme.dividerTheme.color ?? const Color(0xffe6e6e6);
    const leftWidth = 110.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Row(
            children: [
              // ◀ 왼쪽: 브랜드 목록 패널 (둥글고 쫀득한 디자인 적용)
              Container(
                width: leftWidth,
                decoration: BoxDecoration(
                  color: sideBg,
                  border: Border(right: BorderSide(color: dividerColor, width: 1)),
                ),
                child: StreamBuilder<List<_BrandDoc>>(
                  stream: _brandsStream(),
                  builder: (context, snap) {
                    final brands = snap.data ?? const <_BrandDoc>[];

                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      itemCount: brands.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          final sel = _selected == 0;
                          return _BrandTile(
                            theme: theme,
                            selected: sel,
                            onTap: () => setState(() => _selected = 0),
                            onDoubleTap: () => _openAll(initialCategory: null),
                            child: Text(
                              '전체보기',
                              style: TextStyle(
                                fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }

                        final b = brands[i - 1];
                        final sel = _selected == i;

                        return _BrandTile(
                          theme: theme,
                          selected: sel,
                          onTap: () => setState(() => _selected = i),
                          onDoubleTap: () => _openBrand(b.kor, b.eng, initialCategory: null),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                b.kor,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              if (b.eng.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  b.eng,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: sel
                                        ? theme.scaffoldBackgroundColor.withOpacity(0.7)
                                        : theme.colorScheme.onSurface.withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // ▶ 오른쪽: 카테고리 그리드 (쫀득하고 물리적인 3D 카드 뷰)
              Expanded(
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  itemCount: _subs.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.95, // 살짝 세로로 긴 우아한 비율
                  ),
                  itemBuilder: (_, i) {
                    final s = _subs[i];
                    return _CategoryCardTile(
                      theme: theme,
                      isDark: isDark,
                      subCat: s,
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
                    );
                  },
                ),
              ),
            ],
          ),

          if (_effectiveIsAdmin)
            Positioned(
              right: 20,
              bottom: 24,
              child: FloatingActionButton.extended(
                onPressed: _showManageBrandsSheet,
                backgroundColor: theme.colorScheme.onSurface,
                foregroundColor: theme.scaffoldBackgroundColor,
                elevation: 4,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('브랜드 관리', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),

          if (!_roleLoaded)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: theme.scaffoldBackgroundColor.withOpacity(0.5),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onSurface),
                  ),
                ),
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

// 🌟 1. 왼쪽 브랜드 타일용 쫀득한 애니메이션 위젯 (알약 형태)
class _BrandTile extends StatefulWidget {
  final ThemeData theme;
  final bool selected;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const _BrandTile({
    required this.theme,
    required this.selected,
    required this.child,
    required this.onTap,
    this.onDoubleTap,
  });

  @override
  State<_BrandTile> createState() => _BrandTileState();
}

class _BrandTileState extends State<_BrandTile> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final selected = widget.selected;

    // 선택되었을 때 글자색과 배경색 반전 (블랙&화이트 대비)
    final selectedBgColor = theme.colorScheme.onSurface;
    final selectedTextColor = theme.scaffoldBackgroundColor;
    final unselectedTextColor = theme.colorScheme.onSurface.withOpacity(0.6);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) {
        setState(() => _isDown = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isDown = false),
      onDoubleTap: widget.onDoubleTap,
      child: AnimatedScale(
        scale: _isDown ? 0.94 : 1.0, // 쫀득하게 작아지는 효과
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // 둥근 알약이 잘 보이도록 마진 추가
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? selectedBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12), // 밑줄 대신 모서리 둥근 버튼 형태로 변경
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: selected ? selectedTextColor : unselectedTextColor,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}


// 🌟 2. 오른쪽 카테고리 그리드용 쫀득하고 물리적인 3D 카드 위젯
class _CategoryCardTile extends StatefulWidget {
  final ThemeData theme;
  final bool isDark;
  final _SubCat subCat;
  final VoidCallback onTap;

  const _CategoryCardTile({
    required this.theme,
    required this.isDark,
    required this.subCat,
    required this.onTap,
  });

  @override
  State<_CategoryCardTile> createState() => _CategoryCardTileState();
}

class _CategoryCardTileState extends State<_CategoryCardTile> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.subCat;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) {
        setState(() => _isDown = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isDown = false),
      child: AnimatedScale(
        scale: _isDown ? 0.92 : 1.0, // 더 깊숙이 눌리는 손맛 (0.94 -> 0.92)
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1A1D22) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            // 🌟 꾹 눌렸을 때 물리적으로 바닥에 닿는 느낌(그림자 축소)을 주는 다이나믹 그림자
            boxShadow: _isDown
                ? [
              BoxShadow(
                color: widget.isDark ? Colors.black87 : Colors.black.withOpacity(0.08),
                blurRadius: 5,
                offset: const Offset(0, 2),
              )
            ]
                : [
              BoxShadow(
                color: widget.isDark ? Colors.black45 : Colors.black.withOpacity(0.06),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
            border: Border.all(
              color: widget.theme.dividerTheme.color ?? Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Center(
            child: s.image != null
                ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    s.image!,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: widget.theme.colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.5,
                    color: widget.theme.colorScheme.onSurface,
                  ),
                ),
                if (s.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.subtitle!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: widget.theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}