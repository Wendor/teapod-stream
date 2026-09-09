package org.xrayrust.mobile

import android.net.VpnService
import android.util.Log
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

data class XrayFfiVersion(
    val major: Int,
    val minor: Int,
)

enum class XrayFfiCapability(val mask: Long) {
    ConfigWarnings(1L shl 0),
    GeodataSearch(1L shl 1),
    SocketProtection(1L shl 2),
    StartupProbe(1L shl 3),
    FileLogging(1L shl 4),
    TunPacketIo(1L shl 5),
    TunFileDescriptor(1L shl 6),
    TunBatchPoll(1L shl 7),
    TunRuntimeProfiles(1L shl 8),
    DnsBootstrapPolicy(1L shl 9),
    TunStats(1L shl 10),
    TunDiagnosticEvents(1L shl 11),
    OutboundSelection(1L shl 12),
    OutboundHealth(1L shl 13),
    ConnectionManagement(1L shl 14),
    RoutingPolicyUpdate(1L shl 15),
}

data class XrayFfiInfo(
    val version: XrayFfiVersion,
    val capabilityMask: Long,
) {
    fun supports(capability: XrayFfiCapability): Boolean =
        capabilityMask and capability.mask == capability.mask
}

enum class XrayRoutingDomainStrategy(val wireValue: String) {
    AsIs("asIs"),
    IpIfNonMatch("ipIfNonMatch"),
    IpOnDemand("ipOnDemand"),
    ;

    companion object {
        internal fun fromWireValue(value: String): XrayRoutingDomainStrategy =
            entries.firstOrNull { it.wireValue == value }
                ?: throw IllegalArgumentException("unknown routing domain strategy: $value")
    }
}

data class XrayRoutingPolicySnapshot(
    val schemaVersion: Int,
    val revision: Long,
    val ruleCount: Int,
    val domainStrategy: XrayRoutingDomainStrategy,
)

data class XrayOutboundSelectionSnapshot(
    val schemaVersion: Int,
    val revision: Long,
    val groups: List<XrayOutboundSelectorGroupSnapshot>,
)

data class XrayOutboundSelectorGroupSnapshot(
    val tag: String,
    val candidates: List<String>,
    val overrideTag: String?,
)

enum class XrayOutboundHealthState(val wireValue: String) {
    Unknown("unknown"),
    Healthy("healthy"),
    Unhealthy("unhealthy"),
    ;

    companion object {
        internal fun fromWireValue(value: String): XrayOutboundHealthState =
            entries.firstOrNull { it.wireValue == value }
                ?: throw IllegalArgumentException("unknown outbound health state: $value")
    }
}

enum class XrayOutboundHealthFailureKind(val wireValue: String) {
    Timeout("timeout"),
    Transport("transport"),
    Tls("tls"),
    Io("io"),
    MalformedHttpResponse("malformedHttpResponse"),
    HttpStatus("httpStatus"),
    ;

    companion object {
        internal fun fromWireValue(value: String): XrayOutboundHealthFailureKind =
            entries.firstOrNull { it.wireValue == value }
                ?: throw IllegalArgumentException("unknown outbound health failure kind: $value")
    }
}

data class XrayOutboundHealthSnapshot(
    val schemaVersion: Int,
    val revision: Long,
    val outbounds: List<XrayOutboundHealthStatus>,
)

data class XrayOutboundHealthStatus(
    val tag: String,
    val state: XrayOutboundHealthState,
    val delayMs: Long?,
    val lastTryUnixMs: Long?,
    val lastSeenUnixMs: Long?,
    val consecutiveFailures: Long,
    val lastFailureKind: XrayOutboundHealthFailureKind?,
    val httpStatus: Int?,
)

enum class XrayConnectionState(val wireValue: String) {
    Opening("opening"),
    Active("active"),
    ;

    companion object {
        internal fun fromWireValue(value: String): XrayConnectionState =
            entries.firstOrNull { it.wireValue == value }
                ?: throw IllegalArgumentException("unknown connection state: $value")
    }
}

enum class XrayConnectionNetwork(val wireValue: String) {
    Tcp("tcp"),
    Udp("udp"),
    ;

    companion object {
        internal fun fromWireValue(value: String): XrayConnectionNetwork =
            entries.firstOrNull { it.wireValue == value }
                ?: throw IllegalArgumentException("unknown connection network: $value")
    }
}

enum class XrayConnectionAddressType(val wireValue: String) {
    Ip("ip"),
    Domain("domain"),
    ;

