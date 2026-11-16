package com.teapodstream.tun2socks

import android.util.Log
import tun2socks.UIDValidatorFunc

/**
 * Adapter between the Go layer (gomobile) and the Kotlin validator.
 * Implements a strict UID check to prevent VPN bypass.
 */
class TeapodTun2socksCallback(
    private val uidResolver: UidResolver,
    private val allowedUids: Set<Int>,
    private val validator: UidValidator? = null
) : UIDValidatorFunc {

    constructor(
        uidResolver: UidResolver,
        allowedUids: Set<Int>,
        whitelistMode: WhitelistMode,
        validator: UidValidator? = null
    ) : this(uidResolver, allowedUids, validator) {
        this.whitelistMode = whitelistMode
    }

    private var whitelistMode: WhitelistMode = WhitelistMode.ALLOW_ONLY

    override fun validate(
        srcIP: String,
        srcPort: Long,
        dstIP: String,
        dstPort: Long,
        protocol: Long
    ): Boolean {
        val startTime = System.nanoTime()

        // 1. Determine the UID of the connection owner.
        // Go now passes: srcIP = the phone (local), dstIP = the internet (remote).
        val uid = uidResolver.resolveUid(srcIP, srcPort.toInt(), dstIP, dstPort.toInt(), protocol.toInt())
        
        // 2. Check the UID.
        // If UID < 0 (-1), the owner wasn't found. Drop the packet for safety.
        val isAllowed = if (uid < 0) {
            false
        } else {
            checkUidWhitelist(uid)
        }

        // 3. An additional custom validator (if set)
        val finalAllowed = isAllowed && (validator?.validate(srcIP, srcPort.toInt(), dstIP, dstPort.toInt(), protocol.toInt()) != false)

        val elapsedMs = (System.nanoTime() - startTime) / 1_000_000.0
        if (!finalAllowed) {
            Log.w(TAG, "DENY: uid=$uid ($srcIP:$srcPort -> $dstIP:$dstPort proto=$protocol) ${elapsedMs.toInt()}ms")
        } else {
            Log.d(TAG, "ALLOW: uid=$uid ($srcIP:$srcPort -> $dstIP:$dstPort proto=$protocol) ${elapsedMs.toInt()}ms")
        }

        return finalAllowed
    }

    private fun checkUidWhitelist(uid: Int): Boolean = when (whitelistMode) {
        WhitelistMode.ALLOW_ONLY -> uid in allowedUids
        WhitelistMode.DENY_ONLY  -> uid !in allowedUids
        WhitelistMode.ALLOW_ALL  -> true
    }

    companion object {
        private const val TAG = "TeapodTun2socksCallback"
    }
}

enum class WhitelistMode {
    ALLOW_ONLY,
    DENY_ONLY,
    ALLOW_ALL
}
