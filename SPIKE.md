# Witcher 3 Co-op — Spike Report

Цель проекта: добавить настоящий Dark Souls-style co-op к Witcher Online моду (который сейчас работает только как "presence mod" — игроки видят друг друга, но мир и NPC у каждого свои).

Эта серия спайков закрывала технические риски, затем пошла дальше и **доказала полноценный bidirectional cross-device co-op** через два физических устройства (PC + Steam Deck по WiFi).

---

## Достижения (статус: ✅ DONE)

| Спайк | Что | Статус |
|---|---|---|
| **#1** AI suppression | Замолчать AI у NPC на vanilla CActor methods | ✅ |
| **#2** Marionette teleport | Передвигать NPC через TeleportWithRotation без crash | ✅ |
| **#3** Smooth motion | 10Hz updates + 60Hz interp + ground snap + walk anim | ✅ |
| **#4** Network NPC sync | UPDATE_NPC packet end-to-end через UDP relay | ✅ |
| **#5** Hit registration | Guest hit → server → host applies damage authoritatively | ✅ |
| **#6** Cross-device PC↔️Deck | Single-machine localhost → 2 physical устройства по WiFi | ✅ |
| **#7** Wine compatibility | DebugExecClient переписан на CRITICAL_SECTION/CONDITION_VARIABLE | ✅ |
| **#8** Bidirectional co-op | PC видит Deck-Геральта + наоборот, по Wine/Proton через WiFi | ✅ |

**Это работающий vertical slice multiplayer мода.** Dark Souls модель достигнута: оба игрока видят друг друга как ghost'ов в своих мирах, плюс shared NPCs через host authority.

---

## Текущая архитектура (что работает)

```
PC (host, Windows)                          Deck (guest, Wine/Proton)
═══════════════════════                     ═══════════════════════════
W3 Game + Mod                               W3 Game + Mod
   │                                           │
   │ debug-scripts (TCP 37001)                 │ debug-scripts (TCP 37001)
   │                                           │
WitcherOnlineClient.asi                     WitcherOnlineClient.asi
   │                                           │   (Wine-safe: CRITICAL_SECTION/CV)
   │ wo_get / wo_get_npcs                      │ wo_get / wo_get_npcs
   ↓                                           ↓
   UDP 40000  ──────►  Java WitcherServer  ◄──── UDP 40000
                          │
                          │ broadcast UDP
                          ▼
   ◄──── UPDATE1A/B/2A/B/3 + UPDATE_NPC + UPDATE_HIT ────►
   │                                           │
   │ HandleServerPacket                        │ HandleServerPacket
   │ pushPlayer → wo_update (ghost render)     │ wo_update (ghost render)
   │ wo_npc_update (NPC sync)                  │ wo_npc_update (NPC sync)
   ▼                                           ▼
   PC's Geralt + NPCs                          PC's Geralt + NPCs
   + Deck's Geralt as ghost                    + Deck's own Geralt
   + Spike marionettes                         + Spike marionettes (synced)
```

**Network:** WiFi (UDP), Java relay on PC's LAN IP (192.168.0.49:40000)
**Wine workarounds applied:** all std::mutex → CRITICAL_SECTION, std::cv → CONDITION_VARIABLE; AllocConsole disabled; InetPtonA вместо InetPtonW

---

## Известные ограничения

- **Задержка ~300-800ms** между движением одного игрока и его отображением на другом. Причины:
  - Несколько ExecTagged round-trips на цикл (wo_get + wo_get2 + wo_get3 + wo_get_npcs + wo_get_pending_hits)
  - Wine syscall overhead на каждый syscall
  - WiFi RTT
- **Дроунер тэги (`wo_spike_marionette`)** аккумулируются если быстро прыгать — destroy не успевает отработать
- **На Deck иногда первый запуск крашит** (Wine race condition при инициализации) — со 2-3 раза стабильно
- **Renderingu timer стартует только на первом прыжке** (auto-start через OnSpawned не всегда срабатывает)

---

## Recipe запуска

### 1. PC server

```bash
cd C:\Users\kirco\OneDrive\Documents\GitHUb\witcher_server\WitcherOnline\server
"C:/Program Files/Microsoft/jdk-21.0.11.10-hotspot/bin/java.exe" -cp build WitcherServer
```

Слушает UDP 40000 на 0.0.0.0.

