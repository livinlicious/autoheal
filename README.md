# AutoHeal

Automatic healing addon for Vanilla WoW (Turtle WoW 1.12) with intelligent target prioritization and line-of-sight awareness.

## Features

- **Smart Healing Priority**: Mouseover → Target → Lowest HP party/raid member
- **Emergency Self-Preservation**: Automatically prioritizes healing yourself when critically low
- **Blacklist System**: Prevents spam-casting on targets with pending buffs (handles invisible buff problem)
- **Line of Sight & Range Checking**: Uses pfUI-raiddistance integration for accurate distance/LOS checks
- **Auto-Detect Buff**: Automatically detects spell buff texture from your spellbook
- **GCD-Based Success Detection**: Reliably tracks cast success without requiring combat log parsing
- **Preset System**: Configure multiple healing profiles (reju, regrowth, etc.)
- **Macro-Friendly**: Designed for use in keybind macros with silent operation

## Installation

1. Copy the `AutoHeal` folder to `World of Warcraft\Interface\AddOns\`
2. Restart WoW or reload UI (`/reload`)
3. Type `/autoheal config` to open settings

## Usage

### Commands

- `/autoheal config` - Open configuration window
- `/autoheal <preset>` - Cast using specific preset (case-insensitive)

### Macro Example

```
/autoheal Reju
```

The addon will attempt to heal the most appropriate target. If no valid targets are found (or all out of range/LOS), the macro continues to the next best target, or does nothing.

## Configuration

### Preset Settings

Each preset can be configured with:

- **Spell Name**: The spell to cast (e.g., "Rejuvenation", "Regrowth")
- **Health Threshold**: Heal targets below this HP% (0-100)
- **Block Time**: Seconds to wait before re-casting on same target (handles 32 buff limit in vanilla WOW; buffs 33-64 are invisible)
- **Max Range**: Maximum range in yards (default 40 recommended for most spells, can be configured)
- **Self-Preservation Enabled**: Enable emergency self-heal mode, to prioritize heal on yourself
- **Self-Preservation Threshold**: HP% at which to prioritize self-healing (0-100)

### Buff Detection

Buff textures are **automatically detected** from your spellbook. The addon reads the spell icon and uses it to check if buffs are already applied.

## Healing Priority Logic

### Normal Mode

1. **Mouseover** - Highest priority
2. **Current Target** - Second priority (if mouseover target is not under %HP)
3. **Party/Raid/Self** - if 1+2 are over %HP, Healing lowest %HP in Raid first

### Emergency Self-Preservation Mode

When **Self-Preservation is enabled** and your HP falls below the threshold:
- **Player (Self)** becomes the ONLY target until HP recovers
- All other targets are ignored during emergency mode
- Returns to normal priority once you're above the threshold

## Technical Details

### Blacklist System

Prevents spam-casting by tracking recent casts:
- After successfully casting on a target, they're blacklisted for `blockTime` seconds
- Handles the "invisible buff" problem where buffs appear on your client but not immediately on others

### GCD Detection

Uses spell slot 154 cooldown as GCD indicator:
- Checks 0.3s after cast attempt
- If GCD is active, cast succeeded → blacklist target
- If GCD is not active, cast failed → target remains available

### Range & Line of Sight

Integrates with pfUI's distance checking:
- Uses `UnitXP("distanceBetween", "player", unit)` for precise distance
- Uses `UnitXP("inSight", "player", unit)` for line of sight checks
- Skips unreachable targets automatically

## Default Preset

The addon includes a default "reju" preset:
- Spell: Rejuvenation
- Health Threshold: 90%
- Block Time: 12 seconds
- Max Range: 40 yards
- Self-Preservation: Enabled at 60% HP

## Tips

- Create separate presets for different spells (reju, regrowth, HT, etc.)
- Adjust **Block Time** based on buff duration (12s for Rejuv, shorter for instant casts)
- Use **Health Threshold** to control when healing starts (90% = aggressive, 70% = conservative)
- Enable **Self-Preservation** for raid healing to avoid healer deaths
- Lower threshold (30-40%) for dungeons, higher (60-70%) for raids

## Compatibility

- **Vanilla WoW 1.12** (Turtle WoW)
- Works with pfUI raid frames
- Compatible with macro casting
Based on proven patterns from:
- **QuickHeal**: Buff detection and target prioritization
- **AUTO-REJU macro**: Blacklist system and GCD-based success detection
- **pfUI-raiddistance**: Line of sight and distance checking
