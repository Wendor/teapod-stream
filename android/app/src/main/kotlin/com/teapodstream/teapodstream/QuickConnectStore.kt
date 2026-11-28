package com.teapodstream.teapodstream

import com.teapodstream.teapodstream.core.CoreKind
import java.io.File
import org.json.JSONObject

/**
 * A session start: the core config, its parameters and the SOCKS login; [attempt] — the Flutter connect it answers
 * (0 — a native start), [reconnect] — a native restart; [configName] — what the tile shows for it (a quick start's is
 * the stored one, read with its config).
 */
internal data class StartRequest(
    val config: String,
    val params: ConnectionParams,
    val socksUser: String,
    val socksPassword: String,
    val attempt: Long,
    val reconnect: Boolean,
    val configName: String? = null,
) {
    override fun toString() = "StartRequest(engine=${params.engine.id}, attempt=$attempt, reconnect=$reconnect)"
}

/**
 * The quick-reconnect data in [dir] (the app's private files): the last core config (with the SOCKS login in it, the
 * only stored copy), its [ConnectionParams], the config name the tile shows and the "turned off by the user" flag. The
 * config and its params are replaced and read together under one lock shared by every instance (the activity and the service write them), so
 * a quick start never pairs one session's config with another's params. The tile, boot, the notification, a system restart and
 * `reconnectInternal` start from it without Flutter. The only reader and writer of these files; every write goes
 * through a temp file and a rename, so a reader never sees half a file.
 *
 * The config, its params and the tile name are encrypted by [cipher] ([KeystoreCipher] in the app): `MAGIC`, then the
 * cipher's output, the file name as associated data. A file that doesn't decrypt (a lost key, a swapped or corrupt
 * file) reads as missing and is removed — the next connect from the app saves a new one. A plain file of an older
 * version is read once and stored encrypted; if that write fails it stays plain and is retried on the next read.
 */
internal class QuickConnectStore(private val dir: File, private val cipher: StoreCipher) {

    fun config(): String? = synchronized(LOCK) { read(CONFIG) }

    /** The config the session runs (with the prefix proxy injected, if any); only with its params ([save]). */
    private fun saveConfig(config: String) = write(CONFIG, config)

    fun params(): ConnectionParams? = try {
        synchronized(LOCK) { read(PARAMS) }?.let { ConnectionParams.fromJson(JSONObject(it)) }
    } catch (_: Exception) {
        null
    }

    fun saveParams(params: ConnectionParams) = synchronized(LOCK) { write(PARAMS, params.toJson().toString()) }

    /** The name of the config a quick start connects (the tile shows it); null — none. */
    fun tileName(): String? = synchronized(LOCK) { read(TILE_NAME) }

    /** A blank or null [name] removes it. */
    fun saveTileName(name: String?) = synchronized(LOCK) {
        if (name.isNullOrBlank()) File(dir, TILE_NAME).delete() else write(TILE_NAME, name)
    }

    /**
     * A name kept before this store: taken only for a stored config without a name of its own. A failed write only
     * costs the label (the caller drops the old name either way, so it can't attach to a config saved later).
     */
    fun adoptLegacyTileName(legacy: String?) = synchronized(LOCK) {
        if (legacy.isNullOrBlank() || tileName() != null || config() == null) return@synchronized
        try {
            saveTileName(legacy)
        } catch (_: Exception) {
        }
    }

    /**
     * Flutter's `saveQuickConnect` and every session start: the config (which carries its SOCKS login) and its params
     * as one replacement. The old config goes first, so an interrupted replacement leaves no config (nothing to
     * quick-start) or the new one, never a config paired with another one's params. [tileName] — the name the tile shows
     * for it, replaced in the same step (blank removes it; null keeps the stored one, as a reconnect does); a failed
     * name write only costs the label.
     */
    fun save(config: String, params: ConnectionParams, tileName: String? = null) = synchronized(LOCK) {
        // The login file of older versions: nothing reads it, the config holds the login.
        File(dir, LEGACY_CREDENTIALS).delete()
        val old = File(dir, CONFIG)
        if (!old.delete() && old.exists()) throw java.io.IOException("can't remove $CONFIG")
        // The old name goes with the old config: an interrupted save leaves no label for a config it didn't store.
        if (tileName != null) File(dir, TILE_NAME).delete()
        saveParams(params)
        saveConfig(config)
        try {
            if (tileName != null) saveTileName(tileName)
        } catch (_: Exception) {
        }
    }

