// lib/pages/favorites_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/post_overlay.dart'; // ⬅ 상세 보기

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('로그인이 필요합니다.'));

    // ───────── 새 구조 (top-level likes) ─────────
    final topLevelLikes = FirebaseFirestore.instance
        .collection('likes')
        .where('userUid', isEqualTo: uid)
    // 인덱스 만들기 전이면 아래 한 줄 주석
    // .orderBy('createdAt', descending: true)
        .snapshots();

    // ───────── 구 구조 (users/{uid}/likes) ─────────
    final legacyLikes = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('likes').snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: topLevelLikes,
      builder: (context, topSnap) {
        if (topSnap.hasError) {
          return Center(child: Text('오류: ${topSnap.error}'));
        }

        final topDocs = topSnap.data?.docs ?? [];
        if (topDocs.isNotEmpty) {
          final postIds = topDocs
              .map((d) => (d.data()['postId'] ?? '').toString())
              .where((e) => e.isNotEmpty)
              .toList();

          return _LikedPostsGrid(
            uid: uid,
            postIds: postIds,
            prune: (missing) async {
              final col = FirebaseFirestore.instance.collection('likes');
              for (final pid in missing) {
                try { await col.doc('${pid}_$uid').delete(); } catch (_) {}
              }
            },
          );
        }

        // top-level 비어 있으면 구버전 fallback
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: legacyLikes,
          builder: (context, legacySnap) {
            if (legacySnap.connectionState == ConnectionState.waiting &&
                topSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
            }
            final legacyDocs = legacySnap.data?.docs ?? [];
            if (legacyDocs.isEmpty) {
              return const Center(child: Text('좋아요한 게시물이 없습니다.'));
            }

            final postIds = legacyDocs.map((d) => d.id).toList();
            return _LikedPostsGrid(
              uid: uid,
              postIds: postIds,
              prune: (missing) async {
                final col = FirebaseFirestore.instance
                    .collection('users').doc(uid).collection('likes');
                for (final pid in missing) {
                  try { await col.doc(pid).delete(); } catch (_) {}
                }
              },
            );
          },
        );
      },
    );
  }
}

/// 3열 그리드 + 썸네일 탭 시 PostOverlay로 열기
class _LikedPostsGrid extends StatelessWidget {
  final String uid;
  final List<String> postIds;
  final Future<void> Function(List<String>) prune;

  const _LikedPostsGrid({
    required this.uid,
    required this.postIds,
    required this.prune,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PostsBundle>(
      future: _fetchExistingPostsAndPrune(postIds),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
        }
        final bundle = snap.data;
        final items = bundle?.items ?? [];
        final docs  = bundle?.docs  ?? [];

        if (items.isEmpty) {
          return const Center(child: Text('좋아요한 게시물이 없습니다.'));
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(3, 3, 3, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, // 3열
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            childAspectRatio: 1, // 정사각
          ),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final it = items[i];
            return InkWell(
              onTap: () {
                // 좋아요 그리드 순서를 그대로 유지한 문서 리스트와 함께 상세 보기 오픈
                PostOverlay.show(
                  context,
                  docs: docs,
                  startIndex: i,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: it.imageUrl.isNotEmpty
                    ? Image.network(
                  it.imageUrl,
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
      },
    );
  }

  /// 존재하는 post만 모으고(최신순), 없는 postId는 prune()으로 정리
  Future<_PostsBundle> _fetchExistingPostsAndPrune(List<String> ids) async {
    if (ids.isEmpty) return const _PostsBundle.empty();

    final posts = FirebaseFirestore.instance.collection('posts');
    final found = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    // whereIn 10개 제한 대응
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, (i + 10 > ids.length) ? ids.length : i + 10);
      final qs = await posts
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.serverAndCache));
      found.addAll(qs.docs);
    }

    // 없는 것 정리
    final existingIds = found.map((d) => d.id).toSet();
    final missing     = ids.where((id) => !existingIds.contains(id)).toList();
    if (missing.isNotEmpty) await prune(missing);

    // 최신순
    found.sort((a, b) {
      final ta = a.data()['createdAt'];
      final tb = b.data()['createdAt'];
      final da = (ta is Timestamp) ? ta.toDate() : DateTime(1970);
      final db = (tb is Timestamp) ? tb.toDate() : DateTime(1970);
      return db.compareTo(da);
    });

    final items = found.map((d) {
      final m = d.data();
      return _PostCardData(
        id: d.id,
        title: (m['title'] ?? '').toString(),
        description: (m['description'] ?? '').toString(),
        imageUrl: (m['imageUrl'] ?? '').toString(),
      );
    }).toList();

    return _PostsBundle(docs: found, items: items);
  }
}

class _PostsBundle {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final List<_PostCardData> items;
  const _PostsBundle({required this.docs, required this.items});
  const _PostsBundle.empty()
      : docs = const [],
        items = const [];
}

class _PostCardData {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  _PostCardData({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
  });
}

// 간단한 썸네일 플레이스홀더들
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
