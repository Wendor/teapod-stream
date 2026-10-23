package org.xrayrust.mobile

import java.nio.ByteBuffer

/**
 * IPv4 UDP, TCP and ICMP echo packets for the core's packet I/O
 * (pushPacket/pollPacket), so TUN paths run without a VpnService or TUN fd.
 */
internal object TunPackets {
    val client = byteArrayOf(10, 10, 0, 2)
    val loopback = byteArrayOf(127, 0, 0, 1)

    const val FIN = 0x01
    const val SYN = 0x02
    const val RST = 0x04
    const val ACK = 0x10

    data class Udp(val sourcePort: Int, val destinationPort: Int, val payload: ByteArray)
    data class Tcp(val sourcePort: Int, val destinationPort: Int, val seq: Long, val ack: Long, val flags: Int)

    fun udp(src: ByteArray, srcPort: Int, dst: ByteArray, dstPort: Int, payload: ByteArray): ByteArray {
        val length = 8 + payload.size
        val segment = ByteBuffer.allocate(length)
            .putShort(srcPort.toShort()).putShort(dstPort.toShort()).putShort(length.toShort())
            .putShort(0).put(payload)
            .array()
        // A zero UDP checksum means "none"; the computed zero is sent as 0xffff.
        segment.putChecksum(6, checksum(segment, pseudo(src, dst, 17, length)).takeIf { it != 0 } ?: 0xffff)
        return ipv4(src, dst, 17, segment)
    }

    fun tcp(src: ByteArray, srcPort: Int, dst: ByteArray, dstPort: Int, seq: Long, ack: Long, flags: Int): ByteArray {
        val segment = ByteBuffer.allocate(20)
            .putShort(srcPort.toShort()).putShort(dstPort.toShort())
            .putInt(seq.toInt()).putInt(ack.toInt())
            .put((5 shl 4).toByte()).put(flags.toByte()).putShort(0xffff.toShort())
            .putShort(0).putShort(0)
            .array()
        segment.putChecksum(16, checksum(segment, pseudo(src, dst, 6, segment.size)))
        return ipv4(src, dst, 6, segment)
    }

    fun icmpEcho(src: ByteArray, dst: ByteArray, id: Int, seq: Int, payload: ByteArray): ByteArray {
        val message = ByteBuffer.allocate(8 + payload.size)
            .put(8).put(0).putShort(0).putShort(id.toShort()).putShort(seq.toShort()).put(payload)
            .array()
        message.putChecksum(2, checksum(message, 0))
        return ipv4(src, dst, 1, message)
    }

    fun parseUdp(packet: ByteArray): Udp? {
        val header = ipv4Header(packet, 17) ?: return null
        val length = u16(packet, header + 4)
        if (length < 8 || header + length > packet.size) return null
        return Udp(u16(packet, header), u16(packet, header + 2), packet.copyOfRange(header + 8, header + length))
    }

    fun parseTcp(packet: ByteArray): Tcp? {
        val header = ipv4Header(packet, 6) ?: return null
        if (header + 20 > packet.size) return null
        return Tcp(u16(packet, header), u16(packet, header + 2), u32(packet, header + 4),
            u32(packet, header + 8), packet[header + 13].toInt() and 0x3f)
    }

    /** ICMP echo reply id and sequence. */
    fun parseEchoReply(packet: ByteArray): Pair<Int, Int>? {
        val header = ipv4Header(packet, 1) ?: return null
        if (header + 8 > packet.size || packet[header].toInt() != 0) return null
        return u16(packet, header + 4) to u16(packet, header + 6)
    }

    /** Polls the core's outbound packets until [match] accepts one or [timeoutMs] passes. */
    fun <T : Any> await(core: XrayCore, timeoutMs: Long, match: (ByteArray) -> T?): T? {
        val deadline = System.nanoTime() + timeoutMs * 1_000_000
        while (System.nanoTime() < deadline) {
            val packet = core.pollPacket(4_096)
            if (packet == null) Thread.sleep(10) else match(packet)?.let { return it }
        }
        return null
    }

    private fun ipv4(src: ByteArray, dst: ByteArray, protocol: Int, body: ByteArray): ByteArray {
        val packet = ByteBuffer.allocate(20 + body.size)
            .put(0x45).put(0).putShort((20 + body.size).toShort()).putShort(0).putShort(0x4000)
            .put(64).put(protocol.toByte()).putShort(0).put(src).put(dst).put(body)
            .array()
        packet.putChecksum(10, checksum(packet.copyOf(20), 0))
        return packet
    }

    private fun ipv4Header(packet: ByteArray, protocol: Int): Int? {
        if (packet.size < 20 || packet[0].toInt() shr 4 != 4 || packet[9].toInt() != protocol) return null
        return (packet[0].toInt() and 0x0f) * 4
    }

    private fun pseudo(src: ByteArray, dst: ByteArray, protocol: Int, length: Int): Long =
        words(src) + words(dst) + protocol + length

    private fun words(address: ByteArray): Long = (u16(address, 0) + u16(address, 2)).toLong()

    private fun u16(data: ByteArray, offset: Int): Int =
        ((data[offset].toInt() and 0xff) shl 8) or (data[offset + 1].toInt() and 0xff)

    private fun u32(data: ByteArray, offset: Int): Long =
        (u16(data, offset).toLong() shl 16) or u16(data, offset + 2).toLong()

    private fun checksum(data: ByteArray, initial: Long): Int {
        var sum = initial
        var i = 0
        while (i < data.size) {
            val high = data[i].toInt() and 0xff
            val low = if (i + 1 < data.size) data[i + 1].toInt() and 0xff else 0
            sum += ((high shl 8) or low).toLong()
            i += 2
        }
        while (sum shr 16 != 0L) sum = (sum and 0xffff) + (sum shr 16)
        return (sum.inv() and 0xffff).toInt()
    }

    private fun ByteArray.putChecksum(offset: Int, value: Int) {
        this[offset] = (value shr 8).toByte()
        this[offset + 1] = value.toByte()
    }
}
