// lib/pages/search_page.dart ✅ 최종 전체
import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../widgets/post_overlay.dart';
import '../utils/cloudinary_image_utils.dart';

class _SearchCache {
  static List<String>? shuffledIds;
}

/// ✅ 검색 상태(검색어 + 필터) 스택용
class _SearchState {
  final String q;
  final String? brandKor;
  final String? categoryCode;
  const _SearchState({
    required this.q,
    required this.brandKor,
    required this.categoryCode,
  });
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();

  List<String> _recent = [];
  String _q = '';
  bool _showRecent = false;
  bool _refreshing = false;

  // ✅ "상태 스택" (뒤로가기 복귀)
  final List<_SearchState> _stack = [];

  final LayerLink _anchor = LayerLink();
  late final AnimationController _dropCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _size;
  late final Animation<Offset> _slide;

  StreamSubscription<User?>? _authSub;

  // ---------- 필터 상태 ----------
  bool _filterOpen = false;
  String? _selectedBrandKor;
  String? _selectedCategoryCode;

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
    _size = curved;
    _fade = CurvedAnimation(
      parent: _dropCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _dropCtrl, curve: Curves.easeOutCubic),
    );

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

  /// ✅ 검색 실행: "현재 상태"를 스택에 저장하고 새 검색으로 전환
  void _submit([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty) return;

    // 검색 로그(실패해도 무시)
    try {
      await FirebaseFirestore.instance.collection('search_logs_public').add({
        'q': q,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    // ✅ 현재 상태 push
    final current = _SearchState(
      q: _q,
      brandKor: _selectedBrandKor,
      categoryCode: _selectedCategoryCode,
    );
    final shouldPush = !(current.q.isEmpty &&
        current.brandKor == null &&
        current.categoryCode == null);

    if (shouldPush) {
      // 중복 push 방지
      final dup = _stack.isNotEmpty &&
          _stack.last.q == current.q &&
          _stack.last.brandKor == current.brandKor &&
          _stack.last.categoryCode == current.categoryCode;
      if (!dup) _stack.add(current);
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

  /// ✅ 뒤로가기: 이전 검색 상태(검색어+필터)로 복귀
  Future<bool> _onWillPop() async {
    if (_showRecent) {
      _closeRecentOverlay();
      return false;
    }

    if (_stack.isNotEmpty) {
      final prev = _stack.removeLast();
      setState(() {
        _q = prev.q;
        _selectedBrandKor = prev.brandKor;
        _selectedCategoryCode = prev.categoryCode;

        _ctrl.text = prev.q;
        _ctrl.selection = TextSelection.collapsed(offset: prev.q.length);
      });
      _saveLastQuery(prev.q);
      return false;
    }

    if (_q.isNotEmpty || _selectedBrandKor != null || _selectedCategoryCode != null) {
      setState(() {
        _q = '';
        _selectedBrandKor = null;
        _selectedCategoryCode = null;
        _ctrl.clear();
      });
      _saveLastQuery('');
      return false;
    }

    return true;
  }

  // ---------- 필터 섹션 ----------
  Widget _buildFilterSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _filterOpen = !_filterOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  '상세 필터 검색',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _filterOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 20, color: theme.colorScheme.onSurface),
                ),
                const Spacer(),
                if (_selectedBrandKor != null || _selectedCategoryCode != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedBrandKor = null;
                        _selectedCategoryCode = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '초기화',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent.shade200,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _filterOpen
              ? Container(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1D22) : const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.transparent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BrandFilterLine(
                  selectedBrandKor: _selectedBrandKor,
                  onSelected: (kor) => setState(() => _selectedBrandKor = kor),
                  theme: theme,
                ),
                const SizedBox(height: 16),
                _CategoryFilterLine(
                  selectedCategoryCode: _selectedCategoryCode,
                  onSelected: (code) => setState(() => _selectedCategoryCode = code),
                  theme: theme,
                ),
              ],
            ),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// ✅ 브랜드 매칭 스트립(3.5개 보이게 + 가로 스크롤)
  /// ❗️리턴 타입은 Widget (Sliver 클래스 없음)
  Widget _brandMatchStrip({
    required ThemeData theme,
    required bool isDark,
  }) {
    if (_q.trim().isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    final qLower = _q.trim().toLowerCase();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('brands').orderBy('rank').limit(80).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final docs = snap.data!.docs;

        final matched = docs.where((d) {
          final m = d.data();
          final kor = (m['nameKor'] ?? '').toString().trim();
          final eng = (m['nameEng'] ?? m['eng'] ?? '').toString().trim();
          return kor.toLowerCase().contains(qLower) || eng.toLowerCase().contains(qLower);
        }).toList();

        if (matched.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final show = matched.take(24).toList();

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '브랜드',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final itemW = w / 3.5; // ✅ 3.5개
                    final avatar = min(56.0, itemW - 16);

                    return SizedBox(
                      height: avatar + 26,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: show.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final d = show[i];
                          final m = d.data();
                          final kor = (m['nameKor'] ?? '').toString().trim();
                          final eng = (m['nameEng'] ?? m['eng'] ?? '').toString().trim();
                          final label = kor.isNotEmpty ? kor : (eng.isNotEmpty ? eng : 'Brand');

                          final rawImg = (m['profileUrl'] ??
                              m['logoUrl'] ??
                              m['imageUrl'] ??
                              m['thumbUrl'] ??
                              '')
                              .toString()
                              .trim();

                          return SizedBox(
                            width: itemW,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _selectedBrandKor = kor.isNotEmpty ? kor : null;
                                  _filterOpen = true;
                                });
                              },
                              child: Column(
                                children: [
                                  Container(
                                    width: avatar,
                                    height: avatar,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark ? const Color(0xFF2A2F38) : const Color(0xFFF0F0F0),
                                      border: Border.all(
                                        color: theme.dividerTheme.color ?? Colors.transparent,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: rawImg.isEmpty
                                        ? Center(
                                      child: Text(
                                        label.characters.first.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                                        ),
                                      ),
                                    )
                                        : CachedNetworkImage(
                                      imageUrl: rawImg,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => ColoredBox(
                                        color: isDark ? const Color(0xFF2A2F38) : const Color(0xFFE0E0E0),
                                      ),
                                      errorWidget: (_, __, ___) => Center(
                                        child: Text(
                                          label.characters.first.toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface.withOpacity(0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
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
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final maxBarWidth = 600.0;
    final barWidth = min(MediaQuery.of(context).size.width - 32, maxBarWidth);

    const double kTopPadding = 12;
    const double kSearchHeight = 54;

    final searchBar = Center(
      child: CompositedTransformTarget(
        link: _anchor,
        child: SizedBox(
          width: barWidth,
          height: kSearchHeight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1D22) : Colors.white,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: theme.dividerTheme.color ?? Colors.transparent, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black45 : Colors.black.withOpacity(0.06),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onTap: _openRecentOverlay,
                    onSubmitted: (_) => _submit(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: '어떤 주얼리를 찾으시나요?',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                    onPressed: () {
                      setState(() => _ctrl.clear());
                      _openRecentOverlay();
                    },
                  ),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.onSurface,
                    foregroundColor: theme.scaffoldBackgroundColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('검색', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final bodyBelow = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(
            top: kTopPadding + kSearchHeight + 16,
            bottom: 16,
          ),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '인기 검색어',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PopularSearchTop5(
                    theme: theme,
                    isDark: isDark,
                    onPick: (word) {
                      _ctrl.text = word;
                      _ctrl.selection = TextSelection.collapsed(offset: word.length);
                      _submit(word);
                    },
                  ),
                  const SizedBox(height: 18),
                  _buildFilterSection(theme, isDark),
                ],
              ),
            ),
          ),
        ),

        // ✅ 브랜드 매칭 스트립(검색 결과 위)
        _brandMatchStrip(theme: theme, isDark: isDark),

        // ✅ 결과 그리드
        if (_q.isEmpty)
          _RandomExploreGrid(
            forceLoading: _refreshing,
            brandFilterKor: _selectedBrandKor,
            categoryFilterCode: _selectedCategoryCode,
            theme: theme,
            isDark: isDark,
          )
        else
          _SearchResultGrid(
            query: _q,
            brandFilterKor: _selectedBrandKor,
            categoryFilterCode: _selectedCategoryCode,
            theme: theme,
            isDark: isDark,
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );

    // 최근 검색어 드롭다운
    const double itemHeight = 44;
    final int visible = _recent.length.clamp(0, 6);
    final double targetHeight = visible * itemHeight + 16;
    const double maxHeight = 280;

    final recentDropdown = (_showRecent && _recent.isNotEmpty)
        ? CompositedTransformFollower(
      link: _anchor,
      showWhenUnlinked: false,
      offset: const Offset(0, kSearchHeight + 8),
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
                  height: min(targetHeight, maxHeight.toDouble()),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF22252A) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? Colors.black87 : Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(color: theme.dividerTheme.color ?? Colors.transparent),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    physics: const BouncingScrollPhysics(),
                    itemCount: visible,
                    itemBuilder: (_, i) {
                      final e = _recent[i];
                      return InkWell(
                        onTap: () => _submit(e),
                        child: Container(
                          height: itemHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.4)),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  setState(() => _recent.remove(e));
                                  await _saveRecent();
                                  if (_recent.isEmpty) _closeRecentOverlay();
                                },
                              ),
                            ],
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
        backgroundColor: theme.scaffoldBackgroundColor,
        body: ScrollConfiguration(
          behavior: const _DragEverywhere(),
          child: Stack(
            children: [
              RefreshIndicator(
                color: isDark ? Colors.white : Colors.black,
                backgroundColor: theme.scaffoldBackgroundColor,
                onRefresh: _onRefresh,
                child: bodyBelow,
              ),
              dismissLayer,
              Positioned(
                top: kTopPadding,
                left: 16,
                right: 16,
                child: searchBar,
              ),
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

/* ---------------------- 필터 라인 ---------------------- */

class _FilterTextItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _FilterTextItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.onSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : theme.colorScheme.onSurface.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? theme.scaffoldBackgroundColor : theme.colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

class _BrandFilterLine extends StatelessWidget {
  final String? selectedBrandKor;
  final ValueChanged<String?> onSelected;
  final ThemeData theme;

  const _BrandFilterLine({
    super.key,
    required this.selectedBrandKor,
    required this.onSelected,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('brands').orderBy('rank').limit(30).snapshots(),
      builder: (context, snap) {
        final chips = <Widget>[
          _FilterTextItem(
            label: '전체',
            selected: selectedBrandKor == null,
            onTap: () => onSelected(null),
            theme: theme,
          ),
        ];

        if (snap.hasData) {
          final items = snap.data!.docs
              .map((d) => MapEntry(
            d.data()['rank'] is int ? d.data()['rank'] as int : 1000,
            (d.data()['nameKor'] ?? '').toString().trim(),
          ))
              .where((e) => e.value.isNotEmpty)
              .toList()
            ..sort((a, b) => a.key != b.key ? a.key.compareTo(b.key) : a.value.compareTo(b.value));

          for (final e in items) {
            chips.add(
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _FilterTextItem(
                  label: e.value,
                  selected: selectedBrandKor == e.value,
                  onTap: () => onSelected(selectedBrandKor == e.value ? null : e.value),
                  theme: theme,
                ),
              ),
            );
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('브랜드', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(children: chips),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryFilterLine extends StatelessWidget {
  final String? selectedCategoryCode;
  final ValueChanged<String?> onSelected;
  final ThemeData theme;

  const _CategoryFilterLine({
    super.key,
    required this.selectedCategoryCode,
    required this.onSelected,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const labels = <String?, String>{
      null: '전체',
      'ring': '반지',
      'necklace': '목걸이',
      'bracelet': '팔찌',
      'earring': '귀걸이',
      'acc': '기타',
    };

    final chips = <Widget>[];
    labels.forEach((code, label) {
      chips.add(
        Padding(
          padding: EdgeInsets.only(left: chips.isEmpty ? 0 : 8),
          child: _FilterTextItem(
            label: label,
            selected: selectedCategoryCode == code,
            onTap: () => onSelected(selectedCategoryCode == code ? null : code),
            theme: theme,
          ),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('카테고리', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(children: chips),
        ),
      ],
    );
  }
}

/* ---------------------- 인기 검색어 ---------------------- */

class _PopularSearchTop5 extends StatelessWidget {
  final ThemeData theme;
  final bool isDark;
  final void Function(String word)? onPick;

  const _PopularSearchTop5({super.key, required this.theme, required this.isDark, this.onPick});

  @override
  Widget build(BuildContext context) {
    const fallback = ['반지', '목걸이', '귀걸이', '팔찌', '티파니'];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('search_logs_public').orderBy('createdAt', descending: true).limit(1000).snapshots(),
      builder: (context, snap) {
        List<String> top5 = [];
        if (snap.hasData) {
          final counts = <String, int>{};
          for (final d in snap.data!.docs) {
            final q = (d.data()['q'] ?? '').toString().trim();
            if (q.isEmpty) continue;
            counts[q] = (counts[q] ?? 0) + 1;
          }
          top5 = counts.keys.toList()..sort((a, b) => (counts[b]!).compareTo(counts[a]!));
          top5 = top5.take(5).toList();
        }
        if (top5.isEmpty) top5 = fallback;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: List.generate(top5.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => onPick?.call(top5[i]),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF22252A) : Colors.black.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Text('${i + 1}', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.w900, fontSize: 13)),
                        const SizedBox(width: 6),
                        Text(top5[i], style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w700, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/* ---------------------- 핀터레스트 그리드 ---------------------- */

String _pickThumbRaw(Map<String, dynamic> data) {
  final a = (data['thumbUrl'] ?? '').toString().trim();
  if (a.isNotEmpty) return a;
  final b = (data['thumbnailUrl'] ?? '').toString().trim();
  if (b.isNotEmpty) return b;
  final list = data['thumbImages'];
  if (list is List && list.isNotEmpty) return (list.first ?? '').toString().trim();
  return (data['imageUrl'] ?? '').toString().trim();
}

class _PinterestGrid extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final ThemeData theme;
  final bool isDark;

  const _PinterestGrid({super.key, required this.docs, required this.theme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    int crossAxisCount = (!kIsWeb || width < 600) ? 2 : (width >= 1200 ? 5 : 4);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 24,
        crossAxisSpacing: 12,
        childCount: docs.length,
        itemBuilder: (context, i) {
          final data = docs[i].data();
          final docId = docs[i].id;
          final img = buildThumbUrl(_pickThumbRaw(data));
          final title = (data['title'] ?? '').toString();
          final randomHeight = 180.0 + Random(docId.hashCode).nextInt(160);

          return _FadedTile(
            onTap: () => PostOverlay.show(context, docs: docs, startIndex: i),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: randomHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: isDark ? Colors.black45 : Colors.black12, blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => ColoredBox(color: isDark ? const Color(0xFF2A2F38) : const Color(0xFFE0E0E0)),
                      errorWidget: (_, __, ___) => ColoredBox(color: isDark ? const Color(0xFF1A1D22) : Colors.black12),
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
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface, height: 1.3, letterSpacing: -0.3),
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
}

class _RandomExploreGrid extends StatelessWidget {
  final bool forceLoading;
  final String? brandFilterKor;
  final String? categoryFilterCode;
  final ThemeData theme;
  final bool isDark;

  const _RandomExploreGrid({
    super.key,
    this.forceLoading = false,
    this.brandFilterKor,
    this.categoryFilterCode,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (forceLoading) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator(color: theme.colorScheme.onSurface)),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('posts').orderBy('createdAt', descending: true).limit(150).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SliverToBoxAdapter(child: SizedBox());

        final docs = snap.data!.docs;

        _SearchCache.shuffledIds ??= () {
          final ids = docs.map((d) => d.id).toList()..shuffle(Random());
          return ids;
        }();

        final byId = {for (final d in docs) d.id: d};
        var inOrder = _SearchCache.shuffledIds!
            .map((id) => byId[id])
            .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
            .toList();

        inOrder = inOrder.where((d) {
          final m = d.data();
          if (brandFilterKor != null && brandFilterKor!.isNotEmpty && (m['brand'] ?? '').toString() != brandFilterKor) return false;
          if (categoryFilterCode != null && categoryFilterCode!.isNotEmpty && (m['category'] ?? '').toString() != categoryFilterCode) return false;
          return true;
        }).toList();

        if (inOrder.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40.0),
              child: Center(
                child: Text(
                  '조건에 맞는 게시물이 없습니다.',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
            ),
          );
        }

        return _PinterestGrid(docs: inOrder, theme: theme, isDark: isDark);
      },
    );
  }
}

const Map<String, List<String>> _kCatKeywords = {
  'ring': ['반지', '링', 'ring'],
  'necklace': ['목걸이', '넥클리스', 'necklace', 'chain'],
  'bracelet': ['팔찌', '브레이슬릿', 'bangle', 'bracelet'],
  'earring': ['귀걸이', '이어링', 'earring'],
  'acc': ['기타', '액세서리', '악세사리', 'accessory', 'acc'],
};

class _ParsedQuery {
  final Set<String> catCodes;
  final Set<String> tokens;
  _ParsedQuery(this.catCodes, this.tokens);
}

_ParsedQuery _parseQuery(String q) {
  final lower = q.toLowerCase().trim();
  final rawTokens = lower.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  final catCodes = <String>{};
  final others = <String>{};

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

class _SearchResultGrid extends StatelessWidget {
  final String query;
  final String? brandFilterKor;
  final String? categoryFilterCode;
  final ThemeData theme;
  final bool isDark;

  const _SearchResultGrid({
    super.key,
    required this.query,
    this.brandFilterKor,
    this.categoryFilterCode,
    required this.theme,
    required this.isDark,
  });

  bool _textHit(Map<String, dynamic> m, String token) {
    final t = token.toLowerCase();
    return (m['title'] ?? '').toString().toLowerCase().contains(t) ||
        (m['description'] ?? '').toString().toLowerCase().contains(t) ||
        (m['brand'] ?? '').toString().toLowerCase().contains(t) ||
        (m['brandEng'] ?? '').toString().toLowerCase().contains(t);
  }

  bool _match(Map<String, dynamic> m, _ParsedQuery pq) {
    final cat = (m['category'] ?? '').toString().toLowerCase();
    if (pq.catCodes.isNotEmpty) return pq.catCodes.contains(cat) && pq.tokens.every((t) => _textHit(m, t));
    if (pq.tokens.isEmpty) return true;
    return pq.tokens.every((t) => _textHit(m, t));
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseQuery(query);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('posts').orderBy('createdAt', descending: true).limit(60).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SliverToBoxAdapter(child: SizedBox());

        final filtered = snap.data!.docs.where((d) {
          final m = d.data();
          if (!_match(m, parsed)) return false;
          if (brandFilterKor != null && brandFilterKor!.isNotEmpty && (m['brand'] ?? '').toString() != brandFilterKor) return false;
          if (categoryFilterCode != null && categoryFilterCode!.isNotEmpty && (m['category'] ?? '').toString() != categoryFilterCode) return false;
          return true;
        }).toList();

        if (filtered.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40.0),
              child: Center(
                child: Text(
                  '검색 결과가 없습니다.',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
            ),
          );
        }

        return _PinterestGrid(docs: filtered, theme: theme, isDark: isDark);
      },
    );
  }
}

class _FadedTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _FadedTile({super.key, required this.child, required this.onTap});

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

class _DragEverywhere extends MaterialScrollBehavior {
  const _DragEverywhere();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}