package com.teapodstream.teapodstream

import java.io.File
import org.json.JSONObject

/**
 * A session start: the core config, its parameters and the SOCKS login; [attempt] — the Flutter connect it answers
 * (0 — a native start), [reconnect] — a native restart.
 */
internal data class StartRequest(
    val config: String,
    val params: ConnectionParams,
    val socksUser: String,
    val socksPassword: String,
    val attempt: Long,
    val reconnect: Boolean,
) {
    override fun toString() = "StartRequest(engine=${params.engine}, attempt=$attempt, reconnect=$reconnect)"
}

/**
 * The quick-reconnect data in [dir] (the app's private files): the last core config, its [ConnectionParams], the
 * SOCKS login, the config name the tile shows and the "turned off by the user" flag. The tile, boot, the notification, a system restart and
 * `reconnectInternal` start from it without Flutter. The only reader and writer of these files; every write goes
 * through a temp file and a rename, so a reader never sees half a file.
 */
internal class QuickConnectStore(private val dir: File) {

    fun config(): String? = read(CONFIG)

    /** The config the session runs (with the prefix proxy injected, if any). */
    fun saveConfig(config: String) = write(CONFIG, config)

    fun params(): ConnectionParams? = try {
        read(PARAMS)?.let { ConnectionParams.fromJson(JSONObject(it)) }
    } catch (_: Exception) {
        null
    }

    fun saveParams(params: ConnectionParams) = write(PARAMS, params.toJson().toString())

    /** The SOCKS login of the last session; null when none is stored or the file is broken (both fields must be
     *  strings; empty ones are kept). */
    fun credentials(): Pair<String, String>? = try {
        read(CREDENTIALS)?.let { JSONObject(it) }?.let { json ->
            val user = json.opt("user") as? String
            val pass = json.opt("pass") as? String
            if (user != null && pass != null) user to pass else null
        }
    } catch (_: Exception) {
        null
    }

    fun saveCredentials(port: Int, user: String, password: String) = write(
        CREDENTIALS,
        JSONObject().put("port", port).put("user", user).put("pass", password).toString(),
    )

    /** Throws when the file stays: a caller replacing the config must not keep a login that doesn't match it. */
    fun clearCredentials() {
        val file = File(dir, CREDENTIALS)
        if (!file.delete() && file.exists()) throw java.io.IOException("can't remove $CREDENTIALS")
    }

    /** The name of the config a quick start connects (the tile shows it); null — none. */
    fun tileName(): String? = read(TILE_NAME)

    /** A blank or null [name] removes it. */
    fun saveTileName(name: String?) {
        if (name.isNullOrBlank()) File(dir, TILE_NAME).delete() else write(TILE_NAME, name)
    }

    /** Flutter's `saveQuickConnect`: everything a quick start needs, before any session ran with it. */
    fun save(config: String, params: ConnectionParams, socksUser: String, socksPassword: String) {
        saveParams(params)
        clearCredentials() // an interrupted save must not pair the new config with the old login
        saveConfig(config)
        saveCredentials(params.socksPort, socksUser, socksPassword)
    }

    /** Flutter's `clearQuickConnect`: nothing left to quick-start. The off flag stays. */
    fun clear() {
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
    fun quickStart(socksFromConfig: (config: String, engine: String) -> Pair<String, String>): StartRequest? {
        val params = params() ?: return null
        val config = config() ?: return null
        val (user, password) = credentials() ?: socksFromConfig(config, params.engine)
        return StartRequest(config, params, user, password, attempt = 0, reconnect = true)
    }

    private fun read(name: String): String? = File(dir, name).takeIf { it.exists() }?.readText()

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
        const val CONFIG = "xray_config.json"
        const val PARAMS = "last_connection_meta.json"
        const val CREDENTIALS = "socks_creds.json"
        const val USER_OFF = "user_disconnected.flag"
        const val TILE_NAME = "tile_config_name.txt"
    }
}
