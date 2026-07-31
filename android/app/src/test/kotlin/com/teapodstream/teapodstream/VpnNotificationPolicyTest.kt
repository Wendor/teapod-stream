package com.teapodstream.teapodstream

import org.junit.Assert.assertEquals
import org.junit.Test

class VpnNotificationPolicyTest {

    @Test
    fun `hidden rich notification always stays minimal`() {
        listOf(
            "connecting",
            "reconnecting",
            "connected",
            "disconnecting",
            "disconnected",
            "error",
            "blocked",
        ).forEach { state ->
            assertEquals(
                "state=$state",
                VpnNotificationVariant.MINIMAL,
                VpnNotificationPolicy.variantFor(state, showRichNotification = false),
            )
        }
    }

    @Test
    fun `rich notification follows vpn lifecycle`() {
        val expected = mapOf(
            "connecting" to VpnNotificationVariant.CONNECTING,
            "reconnecting" to VpnNotificationVariant.CONNECTING,
            "disconnecting" to VpnNotificationVariant.DISCONNECTING,
            "connected" to VpnNotificationVariant.CONNECTED,
            "disconnected" to VpnNotificationVariant.DISCONNECTED,
            "error" to VpnNotificationVariant.KEEP_CURRENT,
            "blocked" to VpnNotificationVariant.KEEP_CURRENT,
        )

        expected.forEach { (state, variant) ->
            assertEquals(
                "state=$state",
                variant,
                VpnNotificationPolicy.variantFor(state, showRichNotification = true),
            )
        }
    }
}
