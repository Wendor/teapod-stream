package com.teapodstream.teapodstream

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.StringRes
import java.util.Locale

/**
 * String in the app language picked in Flutter (`flutter.app_locale`, written by
 * LocaleNotifier); without a choice — the system locale. Read on every call, so
 * a language switch shows up on the next notification/tile update.
 */
fun Context.appString(@StringRes id: Int): String {
    val tag = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getString("flutter.app_locale", null)
    if (tag.isNullOrEmpty()) return getString(id)
    val config = Configuration(resources.configuration).apply { setLocale(Locale.forLanguageTag(tag)) }
    return createConfigurationContext(config).getString(id)
}
