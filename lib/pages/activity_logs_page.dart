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
  final TextEditingController _searchC = TextEditingController();
  String _myRole = "user";
  bool _roleReady = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
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
      final snap =
      await FirebaseFirestore.instance.collection("users").doc(me.uid).get();

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

  /// 특정 유저의 "마지막 이벤트" login/logout 실시간 표시
  /// - orderBy 없이 클라이언트에서 가장 최근 createdAt 찾음
  /// - 마지막 login 이라도 일정 시간 지나면 logout 으로 간주
  Stream<String> _lastEvent(String uid) {
    return FirebaseFirestore.instance
        .collection("activity_logs")
        .where("uid", isEqualTo: uid)
        .limit(2000)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return "logout";

      QueryDocumentSnapshot<Map<String, dynamic>>? latestDoc;
      Timestamp? latestTs;

      for (final d in snap.docs) {
        final m = d.data();
        final ts = m["createdAt"];
        if (ts is! Timestamp) continue;

        if (latestTs == null || ts.compareTo(latestTs!) > 0) {
          latestTs = ts;
          latestDoc = d;
        }
      }

      if (latestDoc == null || latestTs == null) return "logout";

      final data = latestDoc!.data();
      final action = (data["action"] ?? "logout").toString().toLowerCase();
      final lastTime = latestTs!.toDate();

      // ✅ 최근 10분 이내 login 만 "접속중" 으로 인정
      if (action == "login") {
        final diff = DateTime.now().difference(lastTime);
        const onlineWindow = Duration(minutes: 10); // 필요하면 여기 숫자 바꾸면 됨
        if (diff > onlineWindow) {
          return "logout";
        }
      }

      return action;
    });
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    if (!_roleReady) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
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
          // ───── 검색창 ─────
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

          // ───── 회원 리스트 ─────
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection("users")
                  .orderBy("email")
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.3),
                  );
                }

                var list = snap.data!.docs;

                // 권한 필터링 (항상 data()로 role 꺼내기)
                list = list.where((d) {
                  final m = d.data();
                  final role = (m["role"] ?? "user").toString();
                  return _canShow(role);
                }).toList();

                // 검색 필터
                final q = _searchC.text.trim().toLowerCase();
                if (q.isNotEmpty) {
                  list = list.where((d) {
                    final m = d.data();
                    final email =
                    (m["email"] ?? "").toString().toLowerCase();
                    final idPart = email.split("@").first;
                    return email.contains(q) || idPart.contains(q);
                  }).toList();
                }

                if (list.isEmpty) {
                  return const Center(
                    child: Text(
                      "표시할 회원이 없습니다.",
                      style: TextStyle(color: Colors.black54),
                    ),
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

                    return StreamBuilder<String>(
                      stream: _lastEvent(uid),
                      builder: (context, ev) {
                        final status = ev.data ?? "logout";
                        final isLogin = status == "login";

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
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                // 프로필 이니셜
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFFF1F1F1),
                                  child: Text(
                                    name.isEmpty
                                        ? "?"
                                        : name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // 이름 + 이메일
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
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

                                          // 🔵 현재 접속 상태 원 (login = 초록 / logout = 빨강)
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isLogin
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

                                // 역할 뱃지
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
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
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.black45,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
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