### 2. PC client (Steam launch options)

```
-net -debugscripts
```

Config: `D:\SteamLibrary\steamapps\common\The Witcher 3\bin\WitcherOnline\config.xml`
```xml
<Username>admin2</Username>
<ServerIP>127.0.0.1</ServerIP>
<Port>40000</Port>
```

### 3. Deck client (Steam launch options)

```
-net -debugscripts
```

Config:
```xml
<Username>deck</Username>
<ServerIP>192.168.0.49</ServerIP>  <!-- PC's LAN IP -->
<Port>40000</Port>
```

### 4. Firewall на PC

```powershell
New-NetFirewallRule -DisplayName 'W3 Server UDP 40000' -Direction Inbound -Protocol UDP -LocalPort 40000 -Action Allow
```

### 5. Сборка DLL

```bash
cd C:\Users\kirco\OneDrive\Documents\GitHUb\witcher_server\WitcherOnline\client
"C:/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe" \
  MultiplayerClient.sln /p:Configuration=Release /p:Platform=x64 /p:OutDir=build\
```

Output: `client/build 2/WitcherOnlineClient.asi`

Deploy в обе папки на каждом устройстве:
- `bin/x64/WitcherOnlineClient.asi`
- `bin/x64_dx12/WitcherOnlineClient.asi`

---

## База знаний (Wine + W3 specific)

### Wine quirks мы наткнулись на

- **`std::mutex` / `std::condition_variable` крашат игру под Wine/Proton**. Workaround: использовать Win32 `CRITICAL_SECTION` + `CONDITION_VARIABLE` (`SleepConditionVariableCS`)
- **`AllocConsole()` крашит** в Proton. Не использовать; std::cout/cerr тоже отключить (`rdbuf(nullptr)`)
- **`InetPtonW` ненадёжен на Wine**, использовать `InetPtonA`
- **W3 launcher.exe тоже загружает наш dinput8.dll proxy** — нужно скипать init если процесс не witcher3.exe
- **W3 next-gen с `-net -debugscripts`** действительно открывает TCP 37001 под Wine (проверили `ss -tln | grep 37001`)
- **5-сек initial sleep** в TCP retry loop помогает дождаться полной инициализации W3
- **`debug-scripts` ответы приходят batched** (несколько Log() в одном TCP frame), tag matching должен это учитывать
- **`Log()` output идёт И в scriptslog.txt И в debug-scripts TCP**, `LogChannel()` — только в scriptslog

### WitcherScript gotchas

- `state`, `entry` — зарезервированные слова, не использовать как имена переменных
- `exec function` — вызывается только из console или debug-script TCP, не из обычного кода. Для re-use внутри: обернуть в regular function
- Vector field assignment работает только для local var, не для `obj.method().field.X = ...`
- `thePlayer`, `theGame` — const handles, field writes только из `this` владельца
- `std::mutex/cv` в classes на theGame работают, но crash под Wine (см. выше)
- `LogChannel` не пишет в scriptslog.txt в next-gen — только `Log()`
- Vanilla drowner: `characters\npc_entities\monsters\drowner_lvl1.w2ent`
- `theGame.CreateEntity(... tagList)` — tagList это `array<name>`, не name
- `GetActorsInRange(center, range:float, maxResults:int)` — float первый
- `NavigationComputeZ(pos, zmin, zmax, out z)` — для ground snap
- `SetGameplayMoveDirection + SetGameplayRelativeMoveSpeed(1.0)` — триггерит walk-cycle animation
- AI suppression на vanilla CActor:
  ```
  actor.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
  actor.EnableCollisions(false);
  actor.EnableCharacterCollisions(false);
  actor.SetTemporaryAttitudeGroup('friendly_to_player', AGP_Default);
  actor.GetMovingAgentComponent().SetGameplayRelativeMoveSpeed(0);
  ```
  `Pause/BlockAllActions` НЕ существуют в этой версии WS
- Player tags **сохраняются в save** — для cycle reset нужен RemoveTag в trigger
- `var` декларации только в начале функции, не mid-body

### Steam Deck-specific

