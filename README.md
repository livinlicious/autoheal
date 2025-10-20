# AutoHeal

Automatic healing addon for Vanilla WoW (Turtle WoW 1.12) with intelligent target prioritization and line-of-sight awareness.

## Features

- **Smart Healing Priority**: Mouseover → Target → Lowest HP party/raid member
- **Emergency Self-Preservation**: Automatically prioritizes healing yourself when critically low
- **Chained Presets**: Support multiple presets in priority order (e.g., `/autoheal swift reju`)
- **Consume Spells**: Support for spells that require buffs (e.g., Swiftmend requires Rejuvenation/Regrowth)
- **Spell Rank Selection**: Choose specific spell ranks or use highest available rank
- **Blacklist System**: Prevents spam-casting on targets with pending buffs (handles invisible buff problem)
- **Line of Sight & Range Checking**: Uses pfUI-raiddistance integration for accurate distance/LOS checks
- **GCD-Based Success Detection**: Reliably tracks cast success without requiring combat log parsing
- **Preset System**: Configure unlimited healing profiles with graphical UI
- **Macro-Friendly**: Designed for use in keybind macros with silent operation

## Installation

1. Copy the `AutoHeal` folder to `World of Warcraft\Interface\AddOns\`
2. Restart WoW or reload UI (`/reload`)
3. Type `/autoheal config` to open settings

## Usage

### Commands

- `/autoheal` or `/ah` - Show help and list available presets
- `/autoheal config` - Open configuration window
- `/autoheal <preset>` - Cast using specific preset (case-insensitive)
- `/autoheal <preset1> <preset2> ...` - Try presets in order until one succeeds
- `/autoheal delete all` - Delete all presets and reset to clean state

### Macro Examples

**Single Preset:**
```
/autoheal reju
/cast Healing Touch
```

**Chained Presets (Swiftmend with Rejuvenation fallback):**
```
/autoheal swift reju
```

**Direct Function Call:**
```
/script AutoHeal_Cast("reju")
```

The addon will attempt to heal the most appropriate target. If no valid targets are found (or all out of range/LOS), the macro continues to the next line.

## Configuration

### Preset Settings

Each preset can be configured with:

- **Spell Name**: The spell to cast (e.g., "Rejuvenation", "Regrowth", "Swiftmend")
- **Rank**: Spell rank to use (0 = highest available rank, or specific rank number)
- **Health Threshold**: Heal targets below this HP% (0-100)
- **Block Time**: Seconds to wait before re-casting on same target (handles invisible buff delay)
- **Cooldown**: Spell cooldown in seconds (for spells with cooldowns like Swiftmend)
- **Max Range**: Maximum range in yards (40 recommended for most spells)
- **Requires Buff**: Required buff on target for consume spells (e.g., "Rejuvenation/Regrowth" for Swiftmend). Leave empty for normal buffs and spells.
- **Emergency**: Enable emergency self-heal mode
- **Emergency Health%**: HP% at which to prioritize self-healing (0-100)

## Healing Priority Logic

### Normal Mode

1. **Mouseover** - Highest priority (intentional healing)
2. **Current Target** - Second priority (intentional healing)
3. **Party/Raid/Self** - Sorted by lowest HP% first

### Emergency Self-Preservation Mode

When **Self-Preservation is enabled** and your HP falls below the threshold:
- **Player (Self)** becomes the ONLY target until HP recovers
- All other targets are ignored during emergency mode
- Returns to normal priority once you're above the threshold

## Technical Details

### State Tracking System

Tracks spell casts at the spell level (not preset level):
- **Target States**: `TargetStates[targetName][spellName]` tracks when each spell was cast on each target
- **Spell Cooldowns**: `SpellCooldowns[spellName]` tracks global cooldowns for spells like Swiftmend
- Multiple presets using the same spell share tracking state
- Prevents duplicate casts and respects cooldowns

### Blacklist System

Prevents spam-casting by tracking recent casts:
- After successfully casting on a target, they're blacklisted for `blockTime` seconds
- Handles the "invisible buff" problem where buffs appear on your client but not immediately on others
- Typical values: 12 seconds for HoTs, 6 seconds for instant cast buffs

### Consume Spell Support

Automatically detects consume spells by checking the "Requires Buff" field:
- If `requiresBuff` is filled, spell is treated as consume type (e.g., Swiftmend)
- Checks for required buff presence on target before casting
- Uses optimistic casting: if buff was recently cast but invisible (32-buff limit), tries anyway
- Tracks buff durations to determine if invisible buffs should still be present

### Chained Presets

Tries multiple presets in order until one succeeds:
- `/autoheal swift reju` tries Swiftmend first, falls back to Rejuvenation if unsuccessful
- Useful for combining consume spells with regular buffs
- Each preset in chain is evaluated independently with full priority logic

### GCD Detection

Uses spell slot 154 cooldown as GCD indicator:
- Checks 0.3s after cast attempt
- If GCD is active, cast succeeded → track target state
- If GCD is not active, cast failed → target remains available

### Range & Line of Sight

Integrates with pfUI's distance checking:
- Uses `UnitXP("distanceBetween", "player", unit)` for precise distance
- Uses `UnitXP("inSight", "player", unit)` for line of sight checks
- Skips unreachable targets automatically

## First Time Setup

The addon starts with no presets. Use `/autoheal config` to create your first preset:

**Example Rejuvenation Preset:**
- Spell: Rejuvenation
- Rank: 0 (use highest)
- Health %: 90
- Block Time: 12
- Cooldown: 0
- Max Range: 40
- Requires Buff: (leave empty)
- Emergency: Checked
- Emergency Health%: 60

**Example Swiftmend Preset:**
- Spell: Swiftmend
- Rank: 0
- Health %: 80
- Block Time: 15
- Cooldown: 15
- Max Range: 40
- Requires Buff: Rejuvenation/Regrowth
- Emergency: Checked
- Emergency Health%: 50

## Tips

- Create separate presets for different spells (reju, regrowth, swift, etc.)
- Use chained presets for efficient healing: `/autoheal swift reju` tries Swiftmend first, Rejuvenation as fallback
- Adjust **Block Time** based on buff duration (12s for Rejuv, 15s for Swiftmend to account for consumed buff)
- Use **Health Threshold** to control when healing starts (90% = aggressive, 70% = conservative)
- Set appropriate **Cooldown** values for spells with cooldowns (15s for Swiftmend)
- Enable **Emergency** for raid healing to avoid healer deaths
- Lower emergency threshold (30-40%) for dungeons, higher (60-70%) for raids
- Use `/autoheal delete all` to reset configuration when testing or troubleshooting

## Compatibility

- **Vanilla WoW 1.12** (Turtle WoW)
- Works with pfUI raid frames
- Compatible with macro spam-casting
- No conflicts with other healing addons

## Credits

Based on proven patterns from:
- **QuickHeal**: Buff detection and target prioritization
- **AUTO-REJU macro**: Blacklist system and GCD-based success detection
- **pfUI-raiddistance**: Line of sight and distance checking
