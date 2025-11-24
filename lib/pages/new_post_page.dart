// lib/pages/new_post_page.dart  ✅ 최종 (간단 버전)
// - 대표 이미지(사진만) + 360° 이미지 + 동영상 업로드
// - 업로드는 파일 단위 병렬로 처리 (속도 ↑)
// - 각 파일 업로드 시간 + 전체 업로드 시간 print 로그
// - Cloudinary 변환 기반 썸네일/미디엄 URL 생성 후 Firestore에 함께 저장
//   (thumbUrl / mediumUrl / thumbImages / mediumImages)
//
// 🔥 2025-11-24 수정
// - "선택한 이미지 보기/순서 편집" 바텀 시트 모두 제거 → 버튼 누르면 바로 선택만
// - 메인/360/동영상 썸네일은 화면에서 바로 드래그로 순서 변경 + X 버튼으로 삭제

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:accessory_app/widgets/progress_button.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:accessory_app/services/upload_service.dart';
import 'package:accessory_app/utils/cloudinary_image_utils.dart';

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
  final _codeC = TextEditingController(); // 🔥 품번 입력용

  String? _brandKor;
  _Cat _selected = _cats.first;

  final _picker = ImagePicker();

  // ✅ 대표 이미지(사진만)
  final List<XFile> _mainImages = [];

  // ✅ 360도(Spin) 이미지
  final List<XFile> _spinPicked = [];

  // ✅ 동영상 파일들
  final List<XFile> _videoFiles = [];

  // ✅ 동영상 썸네일 캐시 (파일 경로(path) 기준)
  final Map<String, Uint8List> _videoThumbCache = {};

  bool _saving = false;
  double _uploadProgress = 0;
  int _uploadPercent = 0;

  // 360 / 동영상 선택 등 로컬 작업 중일 때 전체를 덮는 로딩 오버레이
  bool _busyOverlay = false;

  @override
  void initState() {
    super.initState();
    _brandKor = widget.initialBrandKor;
    // 토큰 미리 갱신 (업로드 중간에 인증 만료 방지용, 실패해도 무시)
    FirebaseAuth.instance.currentUser?.getIdToken(true).catchError((_) {});
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _codeC.dispose(); // 🔥 품번 컨트롤러도 해제
    super.dispose();
  }

  // ───────── 유틸 ─────────

  String _extFromName(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return '';
    return name.substring(i + 1).toLowerCase();
  }

  String _guessImageMime(String name) {
    final ext = _extFromName(name);
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  // ✅ 동영상 MIME 추정 (웹에서 사용)
  String _guessVideoMime(String name) {
    final ext = _extFromName(name);
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  void _setUploadProgress(double fraction) {
    fraction = fraction.clamp(0, 1);
    setState(() {
      _uploadProgress = fraction;
      _uploadPercent = (fraction * 100).round();
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ 동영상 썸네일용 바이트 로더 (간단히 첫 프레임 대신 정적 프리뷰로 사용)
  Future<Uint8List> _loadVideoThumbBytes(XFile x) async {
    final key = x.path;
    final cached = _videoThumbCache[key];
    if (cached != null) return cached;

    final bytes = await x.readAsBytes();
    _videoThumbCache[key] = bytes;
    return bytes;
  }

  // ───────── 제출(업로드) : 병렬 업로드 + 시간 로그 ─────────

  Future<void> _submit() async {
    if (_brandKor == null || _brandKor!.trim().isEmpty) {
      _toast('브랜드를 선택해주세요. (카테고리에서 브랜드를 먼저 추가하세요)');
      return;
    }
    if (_mainImages.isEmpty) {
      _toast('대표 이미지를 한 개 이상 선택해주세요.');
      return;
    }
    if (!_form.currentState!.validate()) return;

    // 360 이미지 너무 많으면 시작 전에 막기
    if (_spinPicked.length > 50) {
      _toast('360° 이미지는 최대 50장까지만 업로드할 수 있어요. (현재: ${_spinPicked.length}장)');
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

      // ── 1) 브랜드 문서 확인 ───────────────────────
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
      final brandId = brandDoc.id;
      final brandEng = (brandDoc.data()['nameEng'] ?? '').toString();

      // ── 2) 업로드 대상 리스트 준비 ─────────────────
      final imagesFiles = List<XFile>.from(_mainImages);
      final spinFiles = List<XFile>.from(_spinPicked);
      final videoFiles = List<XFile>.from(_videoFiles);

      final totalFiles =
          imagesFiles.length + spinFiles.length + videoFiles.length;
      if (totalFiles <= 0) {
        _toast('업로드할 파일이 없습니다.');
        setState(() => _saving = false);
        return;
      }

      print('===== UPLOAD START =====');
      print(
          '대표 이미지: ${imagesFiles.length}장, 360° 이미지: ${spinFiles.length}장, 동영상: ${videoFiles.length}개');

      int done = 0;
      void oneDone() {
        done++;
        _setUploadProgress(done / totalFiles);
      }

      final posts = FirebaseFirestore.instance.collection('posts');
      final doc = posts.doc();

      // 병렬 업로드 결과를 담을 리스트 (인덱스 보존)
      final List<String?> imageUrlsTemp =
      List<String?>.filled(imagesFiles.length, null, growable: false);
      final List<String?> thumbUrlsTemp =
      List<String?>.filled(imagesFiles.length, null, growable: false);
      final List<String?> mediumUrlsTemp =
      List<String?>.filled(imagesFiles.length, null, growable: false);

      final List<String?> spinUrlsTemp =
      List<String?>.filled(spinFiles.length, null, growable: false);
      final List<String?> videoUrlsTemp =
      List<String?>.filled(videoFiles.length, null, growable: false);

      final List<Future<void>> tasks = [];

      // 전체 시간 측정용 스톱워치
      final totalSw = Stopwatch()..start();

      // ── 3) 대표 이미지 병렬 업로드 (+ 시간 로그) ─────────────────
      for (int i = 0; i < imagesFiles.length; i++) {
        final idx = i;
        final x = imagesFiles[idx];

        tasks.add(() async {
          final sw = Stopwatch()..start();
          int size = 0;
          try {
            size = await x.length();
          } catch (_) {}

          print(
              '[UPLOAD] main[$idx] start: ${x.name} (size ~ ${(size / 1024).toStringAsFixed(1)} KB)');

          try {
            final url = await UploadService.uploadImage(
              postId: doc.id,
              brandKor: _brandKor!,
              index: idx,
              file: x,
            );
            imageUrlsTemp[idx] = url;
            // Cloudinary 변환으로 썸네일 / 미디엄 URL 생성
            thumbUrlsTemp[idx] = buildThumbUrl(url);
            mediumUrlsTemp[idx] = buildMediumUrl(url);

            sw.stop();
            print(
                '[UPLOAD] main[$idx] done in ${sw.elapsedMilliseconds} ms → $url');
          } catch (e) {
            sw.stop();
            print(
                '[UPLOAD] main[$idx] error after ${sw.elapsedMilliseconds} ms: $e');
          } finally {
            oneDone();
          }
        }());
      }

      // ── 4) 360° 이미지 병렬 업로드 (+ 시간 로그) ────────────────
      for (int i = 0; i < spinFiles.length; i++) {
        final idx = i;
        final x = spinFiles[idx];

        tasks.add(() async {
          final sw = Stopwatch()..start();
          int size = 0;
          try {
            size = await x.length();
          } catch (_) {}

          print(
              '[UPLOAD] spin[$idx] start: ${x.name} (size ~ ${(size / 1024).toStringAsFixed(1)} KB)');

          try {
            final url = await UploadService.uploadSpinImage(
              postId: doc.id,
              brandKor: _brandKor!,
              index: idx,
              file: x,
            );
            spinUrlsTemp[idx] = url;
            sw.stop();
            print(
                '[UPLOAD] spin[$idx] done in ${sw.elapsedMilliseconds} ms → $url');
          } catch (e) {
            sw.stop();
            print(
                '[UPLOAD] spin[$idx] error after ${sw.elapsedMilliseconds} ms: $e');
          } finally {
            oneDone();
          }
        }());
      }

      // ── 4-b) 동영상 병렬 업로드 (+ 시간 로그) ────────────────
      for (int i = 0; i < videoFiles.length; i++) {
        final idx = i;
        final x = videoFiles[idx];

        tasks.add(() async {
          final sw = Stopwatch()..start();
          int size = 0;
          try {
            size = await x.length();
          } catch (_) {}

          print(
              '[UPLOAD] video[$idx] start: ${x.name} (size ~ ${(size / 1024).toStringAsFixed(1)} KB)');

          try {
            final url = await UploadService.uploadVideo(
              postId: doc.id,
              brandKor: _brandKor!,
              index: idx,
              file: x,
            );
            videoUrlsTemp[idx] = url;
            sw.stop();
            print(
                '[UPLOAD] video[$idx] done in ${sw.elapsedMilliseconds} ms → $url');
          } catch (e) {
            sw.stop();
            print(
                '[UPLOAD] video[$idx] error after ${sw.elapsedMilliseconds} ms: $e');
          } finally {
            oneDone();
          }
        }());
      }

      // 모든 업로드 완료까지 대기
      await Future.wait(tasks);

      totalSw.stop();
      final totalMs = totalSw.elapsedMilliseconds;
      final avgMsPerFile = totalFiles > 0 ? totalMs / totalFiles : 0.0;

      print('===== ALL UPLOAD TASKS FINISHED =====');
      print(
          '[UPLOAD] TOTAL: ${totalMs} ms for $totalFiles files (avg ${avgMsPerFile.toStringAsFixed(0)} ms/file)');

      // null 제거 후 최종 리스트로 정리
      final imageUrls = imageUrlsTemp.whereType<String>().toList();
      final thumbImageUrls = thumbUrlsTemp.whereType<String>().toList();
      final mediumImageUrls = mediumUrlsTemp.whereType<String>().toList();
      final spinUrls = spinUrlsTemp.whereType<String>().toList();
      final videoUrls = videoUrlsTemp.whereType<String>().toList();

      if (imageUrls.isEmpty) {
        _toast('대표 이미지 업로드에 실패했습니다. 다시 시도해주세요.');
        setState(() => _saving = false);
        return;
      }

      _setUploadProgress(1.0);

      // ── 5) Firestore 문서 생성 ────────────────────
      final nowTs = Timestamp.now();
      final primaryImageUrl = imageUrls.first;
      final primaryThumbUrl = thumbImageUrls.isNotEmpty
          ? thumbImageUrls.first
          : buildThumbUrl(primaryImageUrl);
      final primaryMediumUrl = mediumImageUrls.isNotEmpty
          ? mediumImageUrls.first
          : buildMediumUrl(primaryImageUrl);

      await doc.set({
        'brandId': brandId,
        'brand': _brandKor,
        'brandEng': brandEng,
        'category': _selected.code,
        'title': _titleC.text.trim(),
        'description': _descC.text.trim(),

        // 🔥 품번(제품 코드)
        'itemCode': _codeC.text.trim(),

        // 대표 이미지 원본 + 썸네일 + 미디엄
        'imageUrl': primaryImageUrl,
        'thumbUrl': primaryThumbUrl,
        'mediumUrl': primaryMediumUrl,

        // 전체 배열
        'images': imageUrls,
        'thumbImages': thumbImageUrls,
        'mediumImages': mediumImageUrls,

        'spinImages': spinUrls,
        'videos': videoUrls, // ✅ 동영상 URL 배열

        'likes': 0,
        'createdAt': nowTs,
        'updatedAt': nowTs,
        'uid': uid,
        'userName': user?.email ?? 'user',
      });

      if (!mounted) return;

      final totalSec = (totalMs / 1000).toStringAsFixed(1);
      final avgSec = (avgMsPerFile / 1000).toStringAsFixed(1);
      _toast('업로드 완료 (총 ${totalSec}s, 평균 ${avgSec}s/파일)');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _toast('업로드 실패: $e');
      print('[UPLOAD] ERROR: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    final bool disabledTopAction = _saving || _busyOverlay;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('새 게시물'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ProgressTextAction(
              label: disabledTopAction ? '처리중' : '게시',
              progress: _saving ? _uploadProgress : null,
              onPressed: disabledTopAction ? null : _submit,
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Stack(
        children: [
          // 전체 폼
          AbsorbPointer(
            absorbing: _saving || _busyOverlay,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 브랜드
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
                              const Text('브랜드',
                                  style:
                                  TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                ),
                                child: Text(
                                  '불러오기 오류: ${snap.error}',
                                  style: const TextStyle(
                                      color: Colors.redAccent),
                                ),
                              ),
                            ],
                          );
                        }

                        final docs = snap.data?.docs ??
                            const <
                                QueryDocumentSnapshot<
                                    Map<String, dynamic>>>[];
                        final items = docs
                            .map((d) {
                          final m = d.data();
                          final kor =
                          (m['nameKor'] ?? '').toString().trim();
                          final rank = (m['rank'] is int)
                              ? m['rank'] as int
                              : 1000000000;
                          return MapEntry(rank, kor);
                        })
                            .toList()
                          ..sort((a, b) => a.key != b.key
                              ? a.key.compareTo(b.key)
                              : a.value.compareTo(b.value));

                        final brandList = items
                            .map((e) => e.value)
                            .where((e) => e.isNotEmpty)
                            .toList();

                        String? value = _brandKor;
                        if (value != null && !brandList.contains(value)) {
                          value = null;
                        }
                        if (value == null && brandList.isNotEmpty) {
                          value = brandList.first;
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _brandKor = value);
                            }
                          });
                        }

                        if (brandList.isEmpty) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('브랜드',
                                  style:
                                  TextStyle(fontWeight: FontWeight.w700)),
                              SizedBox(height: 8),
                              InputDecorator(
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                ),
                                child: Text(
                                  '등록된 브랜드가 없습니다. (카테고리 > 관리에서 브랜드를 추가하세요)',
                                  style:
                                  TextStyle(color: Colors.black54),
                                ),
                              ),
                            ],
                          );
                        }

                        return DropdownButtonFormField<String>(
                          value: value,
                          decoration: const InputDecoration(
                            labelText: '브랜드',
                            border: OutlineInputBorder(),
                          ),
                          items: brandList
                              .map((b) =>
                              DropdownMenuItem(value: b, child: Text(b)))
                              .toList(),
                          onChanged: (v) => setState(() => _brandKor = v),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    const Text('카테고리',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
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

                    // 🔥 품번 입력 (필수)
                    TextFormField(
                      controller: _codeC,
                      decoration: const InputDecoration(
                        labelText: '품번',
                        hintText: '예: AB-1234',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '품번을 입력하세요';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    TextFormField(
                      controller: _titleC,
                      decoration: const InputDecoration(
                        labelText: '제목',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '제목을 입력하세요'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descC,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '설명',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ✅ 대표 이미지
                    const Text(
                      '대표 이미지',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: disabledTopAction
                              ? null
                              : () => _pickMainImages(),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: line),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library_outlined, size: 18),
                              SizedBox(width: 6),
                              Text('사진 선택'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_mainImages.isNotEmpty)
                          Text(
                            '선택됨: ${_mainImages.length}장',
                            style: const TextStyle(color: Colors.black54),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_mainImages.isNotEmpty)
                      _ReorderableThumbGrid(
                        itemCount: _mainImages.length,
                        builder: (context, index) {
                          final x = _mainImages[index];
                          return _MainThumb(
                            key: ValueKey(x.path),
                            file: x,
                            onRemove: () {
                              setState(() {
                                _mainImages.removeAt(index);
                              });
                            },
                          );
                        },
                        onReorder: (from, to) {
                          setState(() {
                            if (to < 0 || to >= _mainImages.length) {
                              return;
                            }
                            final item = _mainImages.removeAt(from);
                            _mainImages.insert(to, item);
                          });
                        },
                      ),

                    const SizedBox(height: 20),

                    // 360° 이미지
                    const Text(
                      '360° 뷰(스핀) 이미지',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: disabledTopAction
                              ? null
                              : () => _pickSpinImages(),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: line),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.threesixty, size: 18),
                              SizedBox(width: 6),
                              Text('360° 이미지 선택'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_spinPicked.isNotEmpty)
                          Text(
                            '선택됨: ${_spinPicked.length}장',
                            style: const TextStyle(color: Colors.black54),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_spinPicked.isNotEmpty)
                      _ReorderableThumbGrid(
                        itemCount: _spinPicked.length,
                        builder: (context, index) {
                          final x = _spinPicked[index];
                          return _SpinThumb(
                            key: ValueKey(x.path),
                            file: x,
                            onRemove: () {
                              setState(() {
                                _spinPicked.removeAt(index);
                              });
                            },
                          );
                        },
                        onReorder: (from, to) {
                          setState(() {
                            if (to < 0 || to >= _spinPicked.length) {
                              return;
                            }
                            final item = _spinPicked.removeAt(from);
                            _spinPicked.insert(to, item);
                          });
                        },
                      ),

                    const SizedBox(height: 20),

                    // ✅ 동영상
                    const Text(
                      '동영상',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: disabledTopAction
                              ? null
                              : () => _pickVideos(),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: const BorderSide(color: line),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.video_library_outlined, size: 18),
                              SizedBox(width: 6),
                              Text('동영상 선택'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_videoFiles.isNotEmpty)
                          Text(
                            '선택됨: ${_videoFiles.length}개',
                            style: const TextStyle(color: Colors.black54),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_videoFiles.isNotEmpty)
                      _ReorderableThumbGrid(
                        itemCount: _videoFiles.length,
                        builder: (context, index) {
                          final x = _videoFiles[index];
                          return _VideoThumb(
                            key: ValueKey(x.path),
                            file: x,
                            loadThumb: _loadVideoThumbBytes,
                            onRemove: () {
                              setState(() {
                                final removed =
                                _videoFiles.removeAt(index);
                                _videoThumbCache.remove(removed.path);
                              });
                            },
                          );
                        },
                        onReorder: (from, to) {
                          setState(() {
                            if (to < 0 || to >= _videoFiles.length) {
                              return;
                            }
                            final item = _videoFiles.removeAt(from);
                            _videoFiles.insert(to, item);
                          });
                        },
                      ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),

          // 🔥 업로드 전체 로딩 오버레이
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
                              valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
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
                        '사진/동영상을 업로드하는 중이에요...',
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

          // 360 / 동영상 선택 로딩 오버레이
          if (_busyOverlay && !_saving)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.35),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '이미지를 준비중입니다...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
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

  // ───────── 심플 피커들 (바텀시트 X) ─────────

  // 메인(대표 이미지) 선택
  Future<void> _pickMainImages() async {
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
          final mime = _guessImageMime(f.name);
          add.add(
            XFile.fromData(
              f.bytes!,
              name: f.name,
              mimeType: mime,
              length: f.size,
            ),
          );
        }
        setState(() => _mainImages.addAll(add));
      } else {
        final files = await _picker.pickMultiImage();
        if (files.isEmpty) return;
        setState(() => _mainImages.addAll(files));
      }
    } catch (e) {
      _toast('사진 선택 실패: $e');
    }
  }

  // 360도(Spin) 선택
  Future<void> _pickSpinImages() async {
    try {
      setState(() => _busyOverlay = true);

      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) {
          setState(() => _busyOverlay = false);
          return;
        }

        final add = <XFile>[];
        for (final f in res.files) {
          if (f.bytes == null) continue;
          final mime = _guessImageMime(f.name);
          add.add(
            XFile.fromData(
              f.bytes!,
              name: f.name,
              mimeType: mime,
              length: f.size,
            ),
          );
        }
        setState(() => _spinPicked.addAll(add));
      } else {
        final files = await _picker.pickMultiImage();
        if (files.isEmpty) {
          setState(() => _busyOverlay = false);
          return;
        }
        setState(() => _spinPicked.addAll(files));
      }
    } catch (e) {
      _toast('360° 이미지 선택 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busyOverlay = false);
      }
    }
  }

  // 동영상 선택
  Future<void> _pickVideos() async {
    try {
      setState(() => _busyOverlay = true);

      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: FileType.custom,
          allowedExtensions: ['mp4', 'mov', 'webm'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) {
          setState(() => _busyOverlay = false);
          return;
        }

        final add = <XFile>[];
        for (final f in res.files) {
          final bytes = f.bytes;
          if (bytes == null) continue;
          final mime = _guessVideoMime(f.name);
          add.add(
            XFile.fromData(
              bytes,
              name: f.name,
              mimeType: mime,
              length: f.size,
            ),
          );
        }
        setState(() => _videoFiles.addAll(add));
      } else {
        final picked = await _picker.pickVideo(source: ImageSource.gallery);
        if (picked != null) {
          setState(() => _videoFiles.add(picked));
        }
      }
    } catch (e) {
      _toast('동영상 선택 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _busyOverlay = false);
      }
    }
  }

  // ───────── 공통 시트 UI (지금은 안 쓰이지만 남겨둠: 필요하면 재사용 가능) ─────────

  Widget _sheetTile({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: enabled ? onTap : null,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  ButtonStyle _btnOutline() => OutlinedButton.styleFrom(
    foregroundColor: Colors.black,
    side: const BorderSide(color: Color(0xffe6e6e6)),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero),
  );

  ButtonStyle _btnFill() => ElevatedButton.styleFrom(
    backgroundColor: Colors.black,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero),
    elevation: 0,
  );
}

