package com.teapodstream.tun2socks

import android.content.Context
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.annotation.RequiresApi
import tun2socks.TeapodTun2socks

/**
 * Public teapod-tun2socks manager.
 *
 * This class is the main API of the AAR library.
 * It takes a [ParcelFileDescriptor] from Android VpnService,
 * configures the SOCKS5 proxy and manages UID validation.
 *
 * ## Usage example:
 *
 * ```kotlin
 * val manager = TeapodVpnManager(context)
 *
 * manager.start(
 *     tunFd = vpnServiceInterface,
 *     socksHost = "proxy.example.com",
 *     socksPort = 1080,
 *     socksUsername = "user",
 *     socksPassword = "pass",
 *     allowedUids = setOf(10086, 10087),
 *     whitelistMode = WhitelistMode.ALLOW_ONLY
 * )
 *
 * // ... later ...
 * manager.stop()
 * ```
 *
 * ## Requirements:
 *  - Minimum Android API: 29 (Q)
 *  - ACCESS_NETWORK_STATE permission (for getConnectionOwnerUid)
 */
@RequiresApi(Build.VERSION_CODES.Q)
class TeapodVpnManager(private val context: Context) {

    @Volatile
    private var teapodTun2socks: TeapodTun2socks? = null

    @Volatile
    private var isStarted = false

    /**
     * Starts teapod-tun2socks.
     *
     * @param tunFd          TUN interface (ParcelFileDescriptor from VpnService)
     * @param mtu            TUN interface MTU; must match VpnService.Builder.setMtu()
     * @param socksHost      SOCKS5 proxy address
     * @param socksPort      SOCKS5 proxy port
     * @param socksUsername  SOCKS5 username (empty string = no auth)
     * @param socksPassword  SOCKS5 password (empty string = no auth)
     * @param allowedUids    Set of UIDs that are allowed (or blocked, depending on the mode)
     * @param whitelistMode  Whitelist mode: [WhitelistMode.ALLOW_ONLY], [WhitelistMode.DENY_ONLY], [WhitelistMode.ALLOW_ALL]
     * @param cacheCapacity  Size of the validation LRU cache (10000 by default)
     * @param cacheTtlSeconds Cache entry TTL in seconds (300 by default)
     * @param customValidator An additional custom validator (may be null)
     *
     * @throws IllegalStateException if the manager is already running
     * @throws IllegalArgumentException if tunFd is invalid
     */
    @Synchronized
    fun start(
        tunFd: ParcelFileDescriptor,
        mtu: Int = DEFAULT_MTU,
        socksHost: String,
        socksPort: Int,
        socksUsername: String = "",
        socksPassword: String = "",
        allowIcmp: Boolean = true,
        blockQuic: Boolean = false,
        allowedUids: Set<Int> = emptySet(),
        whitelistMode: WhitelistMode = WhitelistMode.ALLOW_ONLY,
        cacheCapacity: Int = DEFAULT_CACHE_CAPACITY,
        cacheTtlSeconds: Int = DEFAULT_CACHE_TTL,
        customValidator: UidValidator? = null
    ) {
        if (isStarted) {
            throw IllegalStateException("TeapodVpnManager is already running. Call stop() before start().")
        }

        val fd = tunFd.fd
        if (fd < 0) {
            throw IllegalArgumentException("ParcelFileDescriptor holds an invalid fd: $fd")
        }

        Log.i(TAG, "Starting teapod-tun2socks: fd=$fd mtu=$mtu socks=$socksHost:$socksPort mode=$whitelistMode uids=${allowedUids.size}")

        // Create the UID resolver
        val uidResolver = UidResolver(context)

        // Create the callback adapter that Go will call
        val callback = TeapodTun2socksCallback(
            uidResolver = uidResolver,
            allowedUids = allowedUids,
            whitelistMode = whitelistMode,
            validator = customValidator
        )

        // Create the Go teapod-tun2socks
        teapodTun2socks = TeapodTun2socks().apply {
            setLogEnabled(ENABLE_DEBUG_LOGS)
            val error = start(
                fd.toLong(),
                mtu.toLong(),
                socksHost,
                socksPort.toLong(),
                socksUsername,
                socksPassword,
                allowIcmp,
                blockQuic,
                cacheCapacity.toLong(),
                cacheTtlSeconds.toLong(),
                callback
            )
            if (error.isNotEmpty()) {
                Log.e(TAG, "Error starting teapod-tun2socks: $error")
                throw IllegalStateException("teapod-tun2socks start failed: $error")
            }
        }

        isStarted = true
        Log.i(TAG, "teapod-tun2socks started successfully")
    }

    /**
     * Stops teapod-tun2socks and releases resources.
     *
     * This method blocks until all goroutines of the Go engine finish.
     */
    @Synchronized
    fun stop() {
        if (!isStarted) {
            Log.w(TAG, "stop() called, but teapod-tun2socks is not running")
            return
        }

        Log.i(TAG, "Stopping teapod-tun2socks...")

        try {
            teapodTun2socks?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping teapod-tun2socks: ${e.message}", e)
        } finally {
            teapodTun2socks = null
            isStarted = false
            Log.i(TAG, "teapod-tun2socks stopped")
        }
    }

    /**
     * Returns true if the manager is currently running.
     */
    fun isRunning(): Boolean {
        return teapodTun2socks?.isRunning() == true
    }

    /**
     * Returns the current size of the UID validation cache (for debugging).
     */
    fun getCacheSize(): Int {
        return teapodTun2socks?.cacheSize()?.toInt() ?: 0
    }

    /**
     * Toggles the Go layer's internal logging.
     */
    fun setDebugLogging(enabled: Boolean) {
        teapodTun2socks?.setLogEnabled(enabled)
    }

    /**
     * Returns the total bytes sent through TUN (upload to the internet).
     */
    fun getUploadBytes(): Long {
        return teapodTun2socks?.uploadBytes ?: 0L
    }

    /**
     * Returns the total bytes received through TUN (download from the internet).
     */
    fun getDownloadBytes(): Long {
        return teapodTun2socks?.downloadBytes ?: 0L
    }

    companion object {
        private const val TAG = "TeapodVpnManager"

        /** Default LRU cache size (entries). */
        const val DEFAULT_CACHE_CAPACITY = 10000

        /** Default cache entry TTL (seconds = 5 minutes). */
        const val DEFAULT_CACHE_TTL = 300

        /** Default TUN interface MTU. */
        const val DEFAULT_MTU = 1500

        /** Enable DEBUG logs of the Go layer (for development). */
        private const val ENABLE_DEBUG_LOGS = false
    }
}