- Не запускать одновременно с PC через тот же Steam аккаунт — Steam отключит. **Решение**: Deck в **Offline Mode** (W3 не имеет DRM)
- Launch options: `-net -debugscripts` БЕЗ `%command%` (Steam сам аппендит к Proton-команде)
- File path на Deck: `/home/deck/.local/share/Steam/steamapps/common/The Witcher 3/`
- Wine prefix логи: `~/.local/share/Steam/steamapps/compatdata/292030/pfx/drive_c/`

---

## Файлы изменённые в этой серии (vs upstream)

### Java server
- [`server/src/PlayerSession.java`](server/src/PlayerSession.java) — добавлен `updateNpcFields`
- [`server/src/WitcherServer.java`](server/src/WitcherServer.java) — UPDATE_NPC broadcast, UPDATE_HIT immediate broadcast

### C++ DLL
- [`client/dllmain.cpp`](client/dllmain.cpp):
  - File-based debug logger (`LogStep` → `C:\witcher_dll_log.txt`)
  - std::cout/cerr disabled (Wine crash)
  - `activateConsole()` отключен
  - Process name check (skip if не witcher3.exe)
  - `SendOneShotExec` — synchronous TCP push (Wine fallback)
  - `pushPlayer*` использует `SendOneShotExec` вместо `g_client.ExecNoWaitLatest`
  - HandleServerPacket: UPDATE_NPC + UPDATE_HIT cases (one-shot push), `remoteMu` mutex убран
  - PollPoseThread: heartbeat когда `!g_client.IsConnected()`, добавлены wo_get_npcs + wo_get_pending_hits calls
  - ExecTagged timeout 500 → 3000 ms
- [`client/DebugExecClient.h`](client/DebugExecClient.h) + [`.cpp`](client/DebugExecClient.cpp):
  - `std::mutex` → `CRITICAL_SECTION`
  - `std::condition_variable` → `CONDITION_VARIABLE` (`SleepConditionVariableCS`)
  - `InetPtonW` → `InetPtonA`
  - ThreadMain wrapped in try/catch + 5sec initial sleep
  - File logging (`DEC: ...`)

### WitcherScript
- [`witcher/mods/modWitcherOnline/content/scripts/local/anno.ws`](witcher/mods/modWitcherOnline/content/scripts/local/anno.ws) — 2 gwent wraps закомментированы (vanilla API не существует в этой W3 версии)
- [`witcher/mods/modWitcherOnline/content/scripts/local/client.ws`](witcher/mods/modWitcherOnline/content/scripts/local/client.ws) — 3 multiplayer-gwent блока закомментированы
- [`witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws`](witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws) — все наши спайк-функции:
  - `WO_ApplyMarionetteSuppression`, marionette spawn/destroy
  - `WO_HostNpcRegistry`, `wo_get_npcs` (host emit)
  - `WO_RemoteNpcRegistry`, `WO_RemoteNpcEntry`, `wo_npc_update` (guest receive)
  - `wo_npc_render60hz` timer — multi-NPC interp + ground snap + walk anim
  - `WO_HitQueue`, `wo_get_pending_hits`, `wo_apply_hit` (hit reg)
  - Jump-based test cycle (spawn → motion → hit → destroy → reset)

---

## Roadmap дальше (не критично)

### Высокий приоритет
- **Latency reduction**: timeout снизить с 3000ms, убрать неиспользуемые wo_get3 (gwent), возможно параллелить wo_get* calls
- **Render timer auto-start без jump** — найти надёжный trigger при load save (OnSpawned не работает; возможно AddTimer из конструктора r_MultiplayerClient.Init)

### Средний приоритет
- **Cleanup марионеток** — destroy запускается на jump 4 но при быстрой смене циклов накапливаются. Periodic GC по `wo_spike_marionette` тэгу
- **Damage proper sync через UPDATE_NPC alive=0** — сейчас despawn только через 5-сек timeout, не очень responsive

### Низкий приоритет
- **Quest sync** — не нужен для Dark Souls модели
- **Loot sync** — отдельный спайк
- **Voice / chat** — мод уже имеет, но нужно адаптировать для cross-device

### Заведомо большое
- **Полная реализация Dark Souls model UX**: summon sign, host/guest selection, departure on host death, etc.
- **Production-quality** — текущая версия с file-based debug logging, hardcoded ports, etc., не для релиза

---

*Сессии 2026-05-22 → 2026-05-30, ~3 рабочих дня. От "посмотрим что есть в репо" до работающего bidirectional cross-device co-op через 2 физических устройства.*