    /** [block] under the lock of every read and write: a check and the write it allows, as one step. */
    fun <T> locked(block: () -> T): T = synchronized(LOCK, block)

    /** Flutter's `clearQuickConnect`: nothing left to quick-start. The off flag stays. */
    fun clear() = synchronized(LOCK) {
        for (name in listOf(CONFIG, PARAMS, LEGACY_CREDENTIALS, TILE_NAME)) File(dir, name).delete()
    }

    /** The user turned the VPN off: boot and a system restart don't start it again. Survives a process restart. */
    fun userOff(): Boolean = File(dir, USER_OFF).exists()

    fun setUserOff(off: Boolean) {
        val flag = File(dir, USER_OFF)
        if (off) flag.createNewFile() else flag.delete()
    }

    /**
     * The quick start from what is stored, or null without a config or parameters. The SOCKS login is the config's own
     * ([socksFromConfig] reads it in the format of the session's core).
     */
    fun quickStart(socksFromConfig: (config: String, engine: CoreKind) -> Pair<String, String>): StartRequest? {
        val stored = synchronized(LOCK) {
            val params = params() ?: return null
            val config = config() ?: return null
            StartRequest(config, params, "", "", attempt = 0, reconnect = true, configName = tileName())
        }
        val (user, password) = socksFromConfig(stored.config, stored.params.engine)
        return stored.copy(socksUser = user, socksPassword = password)
    }

    /** Null when missing, unreadable or undecryptable (also removed between the check and the read). Under [LOCK]. */
    private fun read(name: String): String? {
        val file = File(dir, name)
        val bytes = try {
            file.takeIf { it.exists() }?.readBytes()
        } catch (_: java.io.IOException) {
            null
        } ?: return null
        if (!bytes.startsWith(MAGIC)) {
            // Plain, from an older version: stored encrypted from now on (a failed write keeps it for the next read).
            val text = String(bytes, Charsets.UTF_8)
            try {
                write(name, text)
            } catch (_: Exception) {
            }
            return text
        }
        return try {
            String(cipher.decrypt(bytes.copyOfRange(MAGIC.size, bytes.size), name.toByteArray()), Charsets.UTF_8)
        } catch (_: Exception) {
            file.delete()
            null
        }
    }

    private fun write(name: String, text: String) {
        val data = MAGIC + cipher.encrypt(text.toByteArray(Charsets.UTF_8), name.toByteArray())
        // A temp file of its own per write: the activity and the service may write the same file at once.
        val tmp = File.createTempFile("$name.", ".tmp", dir)
        try {
            tmp.writeBytes(data)
            if (!tmp.renameTo(File(dir, name))) throw java.io.IOException("rename failed: $name")
        } finally {
            tmp.delete() // after a rename there is nothing under the temp name
        }
    }

    private fun ByteArray.startsWith(prefix: ByteArray) =
        size >= prefix.size && prefix.indices.all { this[it] == prefix[it] }

    companion object {
        private val LOCK = Any()
        /** Marks an encrypted file; a plain one starts with `{` (JSON) or a name. */
        private val MAGIC = byteArrayOf(0, 'T'.code.toByte(), 'Q'.code.toByte(), 1)
        const val CONFIG = "xray_config.json"
        const val PARAMS = "last_connection_meta.json"
        /** Older versions kept the login here too; removed by [save] and [clear]. */
        const val LEGACY_CREDENTIALS = "socks_creds.json"
        const val USER_OFF = "user_disconnected.flag"
        const val TILE_NAME = "tile_config_name.txt"
    }
}
