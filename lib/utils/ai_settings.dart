import 'package:shared_preferences/shared_preferences.dart';

class AiSettingsData {
  AiSettingsData({
    required this.enabled,
    required this.apiKey,
    required this.model,
  });

  final bool enabled;
  final String apiKey;
  final String model;
}

class AiSettings {
  static const _prefsEnabled = 'ai_enabled';
  static const _prefsApiKey = 'ai_api_key';
  static const _prefsModel = 'ai_model';

  // Fallbacks configurables desde build/run:
  // flutter run --dart-define=OPENAI_API_KEY=... --dart-define=OPENAI_MODEL=gpt-4o-mini
  static const String _envApiKey = String.fromEnvironment('OPENAI_API_KEY');
  static const String _envModel = String.fromEnvironment(
    'OPENAI_MODEL',
    defaultValue: 'gpt-4o-mini',
  );

  static bool get hasEnvApiKey => _envApiKey.trim().isNotEmpty;

  static Future<AiSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(_prefsEnabled) ?? true;
    final apiKey = (prefs.getString(_prefsApiKey) ?? '').trim();
    final model = (prefs.getString(_prefsModel) ?? _envModel).trim();

    return AiSettingsData(
      enabled: enabled,
      apiKey: apiKey,
      model: model.isEmpty ? _envModel : model,
    );
  }

  static Future<void> save(AiSettingsData data) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_prefsEnabled, data.enabled);
    await prefs.setString(_prefsApiKey, data.apiKey.trim());
    await prefs.setString(
      _prefsModel,
      (data.model.trim().isEmpty ? _envModel : data.model.trim()),
    );
  }

  static String effectiveApiKey(AiSettingsData data) {
    if (!data.enabled) return '';
    if (data.apiKey.trim().isNotEmpty) return data.apiKey.trim();
    return _envApiKey.trim();
  }

  static String effectiveModel(AiSettingsData data) {
    final m = data.model.trim();
    return m.isEmpty ? _envModel : m;
  }
}
