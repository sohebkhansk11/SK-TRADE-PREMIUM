---

# CONCEPT #9 — SMC (Smart Money Concepts) S/R
## Complete Detailed Understanding + 12 Highly Advanced AI Extensions

---

## PART 1 — WHAT IS CURRENTLY CODED

From `SK_Defines.mqh`:
```cpp
enum ENUM_SMC_EVENT {
   SMC_NONE=0, SMC_BOS=1, SMC_CHOCH=2,
   SMC_CRT=3, SMC_CRH=4, SMC_SBR=5, SMC_RBS=6
};
```
**6 coded types only.** No grade. No lifecycle state. Minimal TF tracking. No Order Blocks. No FVG. No Liquidity pools. No OTE. No Wyckoff. No AMD. The full SMC methodology is almost entirely absent.

---

## PART 2 — COMPLETE 63-TYPE MATRIX WITH FULL EXPLANATIONS

---

### ═══ CATEGORY A — Structure Break Events (8 types) ═══

---

**A1 — Bullish BOS (Break of Structure)**

Price BODY (not wick — confirmed by VERIFICATION_GUIDE spec) closes above a previously validated swing HIGH. The exact price of that broken swing high becomes the S/R level. Why significant: smart money uses swing highs as reference points. A body close above means genuine buying pressure overwhelmed supply — the former resistance is now institutionally confirmed as support. When price retraces, it should find demand at that broken swing high. The BOS level persists until price body-closes back below it (Invalidated).

---

**A2 — Bearish BOS**

Mirror of A1. Body close below a validated swing LOW. The broken swing low becomes resistance on any retracement. Former support flips to resistance by the same mechanism — trapped longs who bought at that support now want to exit at breakeven when price returns → they sell → creates resistance.

---

**A3 — Bullish Internal BOS**

Same body-close-above-swing-high rule, but applied to INTERNAL structure — the lower-degree swings that exist WITHIN a single price leg. Example: in a downtrend, each individual bearish leg has internal mini-swings (corrective bounces within the leg). When price body-closes above one of those internal lower highs, it is an Internal BOS — it signals momentum shift within the leg but does NOT confirm a trend reversal. Significance is lower than External BOS. Used for early warning entries, or for precision in identifying shift of delivery within a leg.

---

**A4 — Bearish Internal BOS**

Body close below an internal swing low within a bullish leg. Same logic — intra-leg shift, not full structural change.

---

**A5 — Bullish External BOS**

The highest-degree structural break — price body closes above the MOST SIGNIFICANT swing high of the current downtrend (the last relevant lower-high or the most recent macro swing high). This is what converts a downtrend to an uptrend at the structural level. Only ONE External BOS exists at any given time per TF (the most recent significant one). Carries the highest S/R authority of all A-category types. The level = that major swing high.

---

**A6 — Bearish External BOS**

Body close below the most significant swing low of a current uptrend. Converts uptrend to downtrend structurally.

---

**A7 — Bullish CHoCH (Change of Character)**

In a confirmed downtrend (verified series of lower highs and lower lows): the FIRST time price body-closes above a LOWER HIGH. This is different from BOS because BOS confirms the trend direction — CHoCH goes COUNTER to the trend direction. CHoCH says "the character of this market has changed." It does not guarantee reversal — it is the first warning. The broken lower-high level = the CHoCH level. Subsequent BOS in the same direction confirms the new trend. CHoCH has higher reversal probability than a standard BOS because it represents the first capitulation of the prevailing trend.

---

**A8 — Bearish CHoCH**

In a confirmed uptrend: first body-close below a HIGHER LOW. The broken higher-low = CHoCH level. Highest reversal probability among early signals.

---

### ═══ CATEGORY B — Market Structure Labels (4 types) ═══

---

**B1 — Strong High**

A swing high that was FORMED AS THE RESULT of a BOS or CHoCH move upward. When price broke structure upward and then pulled back to create a swing high — that swing high is a Strong High. Why "strong": the move that created it had proven institutional participation (a structural break happened). These levels have higher S/R authority than weak highs. Price reverting to a Strong High zone tends to react more decisively. Every BOS creates a Strong High at its origin.

---

**B2 — Weak High**

A swing high formed by a normal corrective retracement — no BOS or CHoCH preceded its formation. In a downtrend, every bounced lower high is a Weak High. In an uptrend, the pullback highs before continuation are Weak Highs. Lower S/R authority — price is more likely to break through a Weak High without major reaction. Identification: any swing high where the preceding upward move did NOT break structure.

---

**B3 — Strong Low**

Symmetric to B1. Swing low formed as a result of a downward BOS or CHoCH move. The move that created this low had structural confirmation. Strong support authority.

---

**B4 — Weak Low**

Symmetric to B2. Swing low from a normal retracement within a trend. Lower support authority — likely to be swept before any meaningful reversal.

---

### ═══ CATEGORY C — Order Blocks (10 types) ═══

---

**C1 — Bullish Order Block**

The LAST bearish candle (or last consecutive group of bearish candles) immediately before a strong bullish IMPULSE MOVE (displacement). The entire candle range (high to low) defines the OB zone. ICT theory: institutions place bulk BUY orders at this price level. The bearish candle represents price being pushed down briefly to fill buy orders at a discount and collect sell orders (stop-losses of existing shorts) before the actual move upward. The institutional buy orders remain in the system — when price returns to this zone, those orders act as a demand floor. The bullish impulse following the OB MUST be significant — it should break a swing high or leave FVGs behind to confirm the OB is genuine. State: Fresh (just formed) → Active (waiting) → Tested (touched once, wicked into) → Mitigated (> 50% of zone entered by body) → Invalidated (body close below OB low).

---

**C2 — Bearish Order Block**

The last bullish candle (or consecutive bullish group) immediately before a strong bearish displacement. Zone = the candle's full range. Institutional SELL orders reside here. When price retraces to the OB zone from below, supply overwhelms and price reverses down. Invalidated = body close above OB high.

---

**C3 — Bullish Breaker Block**