    companion object {
        internal fun fromWireValue(value: String): XrayConnectionAddressType =
            entries.firstOrNull { it.wireValue == value }
                ?: throw IllegalArgumentException("unknown connection address type: $value")
    }
}

data class XrayConnectionSnapshot(
    val schemaVersion: Int,
    val revision: Long,
    val connections: List<XrayConnectionInfo>,
)

data class XrayConnectionInfo(
    val id: Long,
    val state: XrayConnectionState,
    val inboundTag: String?,
    val outboundTag: String?,
    val network: XrayConnectionNetwork,
    val addressType: XrayConnectionAddressType,
    val address: String,
    val port: Int,
    val startedUnixMs: Long,
)

data class XrayOutboundAccountingSnapshot(
    val schemaVersion: Int,
    val revision: Long,
    val outbounds: List<XrayOutboundAccounting>,
)

data class XrayOutboundAccounting(
    val outboundTag: String?,
    val openedConnections: Long,
    val completedConnections: Long,
    val hostClosedConnections: Long,
    val uplinkBytes: Long,
    val downlinkBytes: Long,
)

enum class XrayTcpSlowFlowEventKind(internal val ffiValue: Int) {
    Unknown(0),
    Open(1),
    FirstByte(2),
    ;

    companion object {
        internal fun fromFfiValue(value: Int): XrayTcpSlowFlowEventKind =
            entries.firstOrNull { it.ffiValue == value } ?: Unknown
    }
}

data class XrayTcpSlowFlowEvent(
    val kind: XrayTcpSlowFlowEventKind,
    val target: String,
    val openDurationMs: Long,
    val firstByteDurationMs: Long,
) {
    fun debugLogMessage(prefix: String = "Debug tcpSlowFlow"): String =
        "$prefix kind=${kind.name} target=$target openMs=$openDurationMs firstByteMs=$firstByteDurationMs"
}

data class XrayTcpFlowSummaryEvent(
    val target: String,
    val outboundTag: String?,
    val closed: Boolean,
    val durationMs: Long,
    val openDurationMs: Long,
    val firstByteDurationMs: Long,
    val remoteReadBytes: Long,
    val msTo64KiB: Long,
    val msTo128KiB: Long,
    val msTo256KiB: Long,
    val msTo512KiB: Long,
    val msTo1MiB: Long,
)

data class XrayTcpRemoteWriteSlowEvent(
    val target: String,
    val outboundTag: String?,
    val durationMs: Long,
    val bytes: Long,
    val messages: Long,
)

data class XrayTcpOpenErrorEvent(
    val target: String,
    val outboundTag: String?,
    val error: String,
)

data class XrayUdpSlowFlowEvent(
    val target: String,
    val firstResponseDurationMs: Long,
    val writtenBytes: Long,
    val readBytes: Long,
)

data class XrayUdpResponseGapEvent(
    val target: String,
    val responseGapDurationMs: Long,
    val writtenBytes: Long,
    val readBytes: Long,
)

data class XrayUdpQuicBlockedEvent(
    val target: String,
    val bytes: Long,
)

internal enum class NativeTunDiagnosticKind(val ffiValue: Int) {
    TcpSlowFlow(1),
    TcpFlowSummary(2),
    TcpRemoteWriteSlow(3),
    TcpOpenError(4),
    UdpSlowFlow(5),
    UdpResponseGap(6),
    UdpQuicBlocked(7),
}

internal data class NativeTunDiagnosticEvent(
    val kind: Int,
    val subtype: Int,
    val target: String,
    val outboundTag: String?,
    val error: String?,
    val values: LongArray,
) {
    internal fun requireShape(expectedKind: NativeTunDiagnosticKind, valueCount: Int) {
        check(kind == expectedKind.ffiValue) {
            "unexpected native TUN diagnostic kind: $kind"
        }
        check(values.size == valueCount) {
            "unexpected native TUN diagnostic value count: ${values.size}"
        }
    }
}

internal fun NativeTunDiagnosticEvent.toTcpSlowFlowEvent(): XrayTcpSlowFlowEvent {
    requireShape(NativeTunDiagnosticKind.TcpSlowFlow, 2)
    return XrayTcpSlowFlowEvent(
        kind = XrayTcpSlowFlowEventKind.fromFfiValue(subtype),
        target = target,
        openDurationMs = values[0],
        firstByteDurationMs = values[1],
    )
}

