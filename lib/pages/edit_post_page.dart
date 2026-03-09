// lib/pages/edit_post_page.dart ✅ 최종
// - 브랜드 시트 검색창 추가
// - dart:io 제거(웹 빌드 OK) → XFile.readAsBytes()로 프리뷰
// - withOpacity -> withValues(alpha: )
// - 저장: sortKey 최상단 + updatedAt + 서버 강제 get + (기존URL을 XFile로 변환 업로드 제거)
// - 수정 페이지 미리보기/썸네일: 원본 비율 유지(BoxFit.contain) + 세로 높이 280 유지

import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:accessory_app/services/upload_service.dart';
import 'package:accessory_app/utils/cloudinary_image_utils.dart';

class EditPostPage extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> initialData;
  const EditPostPage({
    super.key,
    required this.postId,
    required this.initialData,
  });

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _ImageItem {
  final String? url; // 기존 이미지 URL
  final XFile? file; // 새로 선택한 이미지
  const _ImageItem.url(this.url) : file = null;
  const _ImageItem.file(this.file) : url = null;

  bool get isExisting => url != null;
  bool get isPicked => file != null;
}

class _EditPostPageState extends State<EditPostPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _codeCtrl;

  // 브랜드 목록(kor/eng/logoUrl)
  List<Map<String, String>> _brands = [];
  String? _brandKor;
  String? _brandEng;
  String? _brandLogoUrl;

  // ✅ 카테고리(복수 선택 + 최소 1개)
  static const _cats = <Map<String, String>>[
    {'code': 'necklace', 'label': '목걸이'},
    {'code': 'ring', 'label': '반지'},
    {'code': 'earring', 'label': '귀걸이'},
    {'code': 'bracelet', 'label': '팔찌'},
    {'code': 'acc', 'label': '기타'},
  ];
  final Set<String> _categories = {'necklace'};

  // ✅ 이미지: 기존 URL + 새 선택(XFile)을 하나의 리스트로 관리(순서 유지)
  final List<_ImageItem> _images = [];

  // 360 / 동영상
  final List<String> _spinExisting = [];
  final List<XFile> _spinPicked = [];
  final List<String> _videoExisting = [];
  final List<XFile> _videoPicked = [];

  // 진행 상태
  bool _saving = false;
  double _uploadProgress = 0;
  int _uploadPercent = 0;

  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  int? _draggingPhotoIndex;

  final ImagePicker _picker = ImagePicker();

  int get _totalMediaCount => _images.length;

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(
      text: (widget.initialData['title'] ?? '').toString(),
    );
    _descCtrl = TextEditingController(
      text: (widget.initialData['description'] ?? '').toString(),
    );
    _codeCtrl = TextEditingController(
      text: (widget.initialData['itemCode'] ?? '').toString(),
    );

    // 브랜드 초기값
    final rawKor = (widget.initialData['brand'] ?? '').toString();
    _brandKor = rawKor.isEmpty ? null : rawKor;
    _brandEng = (widget.initialData['brandEng'] ?? '').toString();
    _brandLogoUrl =
        (widget.initialData['brandLogoUrl'] ?? widget.initialData['logoUrl'] ?? '')
            .toString();

    // 카테고리 초기값
    final cats = widget.initialData['categories'];
    if (cats is List) {
      final list =
      cats.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      if (list.isNotEmpty) {
        _categories
          ..clear()
          ..addAll(list);
      }
    } else {
      final one = (widget.initialData['category'] ?? 'necklace').toString();
      if (one.isNotEmpty) {
        _categories
          ..clear()
          ..add(one);
      }
    }
    if (_categories.isEmpty) _categories.add('necklace');

    // 이미지 초기값
    final imgs = widget.initialData['images'];
    if (imgs is List && imgs.isNotEmpty) {
      for (final e in imgs) {
        final u = (e ?? '').toString();
        if (u.isNotEmpty) _images.add(_ImageItem.url(u));
      }
    } else {
      final one = (widget.initialData['imageUrl'] ?? '').toString();
      if (one.isNotEmpty) _images.add(_ImageItem.url(one));
    }

    // 360 초기값
    final spins = widget.initialData['spinImages'];
    if (spins is List && spins.isNotEmpty) {
      _spinExisting.addAll(
        spins.map((e) => (e ?? '').toString()).where((s) => s.isNotEmpty),
      );
    }

    // 동영상 초기값
    final vids = widget.initialData['videos'];
    if (vids is List && vids.isNotEmpty) {
      _videoExisting.addAll(
        vids.map((e) => (e ?? '').toString()).where((s) => s.isNotEmpty),
      );
    }

    FirebaseAuth.instance.currentUser?.getIdToken(true).catchError((_) {});
    _loadBrands();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _codeCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // 브랜드 불러오기
  Future<void> _loadBrands() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('brands')
          .orderBy('rank')
          .get(const GetOptions(source: Source.server));

      _brands = snap.docs
          .map((d) {
        final m = d.data();
        return {
          'kor':
          (m['nameKor'] ?? m['kor'] ?? m['name'] ?? '').toString().trim(),
          'eng': (m['nameEng'] ?? m['eng'] ?? '').toString().trim(),
          'logoUrl': (m['logoUrl'] ?? m['profileUrl'] ?? m['imageUrl'] ?? '')
              .toString()
              .trim(),
        };
      })
          .where((b) => (b['kor'] ?? '').trim().isNotEmpty)
          .toList();
    } catch (_) {
      _brands = [];
    }

    if ((_brandKor ?? '').isEmpty && _brands.isNotEmpty) {
      _brandKor = _brands.first['kor'];
      _brandEng = _brands.first['eng'] ?? '';
      _brandLogoUrl = _brands.first['logoUrl'] ?? '';
    }

    if (mounted) setState(() {});
  }

  // ───────── 유틸 ─────────

  void _setUploadProgress(double fraction) {
    fraction = fraction.clamp(0, 1);
    setState(() {
      _uploadProgress = fraction;
      _uploadPercent = (fraction * 100).round();
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ───────── 브랜드 선택(검색 포함) ─────────
  void _showBrandPicker(bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _BrandPickerSheet(
        isDark: isDark,
        brands: _brands,
        selectedKor: _brandKor,
        onPick: (kor, eng, logo) {
          setState(() {
            _brandKor = kor;
            _brandEng = eng;
            _brandLogoUrl = logo;
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ───────── 미디어 선택 ─────────

  Future<void> _pickImages() async {
    try {
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;

        final add = <_ImageItem>[];
        for (final f in res.files) {
          if (f.bytes == null) continue;
          add.add(
            _ImageItem.file(
              XFile.fromData(f.bytes!, name: f.name, length: f.size),
            ),
          );
        }
        setState(() => _images.addAll(add));
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 92);
        if (files.isEmpty) return;
        setState(() => _images.addAll(files.map((x) => _ImageItem.file(x))));
      }
    } catch (e) {
      _showSnack('사진 선택 실패: $e');
    }
  }

  Future<void> _pickSpinImages() async {
    try {
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;

        final add = <XFile>[];
        for (final f in res.files) {
          if (f.bytes == null) continue;
          add.add(XFile.fromData(f.bytes!, name: f.name, length: f.size));
        }
        setState(() => _spinPicked.addAll(add));
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 92);
        if (files.isEmpty) return;
        setState(() => _spinPicked.addAll(files));
      }
    } catch (e) {
      _showSnack('360° 이미지 선택 실패: $e');
    }
  }

  Future<void> _pickVideos() async {
    try {
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['mp4', 'mov', 'webm'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;

        final add = <XFile>[];
        for (final f in res.files) {
          if (f.bytes == null) continue;
          add.add(XFile.fromData(f.bytes!, name: f.name, length: f.size));
        }
        setState(() => _videoPicked.addAll(add));
      } else {
        final picked = await _picker.pickVideo(source: ImageSource.gallery);
        if (picked != null) setState(() => _videoPicked.add(picked));
      }
    } catch (e) {
      _showSnack('동영상 선택 실패: $e');
    }
  }

  // ───────── 제거/재정렬 ─────────

  void _removeImageAt(int i) {
    setState(() {
      _images.removeAt(i);
      if (_currentPage >= _totalMediaCount) {
        _currentPage = _totalMediaCount == 0 ? 0 : _totalMediaCount - 1;
      }
    });
  }

  void _reorderPhoto(int from, int to) {
    setState(() {
      if (from == to) return;
      if (to > from) to -= 1;
      final item = _images.removeAt(from);
      _images.insert(to, item);
    });
  }

  void _removeSpinExistingAt(int i) => setState(() => _spinExisting.removeAt(i));
  void _removeSpinPickedAt(int i) => setState(() => _spinPicked.removeAt(i));
  void _removeVideoExistingAt(int i) => setState(() => _videoExisting.removeAt(i));
  void _removeVideoPickedAt(int i) => setState(() => _videoPicked.removeAt(i));

  // ───────── 저장(안정성 최우선) ─────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if ((_brandKor ?? '').trim().isEmpty) {
      _showSnack('브랜드를 선택해주세요.');
      return;
    }
    if (_categories.isEmpty) {
      _showSnack('카테고리를 최소 1개 선택해주세요.');
      return;
    }
    if (_images.isEmpty) {
      _showSnack('사진을 최소 1개 선택해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _uploadProgress = 0;
      _uploadPercent = 0;
    });

    String? firstUploadError;

    try {
      final brandKor = _brandKor!.trim();
      final docRef =
      FirebaseFirestore.instance.collection('posts').doc(widget.postId);

      // 업로드 대상: 이미지 중 file 있는 것만
      final pickedList = <XFile>[];
      for (final it in _images) {
        if (it.file != null) pickedList.add(it.file!);
      }

      final totalNewFiles =
          pickedList.length + _spinPicked.length + _videoPicked.length;
      int done = 0;

      void bumpProgress() {
        if (totalNewFiles <= 0) return;
        done++;
        _setUploadProgress(done / totalNewFiles);
      }

      // 업로드 결과(순서 유지용)
      final uploadedImageUrls = <String>[];
      final uploadedThumbs = <String>[];
      final uploadedMediums = <String>[];

      // ✅ 새 이미지 업로드
      for (int i = 0; i < pickedList.length; i++) {
        try {
          final xf = pickedList[i];
          final url = await UploadService.uploadImage(
            postId: widget.postId,
            brandKor: brandKor,
            index: i,
            file: xf,
          );
          uploadedImageUrls.add(url);
          uploadedThumbs.add(buildThumbUrl(url));
          uploadedMediums.add(buildMediumUrl(url));
        } catch (e) {
          firstUploadError ??= '이미지 업로드 실패: $e';
        } finally {
          bumpProgress();
        }
      }

      // ✅ 360 업로드
      final newSpinUrls = <String>[];
      for (int i = 0; i < _spinPicked.length; i++) {
        try {
          final xf = _spinPicked[i];
          final url = await UploadService.uploadSpinImage(
            postId: widget.postId,
            brandKor: brandKor,
            index: i + _spinExisting.length,
            file: xf,
          );
          newSpinUrls.add(url);
        } catch (e) {
          firstUploadError ??= '360° 업로드 실패: $e';
        } finally {
          bumpProgress();
        }
      }

      // ✅ 동영상 업로드
      final newVideoUrls = <String>[];
      for (int i = 0; i < _videoPicked.length; i++) {
        try {
          final xf = _videoPicked[i];
          final url = await UploadService.uploadVideo(
            postId: widget.postId,
            brandKor: brandKor,
            index: i + _videoExisting.length,
            file: xf,
          );
          newVideoUrls.add(url);
        } catch (e) {
          firstUploadError ??= '동영상 업로드 실패: $e';
        } finally {
          bumpProgress();
        }
      }

      // ✅ 최종 이미지 리스트: _images 순서대로 (기존 url / 업로드 url)
      int uploadCursor = 0;
      final allImages = <String>[];
      final allThumbImages = <String>[];
      final allMediumImages = <String>[];

      for (final it in _images) {
        if (it.isExisting) {
          final u = it.url!;
          allImages.add(u);
          allThumbImages.add(buildThumbUrl(u));
          allMediumImages.add(buildMediumUrl(u));
        } else if (it.isPicked) {
          if (uploadCursor < uploadedImageUrls.length) {
            final u = uploadedImageUrls[uploadCursor];
            allImages.add(u);
            allThumbImages.add(uploadedThumbs[uploadCursor]);
            allMediumImages.add(uploadedMediums[uploadCursor]);
          }
          uploadCursor++;
        }
      }

      if (allImages.isEmpty) {
        _showSnack(firstUploadError ?? '이미지 업로드에 실패했습니다. 다시 시도해주세요.');
        return;
      }

      final allSpins = <String>[..._spinExisting, ...newSpinUrls];
      final allVideos = <String>[..._videoExisting, ...newVideoUrls];

      final primaryImageUrl = allImages.first;
      final primaryThumbUrl = allThumbImages.first;
      final primaryMediumUrl = allMediumImages.first;

      final categoriesList = _categories.toList();

      await docRef.update({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'brand': brandKor,
        'brandEng': _brandEng ?? '',
        'brandLogoUrl': _brandLogoUrl ?? '',
        'itemCode': _codeCtrl.text.trim(),
        'categories': categoriesList,
        'category': categoriesList.first,
        'images': allImages,
        'thumbImages': allThumbImages,
        'mediumImages': allMediumImages,
        'imageUrl': primaryImageUrl,
        'thumbUrl': primaryThumbUrl,
        'mediumUrl': primaryMediumUrl,
        'spinImages': allSpins,
        'videos': allVideos,
        'updatedAt': FieldValue.serverTimestamp(),
        // ✅ 수정하면 최상단
        'sortKey': DateTime.now().millisecondsSinceEpoch + 1000000000,
      });

      // ✅ 캐시 체감 제거
      await docRef.get(const GetOptions(source: Source.server));

      if (!mounted) return;
      if (firstUploadError != null) {
        _showSnack('수정 완료(일부 업로드 실패): $firstUploadError');
      } else {
        _showSnack('수정 완료');
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('수정 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────── 미리보기(웹/모바일 공통) ─────────

  Widget _previewImageBox(Widget image) {
    return Container(
      color: const Color(0xFFF4F4F4),
      alignment: Alignment.center,
      child: image,
    );
  }

  Widget _buildMediaPage(int index) {
    final it = _images[index];

    if (it.isExisting) {
      final url = it.url!;
      return Stack(
        fit: StackFit.expand,
        children: [
          _previewImageBox(
            Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: IconButton(
              onPressed: () => _removeImageAt(index),
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),
        ],
      );
    }

    final x = it.file!;
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Uint8List>(
          future: x.readAsBytes(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Container(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.06),
              );
            }
            return _previewImageBox(
              Image.memory(
                snap.data!,
                fit: BoxFit.contain,
              ),
            );
          },
        ),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton(
            onPressed: () => _removeImageAt(index),
            icon: const Icon(Icons.close, color: Colors.white),
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewArea() {
    final hasMedia = _totalMediaCount > 0;

    return SizedBox(
      height: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            if (hasMedia)
              PageView.builder(
                controller: _pageCtrl,
                itemCount: _totalMediaCount,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) => _buildMediaPage(index),
              )
            else
              InkWell(
                onTap: _pickImages,
                child: Container(
                  color: const Color(0xFFF4F4F4),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 40),
                        SizedBox(height: 8),
                        Text('사진을 추가해주세요'),
                      ],
                    ),
                  ),
                ),
              ),
            if (hasMedia)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_currentPage + 1} / $_totalMediaCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoReorderRow() {
    if (_images.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '사진 순서 편집',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 6),
        const Text(
          '사진을 길게 눌러 순서를 바꿀 수 있어요.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            itemCount: _images.length,
            onReorderStart: (i) => setState(() => _draggingPhotoIndex = i),
            onReorderEnd: (_) => setState(() => _draggingPhotoIndex = null),
            onReorder: _reorderPhoto,
            itemBuilder: (context, index) {
              final it = _images[index];
              final key = ValueKey(
                it.isExisting ? 'url_${it.url}' : 'file_${it.file!.name}_$index',
              );

              final isDragging = _draggingPhotoIndex == index;
              final dimOthers =
                  _draggingPhotoIndex != null && _draggingPhotoIndex != index;

              return ReorderableDelayedDragStartListener(
                key: key,
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      AnimatedScale(
                        scale: isDragging ? 1.06 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: isDragging
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              color: const Color(0xFFF4F4F4),
                              alignment: Alignment.center,
                              child: it.isExisting
                                  ? Image.network(
                                it.url!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image_outlined),
                              )
                                  : FutureBuilder<Uint8List>(
                                future: it.file!.readAsBytes(),
                                builder: (context, snap) {
                                  if (!snap.hasData) {
                                    return Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                    );
                                  }
                                  return Image.memory(
                                    snap.data!,
                                    fit: BoxFit.contain,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (dimOthers)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () => _removeImageAt(index),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // 드롭다운용 브랜드 목록
    final brandItems = _brands
        .map(
          (b) => DropdownMenuItem<String>(
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
      ),
    )
        .toList();

    String? brandValue = _brandKor;
    if (brandValue != null &&
        _brands.isNotEmpty &&
        !_brands.any((b) => b['kor'] == brandValue)) {
      brandValue = null;
    }

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
          '컬렉션 수정',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            color: cs.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _saving,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 130),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('컬렉션 이미지 (순서 변경 가능)', cs),
                        const SizedBox(height: 12),
                        _buildPreviewArea(),
                        const SizedBox(height: 12),
                        _buildPhotoReorderRow(),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickImages,
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: Color(0xffe6e6e6)),
                              ),
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                              label: const Text('사진 추가'),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '총 $_totalMediaCount개',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        _sectionTitle('기본 정보', cs),
                        const SizedBox(height: 16),

                        // ✅ 브랜드: 디자인 유지(바텀시트 + 검색)
                        _ChewyInteraction(
                          child: InkWell(
                            onTap: () => _showBrandPicker(isDark),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1A1D22)
                                    : const Color(0xFFF6F6F6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.business_center_rounded,
                                    size: 20,
                                    color:
                                    Colors.grey.withValues(alpha: 0.8),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    _brandKor ?? '브랜드를 선택하세요',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _brandKor == null
                                          ? Colors.grey
                                          : cs.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Icon(
                                    Icons.expand_more_rounded,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 카테고리 복수
                        const Text(
                          '카테고리 (복수 선택 가능)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _cats.map((c) {
                            final code = c['code']!;
                            final label = c['label']!;
                            final selected = _categories.contains(code);

                            return FilterChip(
                              label: Text(label),
                              selected: selected,
                              selectedColor: cs.onSurface,
                              checkmarkColor: cs.surface,
                              labelStyle: TextStyle(
                                color: selected
                                    ? cs.surface
                                    : cs.onSurface.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                              ),
                              side: BorderSide(
                                color: cs.onSurface.withValues(alpha: 0.08),
                              ),
                              onSelected: (on) {
                                setState(() {
                                  if (on) {
                                    _categories.add(code);
                                  } else {
                                    if (_categories.length <= 1) return;
                                    _categories.remove(code);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 18),

                        _modernField(
                          _codeCtrl,
                          '품번',
                          '예: AB-1234',
                          Icons.qr_code_scanner,
                          isDark,
                          required: true,
                        ),
                        const SizedBox(height: 16),
                        _modernField(
                          _titleCtrl,
                          '제목',
                          '제목을 입력하세요',
                          Icons.title_rounded,
                          isDark,
                          required: true,
                        ),
                        const SizedBox(height: 16),
                        _modernField(
                          _descCtrl,
                          '상세',
                          '상세 설명을 입력하세요',
                          Icons.notes_rounded,
                          isDark,
                          maxLines: 4,
                          required: false,
                        ),

                        const SizedBox(height: 36),
                        _sectionTitle('고급 미디어 (360도 / 영상)', cs),
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
                                label: '360° 이미지 추가',
                                count: _spinExisting.length + _spinPicked.length,
                                icon: Icons.threesixty_rounded,
                                onTap: _pickSpinImages,
                                isSmall: true,
                              ),
                              const SizedBox(height: 8),
                              if (_spinExisting.isNotEmpty ||
                                  _spinPicked.isNotEmpty)
                                _miniStrip(
                                  existingUrls: _spinExisting,
                                  pickedFiles: _spinPicked,
                                  onRemoveExisting: _removeSpinExistingAt,
                                  onRemovePicked: _removeSpinPickedAt,
                                ),
                              const SizedBox(height: 14),
                              _MediaSelectorTile(
                                label: '동영상 추가',
                                count:
                                _videoExisting.length + _videoPicked.length,
                                icon: Icons.videocam_rounded,
                                onTap: _pickVideos,
                                isSmall: true,
                              ),
                              const SizedBox(height: 8),
                              if (_videoExisting.isNotEmpty ||
                                  _videoPicked.isNotEmpty)
                                _miniVideoStrip(
                                  existingCount: _videoExisting.length,
                                  pickedCount: _videoPicked.length,
                                  onRemoveExisting: _removeVideoExistingAt,
                                  onRemovePicked: _removeVideoPickedAt,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 하단 버튼(디자인 유지)
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: _ChewyButton(
              isUploading: _saving,
              percent: _uploadPercent,
              onTap: _save,
              labelIdle: '수정 저장하기',
            ),
          ),

          if (_saving) _buildGlassOverlay(),
        ],
      ),
    );
  }

  // ───────── UI helpers ─────────

  Widget _sectionTitle(String title, ColorScheme cs) => Text(
    title,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w900,
      color: cs.onSurface.withValues(alpha: 0.4),
      letterSpacing: 0.5,
    ),
  );

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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey),
        filled: true,
        fillColor:
        isDark ? const Color(0xFF1A1D22) : const Color(0xFFF6F6F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(20),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? '필수 입력 사항입니다' : null
          : null,
    );
  }

  Widget _buildGlassOverlay() => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    child: Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _uploadProgress == 0 ? null : _uploadProgress,
              color: Colors.white,
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              '$_uploadPercent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              '변경 사항을 저장 중입니다',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _miniStrip({
    required List<String> existingUrls,
    required List<XFile> pickedFiles,
    required void Function(int) onRemoveExisting,
    required void Function(int) onRemovePicked,
  }) {
    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < existingUrls.length; i++)
            _MiniThumb(
              networkUrl: existingUrls[i],
              onRemove: () => onRemoveExisting(i),
            ),
          for (int i = 0; i < pickedFiles.length; i++)
            _MiniThumb(
              xfile: pickedFiles[i],
              onRemove: () => onRemovePicked(i),
            ),
        ],
      ),
    );
  }

  Widget _miniVideoStrip({
    required int existingCount,
    required int pickedCount,
    required void Function(int) onRemoveExisting,
    required void Function(int) onRemovePicked,
  }) {
    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < existingCount; i++)
            _MiniVideoThumb(onRemove: () => onRemoveExisting(i)),
          for (int i = 0; i < pickedCount; i++)
            _MiniVideoThumb(onRemove: () => onRemovePicked(i)),
        ],
      ),
    );
  }
}

