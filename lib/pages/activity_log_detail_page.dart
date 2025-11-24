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

  // 하루 이벤트(로그인/로그아웃)
  Stream<List<_Event>> _dayEventsStream(String uid, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return FirebaseFirestore.instance
        .collection('activity_logs')
        .where('uid', isEqualTo: uid)
    // orderBy 없이 인덱스 필요 없게
        .limit(2000)
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
        String? kind;
        if (raw == 'login' || raw == 'sign_in' || raw == '로그인') {
          kind = 'login';
        } else if (raw == 'logout' || raw == 'sign_out' || raw == '로그아웃') {
          kind = 'logout';
        }
        if (kind == null) continue;

        out.add(_Event(kind, t));
      }

      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return StreamBuilder<List<_Event>>(
      stream: _dayEventsStream(widget.userUid, _day),
      builder: (context, snap) {
        final events = snap.data ?? const <_Event>[];
        final summary = _buildSummary(events, _day);
        final hasError = snap.hasError;

        // 가로로 길게 쓸 폭 (현재 화면 폭의 2.5배)
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
                    color: summary.openSessionOpen
                        ? const Color(0xff2e7d32) // 현재 온라인
                        : const Color(0xffc62828), // 오프라인
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prev),
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
              // ───── 요약 카드 ─────
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
                    _chip(
                      '상태',
                      summary.openSessionOpen ? '로그인 중' : '로그아웃',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ───── 타임라인 (슬라이드 가능, 축 + 점만) ─────
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

              // ───── 접속 구간 텍스트 ─────
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

              // ───── 에러 표시 ─────
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
  }

  // ───────── 요약 + 세션 리스트 계산 ─────────
  _Summary _buildSummary(List<_Event> events, DateTime day) {
    if (events.isEmpty) return _Summary.zero();

    final isToday = _strip(DateTime.now()) == _strip(day);
    const onlineWindow = Duration(minutes: 10);

    events.sort((a, b) => a.at.compareTo(b.at));

    int sessions = 0;
    Duration total = Duration.zero;
    DateTime? lastLogin;
    final ranges = <_Session>[];

    for (final e in events) {
      if (e.kind == 'login') {
        if (lastLogin != null) {
          // 이전 세션 강제로 종료
          if (!e.at.isBefore(lastLogin)) {
            final d = e.at.difference(lastLogin);
            total += d;
            sessions++;
            ranges.add(_Session(start: lastLogin, end: e.at));
          }
        }
        lastLogin = e.at;
      } else if (e.kind == 'logout') {
        if (lastLogin != null) {
          if (!e.at.isBefore(lastLogin)) {
            final d = e.at.difference(lastLogin);
            total += d;
            sessions++;
            ranges.add(_Session(start: lastLogin, end: e.at));
          }
          lastLogin = null;
        }
      }
    }

    bool openSessionOpen = false;

    if (lastLogin != null) {
      if (isToday) {
        final now = DateTime.now();
        if (!now.isBefore(lastLogin)) {
          final d = now.difference(lastLogin);
          total += d;
          sessions++;
          ranges.add(_Session(start: lastLogin, end: now));
        }
        final diff = now.difference(lastLogin);
        openSessionOpen = diff <= onlineWindow;
      } else {
        final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
        if (!endOfDay.isBefore(lastLogin)) {
          final d = endOfDay.difference(lastLogin);
          total += d;
          sessions++;
          ranges.add(_Session(start: lastLogin, end: endOfDay));
        }
        openSessionOpen = false;
      }
    } else {
      if (events.isNotEmpty && events.last.kind == 'login' && isToday) {
        final diff = DateTime.now().difference(events.last.at);
        openSessionOpen = diff <= onlineWindow;
      }
    }

    return _Summary(
      sessions: sessions,
      total: total,
      openSessionOpen: openSessionOpen,
      ranges: ranges,
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _fmtTime(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}';

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
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

// ---- 모델 ----
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
  final bool openSessionOpen;
  final List<_Session> ranges;

  _Summary({
    required this.sessions,
    required this.total,
    required this.openSessionOpen,
    required this.ranges,
  });

  factory _Summary.zero() =>
      _Summary(sessions: 0, total: Duration.zero, openSessionOpen: false, ranges: const []);
}

/// 축 + 점만 그리는 페인터 (시간 라벨 없음 → 안 겹침)
class _TimelinePainter extends CustomPainter {
  final List<_Event> events;

  _TimelinePainter({required this.events});

  static const double pad = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final baseY = h * 0.55;

    // ── 축 & 눈금 ──
    final axis = Paint()
      ..color = const Color(0xff333333)
      ..strokeWidth = 1.2;
    final tick = Paint()
      ..color = const Color(0xffaaaaaa)
      ..strokeWidth = 0.8;

    // 축
    canvas.drawLine(Offset(pad, baseY), Offset(w - pad, baseY), axis);

    // 시간 눈금 + 3시간 라벨
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

    // ── 로그인/로그아웃 점만 표시 ──
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
      final cy = baseY + dy;
      canvas.drawCircle(Offset(x, cy), 4.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.events != events;
  }
}
