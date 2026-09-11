class VorynSupabaseConfig {
  const VorynSupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  factory VorynSupabaseConfig.fromEnvironment() {
    return const VorynSupabaseConfig(
      url: String.fromEnvironment(
        'VORYN_SUPABASE_URL',
        defaultValue: 'https://nrkaqtrsrfozqyzqbwth.supabase.co',
      ),
      anonKey: String.fromEnvironment(
        'VORYN_SUPABASE_ANON_KEY',
        defaultValue: 'sb_publishable_Mgur545sWhH6KdsaGJg83g_RiFsmpTv',
      ),
    );
  }
}
