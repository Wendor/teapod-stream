package org.xrayrust.mobile

import android.net.ConnectivityManager
import android.os.Build
import java.net.InetAddress
import java.net.InetSocketAddress

/** Raw application tuple, before FakeDNS or routing rewrites. Protocol is 6 or 17. */
data class XrayTunFlow(
    val id: Long,
    val protocol: Int,
    val source: InetSocketAddress,
    val destination: InetSocketAddress,
)

/** Called concurrently on bounded native workers. Never call core lifecycle methods here. */
fun interface XrayTunFlowAdmission {
    fun admit(flow: XrayTunFlow): Boolean
}

/** Opt-in. Timeout/fail-open apply to unavailable workers, not explicit denials or exceptions. */
data class XrayTunAdmissionOptions(
    val callback: XrayTunFlowAdmission,
    val timeoutMs: Int = 100,
    val failOpen: Boolean = false,
) {
    init { require(timeoutMs in 1..5000) { "TUN admission timeout must be in 1..5000 ms" } }
}

/**
 * Android 10+ enforcement for an active VpnService. UID rules also include apps
 * sharing that UID. Unknown owners and lookup errors deny by default. Keep the
 * VpnService Builder allow/disallow rules: this is an additional TUN safeguard.
 */
class XrayAndroidUidAdmission(
    private val connectivityManager: ConnectivityManager,
    allowedUids: Set<Int>,
    private val allowUnknownUid: Boolean = false,
) : XrayTunFlowAdmission {
    private val allowedUids = allowedUids.toSet()

    init {
        require(Build.VERSION.SDK_INT >= 29) { "TUN UID enforcement requires Android 10 or later" }
        require(this.allowedUids.all { it >= 0 }) { "allowed UIDs must be nonnegative" }
    }

    override fun admit(flow: XrayTunFlow): Boolean {
        if (Build.VERSION.SDK_INT < 29) return false
        return try {
            val uid = connectivityManager.getConnectionOwnerUid(flow.protocol, flow.source, flow.destination)
            if (uid < 0) allowUnknownUid else uid in allowedUids
        } catch (_: RuntimeException) {
            false
        }
    }
}

// JNI retains this object until the last callback returns, including after core.close().
internal class NativeTunAdmission(private val callback: XrayTunFlowAdmission) {
    @Suppress("unused")
    fun admitNative(id: Long, protocol: Int, source: ByteArray, sourcePort: Int,
        destination: ByteArray, destinationPort: Int): Boolean = callback.admit(
        XrayTunFlow(id, protocol,
            InetSocketAddress(InetAddress.getByAddress(source), sourcePort),
            InetSocketAddress(InetAddress.getByAddress(destination), destinationPort)),
    )
}
