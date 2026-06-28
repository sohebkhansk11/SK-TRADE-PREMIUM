First updating memory with the Fibonacci lock, then presenting next concept.

✅ **Fibonacci + Harmonics — LOCKED (26,220 exact level types)**

---

## CONCEPT #7 — Key Horizontal Levels

---

### CURRENT CODED

| Level | Abbrev. | Fixed Weight | Gate |
|---|---|---|---|
| Previous Day High | PDH | 8.0 | Macro — always present |
| Previous Day Low | PDL | 8.0 | Macro — always present |
| Previous Week High | PWH | 9.0 | Macro — always present |
| Previous Week Low | PWL | 9.0 | Macro — always present |
| Previous Month High | PMH | 9.5 | Macro — always present |
| Previous Month Low | PML | 9.5 | Macro — always present |

**Current count: 6 fixed levels (no touch states tracked)**

---

### AI SCOPE EXTENSIONS — HIGHLY ADVANCED

---

#### CATEGORY A — Period Highs/Lows (Calendar-Based)

| Level | Description | Weight Class |
|---|---|---|
| PDH / PDL | Previous Day | Steel 8.0 |
| PWH / PWL | Previous Week | Hardened Steel 9.0 |
| PMH / PML | Previous Month | Titanium 9.5 |
| PQH / PQL | Previous Quarter High/Low | Titanium 9.7 |
| PYH / PYL | Previous Year High/Low | Titanium 9.9 |

**5 periods × 2 = 10 levels**

---

#### CATEGORY B — Period Opens/Closes

| Level | Description |
|---|---|
| PDO / PDC | Previous Day Open / Close |
| PWO / PWC | Previous Week Open / Close |
| PMO / PMC | Previous Month Open / Close |
| PQO / PQC | Previous Quarter Open / Close |

