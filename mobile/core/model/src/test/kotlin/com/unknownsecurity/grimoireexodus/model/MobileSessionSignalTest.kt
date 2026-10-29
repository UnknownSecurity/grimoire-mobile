package com.unknownsecurity.grimoireexodus.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MobileSessionSignalTest {
    @Test
    fun `inventory callback recognizes compact and formatted packet payloads`() {
        val payloads = listOf(
            """{"cmd":"loadInventoryBig","bitSuccess":1}""",
            """{ "bitSuccess": 1, "cmd": "loadInventoryBig" }""",
            """{"b":{"o":{"cmd":"loadInventoryBig"}}}""",
            """&quot;cmd&quot; : &quot;loadInventoryBig&quot;""",
        )

        payloads.forEach { payload ->
            assertTrue(
                MobileSessionSignal.isInventoryLoaded(payload),
                "Expected the login milestone to be recognized: $payload",
            )
        }
    }

    @Test
    fun `unrelated packet does not mark the player in game`() {
        assertFalse(MobileSessionSignal.isInventoryLoaded("""{"cmd":"moveToCell"}"""))
    }

    @Test
    fun `bridge booleans accept the legacy quoted true contract`() {
        assertTrue(MobileSessionSignal.isBridgeTrue("\"True\""))
        assertTrue(MobileSessionSignal.isBridgeTrue("true"))
        assertFalse(MobileSessionSignal.isBridgeTrue("\"False\""))
        assertFalse(MobileSessionSignal.isBridgeTrue(null))
    }

    @Test
    fun `bridge in game response connects the authenticated profile`() {
        val profile = MobileBridgeProfile(
            name = "Test Hero",
            level = 42,
            characterClass = "Guardian",
        )

        val session = MobileSessionSignal.reduceBridgeSession("\"True\"", profile)

        assertEquals(MobileBridgeSession(inGame = true, profile = profile), session)
    }

    @Test
    fun `bridge false response disconnects and clears the profile`() {
        val staleProfile = MobileBridgeProfile(
            name = "Test Hero",
            level = 42,
            characterClass = "Guardian",
        )

        val session = MobileSessionSignal.reduceBridgeSession("False", staleProfile)

        assertEquals(MobileBridgeSession(inGame = false, profile = null), session)
    }

    @Test
    fun `invalid bridge response does not overwrite the last known session`() {
        assertNull(MobileSessionSignal.reduceBridgeSession("callback failed", null))
        assertNull(MobileSessionSignal.reduceBridgeSession(null, null))
    }
}
