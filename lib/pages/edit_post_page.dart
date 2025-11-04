// lib/pages/edit_post_page.dart  ✅ 최종(브랜드 조회 정리 / value 초기화 안전)
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class EditPostPage extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> initialData;
  const EditPostPage({super.key, required this.postId, required this.initialData});

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  // 브랜드/카테고리
  List<Map<String, String>> _brands = [];
  String? _brandKor;     // posts.brand
  String? _brandEng;     // posts.brandEng
  String? _brandLogoUrl; // posts.brandLogoUrl
  String _category = 'necklace';

  static const _cats = <Map<String, String>>[
    {'code': 'necklace', 'label': '목걸이'},
    {'code': 'ring', 'label': '반지'},
    {'code': 'earring', 'label': '귀걸이'},
    {'code': 'bracelet', 'label': '팔찌'},
    {'code': 'acc', 'label': '기타'},
  ];

  // 이미지
  final List<String> _existing = []; // 기존 url
  final List<XFile> _picked = [];    // 새로 추가된 로컬 이미지
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(
      text: (widget.initialData['title'] ?? '').toString(),
    );
    _descCtrl  = TextEditingController(
      text: (widget.initialData['description'] ?? '').toString(),
    );
    _category  = (widget.initialData['category'] ?? 'necklace').toString();

    // 브랜드 초기값 (비어있으면 null 유지)
    final rawKor = (widget.initialData['brand'] ?? '').toString();
    _brandKor     = rawKor.isEmpty ? null : rawKor;
    _brandEng     = (widget.initialData['brandEng'] ?? '').toString();
    _brandLogoUrl = (widget.initialData['brandLogoUrl'] ??
        widget.initialData['logoUrl'] ?? '').toString();

    // 이미지 초기값
    final imgs = widget.initialData['images'];
    if (imgs is List && imgs.isNotEmpty) {
      _existing.addAll(
        imgs.map((e) => (e ?? '').toString()).where((s) => s.isNotEmpty),
      );
    } else {
      final one = (widget.initialData['imageUrl'] ?? '').toString();
      if (one.isNotEmpty) _existing.add(one);
    }

    // 권한 토큰 최신화(규칙에서 role 클레임 활용시)
    FirebaseAuth.instance.currentUser?.getIdToken(true).catchError((_) {});
    _loadBrands();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // Firestore brands → 동적 브랜드 목록
  Future<void> _loadBrands() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('brands')
          .orderBy('rank')
          .get(const GetOptions(source: Source.server));

      _brands = snap.docs.map((d) {
        final m = d.data();
        return {
          'kor': (m['nameKor'] ?? m['kor'] ?? m['name'] ?? '').toString().trim(),
          'eng': (m['nameEng'] ?? m['eng'] ?? '').toString().trim(),
          'logoUrl': (m['logoUrl'] ?? '').toString().trim(),
        };
      }).where((b) => (b['kor'] ?? '').trim().isNotEmpty).toList();
    } catch (_) {
      _brands = [];
    }

    // 첫 항목 보정(초기 brand가 비어있을 때만)
    if ((_brandKor ?? '').isEmpty && _brands.isNotEmpty) {
      _brandKor     = _brands.first['kor'];
      _brandEng     = _brands.first['eng'] ?? '';
      _brandLogoUrl = _brands.first['logoUrl'] ?? '';
    }

    if (mounted) setState(() {});
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 92);
    if (files.isNotEmpty) {
      setState(() => _picked.addAll(files));
    }
  }

  void _removeExistingAt(int i) => setState(() => _existing.removeAt(i));
  void _removePickedAt(int i)   => setState(() => _picked.removeAt(i));

  Future<String> _uploadOne(XFile xf, String uid) async {
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final ref = FirebaseStorage.instance.ref('posts/$uid/${ts}_${xf.name}');
    final task = kIsWeb ? ref.putData(await xf.readAsBytes())
        : ref.putFile(File(xf.path));
    final snap = await task.whenComplete(() {});
    return snap.ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    try {
      // 새 이미지 업로드
      final newUrls = <String>[];
      for (final xf in _picked) {
        final url = await _uploadOne(xf, user.uid);
        newUrls.add(url);
      }

      final all = <String>[..._existing, ...newUrls];
      if (all.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지를 최소 1장 선택해주세요.')),
        );
        setState(() => _saving = false);
        return;
      }

      final updates = <String, dynamic>{
        'title'       : _titleCtrl.text.trim(),
        'description' : _descCtrl.text.trim(),
        'category'    : _category,
        'brand'       : _brandKor ?? '',
        'brandEng'    : _brandEng ?? '',
        'brandLogoUrl': _brandLogoUrl ?? '',
        'images'      : all,
        'imageUrl'    : all.first,
        'updatedAt'   : FieldValue.serverTimestamp(),
      };

      // ⚠️ brandId는 변경하지 않음(카운트는 onCreate/onDelete에서만 관리)
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update(updates);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수정 완료')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catItems = _cats
        .map((c) => DropdownMenuItem<String>(
      value: c['code'],
      child: Text(c['label']!),
    ))
        .toList();

    final brandItems = _brands
        .map((b) => DropdownMenuItem<String>(
      value: b['kor'],
      child: Row(
        children: [
          if ((b['logoUrl'] ?? '').isNotEmpty)
            CircleAvatar(
              radius: 10,
              backgroundImage: NetworkImage(b['logoUrl']!),
            ),
          if ((b['logoUrl'] ?? '').isNotEmpty) const SizedBox(width: 6),
          Text(b['kor']!),
        ],
      ),
    ))
        .toList();

    // Dropdown 초기 value 안전 처리
    String? brandValue = _brandKor;
    if (brandValue != null && _brands.isNotEmpty && !_brands.any((b) => b['kor'] == brandValue)) {
      brandValue = null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('게시물 수정'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('저장'),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: IgnorePointer(
        ignoring: _saving,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 이미지 미리보기
            SizedBox(
              height: 280,
              child: PageView(
                children: [
                  for (int i = 0; i < _existing.length; i++)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          _existing[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton(
                            onPressed: () => _removeExistingAt(i),
                            icon: const Icon(Icons.close, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  for (int i = 0; i < _picked.length; i++)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        kIsWeb
                            ? Image.network(_picked[i].path, fit: BoxFit.cover)
                            : Image.file(File(_picked[i].path), fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton(
                            onPressed: () => _removePickedAt(i),
                            icon: const Icon(Icons.close, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  InkWell(
                    onTap: _pickImages,
                    child: Container(
                      color: const Color(0xFFF4F4F4),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_a_photo_outlined, size: 40),
                            SizedBox(height: 8),
                            Text('이미지 추가'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '제목을 입력하세요' : null,
                    decoration: const InputDecoration(labelText: '제목'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '설명'),
                  ),
                  const SizedBox(height: 12),

                  // 브랜드 선택 (Firestore 기반, 동적)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    items: brandItems,
                    value: brandValue, // 안전한 value 사용
                    decoration: const InputDecoration(labelText: '브랜드'),
                    onChanged: (val) {
                      if (val == null) return;
                      final b = _brands.firstWhere((e) => e['kor'] == val);
                      setState(() {
                        _brandKor = b['kor'];
                        _brandEng = b['eng'] ?? '';
                        _brandLogoUrl = b['logoUrl'] ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // 카테고리 선택
                  DropdownButtonFormField<String>(
                    items: catItems,
                    value: _category,
                    decoration: const InputDecoration(labelText: '카테고리'),
                    onChanged: (v) => setState(() => _category = v ?? 'necklace'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('수정 완료'),
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }
}
