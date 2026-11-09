package com.teapodstream.teapodstream

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import teapodcore.Teapodcore
import java.io.File

/**
 * Мост интеграционных тестов (tool/itest). Работает только в itest-сборке
 * (BuildConfig.ITEST): команды приходят интентом
 * `am start -a com.teapodstream.ITEST --es cmd '<json>'` и уходят в Dart
 * (ItestAgent), ответы и переходы состояния — строками TEAPOD_ITEST в logcat.
 */
object ItestBridge {
    const val ACTION = "com.teapodstream.ITEST"
    const val CHANNEL = "com.teapodstream/itest"
    private const val TAG = "TEAPOD_ITEST"

    private val main = Handler(Looper.getMainLooper())
    private val pending = ArrayDeque<String>()
    private var channel: MethodChannel? = null
    private var dartReady = false

    fun marker(payload: Map<String, Any?>): String = "$TAG ${JSONObject(payload)}"

    fun emit(payload: Map<String, Any?>) {
        if (BuildConfig.ITEST) Log.i(TAG, marker(payload))
    }

    fun state(value: String) =
        emit(mapOf("ev" to "state", "value" to value, "t" to System.currentTimeMillis()))

    fun attach(messenger: BinaryMessenger) {
        if (!BuildConfig.ITEST) return
        dartReady = false
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "ready") {
                    dartReady = true
                    flush()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    /** true — интент itest-команды (обработан здесь). */
    fun onIntent(context: Context, intent: Intent?): Boolean {
        if (!BuildConfig.ITEST || intent?.action != ACTION) return false
        val cmd = intent.getStringExtra("cmd") ?: return true
        val json = try {
            JSONObject(cmd)
        } catch (e: Exception) {
            emit(mapOf("ok" to false, "error" to "bad json: ${e.message}"))
            return true
        }
        if (json.optString("op") == "drop") {
            context.startService(
                Intent(context, XrayVpnService::class.java).setAction(XrayVpnService.ACTION_ITEST_DROP)
            )
            emit(mapOf("id" to json.optString("id"), "ok" to true))
            return true
        }
        if (json.optString("op") == "goroutines") {
            // Дамп горутин Go до disconnect: зависание видно только пока ядро живо.
            // Ответ длинный — файлом, как у агента (раннер читает через run-as).
            val id = json.optString("id")
            try {
                val file = File(context.filesDir, "itest_$id.json")
                file.writeText(JSONObject(mapOf("id" to id, "ok" to true, "data" to Teapodcore.dumpGoroutines())).toString())
                emit(mapOf("id" to id, "ok" to true, "file" to file.path))
            } catch (e: Exception) {
                emit(mapOf("id" to id, "ok" to false, "error" to "goroutines: ${e.message}"))
            }
            return true
        }
        main.post {
            pending.addLast(cmd)
            flush()
        }
        return true
    }

    private fun flush() {
        val ch = channel ?: return
        if (!dartReady) return
        while (pending.isNotEmpty()) ch.invokeMethod("command", pending.removeFirst())
    }
}
