// lib/pages/root_tab.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'categories_page.dart';
import 'favorites_page.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'profile_page.dart';
import 'new_post_page.dart';
import 'brand_profile_page.dart' as bp;

import '../services/single_login_guard.dart';

class RootTab extends StatefulWidget {
  final String role;
  final int initialIndex;
  const RootTab({super.key, this.role = 'user', this.initialIndex = 2});

  @override
  State<RootTab> createState() => _RootTabState();
}

class _RootTabState extends State<RootTab> {
  static const double kWide = 900;
  late int _index;
  late final PageController _pageCtrl;

  User? get _user => FirebaseAuth.instance.currentUser;

  bool get _isAdmin {
    final r = widget.role.toLowerCase();
    return r == 'admin' || r == 'super';
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4);
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  bool _isWide(BuildContext c) => MediaQuery.of(c).size.width >= kWide;

  String _initial() {
    final e = _user?.email ?? '';
    final id = e.split('@').first;
    return id.isNotEmpty ? id.characters.first.toUpperCase() : 'U';
  }

  Future<void> _confirmAndLogout() async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: Opacity(
            opacity: anim1.value,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1.2),
                      borderRadius: BorderRadius.zero,
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '로그아웃',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '정말 로그아웃 하시겠어요?',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black54,
                              ),
                              child: const Text('취소'),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: const Text('로그아웃'),
                            ),
                          ],
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

    if (ok == true) {
      await SingleLoginGuard.instance.releaseLock();
      await FirebaseAuth.instance.signOut();
    }
  }

  void _openCategoriesDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, ___) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: Align(
            alignment: const Alignment(0, -0.2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 460,
                maxHeight: 540,
              ),
              child: Material(
                color: Colors.white,
                elevation: 6,
                borderRadius: BorderRadius.circular(4),
                child: CategoriesPage(
                  isAdmin: _isAdmin,
                  onOpenBrand: ({
                    required String brandKor,
                    String? brandEng,
                    bool isAdmin = false,
                    String? initialCategory,
                  }) {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => bp.BrandProfilePage(
                          brandKor: brandKor,
                          brandEng: brandEng ?? '',
                          isAdmin: _isAdmin,
                          initialCategory: initialCategory,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const CategoriesPage(),
      const FavoritesPage(),
      const HomePage(),
      const SearchPage(),
      ProfilePage(role: widget.role),
    ];

    // ───────────────── AppBar: Firestore(system/appbar) 기반 동적 타이틀 ─────────────────
    final appBar = AppBar(
      title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('system')
            .doc('appbar')
            .snapshots(),
        builder: (context, snap) {
          // 기본 타이틀 (에셋 아이콘 2개)
          Widget defaultTitle = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/appbar/free-icon-diamonds-5903088.png',
                width: 35,
                height: 35,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 5),
              Image.asset(
                'assets/appbar/free-icon-k-3522350.png',
                width: 25,
                height: 25,
                fit: BoxFit.contain,
              ),
            ],
          );

          if (!snap.hasData || !snap.data!.exists) {
            return defaultTitle;
          }

          final data = snap.data!.data() ?? {};
          final titleText = (data['titleText'] ?? '').toString();
          final leftUrl = (data['leftImageUrl'] ?? '').toString();
          final rightUrl = (data['rightImageUrl'] ?? '').toString();

          final children = <Widget>[];

          // 왼쪽 아이콘: 업로드된 이미지 있으면 우선, 없으면 기본 다이아몬드
          if (leftUrl.isNotEmpty) {
            children.add(
              Image.network(
                leftUrl,
                width: 35,
                height: 35,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Image.asset(
                    'assets/appbar/free-icon-diamonds-5903088.png',
                    width: 35,
                    height: 35,
                    fit: BoxFit.contain,
                  );
                },
              ),
            );
          } else {
            children.add(
              Image.asset(
                'assets/appbar/free-icon-diamonds-5903088.png',
                width: 35,
                height: 35,
                fit: BoxFit.contain,
              ),
            );
          }

          children.add(const SizedBox(width: 5));

          // 오른쪽 영역: 업로드 이미지 > 제목 텍스트 > 기본 K 아이콘
          if (rightUrl.isNotEmpty) {
            children.add(
              Image.network(
                rightUrl,
                width: 25,
                height: 25,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Image.asset(
                    'assets/appbar/free-icon-k-3522350.png',
                    width: 25,
                    height: 25,
                    fit: BoxFit.contain,
                  );
                },
              ),
            );
          } else if (titleText.isNotEmpty) {
            children.add(
              Text(
                titleText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          } else {
            children.add(
              Image.asset(
                'assets/appbar/free-icon-k-3522350.png',
                width: 25,
                height: 25,
                fit: BoxFit.contain,
              ),
            );
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: children,
          );
        },
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: PopupMenuButton<String>(
            offset: const Offset(0, 32),
            elevation: 0,
            color: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            onSelected: (v) async {
              switch (v) {
                case 'profile':
                  _goTo(4);
                  break;
                case 'upload':
                  if (_isAdmin) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NewPostPage(),
                      ),
                    );
                  }
                  break;
                case 'logout':
                  await _confirmAndLogout();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'profile',
                child: Text('프로필로 이동'),
              ),
              if (_isAdmin)
                const PopupMenuItem<String>(
                  value: 'upload',
                  child: Text('게시물 업로드'),
                ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('로그아웃'),
              ),
            ],
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F4),
                border: Border.all(color: const Color(0xFFE6E6E6)),
              ),
              child: Center(
                child: Text(
                  _initial(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    );

    // ───────────────── 레이아웃 (모바일 / 와이드) ─────────────────
    Widget content;

    if (!_isWide(context)) {
      // 모바일: 하단 NavigationBar
      content = Scaffold(
        backgroundColor: Colors.white,
        appBar: appBar,
        body: PageView(
          controller: _pageCtrl,
          onPageChanged: (i) => setState(() => _index = i),
          children: pages,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.view_headline), label: ''),
            NavigationDestination(icon: Icon(Icons.favorite_outline), label: ''),
            NavigationDestination(icon: Icon(Icons.home_outlined), label: ''),
            NavigationDestination(icon: Icon(Icons.search), label: ''),
            NavigationDestination(icon: Icon(Icons.person_outline), label: ''),
          ],
        ),
      );
    } else {
      // 데스크톱/태블릿 와이드: 좌측 NavigationRail
      content = Scaffold(
        backgroundColor: Colors.white,
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) {
                if (i == 0) {
                  _openCategoriesDialog();
                  return;
                }
                _goTo(i);
              },
              labelType: NavigationRailLabelType.none,
              minWidth: 64,
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.view_headline), label: Text('')),
                NavigationRailDestination(
                    icon: Icon(Icons.favorite_outline), label: Text('')),
                NavigationRailDestination(
                    icon: Icon(Icons.home_outlined), label: Text('')),
                NavigationRailDestination(
                    icon: Icon(Icons.search), label: Text('')),
                NavigationRailDestination(
                    icon: Icon(Icons.person_outline), label: Text('')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _index = i),
                children: pages,
              ),
            ),
          ],
        ),
      );
    }

    return content;
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
}
