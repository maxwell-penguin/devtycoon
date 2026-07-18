# Planet Tycoon — Full Game Design Prompt

> **Instructions to AI:** Build a complete, playable browser-based tycoon game using HTML/CSS/JavaScript (single file, no frameworks). The game should be immediately fun, satisfying, and replayable. Follow every section below precisely.

---

## Core Concept

**Planet Tycoon** — you start as a broke nobody on a procedurally laid-out planet doing grindy side hustles (lemonade stands, flipping items, street performing). You slowly stack cash, unlock districts, and scale into a full planetary empire spanning hospitals, casinos, black markets, space ports, and mega-corporations. The dopamine loop is: **grind → stack money → walk onto a locked zone → watch it auto-build in a satisfying cascade → collect passive income → repeat at a bigger scale.**

Think: *Lemonade Stand Tycoon* meets *Adventure Capitalist* meets *Habbo Hotel* zone-buying, but with a dark/morally-grey empire-building layer.

---

## Game View & Rendering

- **Top-down 2D grid map** (tile-based, ~40×30 visible tiles minimum). Use a `<canvas>` element.
- The player is a small character sprite (can be a simple colored circle/square with eyes) that moves with **WASD or arrow keys**.
- The map is divided into **districts/zones** — visually distinct rectangular regions on the grid (think city blocks).
- Locked zones appear as **translucent outlines with a price tag floating above them** and a lock icon.
- When the player walks onto a locked zone AND has enough money, a prompt appears: **"Buy [Zone Name] for $X? [Y/N]"**
- On purchase, trigger a **satisfying build animation**: tiles fill in one-by-one with a cascade/ripple effect, buildings pop up with a scale-bounce, a cash register "ka-ching" sound plays (use Web Audio API for a simple synth chime), and floating "+$X/sec" text rises from the zone.
- Camera follows the player smoothly (lerp).

---

## Economy & Progression Tiers

Design **6 tiers** of progression. Each tier unlocks new zone types, increases income scales, and introduces new mechanics:

### Tier 1 — Hustle ($0 – $500)
- **Starting zone:** A small sidewalk. Player clicks/taps a button to do manual tasks.
- Available hustles (manual click-to-earn):
  - Lemonade Stand ($1/click)
  - Shoe Shining ($2/click, unlocks at $50)
  - Street Performing ($5/click, unlocks at $150)
- First buyable zone: **Hot Dog Cart** ($200) → generates $2/sec passively

### Tier 2 — Small Business ($500 – $5K)
- **Laundromat** ($500) → $5/sec
- **Pawn Shop** ($1,200) → $12/sec
- **Food Truck Fleet** ($3,000) → $30/sec
- Unlock: **Manager hiring** — pay a one-time fee to auto-click hustles

### Tier 3 — Mogul ($5K – $50K)
- **Apartment Complex** ($8,000) → $80/sec
- **Used Car Dealership** ($15,000) → $150/sec
- **Nightclub** ($30,000) → $350/sec
- Unlock: **Reputation system** — some zones give "Street Cred" or "Corporate Rep" that gate higher-tier purchases

### Tier 4 — Underworld ($50K – $500K)
- **Underground Casino** ($60,000) → $700/sec (requires Street Cred ≥ 50)
- **Counterfeit Workshop** ($120,000) → $1,500/sec (risky: random "raid" events that pause income for 10 sec)
- **Black Market Hub** ($250,000) → $3,500/sec
- Unlock: **Bribes** — spend money to reduce raid frequency
- Unlock: **Rival NPCs** — other "tycoons" appear on the map, buying zones you haven't claimed. Creates urgency.

### Tier 5 — Corporate Empire ($500K – $10M)
- **Hospital Chain** ($500,000) → $6,000/sec
- **Tech Startup Campus** ($1.2M) → $15,000/sec
- **Media Conglomerate** ($3M) → $40,000/sec
- **Private Prison** ($5M) → $60,000/sec (morally grey, boosts income but lowers "Public Trust")
- Unlock: **Stock Market mini-game** — invest surplus cash for multiplied returns (simple buy low/sell high ticker)

### Tier 6 — Planetary Domination ($10M+)
- **Spaceport** ($10M) → $150,000/sec
- **Orbital Station** ($25M) → $400,000/sec
- **Planetary Government HQ** ($50M) → $1M/sec — **you win the game** (show a victory screen with stats)
- Unlock: **Prestige/Reset** — restart with a permanent 2× income multiplier. Track prestige count.

---

## Zone Mechanics (Critical — Make This Satisfying)

Each zone on the map is a **rectangular region of tiles** (e.g., 4×3, 6×4, 8×6 — bigger = more expensive/more income).

**Before purchase:**
- Zone border rendered as dashed outline with low opacity
- Price tag and zone name float above it
- If player doesn't have enough money, the price text is RED
- If player CAN afford it, the price text is GREEN and pulses gently

