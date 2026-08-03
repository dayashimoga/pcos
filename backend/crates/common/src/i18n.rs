//! Localization (i18n) module.
//!
//! Provides multi-language string resolution for API error messages,
//! email templates, and notification text.

use std::collections::HashMap;
use std::sync::Arc;

/// Supported locales.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Locale {
    En, // English (default)
    Es, // Spanish
    Fr, // French
    De, // German
    Ja, // Japanese
    Zh, // Chinese (Simplified)
    Ko, // Korean
    Pt, // Portuguese
    Hi, // Hindi
    Ar, // Arabic
}

impl Locale {
    pub fn from_str(s: &str) -> Self {
        match s.split('-').next().unwrap_or("en").to_lowercase().as_str() {
            "es" => Locale::Es,
            "fr" => Locale::Fr,
            "de" => Locale::De,
            "ja" => Locale::Ja,
            "zh" => Locale::Zh,
            "ko" => Locale::Ko,
            "pt" => Locale::Pt,
            "hi" => Locale::Hi,
            "ar" => Locale::Ar,
            _ => Locale::En,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Locale::En => "en", Locale::Es => "es", Locale::Fr => "fr",
            Locale::De => "de", Locale::Ja => "ja", Locale::Zh => "zh",
            Locale::Ko => "ko", Locale::Pt => "pt", Locale::Hi => "hi",
            Locale::Ar => "ar",
        }
    }
}

/// Translation catalog.
#[derive(Clone)]
pub struct I18n {
    translations: Arc<HashMap<Locale, HashMap<String, String>>>,
    default_locale: Locale,
}

impl I18n {
    pub fn new() -> Self {
        let mut translations = HashMap::new();

        // English (default)
        let mut en = HashMap::new();
        en.insert("auth.login_success".into(), "Login successful".into());
        en.insert("auth.invalid_credentials".into(), "Invalid email or password".into());
        en.insert("auth.token_expired".into(), "Session expired, please login again".into());
        en.insert("auth.mfa_required".into(), "Multi-factor authentication required".into());
        en.insert("file.upload_success".into(), "File uploaded successfully".into());
        en.insert("file.not_found".into(), "File not found".into());
        en.insert("file.quota_exceeded".into(), "Storage quota exceeded".into());
        en.insert("share.created".into(), "Share link created".into());
        en.insert("share.expired".into(), "This share link has expired".into());
        en.insert("backup.created".into(), "Backup created successfully".into());
        en.insert("backup.restored".into(), "Backup restored successfully".into());
        en.insert("notification.none".into(), "No new notifications".into());
        en.insert("error.internal".into(), "An internal error occurred".into());
        en.insert("error.forbidden".into(), "You don't have permission".into());
        en.insert("error.not_found".into(), "Resource not found".into());
        en.insert("error.validation".into(), "Invalid input".into());
        translations.insert(Locale::En, en);

        // Spanish
        let mut es = HashMap::new();
        es.insert("auth.login_success".into(), "Inicio de sesión exitoso".into());
        es.insert("auth.invalid_credentials".into(), "Email o contraseña incorrectos".into());
        es.insert("file.upload_success".into(), "Archivo subido correctamente".into());
        es.insert("file.not_found".into(), "Archivo no encontrado".into());
        es.insert("file.quota_exceeded".into(), "Cuota de almacenamiento excedida".into());
        es.insert("error.internal".into(), "Ocurrió un error interno".into());
        es.insert("error.forbidden".into(), "No tienes permiso".into());
        translations.insert(Locale::Es, es);

        // Hindi
        let mut hi = HashMap::new();
        hi.insert("auth.login_success".into(), "लॉगिन सफल".into());
        hi.insert("auth.invalid_credentials".into(), "अमान्य ईमेल या पासवर्ड".into());
        hi.insert("file.upload_success".into(), "फ़ाइल सफलतापूर्वक अपलोड हुई".into());
        hi.insert("error.internal".into(), "एक आंतरिक त्रुटि हुई".into());
        translations.insert(Locale::Hi, hi);

        Self {
            translations: Arc::new(translations),
            default_locale: Locale::En,
        }
    }

    /// Get a translated string. Falls back to English if key not found in locale.
    pub fn t(&self, locale: Locale, key: &str) -> String {
        // Try requested locale first
        if let Some(catalog) = self.translations.get(&locale) {
            if let Some(val) = catalog.get(key) {
                return val.clone();
            }
        }
        // Fallback to default locale
        if let Some(catalog) = self.translations.get(&self.default_locale) {
            if let Some(val) = catalog.get(key) {
                return val.clone();
            }
        }
        // Key not found — return key itself
        key.to_string()
    }

    /// Get locale from Accept-Language header.
    pub fn from_header(header: Option<&str>) -> Locale {
        match header {
            Some(h) => Locale::from_str(h),
            None => Locale::En,
        }
    }
}

impl Default for I18n {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_english_translation() {
        let i18n = I18n::new();
        assert_eq!(i18n.t(Locale::En, "auth.login_success"), "Login successful");
    }

    #[test]
    fn test_spanish_translation() {
        let i18n = I18n::new();
        assert_eq!(i18n.t(Locale::Es, "auth.login_success"), "Inicio de sesión exitoso");
    }

    #[test]
    fn test_fallback_to_english() {
        let i18n = I18n::new();
        // Spanish doesn't have this key, should fallback to English
        assert_eq!(i18n.t(Locale::Es, "backup.created"), "Backup created successfully");
    }

    #[test]
    fn test_hindi_translation() {
        let i18n = I18n::new();
        assert_eq!(i18n.t(Locale::Hi, "auth.login_success"), "लॉगिन सफल");
    }

    #[test]
    fn test_locale_from_header() {
        assert_eq!(I18n::from_header(Some("es-MX")), Locale::Es);
        assert_eq!(I18n::from_header(Some("hi-IN")), Locale::Hi);
        assert_eq!(I18n::from_header(None), Locale::En);
    }
}