// ───────── 브랜드 검색 시트 ─────────

class _BrandPickerSheet extends StatefulWidget {
  final bool isDark;
  final List<Map<String, String>> brands;
  final String? selectedKor;
  final void Function(String kor, String eng, String logoUrl) onPick;

  const _BrandPickerSheet({
    required this.isDark,
    required this.brands,
    required this.selectedKor,
    required this.onPick,
  });

  @override
  State<_BrandPickerSheet> createState() => _BrandPickerSheetState();
}

class _BrandPickerSheetState extends State<_BrandPickerSheet> {
  final _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = Theme.of(context).dividerColor;
    final q = _searchC.text.trim().toLowerCase();

    final filtered = widget.brands.where((b) {
      if (q.isEmpty) return true;
      final kor = (b['kor'] ?? '').toLowerCase();
      final eng = (b['eng'] ?? '').toLowerCase();
      return kor.contains(q) || eng.contains(q);
    }).toList();

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.68,
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '브랜드 선택',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchC,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '브랜드 검색 (한글/영문)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchC.text.isEmpty
                      ? null
                      : IconButton(
                    onPressed: () {
                      _searchC.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: line),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final kor = filtered[i]['kor'] ?? '';
                  final eng = filtered[i]['eng'] ?? '';
                  final logo = filtered[i]['logoUrl'] ?? '';

                  return _ChewyInteraction(
                    child: ListTile(
                      leading: (logo.isNotEmpty)
                          ? CircleAvatar(backgroundImage: NetworkImage(logo))
                          : CircleAvatar(
                        backgroundColor:
                        cs.onSurface.withValues(alpha: 0.06),
                        child: Text(
                          kor.isNotEmpty ? kor.characters.first : 'B',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      title: Text(
                        kor,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: eng.isEmpty ? null : Text(eng),
                      trailing: widget.selectedKor == kor
                          ? Icon(Icons.check_circle, color: cs.onSurface)
                          : null,
                      onTap: () => widget.onPick(kor, eng, logo),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────── 공용 위젯(디자인 유지) ─────────

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
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: isSmall ? 14 : 16,
                ),
              ),
              const Spacer(),
              if (count > 0)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.onSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: cs.surface,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.add_circle_rounded,
                size: 20,
                color: cs.onSurface.withValues(alpha: 0.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChewyButton extends StatefulWidget {
  final bool isUploading;
  final int percent;
  final VoidCallback onTap;
  final String labelIdle;

  const _ChewyButton({
    required this.isUploading,
    required this.percent,
    required this.onTap,
    required this.labelIdle,
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
            boxShadow: [
              BoxShadow(
                color: cs.onSurface.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.isUploading
                  ? '저장 중 (${widget.percent}%)'
                  : widget.labelIdle,
              style: TextStyle(
                color: cs.surface,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniThumb extends StatelessWidget {
  final String? networkUrl;
  final XFile? xfile;
  final VoidCallback onRemove;

  const _MiniThumb({
    required this.onRemove,
    this.networkUrl,
    this.xfile,
  });

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 80,
        height: 80,
        color: const Color(0xFFF4F4F4),
        alignment: Alignment.center,
        child: networkUrl != null
            ? Image.network(
          networkUrl!,
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined),
        )
            : FutureBuilder<Uint8List>(
          future: xfile!.readAsBytes(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Container(
                width: 80,
                height: 80,
                color: Colors.black.withValues(alpha: 0.06),
              );
            }
            return Image.memory(
              snap.data!,
              width: 80,
              height: 80,
              fit: BoxFit.contain,
            );
          },
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          child,
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniVideoThumb extends StatelessWidget {
  final VoidCallback onRemove;
  const _MiniVideoThumb({required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}