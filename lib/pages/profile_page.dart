// lib/pages/profile_page.dart  ✅ 최종
// - 관리자 도구를 "정사각형 타일"로 통일 + hover 효과
// - [앱바 설정] / [공지 설정] / [전체 알림] 각진 직사각형 팝업(GeneralDialog)
// - 앱바 아이콘: 파일 업로드(Firebase Storage) + Firestore URL 저장
// - 잘못 올린 아이콘은 Storage에서 삭제 + 필드 비우기 기능 추가
// - 전체 알림: Cloud Functions callable(broadcastAll) 호출 (기본 리전 사용)

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../auth/auth_gate.dart';
import 'new_post_page.dart';
import 'admin_users_page.dart';
import 'likes_explorer_page.dart';
import 'activity_logs_page.dart';

/// ───────────────────────── 앱바 설정(에디터) ─────────────────────────
/// system/appbar 문서의 titleText / leftImageUrl / rightImageUrl 수정
Future<void> showAppBarEditorDialog(BuildContext context) async {
  final titleC = TextEditingController();
  final leftUrlC = TextEditingController();
  final rightUrlC = TextEditingController();

  // 기존 값 로드
  try {
    final doc =
    await FirebaseFirestore.instance.collection('system').doc('appbar').get();
    final m = doc.data() ?? {};
    titleC.text = (m['titleText'] ?? '').toString();
    leftUrlC.text = (m['leftImageUrl'] ?? '').toString();
    rightUrlC.text = (m['rightImageUrl'] ?? '').toString();
  } catch (_) {}

  // 🔥 이미지 업로드 (왼쪽/오른쪽 공통)
  Future<void> _pickAndUpload({required bool isLeft}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // 모바일/웹 모두 bytes 사용
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        throw '업로드할 데이터를 읽을 수 없습니다. 다시 시도해 주세요.';
      }

      final fileName =
          '${isLeft ? 'left' : 'right'}_${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      final ref = FirebaseStorage.instance
          .ref()
          .child('system')
          .child('appbar')
          .child(fileName);

      final snap = await ref.putData(bytes);
      final url = await snap.ref.getDownloadURL();

      if (isLeft) {
        leftUrlC.text = url;
      } else {
        rightUrlC.text = url;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '파일 업로드 완료: ${isLeft ? '왼쪽 아이콘' : '오른쪽 아이콘'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e')),
        );
      }
    }
  }

  // 🔥 잘못 올린 이미지 삭제 (Storage + 필드 비우기)
  Future<void> _deleteImage({required bool isLeft}) async {
    final url = (isLeft ? leftUrlC.text : rightUrlC.text).trim();
    if (url.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제할 이미지가 없습니다.')),
        );
      }
      return;
    }

    try {
      // Storage에서 삭제 시도
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();

      // 텍스트 필드 비우기
      if (isLeft) {
        leftUrlC.clear();
      } else {
        rightUrlC.clear();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '이미지 삭제 완료: ${isLeft ? '왼쪽 아이콘' : '오른쪽 아이콘'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 삭제 실패: $e')),
        );
      }
    }
  }

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, a2, child) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim.value),
        child: Opacity(
          opacity: anim.value,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1.2),
                    borderRadius: BorderRadius.zero, // ◻ 각진
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '앱바 설정',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleC,
                        decoration: const InputDecoration(
                          labelText: '제목 텍스트 (없으면 아이콘만 사용)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 🔹 왼쪽 아이콘: 파일 업로드 + 삭제
                      const Text(
                        '왼쪽 아이콘 (파일 업로드)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: leftUrlC,
                              readOnly: true,
                              decoration: const InputDecoration(
                                hintText: '선택된 파일 URL이 여기에 표시됩니다.',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 36,
                            child: OutlinedButton(
                              onPressed: () => _pickAndUpload(isLeft: true),
                              style: OutlinedButton.styleFrom(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                                side: const BorderSide(color: Colors.black),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: const Text(
                                '파일 선택',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 36,
                            child: TextButton(
                              onPressed: () => _deleteImage(isLeft: true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: const Text(
                                '지우기',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 🔹 오른쪽 아이콘: 파일 업로드 + 삭제
                      const Text(
                        '오른쪽 아이콘 (파일 업로드)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: rightUrlC,
                              readOnly: true,
                              decoration: const InputDecoration(
                                hintText: '선택된 파일 URL이 여기에 표시됩니다.',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            height: 36,
                            child: OutlinedButton(
                              onPressed: () => _pickAndUpload(isLeft: false),
                              style: OutlinedButton.styleFrom(
                                padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                                side: const BorderSide(color: Colors.black),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              child: const Text(
                                '파일 선택',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 36,
                            child: TextButton(
                              onPressed: () => _deleteImage(isLeft: false),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: const Text(
                                '지우기',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black54,
                              padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(64, 36),
                            ),
                            child: const Text('취소'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(88, 36),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: const Text('저장'),
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

  if (ok != true) return;

  try {
    await FirebaseFirestore.instance.collection('system').doc('appbar').set(
      {
        'titleText': titleC.text.trim(),
        'leftImageUrl': leftUrlC.text.trim(),
        'rightImageUrl': rightUrlC.text.trim(),
      },
      SetOptions(merge: true),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('앱바 설정이 저장되었습니다.')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    }
  }
}

/// ───────────────────────── 공지 설정(에디터) ─────────────────────────
/// 제목/내용 입력 → 게시 시 revision +1, disabled=false, publishedAt 갱신
Future<void> showAnnouncementEditorDialog(BuildContext context) async {
  final titleC = TextEditingController();
  final bodyC = TextEditingController();

  // 기존 값 로드
  try {
    final doc = await FirebaseFirestore.instance
        .collection('system')
        .doc('announcement')
        .get();
    final m = doc.data() ?? {};
    titleC.text = (m['title'] ?? '').toString();
    bodyC.text = (m['body'] ?? '').toString();
  } catch (_) {}

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, a2, child) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim.value),
        child: Opacity(
          opacity: anim.value,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1.2),
                    borderRadius: BorderRadius.zero, // ◻ 각진
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '공지 수정',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleC,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bodyC,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: '내용',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.zero),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black54,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10),
                              minimumSize: const Size(64, 36),
                            ),
                            child: const Text('취소'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(88, 36),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: const Text('게시'),
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

  if (ok != true) return;

  // 저장
  try {
    await FirebaseFirestore.instance
        .collection('system')
        .doc('announcement')
        .set({
      'title': titleC.text.trim(),
      'body': bodyC.text.trim(),
      'disabled': false,
      'publishedAt': FieldValue.serverTimestamp(),
      'revision': FieldValue.increment(1),
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공지 게시 완료')),
      );
      Navigator.of(context).pop(); // 프로필로 복귀
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('게시 실패: $e')),
      );
    }
  }
}

/// ───────────────────────── 전체 알림(푸시) ─────────────────────────
/// super 전용
Future<void> _broadcastAll(BuildContext context) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('웹에서는 푸시 알림 전송을 지원하지 않습니다. 모바일 앱에서 실행해주세요.'),
      ),
    );
    return;
  }

  // 🔥 기본 문구
  final titleC = TextEditingController(text: '새로운 게시물이 등록되었습니다.');
  final bodyC  = TextEditingController(
    text: '지금 앱에서 최신 게시물을 확인해보세요.',
  );

  final ok = await showGeneralDialog<bool>(
    context: context,
    barrierLabel: '닫기',
    barrierDismissible: true,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(anim.value),
        child: Opacity(
          opacity: anim.value,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1.2),
                    borderRadius: BorderRadius.zero,
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '전체 알림 보내기',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleC,
                        decoration: const InputDecoration(
                          labelText: '제목',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: bodyC,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: '내용',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.zero),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.black54,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              minimumSize: const Size(64, 36),
                            ),
                            child: const Text('취소'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(88, 36),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                            ),
                            child: const Text('보내기'),
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

  if (ok != true) return;

  try {
    final functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    final fn = functions.httpsCallable('broadcastAll');

    // 🔥 여기서 함수 호출 + 응답 로그
    final res = await fn.call({
      'title': titleC.text.trim(),
      'body': bodyC.text.trim(),
    });

    // 디버그 콘솔에서 꼭 이 로그를 확인해봐
    debugPrint('broadcastAll result: ${res.data}');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전체 알림 요청 완료')),
      );
    }
  } on FirebaseFunctionsException catch (e) {
    debugPrint('broadcastAll FirebaseFunctionsException: ${e.code} / ${e.message}');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전체 알림 실패: ${e.code} / ${e.message}')),
      );
    }
  } catch (e) {
    debugPrint('broadcastAll error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전체 알림 실패(기타): $e')),
      );
    }
  }
}