A former BEARISH Order Block that price subsequently broke THROUGH upward (body close above the Bearish OB's high). When the Bearish OB is overcome by price, it "flips" — the entire zone that was previously a supply area now becomes a demand area (Bullish Breaker). Logic: the supply that defined that Bearish OB was completely absorbed by buyers. The price level where that absorption occurred becomes institutional support. Same zone boundaries as the original Bearish OB — price range unchanged, direction reversed. This is one of the HIGHEST probability SMC S/R zones because: (1) it was a proven institutional level (was a real OB), (2) it was taken out (the supply was consumed), (3) it now marks the transition point where demand overcame supply.

---

**C4 — Bearish Breaker Block**

Former Bullish OB broken downward → flips from demand zone to supply zone. Same price range, reversed direction. Equally high probability — the demand was fully consumed when price broke through. Now resistance.

---

**C5 — Bullish Mitigation Block**

A Bullish OB that price returned to and entered but did NOT close through the bottom. "Mitigated" means the institutional orders were partially filled during that test — some of the resting buy orders were consumed. Key distinction from Tested state: Mitigated means price body entered more than 50% into the OB zone. The OB still has S/R authority but is weaker than a Fresh/Active OB because a portion of the institutional demand has already been absorbed. If price returns again, less demand remains → lower weight.

---

**C6 — Bearish Mitigation Block**

Bearish OB partially tested (body entered > 50% of zone). Partially consumed supply — still acts as resistance but weakened.

---

**C7 — Bullish Propulsion Block**

A sub-type of OB specifically in a continuation context. In an established uptrend, price is making higher highs/higher lows. At some point, a single candle "launches" the next bullish leg — typically the candle that breaks the last swing high, accelerating momentum. That specific launch candle = Propulsion Block. Different from a regular OB in that it occurs MID-trend (not at the origin of the trend). The zone = the candle's BODY (close to open) rather than full range — more precise because the wick areas at either end are less institutionally significant. As S/R: strong continuation support on a retracement during the trend.

---

**C8 — Bearish Propulsion Block**

The single acceleration candle in a downtrend continuation. Zone = body range of the launch candle. Strong continuation resistance on retracement.

---

**C9 — Bullish Rejection Block**

A candle with a significant long LOWER wick — price swept down into a zone (lower wick) but buyers aggressively rejected the move and closed the candle in the upper portion of its range. The lower wick represents the area where institutional BUYING was so strong it immediately reversed price. The zone = from the candle LOW to the candle BODY LOW (the lower edge of the body). This wick zone is a demand area — institutions absorbed supply in that range. As S/R: the wick zone supports price on subsequent visits. Different from Swing H/L in that the detection focuses on the CANDLE BODY vs WICK relationship rather than swing structure.

---

**C10 — Bearish Rejection Block**

Long upper wick candle — price spiked up into a zone but sellers aggressively overwhelmed buyers. The wick zone = from candle BODY HIGH to candle HIGH. Supply zone. As S/R: resistance on subsequent tests of that wick area.

---

### ═══ CATEGORY D — Fair Value Gaps / Imbalance (9 types) ═══

---

**D1 — Bullish FVG (Fair Value Gap)**

Three-candle pattern. Candle 1 (the "pre-gap" candle), Candle 2 (the large impulse — the displacement candle), Candle 3 (the "post-gap" candle). The FVG exists when: **Candle 3 Low > Candle 1 High**. The gap zone = the price range between Candle 1 High and Candle 3 Low — price SKIPPED this entire range during Candle 2's move. Why it exists: the impulse moved so fast (institutional BUY execution) that only one side of the market transacted — buyers bought aggressively but there were insufficient sellers to create overlapping price action. The result is an "imbalance" — those price levels were never traded at fair value (no two-way auction). Price is algorithmically drawn back to fill these gaps to seek the opposite side (find sellers who couldn't transact during the imbalance). As S/R: the FVG zone acts as SUPPORT on retracement — it's a known unfilled demand zone.

---

**D2 — Bearish FVG**

Three-candle: **Candle 3 High < Candle 1 Low**. Gap zone = Candle 1 Low to Candle 3 High. Only sellers transacted during the impulse — no buyers got filled. Imbalance to the downside. Acts as RESISTANCE when price retraces upward — the unfilled supply zone.

---

**D3 — Bullish iFVG (Inversion / Inverse FVG)**

A Bullish FVG that has been FULLY filled — price retraced all the way back through the entire FVG zone (Candle 3 Low to Candle 1 High, the entire gap was covered). After being fully filled, the FVG "inverts." The zone that was support (bullish FVG) now becomes RESISTANCE because: the imbalance was resolved (the two-way auction occurred in that range), and now the price has evidence that supply exists there. The zone boundaries remain identical — only the directional bias reverses. iFVG zones are extremely high S/R significance because they were significant enough to: (1) attract a fill, and (2) survive the fill to create a new directional reference.

---

**D4 — Bearish iFVG**

Bearish FVG fully filled → zone flips to SUPPORT. The filled bearish imbalance zone now acts as demand.

---

**D5 — Bullish CE (Consequent Encroachment)**

The exact 50% midpoint of an unfilled Bullish FVG = (FVG top + FVG bottom) / 2. ICT observed that price very frequently reacts at the midpoint of an FVG even before attempting to fill the full gap. The CE represents "half of the imbalance resolved." When price touches the CE of a Bullish FVG: some orders are consumed but the lower half of the FVG remains unfilled. The CE level itself = precision S/R within the FVG zone. Used as a more aggressive entry (entering at the CE rather than waiting for the full bottom of the FVG).

---

**D6 — Bearish CE**

50% midpoint of an unfilled Bearish FVG. Precision S/R level within the gap — price reacts here before potentially filling the rest.

---

**D7 — Bullish Volume Imbalance**

Different from FVG — defined by volume asymmetry rather than price gap. A price range where ASK-side volume completely dominated — aggressive buyers placing market orders with insufficient passive sellers to absorb them at those price levels. This does NOT require a visible 3-candle gap (no price gap may exist) but the volume distribution shows one-sided delivery. The zone = the price range where this volume imbalance occurred (typically identifiable on volume profile or delta analysis). Price is algorithmically drawn back to this zone to find the missing sellers.

---

**D8 — Bearish Volume Imbalance**

BID-side dominated zone — sellers overwhelmed buyers in a price range without opposite volume. Price returns to find missing buyers. Acts as resistance.

---

**D9 — BPR (Balanced Price Range)**

A specific, high-significance formation: a Bullish FVG and a Bearish FVG that OVERLAP within the same price range. This means price moved UP (creating a bull FVG = demand imbalance) and then moved DOWN (creating a bear FVG = supply imbalance) within the same area. The overlapping zone = a region where BOTH institutional buyers AND institutional sellers have reference points. This is "balanced" — two-sided institutional activity is confirmed here. BPR zones are among the strongest SMC S/R levels because consensus exists from BOTH sides — institutions on both sides traded here. The overlap zone = the intersection of the bull FVG and bear FVG price ranges.

---

### ═══ CATEGORY E — Liquidity Levels (6 types) ═══

---

**E1 — BSL (Buy-Side Liquidity)**