internal fun NativeTunDiagnosticEvent.toTcpFlowSummaryEvent(): XrayTcpFlowSummaryEvent {
    requireShape(NativeTunDiagnosticKind.TcpFlowSummary, 10)
    return XrayTcpFlowSummaryEvent(
        target = target,
        outboundTag = outboundTag,
        closed = values[0] != 0L,
        durationMs = values[1],
        openDurationMs = values[2],
        firstByteDurationMs = values[3],
        remoteReadBytes = values[4],
        msTo64KiB = values[5],
        msTo128KiB = values[6],
        msTo256KiB = values[7],
        msTo512KiB = values[8],
        msTo1MiB = values[9],
    )
}

internal fun NativeTunDiagnosticEvent.toTcpRemoteWriteSlowEvent(): XrayTcpRemoteWriteSlowEvent {
    requireShape(NativeTunDiagnosticKind.TcpRemoteWriteSlow, 3)
    return XrayTcpRemoteWriteSlowEvent(
        target = target,
        outboundTag = outboundTag,
        durationMs = values[0],
        bytes = values[1],
        messages = values[2],
    )
}

internal fun NativeTunDiagnosticEvent.toTcpOpenErrorEvent(): XrayTcpOpenErrorEvent {
    requireShape(NativeTunDiagnosticKind.TcpOpenError, 0)
    return XrayTcpOpenErrorEvent(
        target = target,
        outboundTag = outboundTag,
        error = checkNotNull(error) { "native TCP open-error diagnostic omitted its message" },
    )
}

internal fun NativeTunDiagnosticEvent.toUdpSlowFlowEvent(): XrayUdpSlowFlowEvent {
    requireShape(NativeTunDiagnosticKind.UdpSlowFlow, 3)
    return XrayUdpSlowFlowEvent(
        target = target,
        firstResponseDurationMs = values[0],
        writtenBytes = values[1],
        readBytes = values[2],
    )
}

internal fun NativeTunDiagnosticEvent.toUdpResponseGapEvent(): XrayUdpResponseGapEvent {
    requireShape(NativeTunDiagnosticKind.UdpResponseGap, 3)
    return XrayUdpResponseGapEvent(
        target = target,
        responseGapDurationMs = values[0],
        writtenBytes = values[1],
        readBytes = values[2],
    )
}

internal fun NativeTunDiagnosticEvent.toUdpQuicBlockedEvent(): XrayUdpQuicBlockedEvent {
    requireShape(NativeTunDiagnosticKind.UdpQuicBlocked, 1)
    return XrayUdpQuicBlockedEvent(target = target, bytes = values[0])
}

internal fun parseRoutingPolicySnapshot(json: String): XrayRoutingPolicySnapshot {
    val root = JSONObject(json)
    val schemaVersion = root.getInt("schemaVersion")
    require(schemaVersion == 1) {
        "unsupported routing policy snapshot schema: $schemaVersion"
    }
    return XrayRoutingPolicySnapshot(
        schemaVersion = schemaVersion,
        revision = root.getLong("revision"),
        ruleCount = root.getInt("ruleCount"),
        domainStrategy = XrayRoutingDomainStrategy.fromWireValue(
            root.getString("domainStrategy"),
        ),
    )
}

internal fun parseOutboundSelectionSnapshot(json: String): XrayOutboundSelectionSnapshot {
    val root = JSONObject(json)
    val schemaVersion = root.getInt("schemaVersion")
    require(schemaVersion == 1) {
        "unsupported outbound selection snapshot schema: $schemaVersion"
    }
    val groupsJson = root.getJSONArray("groups")
    val groups = List(groupsJson.length()) { groupIndex ->
        val group = groupsJson.getJSONObject(groupIndex)
        val candidatesJson = group.getJSONArray("candidates")
        XrayOutboundSelectorGroupSnapshot(
            tag = group.getString("tag"),
            candidates = List(candidatesJson.length()) { candidatesJson.getString(it) },
            overrideTag = group.optionalString("overrideTag"),
        )
    }
    return XrayOutboundSelectionSnapshot(
        schemaVersion = schemaVersion,
        revision = root.getLong("revision"),
        groups = groups,
    )
}

