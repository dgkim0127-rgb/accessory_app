import 'package:cloud_firestore/cloud_firestore.dart';

class PostRepo {
  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('posts');

  /// 홈(전체) 목록: 임시 포함 여부 선택
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchAll({
    bool includeTemp = false,
  }) {
    Query<Map<String, dynamic>> q = _col.orderBy('createdAt', descending: true);
    if (!includeTemp) {
      q = q.where('isTemp', isEqualTo: false);
    }
    return q.snapshots();
  }

  /// 브랜드/카테고리 목록: 임시 포함 여부 선택
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchByBrandCategory({
    required String brandId,
    required String categoryId,
    bool includeTemp = false,
  }) {
    Query<Map<String, dynamic>> q = _col
        .where('brandId', isEqualTo: brandId)
        .where('categoryId', isEqualTo: categoryId)
        .orderBy('createdAt', descending: true);

    if (!includeTemp) {
      q = q.where('isTemp', isEqualTo: false);
    }
    return q.snapshots();
  }
}
