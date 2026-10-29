# Graph Report - grimoire-mobile  (2026-10-29)

## Corpus Check
- 58 files · ~140,191 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 49 file(s) not represented in the graph (top: .as 23, .xml 10, (none) 6)

## Summary
- 934 nodes · 1743 edges · 75 communities (36 shown, 39 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 50 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Mn
- LegacyGbotReader
- In
- GameCapability
- 845
- .validate
- RuffleGameTransport.kt
- ruffle.js
- gn
- RuffleGameTransport
- RuffleLoopbackServer
- Composable
- .constructor
- I
- ExodusTheme.kt
- qe
- MobileBridgeSession
- Contributor Covenant Code of Conduct
- MainActivity.kt
- Grimoire Exodus for Android — feasibility and delivery plan
- ln
- RuffleGameSurface.kt
- Destination
- RuffleServerMap
- ea
- xn
- GrimoireExodusApp
- .toString
- .constructor
- ActionResult
- .dispatch
- yn
- BridgeContractTest.kt
- vn
- .panic
- Grimoire Exodus Mobile agent guide
- Visual design direction
- 16. Phased roadmap
- ConnectionState
- 17. Stop/go gates
- Grimoire Exodus AIR client
- 21. Sources
- .displayRootMovieDownloadFailedMessage
- 15. Testing and compatibility gates
- 9. Legacy GBot compatibility
- PULL_REQUEST_TEMPLATE.md
- 13. Updates and distribution
- 3. Verified research findings
- 4. Goals and non-goals
- 6. Recommended product architecture
- Bot/README.md
- ruffle/README.md
- game-bridge/v1/README.md
- gbot/v1/README.md
- contracts/README.md
- shared/README.md

## God Nodes (most connected - your core abstractions)
1. `gn` - 78 edges
2. `RuffleGameTransport` - 55 edges
3. `845()` - 36 edges
4. `Mn` - 30 edges
5. `TransportStatus` - 29 edges
6. `RuffleLoopbackServer` - 25 edges
7. `Pn` - 24 edges
8. `Grimoire Exodus for Android — feasibility and delivery plan` - 22 edges
9. `Destination` - 17 edges
10. `GameTransport` - 17 edges

## Surprising Connections (you probably didn't know these)
- `6.1 Product shape` --references--> `GameTransport`  [INFERRED]
  docs/android-port-plan.md → mobile/core/domain/src/main/kotlin/com/unknownsecurity/grimoireexodus/domain/GameTransport.kt
- `Implementation checkpoint 0` --references--> `GameTransport`  [INFERRED]
  docs/android-port-plan.md → mobile/core/domain/src/main/kotlin/com/unknownsecurity/grimoireexodus/domain/GameTransport.kt
- `Current milestone (0.5.0)` --references--> `GameTransport`  [INFERRED]
  mobile/README.md → mobile/core/domain/src/main/kotlin/com/unknownsecurity/grimoireexodus/domain/GameTransport.kt
- `f()` --indirect_call--> `ve()`  [INFERRED]
  mobile/app/src/main/assets/ruffle/ruffle.js → mobile/app/src/main/assets/ruffle/core.ruffle.8b0acaf2b6de35352980.js
- `wn()` --indirect_call--> `Be()`  [INFERRED]
  mobile/app/src/main/assets/ruffle/ruffle.js → mobile/app/src/main/assets/ruffle/core.ruffle.8b0acaf2b6de35352980.js

## Import Cycles
- None detected.

## Communities (75 total, 39 thin omitted)

### Community 2 - "LegacyGbotReader"
Cohesion: 0.08
Nodes (5): LegacyGbotCommand, LegacyGbotDocument, LegacyGbotException, LegacyGbotReader, LegacyGbotReaderTest

### Community 3 - "In"
Cohesion: 0.18
Nodes (3): In, kn(), Tn()

### Community 4 - "GameCapability"
Cohesion: 0.18
Nodes (11): GameCapability, CombatAct, InventoryAct, InventoryRead, NavigationMove, QuestAct, QuestRead, SessionObserve (+3 more)

### Community 5 - "845"
Cohesion: 0.11
Nodes (35): 845(), A(), Ae(), B(), Be(), Ce(), d(), g() (+27 more)

### Community 6 - ".validate"
Cohesion: 0.10
Nodes (9): MobileNavigationStateTest, OfflineGameTransportTest, BridgeCompatibility, BridgeHandshake, BridgeHandshakeValidator, Compatible, Incompatible, BridgeHandshakeValidatorTest (+1 more)

### Community 8 - "ruffle.js"
Cohesion: 0.10
Nodes (14): Ae(), ca(), Ce(), dn(), fa(), Fe(), fn(), ke (+6 more)

### Community 11 - "RuffleLoopbackServer"
Cohesion: 0.09
Nodes (3): HttpRequest, RuffleLoopbackServer, WebSocketFrame

### Community 12 - "Composable"
Cohesion: 0.20
Nodes (33): ActivityDock(), BotDocumentDetails(), BotImportEmptyState(), BotManagerSurface(), BotMetadata(), BrandMark(), CompactAccountCard(), CompactBotCard() (+25 more)

### Community 13 - ".constructor"
Cohesion: 0.30
Nodes (19): 65(), o(), a(), b(), c(), d(), f(), g() (+11 more)

### Community 14 - "I"
Cohesion: 0.07
Nodes (16): B(), d, De(), f, H(), I(), K, L() (+8 more)

### Community 16 - "qe"
Cohesion: 0.33
Nodes (4): s(), Oe(), qe(), Ye()

### Community 17 - "MobileBridgeSession"
Cohesion: 0.27
Nodes (4): MobileBridgeProfile, MobileBridgeSession, MobileSessionSignal, MobileSessionSignalTest

### Community 18 - "Contributor Covenant Code of Conduct"
Cohesion: 0.05
Nodes (33): 1. Correction, 2. Warning, 3. Temporary ban, 4. Permanent ban, Attribution, Contributor Covenant Code of Conduct, Enforcement, Enforcement guidelines (+25 more)

### Community 20 - "Grimoire Exodus for Android — feasibility and delivery plan"
Cohesion: 0.14
Nodes (14): 11. Accounts, security, and privacy, 12. Lifecycle, recovery, and performance rules, 14. Repository layout, 18. Decisions needed from the project owner, 19. Release-policy questions, 1. Executive summary, 20. Recommendation, 2. Reality check (+6 more)

### Community 21 - "ln"
Cohesion: 0.17
Nodes (4): cn(), createPlayer(), la(), ln()

### Community 23 - "Destination"
Cohesion: 0.15
Nodes (12): BotImportMessage(), BrandBar(), Destination, Bank, Bots, Home, Options, Packet (+4 more)

### Community 25 - "ea"
Cohesion: 0.24
Nodes (3): da(), ea, pluginPolyfill()

### Community 28 - "GrimoireExodusApp"
Cohesion: 0.13
Nodes (10): BotImportState, Empty, Failed, GrimoireExodusApp(), LandscapePhonePreview(), Loaded, Loading, MobileNavigationState (+2 more)

### Community 29 - ".toString"
Cohesion: 0.36
Nodes (3): a(), je, xe()

### Community 30 - ".constructor"
Cohesion: 0.15
Nodes (3): bn, Rn(), zn()

### Community 31 - "ActionResult"
Cohesion: 0.20
Nodes (7): Accepted, ActionResult, GameAction, MoveToCell, Rejected, Stop, UseSkill

### Community 34 - "yn"
Cohesion: 0.21
Nodes (4): jn(), Ne(), wn(), yn()

### Community 41 - "Grimoire Exodus Mobile agent guide"
Cohesion: 0.22
Nodes (8): Architecture, Compatibility and UI rules, Graph-first navigation, Grimoire Exodus Mobile agent guide, Privacy, Releases, Scope, Validation

### Community 44 - "Visual design direction"
Cohesion: 0.22
Nodes (9): 10. Android UX and navigation, Accessibility and ownership boundaries, Android equivalents, Color and component language, Design acceptance criteria, Landscape command center, Primary destinations, Typography (+1 more)

### Community 56 - "16. Phased roadmap"
Cohesion: 0.22
Nodes (9): 16. Phased roadmap, Overall range, Phase 0 — architecture and offline foundation (complete), Phase 1 — standalone AIR client proof (in progress), Phase 2 — integrated product foundation (6–10 weeks), Phase 3 — legacy GBot engine and core commands (10–20 weeks), Phase 4 — game integration and product parity (12–28 weeks), Phase 5 — advanced tools and plug-in replacement (12–24+ weeks) (+1 more)

### Community 57 - "ConnectionState"
Cohesion: 0.29
Nodes (6): ConnectionState, Connecting, Failed, Incompatible, Offline, Ready

### Community 58 - "17. Stop/go gates"
Cohesion: 0.33
Nodes (6): 17. Stop/go gates, Gate A — standalone AIR runtime, Gate B — supported technical bridge, Gate C — legacy compatibility, Gate D — Android lifecycle, Gate E — public distribution

### Community 59 - "Grimoire Exodus AIR client"
Cohesion: 0.33
Nodes (5): Build, Grimoire Exodus AIR client, Prerequisites, Runtime boundary, Validation status

### Community 60 - "21. Sources"
Cohesion: 0.40
Nodes (5): 21. Sources, AIR and alternative-stack sources, Android and distribution sources, Official Artix sources, Repository evidence used for this plan

### Community 62 - "15. Testing and compatibility gates"
Cohesion: 0.50
Nodes (4): 15. Testing and compatibility gates, Bridge releases, Every pull request, Release gates

### Community 63 - "9. Legacy GBot compatibility"
Cohesion: 0.50
Nodes (4): 9.1 Safe import pipeline, 9.2 Export strategy, 9.3 Execution compatibility, 9. Legacy GBot compatibility

### Community 64 - "PULL_REQUEST_TEMPLATE.md"
Cohesion: 0.50
Nodes (3): Compatibility and privacy, Summary, Validation

### Community 65 - "13. Updates and distribution"
Cohesion: 0.67
Nodes (3): 13. Updates and distribution, Google Play, Official GitHub sideload

### Community 66 - "3. Verified research findings"
Cohesion: 0.67
Nodes (3): 3.1 AIR standalone client path, 3.3 Policy and distribution constraints, 3. Verified research findings

### Community 67 - "4. Goals and non-goals"
Cohesion: 0.67
Nodes (3): 4. Goals and non-goals, Goals, Non-goals

### Community 68 - "6. Recommended product architecture"
Cohesion: 0.67
Nodes (3): 6.1 Product shape, 6.2 Game transport contract, 6. Recommended product architecture

## Knowledge Gaps
- **28 isolated node(s):** `Home`, `Bots`, `Bank`, `Options`, `Packet` (+23 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 378 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **39 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameTransport` connect `GrimoireExodusApp` to `GrimoireExodusApp.kt`, `6. Recommended product architecture`, `RuffleGameTransport.kt`, `RuffleGameTransport`, `Composable`, `Contributor Covenant Code of Conduct`, `Grimoire Exodus for Android — feasibility and delivery plan`, `ActionResult`?**
  _High betweenness centrality (0.103) - this node is a cross-community bridge._
- **What connects `Home`, `Bots`, `Bank` to the rest of the system?**
  _28 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `GrimoireExodusApp.kt` be split into smaller, more focused modules?**
  _Cohesion score 0.03125 - nodes in this community are weakly interconnected._
- **Why does `RuffleGameTransport` connect `RuffleGameTransport` to `.dispatch`, `GrimoireExodusApp.kt`, `RuffleGameTransport.kt`, `RuffleLoopbackServer`, `Composable`, `MobileBridgeSession`, `MainActivity.kt`, `RuffleGameSurface.kt`, `RuffleServerMap`, `GrimoireExodusApp`, `ActionResult`?**
  _High betweenness centrality (0.086) - this node is a cross-community bridge._
- **Should `Mn` be split into smaller, more focused modules?**
  _Cohesion score 0.050170068027210885 - nodes in this community are weakly interconnected._
- **Why does `Grimoire Exodus for Android — feasibility and delivery plan` connect `Grimoire Exodus for Android — feasibility and delivery plan` to `13. Updates and distribution`, `3. Verified research findings`, `4. Goals and non-goals`, `6. Recommended product architecture`, `Visual design direction`, `Contributor Covenant Code of Conduct`, `16. Phased roadmap`, `17. Stop/go gates`, `21. Sources`, `15. Testing and compatibility gates`, `9. Legacy GBot compatibility`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._
- **Should `LegacyGbotReader` be split into smaller, more focused modules?**
  _Cohesion score 0.08205128205128205 - nodes in this community are weakly interconnected._