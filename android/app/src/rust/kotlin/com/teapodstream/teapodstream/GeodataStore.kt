package com.teapodstream.teapodstream

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.xrayrust.mobile.XrayCore
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Immutable pairs of databases, selected by one atomically replaced pointer. */
internal object GeodataStore {
    private const val BUNDLED = "bundled-202609082347"
    private val revisionName = Regex("(?:bundled|revision)-[0-9]+")
    private val names = listOf("geoip.dat", "geosite.dat")
    private const val MAX_BYTES = 128L * 1024 * 1024

    @Synchronized
    fun directory(context: Context): File {
        val pointer = File(context.filesDir, "geodata.active")
        if (pointer.exists()) {
            val revision = pointer.readText().trim()
            require(revisionName.matches(revision)) { "Некорректная версия геобаз" }
            return File(context.filesDir, "geodata/$revision").also(::checkFiles)
        }
        // Preserve databases downloaded by the original prototype.
        if (names.all { File(context.filesDir, it).isFile }) return context.filesDir.also(::checkFiles)
        val bundled = File(context.filesDir, "geodata/$BUNDLED")
        bundled.mkdirs()
        for (name in names) {
            val temp = File(bundled, "$name.tmp")
            context.assets.open("flutter_assets/assets/binaries/$name").use { input ->
                temp.outputStream().use { input.copyTo(it) }
            }
            move(temp, File(bundled, name))
        }
        validate(bundled)
        select(context, BUNDLED)
        return bundled
    }

    /** Hold the store lock until config loading has compiled its matchers. */
    @Synchronized
    fun <T> withDirectory(context: Context, action: (File) -> T): T = action(directory(context))

    @Synchronized
    fun activate(context: Context, revision: String) {
        require(revision.matches(Regex("revision-[0-9]+"))) { "Некорректная версия геобаз" }
        val candidate = File(context.filesDir, "geodata/$revision")
        val previous = runCatching { directory(context).canonicalFile }.getOrNull()
        validate(candidate)
        select(context, revision)
        // Running cores retain compiled matchers. Keep the previous generation
        // as well; a failed download/validation never changes the active pointer.
        File(context.filesDir, "geodata").listFiles()?.filter {
            it.isDirectory && revisionName.matches(it.name) &&
                it.canonicalFile != candidate.canonicalFile && it.canonicalFile != previous
        }?.forEach { it.deleteRecursively() }
    }

    private fun select(context: Context, revision: String) {
        val temp = File(context.filesDir, "geodata.active.tmp")
        temp.writeText(revision)
        move(temp, File(context.filesDir, "geodata.active"))
    }

    private fun move(from: File, to: File) {
        Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    private fun checkFiles(directory: File) {
        for (name in names) {
            val file = File(directory, name)
            require(file.isFile && file.length() in 1..MAX_BYTES) {
                "Геобаза $name отсутствует, пуста или превышает 128 MiB. Обнови базы в разделе «Маршрут»."
            }
        }
    }

    /** Let the real Rust parser validate both protobuf files without opening sockets. */
    private fun validate(directory: File) {
        checkFiles(directory)
        val site = firstCategory(File(directory, "geosite.dat"))
        val ip = firstCategory(File(directory, "geoip.dat"), skipPrivate = true)
        val rules = JSONArray()
            .put(JSONObject().put("type", "field").put("domain", JSONArray().put("geosite:$site")).put("outboundTag", "direct"))
            .put(JSONObject().put("type", "field").put("ip", JSONArray().put("geoip:$ip")).put("outboundTag", "direct"))
        val config = JSONObject()
            .put("inbounds", JSONArray().put(JSONObject().put("protocol", "socks").put("listen", "127.0.0.1").put("port", 10809)))
            .put("outbounds", JSONArray().put(JSONObject().put("tag", "direct").put("protocol", "freedom")))
            .put("routing", JSONObject().put("rules", rules))
        XrayCore.create(config.toString(), geodataDirectory = directory).use { }
    }

    // Only extract a category name to construct the validation config. The
    // native parser remains responsible for decoding and validating geodata.
    internal fun firstCategory(file: File, skipPrivate: Boolean = false): String {
        DataInputStream(file.inputStream().buffered()).use { input ->
            while (input.available() > 0) {
                val tag = varint(input)
                if (tag != 10) { skipField(input, tag); continue }
                val size = varint(input)
                require(size in 1..(32 * 1024 * 1024) && size <= input.available()) { "Некорректная запись в ${file.name}" }
                val bytes = ByteArray(size)
                input.readFully(bytes)
                val entry = DataInputStream(ByteArrayInputStream(bytes))
                while (entry.available() > 0) {
                    val field = varint(entry)
                    if (field != 10) { skipField(entry, field); continue }
                    val length = varint(entry)
                    require(length in 1..256 && length <= entry.available()) { "Некорректная категория в ${file.name}" }
                    val codeBytes = ByteArray(length)
                    entry.readFully(codeBytes)
                    val code = String(codeBytes, Charsets.UTF_8)
                    if (!skipPrivate || !code.equals("private", ignoreCase = true)) return code
                    break
                }
            }
        }
        error("В ${file.name} нет категорий маршрутизации")
    }

    private fun varint(input: DataInputStream): Int {
        var value = 0
        for (shift in 0..28 step 7) {
            val byte = input.readUnsignedByte()
            require(shift < 28 || byte <= 7) { "Некорректная длина protobuf" }
            value = value or ((byte and 127) shl shift)
            if (byte and 128 == 0) return value
        }
        error("Некорректный protobuf")
    }

    private fun skipField(input: DataInputStream, tag: Int) {
        val length = when (tag and 7) {
            0 -> { varint(input); return }
            1 -> 8
            2 -> varint(input)
            5 -> 4
            else -> error("Некорректный protobuf")
        }
        require(length >= 0 && length <= input.available()) { "Обрезанная геобаза" }
        require(input.skipBytes(length) == length) { "Обрезанная геобаза" }
    }
}
