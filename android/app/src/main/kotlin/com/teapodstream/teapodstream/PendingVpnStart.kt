package com.teapodstream.teapodstream

/**
 * The connect that waits for the system VPN-permission dialog. Only the latest request may start: a newer connect
 * replaces it, a disconnect cancels it. A replaced or cancelled request is answered with an error code at once, so
 * its Dart call completes instead of hanging (Dart ignores it: that attempt is already superseded).
 */
internal class PendingVpnStart {
    private var start: (() -> Unit)? = null
    private var reject: ((String) -> Unit)? = null

    // The system dialog stays on screen after a cancel: only its answer closes it.
    private var dialogOpen = false

    /**
     * Holds [start] until the dialog answers; returns true when the dialog must be shown (none is open yet — one
     * opened for a cancelled request is still on screen, and its answer goes to this request).
     */
    fun offer(start: () -> Unit, reject: (String) -> Unit): Boolean {
        val showDialog = !dialogOpen
        dialogOpen = true
        this.reject?.invoke(SUPERSEDED)
        this.start = start
        this.reject = reject
        return showDialog
    }

    /** Drops the waiting request without starting it. */
    fun cancel(code: String) {
        val r = reject
        clear()
        r?.invoke(code)
    }

    /** The dialog answered: starts the latest request, or rejects it when the permission was denied. */
    fun complete(granted: Boolean) {
        val s = start
        val r = reject
        clear()
        dialogOpen = false
        if (granted) s?.invoke() else r?.invoke(DENIED)
    }

    private fun clear() {
        start = null
        reject = null
    }

    companion object {
        const val SUPERSEDED = "SUPERSEDED"
        const val CANCELLED = "CANCELLED"
        const val DENIED = "VPN_PERMISSION_DENIED"
    }
}