internal fun parseOutboundHealthSnapshot(json: String): XrayOutboundHealthSnapshot {
    val root = JSONObject(json)
    val schemaVersion = root.getInt("schemaVersion")
    require(schemaVersion == 1) {
        "unsupported outbound health snapshot schema: $schemaVersion"
    }
    val outboundsJson = root.getJSONArray("outbounds")
    val outbounds = List(outboundsJson.length()) { outboundIndex ->
        val outbound = outboundsJson.getJSONObject(outboundIndex)
        XrayOutboundHealthStatus(
            tag = outbound.getString("tag"),
            state = XrayOutboundHealthState.fromWireValue(outbound.getString("state")),
            delayMs = outbound.optionalLong("delayMs"),
            lastTryUnixMs = outbound.optionalLong("lastTryUnixMs"),
            lastSeenUnixMs = outbound.optionalLong("lastSeenUnixMs"),
            consecutiveFailures = outbound.getLong("consecutiveFailures"),
            lastFailureKind = outbound.optionalString("lastFailureKind")
                ?.let(XrayOutboundHealthFailureKind::fromWireValue),
            httpStatus = outbound.optionalInt("httpStatus"),
        )
    }
    return XrayOutboundHealthSnapshot(
        schemaVersion = schemaVersion,
        revision = root.getLong("revision"),
        outbounds = outbounds,
    )
}

internal fun parseConnectionSnapshot(json: String): XrayConnectionSnapshot {
    val root = JSONObject(json)
    val schemaVersion = root.getInt("schemaVersion")
    require(schemaVersion == 1) {
        "unsupported connection snapshot schema: $schemaVersion"
    }
    val connectionsJson = root.getJSONArray("connections")
    val connections = List(connectionsJson.length()) { connectionIndex ->
        val connection = connectionsJson.getJSONObject(connectionIndex)
        XrayConnectionInfo(
            id = connection.getLong("id"),
            state = XrayConnectionState.fromWireValue(connection.getString("state")),
            inboundTag = connection.optionalString("inboundTag"),
            outboundTag = connection.optionalString("outboundTag"),
            network = XrayConnectionNetwork.fromWireValue(connection.getString("network")),
            addressType = XrayConnectionAddressType.fromWireValue(
                connection.getString("addressType"),
            ),
            address = connection.getString("address"),
            port = connection.getInt("port"),
            startedUnixMs = connection.getLong("startedUnixMs"),
        )
    }
    return XrayConnectionSnapshot(
        schemaVersion = schemaVersion,
        revision = root.getLong("revision"),
        connections = connections,
    )
}

internal fun parseOutboundAccountingSnapshot(json: String): XrayOutboundAccountingSnapshot {
    val root = JSONObject(json)
    val schemaVersion = root.getInt("schemaVersion")
    require(schemaVersion == 1) {
        "unsupported outbound accounting snapshot schema: $schemaVersion"
    }
    val outboundsJson = root.getJSONArray("outbounds")
    val outbounds = List(outboundsJson.length()) { outboundIndex ->
        val outbound = outboundsJson.getJSONObject(outboundIndex)
        XrayOutboundAccounting(
            outboundTag = outbound.optionalString("outboundTag"),
            openedConnections = outbound.getLong("openedConnections"),
            completedConnections = outbound.getLong("completedConnections"),
            hostClosedConnections = outbound.getLong("hostClosedConnections"),
            uplinkBytes = outbound.getLong("uplinkBytes"),
            downlinkBytes = outbound.getLong("downlinkBytes"),
        )
    }
    return XrayOutboundAccountingSnapshot(
        schemaVersion = schemaVersion,
        revision = root.getLong("revision"),
        outbounds = outbounds,
    )
}

private fun JSONObject.optionalString(name: String): String? =
    if (isNull(name)) null else getString(name)

private fun JSONObject.optionalLong(name: String): Long? =
    if (isNull(name)) null else getLong(name)

private fun JSONObject.optionalInt(name: String): Int? =
    if (isNull(name)) null else getInt(name)

internal const val EXPECTED_XRAY_FFI_MAJOR_VERSION = 1
internal const val MINIMUM_XRAY_FFI_MINOR_VERSION = 1

internal fun validateXrayFfiVersion(version: XrayFfiVersion) {
    check(version.major == EXPECTED_XRAY_FFI_MAJOR_VERSION) {
        "incompatible xray FFI ABI major: expected " +
            "$EXPECTED_XRAY_FFI_MAJOR_VERSION, got ${version.major}"
    }
    check(version.minor >= MINIMUM_XRAY_FFI_MINOR_VERSION) {
        "incompatible xray FFI ABI minor: require at least " +
            "$MINIMUM_XRAY_FFI_MINOR_VERSION, got ${version.minor}"
    }
}

class XrayCore private constructor(handle: Long) : Closeable {
    private val lifecycleLock = ReentrantReadWriteLock(true)
    private var nativeHandle: Long = handle

