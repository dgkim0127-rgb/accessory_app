// lib/pages/search_page.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/post_overlay.dart';

class _SearchCache {
  static List<String>? shuffledIds;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final _ctrl = TextEditingController();

  List<String> _recent = [];
  String _q = '';
  bool _showRecent = false;
  bool _refreshing = false;

  final List<String> _history = [];

  final LayerLink _anchor = LayerLink();
  late final AnimationController _dropCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _size;
  late final Animation<Offset> _slide;

  StreamSubscription<User?>? _authSub;

  @override
  bool get wantKeepAlive => true;

  String _recentKey([User? u]) {
    final uid = (u ?? FirebaseAuth.instance.currentUser)?.uid;
    return uid == null ? 'recentSearches_guest' : 'recentSearches_$uid';
  }

  String _lastQueryKey([User? u]) {
    final uid = (u ?? FirebaseAuth.instance.currentUser)?.uid;
    return uid == null ? 'lastSearchQuery_guest' : 'lastSearchQuery_$uid';
  }

  @override
  void initState() {
    super.initState();

    _dropCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    final curved = CurvedAnimation(
      parent: _dropCtrl,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInCubic,
    );
    _size  = curved;
    _fade  = CurvedAnimation(parent: _dropCtrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic));
    _slide = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _dropCtrl, curve: Curves.easeOutCubic));

    _loadRecent();
    _loadLastQuery();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _loadRecent(user: u);
      _loadLastQuery(user: u);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _dropCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent({User? user}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recent = prefs.getStringList(_recentKey(user)) ?? [];
    });
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey(), _recent);
  }

  Future<void> _loadLastQuery({User? user}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_lastQueryKey(user)) ?? '';
    if (!mounted) return;
    setState(() {
      _q = saved;
      _ctrl.text = saved;
      _ctrl.selection = TextSelection.collapsed(offset: saved.length);
    });
  }

  Future<void> _saveLastQuery(String q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastQueryKey(), q);
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    _SearchCache.shuffledIds = null;
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) setState(() => _refreshing = false);
  }

  void _openRecentOverlay() {
    if (!_showRecent) setState(() => _showRecent = true);
    _dropCtrl.forward();
  }

  void _closeRecentOverlay() {
    if (!_showRecent) return;
    _dropCtrl.reverse();
    setState(() => _showRecent = false);
  }

  void _submit([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('search_logs_public').add({
        'q': q,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (_q.isNotEmpty && (_history.isEmpty || _history.last != _q)) {
      _history.add(_q);
    }

    _ctrl.text = q;
    _ctrl.selection = TextSelection.collapsed(offset: q.length);
    FocusScope.of(context).unfocus();

    setState(() {
      _q = q;
      _recent.remove(q);
      _recent.insert(0, q);
      if (_recent.length > 8) _recent.removeLast();
    });
    await _saveRecent();
    await _saveLastQuery(q);

    _closeRecentOverlay();
  }

  Future<bool> _onWillPop() async {
    if (_showRecent) {
      _closeRecentOverlay();
      return false;
    }
    if (_history.isNotEmpty) {
      final prev = _history.removeLast();
      setState(() => _q = prev);
      _ctrl.text = prev;
      _ctrl.selection = TextSelection.collapsed(offset: prev.length);
      _saveLastQuery(prev);
      return false;
    }
    if (_q.isNotEmpty) {
      setState(() => _q = '');
      _saveLastQuery('');
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final maxBarWidth = 500.0;
    final barWidth = min(MediaQuery.of(context).size.width - 32, maxBarWidth);

    const double kTopPadding = 12;
    const double kSearchHeight = 48;

    final searchBar = Center(
      child: CompositedTransformTarget(
        link: _anchor,
        child: SizedBox(
          width: barWidth,
          height: kSearchHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onTap: _openRecentOverlay,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: '검색',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() => _ctrl.clear());
                      _openRecentOverlay();
                    },
                  ),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('검색'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final bodyBelow = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: kTopPadding + 8, left: 16, right: 16, bottom: 20),
      children: [
        const SizedBox(height: 40),
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text('인기 검색어', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        _PopularSearchTop5(onPick: (word) {
          _ctrl.text = word;
          _ctrl.selection = TextSelection.collapsed(offset: word.length);
          _submit(word);
        }),
        const SizedBox(height: 20),
        if (_q.isEmpty)
          _RandomExploreGrid(forceLoading: _refreshing)
        else
          _SearchResultGrid(query: _q),
      ],
    );

    const double itemHeight = 34;
    final int visible = _recent.length.clamp(0, 8);
    final double targetHeight = visible * itemHeight + 6;
    const double maxHeight = 160;

    final recentDropdown = (_showRecent && _recent.isNotEmpty)
        ? CompositedTransformFollower(
      link: _anchor,
      showWhenUnlinked: false,
      offset: const Offset(0, kSearchHeight),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: SizeTransition(
            sizeFactor: _size,
            axisAlignment: -1.0,
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: barWidth, maxHeight: maxHeight),
                child: Container(
                  width: barWidth,
                  height: min(targetHeight, maxHeight),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(color: const Color(0xffe9e9e9)),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    physics: const BouncingScrollPhysics(),
                    itemCount: visible,
                    itemBuilder: (_, i) {
                      final e = _recent[i];
                      return SizedBox(
                        height: itemHeight,
                        child: InkWell(
                          onTap: () => _submit(e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.history, size: 16, color: Colors.black45),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14.5, color: Colors.black87),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  splashRadius: 16,
                                  onPressed: () async {
                                    setState(() => _recent.remove(e));
                                    await _saveRecent();
                                    if (_recent.isEmpty) _closeRecentOverlay();
                                  },
                                ),
                              ],
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
      ),
    )
        : const SizedBox.shrink();

    final dismissLayer = _showRecent
        ? Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closeRecentOverlay,
      ),
    )
        : const SizedBox.shrink();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xfffafafa),
        body: ScrollConfiguration(
          behavior: const _DragEverywhere(),
          child: Stack(
            children: [
              RefreshIndicator(
                color: Colors.black,
                onRefresh: _onRefresh,
                child: bodyBelow,
              ),
              Positioned(top: kTopPadding, left: 16, right: 16, child: searchBar),
              dismissLayer,
              Positioned(
                top: kTopPadding,
                left: (MediaQuery.of(context).size.width - barWidth) / 2 + 16 - 16,
                child: recentDropdown,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 인기 검색어 TOP5
class _PopularSearchTop5 extends StatelessWidget {
  final void Function(String word)? onPick;
  const _PopularSearchTop5({this.onPick});

  @override
  Widget build(BuildContext context) {
    const fallback = ['반지', '목걸이', '귀걸이', '팔찌', '티파니'];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('search_logs_public')
          .orderBy('createdAt', descending: true)
          .limit(1000)
          .snapshots(),
      builder: (context, snap) {
        List<String> top5 = [];
        if (snap.hasData) {
          final counts = <String, int>{};
          for (final d in snap.data!.docs) {
            final q = (d.data()['q'] ?? '').toString().trim();
            if (q.isEmpty) continue;
            counts[q] = (counts[q] ?? 0) + 1;
          }
          final sorted = counts.keys.toList()
            ..sort((a, b) => (counts[b]!).compareTo(counts[a]!));
          top5 = sorted.take(5).toList();
        }
        if (top5.isEmpty) top5 = fallback;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(top5.length, (i) {
              final label = '${i + 1}. ${top5[i]}';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    side: const BorderSide(color: Color(0xffd0d0d0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => onPick?.call(top5[i]),
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// 랜덤(캐시 유지) 그리드
class _RandomExploreGrid extends StatelessWidget {
  final bool forceLoading;
  const _RandomExploreGrid({this.forceLoading = false});

  @override
  Widget build(BuildContext context) {
    if (forceLoading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(150)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final docs = snap.data!.docs;

        _SearchCache.shuffledIds ??= () {
          final ids = docs.map((d) => d.id).toList()..shuffle(Random());
          return ids;
        }();

        final byId = {for (final d in docs) d.id: d};
        final inOrder = _SearchCache.shuffledIds!
            .map((id) => byId[id])
            .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
            .toList();

        return _PostGrid(docs: inOrder);
      },
    );
  }
}

/* ---------------------- 카테고리/브랜드 인식 검색 ---------------------- */

/// 카테고리 키워드 → 카테고리 코드 매핑
const Map<String, List<String>> _kCatKeywords = {
  'ring':      ['반지', '링', 'ring'],
  'necklace':  ['목걸이', '넥클리스', 'necklace', 'chain'],
  'bracelet':  ['팔찌', '브레이슬릿', 'bangle', 'bracelet'],
  'earring':   ['귀걸이', '이어링', 'earring'],
  'acc':       ['기타', '액세서리', '악세사리', 'accessory', 'acc'],
};

/// 검색어를 토큰으로 쪼개고(공백 기준) 카테고리 코드와 일반키워드 세트로 분리
class _ParsedQuery {
  final Set<String> catCodes;
  final Set<String> tokens; // 일반 텍스트 토큰
  _ParsedQuery(this.catCodes, this.tokens);
}

_ParsedQuery _parseQuery(String q) {
  final lower = q.toLowerCase().trim();
  final rawTokens = lower.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();

  final catCodes = <String>{};
  final others   = <String>{};

  for (final t in rawTokens) {
    bool matchedCat = false;
    _kCatKeywords.forEach((code, words) {
      if (words.any((w) => t.contains(w.toLowerCase()))) {
        catCodes.add(code);
        matchedCat = true;
      }
    });
    if (!matchedCat) others.add(t);
  }
  return _ParsedQuery(catCodes, others);
}

/// 검색 결과 그리드
class _SearchResultGrid extends StatelessWidget {
  final String query;
  const _SearchResultGrid({required this.query});

  bool _textHit(Map<String, dynamic> m, String token) {
    final t = token.toLowerCase();
    return (m['title'] ?? '').toString().toLowerCase().contains(t) ||
        (m['description'] ?? '').toString().toLowerCase().contains(t) ||
        (m['brand'] ?? '').toString().toLowerCase().contains(t) ||
        (m['brandEng'] ?? '').toString().toLowerCase().contains(t);
  }

  bool _match(Map<String, dynamic> m, _ParsedQuery pq) {
    final cat = (m['category'] ?? '').toString().toLowerCase();

    // 1) 카테고리 지정이 있으면: 카테고리 일치 OR (나머지 토큰이 있으면 그 토큰도 모두 AND 매칭)
    if (pq.catCodes.isNotEmpty) {
      final catOk = pq.catCodes.contains(cat);
      final textOk = pq.tokens.every((t) => _textHit(m, t));
      return catOk && textOk;
    }

    // 2) 카테고리 지정이 없으면: 모든 토큰 AND 매칭
    if (pq.tokens.isEmpty) return true;
    return pq.tokens.every((t) => _textHit(m, t));
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseQuery(query);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final filtered = snap.data!.docs.where((d) => _match(d.data(), parsed)).toList();
        if (filtered.isEmpty) {
          return const Center(
            child: Text('검색 결과가 없습니다.', style: TextStyle(color: Colors.black54)),
          );
        }
        return _PostGrid(docs: filtered);
      },
    );
  }
}

/* ------------------------------ 공통 그리드 ------------------------------ */

class _PostGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _PostGrid({required this.docs});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: docs.length,
      itemBuilder: (ctx, i) {
        final img = (docs[i]['imageUrl'] ?? '').toString();
        return GestureDetector(
          onTap: () => PostOverlay.show(ctx, docs: docs, startIndex: i),
          child: _ProgressImage(url: img),
        );
      },
    );
  }
}

class _ProgressImage extends StatelessWidget {
  final String url;
  const _ProgressImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            final total = loadingProgress.expectedTotalBytes;
            final loaded = loadingProgress.cumulativeBytesLoaded;
            final percent = (total != null && total > 0) ? (loaded / total) : null;
            return Container(
              color: const Color(0xfff5f5f5),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(height: 8),
                    Text(
                      percent == null ? '로딩중...' : '${(percent * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
        ),
        IgnorePointer(
          ignoring: true,
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xfff0f0f0), width: 0.5)),
          ),
        ),
      ],
    );
  }
}

class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();
  @override
  Set<PointerDeviceKind> get dragDevices =>
      {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad};
}
