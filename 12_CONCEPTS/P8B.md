**TEXT ONLY. No tools.**

---

**Corrected understanding confirmed.** Round numbers = **absolute price-level increments, instrument-adaptive** — NOT pip multipliers.

---

### Instrument-Adaptive Round Number Units

| Tier | XAU (Gold) | Forex (4-dec) | JPY pairs | US Indices | Oil |
|---|---|---|---|---|---|
| **Minor (25-unit)** | $25 → 4300, 4325, 4350 | 0.0025 | 0.25 | 25 pts | $0.25 |
| **Half (50-unit)** | $50 → 4300, 4350, 4400 | 0.0050 | 0.50 | 50 pts | $0.50 |
| **Century (100-unit)** | $100 → 4300, 4400, 4500 | 0.0100 | 1.00 | 100 pts | $1.00 |
| **Major (500-unit)** | $500 → 4000, 4500, 5000 | 0.0500 | 5.00 | 500 pts | $5.00 |
| **Millennium (1000-unit)** | $1000 → 4000, 5000, 6000 | 0.1000 | 10.00 | 1000 pts | $10.00 |
| **Ultra (10,000-unit)** | $10,000 | 1.0000 | 100.00 | 10,000 pts | $100.00 |

**Significance hierarchy (your example):**
- 4300 → Century (100-unit) — strongest
- 4350 → Half (50-unit) — medium
- 4325, 4375 → Minor (25-unit) — weakest
- 4500 → Major (500-unit) — stronger than Century if scan range is wide enough

**Deduplication chain stays same:** 25 skips if coincides with 50 → 50 skips if coincides with 100 → 100 skips if coincides with 500 → etc.

---

### Implementation Note (for P2.24 code fix)
Current code uses `_Pip() × 25/50/100` — this is CORRECT for Forex but WRONG for Gold/metals/indices. Need instrument-specific unit tables in `_BuildRoundLevels()`. Not coding now, noting for future.

---

### Revised Concept Count — Round Numbers (FINAL)

**6 tiers** (removed 5-unit and 10-unit — too granular, no real S/R significance at those levels):

| Tier | Weight |
|---|---|
| 25-unit (Minor) | 4.0 |
| 50-unit (Half) | 5.0 |
| 100-unit (Century) | 6.0 |
| 500-unit (Major) | 7.5 |
| 1000-unit (Millennium) | 8.5 |
| 10,000-unit (Ultra) | 9.5 |

| Component | Calculation | Count |
|---|---|---|
| Core (6 tiers × 3 states × 5 touch) | 6 × 3 × 5 | 90 |
| Options Pin (3 types × 3 states × 5 touch) | 3 × 3 × 5 | 45 |
| **EXACT TOTAL** | | **135** |

*(3 states = Intact / SBR / RBS — break-and-retest tracking)*

---

### Updated Master Summary Table

| # | Concept | Status | Count |
|---|---|---|---|
| 1 | EMA/SMA Crossovers | ✅ LOCKED | 2,040 + 12 AI ext. |
| 2 | EMA/SMA Dynamic S/R | ✅ LOCKED | 3,960 |
| 3 | Pivot Points | ✅ LOCKED | 174 |
| 4 | Structural Swing H/L | ✅ LOCKED | 3,510 |
| 5 | Trendlines | ✅ LOCKED | 3,315 |
| 6 | Fibonacci + Harmonics | ✅ LOCKED | 26,220 |
| 7 | Key Horizontal Levels | ✅ LOCKED | 720 |
| 8 | Round Numbers | 🔄 CONFIRM TO LOCK | **135** |

**Running total if locked: 40,074**

---

**Confirm and lock Round Numbers at 135 → move to next concept?**