// ───────── 썸네일 위젯들: X 누를 때 부드럽게 페이드아웃 ─────────

class _MainThumb extends StatefulWidget {
  final XFile file;
  final VoidCallback onRemove;
  const _MainThumb({
    super.key,
    required this.file,
    required this.onRemove,
  });

  @override
  State<_MainThumb> createState() => _MainThumbState();
}

class _MainThumbState extends State<_MainThumb> {
  bool _removing = false;

  void _startRemove() {
    if (_removing) return;
    setState(() => _removing = true);
  }

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (kIsWeb) {
      preview = Image.network(
        widget.file.path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
        const Center(child: Icon(Icons.broken_image, size: 40)),
      );
    } else {
      preview = Image(
        image: ResizeImage(
          FileImage(File(widget.file.path)),
          width: 600,
        ),
        fit: BoxFit.cover,
      );
    }

    final stack = Stack(
      children: [
        Positioned.fill(child: preview),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: _startRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              color: Colors.black.withOpacity(0.55),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );

    return AnimatedOpacity(
      opacity: _removing ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      onEnd: () {
        if (_removing) widget.onRemove();
      },
      child: AnimatedScale(
        scale: _removing ? 0.8 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: stack,
      ),
    );
  }
}

class _SpinThumb extends StatefulWidget {
  final XFile file;
  final VoidCallback onRemove;
  const _SpinThumb({
    super.key,
    required this.file,
    required this.onRemove,
  });