    companion object {
        init {
            System.loadLibrary("xray_ffi")
            System.loadLibrary("xray_mobile_jni")
        }

        fun create(
            configJson: String,
            vpnService: VpnService? = null,
            tunFileDescriptor: XrayTunFileDescriptor? = null,
            collectTcpTimings: Boolean = false,
            tunRuntimeProfile: XrayTunRuntimeProfile = XrayTunRuntimeProfile.Default,
            startupProbe: XrayStartupProbeOptions? = null,
            dnsBootstrapMode: XrayDnsBootstrapMode = XrayDnsBootstrapMode.System,
            fileLoggingDirectory: File? = null,
            geodataDirectory: File? = null,
        ): XrayCore {
            val core = XrayCore(nativeNew())
            try {
                if (vpnService != null) {
                    core.setSocketProtector(SocketProtector(vpnService))
                }
                if (tunFileDescriptor != null) {
                    core.setTunFd(tunFileDescriptor)
                }
                core.setTunCollectTcpTimings(collectTcpTimings)
                core.setTunRuntimeProfile(tunRuntimeProfile)
                core.setDnsBootstrapMode(dnsBootstrapMode)
                if (startupProbe != null) {
                    core.setStartupProbe(startupProbe)
                }
                if (fileLoggingDirectory != null) {
                    core.setFileLogging(fileLoggingDirectory)
                }
                if (geodataDirectory != null) core.setGeodataDirectory(geodataDirectory)
                core.loadConfig(configJson)
                return core
            } catch (error: Throwable) {
                core.close()
                throw error
            }
        }

        @JvmStatic
        fun ffiInfo(): XrayFfiInfo {
            val info = XrayFfiInfo(
                version = XrayFfiVersion(
                    major = nativeFfiVersionMajor(),
                    minor = nativeFfiVersionMinor(),
                ),
                capabilityMask = nativeFfiCapabilities(),
            )
            validateXrayFfiVersion(info.version)
            return info
        }

        @JvmStatic
        private external fun nativeFfiVersionMajor(): Int

        @JvmStatic
        private external fun nativeFfiVersionMinor(): Int

        @JvmStatic
        private external fun nativeFfiCapabilities(): Long

        @JvmStatic
        private external fun nativeNew(): Long
    }

    fun start() = withLifecycleHandle { nativeStart(it) }

    fun stop() = withLifecycleHandle { nativeStop(it) }

    fun setOutboundSelectorOverride(groupTag: String, outboundTag: String) {
        requireCapability(XrayFfiCapability.OutboundSelection)
        require(groupTag.isNotEmpty()) { "selector group tag must not be empty" }
        require(outboundTag.isNotEmpty()) { "outbound tag must not be empty" }
        withDataPathHandle { nativeSetOutboundSelectorOverride(it, groupTag, outboundTag) }
    }

    fun clearOutboundSelectorOverride(groupTag: String) {
        requireCapability(XrayFfiCapability.OutboundSelection)
        require(groupTag.isNotEmpty()) { "selector group tag must not be empty" }
        withDataPathHandle { nativeClearOutboundSelectorOverride(it, groupTag) }
    }

    /** Replaces routing rules and compiled geodata matchers for new flows. */
    fun replaceRoutingPolicy(configJson: String) {
        requireCapability(XrayFfiCapability.RoutingPolicyUpdate)
        require(configJson.isNotEmpty()) { "routing policy JSON must not be empty" }
        withDataPathHandle { nativeReplaceRoutingPolicyJson(it, configJson) }
    }

    fun routingPolicySnapshot(): XrayRoutingPolicySnapshot {
        requireCapability(XrayFfiCapability.RoutingPolicyUpdate)
        return parseRoutingPolicySnapshot(
            withDataPathHandle { nativeRoutingPolicySnapshotJson(it) },
        )
    }

    fun outboundSelectionSnapshot(): XrayOutboundSelectionSnapshot {
        requireCapability(XrayFfiCapability.OutboundSelection)
        return parseOutboundSelectionSnapshot(
            withDataPathHandle { nativeOutboundSelectionSnapshotJson(it) },
        )
    }

    fun outboundHealthSnapshot(): XrayOutboundHealthSnapshot {
        requireCapability(XrayFfiCapability.OutboundHealth)
        return parseOutboundHealthSnapshot(
            withDataPathHandle { nativeOutboundHealthSnapshotJson(it) },
        )
    }

    fun connectionSnapshot(): XrayConnectionSnapshot {
        requireCapability(XrayFfiCapability.ConnectionManagement)
        return parseConnectionSnapshot(
            withDataPathHandle { nativeConnectionSnapshotJson(it) },
        )
    }

