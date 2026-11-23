package com.teapodstream.teapodstream

internal fun formatSpeed(bps: Long): String = when {
    bps >= 1_000_000 -> "%.1f MB/s".format(bps / 1_000_000.0)
    bps >= 1_000     -> "%.0f KB/s".format(bps / 1_000.0)
    else             -> "$bps B/s"
}

private val HOSTNAME = Regex(
    "^(?=.{1,253}$)[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(?:\\.[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$",
)
private val IPV6_LITERAL = Regex("^[0-9A-Fa-f:.]+(%[A-Za-z0-9_.-]+)?$")

/** True for a hostname or an IP literal: the only things handed to the `ping` binary (never an option like `-f`). */
internal fun isPingableAddress(address: String): Boolean =
    HOSTNAME.matches(address) || (address.contains(':') && IPV6_LITERAL.matches(address))