**On purchase (THE MONEY SHOT — make this feel amazing):**
- Screen does a subtle shake
- Tiles cascade-fill from the corner nearest to the player, each tile popping in with a 30ms stagger
- Building sprites/icons appear with a bouncy scale animation (overshoot ease)
- A rising "+$X/sec" floats up in gold text
- Total income counter in the HUD ticks up
- A brief particle burst (simple squares/circles) in gold

**After purchase:**
- Zone is fully rendered with its building art (can be simple emoji-style or pixel icons)
- A small animated coin icon pulses on the zone showing it's generating income
- Player can walk through owned zones freely

---

## HUD / UI

Keep the HUD minimal and clean:

- **Top-left:** Cash counter (big, satisfying number that rolls/ticks up smoothly with commas). Format: `$1,234,567`
- **Top-right:** Income per second (`$X,XXX/sec`), Tier indicator, Prestige count (if any)
- **Bottom bar:** Current zone info (when standing on one), available hustles (Tier 1), and a mini-map toggle
- **Mini-map (toggle with M):** Shows the full planet grid — owned zones in green, locked in grey, rival-owned in red, affordable in pulsing yellow

---

## Map Generation

- Generate the map procedurally on game start:
  - Place ~30-40 zones of varying sizes across the grid
  - Zones should be loosely clustered into "districts" (Hustle District near spawn, Business District nearby, Underworld further out, Corporate in the far reaches, Space zones at the map edges)
  - Roads/paths between zones (simple 2-tile-wide paths)
  - Player spawns in the center of the Hustle District

---

## Prestige System

When the player buys the **Planetary Government HQ** (final zone):
- Victory screen shows: total time played, zones owned, total cash earned, peak $/sec
- Option to **Prestige**: reset all zones and cash, but gain a permanent **income multiplier** (1st prestige = 2×, 2nd = 3×, etc.)
- Prestige count displayed in HUD
- Each prestige run should feel noticeably faster

---

## Save System

- Auto-save to `localStorage` every 30 seconds
- Save: cash, owned zones, prestige count, reputation stats, managers hired
- Load on page refresh
- "New Game" button that clears save (with confirmation)
- **Offline earnings:** On load, calculate time elapsed since last save and grant offline income (capped at 2 hours worth)

---

## Audio & Juice

Use **Web Audio API** to generate simple synth sounds (no external files needed):
- **Ka-ching** on zone purchase (short high-pitched chime)
- **Click** sound on hustle actions
- **Ambient hum** that gets richer as income grows (layer in new oscillators at tier thresholds)
- **Warning buzz** on raid events

---

## Visual Style

- **Color palette:** Dark background (#1a1a2e), neon accents for UI (cyan #00d4ff for affordable, gold #ffd700 for income, red #ff4757 for warnings/locked, green #2ed573 for owned)
- Grid lines subtle (#ffffff10)
- Zones use distinct color coding per tier (grey → blue → purple → red → gold → cosmic gradient)
- Text: clean sans-serif, with the cash counter being extra large and using a monospace font for that "ticker" feel
- Particle effects: simple but present (gold coins on purchase, red sparks on raids)

---

## Technical Requirements

- **Single HTML file**, all JS and CSS inline
- Use `<canvas>` for the game world, HTML overlays for HUD/UI
- 60fps game loop with `requestAnimationFrame`
- Keyboard input (WASD/arrows + Y/N for prompts + M for minimap)
- Mobile support: add on-screen virtual joystick + tap-to-interact
- Responsive: scale canvas to fill viewport
- All game state in a single JS object for easy save/load serialization
- No external dependencies — everything self-contained

---

## Bonus Features (If You Have Room)

1. **Random events:** "Health inspector shuts down your Food Truck for 15s", "Celebrity visits your Nightclub — 5× income for 20s", "Market crash — all income halved for 30s"
2. **Upgrades per zone:** Walk onto an owned zone and press U to upgrade (2× cost → 1.5× income). Max 5 upgrades per zone. Visual change on each upgrade (zone gets slightly larger/more detailed).
3. **Achievement system:** "First $1,000", "Own 10 zones", "Survive 5 raids", "Prestige 3 times" — shown as badges in a popup menu (press TAB).
4. **Day/night cycle:** Visual only — the map shifts between warm daytime colors and cool neon night colors on a 2-minute cycle.
5. **NPC pedestrians:** Simple dots that walk along roads for ambiance.

---

## Summary of the Core Loop

```
Manual hustle (click to earn)
    → Buy first passive zone (walk on it, auto-builds)
        → Stack passive income
            → Buy bigger zones (satisfying build animation)
                → Unlock new tiers & mechanics
                    → Deal with raids, rivals, reputation
                        → Build mega-structures
                            → Prestige & repeat faster
```

**The #1 priority is THE FEEL.** The moment you buy a zone — the cascade build, the ka-ching, the particles, the income tick-up — that moment needs to hit like a slot machine jackpot every single time. Everything else serves that dopamine loop.
