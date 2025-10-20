# AutoHeal

Automatic healing addon for Vanilla WoW (Turtle WoW 1.12) with intelligent target prioritization and line-of-sight awareness.

## Features

- **Smart Healing Priority**: Emergency Self-Heal → Priority List → Mouseover → Target → Lowest HP party/raid member
- **Priority List System**: Define specific players to prioritize per preset with two sorting modes
- **Emergency Self-Preservation**: Prioritizes healing yourself when critically low
- **Chained Presets**: Support multiple presets in priority order (e.g., `/autoheal swift reju`)
- **Consume Spells**: Support for spells that require buffs (e.g., Swiftmend requires Rejuvenation/Regrowth)
- **Spell Rank Selection**: Choose specific spell ranks or use highest available rank
- **Blacklist System**: Prevents spam-casting on targets with buffs (handles invisible buff problem)
- **Ignore Buff Check**: Option to disable buff checking for spells with shared buff icons
- **Line of Sight & Range Checking**: Uses UnitXP integration for accurate distance/LOS checks
- **Dynamic GCD Detection**: Tracks cast success by monitoring the actual spell being cast
- **Preset System**: Configure spell presets with graphical UI
- **Macro-Friendly**: Designed for use in keybind macros

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
```

**Chained Presets (Swiftmend if possible, otherwise Rejuvenation):**
```
/autoheal swift reju
/autoheal Heal1 Heal2 Heal3 Heal4
```
The addon will attempt to heal the most appropriate target. If no valid targets are found (or all out of range/LOS), the macro continues to the next preset.

## Configuration

### Preset Settings

Each preset can be configured with:

- **Spell Name**: The spell to cast (e.g., "Rejuvenation", "Regrowth", "Swiftmend")
- **Rank**: Spell rank to use (0 = highest available rank, or specific rank number)
- **Health Threshold**: Heal targets below this HP% (0-100)
- **Block Time**: Seconds to wait before re-casting on same target (prevents spam-casting on invisible buffs)
- **Cooldown**: Spell cooldown in seconds (for spells with cooldowns like Swiftmend, or set bonuses that modify cooldowns)
- **Max Range**: Maximum casting range in yards (further away is "Out of Range" and not cast)
- **Required Buff(s)**: Required buff(s) on unit to cast spell (e.g., "Rejuvenation,Regrowth" for Swiftmend). Comma-separated. Leave empty for spells that don't need specific buffs on target.
- **Ignore Buff Check**: Disable buff checking for spells with shared buff icons (e.g., Priest Renew with T2 8-piece bonus)
- **Emergency**: Enable emergency self-heal
- **Emergency Health%**: HP% at which to prioritize self-healing (0-100)

### Priority List

Per-preset priority player list with two sorting modes:

- **All Equal**: All priority targets are treated equally and healed based on lowest HP% first
- **By Order**: Priority targets are healed strictly from top to bottom if condition for healing is met, otherwise next in line is healed


## Healing Priority Logic

### Priority Order

1. **Emergency Self-Heal** - If enabled and your HP is below threshold, you become the ONLY target
2. **Priority List** - Players in the per-preset priority list (sorted by mode)
3. **Mouseover** - Highest intentional healing priority
4. **Current Target** - Second intentional healing priority
5. **Party/Raid/Self** - Sorted by lowest HP% first

### Emergency Self-Preservation

When **Emergency is enabled** and your HP falls below the threshold:
- **Player (Self)** becomes the ONLY target until HP recovers
- All other targets (including priority list) are ignored during emergency mode
- Returns to normal priority once you're above the threshold

### Priority List Modes

**All Equal Mode:**
- Checks all players in the priority list
- Heals whoever has the lowest HP% among them
- Falls back to normal priority if no priority targets need healing

**By Order Mode:**
- Checks players in strict top-to-bottom order
- Heals the first player in the list who meets healing conditions
- Falls back to normal priority if no priority targets need healing

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

Automatically detects consume spells by checking the "Required Buff(s)" field:
- If `requiresBuff` is filled, spell is treated as consume type (e.g., Swiftmend)
- Checks for required buff presence on target before casting
- Uses optimistic casting: if buff was recently cast but invisible (32-buff limit), tries anyway
- Tracks buff durations to determine if invisible buffs should still be present

### Ignore Buff Check

Some spells share the same buff icon with other effects:
- Example: Priest Renew with T2 8-piece bonus or ring procs
- When enabled, skips buff detection entirely
- Relies on blacklist timer to prevent spam-casting

### Chained Presets

Tries multiple presets in order until one succeeds:
- `/autoheal swift reju` tries Swiftmend first, falls back to Rejuvenation if unsuccessful
- Useful for combining consume spells with regular buffs
- Each preset in chain is evaluated independently with full priority logic

### Dynamic GCD Detection

Uses the actual spell being cast for GCD detection:
- Checks the spell slot of the cast spell (not hardcoded slot)
- Monitors 0.3s after cast attempt
- If GCD is active on that spell, cast succeeded → track target state
- If GCD is not active, cast failed → target remains available

### Range & Line of Sight

Integrates with UnitXP distance checking:
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
- Required Buff(s): (leave empty)
- Ignore Buff Check: Unchecked
- Emergency: Checked
- Emergency Health%: 60

**Example Swiftmend Preset:**
- Spell: Swiftmend
- Rank: 0
- Health %: 80
- Block Time: 15
- Cooldown: 15
- Max Range: 40
- Required Buff(s): Rejuvenation,Regrowth
- Ignore Buff Check: Unchecked
- Emergency: Checked
- Emergency Health%: 50

## Tips

- Create separate presets for different spells (reju, regrowth, swift, etc.)
- Use chained presets for efficient healing: `/autoheal swift reju` tries Swiftmend first, Rejuvenation as fallback
- Use **Priority List** to ensure key players (tanks, healers) get priority healing
- Set Priority Mode to "By Order" for strict tank healing priority
- Adjust **Block Time** based on buff duration (12s for Rejuv, 15s for Swiftmend to account for consumed buff)
- Use **Health Threshold** to control when healing starts (90% = aggressive, 70% = conservative)
- Set appropriate **Cooldown** values for spells with cooldowns (15s for Swiftmend)
- Enable **Emergency** for raid healing to avoid healer deaths
- Lower emergency threshold (30-40%) for dungeons, higher (60-70%) for raids
- Use **Ignore Buff Check** for Priest Renew if you have T2 8-piece bonus
- Use `/autoheal delete all` to reset configuration when testing or troubleshooting

## Compatibility

- **Vanilla WoW 1.12** (Turtle WoW)
- Works with pfUI raid frames
- Compatible with macros (/autoheal preset1 preset2 preset3 ...)
