// lib/pages/activity_logs_page.dart ✅ 최종(접속중 = lastSeenAt만)
// - 로그인 잠금(isLoggedIn)은 접속중 표시에서 사용 ❌
// - lastSeenAt이 onlineWindow 이내면 초록
// - 백그라운드로 가면 ping이 멈춰 lastSeenAt이 갱신되지 않아서 빨강으로 전환

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
  final TextEditingController _searchC = TextEditingController();
  String _myRole = "user";
  bool _roleReady = false;

  // ✅ 백그라운드로 가면 빨강으로 빨리 바뀌게 하고 싶으면 10~20초 추천
  static const Duration onlineWindow = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      setState(() {
        _myRole = "guest";
        _roleReady = true;
      });
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection("users")
          .doc(me.uid)
          .get();

      final role = (snap.data()?["role"] ?? "user").toString().toLowerCase();
      setState(() {
        _myRole = role;
        _roleReady = true;
      });
    } catch (_) {
      setState(() => _roleReady = true);
    }
  }

  bool _canShow(String role) {
    final r = role.toLowerCase();
    if (_myRole == "super") return true;
    if (_myRole == "admin") return r != "admin" && r != "super";
    return false;
  }

  bool _isActiveFromLastSeen(Map<String, dynamic> userMap) {
    final ts = userMap["lastSeenAt"];
    if (ts is! Timestamp) return false;

    final last = ts.toDate();
    final diff = DateTime.now().difference(last);
    return diff <= onlineWindow;
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
        title: const Text("활동 로그 – 회원 선택"),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchC,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: "이메일 / 아이디 검색",
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const Divider(height: 1, color: line),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .orderBy("email")
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 1.3));
                }

                var list = snap.data!.docs;

                list = list.where((d) {
                  final m = d.data();
                  final role = (m["role"] ?? "user").toString();
                  return _canShow(role);
                }).toList();

                final q = _searchC.text.trim().toLowerCase();
                if (q.isNotEmpty) {
                  list = list.where((d) {
                    final m = d.data();
                    final email = (m["email"] ?? "").toString().toLowerCase();
                    final idPart = email.split("@").first;
                    return email.contains(q) || idPart.contains(q);
                  }).toList();
                }

                if (list.isEmpty) {
                  return const Center(
                    child: Text("표시할 회원이 없습니다.",
                        style: TextStyle(color: Colors.black54)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final d = list[i];
                    final m = d.data();
                    final uid = d.id;

                    final email = (m["email"] ?? "").toString();
                    final name = email.split("@").first;
                    final role = (m["role"] ?? "user").toString().toLowerCase();

                    final isActive = _isActiveFromLastSeen(m);

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ActivityLogDetailPage(
                              userUid: uid,
                              displayName: name,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: line),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFF1F1F1),
                              child: Text(
                                name.isEmpty ? "?" : name[0].toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isActive
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: role == "user"
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFE3F2FD),
                              ),
                              child: Text(
                                role,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right,
                                color: Colors.black45),
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