Accumulated stop-loss orders and pending buy orders sitting ABOVE current price. These cluster at predictable locations: equal highs (where multiple swing tops coincide), previous swing highs, prior day/week/month highs, obvious round numbers above price. Retail short traders place their stop-losses ABOVE swing highs → those are BUY orders (covering shorts). Retail range traders place buy-stop entries above resistance. Both create a pool of pending BUY volume. Institutions know exactly where this volume sits. To SELL large size, institutions need offsetting buy volume to fill against → they engineer price to move up toward the BSL, triggering those buy orders, filling their sell orders against them → price reverses downward after the stop raid. The BSL level = the price of the equal high / swing high / round number where stops cluster. As S/R: before being swept, BSL = potential resistance (price approaches from below). After being swept = reversal zone.

---

**E2 — SSL (Sell-Side Liquidity)**

Pending SELL orders and stop-losses sitting BELOW current price. Clusters at: equal lows, swing lows, prior day/week/month lows, round numbers below price. Retail long traders have stops below swing lows. Institutions need to BUY large size → they need sell volume to buy from → they push price down to sweep SSL (triggering those sell stops), buying from panicked sellers, then reversing upward. The SSL level = the price of the equal low / swing low / round number where stops sit. As S/R: before being swept = potential support. After being swept = reversal zone.

---

**E3 — BSL Swept**

A BSL level that has been "taken" — price spiked above it (the wick of a candle moved above the BSL level) and then closed BACK below it, indicating the stop-run completed and no genuine breakout occurred. The SWEEP represents: (1) all the buy-stop orders triggered, (2) institutions sold INTO that rush of buy orders, (3) now those buyers are trapped long at the high. The wick EXTREME (the absolute high of the sweep) = the key reference level post-sweep. It now acts as a ceiling — price distributed at that high. The trapped buyers become overhead supply (they need to exit → they sell on any bounce back toward that high).

---

**E4 — SSL Swept**

SSL that was taken — wick below and reversal. Price spiked below the SSL, triggered the sell-stops, institutions bought that panic selling, then reversed up. The wick low = the sweep level, now acts as a floor. Trapped sellers need to cover → they buy on any dip back toward that low → creates support.

---

**E5 — Bullish Inducement**

A specific liquidity engineering pattern: a small, deliberately created swing HIGH sitting BELOW a major resistance level. Why "bullish inducement"? It induces bullish retail traders to place long entries at that resistance break → their STOPS go below the inducement high → creating SSL. Institutions will run that SSL (the stops of the traders who bought the fake breakout) before the actual directional move. As S/R: the inducement level itself acts as temporary resistance — it was created to lure retail longs. After the stop run below (SSL sweep), the ACTUAL move begins. The inducement high becomes a reference for the true reversal origin.

---

**E6 — Bearish Inducement**

Small swing LOW created above a major support level — lures retail shorts to short the breakdown. Their stops (above the inducement) = BSL that gets swept before the real move. The inducement low = temporary support level above which institutions will drive price to collect BSL before the actual bearish move.

---

### ═══ CATEGORY F — Premium / Discount / OTE (5 types) ═══

---

**F1 — Premium Zone**

The price range ABOVE the 50% midpoint of the current identified swing range (swing high to swing low). ICT: "Premium means expensive." If the measured range runs from 1.0800 to 1.1000 (200 pips), the equilibrium is 1.0900. Premium = anything above 1.0900. In premium, price is trading above fair value relative to the current range. Institutions who bought in discount look to SELL in premium (take profit). New institutional sell positions are initiated in premium targeting discount. As S/R: every level in the premium zone has its significance enhanced by the directional bias. Bearish OBs, FVGs, and confluence points in premium are stronger resistance. Bullish S/R in premium = lower conviction (selling against institutional bias).

---

**F2 — Discount Zone**

Below the 50% midpoint of the range. "Discount means cheap." Price below the equilibrium of the range = undervalued. Institutions who sold in premium target discount to BUY (take profit, or initiate new longs). As S/R: bullish OBs, FVGs, and confluence in discount = stronger support. Bearish S/R in discount = lower conviction (buying against the institutional bias that exists here).

---

**F3 — Equilibrium Level**

The exact 50% midpoint = (Range High + Range Low) / 2. Fair value. This is the price where neither premium nor discount exists — the market is priced "correctly" relative to the current swing range. Price frequently uses equilibrium as a decision point — a battle between buyers and sellers. Multiple other frameworks also converge here: Fibonacci 50% retracement, CRT midpoint, CPR mid-pivot. Equilibrium is also the BOUNDARY between premium and discount — a directional flip point.

---

**F4 — Bullish OTE (Optimal Trade Entry)**

The zone between 61.8% and 79% retracement WITHIN DISCOUNT. This is the highest-probability institutional LONG entry zone. Why 61.8%: the golden ratio — the primary Fibonacci retracement level used globally. Why 79%: it equals the square root of 0.618 — an additional ICT Fibonacci refinement. The OTE zone = from the 61.8% level to the 79% level, measured from the SWING LOW to the SWING HIGH (measuring the retracement of a bullish move). Example: bullish move from 1.0800 to 1.1000. 61.8% retracement from 1.1000 = 1.0800 + (200 × 0.382) = 1.0876. 79% retracement = 1.0800 + (200 × 0.21) = 1.0842. OTE zone = 1.0842–1.0876 in discount. When OB or FVG coincides with OTE = "Golden Setup" — the highest probability SMC long entry.

---

**F5 — Bearish OTE**

61.8%–79% retracement WITHIN PREMIUM. The zone where institutional SELLS are concentrated. Measured from swing high to swing low (measuring the retracement of a bearish move). When Bearish OB or Bearish FVG coincides with Bearish OTE zone = highest probability institutional short setup.

---

### ═══ CATEGORY G — Candle Range Theory (5 types) ═══

---

**G1 — CRH (Candle Range High)**

ICT's Candle Range Theory: higher timeframe candles define key price levels. The HIGH of a specific reference candle on a higher timeframe = CRH. Which candle: typically the PREVIOUS candle (previous D1 candle, previous W1 candle) or the CURRENT incomplete candle. Implementation: for intraday analysis using M15, the D1 CRH = yesterday's daily high. For swing analysis on H4, the W1 CRH = last week's weekly high. As S/R: the CRH is a known reference level for the entire duration of the current candle period on that TF. Price frequently reacts at HTF CRH levels with high precision.

---

**G2 — CRL (Candle Range Low)**

The LOW of the reference HTF candle. Symmetric to CRH. Key support level on lower timeframes. The CRL and CRH together define the "operating range" for the current period — price oscillates within this range, seeks the extremes for liquidity.

---

**G3 — CRT Body High**

The BODY HIGH of the reference candle = max(open, close) of that HTF candle. More precise than the full CRH because the body close represents institutional consensus (the settling price) rather than the wick (which represents temporary overextension). The body high is where price "agreed" to close during that period. As S/R: tighter, more precise reaction level than the full CRH. Used for precision entries within the CRT range.

