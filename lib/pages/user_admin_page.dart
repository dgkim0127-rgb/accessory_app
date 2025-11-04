import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserAdminPage extends StatelessWidget {
  const UserAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final usersRef = FirebaseFirestore.instance.collection('users');

    return Scaffold(
      appBar: AppBar(title: const Text('유저 관리'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('사용자가 없습니다.'));

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = docs[i].data();
              final uid = docs[i].id;
              final email = (m['email'] ?? '').toString();
              final role = (m['role'] ?? 'user').toString();

              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(email),
                subtitle: Text('역할: $role'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    await usersRef.doc(uid).update({'role': v});
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'user', child: Text('user')),
                    PopupMenuItem(value: 'admin', child: Text('admin')),
                    PopupMenuItem(value: 'super', child: Text('super')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
