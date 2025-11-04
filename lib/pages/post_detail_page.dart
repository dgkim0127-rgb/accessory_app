// lib/pages/post_detail_page.dart  ✅ 최종: 두 손가락 전용 줌 + 딤 오버레이 + 브랜드 헤더(점3개)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'edit_post_page.dart';
import 'brand_profile_page.dart';

class PostDetailPage extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;
  const PostDetailPage({super.key, required this.postId, required this.data});

  Future<bool> _isAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final role = (doc.data()?['role'] as String?)?.toLowerCase() ?? 'user';
      return role == 'admin' || role == 'super';
    } catch (_) {
      return false;
    }
  }

  bool _isOwner() => FirebaseAuth.instance.currentUser?.uid == data['uid'];

  @override
  Widget build(BuildContext context) {
    final img   = (data['imageUrl'] ?? '').toString();
    final title = (data['title'] ?? '').toString();
    final desc  = (data['description'] ?? '').toString();

    // 브랜드 정보
    final brandKor  = (data['brand'] ?? '').toString();
    final brandEng  = (data['brandEng'] ?? '').toString();
    final logoUrl   = (data['brandLogoUrl'] ?? data['logoUrl'] ?? '').toString();

    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, snap) {
        final isAdmin = snap.data == true;
        final isOwner = _isOwner();

        return Scaffold(
          appBar: AppBar(
            title: const Text('게시물'),
            centerTitle: false,
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ====== 브랜드 영역(터치 → BrandProfilePage) + 점3개(세로) ======
              _BrandHeaderRow(
                brandKor: brandKor,
                brandEng: brandEng,
                logoUrl: logoUrl,
                createdAt: data['createdAt'],
                isAdmin: isAdmin,
                isOwner: isOwner,
                onEdit: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditPostPage(postId: postId, initialData: data),
                    ),
                  );
                },
                onDelete: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('삭제 확인'),
                      content: const Text('이 게시물을 삭제하시겠습니까?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await FirebaseFirestore.instance.collection('posts').doc(postId).delete();
                      if (img.startsWith('http')) {
                        try { await FirebaseStorage.instance.refFromURL(img).delete(); } catch (_) {}
                      }
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('삭제 실패: $e')),
                        );
                      }
                    }
                  }
                },
              ),

              // ====== 이미지: 두 손가락 전용 확대/이동 + 딤 오버레이 + 손 떼면 원상복구 ======
              SizedBox(
                height: MediaQuery.of(context).size.width * 5 / 4, // 4:5 프레임
                child: _TwoFingerZoomImage(
                  url: img,
                ),
              ),

              // ====== 제목 / 좋아요 버튼 (제목-설명 간격 촘촘) ======
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title.isEmpty ? '(제목 없음)' : title,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () {/* TODO: 좋아요 */},
                      icon: const Icon(Icons.favorite_border),
                      splashRadius: 18,
                      tooltip: '좋아요',
                    ),
                  ],
                ),
              ),

              if (desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                  child: Text(
                    desc,
                    style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.3),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 브랜드 헤더(아이콘 + 이름 + 날짜 + ⋮)
class _BrandHeaderRow extends StatelessWidget {
  final String brandKor;
  final String brandEng;
  final String logoUrl;
  final dynamic createdAt;
  final bool isAdmin;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BrandHeaderRow({
    required this.brandKor,
    required this.brandEng,
    required this.logoUrl,
    required this.createdAt,
    required this.isAdmin,
    required this.isOwner,
    required this.onEdit,
    required this.onDelete,
  });

  static String _humanize(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    String _2(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}.${_2(dt.month)}.${_2(dt.day)}';
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE6E6E6);
    final dateStr = (createdAt is Timestamp) ? _humanize((createdAt as Timestamp).toDate()) : '';
    final displayKor = brandKor.isEmpty ? 'ALL' : brandKor;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BrandProfilePage(
                    brandKor: displayKor,
                    brandEng: brandEng,
                    isAdmin: isAdmin,
                  ),
                ),
              );
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0x11000000),
                  backgroundImage: (logoUrl.isNotEmpty) ? NetworkImage(logoUrl) : null,
                  child: (logoUrl.isEmpty)
                      ? const Icon(Icons.store, color: Colors.black54)
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayKor, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          if (isAdmin || isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onSelected: (v) {
                if (v == 'edit') {
                  onEdit();
                } else if (v == 'delete' && isAdmin) {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('수정')),
                if (isAdmin)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('삭제', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 두 손가락 전용 줌 + 더 빠른 인식 + 확대 중 딤 오버레이 + 손 떼면 원복
class _TwoFingerZoomImage extends StatefulWidget {
  final String url;
  const _TwoFingerZoomImage({required this.url});

  @override
  State<_TwoFingerZoomImage> createState() => _TwoFingerZoomImageState();
}

class _TwoFingerZoomImageState extends State<_TwoFingerZoomImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _tc = TransformationController();
  late final AnimationController _anim;
  Animation<Matrix4>? _resetTween;

  // 포인터/줌 상태
  int _pointers = 0;
  bool _zooming = false;
  double _dim = 0.0; // 0~0.28

  static const double _dimMax = 0.28;
  static const double _zoomThreshold = 1.005; // 민감도 ↑ (빠르게 줌 인식)

  // 빠른 멀티터치 인식(더블-포인터)
  DateTime? _lastPointerDownAt;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        _tc.value = _resetTween?.value ?? Matrix4.identity();
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _setZooming(false);
          _setDim(0.0);
        }
      });
  }

  @override
  void dispose() {
    _anim.dispose();
    _tc.dispose();
    super.dispose();
  }

  void _setZooming(bool z) {
    if (_zooming == z) return;
    setState(() => _zooming = z);
  }

  void _setDim(double v) {
    final nv = v.clamp(0.0, _dimMax);
    if ((nv - _dim).abs() < 0.01) return;
    setState(() => _dim = nv);
  }

  void _animateBack() {
    _anim.stop();
    _resetTween = Matrix4Tween(
      begin: _tc.value,
      end: Matrix4.identity(),
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_anim);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;

    return Listener(
      onPointerDown: (_) {
        final now = DateTime.now();
        // 180ms 안에 두 번째 손가락이 닿으면 바로 멀티터치로 간주 → 더 빠른 반응
        if (_lastPointerDownAt != null &&
            now.difference(_lastPointerDownAt!).inMilliseconds < 180) {
          _pointers = (_pointers + 1).clamp(0, 10);
        } else {
          _pointers = (_pointers + 1).clamp(0, 10);
        }
        _lastPointerDownAt = now;
        if (_pointers >= 2) {
          _setZooming(true);
          _setDim(_dimMax); // 멀티터치 순간 바로 딤 켜기
        }
      },
      onPointerUp: (_) {
        _pointers = (_pointers - 1).clamp(0, 10);
        if (_pointers < 2) {
          _animateBack();
        }
      },
      onPointerCancel: (_) {
        _pointers = (_pointers - 1).clamp(0, 10);
        if (_pointers < 2) {
          _animateBack();
        }
      },
      child: LayoutBuilder(
        builder: (_, constraints) {
          final frameW = constraints.maxWidth;
          final frameH = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            children: [
              InteractiveViewer(
                transformationController: _tc,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(99999),
                minScale: 1.0,
                maxScale: 4.0,
                // 두 손가락(>=2)일 때만 이동 허용
                panEnabled: _pointers >= 2,
                scaleEnabled: true, // 핀치 줌
                clipBehavior: Clip.none,
                onInteractionStart: (_) {
                  if (_pointers >= 2) {
                    _setZooming(true);
                    _setDim(_dimMax);
                  }
                },
                onInteractionUpdate: (_) {
                  final s = _tc.value.getMaxScaleOnAxis();
                  // 아주 미세한 확대에서도 바로 인식되도록 임계값 낮춤
                  _setZooming(s > _zoomThreshold);
                  _setDim(_zooming ? _dimMax : 0.0);
                },
                onInteractionEnd: (_) => _animateBack(),
                child: SizedBox(
                  width: frameW,
                  height: frameH,
                  child: (url.isNotEmpty)
                      ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image, size: 40)),
                    loadingBuilder: (_, child, ev) =>
                    ev == null ? child : const Center(child: CircularProgressIndicator()),
                  )
                      : const Center(child: Icon(Icons.broken_image, size: 40)),
                ),
              ),

              // 확대 중 딤 오버레이
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: _dim,
                  child: Container(color: Colors.black),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
