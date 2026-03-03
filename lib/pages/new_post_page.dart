// lib/pages/new_post_page.dart ✅ 최종(디자인 유지 + 안정성/웹/필드 강화)
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:accessory_app/services/upload_service.dart';
import 'package:accessory_app/utils/cloudinary_image_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const _cats = <_Cat>[
  _Cat('반지', 'ring'),
  _Cat('목걸이', 'necklace'),
  _Cat('팔찌', 'bracelet'),
  _Cat('귀걸이', 'earring'),
  _Cat('기타', 'acc'),
];

class NewPostPage extends StatefulWidget {
  final String? initialBrandKor;
  const NewPostPage({super.key, this.initialBrandKor});

  @override
  State<NewPostPage> createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage> {
  final _form = GlobalKey<FormState>();
  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _codeC = TextEditingController();

  String? _brandKor;
  String? _brandEng;
  String? _brandId;

  final Set<String> _selectedCats = {'ring'};
  final _picker = ImagePicker();

  final List<XFile> _mainImages = [];
  final List<XFile> _spinPicked = [];
  final List<XFile> _videoFiles = [];
  final Map<String, Uint8List> _videoThumbCache = {}; // (현재 미사용, 유지)

  bool _saving = false;
  double _uploadProgress = 0;
  int _uploadPercent = 0;

  @override
  void initState() {
    super.initState();
    _brandKor = widget.initialBrandKor;
    FirebaseAuth.instance.currentUser?.getIdToken(true).catchError((_) {});
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _codeC.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  // ✅ 브랜드 2단 조회: nameKorLower → nameKor
  Future<_BrandResolved> _resolveBrand(String brandKor) async {
    final col = FirebaseFirestore.instance.collection('brands');
    final lower = brandKor.trim().toLowerCase();

    // 1) nameKorLower
    try {
      final q1 = await col
          .where('nameKorLower', isEqualTo: lower)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (q1.docs.isNotEmpty) {
        final d = q1.docs.first;
        final m = d.data();
        return _BrandResolved(
          brandId: d.id,
          brandEng: (m['nameEng'] ?? m['eng'] ?? '').toString().trim(),
        );
      }
    } catch (_) {}

    // 2) nameKor exact
    final q2 = await col
        .where('nameKor', isEqualTo: brandKor.trim())
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (q2.docs.isNotEmpty) {
      final d = q2.docs.first;
      final m = d.data();
      return _BrandResolved(
        brandId: d.id,
        brandEng: (m['nameEng'] ?? m['eng'] ?? '').toString().trim(),
      );
    }

    throw '브랜드 정보를 찾을 수 없습니다.';
  }

  Future<void> _submit() async {
    if (_brandKor == null) {
      _toast('브랜드를 선택해주세요.');
      return;
    }
    if (_mainImages.isEmpty) {
      _toast('이미지를 최소 1장 선택해주세요.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    if (_selectedCats.isEmpty) {
      _toast('카테고리를 최소 1개 선택해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _uploadProgress = 0;
      _uploadPercent = 0;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'unknown';
      final userName = (user?.email ?? '').split('@').first;

      // ✅ 브랜드 확정(brandId/brandEng)
      final resolved = await _resolveBrand(_brandKor!.trim());
      _brandId = resolved.brandId;
      _brandEng = resolved.brandEng;

      final posts = FirebaseFirestore.instance.collection('posts');
      final doc = posts.doc();

      final total = _mainImages.length + _spinPicked.length + _videoFiles.length;
      int done = 0;

      void onOneDone() {
        if (!mounted) return;
        setState(() {
          done++;
          _uploadProgress = total == 0 ? 0 : done / total;
          _uploadPercent = (_uploadProgress * 100).round();
        });
      }

      final mainUrls = List<String?>.filled(_mainImages.length, null);
      final spinUrls = List<String?>.filled(_spinPicked.length, null);
      final videoUrls = List<String?>.filled(_videoFiles.length, null);

      final tasks = <Future>[];

      for (int i = 0; i < _mainImages.length; i++) {
        final idx = i;
        tasks.add(
          UploadService.uploadImage(
            postId: doc.id,
            brandKor: _brandKor!,
            index: idx,
            file: _mainImages[idx],
          ).then((url) {
            mainUrls[idx] = url;
            onOneDone();
          }),
        );
      }
      for (int i = 0; i < _spinPicked.length; i++) {
        final idx = i;
        tasks.add(
          UploadService.uploadSpinImage(
            postId: doc.id,
            brandKor: _brandKor!,
            index: idx,
            file: _spinPicked[idx],
          ).then((url) {
            spinUrls[idx] = url;
            onOneDone();
          }),
        );
      }
      for (int i = 0; i < _videoFiles.length; i++) {
        final idx = i;
        tasks.add(
          UploadService.uploadVideo(
            postId: doc.id,
            brandKor: _brandKor!,
            index: idx,
            file: _videoFiles[idx],
          ).then((url) {
            videoUrls[idx] = url;
            onOneDone();
          }),
        );
      }

      await Future.wait(tasks);

      final finalMain = mainUrls.whereType<String>().toList();
      if (finalMain.isEmpty) throw '업로드 실패';

      final first = finalMain.first;

      // ✅ Cloudinary 유틸(기존 사용 유지)
      final thumbUrl = buildThumbUrl(first);
      final mediumUrl = buildMediumUrl(first);

      // ✅ 안정 필드 확장: mediumImages + updatedAt + brandId + userName
      await doc.set({
        'brand': _brandKor,
        'brandEng': _brandEng ?? '',
        'brandId': _brandId ?? '',

        'categories': _selectedCats.toList(),
        'category': _selectedCats.first,

        'title': _titleC.text.trim(),
        'description': _descC.text.trim(),
        'itemCode': _codeC.text.trim(),

        'imageUrl': first,
        'thumbUrl': thumbUrl,
        'mediumUrl': mediumUrl,

        'images': finalMain,
        'thumbImages': finalMain.map((u) => buildThumbUrl(u)).toList(),
        'mediumImages': finalMain.map((u) => buildMediumUrl(u)).toList(),

        'spinImages': spinUrls.whereType<String>().toList(),
        'videos': videoUrls.whereType<String>().toList(),

        'likes': 0,
        'uid': uid,
        'userName': userName,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),

        // ✅ 상단 노출(기존 가중치 유지)
        'sortKey': DateTime.now().millisecondsSinceEpoch + 1000000000,
      });

      if (mounted) {
        _toast('등록 완료');
        Navigator.pop(context, true);
      }
    } catch (e) {
      _toast('오류: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────── 브랜드 선택 시트 ─────────
  void _showBrandPicker(List<String> brands, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3), // ✅ withOpacity -> withValues
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('브랜드 선택', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: brands.length,
                itemBuilder: (ctx, i) => _ChewyInteraction(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                      child: Text(
                        brands[i].characters.first,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    title: Text(brands[i], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    trailing: _brandKor == brands[i]
                        ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.onSurface)
                        : null,
                    onTap: () {
                      setState(() => _brandKor = brands[i]);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: _ChewyInteraction(
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          '컬렉션 등록',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cs.onSurface),
        ),
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('컬렉션 이미지', cs),
                      const SizedBox(height: 12),

                      _MediaSelectorTile(
                        label: '이미지 추가',
                        count: _mainImages.length,
                        icon: Icons.add_photo_alternate_rounded,
                        onTap: _pickMain,
                      ),
                      if (_mainImages.isNotEmpty) _reorderableThumbGrid(_mainImages),

                      const SizedBox(height: 32),
                      _sectionTitle('기본 정보', cs),
                      const SizedBox(height: 16),

                      // 브랜드 선택 박스(디자인 유지)
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('brands').orderBy('rank').snapshots(),
                        builder: (context, snap) {
                          final brandList = snap.data?.docs
                              .map((d) => (d.data()['nameKor'] ?? '').toString())
                              .where((s) => s.trim().isNotEmpty)
                              .toList() ??
                              [];
                          return _ChewyInteraction(
                            child: InkWell(
                              onTap: () => _showBrandPicker(brandList, isDark),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1A1D22) : const Color(0xFFF6F6F6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.business_center_rounded, size: 20, color: Colors.grey.withValues(alpha: 0.8)),
                                    const SizedBox(width: 14),
                                    Text(
                                      _brandKor ?? '브랜드를 선택하세요',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: _brandKor == null ? Colors.grey : cs.onSurface,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.expand_more_rounded, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      _buildCategoryChips(cs),
                      const SizedBox(height: 24),

                      _modernField(_codeC, '제품 품번', '예: RN-5021', Icons.qr_code_scanner, isDark, required: false),
                      const SizedBox(height: 16),
                      _modernField(_titleC, '제품 이름', '예: 18K 퀼팅 골드 링', Icons.title_rounded, isDark, required: true),
                      const SizedBox(height: 16),
                      _modernField(_descC, '상세 설명', '제품의 특징을 적어주세요', Icons.notes_rounded, isDark, maxLines: 4, required: true),

                      const SizedBox(height: 40),
                      _sectionTitle('고급 미디어 (선택)', cs),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            _MediaSelectorTile(
                              label: '360° 스핀 이미지',
                              count: _spinPicked.length,
                              icon: Icons.threesixty_rounded,
                              onTap: _pickSpin,
                              isSmall: true,
                            ),
                            if (_spinPicked.isNotEmpty) _reorderableThumbGrid(_spinPicked),

                            const SizedBox(height: 12),

                            _MediaSelectorTile(
                              label: '동영상 클립',
                              count: _videoFiles.length,
                              icon: Icons.videocam_rounded,
                              onTap: _pickVideo,
                              isSmall: true,
                            ),
                            if (_videoFiles.isNotEmpty) _reorderableThumbGrid(_videoFiles, isVideo: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: _ChewyButton(
              isUploading: _saving,
              percent: _uploadPercent,
              onTap: _submit,
            ),
          ),

          if (_saving) _buildGlassOverlay(),
        ],
      ),
    );
  }

  // --- UI Helper ---
  Widget _sectionTitle(String title, ColorScheme cs) => Text(
    title,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w900,
      color: cs.onSurface.withValues(alpha: 0.4),
      letterSpacing: 0.5,
    ),
  );

  Widget _buildCategoryChips(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _cats.map((c) {
        final sel = _selectedCats.contains(c.code);
        return _ChewyInteraction(
          child: FilterChip(
            label: Text(c.kor),
            selected: sel,
            onSelected: (on) => setState(() {
              if (on) {
                _selectedCats.add(c.code);
              } else {
                if (_selectedCats.length > 1) _selectedCats.remove(c.code);
              }
            }),
            selectedColor: cs.onSurface,
            checkmarkColor: cs.surface,
            labelStyle: TextStyle(
              color: sel ? cs.surface : cs.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide.none,
            ),
            backgroundColor: cs.onSurface.withValues(alpha: 0.05),
          ),
        );
      }).toList(),
    );
  }

  Widget _modernField(
      TextEditingController c,
      String label,
      String hint,
      IconData icon,
      bool isDark, {
        int maxLines = 1,
        required bool required,
      }) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      decoration: _inputDeco(label, icon, isDark).copyWith(hintText: hint),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '필수 입력 사항입니다' : null
          : null,
    );
  }

  InputDecoration _inputDeco(String label, IconData icon, bool isDark) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13),
    prefixIcon: Icon(icon, size: 20, color: Colors.grey),
    filled: true,
    fillColor: isDark ? const Color(0xFF1A1D22) : const Color(0xFFF6F6F6),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.all(20),
  );

  Widget _buildGlassOverlay() => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    child: Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _uploadProgress,
              color: Colors.white,
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              '$_uploadPercent%',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
            ),
            const Text(
              '클라우드에 안전하게 저장 중입니다',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            )
          ],
        ),
      ),
    ),
  );

  // --- Media picks ---
  Future<void> _pickMain() async {
    final res = await _picker.pickMultiImage(imageQuality: 92);
    if (res.isNotEmpty) setState(() => _mainImages.addAll(res));
  }

  Future<void> _pickSpin() async {
    final res = await _picker.pickMultiImage(imageQuality: 85);
    if (res.isNotEmpty) setState(() => _spinPicked.addAll(res));
  }

  Future<void> _pickVideo() async {
    final res = await _picker.pickVideo(source: ImageSource.gallery);
    if (res != null) setState(() => _videoFiles.add(res));
  }

  // --- Reorder grid ---
  Widget _reorderableThumbGrid(List<XFile> list, {bool isVideo = false}) {
    return Container(
      height: 110,
      margin: const EdgeInsets.only(top: 14),
      child: _ReorderableThumbGrid(
        itemCount: list.length,
        builder: (ctx, i) => _ThumbItem(
          file: list[i],
          isVideo: isVideo,
          onRemove: () => setState(() => list.removeAt(i)),
        ),
        onReorder: (from, to) => setState(() {
          final item = list.removeAt(from);
          list.insert(to, item);
        }),
      ),
    );
  }
}