---

**G4 — CRT Body Low**

min(open, close) of the reference HTF candle. Institutional settlement low for that period. Precision support level within the CRT range.

---

**G5 — CRT Midpoint**

Exact midpoint of the reference candle's total range = (CRH + CRL) / 2. This is the equilibrium of the reference HTF candle — the "fair value" of that specific period. Price frequently reacts at the midpoint of HTF candles before deciding direction. Same concept as F3 Equilibrium but applied to individual candles rather than the full swing range. Coincides with the Fibonacci 50% within the candle range.

---

### ═══ CATEGORY H — SBR / RBS (2 types) ═══

---

**H1 — SBR (Support Becomes Resistance)**

A former support level that was decisively broken downward (body close below it). After the break, on any subsequent retracement upward, this level acts as RESISTANCE. The mechanism: traders who bought at that support level are now trapped long above a broken level — their positions are in loss. When price retraces back to the old support (now the break level), those trapped buyers use the opportunity to EXIT at a lesser loss → they sell → creates selling pressure at that level → resistance is born. The S/R level = the exact price of the former support. This level remains active as resistance until another structural break changes context.

---

**H2 — RBS (Resistance Becomes Support)**

Former resistance broken upward (body close above it). On any subsequent pullback, that former resistance is now SUPPORT. Trapped short-sellers who sold at that resistance now face a losing position as price broke above — when price retraces to the old resistance, they cover shorts (buy to exit) → creates buying pressure → the former resistance supports price. A classic technical principle formalized in SMC. The exact price of the former resistance = the new support level.

---

### ═══ CATEGORY I — AMD / Power of Three (6 types) ═══

---

**I1 — AMD Accumulation Low**

ICT's Accumulation-Manipulation-Distribution (AMD) model. In the ACCUMULATION phase, price trades in a tight range as institutions QUIETLY build large positions without revealing their intent. The LOW of this accumulation range = the AMD Accumulation Low. Institutions accumulate longs at this level — they buy everything that is offered, absorbing all sell-side pressure, but without driving price up yet (they want to fill more). As S/R: the accumulation low is extremely strong support because institutions have massive long exposure there. Any return to the accumulation low = institutions defend their positions aggressively.

---

**I2 — AMD Manipulation High (Judas Swing — Bullish)**

After accumulation, price is MANIPULATED — typically right at the beginning of the most active session (London open, NY open). Price spikes ABOVE the accumulation range high (a bullish Judas Swing) to: (1) trigger stop-losses of short-sellers above the range (buy those stops = more longs for institutions), (2) attract FOMO retail buyers at a premium (who will provide exit liquidity for institutions). The manipulation HIGH = the absolute top of the fake breakout spike. As S/R: this level is strong RESISTANCE after the reversal — it marks where institutions began distributing to the FOMO buyers. The manipulation candle is often the AMD Bearish OB.

---

**I3 — AMD Manipulation Low (Judas Swing — Bearish)**

The inverse Judas Swing — price spikes DOWN below the accumulation range low to: (1) trigger long stop-losses below the range = forced selling = more buying opportunity for institutions, (2) attract panic sellers at a discount. After sweeping below, price reverses sharply upward. The manipulation LOW = the absolute bottom of the fake breakdown. As S/R: this level becomes strong SUPPORT after the reversal — institutions bought everything at that low. The manipulation candle = AMD Bullish OB.

---

**I4 — AMD Distribution High**

After manipulation, price moves in the TRUE direction (distribution to early buyers / late sellers). The DISTRIBUTION HIGH = where institutions complete their selling into retail demand. This is the actual high of the move — not the fake manipulation high. As S/R: Major resistance going forward. All institutional supply was distributed at this high. No more institutional buying above this level (they already exited). Very significant S/R level.

---

**I5 — Power of 3 Session High**

Every trading session (Asian, London, NY) has its own AMD micro-cycle. The SESSION HIGH is the high of that specific session's candle (or the consolidated candle for the session). ICT's Power of 3 at the session level: the session high often represents either the manipulation high (if it's a fake spike) or the distribution high (if it's the true session direction). As S/R: HTF-session highs act as intraday resistance that lower TF analysis respects.

---

**I6 — Power of 3 Session Low**

Session LOW = AMD accumulation low or manipulation low for that session's cycle. Intraday support reference. Session lows frequently get swept (SSL raid) before the true directional move, making them both an S/R level AND a liquidity trap indicator.

---

### ═══ CATEGORY J — Wyckoff Integration (4 types) ═══

---

**J1 — Wyckoff Spring Level**

In Wyckoff's accumulation schematic, the "Spring" is a sharp price move BELOW the support of the trading range (Phase C), followed by an equally sharp reversal back into the range. Purpose: (1) shake out the last weak longs who placed stops below support, (2) test remaining supply at lower prices (if supply is exhausted = range is ready to break out). The Spring LOW = the absolute low of the false breakdown. As S/R: one of the strongest support levels in Wyckoff methodology. Institutions absorbed ALL remaining supply at the spring low. No sellers are left below it. Any return to the spring low = institutional absorption zone. The spring low is the foundation of the eventual breakout.

---

**J2 — Wyckoff Upthrust Level**

In Wyckoff's distribution schematic: price spikes ABOVE the trading range resistance (Phase C), fails to hold, and reverses back into the range. Purpose: (1) trigger short-seller stops above resistance (buy those stops to sell into), (2) attract breakout buyers at premium. The Upthrust HIGH = the absolute high of the false breakout. As S/R: strongest resistance in the Wyckoff structure. Institutions distributed (sold) maximum supply at this high. Strong ceiling for the markdown phase that follows.

---

**J3 — Wyckoff UTAD (Upthrust After Distribution)**

A secondary, typically FINAL upthrust that occurs LATER in the distribution phase after the initial upthrust has already occurred. Price makes one last attempt to break higher in distribution — retailers who missed the first upthrust and waited to "confirm the uptrend" buy this UTAD high. Institutions sell into this final surge. The UTAD HIGH = strong resistance and often the LAST high before a major sustained downtrend. Higher S/R authority than a standard Upthrust because it occurs after the distribution is more mature.

---

**J4 — Wyckoff BUEC (Back-Up to Edge of Creek)**

After price breaks below the accumulation range (the "Creek" = the resistance/supply zone of the accumulation range), it sometimes RETURNS to retest the bottom of the creek from below (the old resistance, now support). This retest = BUEC. The BUEC level = the bottom of the accumulation range (the "edge of the creek") — now acting as support after the breakout. As S/R: extremely high probability support level. Institutional long orders were placed at the breakout point and defended as price pulls back. One of the highest conviction long entries in Wyckoff framework.