    fun outboundAccountingSnapshot(): XrayOutboundAccountingSnapshot {
        requireCapability(XrayFfiCapability.ConnectionManagement)
        return parseOutboundAccountingSnapshot(
            withDataPathHandle { nativeOutboundAccountingSnapshotJson(it) },
        )
    }

    fun closeConnection(id: Long) {
        requireCapability(XrayFfiCapability.ConnectionManagement)
        require(id > 0) { "connection id must be positive" }
        withDataPathHandle { nativeCloseConnection(it, id) }
    }

    fun pollTcpSlowFlowEvents(maxEvents: Int = 16): List<XrayTcpSlowFlowEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.TcpSlowFlow) {
            it.toTcpSlowFlowEvent()
        }

    fun pollTcpFlowSummaryEvents(maxEvents: Int = 16): List<XrayTcpFlowSummaryEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.TcpFlowSummary) {
            it.toTcpFlowSummaryEvent()
        }

    fun pollTcpRemoteWriteSlowEvents(maxEvents: Int = 16): List<XrayTcpRemoteWriteSlowEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.TcpRemoteWriteSlow) {
            it.toTcpRemoteWriteSlowEvent()
        }

    fun pollTcpOpenErrorEvents(maxEvents: Int = 16): List<XrayTcpOpenErrorEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.TcpOpenError) {
            it.toTcpOpenErrorEvent()
        }

    fun pollUdpSlowFlowEvents(maxEvents: Int = 16): List<XrayUdpSlowFlowEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.UdpSlowFlow) {
            it.toUdpSlowFlowEvent()
        }

    fun pollUdpResponseGapEvents(maxEvents: Int = 16): List<XrayUdpResponseGapEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.UdpResponseGap) {
            it.toUdpResponseGapEvent()
        }

    fun pollUdpQuicBlockedEvents(maxEvents: Int = 16): List<XrayUdpQuicBlockedEvent> =
        pollTunDiagnosticEvents(maxEvents, NativeTunDiagnosticKind.UdpQuicBlocked) {
            it.toUdpQuicBlockedEvent()
        }

    fun pushPacket(packet: ByteArray, length: Int = packet.size) {
        require(length in 0..packet.size) { "packet length is outside the source buffer" }
        withDataPathHandle { nativePushPacket(it, packet, length) }
    }

    fun pollPacket(maxBytes: Int = 1_500): ByteArray? {
        require(maxBytes > 0) { "maxBytes must be positive" }
        val storage = ByteBuffer.allocateDirect(maxBytes)
        val lengths = IntArray(1)
        val count = pollPacketsInto(
            storage = storage,
            lengths = lengths,
            maxPacketBytes = maxBytes,
            waitMilliseconds = 0,
        )
        if (count == 0) {
            return null
        }
        return ByteArray(lengths[0]).also {
            storage.position(0)
            storage.get(it)
        }
    }

    fun pollPacketsInto(
        storage: ByteBuffer,
        lengths: IntArray,
        maxPacketBytes: Int = 1_500,
        waitMilliseconds: Int = 250,
    ): Int {
        require(storage.isDirect) { "packet storage must be a direct ByteBuffer" }
        require(lengths.isNotEmpty()) { "lengths must not be empty" }
        require(maxPacketBytes > 0) { "maxPacketBytes must be positive" }
        require(waitMilliseconds >= 0) { "waitMilliseconds must not be negative" }
        require(
            storage.capacity().toLong() >= lengths.size.toLong() * maxPacketBytes.toLong(),
        ) {
            "packet storage is smaller than lengths.size * maxPacketBytes"
        }
        storage.clear()
        return withDataPathHandle {
            nativePollPackets(
                handle = it,
                storage = storage,
                lengths = lengths,
                maxPacketBytes = maxPacketBytes,
                waitMilliseconds = waitMilliseconds,
            )
        }
    }

    fun stats(): XrayTunStats {
        val raw = withDataPathHandle { nativeStats(it) }
        return XrayTunStats(
            inboundPackets = raw[0],
            outboundPackets = raw[1],
            droppedPackets = raw[2],
            udpRemoteOpenEvents = raw[3],
            udpRemoteUdp443OpenEvents = raw[4],
            udpRemoteWrittenBytes = raw[5],
            udpRemoteReadBytes = raw[6],
            tcpOpenEvents = raw[7],
            tcpOpenDurationMsTotal = raw[8],
            tcpOpenDurationMsMax = raw[9],
            tcpFirstByteEvents = raw[10],
            tcpFirstByteDurationMsTotal = raw[11],
            tcpFirstByteDurationMsMax = raw[12],
            tcp443OpenEvents = raw[13],
            tcp443OpenDurationMsTotal = raw[14],
            tcp443OpenDurationMsMax = raw[15],
            tcp443FirstByteEvents = raw[16],
            tcp443FirstByteDurationMsTotal = raw[17],
            tcp443FirstByteDurationMsMax = raw[18],
        )
    }

    override fun close() {
        // Zero the handle under the write lock so no concurrent data-path caller can observe
        // (and pass to native code) a handle that is about to be freed.
        val handle = lifecycleLock.write {
            val current = nativeHandle
            nativeHandle = 0L
            current
        }
        if (handle != 0L) {
            nativeFree(handle)
        }
    }

    private fun loadConfig(configJson: String) = withLifecycleHandle {
        nativeLoadConfig(it, configJson)
        nativeConfigWarnings(it)?.lineSequence()
            ?.filter { warning -> warning.isNotBlank() }
            ?.forEach { warning -> Log.w("XrayCore", "Config warning: $warning") }
    }

    private fun setSocketProtector(protector: SocketProtector) {
        withLifecycleHandle { nativeSetSocketProtector(it, protector) }
    }

    private fun setTunFd(tunFileDescriptor: XrayTunFileDescriptor) {
        withLifecycleHandle {
            nativeSetTunFd(
                it,
                tunFileDescriptor.fd,
                tunFileDescriptor.packetFormat.ffiValue,
                tunFileDescriptor.closePolicy.ffiValue,
            )
        }
    }

    private fun setTunRuntimeProfile(profile: XrayTunRuntimeProfile) {
        withLifecycleHandle { nativeSetTunRuntimeProfile(it, profile.ffiValue) }
    }

    private fun setTunCollectTcpTimings(collect: Boolean) {
        withLifecycleHandle { nativeSetTunCollectTcpTimings(it, collect) }
    }

    private fun setDnsBootstrapMode(mode: XrayDnsBootstrapMode) {
        withLifecycleHandle { nativeSetDnsBootstrapMode(it, mode.ffiValue) }
    }

    private fun setStartupProbe(startupProbe: XrayStartupProbeOptions) {
        withLifecycleHandle {
            nativeSetStartupProbe(
                it,
                startupProbe.url,
                startupProbe.timeoutMs,
                startupProbe.outboundTag,
            )
        }
    }

    private fun setGeodataDirectory(directory: File) {
        requireCapability(XrayFfiCapability.GeodataSearch)
        require(directory.isDirectory) { "geodata directory must exist" }
        withLifecycleHandle { nativeSetGeodataDirectory(it, directory.absolutePath) }
    }

    private external fun nativeSetGeodataDirectory(handle: Long, directory: String)

    private fun setFileLogging(directory: File) {
        require(directory.isDirectory) { "file logging directory must already exist" }
        withLifecycleHandle {
            nativeSetFileLogging(it, directory.absolutePath, true)
        }
    }

    private fun requireCapability(capability: XrayFfiCapability) {
        check(ffiInfo().supports(capability)) {
            "required xray FFI capability is unavailable: $capability"
        }
    }

    private fun <T> pollTunDiagnosticEvents(
        maxEvents: Int,
        kind: NativeTunDiagnosticKind,
        convert: (NativeTunDiagnosticEvent) -> T,
    ): List<T> {
        requireCapability(XrayFfiCapability.TunDiagnosticEvents)
        require(maxEvents >= 0) { "maxEvents must not be negative" }
        return withDataPathHandle { handle ->
            val events = mutableListOf<T>()
            while (events.size < maxEvents) {
                val event = nativePollTunDiagnosticEvent(handle, kind.ffiValue) ?: break
                events += convert(event)
            }
            events
        }
    }

    private inline fun <T> withLifecycleHandle(block: (Long) -> T): T =
        lifecycleLock.write {
            check(nativeHandle != 0L) { "xray core is closed" }
            block(nativeHandle)
        }

    private inline fun <T> withDataPathHandle(block: (Long) -> T): T =
        lifecycleLock.read {
            check(nativeHandle != 0L) { "xray core is closed" }
            block(nativeHandle)
        }

    private external fun nativeLoadConfig(handle: Long, configJson: String)
    private external fun nativeConfigWarnings(handle: Long): String?
    private external fun nativeStart(handle: Long)
    private external fun nativeStop(handle: Long)
    private external fun nativeFree(handle: Long)
    private external fun nativeSetOutboundSelectorOverride(
        handle: Long,
        groupTag: String,
        outboundTag: String,
    )
    private external fun nativeClearOutboundSelectorOverride(handle: Long, groupTag: String)
    private external fun nativeReplaceRoutingPolicyJson(handle: Long, configJson: String)
    private external fun nativeRoutingPolicySnapshotJson(handle: Long): String
    private external fun nativeOutboundSelectionSnapshotJson(handle: Long): String
    private external fun nativeOutboundHealthSnapshotJson(handle: Long): String
    private external fun nativeConnectionSnapshotJson(handle: Long): String
    private external fun nativeOutboundAccountingSnapshotJson(handle: Long): String
    private external fun nativeCloseConnection(handle: Long, connectionId: Long)
    private external fun nativePollTunDiagnosticEvent(
        handle: Long,
        kind: Int,
    ): NativeTunDiagnosticEvent?
    private external fun nativeSetSocketProtector(handle: Long, protector: SocketProtector)
    private external fun nativeSetTunFd(
        handle: Long,
        fd: Int,
        packetFormat: Int,
        closePolicy: Int,
    )
    private external fun nativeSetTunRuntimeProfile(handle: Long, profile: Int)
    private external fun nativeSetTunCollectTcpTimings(handle: Long, collect: Boolean)
    private external fun nativeSetDnsBootstrapMode(handle: Long, mode: Int)
    private external fun nativeSetFileLogging(
        handle: Long,
        directory: String,
        enabled: Boolean,
    )
    private external fun nativeSetStartupProbe(
        handle: Long,
        url: String,
        timeoutMs: Long,
        outboundTag: String?,
    )
    private external fun nativePushPacket(handle: Long, packet: ByteArray, length: Int)
    private external fun nativePollPackets(
        handle: Long,
        storage: ByteBuffer,
        lengths: IntArray,
        maxPacketBytes: Int,
        waitMilliseconds: Int,
    ): Int
    private external fun nativeStats(handle: Long): LongArray
}

