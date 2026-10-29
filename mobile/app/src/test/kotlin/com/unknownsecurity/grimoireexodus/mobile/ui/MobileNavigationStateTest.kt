package com.unknownsecurity.grimoireexodus.mobile.ui

import kotlin.test.assertEquals
import org.junit.Test

class MobileNavigationStateTest {
    @Test
    fun `every overlay destination remains selected after its menu action`() {
        listOf(
            Destination.Bots,
            Destination.Options,
            Destination.Packet,
            Destination.Tools,
            Destination.Settings,
        ).forEach { requested ->
            assertEquals(requested, MobileNavigationState.select(requested))
        }
    }
}
