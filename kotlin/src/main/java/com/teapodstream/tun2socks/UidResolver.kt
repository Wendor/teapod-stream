package com.teapodstream.tun2socks

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.system.OsConstants
import androidx.annotation.RequiresApi
import java.net.InetSocketAddress

/**
 * A wrapper over [ConnectivityManager.getConnectionOwnerUid] that determines
 * the Android UID of the process owning a network connection.
 *
 * Requires Android API 29+.
 */
@RequiresApi(Build.VERSION_CODES.Q)
class UidResolver(private val context: Context) {

    private val connectivityManager: ConnectivityManager by lazy {
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    }

    /**
     * Determines the connection owner's UID.
     *
     * @param srcAddr  Local IP address
     * @param srcPort  Local port
     * @param dstAddr  Remote IP address
     * @param dstPort  Remote port
     * @param protocol Protocol number (OsConstants.IPPROTO_TCP or OsConstants.IPPROTO_UDP)
     * @return The owner's UID, or -1 if it couldn't be determined
     */
    fun resolveUid(
        srcAddr: String,
        srcPort: Int,
        dstAddr: String,
        dstPort: Int,
        protocol: Int
    ): Int {
        return try {
            // getConnectionOwnerUid determines the UID of the app owning
            // this local/remote address pair.
            // IPPROTO_TCP for TCP, IPPROTO_UDP for UDP.
            val uid = connectivityManager.getConnectionOwnerUid(
                protocol,
                InetSocketAddress(srcAddr, srcPort),
                InetSocketAddress(dstAddr, dstPort)
            )
            uid
        } catch (e: SecurityException) {
            // Requires the ACCESS_NETWORK_STATE permission
            android.util.Log.w(
                TAG,
                "SecurityException in getConnectionOwnerUid: ${e.message}"
            )
            -1
        } catch (e: Exception) {
            android.util.Log.e(
                TAG,
                "Error determining the UID for $srcAddr:$srcPort -> $dstAddr:$dstPort: ${e.message}"
            )
            -1
        }
    }

    /**
     * Determines the UID for a TCP connection.
     */
    fun resolveTcpUid(
        localAddr: String,
        localPort: Int,
        remoteAddr: String,
        remotePort: Int
    ): Int {
        return resolveUid(
            localAddr, localPort, remoteAddr, remotePort,
            OsConstants.IPPROTO_TCP
        )
    }

    /**
     * Determines the UID for a UDP connection.
     */
    fun resolveUdpUid(
        localAddr: String,
        localPort: Int,
        remoteAddr: String,
        remotePort: Int
    ): Int {
        return resolveUid(
            localAddr, localPort, remoteAddr, remotePort,
            OsConstants.IPPROTO_UDP
        )
    }

    companion object {
        private const val TAG = "UidResolver"
    }
}