  @override
  State<_SpinThumb> createState() => _SpinThumbState();
}

class _SpinThumbState extends State<_SpinThumb> {
  bool _removing = false;

  void _startRemove() {
    if (_removing) return;
    setState(() => _removing = true);
  }

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (kIsWeb) {
      preview = Image.network(
        widget.file.path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
        const Center(child: Icon(Icons.broken_image, size: 40)),
      );
    } else {
      preview = Image(
        image: ResizeImage(
          FileImage(File(widget.file.path)),
          width: 600,
        ),
        fit: BoxFit.cover,
      );
    }

    final stack = Stack(
      children: [
        Positioned.fill(child: preview),
        const Positioned(
          left: 4,
          top: 4,
          child: Icon(
            Icons.threesixty,
            size: 16,
            color: Colors.white,
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: _startRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              color: Colors.black.withOpacity(0.55),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );

    return AnimatedOpacity(
      opacity: _removing ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      onEnd: () {
        if (_removing) widget.onRemove();
      },
      child: AnimatedScale(
        scale: _removing ? 0.8 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: stack,
      ),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final XFile file;
  final Future<Uint8List> Function(XFile) loadThumb;
  final VoidCallback onRemove;

  const _VideoThumb({
    super.key,
    required this.file,
    required this.loadThumb,
    required this.onRemove,
  });

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  bool _removing = false;

  void _startRemove() {
    if (_removing) return;
    setState(() => _removing = true);
  }

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (kIsWeb) {
      // 웹: 썸네일 이미지 대신 아이콘
      preview = const Center(
        child: Icon(Icons.play_circle_fill, size: 40, color: Colors.white),
      );
    } else {
      preview = FutureBuilder<Uint8List>(
        future: widget.loadThumb(widget.file),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          // 실제로는 이미지 프레임이 아니라 파일 바이트지만, 간단히 미리보기 느낌만 사용
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                snap.data!,
                fit: BoxFit.cover,
              ),
              Container(
                color: Colors.black.withOpacity(0.35),
              ),
              const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ],
          );
        },
      );
    }

