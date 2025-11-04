import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'liked_user_detail_page.dart';

/// 관리자/최종관리자 전용: '일반 회원'만 나열
/// - role 필드가 없거나(null) / user(대소문자 아무거나) → 일반 회원으로 간주
/// - admin/super(대소문자 아무거나)는 목록에서 제외
class LikesExplorerPage extends StatelessWidget {
  const LikesExplorerPage({super.key});

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

  /// 좋아요 수 우선순위:
  /// 1) 상위 likes (where userUid == uid)
  /// 2) (fallback) users/{uid}/likes 서브컬렉션
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

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('좋아요 – 일반 회원 목록'),
        centerTitle: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        // 모든 users 구독 후 클라이언트 필터
        stream: FirebaseFirestore.instance
            .collection('users')
            .orderBy('email')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
          }
          if (!snap.hasData) {
            return const Center(child: Text('데이터가 없습니다.'));
          }

          final all = snap.data!.docs;
          final users = all.where((d) => _isGeneralUser(d.data())).toList();

          if (users.isEmpty) {
            return const Center(child: Text('일반 회원이 없습니다.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final d = users[i];
              final data = d.data();
              final email = (data['email'] ?? '').toString();
              final idLabel = _idOf(email);

              return InkWell(
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
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: line),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFF0F0F0),
                        child: Text(
                          idLabel.isNotEmpty
                              ? idLabel.characters.first.toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          idLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FutureBuilder<int>(
                        future: _favCount(d.id),
                        builder: (_, countSnap) {
                          final n = countSnap.data ?? 0;
                          return Text(
                            '♥ $n',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: Colors.black38),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
