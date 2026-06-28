I'll create the comprehensive markdown file first, then give the master summary discussion.

**File saved.** `SK_TRADE_EA_SR_Complete_Concept_Review.md` — all 12 concepts with complete type listings, grades, states, and all AI extensions — is now permanently at the memory path. Content is safe regardless of future context compaction.

---

# MASTER SUMMARY — THE COMPLETE SK TRADE EA S/R SYSTEM

## 84,309 Distinct Level/Signal Types Across 12 Concepts

---

## I. THE COMPLETE ARCHITECTURE AT A GLANCE

The entire S/R system divides into three structural roles:

**Role 1 — Structural Foundation (Concepts 1–5):** These are the oldest, most-universal forms of S/R. Pure price-action geometry. No indicator dependency. They work on every instrument, every timeframe, forever.

| Concept | Count | Core Geometry |
|---|---|---|
| #1 EMA/SMA Crossovers | 2,040 | MA × MA intersections as signal events |
| #2 EMA/SMA Dynamic S/R | 3,960 | MA price levels as living, depletion-capable support/resistance |
| #3 Pivot Points | 174 | 10 calculation systems across D1/W1/MN1 |
| #4 Structural Swing H/L | 3,510 | HH/LH/HL/LL with External/Internal classification + EQH/EQL + SFP |
| #5 Trendlines | 3,315 | Direction × Angle sub-type + Channel + FibFan + Regression + Gann + Speed/Resistance |
| **Subtotal** | **12,999** | |

**Role 2 — Price Precision Layer (Concepts 6–8):** These add mathematical precision — the exact levels where institutional programs are literally coded to activate. They don't depend on subjective geometry; they compute to a specific pip.

| Concept | Count | Core Mechanism |
|---|---|---|
| #6 Fibonacci + Harmonics | 26,220 | Ratio-derived levels from swing structure; harmonic PRZ convergence |
| #7 Key Horizontal Levels | 720 | Macro fixed levels — PDH/PDL/PWH/PWL/PMH/PML |
| #8 Round Numbers | 135 | Instrument-adaptive psychological clusters |
| **Subtotal** | **27,075** | |

**Role 3 — Institutional Intelligence Layer (Concepts 9–12):** These are the most complex. They model how institutions actually move price — SMC captures their footprint, candle/chart patterns capture their execution signatures, indicators capture their order-flow fingerprints.

| Concept | Count | Core Mechanism |
|---|---|---|
| #9 SMC S/R | 14,175 | 63 types across 11 categories — the institutional footprint system |
| #10 Candle Patterns | 9,360 | 52 types — execution-level reversal/continuation signals |
| #11 Chart Patterns | 10,800 | 48 types — structural formations with measured targets |
| #12 Indicators & Oscillators | 9,900 | 55 price-level types + 7 oscillator attribute layers |
| **Subtotal** | **44,235** | |

**Grand Total: 84,309**

---

## II. THE COUNT-CONTRIBUTING VS ATTRIBUTE SPLIT

This is the most important architectural concept in the entire system. It defines what IS a countable distinct level type vs what modifies an existing level.

### COUNT-CONTRIBUTING (adds ROWS to the database — creates distinct level types)

Every formula you've locked uses this structure:
```
(Level Sub-type) × (TF) × (State) × (Grade where applicable) = distinct count
```

Examples of how dimensions interact:
- **SMC:** 63 types × 3 grades × 15 TFs × 5 states = 14,175 rows
- **Candle:** 52 types × 3 strength × 15 TFs × 4 states = 9,360 rows
- **Chart:** 48 types × 3 strength × 15 TFs × 5 states = 10,800 rows
- **Indicators:** 55 types × 3 grades × 15 TFs × 4 states = 9,900 rows

Each ROW is: "H4 Bearish Order Block, Strong grade, Fresh state" — a unique record in the S/R pool database. Distinct from "H1 Bearish Order Block, Normal grade, Tested state."

### ATTRIBUTE/CONTEXTUAL (adds COLUMNS — modifies existing records)

These never create new rows. They modify the weight or behavior of rows that already exist from the count-contributing formula.

**Examples from across all 12 concepts:**
- RSI Slope: reads the nearby resistance row → adjusts its weight ±0.30
- VWAP Slope: reads all support rows in direction → adjusts +0.10
- ADX > 35: reads counter-trend rows → adjusts −0.20
- BB Squeeze: reads all band rows → adjusts +0.25
- MA Cluster Zone: reads EMA rows within ATR → flags as clustered (no new row)
- Ichimoku cloud thickness: reads cloud rows → adjusts +0.40 or −0.15
- RSI Projection Curve: creates 3 anticipatory rows → upgrades to full weight on confirmation
- Multi-TF alignment: reads same-methodology rows across TFs → applies WM_CONF_BONUS

