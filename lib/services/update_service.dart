// lib/services/update_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  bool _dialogShowing = false;

  Future<void> checkAndHandle(BuildContext context) async {
    if (_dialogShowing) return;
    if (kIsWeb) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final rc = FirebaseRemoteConfig.instance;

      // ✅ 기본값(콘솔 값 못 받아도 앱이 죽지 않게)
      await rc.setDefaults(<String, dynamic>{
        'minBuild': '0',
        'recommendedBuild': '0',
        'forceUpdate': 'false',
        'androidStoreUrl': '',
      });

      // ✅ fetch + activate
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 7),
        minimumFetchInterval: const Duration(minutes: 5),
      ));
      await rc.fetchAndActivate();

      int _rcInt(String key) => int.tryParse(rc.getString(key).trim()) ?? 0;
      bool _rcBool(String key) =>
          rc.getString(key).trim().toLowerCase() == 'true';

      final minBuild = _rcInt('minBuild');
      final recommendedBuild = _rcInt('recommendedBuild');
      final forceUpdate = _rcBool('forceUpdate');
      final storeUrl = rc.getString('androidStoreUrl').trim();

      final mustUpdate = forceUpdate && currentBuild < minBuild;
      final shouldUpdate = currentBuild < recommendedBuild;

      if (mustUpdate) {
        final ok = await _tryImmediateUpdate();
        if (!ok) {
          await _showForceDialog(context, storeUrl);
        }
        return;
      }

      if (shouldUpdate && recommendedBuild > 0) {
        await _showRecommendDialog(context, storeUrl);
      }
    } catch (_) {
      // 네트워크/RC 오류여도 앱은 계속 실행
    }
  }

  Future<bool> _tryImmediateUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openStore(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showForceDialog(BuildContext context, String storeUrl) async {
    _dialogShowing = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('업데이트가 필요합니다'),
            content: const Text('최신 버전으로 업데이트 후 이용해 주세요.'),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  await _openStore(storeUrl);
                },
                child: const Text('업데이트'),
              ),
            ],
          ),
        );
      },
    );

    _dialogShowing = false;
  }

  Future<void> _showRecommendDialog(BuildContext context, String storeUrl) async {
    if (_dialogShowing) return;
    _dialogShowing = true;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('업데이트가 있습니다'),
        content: const Text('더 안정적인 사용을 위해 업데이트를 권장합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('나중에'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('업데이트'),
          ),
        ],
      ),
    );

    _dialogShowing = false;

    if (ok == true) {
      await _openStore(storeUrl);
    }
  }
}