---

### ═══ CATEGORY K — Displacement / Institutional (4 types) ═══

---

**K1 — Bullish Displacement Origin**

A "displacement" is a single candle OR tight multi-candle group (≤ 3 candles) that moves price ≥ 2×ATR(14) in one direction without a counter-move. The ORIGIN LEVEL = the price at the BASE of the displacement — the opening price / low of the displacement candle. Why significant: at the displacement origin, institutional BUY orders activated en masse. The scale of the move (≥ 2×ATR) proves this was not retail-driven — only institutional volume creates displacement of this magnitude. As S/R: when price retraces all the way to the displacement origin (back to where the institutional buy activation began), those same institutions are expected to defend the origin. Very strong support.

---

**K2 — Bearish Displacement Origin**

Base of a ≥ 2×ATR bearish displacement candle. The price at the HIGH/open of the displacement candle where institutional SELL orders activated. Strong resistance on any retracement.

---

**K3 — Bullish Institutional Candle Zone**

A large bullish candle (≥ 2×ATR range). The specific zone = from the candle's CLOSE (body high) to its absolute HIGH (wick high). This upper zone above the body = the area where institutional BUYING overwhelmed supply (hence the close near the high, but not AT the high — some supply was still absorbed in the wick portion). The HIGH-to-CLOSE zone is where supply was absorbed and converted to demand. When price returns to this zone = the remaining demand acts as support. More precise than using the full candle range — it focuses on the institutional absorption zone specifically.

---

**K4 — Bearish Institutional Candle Zone**

Large bearish candle (≥ 2×ATR). Zone = from candle absolute LOW (wick low) to its CLOSE (body low). The LOW-to-CLOSE zone = where institutional SELLING overwhelmed demand. When price retraces up to this zone = remaining supply acts as resistance.

---

## PART 3 — DIMENSION VERIFICATION

| Dimension | Values | Count |
|-----------|--------|-------|
| Level types (11 categories) | A8 + B4 + C10 + D9 + E6 + F5 + G5 + H2 + I6 + J4 + K4 | **63** |
| Grade | Strong / Normal / Weak | **×3** |
| Timeframe | M1 M3 M5 M6 M10 M15 M30 H1 H2 H4 H8 H12 D1 W1 MN1 | **×15** |
| State | Fresh / Active / Tested / Mitigated / Invalidated | **×5** |
| **Total** | 63 × 3 × 15 × 5 | **= 14,175** |

---

---

## PART 4 — 12 HIGHLY ADVANCED AI EXTENSIONS — FULL DETAIL

---

### ═══ EXTENSION 1: Full Type Expansion (6 coded → 63 extended) ═══

**What it is:** The current enum has 6 event flags used as basic signal identifiers with no S/R geometry. The extension transforms SMC from an event-flagging system into a full S/R LEVEL GEOMETRY system — each type creates a ZONE with defined price boundaries, not just a tag on a candle.

**How it changes the architecture:**
- Current: `SMC_BOS` flags the bar where a BOS occurred — no zone, no boundaries, no persistence
- Extended: BOS detection creates a persistent `SRLevel` object with `price_high`, `price_low` (the zone boundary), `tf`, `grade`, `state`, `age`, `weight`
- Each of the 63 types needs its own geometry extraction: OBs use candle range, FVGs use the 3-candle gap, BOS uses the swing high/low price, BSL uses the equal-high cluster price, etc.

**Implementation required:**
- `_DetectBOS()` → creates BOS S/R level objects (6 variants A1–A6)
- `_DetectCHoCH()` → creates CHoCH objects (A7–A8)
- `_ClassifyStructureLabel()` → tags existing swing levels as Strong/Weak (B1–B4) based on whether they preceded a BOS
- `_DetectOrderBlocks()` → 10 OB variants, requires displacement check
- `_DetectFVG()` → 9 FVG/imbalance variants
- `_DetectLiquidity()` → 6 BSL/SSL/Inducement variants
- `_DetectPremiumDiscount()` → dynamic recalculation per identified swing
- `_DetectCRT()` → 5 types, reads HTF candle data
- `_DetectAMD()` → 6 types, session-range analysis
- `_DetectWyckoff()` → 4 types, requires range + spring/upthrust pattern recognition
- `_DetectDisplacement()` → 4 types, ATR-normalized candle filter

**Why this matters:** The current 6 types produce perhaps 6–20 data points per TF per timeframe. The 63-type expansion produces 60–200 S/R zone objects per TF — complete multi-dimensional coverage of the institutional price delivery map.

---

### ═══ EXTENSION 2: Grade Dimension (Strong / Normal / Weak) ═══

**What it is:** Every SMC level is graded based on the quality of the INSTITUTIONAL SIGNATURE that created it. Same type, same TF — but if one OB was created by a 3×ATR displacement and another by a 0.8×ATR move, they are fundamentally different levels.

**Grade criteria:**

| Grade | Criteria | Weight Multiplier |
|-------|----------|-------------------|
| **STRONG** | Displacement ≥ 2.0×ATR(14) creating the level; BOS of a swing with 3+ previous touches; OB created immediately after a liquidity sweep (stop-raid confirmation) | ×1.20 |
| **NORMAL** | Displacement 1.0–2.0×ATR; BOS of 1–2 touch swing; standard OB formation | ×1.00 |
| **WEAK** | Displacement < 1.0×ATR; BOS of unconfirmed swing (< 1 confirmed candle close); OB with no clear displacement follow-through | ×0.80 |

**Specific grade elevations:**
- OB formed immediately AFTER a BSL/SSL sweep → always STRONG (the sweep + OB sequence = highest probability ICT setup)
- FVG gap size > 1.5×ATR(14) → STRONG
- FVG gap size < 0.5×ATR → WEAK (too small to represent institutional imbalance)
- Breaker Block → always minimum NORMAL (it was a real OB that was proven)
- Wyckoff Spring/Upthrust → always STRONG (by definition requires significant false breakout)
- iFVG → inherits grade of the original FVG ×0.9 (slightly degraded after being filled)

**Implementation:**
```cpp
ENUM_SMC_GRADE _CalcGrade(double displacement_range, double atr14, 
                           int swing_touches, bool post_sweep) {
   double dqs = displacement_range / atr14;
   if(post_sweep || dqs >= 2.0) return GRADE_STRONG;
   if(dqs >= 1.0)               return GRADE_NORMAL;
   return GRADE_WEAK;
}
```

---

### ═══ EXTENSION 3: State Tracking (5 Lifecycle States per Level) ═══

**What it is:** Every SMC level progresses through a defined lifecycle. The state determines: current weight multiplier, whether the level is displayed, and whether the level triggers any signals.