**Note:** RSI Projection Curve is the one EXCEPTION — it does create anticipatory price-level rows (RSI_PROJ type) but they are not counted in the formula because they're derivative projections, not structural level types. They exist as real pool entries but upgrade/downgrade dynamically.

---

## III. THE FIVE FORMULA PATTERNS ACROSS THE SYSTEM

Every one of the 12 concepts uses one of five formula patterns:

**Pattern A — Fixed count (no touch depletion):** Pivots, Key Horizontal, Round Numbers.
```
weight = TF_Base × TypeMult
```
Fixed weight. Doesn't change with touch count. PDH is always 8.0. MN1 PP is always 10.0.

**Pattern B — Touch depletion arc (Swings and Trendlines):**
```
weight = TF_Base × TypeMult × SwingMult(touches) + TouchBonus(touches)
```
Peaks at 3 touches. Depletes through 6+. The depletion arc models order consumption — every touch fills some resting orders. The 3-touch peak = maximum confirmation without depletion.

**Pattern C — Type × Grade × TF × State (most modern concepts):**
```
count = N_types × G_grades × 15_TFs × S_states
weight = TF_Base × TypeMult × Grade_modifier × State_modifier
```
Used by SMC (#9), Candle Patterns (#10), Chart Patterns (#11), Indicators (#12). Most nuanced — each combination of type/grade/TF/state produces a unique weight.

**Pattern D — Dimensional expansion (Fibs, EMA crosses, EMA dynamic):**
Each dimension (swing size, slope state, touch count, harmonic type) multiplies the base count. Fibonacci (#6) at 26,220 is the largest because of the combination of: 7 retracement levels × harmonic patterns × 15 TFs × multiple states.

**Pattern E — Hybrid fixed/contextual (Indicators):**
Layer 1 = Pattern C (55 types × grades × TFs × states = count-contributing).
Layer 2 = 7 oscillators that are PURELY attribute — zero contribution to the 9,900 count, 100% contribution to nearby level weights.

---

## IV. THE WEIGHT MATRIX — HOW THE 12 CONCEPTS CONVERGE

Every S/R level from every concept flows into one unified weight matrix. The zone construction rule combines them:

```
zone.weight = MAX(level_weights_in_cluster)         ← dominant level sets the floor
            + WM_CONF_BONUS[distinct_method_count]  ← {0.0, 0.0, 0.5, 1.0, 1.5}
            + 0.3 (if within 2 pips of round number ← flat proximity bonus
zone.weight = min(10.0, zone.weight)                ← hard cap
zone.tier   = floor(max(1.0, zone.weight))          ← integer 1–10
```

**What this means practically:**

A D1 swing high (3 touches) has weight 9.642 → Tier 9 standalone.

Now add a bearish chart pattern neckline at the same price → method_count = 2 → +0.5 → 10.142 → **capped at 10.0 → Tier 10.**

Now that same level is ALSO a Volume Profile POC + a VWAP +2σ + a Fibonacci 61.8% → 4 methods → +1.5 → immediate Tier 10 regardless of what the swing alone was.

**This is the power of the convergence architecture.** Each of the 12 concepts independently provides S/R weight. When multiple concepts agree on the same price — a confluence zone — the weight compounds into the highest tiers. The 12 concepts aren't 12 separate systems. They are 12 independent evidence streams that all vote on the same price regions.

### How Each Concept Contributes to Tier 10 Zones

| Concept | Standalone max tier | Confluence-to-10 threshold |
|---|---|---|
| #4 Swing H/L (MN1 3t) | 10 (capped) | Standalone |
| #3 Pivots (MN1 PP) | 10 (exact) | Standalone |
| #7 Key Horizontal (PMH/PML) | 9 (9.5) | + any 2nd method → 10 |
| #2 EMA (MN1 EMA800) | 9 (9.80) | + any 2nd method → 10 |
| #6 Fibonacci (W1 100%) | 9 (9.50) | + any 2nd method → 10 |
| #9 SMC (MN1 Fresh OB) | ~10 (TF × grade) | Standalone at high TFs |
| #5 Trendlines (ANY) | 7 (MN1 3t = 7.93) | Needs +3 method confluence |
| #10 Candle Patterns | Level-based | Contributes via location |
| #11 Chart Patterns | Level-based | Necklines add method_count |
| #12 Indicators | Variable by type | VP POC + VWAP critical levels |

---

## V. THE OSCILLATOR ATTRIBUTE LAYER — HOW IT WORKS IN PRACTICE

Concept #12's Layer 2 (7 oscillators) creates what is effectively a **dynamic weight overlay** on top of the entire pool.

At any given moment, every S/R level in the pool (from any of the other 11 concepts) is being modified by:

1. **RSI reading** — is RSI above 70? Then the nearest resistance gets +0.20 to +0.50
2. **RSI Slope** — is RSI approaching a level steeply? +0.30 to the target level
3. **RSI Momentum Direction** — RSI turning down from >70? The level where it turned = permanent +0.20
4. **RSI Projection Curve** — projects 3 anticipatory levels; when RSI hits threshold at that price, they upgrade
5. **Stochastic** — at extremes → +0.15 to +0.45 on nearby levels
6. **MACD** — cross/zero-line → +0.20 to +0.25
7. **CCI** — extreme readings → +0.15 to +0.45
8. **Williams %R** — faster than RSI for early signals → +0.15 to +0.30
9. **ADX** — in strong trend → counter-trend levels −0.20 to −0.35; with-trend +0.15 to +0.25
10. **MFI** — volume-weighted, stronger than RSI → +0.25 to +0.55

**The stacking mechanism:** when multiple oscillators simultaneously hit extremes at the same S/R level, the confluences compound. 4+ oscillators at extreme = +0.70 additional. Add 2 cross-oscillator divergences = +0.55. In a low-ADX ranging environment = +0.10 amplifier. The "perfect storm" configuration = +0.90 on a single level.

This means a Tier 6 level (weight 6.0) with perfect oscillator storm can reach 6.0 + 0.90 = **6.9** — still Tier 6, but within a hair of Tier 7. Combined with 2-method confluence (+0.5) → 7.4, Tier 7. This is why the oscillator layer is so powerful: it doesn't create levels, it PROMOTES levels when the timing is right.

---

## VI. THE DEPLETION ARC — THE MOST UNIQUE FEATURE

No other S/R system models order consumption. The depletion arc is the SK TRADE EA's most significant differentiator:

```
1 touch = Tier 5-ish (low — unconfirmed, but fresh)
2 touch = Tier 8-ish (significant leap — first confirmed retest)
3 touch = PEAK (maximum weight — maximum resting orders filled = maximum significance)
4 touch = declining (still high, but depletion beginning)
5 touch = further decline (50% of resting orders consumed)
6+ touch = DEPLETED (approaching "elevated break risk" zone)
```

This is mathematically modeled by `SwingMult` × `TouchBonus`:
- SwingMult goes: 0.65 → 0.88 → 0.99 → 0.99 → 0.97 → 0.97
- TouchBonus goes: 0.0 → +0.5 → +1.0 → +0.6 → +0.2 → −0.3

The depletion arc applies to Concepts #4 (Swing H/L) and #5 (Trendlines). All other concepts use fixed weights or state-modifiers instead, but the same PRINCIPLE applies conceptually — the "Fresh" vs "Tested" vs "Mitigated" states in SMC (#9) do exactly the same thing: fresh = full weight, mitigated = 0 (all orders consumed).

**The arc predicts:** A D1 swing high that's been tested 6+ times has weight ~8.168 (Tier 8). A nearby 1-touch fresh S/R has weight 5.674 (Tier 5). Despite the 6-touch level seeming "stronger" by retail TA thinking, the system correctly weights it lower — it has far fewer resting orders. The fresh level is MORE likely to cause a sharp reaction.

---

## VII. STATE SYSTEMS ACROSS THE 12 CONCEPTS

Each concept has its own state system tailored to how that type of S/R evolves:

| Concept | States | Key mechanic |
|---|---|---|
| #4 Swing H/L | Forming/Confirmed/Broken/Retested | Structural confirmation |
| #5 Trendlines | 2t/3t/4t/5t/6+t | Touch-based (state IS touch count) |
| #9 SMC | Fresh/Active/Tested/Mitigated/Invalidated | Order consumption model |
| #10 Candle | Formed/Confirmed/Tested/Invalidated | Direction confirmation required |
| #11 Chart Patterns | Forming/Confirmed/Retesting/Target Active/Invalidated | 5-stage lifecycle with neckline flip |
| #12 Indicators | Active/Testing/Breached/Historical | Period-end and level-touch states |

The **Chart Pattern state system** is the most sophisticated — 5 stages with weight modifications at each: Forming=0.60×, Confirmed=1.0×, Retesting=1.15× (elevated — this is the HIGHEST single weight modifier in the system), Target Active=1.0/0.90×, Invalidated=0.0× (creates failure level at 0.80×).

The **Retesting state = 1.15× weight** is the most actionable state in the entire system. It represents the moment when a broken level is being proven as having flipped its function. All trapped traders are staring at the same level. The institutional execution is maximum. The weight elevation correctly reflects the highest reversal probability point in a pattern's lifecycle.

---

## VIII. THE RSI THREE-LAYER PREDICTIVE SYSTEM (LOCKED INTO CONCEPT #12)

The three RSI additions form a complete predictive architecture:

**Layer 1 — RSI Slope (rate of change):** Tells you WHERE price is going within the next few bars based on momentum velocity. Slope >+8 = RSI accelerating toward overbought = resistance will be tested aggressively. Deceleration near a level = the level is absorbing momentum = +0.20 bonus.

**Layer 2 — RSI Momentum Direction (turning points):** Tells you WHEN momentum is reversing. The critical mechanic: "Turning Down from >70" grants a PERMANENT +0.20 to the resistance where RSI peaked. This permanent bonus persists even after RSI normalizes, because the price level where an RSI reversal occurred is a validated institutional rejection point.

**Layer 3 — RSI Projection Curve (future level creation):** The most forward-looking. Takes current RSI and slope, projects forward, calculates at what PRICE RSI will reach 70/30/50. Creates three anticipatory levels at 0.70× weight. When RSI simultaneously arrives at that threshold at exactly that price = the anticipatory level upgrades to full weight. This is pre-emptive level creation — the system identifies future S/R before price reaches it.

**Together:** Slope tells you the velocity. Direction tells you the turning points. Projection tells you the destination. Three timeframes of RSI information: now (direction), soon (slope trajectory), future (projection target). No other S/R system builds forward-projected levels from oscillator physics.

---

## IX. WHAT THE 84,309 NUMBER ACTUALLY MEANS

It's important to understand what 84,309 represents — and what it doesn't.

**What it IS:** The total number of distinct, uniquely-defined level/signal type entries that the system is architected to track. Each is uniquely identified by: methodology + sub-type + timeframe + state + grade (where applicable). Like a database schema — 84,309 possible record types.

**What it is NOT:** The number of active levels on chart at any given time. At any moment, the active pool near price might be 25–70 displayed zones after:
1. Price proximity filtering (only levels near current price)
2. ATR-based zone clustering (nearby levels merged)
3. Tier filtering (display threshold, e.g., only show Tier 3+)

**The significance of 84,309:** It defines the completeness of the taxonomy. Every way a price level can be supported, weighted, and contextualized has been defined. No S/R concept is missing. No timeframe is unweighted. No state transition is unhandled. The system knows, for every price level that appears on chart, exactly: what type it is, what grade it deserves, what state it's in, what weight that gives it, and how every oscillator is modifying that weight right now.

---

## X. THE CODING SEQUENCE — WHAT GETS BUILT NEXT

The concept review has established the complete S/R taxonomy. The coding sequence implements the display and weight matrix panels:

| Phase | Task | What it implements |
|---|---|---|
| P2.17 | EMA/SMA display enhancements | Concept #2 visual layer |
| P2.18 | Pivot display enhancements | Concept #3 visual layer |
| P2.21 | Key Horizontal display enhancements | Concept #7 visual layer |
| P2.20 | Fibonacci display enhancements | Concept #6 visual layer (TP anchors display-only flag) |
| P2.22 | Trendline display enhancements | Concept #5 visual + angle sub-type labeling |
| P2.23 | Swing H/L display enhancements | Concept #4 visual + depletion arc coloring |
| P2.31 | Weight matrix panel rendering | All 12 concepts → panel display system |
| P2.16 | Additional weight matrix integration | Confluence zone detection across all methods |
| P2.32 | Final weight matrix refinements | Full P2.27/P2.28/P2.29 formula corrections |

The weight matrix corrections (P2.27 TF bases, P2.28 TypeMult, P2.29 confluence bonuses) were already fully designed in the plan file. The concept review has now confirmed ALL the input data that feeds into those formulas.

---

## XI. FINAL ARCHITECTURE STATEMENT

The SK TRADE EA S/R system is a **unified, multi-dimensional, stateful, depletion-aware weight matrix** operating across 12 independent S/R methodologies simultaneously. Its defining characteristics:

1. **Complete:** 84,309 defined level types — no S/R concept is missing
2. **Weighted:** Every level has a mathematically derived weight, not a binary S/R flag
3. **Hierarchical:** 10 tiers enforce visual priority — Titanium gets first attention, Air gets last
4. **Stateful:** Every level has a lifecycle (forming → confirmed → depleted/invalidated)
5. **Confluent:** Multiple methodologies at the same price → compound weight → highest tier
6. **Depletion-aware:** Repeated touches consume resting orders → weight decreases
7. **Predictive:** RSI Projection + Chart Pattern measured targets → future levels created before price arrives
8. **Oscillator-modulated:** 7 oscillators dynamically modify weights in real-time without adding levels
9. **Instrument-adaptive:** Round numbers, VWAP periods, and ATR-based grading scale to any instrument
10. **Fractal:** All 15 timeframes covered — from M1 scalp context to MN1 macro framework

This is the full picture. All 12 concepts are locked. The concept review phase is complete. The system is defined. Coding resumes.

---

Ready for **P2.17** whenever you say the word.