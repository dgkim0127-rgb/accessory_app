import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ActivityLogDetailPage extends StatefulWidget {
  final String userUid;
  final String displayName;

  const ActivityLogDetailPage({
    super.key,
    required this.userUid,
    required this.displayName,
  });

  @override
  State<ActivityLogDetailPage> createState() => _ActivityLogDetailPageState();
}

class _ActivityLogDetailPageState extends State<ActivityLogDetailPage> {
  DateTime _day = _strip(DateTime.now());
  static DateTime _strip(DateTime d) => DateTime(d.year, d.month, d.day);

  void _prev() => setState(() => _day = _day.subtract(const Duration(days: 1)));
  void _next() => setState(() => _day = _day.add(const Duration(days: 1)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _day = _strip(d));
  }

  // ✅ 활동중(초록/빨강) 판단 시간
  static const Duration onlineWindow = Duration(seconds: 20);

  /// ✅ users/{uid}.lastSeenAt 기반 “지금 활동중” + lastSeenAt 반환
  Stream<_Presence> _presenceStream(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snap) {
      final data = snap.data() ?? {};
      final ts = data['lastSeenAt'];
      DateTime? lastSeenAt;
      if (ts is Timestamp) lastSeenAt = ts.toDate();

      final active = (lastSeenAt != null) &&
          (DateTime.now().difference(lastSeenAt) <= onlineWindow);

      return _Presence(isActiveNow: active, lastSeenAt: lastSeenAt);
    });
  }

  /// ✅ 하루 이벤트(로그인/로그아웃) - pause/resume도 반영
  Stream<List<_Event>> _dayEventsStream(String uid, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return FirebaseFirestore.instance
        .collection('activity_logs')
        .where('uid', isEqualTo: uid)
        .limit(3000)
        .snapshots()
        .map((snap) {
      final out = <_Event>[];

      for (final d in snap.docs) {
        final m = d.data();
        final ts = m['createdAt'];
        if (ts is! Timestamp) continue;

        final t = ts.toDate();
        if (t.isBefore(start) || !t.isBefore(end)) continue;

        final raw = (m['action'] ?? m['type'] ?? '').toString().toLowerCase();

        // ✅ resume -> login, pause -> logout
        if (raw == 'login' || raw == 'sign_in' || raw == 'resume' || raw == '로그인') {
          out.add(_Event('login', t));
        } else if (raw == 'logout' || raw == 'sign_out' || raw == 'pause' || raw == '로그아웃') {
          out.add(_Event('logout', t));
        }
      }

      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return StreamBuilder<_Presence>(
      stream: _presenceStream(widget.userUid),
      builder: (context, presSnap) {
        final presence =
            presSnap.data ?? const _Presence(isActiveNow: false, lastSeenAt: null);

        return StreamBuilder<List<_Event>>(
          stream: _dayEventsStream(widget.userUid, _day),
          builder: (context, snap) {
            final events = snap.data ?? const <_Event>[];
            final summary = _buildSummary(
              events: events,
              day: _day,
              isActiveNow: presence.isActiveNow,
              lastSeenAt: presence.lastSeenAt,
            );
            final hasError = snap.hasError;

            final double timelineWidth =
                MediaQuery.of(context).size.width * 2.5;

            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    Text(
                      '${widget.displayName} – 활동(하루)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: presence.isActiveNow
                            ? const Color(0xff2e7d32)
                            : const Color(0xffc62828),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left), onPressed: _prev),
                  TextButton(
                    onPressed: _pickDate,
                    child: Text(
                      '${_day.year}.${_two(_day.month)}.${_two(_day.day)}',
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.chevron_right), onPressed: _next),
                ],
                bottom: const PreferredSize(
                  preferredSize: Size.fromHeight(1),
                  child: Divider(height: 1),
                ),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _chip('세션 수', '${summary.sessions}'),
                        const SizedBox(width: 8),
                        _chip('총 접속시간', _humanDuration(summary.total)),
                        const SizedBox(width: 8),
                        _chip('상태', presence.isActiveNow ? '활동 중' : '비활동'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    child: SizedBox(
                      height: 200,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: timelineWidth,
                          height: 200,
                          child: CustomPaint(
                            painter: _TimelinePainter(events: events),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (summary.ranges.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '접속 구간',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...summary.ranges.asMap().entries.map((e) {
                            final idx = e.key + 1;
                            final r = e.value;
                            final from = _fmtTime(r.start);
                            final to = _fmtTime(r.end);
                            final dur = r.end.difference(r.start);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '$idx) $from ~ $to (${_humanDuration(dur)})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: const Text(
                        '해당 날짜의 접속 기록이 없습니다.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),

                  const SizedBox(height: 14),

                  if (hasError)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: line),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '로그를 불러오는 중 오류가 발생했습니다.\n${snap.error}',
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// ✅ 핵심 변경:
  /// - lastLogin만 있고 logout이 없으면
  ///   - 초록(활동중): end = now
  ///   - 빨강(비활동): end = lastSeenAt (없으면 마지막 이벤트 시각)
  _Summary _buildSummary({
    required List<_Event> events,
    required DateTime day,
    required bool isActiveNow,
    required DateTime? lastSeenAt,
  }) {
    if (events.isEmpty) return _Summary.zero();

    final isToday = _strip(DateTime.now()) == _strip(day);

    events.sort((a, b) => a.at.compareTo(b.at));

    int sessions = 0;
    Duration total = Duration.zero;
    DateTime? lastLogin;
    final ranges = <_Session>[];

    for (final e in events) {
      if (e.kind == 'login') {
        if (lastLogin == null) {
          lastLogin = e.at;
        }
      } else if (e.kind == 'logout') {
        if (lastLogin != null && !e.at.isBefore(lastLogin)) {
          final d = e.at.difference(lastLogin);
          total += d;
          sessions++;
          ranges.add(_Session(start: lastLogin, end: e.at));
        }
        lastLogin = null;
      }
    }

    // ✅ 열린 세션 처리(로그아웃 없이 login만 있는 경우)
    if (lastLogin != null) {
      DateTime end;

      if (isToday) {
        if (isActiveNow) {
          end = DateTime.now();
        } else {
          end = lastSeenAt ?? events.last.at; // ✅ 빨강이면 now 금지
        }
      } else {
        // 과거 날짜는 그날 끝까지만
        end = DateTime(day.year, day.month, day.day, 23, 59, 59);
      }

      if (!end.isBefore(lastLogin)) {
        final d = end.difference(lastLogin);
        total += d;
        sessions++;
        ranges.add(_Session(start: lastLogin, end: end));
      }
    }

    return _Summary(
      sessions: sessions,
      total: total,
      ranges: ranges,
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmtTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _humanDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}시간 ${m}분';
    if (m > 0) return '${m}분 ${s}초';
    return '${s}초';
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffe6e6e6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }
}

class _Presence {
  final bool isActiveNow;
  final DateTime? lastSeenAt;
  const _Presence({required this.isActiveNow, required this.lastSeenAt});
}

class _Event {
  final String kind; // 'login' / 'logout'
  final DateTime at;
  _Event(this.kind, this.at);
}

class _Session {
  final DateTime start;
  final DateTime end;
  _Session({required this.start, required this.end});
}

class _Summary {
  final int sessions;
  final Duration total;
  final List<_Session> ranges;

  _Summary({
    required this.sessions,
    required this.total,
    required this.ranges,
  });

  factory _Summary.zero() => _Summary(
    sessions: 0,
    total: Duration.zero,
    ranges: const [],
  );
}

class _TimelinePainter extends CustomPainter {
  final List<_Event> events;

  _TimelinePainter({required this.events});

  static const double pad = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baseY = h * 0.55;

    final axis = Paint()
      ..color = const Color(0xff333333)
      ..strokeWidth = 1.2;
    final tick = Paint()
      ..color = const Color(0xffaaaaaa)
      ..strokeWidth = 0.8;

    canvas.drawLine(Offset(pad, baseY), Offset(w - pad, baseY), axis);

    final tp = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    for (int hour = 0; hour <= 24; hour++) {
      final x = pad + (w - pad * 2) * (hour / 24.0);
      canvas.drawLine(Offset(x, baseY - 6), Offset(x, baseY + 6), tick);

      if (hour % 3 == 0) {
        tp.text = TextSpan(
          text: hour.toString().padLeft(2, '0'),
          style: const TextStyle(fontSize: 10, color: Colors.black87),
        );
        tp.layout();
        tp.paint(canvas, Offset(x - tp.width / 2, baseY + 10));
      }
    }

    if (events.isEmpty) return;

    final dotLogin = Paint()..color = const Color(0xff2e7d32);
    final dotLogout = Paint()..color = const Color(0xffc62828);

    double xOf(DateTime t) {
      final hh = t.hour + t.minute / 60.0 + t.second / 3600.0;
      return pad + (w - pad * 2) * (hh / 24.0);
    }

    for (final e in events) {
      final x = xOf(e.at);
      final isLogin = e.kind == 'login';
      final paint = isLogin ? dotLogin : dotLogout;
      final dy = isLogin ? -8.0 : 8.0;
      canvas.drawCircle(Offset(x, baseY + dy), 4.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.events != events;
  }
}