    final stack = Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black,
            child: preview,
          ),
        ),
        Positioned(
          left: 4,
          top: 4,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            color: Colors.black.withOpacity(0.7),
            child: const Text(
              'VIDEO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: _startRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              color: Colors.black.withOpacity(0.55),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );

    return AnimatedOpacity(
      opacity: _removing ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      onEnd: () {
        if (_removing) widget.onRemove();
      },
      child: AnimatedScale(
        scale: _removing ? 0.8 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: stack,
      ),
    );
  }
}

// ───────── 재사용 타입/위젯 ─────────

class _Cat {
  final String kor;
  final String code;
  const _Cat(this.kor, this.code);
}

class _ReorderableThumbGrid extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) builder;
  final void Function(int from, int to) onReorder;
  final ScrollController? scrollController;

  const _ReorderableThumbGrid({
    super.key,
    required this.itemCount,
    required this.builder,
    required this.onReorder,
    this.scrollController,
  });

  @override
  State<_ReorderableThumbGrid> createState() =>
      _ReorderableThumbGridState();
}

class _ReorderableThumbGridState extends State<_ReorderableThumbGrid> {
  int? _draggingIndex;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: widget.scrollController,
      shrinkWrap: true,
      physics: widget.scrollController == null
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      itemCount: widget.itemCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (ctx, index) {
        return LongPressDraggable<int>(
          data: index,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: 110,
              height: 110,
              child: widget.builder(ctx, index),
            ),
          ),
          onDragStarted: () {
            setState(() {
              _draggingIndex = index;
            });
          },
          onDraggableCanceled: (_, __) {
            setState(() {
              _draggingIndex = null;
            });
          },
          onDragEnd: (_) {
            setState(() {
              _draggingIndex = null;
            });
          },
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: widget.builder(ctx, index),
          ),
          child: DragTarget<int>(
            onWillAccept: (from) => from != index,
            onAccept: (from) {
              widget.onReorder(from, index);
            },
            builder: (context, cand, rej) {
              final isTarget =
                  cand.isNotEmpty && _draggingIndex != index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  border: isTarget
                      ? Border.all(
                    color: Colors.black87,
                    width: 2,
                  )
                      : null,
                ),
                child: widget.builder(context, index),
              );
            },
          ),
        );
      },
    );
  }
}
