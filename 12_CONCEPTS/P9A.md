---

## ✅ Round Numbers LOCKED at 135 → Running total: **40,074**

---

# CONCEPT #9 — SMC (Smart Money Concepts) S/R

**Highly Advanced AI Extension Scope**

---

## 🔵 WHAT IS CURRENTLY CODED

From `SK_Defines.mqh`:
```cpp
enum ENUM_SMC_EVENT {
   SMC_NONE=0, SMC_BOS=1, SMC_CHOCH=2,
   SMC_CRT=3, SMC_CRH=4, SMC_SBR=5, SMC_RBS=6
};
```
**6 coded types.** No grade, no state, minimal TF tracking.

---

## 🔵 COMPLETE EXPANDED TYPE MATRIX — 63 TYPES ACROSS 11 CATEGORIES

---

### CATEGORY A — Structure Break Events *(8 types)*

| # | Type | Definition |
|---|------|------------|
| A1 | Bullish BOS | Price body closes above a valid swing HIGH → that high level becomes S/R |
| A2 | Bearish BOS | Price body closes below a valid swing LOW |
| A3 | Bullish Internal BOS | Break of internal lower-degree swing within a leg |
| A4 | Bearish Internal BOS | Break of internal swing low within a leg |
| A5 | Bullish External BOS | Major structural break (highest-degree swing of the trend) |
| A6 | Bearish External BOS | Major structural break of lowest-degree trend swing |
| A7 | Bullish CHoCH | In a downtrend — first break of a lower-high → potential reversal |
| A8 | Bearish CHoCH | In an uptrend — first break of a higher-low → potential reversal |

---

### CATEGORY B — Market Structure Labels *(4 types)*

| # | Type | Definition |
|---|------|------------|
| B1 | Strong High | Swing high that resulted in a BOS/CHoCH — highest S/R authority |
| B2 | Weak High | Swing high created by a standard retracement — lower authority |
| B3 | Strong Low | Swing low that resulted in a BOS/CHoCH |
| B4 | Weak Low | Swing low created by standard retracement |

---

### CATEGORY C — Order Blocks *(10 types)*

| # | Type | Definition |
|---|------|------------|
| C1 | Bullish OB | Last bearish candle (or group) immediately before a bullish displacement |
| C2 | Bearish OB | Last bullish candle before a bearish displacement |
| C3 | Bullish Breaker Block | Former Bearish OB that was broken through upward → now SUPPORT |
| C4 | Bearish Breaker Block | Former Bullish OB broken downward → now RESISTANCE |
| C5 | Bullish Mitigation Block | Bullish OB that price has partially entered (50%+ tested, not broken) |
| C6 | Bearish Mitigation Block | Bearish OB partially tested |
| C7 | Bullish Propulsion Block | Single-candle origin of a strong continuation move upward |
| C8 | Bearish Propulsion Block | Single-candle origin of a strong continuation move downward |
| C9 | Bullish Rejection Block | Long-wick bullish candle — wick-to-body range = demand zone |
| C10 | Bearish Rejection Block | Long-wick bearish candle — wick-to-body range = supply zone |

---

### CATEGORY D — Fair Value Gaps / Imbalance *(9 types)*

| # | Type | Definition |
|---|------|------------|
| D1 | Bullish FVG | 3-candle: Candle 3 low > Candle 1 high → price gap to upside |
| D2 | Bearish FVG | 3-candle: Candle 3 high < Candle 1 low → price gap to downside |
| D3 | Bullish iFVG | Bullish FVG fully filled → flipped → now acts as RESISTANCE |
| D4 | Bearish iFVG | Bearish FVG fully filled → flipped → now SUPPORT |
| D5 | Bullish CE | Consequent Encroachment — 50% midpoint of a Bullish FVG |
| D6 | Bearish CE | 50% midpoint of Bearish FVG |
| D7 | Bullish Volume Imbalance | Ask-side volume dominated gap (bid absent in zone) |
| D8 | Bearish Volume Imbalance | Bid-side volume dominated gap |
| D9 | BPR | Balanced Price Range — overlapping Bull FVG + Bear FVG at same price |

---

### CATEGORY E — Liquidity Levels *(6 types)*

