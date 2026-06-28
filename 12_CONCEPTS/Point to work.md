
---

### 12-CONCEPT COVERAGE TABLE

| # | Concept | Locked Count | Phase 2 Covers | Gap | Phase Assignment |
|---|---------|-------------|----------------|-----|-----------------|
| 1 | EMA/SMA Crossovers | 2,040 + 12 ext | Golden Cross +15 (P2.22) | EMA Rainbow Stack, MA Squeeze, MA Slope Direction, Triple MA Align, MA Cascade Event, EMA Ribbon Width | Cross types → Phase 3; MA slope → **Add to Phase 2 now** |
| 2 | EMA/SMA Dynamic S/R | 3,960 | 240 levels (120+120, flat weights) | MA Slope sub-type ×3, Bounce Touch State ×5, Flip/Retest events, EMA-SMA Same-Period Confluence, MA Cluster | Slope + Confluence → **Add to Phase 2 now**; Full sub-types → Phase 3 |
| 3 | Pivot Points | 174 (10 systems) | 27 (Classic 21 + KeyH 6) | CPR, Camarilla, Woodie's, Fib Pivot, DeMark, Mid-Pivots, Intraday, Session, Period Opens | CPR + Period Opens → **Add to Phase 2 now**; Camarilla/Woodie's → Phase 3 |
| 4 | Structural Swing H/L | 3,510 | ~30 (basic H/L with touch) | HH/LH/HL/LL classification, EQH/EQL liquidity pools, Fractal Size ×4, SFP Bull/Bear, Swing decay | Full classification → Phase 3; EQH/EQL → Phase 3 |
| 5 | Trendlines | 3,315 | 75 (basic 4-dir × 3-angle × 5-touch per TF subset) | Channel lines, Fib Fan, Regression Channel, Gann Fan, Speed Resistance | Full sub-types → Phase 3 |
| 6 | Fibonacci + Harmonics | 26,220 | 70 in pool (7 levels × 10 TFs) | Harmonics (XABCD: Gartley/Bat/Butterfly/Crab/Shark), Fib Fan, Arcs, Time Zones | Harmonics → Phase 3 |
| 7 | Key Horizontal | 720 (11 AI categories) | 6 (PDH/PDL/PWH/PWL/PMH/PML) | Session H/L/Open (AS/LS/NY), Gap levels, HOD/LOD, Intraday opens, 11 AI categories | Session levels → **Add to Phase 2 now**; Full 11 AI categories → Phase 3 |
| 8 | Round Numbers | 135 (6 sizes) | 45 (3 sizes: 25/50/100 pip) | 500-pip, 1000-pip, 10000-pip (instrument-adaptive) | **Add to Phase 2 now** |
| 9 | SMC S/R | 14,175 (63 types, 11 categories) | ~18 coded types | Full 63-type system | **Deferred to Phase 3** (Bug-1) |
| 10 | Candle Patterns | 9,360 (52 types) | ~9 types coded | 43 additional types | Phase 3 |
| 11 | Chart Patterns | 10,800 (48 types × 3 grades × 15 TF × 5 states) | ~8 types coded | 40 additional types | Phase 3 |
| 12 | Supportive Indicators & Oscillators | 9,900 (55 types + 7 oscillators) | RSI/ADX basic scoring | BB bands, VWAP, Volume Profile, Ichimoku, SAR, Supertrend; **RSI Slope/Direction/Projection** | RSI Slope+Direction → **Add to Phase 2 now**; BB/VWAP/Ichimoku → Phase 3 |

---

### WHAT GETS ADDED TO PHASE 2 NOW

These 6 upgrades directly touch files already being edited in Phase 2. Deferring them means coming back to these exact same files in Phase 3 for 1-liner changes — wasteful.

