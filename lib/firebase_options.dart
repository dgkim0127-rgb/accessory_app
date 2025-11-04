// lib/firebase_options.dart  ✅ 최종
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get web => const FirebaseOptions(
    apiKey: "AIzaSyDR0Gq3HwrAfHFfQo8ngrLFNo7YBSLpw5U",
    authDomain: "djvmf-ce8e6.firebaseapp.com",
    projectId: "djvmf-ce8e6",
    // ✅ 신형 포맷 버킷 (정상)
    storageBucket: "djvmf-ce8e6.appspot.com",
    messagingSenderId: "1028791528109",
    appId: "1:1028791528109:web:709dc56fec1446e5bef424",
    measurementId: "G-6VQSNE9DQN",
  );
}