class ProfilePage extends StatelessWidget {
  final String role; // 'user' | 'admin' | 'super'
  const ProfilePage({super.key, this.role = 'user'});

  String _initialOf(User u) {
    final e = u.email ?? '';
    final id = e.split('@').first;
    return id.isNotEmpty ? id.characters.first.toUpperCase() : 'U';
  }

  String _idOf(User u) {
    final e = u.email ?? '';
    final id = e.split('@').first;
    return id.isNotEmpty ? id : 'user';
  }

  /// 각진 + 좁은폭 로그아웃 팝업
  Future<void> _logout(BuildContext context) async {
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
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
                      border:
                      Border.all(color: Colors.black, width: 1.2),
                      borderRadius: BorderRadius.zero,
                    ),
                    padding:
                    const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
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
                          mainAxisAlignment:
                          MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, false),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                Colors.black54,
                                minimumSize:
                                const Size(60, 36),
                                padding: const EdgeInsets
                                    .symmetric(
                                  horizontal: 6,
                                ),
                              ),
                              child: const Text('취소'),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                Colors.black,
                                foregroundColor:
                                Colors.white,
                                shape:
                                const RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.zero,
                                ),
                                minimumSize:
                                const Size(70, 36),
                                elevation: 0,
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
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
            (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE6E6E6);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('로그인이 필요합니다.')),
      );
    }

    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        final fsRole =
        (snap.data?.data()?['role'] as String?)?.toLowerCase();
        final effectiveRole = (fsRole ?? role).toLowerCase();
        final isAdmin =
            effectiveRole == 'admin' || effectiveRole == 'super';
        final isSuper = effectiveRole == 'super';

        // 타일 목록(지정 순서)
        final tiles = <Widget>[];
        if (isSuper) {
          tiles.addAll([
            _SquareTool(
              icon: Icons.palette_outlined,
              title: '앱바 설정',
              onTap: () => showAppBarEditorDialog(context),
            ),
            _SquareTool(
              icon: Icons.announcement_outlined,
              title: '공지 설정',
              onTap: () => showAnnouncementEditorDialog(context),
            ),
            _SquareTool(
              icon: Icons.campaign_outlined,
              title: '전체 알림',
              onTap: () => _broadcastAll(context),
            ),
          ]);
        }
        tiles.addAll([
          _SquareTool(
            icon: Icons.favorite_outline,
            title: '회원 좋아요 탐색',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LikesExplorerPage(),
              ),
            ),
          ),
          _SquareTool(
            icon: Icons.event_note_outlined,
            title: '회원 활동 로그',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ActivityLogsPage(),
              ),
            ),
          ),
        ]);
        if (isSuper) {
          tiles.add(
            _SquareTool(
              icon: Icons.group_outlined,
              title: '회원 관리',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminUsersPage(),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: ListView(
              padding:
              const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                // ───── 프로필 상단 ─────
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        border: Border.all(color: line),
                      ),
                      child: Center(
                        child: Text(
                          _initialOf(user),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            _idOf(user),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (isAdmin)
                                _RectBtn(
                                  icon: Icons
                                      .cloud_upload_outlined,
                                  label: '게시물 업로드',
                                  color: Colors.black,
                                  textColor: Colors.white,
                                  height: 28,
                                  minWidth: 110,
                                  iconSize: 14,
                                  fontSize: 11,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                        const NewPostPage(),
                                      ),
                                    );
                                  },
                                ),
                              _RectBtn(
                                icon: Icons.logout,
                                label: '로그아웃',
                                color: const Color(0xFFF3F3F3),
                                textColor: Colors.black,
                                height: 24,
                                minWidth: 84,
                                iconSize: 12,
                                fontSize: 10,
                                onTap: () => _logout(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(height: 1),

                // ───── 관리자 도구(타일) ─────
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '관리자 도구',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics:
                    const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.4,
                    children: tiles,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ───────────────────────── 공용 버튼 위젯들 ─────────────────────────

class _RectBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final double height;
  final double minWidth;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const _RectBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.height = 40,
    this.minWidth = 96,
    this.iconSize = 16,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  @override
  State<_RectBtn> createState() => _RectBtnState();
}

class _RectBtnState extends State<_RectBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minWidth),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 100),
          opacity: _down ? 0.85 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.zero,
              border:
              Border.all(color: const Color(0xFFE6E6E6)),
            ),
            padding: widget.padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: widget.textColor,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.fontSize,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SquareTool extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _SquareTool({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  State<_SquareTool> createState() => _SquareToolState();
}

class _SquareToolState extends State<_SquareTool> {
  bool _down = false;
  bool _hover = false; // hover 상태

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE6E6E6);

    Color _bg() {
      if (_down) return Colors.grey[200]!;
      if (_hover) return Colors.grey[100]!;
      return Colors.white;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap();
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: _down ? 0.85 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _bg(),
              border: Border.all(color: line),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.black87),
                const SizedBox(height: 10),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
