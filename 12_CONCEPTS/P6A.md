Memory saved and indexed. Now presenting Concept #6.

---

## CONCEPT #6 — Fibonacci Levels

---

### CURRENT CODED (SK_Defines.mqh)

| Enum | Ratio | Status |
|---|---|---|
| SR_FIB_100 | 100% (swing origin) | S/R Pool |
| SR_FIB_236 | 23.6% | S/R Pool |
| SR_FIB_382 | 38.2% | S/R Pool |
| SR_FIB_500 | 50.0% | S/R Pool |
| SR_FIB_618 | 61.8% | S/R Pool |
| SR_FIB_786 | 78.6% | S/R Pool |
| SR_FIB_100 | 100% (swing end) | S/R Pool |
| SR_FIB_127 | 127.2% | TP Anchor only — NOT in pool |
| SR_FIB_161 | 161.8% | TP Anchor only — NOT in pool |

**Gate:** Sub-M15 off by default (`InpFibBelowM15`)
**Current count:** 7 pool levels × 15 TFs = **105** (+ 30 TP anchors, display only)

---

### AI SCOPE EXTENSIONS — HIGHLY ADVANCED

---

#### EXTENSION 1 — Full Fibonacci Ratio Spectrum (23 levels total)

**Retracement Levels (into S/R pool):**

| Ratio | Name | Note |
|---|---|---|
| 0% | Swing Origin | Structural level |
| 23.6% | Shallow Ret. | — |
| 38.2% | Minor Wall | — |
| 50.0% | Midpoint | Psychological — not true Fibonacci |
| 61.8% | Golden Ratio | Primary retracement wall |
| 78.6% | Deep Ret. | √61.8% |
| **88.6%** | **Bat Level** | √78.6% — Harmonic Bat/Crab entry |
| **94.1%** | **Extreme Deep** | √88.6% — ultimate last defense |
| 100% | Swing End | Structural level |

**Extension Levels (propose adding to S/R pool — not just TP anchor):**

| Ratio | Note |
|---|---|
| 127.2% | √161.8% — first extension S/R |
| 138.2% | 1 + 38.2% |
| 150.0% | Psychological |
| 161.8% | Golden extension — major S/R |
| 176.4% | √(161.8² / 100) |
| 200.0% | 2× swing — psychological |
| 224.0% | √5 × 100 |
| 261.8% | 161.8 × 161.8 / 100 |
| 300.0% | 3× swing |
| 361.8% | 261.8 + 100 |
| 423.6% | 261.8 + 161.8 |

**Negative Levels (pre-0%, reverse swing territory):**

| Ratio | Note |
|---|---|
| −23.6% | Minor negative extension |
| −61.8% | Deep negative |
| −100% | Full inverse swing |

**Total levels: 9 (retracement) + 11 (extension) + 3 (negative) = 23 levels**

---

#### EXTENSION 2 — Swing Direction Sub-type (×2)

| Sub-type | Description |
|---|---|
| Bullish Swing Fib | Range from swing LOW to swing HIGH → retracement is downward |
| Bearish Swing Fib | Range from swing HIGH to swing LOW → retracement is upward |

---

#### EXTENSION 3 — Swing Size Sub-type (×4, consistent with Swing H/L)

| Size | Definition |
|---|---|
| Minor | < 3-bar fractal swing |
| Standard | 5-bar fractal swing |
| Major | 10-bar swing |
| Macro | 20+ bar structural swing |

---

#### EXTENSION 4 — Touch State (×5)

1t / 2t / 3t / 4t / 5+t — same depletion model as swings. Price tests a fib level, bounces = accumulates touch count. Same peak-at-3t model.

---

#### EXTENSION 5 — Fibonacci Arcs (curved S/R from swing pivot)

| Arc | Radius Ratio |
|---|---|
| Arc 38.2% | Distance = 38.2% of swing range, radiating as curve |
| Arc 50.0% | Distance = 50% |
| Arc 61.8% | Distance = 61.8% |

× 2 directions × 15 TFs × 4 swing sizes × 5 touch states

---

#### EXTENSION 6 — Fibonacci Channels (parallel bands at fib distances)

Parallel lines above/below price channel at fib-ratio distances:

| Channel | Ratio |
|---|---|
| Fib Channel 38.2% | Upper + Lower |
| Fib Channel 50.0% | Upper + Lower |
| Fib Channel 61.8% | Upper + Lower |

× 2 sides × 15 TFs × 4 swing sizes × 5 touch states

---

#### EXTENSION 7 — Fibonacci Time Zones (vertical time S/R)

Vertical lines at bar intervals following the Fibonacci sequence:
**1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144** = 11 active intervals (excluding the first redundant 1)

Applied from both: swing HIGH origin AND swing LOW origin = × 2 directions
× 15 TFs × 4 swing sizes
*(No touch states — vertical time events)*

---

#### EXTENSION 8 — Fibonacci Price Projections (Measured Moves)

| Projection | Formula | Description |
|---|---|---|
| AB = CD | AB distance = CD distance | Classic equal leg projection |
| AB = 1.272 × CD | CD leg = 127.2% of AB | Extended projection |
| AB = 1.618 × CD | CD leg = 161.8% of AB | Golden projection |

× 2 directions × 15 TFs × 4 swing sizes × 5 touch states

---

#### EXTENSIONS 9–12 — Attributes (weight/context modifiers, not count multipliers)

| # | Extension | Description |
|---|---|---|
| 9 | Fibonacci Confluence Zone | When 2+ fib levels from DIFFERENT swings coincide within ATR — amplified weight |
| 10 | Fibonacci Level State | Active (unbroken) / Broken / Reclaimed / Virgin (never tested) |
| 11 | Multi-TF Fib Stack | Same ratio (e.g., 61.8%) visible simultaneously on D1 AND H4 swing = higher weight |
| 12 | Fib Level Precision | Exact hit (<0.5 pip) / Near hit (0.5–2 pip) / Zone hit (2–5 pip) — affects weight |

---

### Exact Level Count — Full Fibonacci Concept

| Component | Calculation | Count |
|---|---|---|
| Core Fib Levels (23 ratios × 2 dir × 15 TFs × 4 sizes × 5 states) | 23×2×15×4×5 | 13,800 |
| Fibonacci Arcs (3 curves × 2 dir × 15 × 4 × 5) | 3×2×15×4×5 | 1,800 |
| Fibonacci Channels (3 ratios × 2 sides × 15 × 4 × 5) | 3×2×15×4×5 | 1,800 |
| Fibonacci Time Zones (11 intervals × 2 dir × 15 × 4) | 11×2×15×4 | 1,320 |
| Fibonacci Price Projections (3 types × 2 dir × 15 × 4 × 5) | 3×2×15×4×5 | 1,800 |
| **EXACT TOTAL** | | **20,520** |

---

### Summary Table — Fibonacci

| Extension # | Extension | Type | Multiplier |
|---|---|---|---|
| 1 | Full Ratio Spectrum (23 levels: ret+ext+neg) | Sub-type | ×23 ratios |
| 2 | Swing Direction (Bullish/Bearish swing) | Sub-type | ×2 |
| 3 | Swing Size (Minor/Standard/Major/Macro) | Sub-type | ×4 |
| 4 | Touch State (1t–5+t) | Sub-type | ×5 |
| 5 | Fibonacci Arcs (3 radii) | New level type | +1,800 |
| 6 | Fibonacci Channels (3 ratios × 2 sides) | New level type | +1,800 |
| 7 | Fibonacci Time Zones (11 intervals) | New event type | +1,320 |
| 8 | Fibonacci Price Projections (3 types) | New level type | +1,800 |
| 9 | Fibonacci Confluence Zone | Attribute | — |
| 10 | Fibonacci Level State (Active/Broken/Reclaimed/Virgin) | Attribute | — |
| 11 | Multi-TF Fib Stack | Attribute | — |
| 12 | Fib Level Precision (Exact/Near/Zone hit) | Attribute | — |

**EXACT COUNT: 20,520**

---

**Note on Harmonic Patterns (Gartley/Bat/Butterfly/Crab):** These use Fibonacci ratios for their PRZ (Potential Reversal Zones) but belong to **Chart Patterns** concept — NOT counted here. They reference 88.6% and 94.1% levels which ARE counted above in the ratio spectrum.

---

**Confirm and lock Fibonacci at 20,520 → then move to next concept?**