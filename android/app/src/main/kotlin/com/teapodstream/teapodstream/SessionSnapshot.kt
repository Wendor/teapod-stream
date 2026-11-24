package com.teapodstream.teapodstream

/** The service's session state; [wire] is the name Flutter, the itest marker and the automation broadcast see. */
enum class SessionState(val wire: String) {
    DISCONNECTED("disconnected"),
    CONNECTING("connecting"),
    /** A native restart of the session (network change, heartbeat, retry, quick start): TUN is a sink meanwhile. */
    RECONNECTING("reconnecting"),
    CONNECTED("connected"),
    DISCONNECTING("disconnecting"),
    ERROR("error"),
    /** The kill switch keeps the TUN sink after a drop: traffic is blocked. */
    BLOCKED("blocked");

    /** The states that report why the session failed. */
    val carriesError: Boolean get() = this == ERROR || this == BLOCKED

    /** The VPN is off: disconnected or failed without the kill switch's sink ([BLOCKED] is not off). */
    val isOff: Boolean get() = this == DISCONNECTED || this == ERROR
}

/**
 * Whether the service has nothing left to hold and stops: the VPN is off, no TUN is held (a kill-switch sink keeps
 * the service) and the session queue is idle (a start would bring the VPN up, a disconnect still reports its end). The tile, boot and automation start it again.
 */
internal fun serviceIdle(state: SessionState, tunHeld: Boolean, queueBusy: Boolean): Boolean =
    state.isOff && !tunHeld && !queueBusy

/**
 * The whole session state as Flutter and the rest of the app see it. Immutable: the service changes it only by
 * publishing a new one. [attempt] — Flutter's connect attempt that started the session (0 — started natively:
 * tile, boot, restart); [connectedAtMs] and the SOCKS login are set only while [SessionState.CONNECTED]; [error]
 * only with [SessionState.carriesError].
 */
data class SessionSnapshot(
    val state: SessionState = SessionState.DISCONNECTED,
    val attempt: Long = 0,
    val socksPort: Int = 0,
    val socksUser: String = "",
    val socksPassword: String = "",
    val connectedAtMs: Long = 0,
    val error: String? = null,
) {
    /**
     * The session in a state other than connected, tagged with [attempt]. The failure reason stays (or is replaced
     * by [error]) only in a state that carries one.
     */
    fun moved(state: SessionState, attempt: Long = this.attempt, error: String? = this.error): SessionSnapshot =
        SessionSnapshot(state = state, attempt = attempt, error = error.takeIf { state.carriesError })

    /**
     * The `state` event of the EventChannel (and its `onListen` replay). `attempt` only when Flutter started
     * the session, the SOCKS login and `connectedAtMs` only for `connected`, `error` for every other state.
     */
    fun toMap(): Map<String, Any?> = buildMap {
        put("type", "state")
        put("value", state.wire)
        if (attempt > 0) put("attempt", attempt)
        if (state == SessionState.CONNECTED) {
            put("socksPort", socksPort)
            put("socksUser", socksUser)
            put("socksPassword", socksPassword)
            put("connectedAtMs", connectedAtMs)
        } else {
            put("error", error)
        }
    }

    /** The itest marker of the state (`tool/itest` reads `value` and, for `connected`, the SOCKS login). */
    fun itestMarker(t: Long): Map<String, Any?> = buildMap {
        put("ev", "state")
        put("value", state.wire)
        put("t", t)
        if (state == SessionState.CONNECTED) {
            put("socksPort", socksPort)
            put("socksUser", socksUser)
            put("socksPassword", socksPassword)
        }
    }

    companion object {
        fun connected(attempt: Long, socksPort: Int, socksUser: String, socksPassword: String, atMs: Long) =
            SessionSnapshot(SessionState.CONNECTED, attempt, socksPort, socksUser, socksPassword, atMs)
    }
}
