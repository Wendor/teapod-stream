package com.teapodstream.tun2socks

/**
 * UID connection validation interface.
 *
 * An implementation of this interface is passed to the Go layer via the gomobile binding
 * and called synchronously for every new TCP/UDP connection before
 * the traffic is redirected to the SOCKS5 proxy.
 *
 * If [validate] returns false, the connection is blocked:
 *  - TCP: an RST packet is sent back into TUN
 *  - UDP: the packet is silently dropped
 */
interface UidValidator {

    /**
     * Called from the Go layer to check a new connection.
     *
     * @param srcAddr  Source IP address (local, from TUN)
     * @param srcPort  Source port
     * @param dstAddr  Destination IP address (the target server)
     * @param dstPort  Destination port
     * @param protocol Protocol number: [android.system.OsConstants.IPPROTO_TCP] (6)
     *                 or [android.system.OsConstants.IPPROTO_UDP] (17)
     * @return true if the connection is allowed, false if blocked
     */
    fun validate(
        srcAddr: String,
        srcPort: Int,
        dstAddr: String,
        dstPort: Int,
        protocol: Int
    ): Boolean
}
