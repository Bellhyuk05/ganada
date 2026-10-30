import 'package:firebase_core/firebase_core.dart';

class AppConfig {
  static const mode = String.fromEnvironment(
    'APP_DATA_MODE',
    defaultValue: 'supabase',
  );
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zvuqhfmjqbqcqseqmeht.supabase.co',
  );
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_50KrstaGmNQEyVcvtcSGyg_JPRBUud_',
  );
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static bool get isLive => mode == 'supabase';
  static bool get firebaseConfigured => [
    firebaseApiKey,
    firebaseAppId,
    firebaseSenderId,
    firebaseProjectId,
  ].every((value) => value.isNotEmpty);
  static FirebaseOptions get firebaseOptions => FirebaseOptions(
    apiKey: firebaseApiKey,
    appId: firebaseAppId,
    messagingSenderId: firebaseSenderId,
    projectId: firebaseProjectId,
  );
}