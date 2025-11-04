import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LikeService {
  LikeService._();
  static final LikeService instance = LikeService._();

  final _fs = FirebaseFirestore.instance;
  User? get _user => FirebaseAuth.instance.currentUser;

  String _likeDocId(String postId, String uid) => '${postId}_$uid';

  /// 실시간: 로그인 사용자가 postId를 좋아요했는지
  Stream<bool> watchLiked(String postId) async* {
    final u = _user;
    if (u == null) {
      yield false;
      return;
    }
    final docId = _likeDocId(postId, u.uid);
    yield* _fs.collection('likes').doc(docId).snapshots().map((s) => s.exists);
  }

  /// 단발 조회
  Future<bool> isLiked(String postId) async {
    final u = _user;
    if (u == null) return false;
    final docId = _likeDocId(postId, u.uid);
    final doc = await _fs.collection('likes').doc(docId).get();
    return doc.exists;
  }

  /// 토글: likes 문서 생성/삭제 + posts.likes 카운터 ±1 (트랜잭션)
  Future<void> toggle(String postId) async {
    final u = _user;
    if (u == null) throw '로그인이 필요합니다.';

    final likeRef = _fs.collection('likes').doc(_likeDocId(postId, u.uid));
    final postRef = _fs.collection('posts').doc(postId);

    return _fs.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final postSnap = await tx.get(postRef);
      if (!postSnap.exists) throw '게시물이 없습니다.';

      final currLikes = (postSnap.data()?['likes'] ?? 0) as int;

      if (likeSnap.exists) {
        // 이미 좋아요 → 취소
        tx.delete(likeRef);
        tx.update(postRef, {'likes': currLikes - 1});
      } else {
        // 최초 좋아요
        tx.set(likeRef, {
          'postId': postId,
          'userUid': u.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.update(postRef, {'likes': currLikes + 1});
      }
    });
  }
}
