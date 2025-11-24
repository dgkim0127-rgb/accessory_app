// lib/pages/edit_post_page.dart  ✅ 최종
// - 사진 + 360° + 동영상 수정 가능
// - 사진 순서: 기존/새 이미지 포함해서 썸네일 가로 리스트에서 드래그로 순서 변경 가능
// - 드래그 중: 선택된 사진은 확대 + 테두리, 나머지는 살짝 어두워짐
// - UploadService 사용: 이미지/360/동영상 업로드
// - 저장(업로드) 중 전체 화면 로딩 오버레이 + % 진행률 표시
// - Cloudinary 변환 기반 썸네일/미디엄 URL 관리
//   (thumbImages / mediumImages, thumbUrl / mediumUrl)
// - 품번(itemCode) 수정 지원

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/upload_service.dart';
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

class _EditPostPageState extends State<EditPostPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _codeCtrl; // 🔥 품번

  // 브랜드/카테고리
  List<Map<String, String>> _brands = [];
  String? _brandKor; // posts.brand
  String? _brandEng; // posts.brandEng
  String? _brandLogoUrl; // posts.brandLogoUrl
  String _category = 'necklace';

  static const _cats = <Map<String, String>>[
    {'code': 'necklace', 'label': '목걸이'},
    {'code': 'ring', 'label': '반지'},
    {'code': 'earring', 'label': '귀걸이'},
    {'code': 'bracelet', 'label': '팔찌'},
    {'code': 'acc', 'label': '기타'},
  ];

  // 사진 (기존 + 새 이미지)
  final List<String> _existingImages = []; // 기존 이미지 URL
  final List<String> _existingThumbImages = [];
  final List<String> _existingMediumImages = [];
  final List<XFile> _pickedImages = []; // 새 이미지

  // 360도용
  final List<String> _spinExisting = []; // 기존 360도 URL
  final List<XFile> _spinPicked = []; // 새 360도 이미지

  // 동영상
  final List<String> _videoExisting = []; // 기존 동영상 URL
  final List<XFile> _videoPicked = []; // 새 동영상

  bool _saving = false;
  double _uploadProgress = 0;
  int _uploadPercent = 0;

  // 상단 미리보기 페이지 인덱스 (0-based)
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  // 사진 순서 편집용: 드래그 중인 인덱스
  int? _draggingPhotoIndex;

  // 전체 사진 수 (기존 + 새)
  int get _totalMediaCount => _existingImages.length + _pickedImages.length;

  final ImagePicker _picker = ImagePicker();

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
    _category = (widget.initialData['category'] ?? 'necklace').toString();

    // 브랜드 초기값
    final rawKor = (widget.initialData['brand'] ?? '').toString();
    _brandKor = rawKor.isEmpty ? null : rawKor;
    _brandEng = (widget.initialData['brandEng'] ?? '').toString();
    _brandLogoUrl =
        (widget.initialData['brandLogoUrl'] ?? widget.initialData['logoUrl'] ?? '')
            .toString();

    // 이미지 초기값
    final imgs = widget.initialData['images'];
    if (imgs is List && imgs.isNotEmpty) {
      _existingImages.addAll(
        imgs.map((e) => (e ?? '').toString()).where((s) => s.isNotEmpty),
      );
    } else {
      final one = (widget.initialData['imageUrl'] ?? '').toString();
      if (one.isNotEmpty) _existingImages.add(one);
    }

    // 썸네일/미디엄 초기값 (없으면 런타임으로 생성)
    final thumbs = widget.initialData['thumbImages'];
    if (thumbs is List && thumbs.isNotEmpty) {
      _existingThumbImages.addAll(
        thumbs.map((e) => (e ?? '').toString()).where((s) => s.isNotEmpty),
      );
    }

    final mediums = widget.initialData['mediumImages'];
    if (mediums is List && mediums.isNotEmpty) {
      _existingMediumImages.addAll(
        mediums.map((e) => (e ?? '').toString()).where((s) => s.isNotEmpty),
      );
    }

    if (_existingImages.isNotEmpty && _existingThumbImages.isEmpty) {
      _existingThumbImages.addAll(
        _existingImages.map((u) => buildThumbUrl(u)),
      );
    }
    if (_existingImages.isNotEmpty && _existingMediumImages.isEmpty) {
      _existingMediumImages.addAll(
        _existingImages.map((u) => buildMediumUrl(u)),
      );
    }

    // 360도 초기값
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

    // 권한 토큰 최신화
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

  // Firestore brands → 동적 브랜드 목록
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
          'logoUrl': (m['logoUrl'] ?? '').toString().trim(),
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

  // ───────── 미디어 선택 ─────────

  Future<void> _pickImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 92);
      if (files.isEmpty) return;
      setState(() => _pickedImages.addAll(files));
    } catch (e) {
      _showSnack('사진 선택 실패: $e');
    }
  }

  Future<void> _pickSpinImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 92);
      if (files.isEmpty) return;
      setState(() => _spinPicked.addAll(files));
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
          add.add(
            XFile.fromData(
              f.bytes!,
              name: f.name,
            ),
          );
        }
        setState(() => _videoPicked.addAll(add));
      } else {
        final picked = await _picker.pickVideo(source: ImageSource.gallery);
        if (picked != null) {
          setState(() => _videoPicked.add(picked));
        }
      }
    } catch (e) {
      _showSnack('동영상 선택 실패: $e');
    }
  }

  // ───────── 사진 제거 + 순서 재정렬 ─────────

  void _removeExistingImageAt(int i) {
    setState(() {
      _existingImages.removeAt(i);
      if (_existingThumbImages.length > i) {
        _existingThumbImages.removeAt(i);
      }
      if (_existingMediumImages.length > i) {
        _existingMediumImages.removeAt(i);
      }
      if (_currentPage >= _totalMediaCount) {
        _currentPage = _totalMediaCount == 0 ? 0 : _totalMediaCount - 1;
      }
    });
  }

  void _removePickedImageAt(int i) {
    setState(() {
      _pickedImages.removeAt(i);
      if (_currentPage >= _totalMediaCount) {
        _currentPage = _totalMediaCount == 0 ? 0 : _totalMediaCount - 1;
      }
    });
  }

  void _removeSpinExistingAt(int i) =>
      setState(() => _spinExisting.removeAt(i));

  void _removeSpinPickedAt(int i) =>
      setState(() => _spinPicked.removeAt(i));

  void _removeVideoExistingAt(int i) =>
      setState(() => _videoExisting.removeAt(i));

  void _removeVideoPickedAt(int i) =>
      setState(() => _videoPicked.removeAt(i));

  // index 기준 → (isExisting, realIndex)로 변환
  ({bool fromExisting, int realIndex}) _decodePhotoIndex(int combinedIndex) {
    if (combinedIndex < _existingImages.length) {
      return (fromExisting: true, realIndex: combinedIndex);
    } else {
      final idx = combinedIndex - _existingImages.length;
      return (fromExisting: false, realIndex: idx);
    }
  }

  // combined index 두 개를 서로 재정렬
  void _reorderPhoto(int from, int to) {
    setState(() {
      if (from == to) return;
      final total = _totalMediaCount;
      if (from < 0 || from >= total || to < 0 || to >= total) return;

      final fromInfo = _decodePhotoIndex(from);
      final toInfo = _decodePhotoIndex(to);

      // 1) existing ↔ existing
      if (fromInfo.fromExisting && toInfo.fromExisting) {
        final item = _existingImages.removeAt(fromInfo.realIndex);
        _existingImages.insert(toInfo.realIndex, item);

        if (_existingThumbImages.length > fromInfo.realIndex) {
          final thumb =
          _existingThumbImages.removeAt(fromInfo.realIndex);
          _existingThumbImages.insert(toInfo.realIndex, thumb);
        }
        if (_existingMediumImages.length > fromInfo.realIndex) {
          final medium =
          _existingMediumImages.removeAt(fromInfo.realIndex);
          _existingMediumImages.insert(toInfo.realIndex, medium);
        }
        return;
      }

      // 2) picked ↔ picked
      if (!fromInfo.fromExisting && !toInfo.fromExisting) {
        final item = _pickedImages.removeAt(fromInfo.realIndex);
        _pickedImages.insert(toInfo.realIndex, item);
        return;
      }

      // 3) existing → picked 또는 picked → existing
      if (fromInfo.fromExisting && !toInfo.fromExisting) {
        // existing → picked 영역으로 이동
        final img = _existingImages.removeAt(fromInfo.realIndex);
        String? thumb;
        String? medium;
        if (_existingThumbImages.length > fromInfo.realIndex) {
          thumb = _existingThumbImages.removeAt(fromInfo.realIndex);
        }
        if (_existingMediumImages.length > fromInfo.realIndex) {
          medium = _existingMediumImages.removeAt(fromInfo.realIndex);
        }

        final destIndexInPicked = toInfo.realIndex;
        _pickedImages.insert(destIndexInPicked, XFile(img));
        return;
      }

      if (!fromInfo.fromExisting && toInfo.fromExisting) {
        // picked → existing 영역으로 이동
        final x = _pickedImages.removeAt(fromInfo.realIndex);

        final destIndexInExisting = toInfo.realIndex;
        _existingImages.insert(destIndexInExisting, x.path);
        _existingThumbImages.insert(
          destIndexInExisting,
          buildThumbUrl(x.path),
        );
        _existingMediumImages.insert(
          destIndexInExisting,
          buildMediumUrl(x.path),
        );
        return;
      }
    });
  }

  void _setUploadProgress(double fraction) {
    fraction = fraction.clamp(0, 1);
    setState(() {
      _uploadProgress = fraction;
      _uploadPercent = (fraction * 100).round();
    });
  }

  // ───────── 저장 ─────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if ((_brandKor ?? '').trim().isEmpty) {
      _showSnack('브랜드를 선택해주세요.');
      return;
    }

    if (_existingImages.isEmpty && _pickedImages.isEmpty) {
      _showSnack('사진을 최소 1개 선택해주세요.');
      return;
    }

    setState(() {
      _saving = true;
      _uploadProgress = 0;
      _uploadPercent = 0;
    });

    try {
      final brandKor = _brandKor!.trim();
      final docRef =
      FirebaseFirestore.instance.collection('posts').doc(widget.postId);

      // 새 이미지 업로드
      final newImageOriginal = <String>[];
      final newThumbImages = <String>[];
      final newMediumImages = <String>[];

      // 새 360도/동영상
      final newSpinUrls = <String>[];
      final newVideoUrls = <String>[];

      final totalNewFiles =
          _pickedImages.length + _spinPicked.length + _videoPicked.length;
      int done = 0;
      void bumpProgress() {
        if (totalNewFiles <= 0) return;
        done++;
        _setUploadProgress(done / totalNewFiles);
      }

      // 기존 이미지 개수를 기준으로 index 오프셋
      final existingCount = _existingImages.length;

      for (int i = 0; i < _pickedImages.length; i++) {
        final xf = _pickedImages[i];
        final url = await UploadService.uploadImage(
          postId: widget.postId,
          brandKor: brandKor,
          index: existingCount + i,
          file: xf,
        );
        newImageOriginal.add(url);
        newThumbImages.add(buildThumbUrl(url));
        newMediumImages.add(buildMediumUrl(url));
        bumpProgress();
      }

      for (int i = 0; i < _spinPicked.length; i++) {
        final xf = _spinPicked[i];
        final url = await UploadService.uploadSpinImage(
          postId: widget.postId,
          brandKor: brandKor,
          index: i + _spinExisting.length,
          file: xf,
        );
        newSpinUrls.add(url);
        bumpProgress();
      }

      for (int i = 0; i < _videoPicked.length; i++) {
        final xf = _videoPicked[i];
        final url = await UploadService.uploadVideo(
          postId: widget.postId,
          brandKor: brandKor,
          index: i + _videoExisting.length,
          file: xf,
        );
        newVideoUrls.add(url);
        bumpProgress();
      }

      final allImages = <String>[
        ..._existingImages,
        ...newImageOriginal,
      ];
      final allThumbImages = <String>[
        ..._existingThumbImages,
        ...newThumbImages,
      ];
      final allMediumImages = <String>[
        ..._existingMediumImages,
        ...newMediumImages,
      ];
      final allSpins = <String>[
        ..._spinExisting,
        ...newSpinUrls,
      ];
      final allVideos = <String>[
        ..._videoExisting,
        ...newVideoUrls,
      ];

      final primaryImageUrl = allImages.isNotEmpty
          ? allImages.first
          : (widget.initialData['imageUrl'] ?? '').toString();

      final primaryThumbUrl = allThumbImages.isNotEmpty
          ? allThumbImages.first
          : buildThumbUrl(primaryImageUrl);

      final primaryMediumUrl = allMediumImages.isNotEmpty
          ? allMediumImages.first
          : buildMediumUrl(primaryImageUrl);

      final updates = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
        'brand': brandKor,
        'brandEng': _brandEng ?? '',
        'brandLogoUrl': _brandLogoUrl ?? '',
        'itemCode': _codeCtrl.text.trim(),

        // 전체 이미지 배열
        'images': allImages,
        'thumbImages': allThumbImages,
        'mediumImages': allMediumImages,

        // 대표 이미지
        'imageUrl': primaryImageUrl,
        'thumbUrl': primaryThumbUrl,
        'mediumUrl': primaryMediumUrl,

        // 360 / 동영상
        'spinImages': allSpins,
        'videos': allVideos,

        'updatedAt': FieldValue.serverTimestamp(),
      };

      await docRef.update(updates);

      if (!mounted) return;
      if (totalNewFiles > 0) {
        _setUploadProgress(1.0);
      }
      _showSnack('수정 완료');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('수정 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────── 상단 미리보기 빌더 ─────────

  Widget _buildMediaPage(int index) {
    int idx = index;

    // 1) 기존 이미지
    if (idx < _existingImages.length) {
      final url = _existingImages[idx];
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: IconButton(
              onPressed: () => _removeExistingImageAt(idx),
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      );
    }
    idx -= _existingImages.length;

    // 2) 새 이미지
    if (idx < _pickedImages.length) {
      final x = _pickedImages[idx];
      return Stack(
        fit: StackFit.expand,
        children: [
          kIsWeb
              ? Image.network(x.path, fit: BoxFit.cover)
              : Image.file(File(x.path), fit: BoxFit.cover),
          Positioned(
            left: 8,
            top: 8,
            child: IconButton(
              onPressed: () => _removePickedImageAt(idx),
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      );
    }

    return const Center(child: Icon(Icons.broken_image_outlined));
  }

  Widget _buildPreviewArea() {
    final hasMedia = _totalMediaCount > 0;

    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          if (hasMedia)
            PageView.builder(
              controller: _pageCtrl,
              itemCount: _totalMediaCount,
              onPageChanged: (i) {
                setState(() => _currentPage = i);
              },
              itemBuilder: (context, index) {
                return _buildMediaPage(index);
              },
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

          // 우측 상단: "현재/전체" 카운터
          if (hasMedia)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
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
    );
  }

  // ───────── 사진 썸네일 리스트 (꾹 눌러 드래그 + 선택 이외 어둡게) ─────────

  Widget _buildPhotoReorderGrid() {
    if (_totalMediaCount <= 1) {
      // 1장이면 굳이 드래그할 필요 없음
      return const SizedBox.shrink();
    }

    // combined 리스트: 기존 + 새 이미지 (UI용)
    final tiles = <Widget>[];
    for (int i = 0; i < _existingImages.length; i++) {
      tiles.add(_PhotoThumbTile(
        key: ValueKey('existing_$i'),
        imageProvider: NetworkImage(_existingImages[i]),
      ));
    }
    for (int i = 0; i < _pickedImages.length; i++) {
      final x = _pickedImages[i];
      final provider = kIsWeb
          ? NetworkImage(x.path)
          : FileImage(File(x.path)) as ImageProvider;
      tiles.add(_PhotoThumbTile(
        key: ValueKey('picked_$i'),
        imageProvider: provider,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '사진 순서 편집',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
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
            itemCount: _totalMediaCount,
            onReorderStart: (i) {
              setState(() => _draggingPhotoIndex = i);
            },
            onReorderEnd: (_) {
              setState(() => _draggingPhotoIndex = null);
            },
            onReorder: (from, to) {
              if (to > from) to -= 1;
              _reorderPhoto(from, to);
            },
            itemBuilder: (context, index) {
              final tile = tiles[index];
              final bool isDragging =
                  _draggingPhotoIndex != null && _draggingPhotoIndex == index;
              final bool dimOthers =
                  _draggingPhotoIndex != null && _draggingPhotoIndex != index;

              return ReorderableDelayedDragStartListener(
                key: tile.key!,
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
                                ? Border.all(
                              color: Colors.black,
                              width: 2,
                            )
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: tile,
                          ),
                        ),
                      ),
                      // 드래그 중일 때, 선택된 사진 이외는 살짝 어둡게
                      if (dimOthers)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () {
                            final info = _decodePhotoIndex(index);
                            if (info.fromExisting) {
                              _removeExistingImageAt(info.realIndex);
                            } else {
                              _removePickedImageAt(info.realIndex);
                            }
                          },
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
          if ((b['logoUrl'] ?? '').isNotEmpty)
            const SizedBox(width: 6),
          Text(b['kor']!),
        ],
      ),
    ))
        .toList();

    String? brandValue = _brandKor;
    if (brandValue != null &&
        _brands.isNotEmpty &&
        !_brands.any((b) => b['kor'] == brandValue)) {
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
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPreviewArea(),
                const SizedBox(height: 12),
                _buildPhotoReorderGrid(), // 🔥 사진 순서 편집 + 꾹 눌러 선택/드래그
                const SizedBox(height: 14),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 브랜드 / 카테고리
                      const Text(
                        '브랜드 / 카테고리',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        items: brandItems,
                        value: brandValue,
                        decoration: const InputDecoration(
                          labelText: '브랜드',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          if (val == null) return;
                          final b =
                          _brands.firstWhere((e) => e['kor'] == val);
                          setState(() {
                            _brandKor = b['kor'];
                            _brandEng = b['eng'] ?? '';
                            _brandLogoUrl = b['logoUrl'] ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        items: catItems,
                        value: _category,
                        decoration: const InputDecoration(
                          labelText: '카테고리',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) =>
                            setState(() => _category = v ?? 'necklace'),
                      ),
                      const SizedBox(height: 16),

                      // 품번
                      const Text(
                        '품번',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _codeCtrl,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '품번을 입력하세요'
                            : null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '예: AB-1234',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 제목
                      const Text(
                        '제목',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleCtrl,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '제목을 입력하세요'
                            : null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '제목을 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 상세
                      const Text(
                        '상세',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '상세 설명을 입력하세요',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 사진
                      const Text(
                        '사진',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickImages,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              side: const BorderSide(
                                  color: Color(0xffe6e6e6)),
                            ),
                            icon: const Icon(Icons.photo_library_outlined,
                                size: 18),
                            label: const Text('사진 추가'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '총 $_totalMediaCount개 선택됨',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 360도 사진
                      const Text(
                        '360도 사진',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickSpinImages,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              side: const BorderSide(
                                  color: Color(0xffe6e6e6)),
                            ),
                            icon: const Icon(Icons.threesixty, size: 18),
                            label: const Text('360° 이미지 추가'),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${_spinExisting.length + _spinPicked.length}장)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_spinExisting.isNotEmpty || _spinPicked.isNotEmpty)
                        SizedBox(
                          height: 80,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              // 기존 360
                              for (int i = 0;
                              i < _spinExisting.length;
                              i++)
                                Padding(
                                  padding:
                                  const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                        BorderRadius.circular(4),
                                        child: Image.network(
                                          _spinExisting[i],
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: 2,
                                        top: 2,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _removeSpinExistingAt(i),
                                          child: Container(
                                            padding:
                                            const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                              BorderRadius.circular(
                                                  999),
                                            ),
                                            child: const Icon(Icons.close,
                                                size: 14,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              // 새 360
                              for (int i = 0;
                              i < _spinPicked.length;
                              i++)
                                Padding(
                                  padding:
                                  const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                        BorderRadius.circular(4),
                                        child: kIsWeb
                                            ? Image.network(
                                          _spinPicked[i].path,
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        )
                                            : Image.file(
                                          File(_spinPicked[i].path),
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        right: 2,
                                        top: 2,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _removeSpinPickedAt(i),
                                          child: Container(
                                            padding:
                                            const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                              BorderRadius.circular(
                                                  999),
                                            ),
                                            child: const Icon(Icons.close,
                                                size: 14,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // 동영상
                      const Text(
                        '동영상',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pickVideos,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              side: const BorderSide(
                                  color: Color(0xffe6e6e6)),
                            ),
                            icon: const Icon(
                                Icons.video_library_outlined,
                                size: 18),
                            label: const Text('동영상 추가'),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${_videoExisting.length + _videoPicked.length}개 선택됨)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_videoExisting.isNotEmpty ||
                          _videoPicked.isNotEmpty)
                        SizedBox(
                          height: 80,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (int i = 0;
                              i < _videoExisting.length;
                              i++)
                                Padding(
                                  padding:
                                  const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                          BorderRadius.circular(4),
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
                                          onTap: () =>
                                              _removeVideoExistingAt(i),
                                          child: Container(
                                            padding:
                                            const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                              BorderRadius.circular(
                                                  999),
                                            ),
                                            child: const Icon(Icons.close,
                                                size: 14,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              for (int i = 0;
                              i < _videoPicked.length;
                              i++)
                                Padding(
                                  padding:
                                  const EdgeInsets.only(right: 8),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius:
                                          BorderRadius.circular(4),
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
                                          onTap: () =>
                                              _removeVideoPickedAt(i),
                                          child: Container(
                                            padding:
                                            const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                              BorderRadius.circular(
                                                  999),
                                            ),
                                            child: const Icon(Icons.close,
                                                size: 14,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
              ],
            ),
          ),

          // 🔥 저장 로딩 오버레이 (new_post_page 스타일로 맞춤)
          if (_saving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.45),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              strokeWidth: 3,
                              value: _uploadProgress == 0
                                  ? null
                                  : _uploadProgress,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.white,
                              ),
                            ),
                            Text(
                              '$_uploadPercent%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '게시물을 저장하는 중이에요...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────── 사진 썸네일 타일 ─────────

class _PhotoThumbTile extends StatelessWidget {
  final ImageProvider imageProvider;
  const _PhotoThumbTile({
    super.key,
    required this.imageProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Image(
      image: imageProvider,
      fit: BoxFit.cover,
    );
  }
}