data class XrayStartupProbeOptions(
    val url: String,
    val timeoutMs: Long = 5_000,
    val outboundTag: String? = null,
) {
    init {
        require(url.isNotEmpty()) { "startup probe URL must not be empty" }
        require(timeoutMs > 0) { "startup probe timeout must be positive" }
    }
}

data class XrayTunFileDescriptor(
    val fd: Int,
    val packetFormat: XrayTunFdPacketFormat = XrayTunFdPacketFormat.RawIp,
    val closePolicy: XrayTunFdClosePolicy = XrayTunFdClosePolicy.Borrowed,
)

enum class XrayTunFdPacketFormat(val ffiValue: Int) {
    RawIp(0),
    DarwinUtun(1),
}

enum class XrayTunFdClosePolicy(val ffiValue: Int) {
    Borrowed(0),
    Owned(1),
}

enum class XrayTunRuntimeProfile(val ffiValue: Int) {
    Default(0),
    Mobile(1),
    Desktop(2),
    LowMemory(3),
    Throughput(4),
    MobilePlus(5),
}

enum class XrayDnsBootstrapMode(val ffiValue: Int) {
    System(0),
    StaticOnly(1),
}

data class XrayTunStats(
    val inboundPackets: Long,
    val outboundPackets: Long,
    val droppedPackets: Long,
    val udpRemoteOpenEvents: Long,
    val udpRemoteUdp443OpenEvents: Long,
    val udpRemoteWrittenBytes: Long,
    val udpRemoteReadBytes: Long,
    val tcpOpenEvents: Long,
    val tcpOpenDurationMsTotal: Long,
    val tcpOpenDurationMsMax: Long,
    val tcpFirstByteEvents: Long,
    val tcpFirstByteDurationMsTotal: Long,
    val tcpFirstByteDurationMsMax: Long,
    val tcp443OpenEvents: Long,
    val tcp443OpenDurationMsTotal: Long,
    val tcp443OpenDurationMsMax: Long,
    val tcp443FirstByteEvents: Long,
    val tcp443FirstByteDurationMsTotal: Long,
    val tcp443FirstByteDurationMsMax: Long,
)

class XrayCoreException(
    val code: Int,
    message: String,
) : RuntimeException(message)

class SocketProtector(private val vpnService: VpnService) {
    fun protect(fd: Int): Boolean = vpnService.protect(fd)
}