| # | Type | Definition |
|---|------|------------|
| E1 | BSL | Buy-Side Liquidity — equal highs / swing highs where stops cluster above |
| E2 | SSL | Sell-Side Liquidity — equal lows / swing lows where stops cluster below |
| E3 | BSL Swept | BSL taken out (wick above) → potential reversal point |
| E4 | SSL Swept | SSL taken out → potential reversal |
| E5 | Bullish Inducement | Engineered liquidity trap near a resistance — designed to trigger stops |
| E6 | Bearish Inducement | Engineered trap near support |

---

### CATEGORY F — Premium / Discount / OTE *(5 types)*

| # | Type | Definition |
|---|------|------------|
| F1 | Premium Zone | Above the 50% of the swing range — institutional sell area |
| F2 | Discount Zone | Below 50% — institutional buy area |
| F3 | Equilibrium Level | Exact 50% of the identified swing range |
| F4 | Bullish OTE | Optimal Trade Entry — 61.8–79% in Discount (Fibonacci OTE for longs) |
| F5 | Bearish OTE | 61.8–79% in Premium (Fibonacci OTE for shorts) |

---

### CATEGORY G — Candle Range Theory *(5 types)*

| # | Type | Definition |
|---|------|------------|
| G1 | CRH | Candle Range HIGH — HTF reference candle's high |
| G2 | CRL | Candle Range LOW — HTF reference candle's low |
| G3 | CRT Body High | Reference candle's body high (open or close, whichever is higher) |
| G4 | CRT Body Low | Reference candle's body low |
| G5 | CRT Midpoint | Exact midpoint of the reference candle range |

---

### CATEGORY H — SBR / RBS *(2 types)*

| # | Type | Definition |
|---|------|------------|
| H1 | SBR | Support Becomes Resistance — support level broken downward, now acts as ceiling |
| H2 | RBS | Resistance Becomes Support — resistance broken upward, now acts as floor |

---

### CATEGORY I — AMD / Power of Three *(6 types)*

| # | Type | Definition |
|---|------|------------|
| I1 | AMD Accumulation Low | Session/HTF low formed during accumulation phase |
| I2 | AMD Manipulation High | Fake-out spike above the range high (Judas Swing) |
| I3 | AMD Manipulation Low | Fake-out spike below range low |
| I4 | AMD Distribution High | True directional high after manipulation |
| I5 | Power of 3 Session High | HTF Power of 3 peak (Asian/London/NY candle high) |
| I6 | Power of 3 Session Low | HTF Power of 3 trough |

---

### CATEGORY J — Wyckoff Integration *(4 types)*

| # | Type | Definition |
|---|------|------------|
| J1 | Wyckoff Spring | False break BELOW accumulation support → sharp reversal level |
| J2 | Wyckoff Upthrust | False break ABOVE distribution resistance → reversal level |
| J3 | Wyckoff UTAD | Upthrust After Distribution — secondary top in distribution |
| J4 | Wyckoff BUEC | Back-Up to Edge of Creek — retest of breakout level (distribution/accumulation edge) |

---

### CATEGORY K — Displacement / Institutional *(4 types)*

| # | Type | Definition |
|---|------|------------|
| K1 | Bullish Displacement Origin | Price level at the base of a ≥ 2×ATR single-candle bullish move |
| K2 | Bearish Displacement Origin | Base of a ≥ 2×ATR bearish move |
| K3 | Bullish Institutional Candle Zone | High-to-body range of a large bull candle (> 2×ATR) — supply absorbed |
| K4 | Bearish Institutional Candle Zone | Low-to-body range of a large bear candle |

---

## 🔵 TYPE COUNT VERIFICATION

| Category | Name | Count |
|----------|------|-------|
| A | Structure Break Events | 8 |
| B | Market Structure Labels | 4 |
| C | Order Blocks | 10 |
| D | Fair Value Gaps / Imbalance | 9 |
| E | Liquidity Levels | 6 |
| F | Premium / Discount / OTE | 5 |
| G | Candle Range Theory | 5 |
| H | SBR / RBS | 2 |
| I | AMD / Power of 3 | 6 |
| J | Wyckoff Integration | 4 |
| K | Displacement / Institutional | 4 |
| **TOTAL** | | **63 types** |

