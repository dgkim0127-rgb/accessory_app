// lib/pages/activity_log_detail_page.dart
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
        .orderBy('createdAt')
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
        final action = (m['action'] ?? m['type'] ?? '').toString().toLowerCase();
        if (action == 'login' || action == 'logout') {
          out.add(_Event(action, t));
        }
      }
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    });
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.displayName} – 활동(하루)'),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _prev),
          TextButton(
            onPressed: _pickDate,
            child: Text('${_day.year}.${_2(_day.month)}.${_2(_day.day)}'),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _next),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: StreamBuilder<List<_Event>>(
        stream: _dayEventsStream(widget.userUid, _day),
        builder: (context, snap) {
          final events = snap.data ?? const <_Event>[];
          final summary = _buildSummary(events);

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
            children: [
              // 요약
              Container(
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line)),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _chip('세션 수', '${summary.sessions}'),
                    const SizedBox(width: 8),
                    _chip('총 접속시간', _humanDuration(summary.total)),
                    const SizedBox(width: 8),
                    _chip('상태', summary.openSessionOpen ? '로그인 중' : '로그아웃'),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 타임라인 (점/눈금)
              Container(
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line)),
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: const SizedBox(height: 140, child: _Timeline()),
              ),

              // 데이터 바인딩을 위해 repaint 신호만 전달
              RepaintBoundary(
                child: _TimelineData(events: events),
              ),

              const SizedBox(height: 14),
              if (events.isEmpty)
                Container(
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: line)),
                  padding: const EdgeInsets.all(12),
                  child: const Text('해당 날짜의 로그인/로그아웃 기록이 없습니다.',
                      style: TextStyle(color: Colors.black54)),
                ),
            ],
          );
        },
      ),
    );
  }

  _Summary _buildSummary(List<_Event> events) {
    if (events.isEmpty) return _Summary.zero();
    int sessions = 0;
    Duration total = Duration.zero;
    DateTime? lastLogin;

    for (final e in events) {
      if (e.kind == 'login') {
        lastLogin = e.at; // 미종료 세션 갱신
      } else if (e.kind == 'logout') {
        if (lastLogin != null) {
          final d = e.at.difference(lastLogin!);
          if (!d.isNegative) {
            total += d;
            sessions += 1;
          }
          lastLogin = null;
        }
      }
    }
    final open = lastLogin != null;
    return _Summary(sessions: sessions, total: total, openSessionOpen: open);
  }

  static String _2(int n) => n.toString().padLeft(2, '0');
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
      decoration: BoxDecoration(border: Border.all(color: const Color(0xffe6e6e6))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(color: Colors.black87)),
      ]),
    );
  }
}

// ---- 모델
class _Event {
  final String kind; // login/logout
  final DateTime at;
  _Event(this.kind, this.at);
}

class _Summary {
  final int sessions;
  final Duration total;
  final bool openSessionOpen;
  _Summary({required this.sessions, required this.total, required this.openSessionOpen});
  factory _Summary.zero() => _Summary(sessions: 0, total: Duration.zero, openSessionOpen: false);
}

/// 축/눈금 그리는 도화지(고정)
class _Timeline extends StatelessWidget {
  const _Timeline({super.key});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _AxisPainter());
  }
}

/// 점(이벤트)만 그리는 레이어(데이터 바인딩)
class _TimelineData extends StatelessWidget {
  final List<_Event> events;
  const _TimelineData({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 0, // 보이지 않게, 하지만 repaint 트리거만
      child: CustomPaint(painter: _DotsPainter(events)),
    );
  }
}

// 축/라벨/눈금
class _AxisPainter extends CustomPainter {
  static const pad = 20.0;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width == 0 ? (canvas.getSaveCount() + 1) * 1.0 : size.width;
    final h = 140.0;
    final baseY = h * 0.55;

    final axis = Paint()..color = const Color(0xff333333)..strokeWidth = 1.2;
    final tick = Paint()..color = const Color(0xffaaaaaa)..strokeWidth = 0.8;

    // 축
    canvas.drawLine(Offset(pad, baseY), Offset(w - pad, baseY), axis);

    // 1시간 눈금 + 3시간 라벨
    final tp = TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);
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
  }
  @override
  bool shouldRepaint(covariant _AxisPainter oldDelegate) => false;
}

// 로그인/로그아웃 점
class _DotsPainter extends CustomPainter {
  final List<_Event> events;
  _DotsPainter(this.events);
  static const pad = 20.0;

  double _xOf(DateTime t, double w) {
    final hh = t.hour + t.minute / 60.0 + t.second / 3600.0;
    return pad + (w - pad * 2) * (hh / 24.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width == 0 ? 360.0 : size.width; // 안전폭
    const h = 140.0;
    final baseY = h * 0.55;

    final dotLogin = Paint()..color = const Color(0xff2e7d32);
    final dotLogout = Paint()..color = const Color(0xffc62828);
    final label = TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);

    for (final e in events) {
      final x = _xOf(e.at, w);
      final isLogin = e.kind == 'login';
      final p = isLogin ? dotLogin : dotLogout;

      // 점 크게
      canvas.drawCircle(Offset(x, baseY), 5.0, p);

      // 시간 라벨(점 아래)
      final hh = e.at.hour.toString().padLeft(2, '0');
      final mm = e.at.minute.toString().padLeft(2, '0');
      label.text = TextSpan(
        text: '$hh:$mm',
        style: TextStyle(
          fontSize: 10,
          color: isLogin ? const Color(0xff2e7d32) : const Color(0xffc62828),
          fontWeight: FontWeight.w600,
        ),
      );
      label.layout();
      label.paint(canvas, Offset(x - label.width / 2, baseY - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.events != events;
}