**The 5 states and their logic:**

| State | Definition | Weight Multiplier | Display |
|-------|-----------|-------------------|---------|
| **FRESH** | Level just formed, 0–5 bars on native TF. Zero visits. | ×1.00 | Brightest color |
| **ACTIVE** | > 5 bars old, price has NOT returned to the zone. Orders still fully intact. | ×0.95 | Full color |
| **TESTED** | Price touched the zone ONCE (wick entered the zone boundaries). One partial absorption. | ×0.85 | Standard color |
| **MITIGATED** | Price body entered > 50% of the zone depth. Significant order consumption. | ×0.65 | Faded color |
| **INVALIDATED** | Body close through the zone in the opposite direction. Level removed from active pool. | ×0.00 | Removed |

**State transitions:**

```
FRESH → ACTIVE       : when bar_count > 5 on native TF
FRESH/ACTIVE → TESTED: when price wick enters zone boundary once
TESTED → MITIGATED   : when price body enters > 50% depth of zone
ANY → INVALIDATED    : when body close exits through zone boundary
FRESH/ACTIVE → INVALIDATED: if price blows through without stopping
```

**Special invalidation rules by type:**
- **OB (C1/C2) Invalidation:** Body close BELOW the OB's LOW (for Bullish OB) or ABOVE the OB's HIGH (for Bearish OB) → invalidated. The OB simultaneously creates a Breaker Block (C3/C4) at invalidation.
- **FVG (D1/D2) Invalidation:** Body close that completes filling the entire gap (price body covers from Candle3-Low to Candle1-High) → creates iFVG (D3/D4).
- **BOS Level (A1–A6) Invalidation:** When price body-closes back THROUGH the BOS level from the opposite side → the structure is negated.
- **BSL/SSL (E1/E2) Invalidation:** After the sweep (E3/E4) — the BSL transitions to E3 state rather than being deleted.
- **Wyckoff (J1–J4) Invalidation:** Price body-closes below the Spring low (for J1) or above the Upthrust high (for J2) → the Wyckoff pattern is negated.

**Implementation note:** State tracking requires per-level `last_body_close`, `max_wick_entry`, `zone_depth` variables updated on each bar close. This is a persistent state machine per level.

---

### ═══ EXTENSION 4: Full TF Coverage (×15) ═══

**What it is:** ALL 63 SMC types are detected and maintained independently on ALL 15 timeframes. No TF is excluded from SMC detection (though display can be gated).

**TF significance for each SMC category:**

| TF Group | Significance | SMC Authority |
|----------|-------------|---------------|
| MN1/W1 | Macro institutional | OBs: central bank / fund-level. FVGs: months to fill. BSL: macro stop-clusters. |
| D1/H12 | Daily institutional | Most-discussed "standard" SMC OB/FVG. Daily trader positioning. |
| H8/H4 | Swing trading | Core ICT reference TFs. OBs here = 4H / swing trader levels. |
| H2/H1 | Intraday | Active FX bank trader references. Kill Zone levels. |
| M30/M15 | Entry TF | ICT recommends M15 FVG/OB for entries triggered from H4 setups. |
| M10/M6/M5 | Precision entry | Very short-term OBs, FVGs. Only valid in context of higher TF alignment. |
| M3/M1 | Scalp | Noise-heavy. Gated off by default (InpSMCBelowM5 = false). |

**TF base weight applies directly:** A D1 Bullish OB (TF_base = 9.0) × grade_mult × type_mult vs M15 Bullish OB (TF_base = 3.0) × grade_mult × type_mult → D1 OB is 3× stronger at minimum before grade/state modifiers.

**Gating settings:** Similar to existing `InpTLBelowM15` parameter:
- `InpSMCBelowM15 = false` (default) — M1/M3/M5/M6/M10 SMC disabled by default
- Can be enabled for scalping contexts

---

### ═══ EXTENSION 5: Multi-TF SMC Alignment ═══

**What it is:** When the SAME SMC type (same category) occurs at approximately the same price on TWO OR MORE different timeframes simultaneously, this is multi-TF alignment — an exponentially stronger signal than any single-TF level.

**Detection logic:**
```
For each SMC level on TF_high (e.g., D1 Bullish OB at price 1.0850):
   For each SMC level of same category on TF_low (e.g., H4 Bullish OB):
      If |TF_low.zone_mid - TF_high.zone_mid| <= 2 × ATR(14, TF_low):
         → Multi-TF Alignment detected at this price
         → Merge into single zone, apply confluence bonus
```

**Weight bonus:**
- 2-TF alignment: +0.5 (same as 2-method WM_CONF_BONUS)
- 3-TF alignment: +1.0
- 4+-TF alignment: +1.5 (same cap as maximum confluence)

**Practical meaning by type:**
- **D1 OB + H4 OB** at same price: institutions on two holding periods both placed orders here — daily traders AND swing traders. Doubly significant.
- **W1 BSL + D1 BSL** at same swing high: both weekly and daily stop clusters at the same level — enormous liquidity pool.
- **D1 FVG + H1 FVG** overlapping: the imbalance is visible on both macro and micro timeframes — highly unfilled, algorithm targeting confirmed.
- **D1 CHoCH + H4 CHoCH** at same lower-high level: two timeframes confirming the same structural shift simultaneously.

**Implementation:**
`_CheckMultiTFSMCAlignment(SMCLevel levels[], int count)` — runs after ALL TF detection completes, creates merged zone objects with elevated weight.

---

### ═══ EXTENSION 6: SMC-Fibonacci Confluence ═══

**What it is:** SMC levels that coincide with Fibonacci retracement levels on the SAME timeframe are the highest-probability institutional setups in the ICT methodology. This is not accidental — ICT explicitly states that OBs and FVGs at Fibonacci levels represent the best trade locations.

**Specific high-significance confluences:**

| SMC Type | Fibonacci Level | Significance | ICT Name |
|----------|----------------|-------------|----------|
| Bullish OB / FVG | 61.8% retracement | ★★★★★ | "Golden OB" / "Golden FVG" |
| Bullish OTE (F4) | 61.8%–79% range | ★★★★★ | OTE zone (by definition Fibonacci) |
| Bearish OB / FVG | 61.8% retracement (of upswing) | ★★★★★ | "Golden Bearish OB" |
| Any OB/FVG | 50% (equilibrium) | ★★★★ | OB at Fair Value |
| Any OB/FVG | 38.2% | ★★★ | Shallow OB |
| BOS Level | 0% or 100% | ★★★★ | Structural Fibonacci |
| BSL/SSL | 127.2% or 161.8% extension | ★★★★ | Fibonacci extension liquidity |

