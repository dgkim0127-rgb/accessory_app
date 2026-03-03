import 'package:cloud_firestore/cloud_firestore.dart';

class UpdatePolicyBootstrap {
  static Future<void> ensureExists() async {
    final ref = FirebaseFirestore.instance.collection('system').doc('app');
    final doc = await ref.get();
    if (doc.exists) return;

    // ✅ 최초 1회만 자동 생성 (원하는 기본값 넣기)
    await ref.set({
      'minBuild': 0,
      'recommendedBuild': 0,
      'forceUpdate': false,
      'androidStoreUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}