**4 periods × 2 = 8 levels**
*(Note: PDC = yesterday's close — one of the most-watched intraday reference levels)*

---

#### CATEGORY C — Period Range Midpoints (CPR equivalent)

| Level | Description |
|---|---|
| PDM | (PDH + PDL) ÷ 2 — Daily Range Midpoint |
| PWM | Weekly Range Midpoint |
| PMM | Monthly Range Midpoint |
| PQM | Quarterly Range Midpoint |

**4 midpoints**

---

#### CATEGORY D — Historical Rolling Extremes

| Level | Description |
|---|---|
| 52W-H | 52-Week High |
| 52W-L | 52-Week Low |
| ATH | All-Time High |
| ATL | All-Time Low |

**4 historical extremes** — highest fixed weights (10.0 for ATH/ATL)

---

#### CATEGORY E — Rolling N-Day Highs/Lows

| Window | Levels |
|---|---|
| 5D | 5-Day High / 5-Day Low |
| 10D | 10-Day High / 10-Day Low |
| 20D | 20-Day High / 20-Day Low |
| 50D | 50-Day High / 50-Day Low |
| 100D | 100-Day High / 100-Day Low |
| 200D | 200-Day High / 200-Day Low |

**6 windows × 2 = 12 levels**
*(Distinct from Period H/L — rolling window does not reset on calendar boundary)*

---

#### CATEGORY F — Gap Levels (Event-Based, Conditional)

Activated ONLY when current open creates a gap vs previous period close:

| Level | Description | Direction |
|---|---|---|
| Daily Gap Up | Current open > PDH → gap fill target = PDH | Bearish fill |
| Daily Gap Down | Current open < PDL → gap fill target = PDL | Bullish fill |
| Weekly Gap Up/Down | Weekly open gaps from prior PWH/PWL | Both |
| Monthly Gap Up/Down | Monthly open gaps from prior PMH/PML | Both |

**4 period × 2 directions = 8 gap levels**

---

#### CATEGORY G — ATR Extension Bands (Dynamic Envelope)

For each of Daily/Weekly/Monthly High and Low, project outward:

| Band | Formula |
|---|---|
| 0.5 ATR extension | PDH + 0.5×ATR(D1) |
| 1.0 ATR extension | PDH + 1.0×ATR(D1) |
| 1.5 ATR extension | PDH + 1.5×ATR(D1) |

Applied to: PDH, PDL, PWH, PWL, PMH, PML (6 levels × 3 bands = 18 extension levels)

**6 base levels × 3 ATR bands = 18 ATR extension levels**

---

#### CATEGORY H — Opening Range / Initial Balance

| Level | Time Window | Description |
|---|---|---|
| ORB-H / ORB-L | First 15 minutes | Opening Range Breakout level |
| IB-H / IB-L | First 30 minutes | Initial Balance High/Low |
| FH-H / FH-L | First 60 minutes | First Hour High/Low |

**3 time ranges × 2 = 6 intraday levels**
*(Applied per trading session — Asian/London/NY = 3 sessions × 6 = 18, but session-specific scope)*

For AI scope, counting across 3 sessions:
**3 sessions × 3 ranges × 2 = 18 Opening Range levels**

---

#### CATEGORY I — Overnight / RTH / Extended Hours

| Level | Description |
|---|---|
| OVH | Overnight High (non-main-session high) |
| OVL | Overnight Low |
| RTH-H | Regular Trading Hours High |
| RTH-L | Regular Trading Hours Low |

**4 levels**

---

#### CATEGORY J — Market Profile / Volume Profile

| Level | Description |
|---|---|
| VPOC | Volume Point of Control (most traded price) |
| VAH | Value Area High (70% of volume above this) |
| VAL | Value Area Low (70% of volume below this) |

Applied per session (Asian/London/NY) + daily composite:
**3 sessions × 3 = 9 + 3 daily = 12 market profile levels**

---

#### CATEGORY K — Developing / Current Period Levels (Live Updating)

| Level | Description |
|---|---|
| CDH / CDL | Current Day High/Low (forming live) |
| CWH / CWL | Current Week High/Low (forming live) |
| CMH / CML | Current Month High/Low (forming live) |

**3 periods × 2 = 6 developing levels**

---

### Exact Level Count — Key Horizontal

| Category | Level Types |
|---|---|
| A — Period H/L (D/W/M/Q/Y) | 10 |
| B — Period O/C (D/W/M/Q) | 8 |
| C — Period Midpoints | 4 |
| D — Historical Extremes | 4 |
| E — Rolling N-Day (5/10/20/50/100/200D) | 12 |
| F — Gap Levels (D/W/M/Q × up/down) | 8 |
| G — ATR Extension Bands | 18 |
| H — Opening Range (3 sessions × 3 ranges × H/L) | 18 |
| I — Overnight / RTH | 4 |
| J — Market Profile / VPOC (3 sessions + daily) | 12 |
| K — Developing Current Period | 6 |
| **Total Level Types** | **104** |

**× 5 Touch States (1t/2t/3t/4t/5+t): 104 × 5 = 520**

---

### AI Extension List — Key Horizontal (15 total)

| # | Extension | Type |
|---|---|---|
| 1 | Extended Period H/L (Quarterly + Yearly) | New level types |
| 2 | Period Open/Close (O/C for all periods) | New level types |
| 3 | Period Range Midpoints | New level types |
| 4 | Historical Extremes (52W-H/L, ATH/ATL) | New level types |
| 5 | Rolling N-Day H/L (5/10/20/50/100/200D) | New level types |
| 6 | Gap Levels (conditional on gap occurrence) | Event-based level types |
| 7 | ATR Extension Bands (0.5/1.0/1.5 ATR) | Dynamic envelope types |
| 8 | Opening Range / Initial Balance (3 sessions) | Intraday level types |
| 9 | Overnight / RTH Range | Session boundary types |
| 10 | Market Profile VPOC/VAH/VAL | Volume-based level types |
| 11 | Developing Current Period Levels (live) | Real-time updating types |
| 12 | Multi-Level Confluence (PDH = 52W-H = elevated weight) | Attribute |
| 13 | Level Breach State (Active/Broken/Retested/Reclaimed) | Attribute |
| 14 | Time Decay (Fresh=current period / Aged=prior) | Attribute |
| 15 | Volume Confirmation (spike at level = weight boost) | Attribute |

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
| 7 | Key Horizontal Levels | 🔄 CONFIRM TO LOCK | **520** |

**Running total if locked: 39,739**

---

**Confirm and lock Key Horizontal at 520 → move to next concept?**