**Implementation:**
- After Fibonacci levels are built by `_BuildFibLevels()`, run `_CheckSMCFibConfluence()` that cross-references SMC zone midpoints against all active Fibonacci levels on the same TF within 2-pip tolerance
- Matching → apply WM_CONF_BONUS based on method count (SMC + Fibonacci = 2 methods = +0.5)
- If the specific match is OB at 61.8% → override bonus to +0.8 (special "Golden" bonus above standard)

**Why it matters architecturally:** Fibonacci and SMC levels are detected by completely independent algorithms. When both point to the same price → two separate detection systems with zero shared logic confirming the same S/R → highest possible confidence.

---

### ═══ EXTENSION 7: SMC-Round Number Confluence ═══

**What it is:** SMC levels (especially BSL/SSL and OBs) that coincide with round number price levels create exponentially stronger stops clusters and institutional order concentration.

**Standard behavior (already in P2.29):** Any level within 2 pips of a round number receives +0.3 bonus.

**Enhanced SMC-specific logic:**

**BSL/SSL at Round Number — Double Stop Clustering:**
- Retail traders place stops at round numbers AND at swing highs/lows
- When a BSL level (equal highs) is ALSO at a round number = BOTH types of stop-clustering coincide
- Stop volume is doubled (retail swing stops + round number stops)
- Enhanced bonus: `+0.6` instead of standard `+0.3`
- Logic: `if (level.type == E1_BSL || level.type == E2_SSL) && round_proximity → bonus × 2.0`

**OB at Round Number — Institutional Precision:**
- Institutions often deliberately place order blocks AT round numbers (institutional price levels)
- An OB whose midpoint is exactly at a round number = intentional institutional construction
- Standard `+0.3` applies (no doubling — not stop-clustering, but precision placement)

**AMD Manipulation at Round Number:**
- The Judas Swing (I2/I3) terminating at a round number = the fake spike was designed to reach the round level specifically (known stop cluster above/below)
- This confirms the AMD manipulation level at a doubly significant price

**Round Number confirmation of OTE:**
- If the Bullish OTE zone (F4) contains a 25-pip or 50-pip round number = OTE confirmation
- The round level WITHIN the OTE zone elevates the entire zone weight

---

### ═══ EXTENSION 8: Kill Zone Timing Context ═══

**What it is:** ICT defines three primary Kill Zones — time windows when institutional activity (particularly SMC-defined setups) is highest probability. SMC levels that are TESTED during Kill Zones have elevated significance.

**Kill Zone windows (New York time):**

| Kill Zone | NY Time | London Time | Characteristics |
|-----------|---------|-------------|----------------|
| **Asian KZ** | 8:00 PM – 12:00 AM | 01:00 – 05:00 | Creates initial range; CRT session high/low formed here |
| **London KZ** | 2:00 AM – 5:00 AM | 07:00 – 10:00 | Highest liquidity; sweeps Asian range; OBs/FVGs formed here |
| **NY KZ** | 7:00 AM – 10:00 AM | 12:00 – 15:00 | FOMC, NFP, NY open reversal; Silver Bullet window |
| **NY Lunch** | 12:00 PM – 1:00 PM | 17:00 – 18:00 | Dead zone — low SMC reliability |

**Implementation as attribute:**
- Each SMC level gets a `kz_activation` flag: NONE / ASIAN / LONDON / NY
- When current bar time falls within a Kill Zone AND price is within 10 pips of an SMC level: `kz_active = true`
- While `kz_active`: temporary weight boost `KZ_BONUS = 0.4` added to the level weight
- After Kill Zone window closes: `KZ_BONUS` removed (base weight unchanged)
- Levels are NOT promoted permanently — KZ activation is time-decaying

**Kill Zone formation of new levels:**
- An OB or FVG FORMED during a Kill Zone is automatically graded as STRONG (institutional activity confirmed by session timing)
- Asian session high/low = CRH/CRL for that session (G1/G2 types)

**Display:** During active Kill Zone, SMC levels within range show a time-indicator — e.g., clock icon or glow effect showing "LONDON KZ ACTIVE" — alerting trader that current SMC levels are in their highest-probability window.

---

### ═══ EXTENSION 9: IPDA Draw-on-Liquidity ═══

**What it is:** ICT's Interbank Price Delivery Algorithm (IPDA) theory: algorithmic price delivery is governed by 20-day, 40-day, and 60-day reference ranges. The algorithm "draws" price toward the extremes of these ranges as targets.

**IPDA Reference Levels:**
```
IPDA_20_HIGH = highest high of last 20 trading days (D1 TF)
IPDA_20_LOW  = lowest low of last 20 trading days
IPDA_40_HIGH = highest high of last 40 trading days
IPDA_40_LOW  = lowest low of last 40 trading days
IPDA_60_HIGH = highest high of last 60 trading days
IPDA_60_LOW  = lowest low of last 60 trading days
```

**How IPDA interacts with SMC:**
- When an SMC level (OB, FVG, BSL) coincides with an IPDA boundary price = the IPDA confirms the SMC level as an algorithmic delivery target
- Example: H4 Bullish OB at 1.0850. IPDA_20_LOW is also at 1.0852. The algorithm is coded to deliver price toward this low → the OB level is on the algorithm's path → elevated weight.

**Directional bias from IPDA:**
- If price is BELOW the IPDA_20_HIGH → the algorithm has a draw on liquidity UPWARD (toward the high). All bullish SMC levels elevated. Bearish SMC slightly reduced.
- If price is ABOVE the IPDA_20_HIGH → draw is DOWNWARD (algo already took the level; now seeks the low). Bearish SMC elevated.

**Implementation:**
- `_BuildIPDALevels()` → calculates the 6 IPDA levels on D1 TF (rolling window)
- `_CheckIPDAAlignment(smcLevel)` → checks if any IPDA level is within 5 pips of the SMC zone midpoint
- If aligned: `IPDA_ALIGNMENT = true` → `weight += 0.5` (equivalent to 2-method confluence)
- Directional bias score: SMC level in the direction of IPDA draw → `weight += 0.2`

---

### ═══ EXTENSION 10: Displacement Quality Score (DQS) ═══

**What it is:** OBs and FVGs are CREATED by displacement moves. The quality of that displacement — how fast, how far, how clean — directly determines how much institutional participation existed and therefore how strong the created S/R level is. DQS quantifies this.

**DQS formula:**
```cpp
double DQS = (displacement_range / ATR14) × (1.0 / sqrt(bar_count));
// displacement_range = total range of the displacement (high - low)
// ATR14 = 14-period ATR on the level's native TF
// bar_count = number of candles forming the displacement (1-3)
// sqrt() dampens the penalty for multi-candle but still rewards single-candle
```

**DQS thresholds → Grade mapping:**

