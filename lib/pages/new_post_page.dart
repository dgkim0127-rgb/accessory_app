// lib/pages/new_post_page.dart  ✅ 최종(중복 카운트 제거 / 권한·브랜드 조회 안정화)
import 'dart:typed_data';
import 'package:accessory_app/widgets/progress_button.dart';
import 'package:pool/pool.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

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
  final _form  = GlobalKey<FormState>();
  final _titleC = TextEditingController();
  final _descC  = TextEditingController();

  String? _brandKor;
  _Cat _selected = _cats.first;

  final _picker = ImagePicker();
  final List<XFile> _picked = [];

  bool _saving = false;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _brandKor = widget.initialBrandKor;
    // 규칙에서 auth.token.role 사용 가능하게 토큰 최신화
    FirebaseAuth.instance.currentUser?.getIdToken(true).catchError((_) {});
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    super.dispose();
  }

  // ───────── utils ─────────
  Future<Uint8List> _compress(XFile x) async {
    final bytes = await x.readAsBytes();
    if (kIsWeb) return bytes;
    try {
      final out = await FlutterImageCompress.compressWithList(
        bytes, minWidth: 1600, minHeight: 1600, quality: 85, format: CompressFormat.jpeg,
      );
      return Uint8List.fromList(out);
    } catch (_) {
      return bytes;
    }
  }

  Future<String> _getUrlWithRetry(Reference ref) async {
    for (int t = 1; t <= 4; t++) {
      try { return await ref.getDownloadURL(); }
      catch (_) { await Future.delayed(Duration(milliseconds: 350 * t)); }
    }
    return await ref.getDownloadURL();
  }

  String _extFromName(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return '';
    return name.substring(i + 1).toLowerCase();
  }

  // ───────── 업로드 ─────────
  Future<List<String>> _uploadImages(String postId, String brandKor) async {
    final storage = FirebaseStorage.instance;
    final pool = Pool(3);
    final total = _picked.length;
    var done = 0;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

    Future<String> _uploadOne(int i) async {
      final x = _picked[i];
      String mime = x.mimeType ?? '';
      String ext  = _extFromName(x.name);

      if (kIsWeb) {
        if (mime.isNotEmpty) {
          final parts = mime.split('/');
          if (parts.length == 2) ext = parts.last.toLowerCase();
        }
        if (ext.isEmpty) ext = 'jpg';
        if (mime.isEmpty) {
          if (ext == 'jpg' || ext == 'jpeg') mime = 'image/jpeg';
          else if (ext == 'png') mime = 'image/png';
          else if (ext == 'heic') mime = 'image/heic';
          else if (ext == 'heif') mime = 'image/heif';
          else if (ext == 'webp') mime = 'image/webp';
          else mime = 'application/octet-stream';
        }
      } else {
        if (ext.isEmpty) ext = 'jpg';
        mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
        ext = 'jpg';
      }

      final fileName = '$i.$ext';
      final ref = storage.ref().child('posts').child(brandKor).child(postId).child(fileName);
      final data = await _compress(x);

      final meta = SettableMetadata(
        contentType: mime,
        cacheControl: 'public, max-age=31536000, immutable',
        customMetadata: {'ownerUid': uid, 'postId': postId},
      );

      final snap = await ref.putData(data, meta);
      final url  = await _getUrlWithRetry(snap.ref);

      done += 1;
      if (mounted) setState(() => _uploadProgress = done / total);
      return url;
    }

    final urls = await Future.wait([
      for (var i = 0; i < _picked.length; i++) pool.withResource(() => _uploadOne(i))
    ]);
    await pool.close();
    return urls;
  }

  Future<void> _submit() async {
    if (_brandKor == null || _brandKor!.trim().isEmpty) {
      _toast('브랜드를 선택해주세요. (카테고리에서 브랜드를 먼저 추가하세요)');
      return;
    }
    if (_picked.isEmpty) {
      _toast('사진을 한 장 이상 선택해주세요.');
      return;
    }
    if (!_form.currentState!.validate()) return;

    setState(() { _saving = true; _uploadProgress = 0; });

    try {
      final user  = FirebaseAuth.instance.currentUser;
      final uid   = user?.uid ?? 'unknown';

      // 1) 브랜드 문서 조회(서버 우선 + 폴백)
      final korLower = _brandKor!.trim().toLowerCase();
      var brandQuery = await FirebaseFirestore.instance
          .collection('brands')
          .where('nameKorLower', isEqualTo: korLower)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (brandQuery.docs.isEmpty) {
        brandQuery = await FirebaseFirestore.instance
            .collection('brands')
            .where('nameKor', isEqualTo: _brandKor)
            .limit(1)
            .get(const GetOptions(source: Source.server));
      }

      if (brandQuery.docs.isEmpty) {
        _toast('선택한 브랜드가 존재하지 않습니다. (카테고리 > 관리에서 먼저 추가해주세요)');
        setState(() => _saving = false);
        return;
      }

      final brandDoc = brandQuery.docs.first;
      final brandId  = brandDoc.id;
      final brandEng = (brandDoc.data()['nameEng'] ?? '').toString();

      // 2) 이미지 업로드
      final posts = FirebaseFirestore.instance.collection('posts');
      final doc   = posts.doc();
      final images = await _uploadImages(doc.id, _brandKor!);

      // 3) 게시글 저장
      final now = FieldValue.serverTimestamp();
      await doc.set({
        'brandId'    : brandId,
        'brand'      : _brandKor,
        'brandEng'   : brandEng,
        'category'   : _selected.code,
        'title'      : _titleC.text.trim(),
        'description': _descC.text.trim(),
        'imageUrl'   : images.first,
        'images'     : images,
        'likes'      : 0,
        'createdAt'  : now,
        'updatedAt'  : now,
        'uid'        : uid,
        'userName'   : (user?.email ?? 'user'),
      });

      // ❌ 여기서 brands.postsCount 증가시키지 않음
      //  → 증가/감소는 Cloud Functions 트리거(onCreate/onDelete)가 단독으로 담당

      if (!mounted) return;
      _toast('업로드 완료');
      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      final code = e.code;
      if (code == 'permission-denied') {
        _toast('권한 부족: 관리자만 게시물을 등록할 수 있어요. (role: admin/super 필요)');
      } else {
        _toast('업로드 실패: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('새 게시물'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ProgressTextAction(
              label: '게시',
              progress: _saving ? _uploadProgress : null,
              onPressed: _saving ? null : _submit,
            ),
          ),
        ],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 브랜드 드롭다운
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('brands')
                      .orderBy('rank')
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('브랜드', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          InputDecorator(
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            child: Text('불러오기 오류: ${snap.error}',
                                style: const TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      );
                    }

                    final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final items = docs.map((d) {
                      final m = d.data();
                      final kor = (m['nameKor'] ?? '').toString().trim();
                      final rank = (m['rank'] is int) ? m['rank'] as int : 1000000000;
                      return MapEntry(rank, kor);
                    }).toList()
                      ..sort((a, b) => a.key != b.key ? a.key.compareTo(b.key) : a.value.compareTo(b.value));

                    final brandList = items.map((e) => e.value).where((e) => e.isNotEmpty).toList();

                    String? value = _brandKor;
                    if (value != null && !brandList.contains(value)) value = null;
                    if (value == null && brandList.isNotEmpty) {
                      value = brandList.first;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _brandKor = value);
                      });
                    }

                    if (brandList.isEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('브랜드', style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(height: 8),
                          InputDecorator(
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            child: Text('등록된 브랜드가 없습니다. (카테고리 > 관리에서 브랜드를 추가하세요)',
                                style: TextStyle(color: Colors.black54)),
                          ),
                        ],
                      );
                    }

                    return DropdownButtonFormField<String>(
                      value: value,
                      decoration: const InputDecoration(labelText: '브랜드', border: OutlineInputBorder()),
                      items: brandList.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                      onChanged: (v) => setState(() => _brandKor = v),
                    );
                  },
                ),
                const SizedBox(height: 12),

                const Text('카테고리', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _cats.map((c) {
                    final sel = c == _selected;
                    return ChoiceChip(
                      label: Text(c.kor),
                      selected: sel,
                      labelStyle: TextStyle(
                        color: sel ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      selectedColor: Colors.black,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Color(0xffe6e6e6)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onSelected: (_) => setState(() => _selected = c),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _titleC,
                  decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '제목을 입력하세요' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descC,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '설명', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _openPickerSheet,
                      style: ElevatedButton.styleFrom(
                        elevation: 0, backgroundColor: Colors.white, foregroundColor: Colors.black,
                        side: const BorderSide(color: Color(0xffe6e6e6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [ Icon(Icons.photo_library_outlined, size: 18), SizedBox(width: 6), Text('사진 선택') ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_picked.isNotEmpty)
                      const Text('선택됨', style: TextStyle(color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 12),

                if (_picked.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _picked.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
                    ),
                    itemBuilder: (_, i) {
                      final x = _picked[i];
                      Widget preview;
                      if (kIsWeb) {
                        preview = Image.network(
                          x.path, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40)),
                        );
                      } else {
                        preview = FutureBuilder<Uint8List>(
                          future: x.readAsBytes(),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                            }
                            return Image.memory(snap.data!, fit: BoxFit.cover);
                          },
                        );
                      }

                      return Stack(
                        children: [
                          Positioned.fill(child: preview),
                          Positioned(
                            right: 2, top: 2,
                            child: InkWell(
                              onTap: () => setState(() => _picked.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                color: Colors.black.withOpacity(0.5),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                if (_saving) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _uploadProgress == 0 ? null : _uploadProgress, minHeight: 4,
                  ),
                ],

                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────── 파일 선택 시트 ─────────
  Future<void> _openPickerSheet() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetTile(
                icon: Icons.photo_library_outlined,
                text: kIsWeb ? '파일에서 선택(여러 장)' : '갤러리에서 선택(여러 장)',
                onTap: () async {
                  Navigator.pop(context);
                  if (kIsWeb) { await _pickFromWebFiles(); } else { await _pickFromGallery(); }
                },
              ),
              const Divider(height: 1),
              _sheetTile(
                icon: Icons.photo_camera_outlined,
                text: '카메라로 촬영',
                onTap: () async {
                  Navigator.pop(context);
                  await _pickFromCamera();
                },
              ),
              const SizedBox(height: 8),
              _sheetTile(
                icon: Icons.dashboard_customize_outlined,
                text: '선택함 미리보기/정리',
                enabled: _picked.isNotEmpty,
                onTap: () { Navigator.pop(context); _openSelectionSheet(); },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  // 웹(모바일 브라우저 포함) 파일 선택
  Future<void> _pickFromWebFiles() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['jpg','jpeg','png','heic','heif','webp'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final add = <XFile>[];
      for (final f in res.files) {
        if (f.bytes == null) continue;
        final mime = _guessMime(f.name);
        add.add(XFile.fromData(f.bytes!, name: f.name, mimeType: mime, length: f.size));
      }
      setState(() => _picked.addAll(add));
      _openSelectionSheet();
    } catch (e) {
      _toast('파일 선택 실패: $e');
    }
  }

  String _guessMime(String name) {
    final ext = _extFromName(name);
    switch (ext) {
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png':  return 'image/png';
      case 'heic': return 'image/heic';
      case 'heif': return 'image/heif';
      case 'webp': return 'image/webp';
      default:     return 'application/octet-stream';
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 92);
      if (files.isEmpty) return;
      setState(() => _picked.addAll(files));
      _openSelectionSheet();
    } catch (e) {
      _toast('갤러리에서 불러오기 실패: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
      if (x == null) return;
      setState(() => _picked.add(x));
      _openSelectionSheet();
    } catch (e) {
      _toast('카메라 촬영 실패: $e');
    }
  }

  Future<void> _openSelectionSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false, initialChildSize: 0.75, minChildSize: 0.5, maxChildSize: 0.95,
          builder: (_, controller) {
            return Column(
              children: [
                _sheetHeader(title: '선택한 사진 (${_picked.length})'),
                const Divider(height: 1),
                Expanded(
                  child: GridView.builder(
                    controller: controller,
                    padding: const EdgeInsets.all(12),
                    itemCount: _picked.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
                    ),
                    itemBuilder: (_, i) {
                      final x = _picked[i];
                      Widget preview;
                      if (kIsWeb) {
                        preview = Image.network(
                          x.path, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40)),
                        );
                      } else {
                        preview = FutureBuilder<Uint8List>(
                          future: x.readAsBytes(),
                          builder: (_, snap) {
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                            }
                            return Image.memory(snap.data!, fit: BoxFit.cover);
                          },
                        );
                      }

                      return Stack(
                        children: [
                          Positioned.fill(child: preview),
                          Positioned(
                            right: 2, top: 2,
                            child: InkWell(
                              onTap: () => setState(() => _picked.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                color: Colors.black.withOpacity(0.55),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 2, bottom: 2,
                            child: _moveBtn(icon: Icons.chevron_left, onTap: () => _moveIndex(i, i - 1)),
                          ),
                          Positioned(
                            right: 2, bottom: 2,
                            child: _moveBtn(icon: Icons.chevron_right, onTap: () => _moveIndex(i, i + 1)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: kIsWeb ? _pickFromWebFiles : _pickFromGallery,
                          style: _btnOutline(),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
                            children: [ Icon(Icons.add_photo_alternate_outlined), SizedBox(width: 6), Text('사진 더 선택') ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: _btnFill(),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
                            children: [ Icon(Icons.check_circle_outline), SizedBox(width: 6), Text('완료') ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _moveBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }

  void _moveIndex(int from, int to) {
    if (to < 0 || to >= _picked.length) return;
    setState(() {
      final item = _picked.removeAt(from);
      _picked.insert(to, item);
    });
  }

  // ───────── 시트 공통 위젯 ─────────
  Widget _sheetTile({required IconData icon, required String text, required VoidCallback onTap, bool enabled = true}) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: Colors.black87),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: enabled ? onTap : null,
      dense: true, visualDensity: VisualDensity.compact,
    );
  }

  Widget _sheetHeader({required String title}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      alignment: Alignment.centerLeft,
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    );
  }

  ButtonStyle _btnOutline() => OutlinedButton.styleFrom(
    foregroundColor: Colors.black,
    side: const BorderSide(color: Color(0xffe6e6e6)),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
  );

  ButtonStyle _btnFill() => ElevatedButton.styleFrom(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    elevation: 0,
  );
}

class _Cat {
  final String kor;
  final String code;
  const _Cat(this.kor, this.code);
}
