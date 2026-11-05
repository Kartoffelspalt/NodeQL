// Shared by the release tools and the app. Unknown locales display their tag.
const translationNativeNames = <String, String>{
  'ar': 'العربية',
  'cs': 'Čeština',
  'da': 'Dansk',
  'de': 'Deutsch',
  'el': 'Ελληνικά',
  'en': 'English',
  'es': 'Español',
  'fa': 'فارسی',
  'fi': 'Suomi',
  'fr': 'Français',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'hu': 'Magyar',
  'id': 'Bahasa Indonesia',
  'it': 'Italiano',
  'ja': '日本語',
  'ko': '한국어',
  'nl': 'Nederlands',
  'no': 'Norsk',
  'pl': 'Polski',
  'pt': 'Português',
  'ro': 'Română',
  'ru': 'Русский',
  'sv': 'Svenska',
  'th': 'ไทย',
  'tr': 'Türkçe',
  'uk': 'Українська',
  'ur': 'اردو',
  'vi': 'Tiếng Việt',
  'zh': '中文',
};

String translationNativeName(String locale) {
  final language = locale.split('-').first;
  final name = translationNativeNames[language];
  if (name == null) return locale;
  return locale == language ? name : '$name ($locale)';
}

bool isRtlTranslation(String locale) => const {
  'ar',
  'fa',
  'he',
  'ur',
  'ps',
  'sd',
  'ug',
  'yi',
}.contains(locale.split('-').first);