| DQS | Grade | Weight Mult | Interpretation |
|-----|-------|-------------|----------------|
| ≥ 2.5 | STRONG+ | ×1.30 | Explosive institutional entry — rare and extremely significant |
| 2.0–2.5 | STRONG | ×1.20 | Clear institutional displacement |
| 1.0–2.0 | NORMAL | ×1.00 | Standard displacement |
| 0.5–1.0 | WEAK | ×0.80 | Modest move — reduced institutional footprint |
| < 0.5 | VERY WEAK | ×0.60 | Below ATR — questionable as true OB |

**Additional DQS sub-factors:**

- **FVG gap within displacement:** If the displacement candle also leaves an FVG (D1/D2) → the OB that preceded it gains +0.15 weight bonus. The FVG confirms the displacement was aggressive (gaps only form in true displacement).
- **Wick-to-body ratio:** If the displacement candle's BODY is > 75% of its total range (minimal wicks) → DQS × 1.1 (clean candle = one-sided delivery, no hesitation).
- **Volume confirmation (where available):** If volume data available AND displacement candle volume > 1.5× 20-bar average → DQS × 1.15.

**Implementation:**
```cpp
struct SMC_LEVEL {
   double dqs;              // stored at creation
   double grade_mult;       // computed from dqs
   int    displacement_bars;
   bool   has_internal_fvg;
   double displacement_range;
};
```
DQS is calculated ONCE when the level is first detected and stored. It does not change over time (the displacement is a historical fact).

---

### ═══ EXTENSION 11: Zone Freshness Decay ═══

**What it is:** Unlike Swing H/L where significance grows with touch count (up to 3 touches), SMC levels decay with TIME. An OB that was formed 200 bars ago on H4 without being tested has had its institutional orders potentially cancelled, moved, or consumed by other mechanisms. Freshness Decay models this temporal degradation.

**Decay model (bar-count based, native TF):**

| Age (bars on native TF) | Decay Multiplier | Label |
|-------------------------|-------------------|-------|
| 0–5 | 1.00 | Fresh |
| 6–20 | 0.95 | Recent |
| 21–50 | 0.85 | Aged |
| 51–100 | 0.75 | Old |
| 101–200 | 0.65 | Ancient |
| > 200 | 0.55 | Stale (consider removal) |

**ATR-adaptive thresholds:**
- High volatility (current ATR > 1.5× 50-bar average ATR): compress thresholds × 0.7 (levels age faster — high volatility = faster order consumption)
- Low volatility (current ATR < 0.7× average): expand thresholds × 1.4 (levels stay fresh longer — price is moving slowly, orders persist)

**Decay exceptions and resets:**

| Condition | Effect |
|-----------|--------|
| Price tests the EDGE of the zone (wick enters) | Decay clock RESETS to 0 (the test proved the level is active — fresh institutional reaction) |
| Price touches CE of FVG (D5/D6) | Decay partially resets to "Recent" bar count |
| Breaker Block (C3/C4) | Decay rate is halved — structural flips age slower |
| Wyckoff levels (J1–J4) | Fixed at "Aged" multiplier (0.85) from creation — they are by nature already-completed patterns |
| BOS levels (A1–A6) | Decay at standard rate but minimum of 0.70 (never below Old — BOS creates permanent structural reference) |
| iFVG (D3/D4) | Inherits the age of the original FVG at the time of inversion |

**Display implication:** Stale levels (> 200 bars) can optionally be hidden or shown in a visually different style to reduce chart clutter — configurable via `InpSMCMaxAge`.

---

### ═══ EXTENSION 12: Liquidity Pool Depth ═══

**What it is:** Not all BSL and SSL levels are equal. The DEPTH of a liquidity pool — how many stop-loss orders are actually resting at that level — determines how violently price will react when it reaches the pool and how significant the level is as a reference.

**Pool depth measurement:**

**Equal High/Low Count (for BSL/SSL):**
```
depth_count = number of swing highs within 2 pips of the BSL price
```

| Equal High Count | Depth Label | Weight Bonus |
|-----------------|-------------|-------------|
| 1 | Single BSL | +0.0 |
| 2 | Double Top BSL | +0.3 |
| 3 | Triple Top BSL | +0.6 |
| 4 | Quad BSL | +0.9 |
| 5+ | Deep Pool BSL | +1.2 (capped at +1.2) |

Same scale applies for equal lows → SSL depth.

**Prior Period Amplification:**
- BSL level that is ALSO a PDH/PWH/PMH → additional +0.4 (institutional daily/weekly reference adds to stop cluster density)
- BSL that is ALSO a Round Number → additional +0.3 (three-layer stop clustering: swing stops + period-high stops + round number stops)
- Maximum total depth bonus for a single BSL level: capped at +1.5

**Pool depletion after a sweep:**
- Partial sweep (wick through, body not above): pool depth reduced by ~30% → weight bonus decreases proportionally
- Full sweep (E3 BSL Swept): original BSL pool largely consumed → pool depth reset to 0 for that level. A new post-sweep high is created at the sweep wick extreme (new SSL forms at the wick bottom where institutions sold into the sweep).

**Sell-side pool depth:**
- Equal lows count exactly mirrors the equal highs logic
- PDL/PWL/PML coincidence → +0.4
- After SSL sweep: new BSL forms at the wick high

**Dynamic pool tracking:**
```cpp
struct SMC_LEVEL {
   int    equal_HL_count;     // updated on each bar close
   double depth_bonus;        // = f(equal_HL_count) + period_bonus + round_bonus
   bool   partially_swept;    // flag
   double sweep_reduction;    // applied when partially_swept
};
```

`_UpdateLiquidityPoolDepth()` is called on each bar close — it re-scans all BSL/SSL levels and recounts equal highs/lows as new swings form or old swings are broken, keeping pool depth dynamically accurate.

---

## PART 5 — COMPLETE SUMMARY TABLE

| | Value |
|---|---|
| Current coded types | 6 |
| Extended types | **63 across 11 categories** |
| Dimensions | Grade ×3 · TF ×15 · State ×5 |
| **TOTAL SMC level types** | **63 × 3 × 15 × 5 = 14,175** |
| AI Extensions — count-contributing | 4 (type expansion, grade, state, TF) |
| AI Extensions — attribute/contextual | 8 (multi-TF align, Fib confluence, round# confluence, kill zone, IPDA, DQS, freshness decay, pool depth) |
| **Total AI Extensions** | **12** |
| Concepts absorbed (no separate count) | CRT/CRH/CRL (→ G1–G5) and SBR/RBS (→ H1–H2) |
| Running total if locked | 40,074 + 14,175 = **54,249** |

---

**Confirm and lock SMC at 14,175 → move to Concept #10?**