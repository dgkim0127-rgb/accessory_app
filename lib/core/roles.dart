// lib/core/roles.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _auth = FirebaseAuth.instance;
final _db = FirebaseFirestore.instance;

/// 현재 로그인 사용자의 역할을 스트림으로 제공 ("admin" / "user" / null)
Stream<String?> roleStream() {
  return _auth.authStateChanges().asyncExpand((user) async* {
    if (user == null) {
      yield null;
      return;
    }
    final snap = await _db.collection('users').doc(user.uid).get();
    final role = (snap.data()?['role'] as String?)?.toLowerCase();
    yield role;
  });
}

/// 지금 사용자가 관리자면 true
Future<bool> isAdmin() async {
  final user = _auth.currentUser;
  if (user == null) return false;
  final snap = await _db.collection('users').doc(user.uid).get();
  final role = (snap.data()?['role'] as String?)?.toLowerCase();
  return role == 'admin';
}
