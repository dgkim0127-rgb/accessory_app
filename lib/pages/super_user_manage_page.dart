import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class SuperUserManagePage extends StatelessWidget {
  const SuperUserManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final usersRef = FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 관리'),
        actions: [
          IconButton(
            tooltip: '회원 추가',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => _showCreateUserDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data?.docs ?? [];
          if (users.isEmpty) return const Center(child: Text('회원이 없습니다.'));

          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = users[i];
              final data = doc.data();
              final uid = doc.id;
              final email = (data['email'] as String?) ?? uid;
              final name = (data['name'] as String?) ?? '';
              final role = (data['role'] as String?) ?? 'user';
              final disabled = (data['disabled'] as bool?) ?? false;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.black12,
                  child: Text(
                    (name.isNotEmpty ? name : email).substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                title: Text(name.isNotEmpty ? name : email.split('@').first),
                subtitle: Text('$email  •  $role${disabled ? '  •  비활성화' : ''}'),
                trailing: PopupMenuButton<String>(
                  tooltip: '역할/삭제',
                  onSelected: (v) async {
                    switch (v) {
                      case 'user':
                      case 'admin':
                      case 'super':
                        await _setRole(uid, v, context);
                        break;
                      case 'toggle-disable':
                        await _toggleDisable(uid, !disabled, context);
                        break;
                      case 'delete':
                        await _confirmDelete(uid, context);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'user', child: Text('역할: user')),
                    const PopupMenuItem(value: 'admin', child: Text('역할: admin')),
                    const PopupMenuItem(value: 'super', child: Text('역할: super')),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'toggle-disable',
                      child: Text(disabled ? '활성화로 전환' : '비활성화로 전환'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('계정 완전 삭제(Functions)'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _setRole(String uid, String role, BuildContext ctx) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'role': role});
      _toast(ctx, '역할을 $role 로 변경했습니다.');
    } catch (e) {
      _toast(ctx, '역할 변경 실패: $e');
    }
  }

  Future<void> _toggleDisable(String uid, bool disable, BuildContext ctx) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'disabled': disable},
        SetOptions(merge: true),
      );
      _toast(ctx, disable ? '비활성화했습니다.' : '활성화했습니다.');
    } catch (e) {
      _toast(ctx, '상태 변경 실패: $e');
    }
  }

  Future<void> _confirmDelete(String uid, BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('계정 삭제'),
        content: Text('정말로 삭제하시겠어요?\n(uid: $uid)\n\n(Cloud Functions 필요)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('superDeleteUser');
        await callable.call({'uid': uid}); // 관리자 SDK로 Auth 삭제 + 데이터 정리
        _toast(ctx, '삭제 요청을 완료했습니다.');
      } catch (e) {
        _toast(ctx, '삭제 실패(Functions 미배포?): $e');
      }
    }
  }

  Future<void> _showCreateUserDialog(BuildContext ctx) async {
    final idCtrl = TextEditingController();
    final pwCtrl = TextEditingController();
    String role = 'user';

    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('회원 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                labelText: '아이디 (이메일은 @test.com 자동)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '임시 비밀번호'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('역할:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: role,
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('user')),
                    DropdownMenuItem(value: 'admin', child: Text('admin')),
                    DropdownMenuItem(value: 'super', child: Text('super')),
                  ],
                  onChanged: (v) => role = v ?? 'user',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('추가')),
        ],
      ),
    );

    if (ok == true) {
      final email = '${idCtrl.text.trim()}@test.com';
      final password = pwCtrl.text;
      try {
        // Cloud Functions: superCreateUser (email/password/role)
        final callable = FirebaseFunctions.instance.httpsCallable('superCreateUser');
        await callable.call({'email': email, 'password': password, 'role': role});
        _toast(ctx, '회원이 추가되었습니다.');
      } catch (e) {
        _toast(ctx, '추가 실패(Functions 미배포?): $e');
      }
    }
  }

  void _toast(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }
}
