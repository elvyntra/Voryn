import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VorynStartupPermissions {
  VorynStartupPermissions._();

  static const _completedKey = 'voryn.permissions.setup.completed';
  static const _permissions = <Permission>[
    Permission.notification,
    Permission.contacts,
    Permission.microphone,
    Permission.camera,
  ];

  /// Presents Android's native permission dialogs once, immediately after splash.
  static Future<void> requestAfterSplash() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_completedKey) ?? false) return;

    for (final permission in _permissions) {
      final status = await permission.status;
      if (!status.isGranted && !status.isLimited) {
        await permission.request();
      }
    }

    await preferences.setBool(_completedKey, true);
  }
}
