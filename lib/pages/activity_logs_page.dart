// lib/pages/activity_logs_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'activity_log_detail_page.dart';

class ActivityLogsPage extends StatefulWidget {
  const ActivityLogsPage({super.key});
  @override
  State<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends State<ActivityLogsPage> {
  final _searchC = TextEditingController();
  String? _selectedUid;
  String _myRole = 'user';
  bool _roleReady = false;

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      setState(() { _myRole = 'guest'; _roleReady = true; });
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
      final r = (snap.data()?['role'] ?? 'user').toString().toLowerCase();
      setState(() { _myRole = r.isEmpty ? 'user' : r; _roleReady = true; });
    } catch (_) {
      setState(() { _myRole = 'user'; _roleReady = true; });
    }
  }

  bool _canShow(String roleOfTarget) {
    final t = (roleOfTarget.isEmpty ? 'user' : roleOfTarget.toLowerCase());
    if (_myRole == 'super') return true;                    // 최종관리자: 모두
    if (_myRole == 'admin') return t != 'admin' && t != 'super'; // 관리자: 일반회원만
    return false; // 일반 회원: 리스트에 노출 안 함
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    if (!_roleReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('활동 로그 – 회원 선택'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          // 상단 검색창
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchC,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '이메일 / 아이디 검색',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchC.text.isEmpty
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () { _searchC.clear(); setState(() {}); },
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: line),

          // 회원 리스트
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('email')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
                }

                var docs = snap.data?.docs ?? [];

                // 권한 필터
                docs = docs.where((d) {
                  final role = (d.data()['role'] ?? 'user').toString();
                  return _canShow(role);
                }).toList();

                // 일반회원이면 본인만 (보안상 더블세이프)
                if (_myRole != 'admin' && _myRole != 'super') {
                  final me = FirebaseAuth.instance.currentUser?.uid;
                  docs = docs.where((d) => d.id == me).toList();
                }

                // 검색어 필터
                final q = _searchC.text.trim().toLowerCase();
                if (q.isNotEmpty) {
                  docs = docs.where((d) {
                    final email = (d.data()['email'] ?? '').toString().toLowerCase();
                    final name = email.split('@').first;
                    return email.contains(q) || name.contains(q);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return const Center(child: Text('표시할 회원이 없습니다.', style: TextStyle(color: Colors.black54)));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final m = d.data();
                    final email = (m['email'] ?? '').toString();
                    final idLabel = email.split('@').first;
                    final role = (m['role'] ?? 'user').toString().toLowerCase();
                    final selected = _selectedUid == d.id;

                    return InkWell(
                      onTap: () {
                        setState(() => _selectedUid = d.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActivityLogDetailPage(
                              userUid: d.id,
                              displayName: idLabel,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: line),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFF0F0F0),
                              child: Text(
                                idLabel.isEmpty ? '?' : idLabel.characters.first.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(idLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                  Text(email, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: role == 'user' ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            Icon(selected ? Icons.check_circle : Icons.chevron_right, color: Colors.black45),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
