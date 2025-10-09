# AutoHeal - Smart Healing Addon for Turtle WoW

Ultimate raid healing addon based on proven patterns from QuickHeal and the AUTO-REJU macro.

## Features

### 1. **Preset System**
- Create unlimited healing presets
- Each preset is fully configurable
- Call presets by name: `/autoheal reju`, `/autoheal renew`, etc.

### 2. **Invisible Buff Detection**
Solves the "32-buff problem" in vanilla WoW:
- Checks if buff is visible on target
- Uses time-based blacklist for invisible buffs
- GCD-based cast detection to confirm successful casts
- Auto-expires blacklist when buff duration ends

### 3. **Smart Target Selection**
Priority system (from AUTO-REJU macro):
1. Mouseover (highest)
2. Current target
3. Party members
4. Raid members
5. Player (lowest)

Within same priority: heals lowest HP% first

### 4. **In-Game Configuration**
- `/autoheal config` - Open configuration window
- Create, edit, and delete presets
- No LUA editing required!

## Configuration Options (per preset)

- **Spell Name**: The spell to cast (e.g., "Rejuvenation", "Renew")
- **Health Threshold (%)**: Cast only if target HP is below this %
- **Block Time (sec)**: How long to blacklist target after casting (should match buff duration)
- **Mana Cost**: Minimum mana required to cast
- **Buff Texture**: Texture name to detect if buff is already present

## Usage

### Slash Commands
- `/autoheal` or `/ah` - Cast default preset (reju)
- `/autoheal config` - Open configuration window
- `/autoheal <preset>` - Cast specific preset (e.g., `/autoheal reju`)

### Creating Custom Presets

1. Open config: `/autoheal config`
2. Click "New" button
3. Enter preset name (e.g., "renew", "flash", "regrowth")
4. Configure settings:
   - Spell Name: e.g., "Renew"
   - Health Threshold: e.g., 85
   - Block Time: e.g., 15 (match buff duration)
   - Mana Cost: e.g., 350
   - Buff Texture: e.g., "Spell_Holy_Renew"
5. Click "Save"
6. Use with: `/autoheal renew`

### Example Presets

**Rejuvenation (Druid)**
- Spell: Rejuvenation
- Health Threshold: 90%
- Block Time: 12s
- Mana Cost: 360
- Buff Texture: Spell_Nature_Rejuvenation

**Renew (Priest)**
- Spell: Renew
- Health Threshold: 85%
- Block Time: 15s
- Mana Cost: 350
- Buff Texture: Spell_Holy_Renew

**Regrowth (Druid - Emergency)**
- Spell: Regrowth
- Health Threshold: 60%
- Block Time: 21s
- Mana Cost: 704
- Buff Texture: Spell_Nature_ResistNature

## How Blacklisting Works

The addon solves the invisible buff problem:

1. **Checks visible buffs first** (buffs 1-32)
2. **If not visible**, checks blacklist timer
3. **On cast attempt**:
   - Waits 0.3s
   - Checks if GCD activated (spell slot 154)
   - If GCD active = cast succeeded → blacklist target
4. **Blacklist auto-expires** after configured time

This prevents spam-casting on targets with invisible buffs!

## Macro Example

You can bind this to a key:
```
/autoheal reju
```

Or create different macros for different situations:
```
/autoheal renew
```

## Credits

Based on:
- **QuickHeal** - Spell detection, buff checking, target selection
- **AUTO-REJU macro** - GCD detection, blacklisting system, priority targeting

All API calls are proven and tested in Turtle WoW!
