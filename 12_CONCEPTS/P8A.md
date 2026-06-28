✅ **Key Horizontal — LOCKED (720)**. Memory updated. Presenting next concept.

---

## CONCEPT #8 — Round Numbers

---

### CURRENT CODED (P2.24)

| Type | Abbrev | Fixed Weight | Pip Size |
|---|---|---|---|
| 100-pip round | RND100 | 6.0 | 100 pips (e.g. 1.2000, 1.2100) |
| 50-pip round | RND50 | 5.0 | 50 pips (e.g. 1.2050) |
| 25-pip round | RND25 | 4.0 | 25 pips (e.g. 1.2025, 1.2075) |

**Deduplication:** 50-pip skips if coincides with 100-pip. 25-pip skips if coincides with 50-pip (covers 100 automatically).
**Scan range:** max(ATR×20, 300 pips) from current price.
**method_bit = 7**
**No touch state tracking — fixed weight only.**

**Current count: 3 tiers (no touch states, no break states)**

---

### AI SCOPE EXTENSIONS — HIGHLY ADVANCED

---

#### EXTENSION 1 — Full Pip Tier Spectrum (8 Tiers)

| Tier | Pip Size | Weight | Examples (EURUSD) | Use Case |
|---|---|---|---|---|
| 1 | **5-pip** | 2.5 | 1.2005, 1.2010 | Scalping micro-magnets |
| 2 | **10-pip** | 3.0 | 1.2010, 1.2020 | Short-term psychological |
| 3 | **25-pip** | 4.0 | 1.2025, 1.2050 | Quarter figure *(coded)* |
| 4 | **50-pip** | 5.0 | 1.2050 | Half figure *(coded)* |
| 5 | **100-pip** | 6.0 | 1.2000, 1.2100 | Big figure / Century *(coded)* |
| 6 | **500-pip** | 7.5 | 1.2000, 1.2500 | Major figure — institutional |
| 7 | **1000-pip** | 8.5 | 1.2000, 1.3000 | Millennium figure |
| 8 | **10,000-pip** | 9.5 | 30,000 / 40,000 (Dow) | Ultra figure — indices only |

**8 tiers total. Deduplication chain: 5→10→25→50→100→500→1000→10000. Higher tier always takes priority.**

---

#### EXTENSION 2 — Level States (3 States per Tier)

| State | Name | Description |
|---|---|---|
| **Intact** | Holding | Price approaching — level untested or respecting from correct side |
| **SBR** | Support-Becomes-Resistance | Round number broken upward — now retesting from above as resistance |
| **RBS** | Resistance-Becomes-Support | Round number broken downward — retesting from below as support |

*SBR/RBS state adds significant weight — psychologically, broken round numbers become even stronger as they flip. Institutional orders are placed anticipating this exact pattern.*

---

#### EXTENSION 3 — Touch State Accumulation (5 States)

1t / 2t / 3t / 4t / 5+t — same depletion model as all other concepts.

*Round numbers DO deplete after heavy testing. A 100-pip level tested 5+ times signals exhaustion — the magnet effect weakens as resting orders are consumed.*

---

#### EXTENSION 4 — Options-Derived Pin Levels (3 Types)

| Level | Description | Mechanism |
|---|---|---|
| **Monthly Options Max Pain** | Strike where largest total options expire worthless (max pain theory) | Market makers apply gamma pressure to pin price at this strike into monthly expiry |
| **Weekly Options Max Pain** | Same for weekly expiry | Strong pin effect Thu–Fri before expiry |
| **Daily 0DTE Gamma Strike** | Highest open interest strike for same-day (0 days-to-expiry) options | Most powerful intraday gamma pinning effect — active every day in liquid markets |

*These are distinct from standard round numbers because the force is OPTIONS GAMMA, not psychology. They often coincide with round numbers (confirming them) but can also be off-round — making them independent level types.*

× 3 states × 5 touch states = 45 option-derived level types

---

#### EXTENSIONS 5–8 — Attributes (Weight/Context Modifiers)

| # | Extension | Description |
|---|---|---|
| 11 | **Grand Round Composite** | When 100-pip + 500-pip + 1000-pip all land at the same price (e.g., 1.2000 = 100, 500, and 1000-pip round) → weights STACK, not just bonus |
| 12 | **Magnetic Zone** | Price within 2 pips of round = +0.3 zone bonus *(P2.29 already implements this)* |
| 13 | **Session Freshness Reset** | Round level confidence resets at each major session open (Asian/London/NY) — a 100-pip round rejected in Asian session is "fresh" again at London open |
| 14 | **Historical Respect Score** | Count of how many distinct periods this specific round number has been respected — a 1.2000 with 12 previous respected touches across 24 months = much higher weight than a newly created 100-pip level |

---

### Exact Level Count — Round Numbers

| Component | Calculation | Count |
|---|---|---|
| Core (8 tiers × 3 states × 5 touch) | 8 × 3 × 5 | 120 |
| Options Pin Levels (3 types × 3 states × 5 touch) | 3 × 3 × 5 | 45 |
| **EXACT TOTAL** | | **165** |

---

### AI Extension Summary — Round Numbers (14 total)

| # | Extension | Type |
|---|---|---|
| 1 | 5-pip tier (ultra-minor scalping) | New pip tier |
| 2 | 10-pip tier | New pip tier |
| 3 | 500-pip major figure | New pip tier |
| 4 | 1000-pip millennium figure | New pip tier |
| 5 | 10,000-pip ultra figure (indices) | New pip tier |
| 6 | SBR State (broken round → opposite S/R) | Level state |
| 7 | RBS State (reverse break and retest) | Level state |
| 8 | Touch State (1t/2t/3t/4t/5+t) | State dimension |
| 9 | Monthly Options Max Pain Strike | Options-derived level |
| 10 | Weekly Options Max Pain Strike | Options-derived level |
| 11 | Daily 0DTE Gamma Strike | Options-derived level |
| 12 | Grand Round Composite (tier stacking) | Attribute |
| 13 | Session Freshness Reset | Attribute |
| 14 | Historical Respect Score | Attribute |

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
| 8 | Round Numbers | 🔄 CONFIRM TO LOCK | **165** |

**Running total if locked: 40,104**

---

**Confirm and lock Round Numbers at 165 → move to next concept?**