// --- 공용 커스텀 위젯들 ---

class _ChewyInteraction extends StatefulWidget {
  final Widget child;
  const _ChewyInteraction({required this.child});

  @override
  State<_ChewyInteraction> createState() => _ChewyInteractionState();
}

class _ChewyInteractionState extends State<_ChewyInteraction> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

class _ReorderableThumbGrid extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) builder;
  final void Function(int from, int to) onReorder;
  const _ReorderableThumbGrid({
    required this.itemCount,
    required this.builder,
    required this.onReorder,
  });

  @override
  State<_ReorderableThumbGrid> createState() => _ReorderableThumbGridState();
}

class _ReorderableThumbGridState extends State<_ReorderableThumbGrid> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: widget.itemCount,
      itemBuilder: (ctx, i) => DragTarget<int>(
        onWillAccept: (from) => from != i,
        onAccept: (from) => widget.onReorder(from, i),
        builder: (context, cand, rej) => AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: cand.isNotEmpty ? 1.1 : 1.0,
          child: LongPressDraggable<int>(
            delay: kIsWeb ? Duration.zero : const Duration(milliseconds: 500),
            data: i,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(width: 100, height: 100, child: widget.builder(context, i)),
            ),
            childWhenDragging: Opacity(
              opacity: 0.2,
              child: widget.builder(context, i),
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(width: 90, child: widget.builder(context, i)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaSelectorTile extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final VoidCallback onTap;
  final bool isSmall;
  const _MediaSelectorTile({
    required this.label,
    required this.count,
    required this.icon,
    required this.onTap,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _ChewyInteraction(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.all(isSmall ? 16 : 22),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: cs.onSurface),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: isSmall ? 14 : 16),
              ),
              const Spacer(),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: cs.onSurface, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '$count',
                    style: TextStyle(color: cs.surface, fontWeight: FontWeight.w900, fontSize: 11),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.add_circle_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✅ 웹/모바일 공통: File 대신 XFile.readAsBytes()로 프리뷰
class _ThumbItem extends StatelessWidget {
  final XFile file;
  final bool isVideo;
  final VoidCallback onRemove;
  const _ThumbItem({
    required this.file,
    required this.isVideo,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Container(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06));
                }
                return Image.memory(snap.data!, fit: BoxFit.cover);
              },
            ),
          ),
          if (isVideo) const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 30)),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChewyButton extends StatefulWidget {
  final bool isUploading;
  final int percent;
  final VoidCallback onTap;
  const _ChewyButton({
    required this.isUploading,
    required this.percent,
    required this.onTap,
  });

  @override
  State<_ChewyButton> createState() => _ChewyButtonState();
}

class _ChewyButtonState extends State<_ChewyButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) {
        setState(() => _isDown = false);
        if (!widget.isUploading) widget.onTap();
      },
      onTapCancel: () => setState(() => _isDown = false),
      child: AnimatedScale(
        scale: _isDown ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: cs.onSurface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: cs.onSurface.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Center(
            child: Text(
              widget.isUploading ? '업로드 중 (${widget.percent}%)' : '새 컬렉션 게시하기',
              style: TextStyle(color: cs.surface, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cat {
  final String kor;
  final String code;
  const _Cat(this.kor, this.code);
}

class _BrandResolved {
  final String brandId;
  final String brandEng;
  const _BrandResolved({required this.brandId, required this.brandEng});
}