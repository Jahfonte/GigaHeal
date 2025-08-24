# GigaHealer

Intelligent Downranking for Turtle WoW healers.

**Heal smarter, not harder.**

## Features

### Core Improvements
- **Guaranteed Castability** - Never attempts to cast spells you can't afford (requires [TheoryCraft](https://github.com/tiffanyplus/TheoryCraft-Turtle) addon)
- **Intelligent Downranking** - Finds the most mana-efficient rank that adequately heals
- **Emergency Detection** - Different logic for critical vs stable targets

### Efficiency Systems
- **Auto Mode** - Adaptive downranking based on mana conservation levels
- **Conservation Mode** - Aggressive efficiency when mana <50% and target >70% health  
- **Healing History** - Tracks last 25 heals for efficiency analysis
- **Priority Logic** - Healing Need → Mana Availability → Efficiency

### Statistics & Monitoring
- `/gh_stats` - View healing efficiency and overheal analysis
- `/gh_emergency 0.3` - Set emergency threshold (default 30%)
- `/gh_auto on/off` - Toggle auto efficiency mode
- `/gh_overheal 1.2` - Set overheal multiplier

## Installation

1. Download the latest release
2. Extract to `Interface/AddOns/GigaHealer`
3. Restart WoW or type `/reload`

## Usage

### Basic Commands
```
/heal <spell_name> - Cast optimal rank of specified spell
/heal <spell_name>, 1.2 - Cast with 20% overheal tolerance
```

### Examples by Class

**Shaman**
```
/heal Healing Wave
/heal Lesser Healing Wave
/heal Chain Heal
```

**Priest**
```
/heal Greater Heal
/heal Flash Heal
/heal Heal
```

**Paladin**
```
/heal Holy Light
/heal Flash of Light
```

**Druid**
```
/heal Healing Touch
/heal Regrowth
```

## How It Works

### Rank Selection Algorithm

1. **Calculate Affordable Ranks** - Determines highest rank you can cast with current mana
2. **Find Optimal Rank** - Searches from Rank 1 upward for lowest adequate rank
3. **Apply Context Logic** - Emergency mode uses max rank, conservation mode prefers rank 1
4. **Guarantee Castability** - Final safety check ensures selected rank is affordable

### Key Improvements Over Original

**Original SmartHealer Issues:**
- Could suggest uncastable ranks (mana bug)
- Started from max rank and broke early (inefficient)
- No context awareness (same logic for all situations)

**GigaHealer Solutions:**
- Guaranteed mana affordability check
- Searches from rank 1 up (finds most efficient)
- Emergency vs conservation modes
- Proper traversal without early breaks

## Integration Support

Works seamlessly with:
- pfUI
- Clique
- ClassicMouseover
- **[TheoryCraft](https://github.com/tiffanyplus/TheoryCraft-Turtle)** (recommended for enhanced mana affordability features)

## Configuration

Settings are saved per account in `GigaHealerDB`:
- `overheal` - Default overheal multiplier (1.1 = 10% overheal)
- `auto_mode` - Enable adaptive efficiency mode
- `emergency_threshold` - Health % to trigger emergency mode
- `aggressive_conservation` - Use rank 1 when possible

## Technical Details

- **WoW Version**: 1.12 (Turtle WoW)
- **Dependencies**: Ace2 libraries (included)
- **Recommended**: [TheoryCraft](https://github.com/tiffanyplus/TheoryCraft-Turtle) addon for precise mana affordability calculations
- **Language**: Lua 5.1

**Note**: GigaHealer works standalone, but installing [TheoryCraft](https://github.com/tiffanyplus/TheoryCraft-Turtle) addon unlocks enhanced mana efficiency features including guaranteed spell castability.

## Performance Impact

- Minimal CPU usage (calculations only on cast)
- Small memory footprint (~200KB)
- No combat log parsing overhead

## Credits

- **Author**: Jah
- **Based on**: [SmartHealer](https://github.com/melbaa/SmartHealer) by Ogrisch/Garkin
- **Original Concept**: LazySpell by Ogrisch
- **Libraries**: Ace2, HealComm-1.0, SpellCache-1.0

## Attribution

GigaHealer builds upon the excellent foundation of SmartHealer, which provided the core rank selection concepts and addon integrations. Major improvements include guaranteed mana affordability, enhanced efficiency algorithms, and advanced statistics tracking.

## License

This addon is free software. You can redistribute it and/or modify it under the terms of the GNU General Public License.

## Support

Report issues or suggestions on the [GitHub repository](https://github.com/Jahfonte/GigaHeal).