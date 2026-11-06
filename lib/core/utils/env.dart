import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'SENTRY_DNS', obfuscate: true)
  static final String sentryDns = _Env.sentryDns;
  @EnviedField(varName: 'SUPABASE_PROJECT_URL', obfuscate: true)
  static final String supabaseProjectUrl = _Env.supabaseProjectUrl;
  @EnviedField(varName: 'SUPABASE_PROJECT_ANON_KEY', obfuscate: true)
  static final String supabaseProjectAnonKey = _Env.supabaseProjectAnonKey;

  // Our own Supabase project: accounts and families
  // (docs/WEB_ARCHITECTURE.md). Optional — a build without it has no
  // account features and works fully offline, as before.
  @EnviedField(varName: 'ACCOUNT_SUPABASE_URL', obfuscate: true, optional: true)
  static final String? accountSupabaseUrl = _Env.accountSupabaseUrl;
  @EnviedField(
    varName: 'ACCOUNT_SUPABASE_PUBLISHABLE_KEY',
    obfuscate: true,
    optional: true,
  )
  static final String? accountSupabasePublishableKey =
      _Env.accountSupabasePublishableKey;
}