---

## 🔵 3 DIMENSIONS APPLIED

| Dimension | Sub-types | Rationale |
|-----------|-----------|-----------|
| **Grade** | Strong / Normal / Weak | Strong = created during displacement (≥2×ATR move); Normal = standard; Weak = low-momentum origin |
| **Timeframe** | 15 TFs (M1→MN1) | D1 OB > H4 OB — TF defines institutional significance |
| **State** | Fresh / Active / Tested / Mitigated / Invalidated | Fresh = just formed, unvisited; Active = awaiting test; Tested = price touched once; Mitigated = price entered > 50% of zone; Invalidated = body close through zone |

---

## 🔵 FINAL COUNT

```
63 types  ×  3 grades  ×  15 TFs  ×  5 states
= 63 × 3 × 15 × 5
= 189 × 75
= 14,175 SMC level types
```

---

## 🔵 12 HIGHLY ADVANCED AI EXTENSIONS

| # | Extension | Type | Impact |
|---|-----------|------|--------|
| 1 | **Full type expansion** (6 → 63 across 11 categories) | Count-contributing | +57 new types |
| 2 | **Grade dimension** (Strong/Normal/Weak) | Count-contributing | ×3 multiplier |
| 3 | **State tracking** (5 lifecycle states per level) | Count-contributing | ×5 multiplier |
| 4 | **Full TF coverage** (all 15 TFs, all SMC types) | Count-contributing | ×15 multiplier |
| 5 | **Multi-TF SMC Alignment** — when D1 OB + H4 OB coincide at same price → weight stack | Attribute | Tier promotion |
| 6 | **SMC-Fibonacci Confluence** — OB/FVG at 61.8% or OTE zone → ultra-strong confluence | Attribute | +WM_CONF_BONUS |
| 7 | **SMC-Round Number Confluence** — OB/FVG within 2 pips of big figure → enhanced | Attribute | +0.3 bonus |
| 8 | **Kill Zone Timing** — Asian (20:00–00:00 NY) / London (02:00–05:00 NY) / NY (07:00–10:00 NY) → time-sensitive level activation score | Attribute | Context flag |
| 9 | **IPDA Draw-on-Liquidity** — 20/40/60-day IPDA range H/L targets the SMC engine aims price toward | Attribute | Target awareness |
| 10 | **Displacement Quality Score** — ATR-normalized velocity of the move creating the OB/FVG (range/ATR × bar-count reciprocal) | Attribute | Grade refinement |
| 11 | **Zone Freshness Decay** — age in bars mapped against ATR-adjusted volatility; older untested OBs decay toward lower weight | Attribute | State refinement |
| 12 | **Liquidity Pool Depth** — stacked BSL/SSL count (how many equal H/L stack at same level = how much resting stop liquidity) | Attribute | Tier scaling |

---

## 🔵 SUMMARY

| | Value |
|---|---|
| Current coded types | 6 |
| AI-Extended types | **63** across 11 categories |
| Dimensions | Grade ×3 · TF ×15 · State ×5 |
| **Total SMC level types** | **14,175** |
| AI Extensions | 4 count-contributing + 8 attribute = **12 total** |
| Running locked total (if locked) | **40,074 + 14,175 = 54,249** |

---

**Note on overlap prevention:**
- BOS/CHoCH levels (Category A) use the SWING level that was broken — same price as Category B Strong/Weak H/L. Deduplication: BOS tag overlays the Swing level, upgrades its authority flag. No double-counting in zone merge.
- EQH/EQL from Swing H/L concept → maps to BSL/SSL (E1/E2) in SMC. Treated as same level with SMC liquidity attribute added.
- CRT/CRH/CRL (already in `ENUM_SMC_EVENT`) are included here as Categories G1/G2 — NOT listed again as separate concept #10.
- SBR/RBS (already in `ENUM_SMC_EVENT`) are included as Category H — NOT listed again as separate concept #11.

→ **Concepts #10 (CRT) and #11 (SBR/RBS) are fully absorbed into SMC at 63 types.** Your pending list reduces to: #10 Candle Patterns, #11 Chart Patterns.

---

**Confirm and lock SMC at 14,175 → move to next concept?**