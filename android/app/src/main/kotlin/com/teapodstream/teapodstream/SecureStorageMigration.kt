package com.teapodstream.teapodstream

import android.content.Context

/**
 * Whether flutter_secure_storage (10.x) still has data of its v9 (EncryptedSharedPreferences) to move. The plugin moves
 * it key by key and sets its "migrated" flag only after the last one; a migration that failed midway reads from the
 * old store for that session, where the keys already moved are missing — Dart must not take them as empty then
 * (`ProfileNotifier`). The next launch resumes the migration. Reads the plugin's files, never writes them.
 */
internal object SecureStorageMigration {
    private const val DATA_PREFS = "FlutterSecureStorage"
    private const val CONFIG_PREFS = "FlutterSecureStorageConfiguration:$DATA_PREFS"
    private const val LEGACY_CONFIG_PREFS = "FlutterSecureStorageConfiguration"
    private const val MIGRATED = "ENCRYPTED_PREFERENCES_MIGRATED"
    private const val KEY_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    private const val MARKER_PREFIX = "FlutterSecureSAlgorithm"
    private const val ESP_KEYSET_PREFIX = "__androidx_security_crypto_encrypted_prefs_"

    fun pending(context: Context): Boolean {
        val config = context.getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
        val migrated = if (config.contains(MIGRATED)) {
            config.getBoolean(MIGRATED, false)
        } else {
            context.getSharedPreferences(LEGACY_CONFIG_PREFS, Context.MODE_PRIVATE).getBoolean(MIGRATED, false)
        }
        return isPending(migrated, context.getSharedPreferences(DATA_PREFS, Context.MODE_PRIVATE).all.keys)
    }

    /**
     * [dataKeys] — the raw keys of the plugin's data file, which v9 and v10 share: v10 entries carry the plugin's
     * prefix in clear, v9 entries have encrypted names; besides them only v9's keysets and the plugin's old markers.
     */
    fun isPending(migrated: Boolean, dataKeys: Collection<String>): Boolean =
        !migrated && dataKeys.any {
            !it.startsWith(KEY_PREFIX) && !it.startsWith(MARKER_PREFIX) && !it.startsWith(ESP_KEYSET_PREFIX)
        }
}
