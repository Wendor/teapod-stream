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
 * The quick-reconnect data in [dir] (the app's private files): the last core config, its [ConnectionParams], the
 * SOCKS login, the config name the tile shows and the "turned off by the user" flag. The config and its login are
 * (with the params) replaced and read together under one lock shared by every instance (the activity and the service write them), so
 * a quick start never pairs one session's config with another's login. The tile, boot, the notification, a system restart and
 * `reconnectInternal` start from it without Flutter. The only reader and writer of these files; every write goes
 * through a temp file and a rename, so a reader never sees half a file.
 */
internal class QuickConnectStore(private val dir: File) {

    fun config(): String? = synchronized(LOCK) { read(CONFIG) }

    /** The config the session runs (with the prefix proxy injected, if any); only with its params and login ([save]). */
    private fun saveConfig(config: String) = write(CONFIG, config)

    fun params(): ConnectionParams? = try {
        synchronized(LOCK) { read(PARAMS) }?.let { ConnectionParams.fromJson(JSONObject(it)) }
    } catch (_: Exception) {
        null
    }

    fun saveParams(params: ConnectionParams) = synchronized(LOCK) { write(PARAMS, params.toJson().toString()) }

    /** The SOCKS login of the last session; null when none is stored or the file is broken (both fields must be
     *  strings; empty ones are kept). */
    fun credentials(): Pair<String, String>? = try {
        synchronized(LOCK) { read(CREDENTIALS) }?.let { JSONObject(it) }?.let { json ->
            val user = json.opt("user") as? String
            val pass = json.opt("pass") as? String
            if (user != null && pass != null) user to pass else null
        }
    } catch (_: Exception) {
        null
    }

    private fun saveCredentials(port: Int, user: String, password: String) = write(
        CREDENTIALS,
        JSONObject().put("port", port).put("user", user).put("pass", password).toString(),
    )

    /** Throws when the file stays: a caller replacing the config must not keep a login that doesn't match it. */
    fun clearCredentials() = synchronized(LOCK) {
        val file = File(dir, CREDENTIALS)
        if (!file.delete() && file.exists()) throw java.io.IOException("can't remove $CREDENTIALS")
    }

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
     * Flutter's `saveQuickConnect` and every session start: the config, its params and its SOCKS login as one
     * replacement. The old login and config go first, so an interrupted replacement leaves no config (nothing to
     * quick-start) or the new config with the login read from it, never a config paired with another one's params or
     * login. A failed login write is left to that fallback rather than thrown. [tileName] — the name the tile shows
     * for it, replaced in the same step (blank removes it; null keeps the stored one, as a reconnect does); a failed
     * name write only costs the label.
     */
    fun save(
        config: String,
        params: ConnectionParams,
        socksUser: String,
        socksPassword: String,
        tileName: String? = null,
    ) = synchronized(LOCK) {
        clearCredentials()
        val old = File(dir, CONFIG)
        if (!old.delete() && old.exists()) throw java.io.IOException("can't remove $CONFIG")
        // The old name goes with the old config: an interrupted save leaves no label for a config it didn't store.
        if (tileName != null) File(dir, TILE_NAME).delete()
        saveParams(params)
        saveConfig(config)
        try {
            saveCredentials(params.socksPort, socksUser, socksPassword)
        } catch (_: Exception) {
        }
        try {
            if (tileName != null) saveTileName(tileName)
        } catch (_: Exception) {
        }
    }

    /** [block] under the lock of every read and write: a check and the write it allows, as one step. */
    fun <T> locked(block: () -> T): T = synchronized(LOCK, block)

    /** Flutter's `clearQuickConnect`: nothing left to quick-start. The off flag stays. */
    fun clear() = synchronized(LOCK) {
        for (name in listOf(CONFIG, PARAMS, CREDENTIALS, TILE_NAME)) File(dir, name).delete()
    }

    /** The user turned the VPN off: boot and a system restart don't start it again. Survives a process restart. */
    fun userOff(): Boolean = File(dir, USER_OFF).exists()

    fun setUserOff(off: Boolean) {
        val flag = File(dir, USER_OFF)
        if (off) flag.createNewFile() else flag.delete()
    }

    /**
     * The quick start from what is stored, or null without a config or parameters. The SOCKS login comes from the
     * stored one, else from the config ([socksFromConfig] reads it in the format of the session's core).
     */
    fun quickStart(socksFromConfig: (config: String, engine: CoreKind) -> Pair<String, String>): StartRequest? {
        val stored = synchronized(LOCK) {
            val params = params() ?: return null
            val config = config() ?: return null
            StartRequest(config, params, "", "", attempt = 0, reconnect = true, configName = tileName()) to credentials()
        }
        val (request, login) = stored
        val (user, password) = login ?: socksFromConfig(request.config, request.params.engine)
        return request.copy(socksUser = user, socksPassword = password)
    }

    /** Null when missing or unreadable (also removed between the check and the read). */
    private fun read(name: String): String? = try {
        File(dir, name).takeIf { it.exists() }?.readText()
    } catch (_: java.io.IOException) {
        null
    }

    private fun write(name: String, text: String) {
        // A temp file of its own per write: the activity and the service may write the same file at once.
        val tmp = File.createTempFile("$name.", ".tmp", dir)
        try {
            tmp.writeText(text)
            if (!tmp.renameTo(File(dir, name))) throw java.io.IOException("rename failed: $name")
        } finally {
            tmp.delete() // after a rename there is nothing under the temp name
        }
    }

    companion object {
        private val LOCK = Any()
        const val CONFIG = "xray_config.json"
        const val PARAMS = "last_connection_meta.json"
        const val CREDENTIALS = "socks_creds.json"
        const val USER_OFF = "user_disconnected.flag"
        const val TILE_NAME = "tile_config_name.txt"
    }
}
