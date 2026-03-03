// lib/pages/likes_explorer_page.dart ✅ 최종(검색 추가)
// - 상단 검색창(아이디/이메일 검색)
// - 기존: 관리자/최종관리자 전용 "일반 회원"만 나열 + 좋아요 카운트 표시 유지

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'liked_user_detail_page.dart';

class LikesExplorerPage extends StatefulWidget {
  const LikesExplorerPage({super.key});

  @override
  State<LikesExplorerPage> createState() => _LikesExplorerPageState();
}

class _LikesExplorerPageState extends State<LikesExplorerPage> {
  final TextEditingController _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  String _idOf(String? email) {
    final e = (email ?? '').trim();
    final i = e.indexOf('@');
    return i > 0 ? e.substring(0, i) : (e.isNotEmpty ? e : 'user');
  }

  bool _isGeneralUser(Map<String, dynamic> data) {
    final raw = (data['role'] ?? 'user').toString().trim();
    final role = raw.isEmpty ? 'user' : raw.toLowerCase();
    return role != 'admin' && role != 'super';
  }

  Future<int> _favCount(String uid) async {
    try {
      final top = await FirebaseFirestore.instance
          .collection('likes')
          .where('userUid', isEqualTo: uid)
          .count()
          .get();
      final c = top.count ?? 0;
      if (c > 0) return c;
    } catch (_) {
      // ignore and try legacy
    }
    try {
      final legacy = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('likes')
          .count()
          .get();
      return legacy.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _matchSearch({
    required String q,
    required String email,
    required String idLabel,
  }) {
    if (q.isEmpty) return true;
    final qq = q.toLowerCase();
    return email.toLowerCase().contains(qq) || idLabel.toLowerCase().contains(qq);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final line = theme.dividerTheme.color ?? Colors.transparent;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        title: Text(
          '회원 좋아요 탐색',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Column(
            children: [
              Divider(height: 1, color: line),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchC,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '아이디/이메일 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchC.text.isEmpty
                          ? null
                          : IconButton(
                        onPressed: () {
                          _searchC.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1A1D22)
                          : const Color(0xFFF4F4F4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.onSurface.withOpacity(0.35)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').orderBy('email').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface),
            );
          }
          if (!snap.hasData) {
            return Center(
              child: Text(
                '데이터가 없습니다.',
                style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
              ),
            );
          }

          final q = _searchC.text.trim();

          final all = snap.data!.docs;
          final users = all
              .where((d) => _isGeneralUser(d.data()))
              .where((d) {
            final data = d.data();
            final email = (data['email'] ?? '').toString();
            final idLabel = _idOf(email);
            return _matchSearch(q: q, email: email, idLabel: idLabel);
          })
              .toList();

          if (users.isEmpty) {
            return Center(
              child: Text(
                q.isEmpty ? '일반 회원이 없습니다.' : '검색 결과가 없습니다.',
                style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 15),
              ),
            );
          }

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) {
              final d = users[i];
              final data = d.data();
              final email = (data['email'] ?? '').toString();
              final idLabel = _idOf(email);

              return _UserCard(
                uid: d.id,
                idLabel: idLabel,
                favCountFuture: _favCount(d.id),
                isDark: isDark,
                cs: cs,
                lineColor: line,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LikedUserDetailPage(
                        userUid: d.id,
                        userIdLabel: idLabel,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// ───────────────────────── 쫀득한 3D 유저 카드 위젯 ─────────────────────────
class _UserCard extends StatefulWidget {
  final String uid;
  final String idLabel;
  final Future<int> favCountFuture;
  final bool isDark;
  final ColorScheme cs;
  final Color lineColor;
  final VoidCallback onTap;

  const _UserCard({
    required this.uid,
    required this.idLabel,
    required this.favCountFuture,
    required this.isDark,
    required this.cs,
    required this.lineColor,
    required this.onTap,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1A1D22) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.lineColor, width: 0.5),
            boxShadow: _down
                ? []
                : [
              BoxShadow(
                color: widget.isDark
                    ? Colors.black45
                    : Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.cs.onSurface.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.idLabel.isNotEmpty
                        ? widget.idLabel.characters.first.toUpperCase()
                        : 'U',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: widget.cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.idLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: widget.cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FutureBuilder<int>(
                future: widget.favCountFuture,
                builder: (_, countSnap) {
                  final n = countSnap.data ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, size: 12, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(
                          '$n',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: widget.cs.onSurface.withOpacity(0.25), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}