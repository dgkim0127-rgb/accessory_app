// lib/admin/admin_manage_page.dart  ✅ 최종 (브랜드 · 카테고리 관리)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminManagePage extends StatefulWidget {
  const AdminManagePage({super.key});

  @override
  State<AdminManagePage> createState() => _AdminManagePageState();
}

class _AdminManagePageState extends State<AdminManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('관리 (브랜드 · 카테고리)'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: TabBar(
              controller: _tab,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black54,
              indicatorColor: Colors.black,
              tabs: const [
                Tab(text: '브랜드'),
                Tab(text: '카테고리'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _BrandsAdmin(),
                _CategoriesAdmin(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ----------------------- 브랜드 관리 -----------------------
class _BrandsAdmin extends StatelessWidget {
  const _BrandsAdmin();

  Future<void> _openEditor(BuildContext context,
      {String? docId, Map<String, dynamic>? data}) async {
    final korC = TextEditingController(text: data?['nameKor'] ?? '');
    final engC = TextEditingController(text: data?['nameEng'] ?? '');
    final logoC = TextEditingController(text: data?['logoUrl'] ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(docId == null ? '브랜드 추가' : '브랜드 수정'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: korC,
                decoration: const InputDecoration(labelText: '한글명 (필수)'),
              ),
              TextField(
                controller: engC,
                decoration: const InputDecoration(labelText: '영문명 (선택)'),
              ),
              TextField(
                controller: logoC,
                decoration: const InputDecoration(
                    labelText: '로고 URL (선택, https://)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );

    if (saved != true) return;

    final kor = korC.text.trim();
    final eng = engC.text.trim();
    final logo = logoC.text.trim();

    if (kor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('브랜드 한글명을 입력하세요.')),
      );
      return;
    }

    final col = FirebaseFirestore.instance.collection('brands');

    if (docId == null) {
      await col.add({
        'nameKor': kor,
        'nameEng': eng,
        'logoUrl': logo,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await col.doc(docId).update({
        'nameKor': kor,
        'nameEng': eng,
        'logoUrl': logo,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _delete(BuildContext context, String docId, String nameKor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('브랜드 "$nameKor" 을(를) 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('brands').doc(docId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    final brands = FirebaseFirestore.instance
        .collection('brands')
        .orderBy('nameKor')
        .snapshots();

    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('브랜드 추가'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: brands,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.5));
              }
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return const Center(child: Text('등록된 브랜드가 없습니다.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data();
                  final kor = (m['nameKor'] ?? '').toString();
                  final eng = (m['nameEng'] ?? '').toString();
                  final logo = (m['logoUrl'] ?? '').toString();

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF4F4F4),
                        backgroundImage:
                        logo.isNotEmpty ? NetworkImage(logo) : null,
                        child: logo.isEmpty
                            ? const Icon(Icons.storefront_outlined)
                            : null,
                      ),
                      title: Text(
                        kor,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: eng.isNotEmpty ? Text(eng) : null,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '수정',
                            onPressed: () =>
                                _openEditor(context, docId: d.id, data: m),
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: '삭제',
                            onPressed: () => _delete(context, d.id, kor),
                            icon:
                            const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ----------------------- 카테고리 관리 -----------------------
/// categories 컬렉션: { code: 'ring', label: '반지', order: 10 }
class _CategoriesAdmin extends StatelessWidget {
  const _CategoriesAdmin();

  Future<void> _openEditor(BuildContext context,
      {String? docId, Map<String, dynamic>? data}) async {
    final codeC = TextEditingController(text: data?['code'] ?? '');
    final labelC = TextEditingController(text: data?['label'] ?? '');
    final orderC =
    TextEditingController(text: (data?['order'] ?? 100).toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(docId == null ? '카테고리 추가' : '카테고리 수정'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: labelC,
                decoration:
                const InputDecoration(labelText: '표시 이름 (예: 반지)'),
              ),
              TextField(
                controller: codeC,
                decoration:
                const InputDecoration(labelText: '코드 (예: ring)'),
              ),
              TextField(
                controller: orderC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '정렬(숫자, 작을수록 위)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장')),
        ],
      ),
    );

    if (saved != true) return;

    final code = codeC.text.trim();
    final label = labelC.text.trim();
    final order = int.tryParse(orderC.text.trim());

    if (code.isEmpty || label.isEmpty || order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('코드/이름/정렬을 올바르게 입력하세요.')),
      );
      return;
    }

    final col = FirebaseFirestore.instance.collection('categories');

    if (docId == null) {
      await col.add({
        'code': code,
        'label': label,
        'order': order,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await col.doc(docId).update({
        'code': code,
        'label': label,
        'order': order,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _delete(
      BuildContext context, String docId, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('카테고리 "$label" 을(를) 삭제할까요?\n'
            '※ 이 카테고리를 사용 중인 게시물은 필드만 남습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('categories')
          .doc(docId)
          .delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    final cats = FirebaseFirestore.instance
        .collection('categories')
        .orderBy('order')
        .snapshots();

    return Column(
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _openEditor(context),
                icon: const Icon(Icons.add),
                label: const Text('카테고리 추가'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: cats,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.5));
              }
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return const Center(child: Text('등록된 카테고리가 없습니다.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data();
                  final label = (m['label'] ?? '').toString();
                  final code = (m['code'] ?? '').toString();
                  final order = (m['order'] ?? 0) as int? ?? 0;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: line),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF0F0F0),
                        child: Text(
                          order.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      title: Text(
                        label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700),
                      ),
                      subtitle:
                      Text(code, style: const TextStyle(color: Colors.black54)),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '수정',
                            onPressed: () =>
                                _openEditor(context, docId: d.id, data: m),
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: '삭제',
                            onPressed: () => _delete(context, d.id, label),
                            icon:
                            const Icon(Icons.delete, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
