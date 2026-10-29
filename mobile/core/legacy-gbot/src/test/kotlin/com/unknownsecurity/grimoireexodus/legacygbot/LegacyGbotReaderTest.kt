package com.unknownsecurity.grimoireexodus.legacygbot

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import java.io.ByteArrayInputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class LegacyGbotReaderTest {
    private val reader = LegacyGbotReader()

    @Test
    fun `reads the shared legacy fixture without resolving CLR types`() {
        val bytes = checkNotNull(javaClass.getResourceAsStream("/v1/legacy-delay.gbot")) {
            "Shared legacy fixture was not added to test resources."
        }.use { it.readBytes() }

        val bot = reader.read(bytes)

        assertEquals("Grimoire.Botting.Configuration", bot.rootType)
        assertEquals(1, bot.commands.size)
        assertEquals("Grimoire.Botting.Commands.Misc.CmdDelay", bot.commands.single().typeName)
        assertEquals(321, (bot.commands.single().properties["Delay"] as JsonPrimitive).int)

        val roundTripped = reader.read(reader.writeValidated(bot))
        assertEquals(bot.rootType, roundTripped.rootType)
        assertEquals(bot.commands.map { it.typeName }, roundTripped.commands.map { it.typeName })
    }

    @Test
    fun `rejects a command outside the Grimoire command namespace`() {
        val unsafe = """
            {
              "${'$'}type": "Grimoire.Botting.Configuration, Grimoire",
              "Commands": {
                "${'$'}type": "System.Collections.Generic.List`1[[Grimoire.Botting.IBotCommand, Grimoire]], mscorlib",
                "${'$'}values": [
                  { "${'$'}type": "System.Diagnostics.Process, System" }
                ]
              }
            }
        """.trimIndent().encodeToByteArray()

        assertFailsWith<LegacyGbotException> {
            reader.read(unsafe)
        }
    }

    @Test
    fun `enforces byte and depth limits before parsing`() {
        assertFailsWith<LegacyGbotException> {
            LegacyGbotReader(maximumBytes = 4).read("{}".repeat(3).encodeToByteArray())
        }

        assertFailsWith<LegacyGbotException> {
            LegacyGbotReader(maximumDepth = 2).read("{\"a\":{\"b\":{}}}".encodeToByteArray())
        }
    }

    @Test
    fun `bounds a selected document stream before parsing`() {
        val oversized = ByteArrayInputStream(ByteArray(9) { '{'.code.toByte() })

        assertFailsWith<LegacyGbotException> {
            LegacyGbotReader(maximumBytes = 8).read(oversized)
        }
    }

    @Test
    fun `rejects a document above the mobile command limit`() {
        val source = """
            {
              "${'$'}type": "Grimoire.Botting.Configuration, Grimoire",
              "Commands": {
                "${'$'}type": "System.Collections.Generic.List`1[[Grimoire.Botting.IBotCommand, Grimoire]], mscorlib",
                "${'$'}values": [
                  { "${'$'}type": "Grimoire.Botting.Commands.Misc.CmdDelay, Grimoire", "Delay": 1 },
                  { "${'$'}type": "Grimoire.Botting.Commands.Misc.CmdDelay, Grimoire", "Delay": 1 }
                ]
              }
            }
        """.trimIndent().encodeToByteArray()

        assertFailsWith<LegacyGbotException> {
            LegacyGbotReader(maximumCommands = 1).read(source)
        }
    }

    @Test
    fun `preserves command order and properties across the mobile round trip`() {
        val source = """
            {
              "${'$'}type": "Grimoire.Botting.Configuration, Grimoire",
              "Author": "Compatibility fixture",
              "BotDelay": 10,
              "Commands": {
                "${'$'}type": "System.Collections.Generic.List`1[[Grimoire.Botting.IBotCommand, Grimoire]], mscorlib",
                "${'$'}values": [
                  { "${'$'}type": "Grimoire.Botting.Commands.Misc.CmdDelay, Grimoire", "Delay": 10 },
                  { "${'$'}type": "Grimoire.Botting.Commands.Player.CmdSetCell, Grimoire", "Cell": "Enter" },
                  { "${'$'}type": "Grimoire.Botting.Commands.Player.CmdSetSpawn, Grimoire" }
                ]
              }
            }
        """.trimIndent().encodeToByteArray()

        val parsed = reader.read(source)
        val roundTripped = reader.read(reader.writeValidated(parsed))

        assertEquals(10, parsed.botDelay)
        assertEquals(
            listOf(
                "Grimoire.Botting.Commands.Misc.CmdDelay",
                "Grimoire.Botting.Commands.Player.CmdSetCell",
                "Grimoire.Botting.Commands.Player.CmdSetSpawn",
            ),
            roundTripped.commands.map { it.typeName },
        )
        assertEquals(
            parsed.commands.map { it.properties },
            roundTripped.commands.map { it.properties },
        )
    }
}