**Add-1 — MA Slope Direction modifier in SRWM** (Concept #2, Ext #1)
- In `_BuildEMALevels()` + `_BuildSMALevels()`: compute slope = `(ema_now - ema_5bars_ago) / 5`
- Classify: `Rising` (slope > +0.3pip/bar), `Flat` (±0.3), `Falling` (< -0.3)
- Weight modifier: Rising support/falling resistance = +0.10; flat = 0.0; counter-direction (falling support / rising resistance) = −0.05
- Label suffix: `"H4 EMA200 ↗ ⚙️"` vs `"H4 EMA200 → ⚙️"` vs `"H4 EMA200 ↘ ⚙️"`

**Add-2 — EMA-SMA Same-Period Confluence zones** (Concept #2, Ext #4)
- In SRWM: after building EMA + SMA levels, scan for EMA and SMA of same period on same TF within ATR×0.3
- If found: merge into one zone, add +0.5 confluence bonus, label `"H4 EMA+SMA200 ⚙️"`
- Method bit: `bit4 | bit5` = EMA+SMA combined

**Add-3 — CPR + Period Opens in CalcMacroPivots** (Concept #3)
- Central Pivot Range (TC/CP/BC): `CP = (H+L+C)/3`, `TC = (PP-BC)+PP`, `BC = (H+L)/2` — for D1/W1/MN1 = 9 levels
- Period Opens (DO/WO/MO): prior D1/W1/MN1 `rates[cnt-2].open` = 3 levels
- New SR types: `SR_CPR_TC`, `SR_CPR_CP`, `SR_CPR_BC`, `SR_PERIOD_OPEN_D1`, `SR_PERIOD_OPEN_W1`, `SR_PERIOD_OPEN_MN1`
- Weights: CPR BC/TC = 7.5 (fixed), CPR CP = 8.5 (fixed), Period Opens = 7.0 (fixed)

**Add-4 — Round Number 6-size expansion** (Concept #8)
- Add 500-pip (weight 7.5) and 1000-pip (weight 8.5) to `_BuildRoundLevels()`
- Instrument-adaptive: for XAUUSD/indices where 25-pip is noise, skip sub-100-pip rounds
- Keep 100-pip=6.0, 50-pip=5.0, 25-pip=4.0, new 500-pip=7.5, 1000-pip=8.5

**Add-5 — Session Key Horizontal levels** (Concept #7 AI categories)
- Add Asian Session H/L, London Session H/L, New York Session H/L = 6 more levels to CalcMacroPivots
- New SR types: `SR_KEYH_AS_H`, `SR_KEYH_AS_L`, `SR_KEYH_LS_H`, `SR_KEYH_LS_L`, `SR_KEYH_NY_H`, `SR_KEYH_NY_L`
- Fixed weights: Session H/L = 6.5 (Stone tier — intraday significance)

**Add-6 — RSI Slope + Direction as S/R weight modifiers** (Concept #12 locked additions)
- In SRWM `_ComputeTier1()` or a new `_ApplyOscillatorModifiers()` function:
- For each WMLevel, check RSI state from AnalysisEngine for that TF
- RSI Slope modifier: `if RSI decelerating near zone → +0.15 to +0.30 weight bonus`
- RSI Direction modifier: `if RSI rising + level is support → +0.10; if RSI falling + support → −0.05`
- RSI turning point at 70/30: permanent +0.20 to zone where turn occurred (upgrade its weight floor)

---

### WHAT STAYS DEFERRED

| Concept | Deferred To |
|---------|-------------|
| Full HH/LH/HL/LL swing classification | Phase 3 |
| EQH/EQL liquidity pools | Phase 3 |
| SFP Bull/Bear patterns | Phase 3 |
| TL Channel lines, Fib Fan, Regression Channel, Gann Fan | Phase 3 |
| Harmonics (XABCD) | Phase 3/4 |
| Full SMC 63 types | Phase 3 (Bug-1 already deferred) |
| CPR Camarilla / Woodie's / DeMark / Fib Pivot | Phase 3 |
| Candle Patterns 52 types | Phase 3 |
| Chart Patterns 48 types | Phase 3 |
| BB Bands / VWAP / Volume Profile / Ichimoku / SAR / Supertrend | Phase 3 |
| RSI Projection Curve (anticipatory price levels) | Phase 3 |
| EMA Rainbow Stack / MA Squeeze / MA Ribbon Width | Phase 3 |

---

### UPDATED PHASE 2 IMPLEMENTATION SEQUENCE

```
PART A (Done):  SK_Defines + SK_SREngine + SK_SRWeightMatrix — P2.23 KeyH types ✅

PART A-ext:     SK_Defines (6 new SR types for CPR + Period Opens + Session KeyH)
                SK_SREngine (CalcMacroPivots + CPR + Period Opens + Session H/L)
                SK_SRWeightMatrix (_BuildRoundLevels 500/1000-pip expansion)

PART B:         P2.22 Golden Cross (after EMA vs SMA confirmation)
                SK_DataEngine + SK_ConfidenceEngine

PART B-ext:     SRWM _BuildEMALevels/_BuildSMALevels — MA Slope Direction modifier
                SRWM — EMA-SMA Same-Period Confluence detection
                SRWM — _ApplyOscillatorModifiers() RSI Slope + Direction

PART C:         Bug fixes (Bug-2/3/4/5/6) — UNCHANGED

PART D:         P2.16 Fib Phase Label — UNCHANGED

PART E:         UIManager chart vis upgrades — UNCHANGED
```

---
Let me read all memory files and the verification guide to compile a complete picture before answering.

Here is the complete structured pending task register — everything from Phase 1 start to the current state, organized by priority tier.

---

## SK TRADE EA — MASTER PENDING TASK REGISTER
### As of 2026-06-06 | Post-Session dd45d14f + current session edits

---

## ✅ COMPLETED (confirmed done — do not re-implement)

### Phase 1 Foundation (v2.0–v2.2)
- I1–I15: All 15 original issues resolved (TF independence, async init, progress bar, ghost object cleanup, header session inline, button routing, ActFromName→DispatchAction 3-chain)
- 9-tab glassmorphism dashboard with sub-tab navigation
- MA HUB: 15TF×8period EMA/SMA matrix + DELTA MAP heatmap + FIB overview sub-tabs
- SMC tab: BOS/CHoCH/OB/FVG per TF
- Signal tab: 14 sub-tabs, full lifecycle FORMING→EXPIRED, popup gate
- Execution: 4 modes, popup countdown, MarketOrderRiskSL()
- Virtual P&L + CSV Logger + Telegram skeleton

### v2.6 Second-batch fixes (B1–B6)
- B1: Abnormal termination OnDeinit reason=1 guard
- B2: CalcPip normalization (XAU/XAG ×10 correction, replaces ~15 inline formulas)
- B3: Lot/SL/TP manual edit + safety limits
- B4: One-click opening 3 positions → single order when tp2=tp3=0
- B5: Mode-specific risk% automation, ATR fallback sizing
- B6: STOP/LIMIT editable fields (OBJ_EDIT), HandleEditEnd, per-level lots

### P2.1–P2.15 Weight Matrix Foundation
- P2.1: CalcSwingLevels 200-bar lookback
- P2.2: Touch depletion arc (peak +1.0 at 3t, penalty −0.3 at 6+t)
- P2.3–P2.4: MAX_SR_POOL→3000, zone merge capacity
- P2.5: Sub-M15 TL gate (InpTLBelowM15)
- P2.6: TL touch counting (±1.5 pip tolerance)
- P2.7: TL angle in degrees (Shallow/Normal/Steep)
- P2.8: Body-close TL invalidation (wick-only = NOT invalidated)
- P2.9+P2.12: CalcMacroPivots unconditional (D1/W1/MN1 PP+R/S 1–3, PDH/PDL/PWH/PWL/PMH/PML)
- P2.13: Sub-M15 Fib gate (InpFibBelowM15)
- P2.14: Fib retracements (0%–100%) in S/R pool
- P2.15: Fib extensions (>100% / negative) stored as TP⚓ display only, excluded from pool
- 10-tier weight system (💎 Titanium→💨 Air) — floor(weight), emoji labels, _ClassColor()
- SK_SRWeightMatrix: WM_WEIGHT_CAP=10.0, _SwingMult, _TouchBonus, _ClassLabel, _TierName, _ClassColor

### Current Session Additions (Part B-ext + Part E)
- E.1 SRWM: `GetTierColor(double w)` public wrapper delegating to `_ClassColor()`
- E.2–E.4 UIManager: `m_vis_keyh`/`m_vis_emas` member flags, `_TierColor()` inline bridge, constructor init
- E.5 UIManager: `RefreshChartVisuals()` now calls `_ChartVis_KeyH()` + `_ChartVis_EMA()`
- E.6 UIManager: `DispatchAction` VIS_KEYH_TOG / VIS_EMA_TOG handlers
- E.7 UIManager: Config tab Row 4 KEY-H LINES / EMA/SMA toggle buttons
- E.8 UIManager: `_ChartVis_SR()` upgraded to SRWM WMLevel primary path (tier-colored, width-graded, skips is_ema/is_sma) with CSREngine fallback
- E.9–E.10 UIManager: `RenderSRZonePanel()` P2.30 — both R and S zone blocks use `GetTierColor(zone_weight)` for `tier_c`
- E.11 UIManager: `_ChartVis_KeyH()` — PDH/PDL (w=8.0, DodgerBlue, width=3), PWH/PWL (w=9.0, Orange), PMH/PML (w=9.5, Orange)
- E.11 UIManager: `_ChartVis_EMA()` — iterates SRWM is_ema/is_sma levels, STYLE_DASH for EMA, STYLE_DOT for SMA, tier-colored, tier-graded width
- B-ext UIManager: GC Status Panel in MA CROSS sub-tab — D1 SMA50×200 + EMA50×200 active status, direction, CE bonus display (+15/+30)
- Bug-2: Partial selection sort O(K×N) replacing O(N²) in `_CollectBarriers()` (K=10, N≤440)
- Bug-5: Wave restart override (`can_start = true` when `new_level.weight > m_wave_origin_of × 1.2`)
- Bug-6: Distance-weighted OB scoring (`dist_factor = 1.0 − MathMin(1.0, best_dist/(2×ATR))`)
- P2.22 / DataEngine: Golden/Death Cross dual-track (SMA50×200 + EMA50×200), `gc_active`/`ema_gc_active` via 4-hour window, 4 accessor methods
- Part D / SREngine: `GetFibPhase(int tf)` — 5-phase string (EXPANSION/CONTINUATION/RETRACEMENT/DEEP RETRACE/REVERSAL)
- Bug-4 (SK_TradeEA.mq5 line 815): `HistorySelect` guard confirmed pre-existing, no change needed

---

## 🔴 CRITICAL BUGS — Implement immediately after P2.32

### BUG-5D — Mouse click penetration through dashboard
- **Symptom:** Clicking dashboard controls selects chart objects underneath (trade lines, positions, HLines)
- **Root cause:** Dashboard rectangle objects are not consuming click events; `CHARTEVENT_OBJECT_CLICK` still propagates to chart layer after dashboard button handler runs
- **Fix:** In `OnChartEvent()`, after detecting click is within dashboard bounds (`lparam >= m_x && lparam <= m_x+BENTO_W && dparam >= m_y && dparam <= m_y+BENTO_H`), call `ChartSetInteger(0, CHART_MOUSE_SCROLL, false)` during interaction OR add a transparent OBJ_RECTANGLE at top Z-order covering the full dashboard area with `OBJPROP_SELECTABLE=false` and `OBJPROP_BACK=false` to intercept
- **Files:** `SK_UIManager.mqh` (OnChartEvent bounds guard + absorber object)

### BUG-5E — DD lock re-fires immediately after password reset
- **Symptom:** Correct password "SKTRADE" accepted → trading unlocks → re-locks on next OnTimer tick (50–100ms later) because DD% still above threshold
- **Root cause:** `UpdateDDTrack()` recalculates `m_dd_pct` every tick from `(m_dd_peak − AccountInfoDouble(ACCOUNT_EQUITY)) / m_dd_peak`; no baseline reset on unlock; `IsDDLocked()` immediately re-triggers
- **Fix:** On password accept → call `m_dd_baseline = AccountInfoDouble(ACCOUNT_EQUITY)` (resets peak to current equity) AND set `m_dd_reset_immunity_ticks = 10` (skip re-lock for ~1 second). During immunity window, `UpdateDDTrack()` returns early without updating `m_dd_locked`
- **Files:** `SK_TradeEA.mq5` (password accept handler after `InpDDResetCode` match), `SK_UIManager.mqh` (DD tracking + immunity counter)

---

## 🟡 P2.16–P2.32 REMAINING — Implementation order (per plan document)

### STEP 1 — P2.27: TF Base Weight Corrections ← NEXT CODING TARGET
**4 values wrong in current `SK_SRWeightMatrix.mqh`:**
| TF | Current | Target | Delta |
|----|---------|--------|-------|
| M6 | 2.2 | **2.3** | +0.1 |
| M30 | 4.0 | **3.5** | −0.5 |
| H8 | 8.0 | **7.5** | −0.5 |
| H12 | 8.5 | **8.0** | −0.5 |

Full 15-TF target: M1=1.0, M3=1.5, M5=2.0, M6=2.3, M10=2.5, M15=3.0, M30=3.5, H1=5.0, H2=5.5, H4=7.0, H8=7.5, H12=8.0, D1=9.0, W1=9.5, MN1=10.0  
**File:** `SK_SRWeightMatrix.mqh` → `WM_TF_BASE[]` or `_TFBase()` lookup

### STEP 2 — P2.28: TypeMult Table + SwingMult Applied to TLs
**Two sub-changes:**
1. Swing H/L: multiply base weight by 0.97 TypeMult BEFORE applying `_SwingMult(strength)`. Currently code applies SwingMult directly on raw TF base → misses the 0.97 Swing type factor.
2. Trendlines: currently use flat 0.70 multiplier but IGNORE touch count. Must apply `_SwingMult(strength)` to trendlines too — same depletion arc as swings (peak at 3t, decay at 6+t).

Full TypeMult table (key values): PP=1.00, Pivot R1/S1=0.97, Pivot R2/S2=0.90, Pivot R3/S3=0.82, Swing=0.97, TL=0.70, EMA9=0.58, EMA21=0.70, EMA34=0.72, EMA50=0.78, EMA80=0.82, EMA100=0.88, EMA200=0.93, EMA800=0.98, SMA9=0.55, SMA21=0.62, SMA34=0.70, SMA50=0.78, SMA80=0.82, SMA100=0.88, SMA200=0.95, SMA800=0.95, Fib0%=1.00, Fib23.6%=0.55, Fib38.2%=0.75, Fib50%=0.72, Fib61.8%=0.84, Fib78.6%=0.70, Fib100%=1.00  
**File:** `SK_SRWeightMatrix.mqh` → `_TypeMult()` function

### STEP 3 — P2.29: Confluence Bonus + Round# Proximity Bonus
**Currently:** Only touch bonus exists. Zone where Swing+Pivot+EMA all agree gets no credit.  
**Target bonus table:**

| Condition | Bonus |
|-----------|-------|
| 1 method only | +0.0 |
| 2 methods agree | **+0.5** |
| 3 methods agree | **+1.0** |
| 4+ methods agree | **+1.5** |
| Within 2 pips of round number | **+0.3** (stackable) |

- Bonus detection: method count from `WMLevel.conf_count` or `method_bit` popcount
- Round# proximity: integer pip-nearest check within zone merge pass
- All bonuses stack additively; `MathMin(10.0, final_w)` cap applied after
- **Files:** `SK_SRWeightMatrix.mqh` (bonus stack logic), `SK_SREngine.mqh` (round# proximity detection in `RebuildPool`)

### STEP 4 — P2.30: Hard Cap 10.0 Enforcement Audit
**Verify `MathMin(w, 10.0)` exists at every weight write point:**
- Zone building initial assignment
- Zone merge (when summing two merged zone weights)
- Bonus application (after adding confluence/touch/round# bonuses)
- WMLevel construction before push to pool
- No weight anywhere in system can exceed 10.0 even transiently
- **Files:** `SK_SRWeightMatrix.mqh`, `SK_SREngine.mqh` (audit + clamp at every assignment)

### STEP 5 — P2.24: Round Number S/R Zone Generation
**New `CalcRoundLevels()` method in SREngine:**
- Scan ±200 pips from current bid
- 100-pip round numbers (e.g. 2300.00, 2400.00 on XAUUSD) → weight 6.0, type `SR_ROUND_100`
- 50-pip rounds (e.g. 2350.00, 2450.00) → weight 5.0, type `SR_ROUND_50`
- 25-pip rounds (e.g. 2325.00, 2375.00) → weight 4.0, type `SR_ROUND_25`
- Inject into pool on every `ForceRebuild()`; label "ROUND 2350" etc.
- Round# bonus: if Pivot, Swing, or EMA overlaps within 2 pips → P2.29 bonus triggers on that zone
- **Files:** `SK_SREngine.mqh` (new method), `SK_Defines.mqh` (SR_ROUND_100/50/25 enum types)

### STEP 6 — P2.17: CalcEMALevels — 120 EMA Levels in S/R Pool
**Currently:** EMAs live only in MA HUB display. Zone matrix has no EMA entries.  
**Target:** 8 EMA periods × 15 TFs = up to 120 EMA price levels injected into the pool. Near-price ones appear in zone matrix with EMA label, weight from TypeMult table, direction from P2.18 rule.  
- Method: `CalcEMALevels()` in SREngine loops all enabled TFs, reads current EMA value from DataEngine, creates WMLevel with `is_ema=true`, weight = `TF_Base[tf] × TypeMult_EMA[period]`
- Proximity filter: only EMA levels within N×ATR of current price enter pool (default N=5)
- **Files:** `SK_SREngine.mqh` (new `CalcEMALevels()`), `SK_DataEngine.mqh` (EMA value access for all TFs)

### STEP 7 — P2.18: EMA Direction Rule
**Rule:** Price ABOVE EMA → `is_resistance = false` (Support floor). Price BELOW EMA → `is_resistance = true` (Resistance ceiling). Updates dynamically on every pool rebuild.  
**Files:** `SK_SREngine.mqh` (applied inside `CalcEMALevels()` after price comparison)

### STEP 8 — P2.20: EMA Cluster Merge
**Rule:** Two or more EMAs on the same TF within `0.5 × ATR` of each other → collapse into one zone. Merged zone weight = sum of both weights, capped at 10.0. Label: "×2 EMA" or "×3 EMA". Prevents display clutter and correctly models institutional EMA confluence.  
**Files:** `SK_SREngine.mqh` (ATR-based dedup pass after `CalcEMALevels()`)

### STEP 9 — P2.21: CalcSMALevels — 75 SMA Levels
**Same as P2.17 but for SMA:** 8 SMA periods × 15 TFs, SMA800 excluded on TFs shorter than D1 (insufficient history would give wrong values).  
- If SMA200 and EMA200 on same TF overlap within ATR×0.5 → merge into "×2 EMA+SMA" zone, weight = sum, capped 10.0  
- **Files:** `SK_SREngine.mqh` (new `CalcSMALevels()`), `SK_DataEngine.mqh` (SMA value access)

### STEP 10 — P2.23: CalcMacroPivots Weight Verification
**Currently:** Weights assigned in `CalcMacroPivots()` may not precisely match spec.  
**Required exact weights:** PDH/PDL = **8.0**, PWH/PWL = **9.0**, PMH/PML = **9.5**. These are macro-exception levels — never gated by TFSync, always present. If confluence bonus pushes them above 9.5 → must cap at 10.0 via P2.30 rule.  
**Files:** `SK_SREngine.mqh` (audit `CalcMacroPivots()` weight assignments, correct if needed)

### STEP 11 — P2.31: Zone Merging Survival Mechanic
**Currently:** Pool may show ~100+ individual zones, one per raw level. Unreadable.  
**Target:** During `RebuildPool()` merge pass, collapse all levels within `ATR × 0.5` tolerance into one zone. The surviving zone gets:
- `zone_weight` = highest member weight + confluence bonus from P2.29
- `method_count` = number of methodologies that contributed
- `label` = e.g. "D1 SWING ×3" (showing 3 raw levels merged)
- Result: 80–120 raw levels → 20–40 consolidated display zones  
**Files:** `SK_SREngine.mqh` (merge pass in `RebuildPool()`, ATR tolerance from DataEngine ATR value)

### STEP 12 — P2.32: SR Matrix No-Auto-Execute Audit (Verification Only)
**Confirm:** Zero calls to any `COrderDesk` method from within `CSREngine` or `SK_SRWeightMatrix` code paths. S/R engine is data-only — orders may only originate from EXEC tab → popup confirmation.  
- Code read-through, no change expected  
**Files:** `SK_SREngine.mqh`, `SK_SRWeightMatrix.mqh` (audit only)

### REMAINING P2.16 — Fib Phase Label in FIB Panel (partially done)
- `GetFibPhase(int tf)` DONE in SREngine (returns string)
- UIManager FIB sub-tab must DISPLAY this phase label per TF row (still TODO)
- **File:** `SK_UIManager.mqh` (FIB sub-tab row builder — add phase column)

---

## 🟢 NEAR-TERM — Phase 3 Features

### P3-A — Pip-wise SL/TP in Stop/Limit tree panels
- PRICE/PIPS toggle for Stop tab and Limit tab (same as already exists on EXEC tab)
- In PIPS mode: OBJ_EDIT SL/TP1/TP2 fields accept pip distances; convert to absolute prices on `HandleEditEnd`
- Need `LevelTreeEntry.slPips` / `tp1Pips` / `tp2Pips` fields in struct
- **Files:** `SK_UIManager.mqh` (Stop/Limit RenderLevelTree + HandleEditEnd), `SK_Defines.mqh` (struct fields)

### P3-B — L1 SL/TP auto-cascade delta to lower levels
- Editing L1 SL price → compute `delta = new_sl - old_sl` → apply same delta to all unlocked L2/L3/.../Ln levels
- Same for TP1/TP2 edits at L1
- Cascade stops at first locked level; locked levels untouched
- **Files:** `SK_UIManager.mqh` (HandleEditEnd for level tree fields)

### P3-C — Dedicated cancel buttons per direction
- "Cancel All Buy Stops" in BUY STOP sub-tab
- "Cancel All Sell Stops" in SELL STOP sub-tab
- "Cancel All Buy Limits" in BUY LIMIT sub-tab
- "Cancel All Sell Limits" in SELL LIMIT sub-tab
- **Files:** `SK_UIManager.mqh` (render buttons + DispatchAction routing), `SK_OrderDesk.mqh` (new `CancelAllByType(ENUM_ORDER_TYPE)` method)

---

## ⬜ BACKLOG — Larger architectural work

### BL-1 — Full system forensic debug pass
- Validate every data path: DataEngine → PressureEngine → SMCEngine → PatternEngine → SREngine → AnalysisEngine → UIManager display
- Specifically diagnose: trendlines not showing in TL sub-tab (symptom reported earlier)
- Verify Statistics tab renders correctly with live data
- Verify MA HUB delta pips heatmap values are correct vs manual calculation
- Full debug pass — not a feature add

### BL-2 — Analysis period input parameter
- New EA input enum with 9 options: Today / Last 3 Days / This Week / Last 2 Weeks / 1 Month / 3 Months / 6 Months / 1 Year / 5 Years Max
- On selection: reload candle data for all active TFs limited to the selected period
- `OnInit` validation: check broker history depth; warn if shorter than selected period
- **Files:** `SK_TradeEA.mq5` (input + reload trigger), `SK_DataEngine.mqh` (period-gated bar load)

### BL-3 — All displayed levels filtered by analysis period
- S/R pool: only levels whose anchor bar falls within the selected analysis period
- Fib levels: only from swings within the period
- Trendlines: only from pivot anchors within the period
- Pivots: use the period's D1/W1/MN1 bar slice
- This is a major architectural gate on the SR/Fib pipeline — depends on BL-2

### BL-4 — VERIFICATION_GUIDE.md tier threshold update
- Guide still documents old 4-tier system: Titanium ≥9.0 (🔱), Steel 6.0–8.9 (⚔️), Wood 3.0–5.9 (🪵), Paper <3.0 (📄)
- Must be updated to the 10-tier floor() system with all emoji labels, weight ranges, and color assignments
- **File:** `C:\Users\amosd\Downloads\SK TRADE EA\VERIFICATION_GUIDE.md` (Phase 2 section P2.30 row)

### BL-5 — Concept Review → Code Coverage gap analysis
- 84,309 locked concept types identified in concept_review.md
- Only a fraction currently coded (EMA/SMA Crossovers partial, Dynamic S/R partial, Pivots, Swing H/L, Trendlines)
- Need systematic gap map: which of the 12 locked concepts have ZERO code coverage, which have partial
- Candle Patterns (9,360 types) — PatternEngine has ~13 types coded → 13/52 coverage
- Chart Patterns (10,800 types) — PatternEngine has ~10 → 10/48 coverage
- Supportive Indicators (9,900 types) — RSI Slope/Direction/Projection coded; VWAP/Volume Profile/Ichimoku/SAR = zero coverage
- Fibonacci+Harmonics (26,220 types) — harmonic patterns (Gartley/Bat/Butterfly/Crab) = zero coverage
- SMC S/R (14,175 types) — Wyckoff/AMD/CRT/CRL partially coded; others incomplete

---

## 📋 VERIFICATION — 13 Phases (none fully tested)

All 13 phases from `VERIFICATION_GUIDE.md` require a complete test pass against live MT5. Status: none formally verified against the current v2.6+ codebase.

| Phase | Focus | Key verification points |
|-------|-------|------------------------|
| 1 | Core Architecture | TF independence, async init 7 stages, no freeze, no ghost objects, 3-chain routing (SK_ACT → SK_DISPATCH → action) |
| 2 | S/R Matrix Engine | 7 methodologies present, zone merge ×N labels, weight formula correctness, tier colors, 10-tier display |
| 3 | Warriors Weapon Physics | 10 stages, OF decay curve, ClashDelta sign logic, BREAKOUT/REJECTION/UNCERTAIN verdicts, WW% on signal rows |
| 4 | Dual-Tier Confidence | 10 concept subscores (0–100 each), weighted MasterScore, 7 grade labels (ELITE→NOISE), ConfidenceEngine weights: SR=20%, WW=15%, SMC=12%, etc. |
| 5 | SMC Engine | BOS = body-close only (not wick), CHoCH, EQH/EQL, OB, Breaker Block, FVG, Premium/Discount zones |
| 6 | Signal Architecture | 14 sub-tabs present (MASTER first, not ALL), FORMING→ACTIVE→EXPIRED lifecycle, MISSED flash, popup gate is ONLY execution path |
| 7 | Execution Engine | HFT/Scalp/Dynamic/Manual modes, popup countdown 5s/10s/15s per mode, popup blocks keyboard during countdown |
| 8 | Virtual Tracking + CSV | Virtual P&L panel visible, CSV written to `MQL5\Files\` on every trade event, full snapshot fields |
| 9 | Telegram | 6 trigger events fire, notify-only vs execution format templates, bot token + chat ID input validation |
| 10 | Chart Marking + Auto-Snap | HLines appear on UPCOMING signals, auto-removed on EXPIRED, ChartScreenShot PNG saved on ACTIVATED |
| 11 | Candle Patterns | 13 patterns detected, 7 context multipliers applied, scores appear in CONFIDENCE sub-tab |
| 12 | Chart Patterns | 10 patterns, FORMING vs CONFIRMED threshold distinction, measured move projection shown |
| 13 | MA System | 3 display forms (MA S/R / MA CROSS / MA UNIFIED), 345 total MA cross combinations, Cascade Event +40 bonus active, GC Status panel D1 rows |

**Key spec constants for verification:**
- TF base weights: M1=1.0, H1=5.0, H4=7.0, D1=9.0, MN1=10.0; hard cap 10.0
- Confidence weights: SR=20%, WW=15%, SMC=12%, RSI=10%, ADX=8%, Vol=8%, EMA=8%, MAX=7%, Candle=6%, Chart=6%
- ADX < 15 → blocks ALL breakout signals (this gate must be active)
- Popup gate = ONLY execution path; 1-click permanently superseded
- Macro exceptions never gated: D1/W1/MN1 pivots, PDH/PDL/PWH/PWL/PMH/PML
- GC window: 14400 seconds (4 hours) from cross time
- DD reset password: "SKTRADE" (exact, case-sensitive)

---

## 📌 IMPLEMENTATION PRIORITY SEQUENCE

```
NOW:  P2.27 (4 TF base corrections) → P2.28 (TypeMult table + TL touch) 
      → P2.29 (confluence+round# bonuses) → P2.30 (hard cap audit)
      → P2.24 (round number zones) → P2.17+P2.18 (EMA pool + direction)
      → P2.20 (EMA cluster merge) → P2.21 (SMA pool)
      → P2.23 (macro weight verify) → P2.31 (zone merge survival)
      → P2.32 (no-auto-execute audit) → P2.16 FIB panel label display

THEN: BUG-5D (click penetration) → BUG-5E (DD immunity window)

THEN: P3-A / P3-B / P3-C (STOP/LIMIT pip mode, cascade, cancel buttons)

THEN: BL-1 (forensic debug) → BL-4 (verification guide update)

LATER: BL-2 → BL-3 (analysis period gating)
       BL-5 (concept coverage gap map → harmonic patterns, VWAP, Ichimoku, Volume Profile)

ONGOING: 13-phase verification pass (begin after P2.32 + bug fixes complete)
```

---

**Total open items:** 12 P2.x coding tasks + 2 critical bugs + 3 Phase 3 features + 5 backlog architectural items + 13 verification phases = **35 distinct work items** across all categories.

The weight matrix reference (plan file `merry-dreaming-puddle.md`) contains exact pre-calculated values for every tier, every TF, every methodology combination — use it as the ground-truth spec when implementing P2.27+P2.28+P2.29.