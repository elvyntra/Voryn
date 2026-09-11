import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class VorynBackend {
  VorynBackend._();

  static SupabaseClient? get client {
    try {
      if (!Supabase.instance.isInitialized) return null;
      return Supabase.instance.client;
    } on AssertionError {
      return null;
    }
  }

  static Future<bool> initialize({VorynSupabaseConfig? config}) async {
    final resolved = config ?? VorynSupabaseConfig.fromEnvironment();
    if (!resolved.isConfigured) return false;

    if (client == null) {
      await Supabase.initialize(
        url: resolved.url,
        publishableKey: resolved.anonKey,
      );
    }
    return true;
  }

  static bool get isConfigured => client != null;
}
