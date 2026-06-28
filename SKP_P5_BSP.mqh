#ifndef SKP_P5_BSP_MQH
#define SKP_P5_BSP_MQH

//════════════════════════════════════════════════════════════════════
//  ⚙️  SK TRADE PREMIUM BOT v6.0 — PART 5
//  ENGINE 10 — Broker Sanity + Blackout Engine
//  ENGINE 11 — Regime Classification Engine
//  ENGINE 12 — Portfolio Watchlist Engine
//  ENGINE v5.0a — Spike Detection Engine
//  ENGINE v5.0b — News Filter Engine
//  ENGINE v5.0c — Volume Momentum Engine
//  ENGINE SUP   — Symbol Profile Engine (Asset Class Auto-Detection)
//  ─────────────────────────────────────────────────────────────────
//  Spec refs: v6.md §Engines 10-16, v4.md §v5.0 additions
//  ─────────────────────────────────────────────────────────────────
//  ASSEMBLY NOTE — P4 Compatibility Defines
//  P4 was written with simplified input names before P1 was finalized.
//  These #define aliases bridge the gap. In the merged single-file EA,
//  place this block immediately after P1 (before P4 code sections).
//  All aliases are transparent zero-cost preprocessor substitutions.
//
//  P4 name                    →  Actual P1 input / expression
//  ─────────────────────────────────────────────────────────────────
//  InpLotMode                 →  InpLotControlMode
//  InpRiskPercent             →  (mode-specific — see ActiveRiskPct())
//  InpManualLot               →  (mode-specific — see ActiveManualLot())
//  InpMinLotCap               →  (mode-specific — see ActiveMinLot())
//  InpMaxLotCap               →  (mode-specific — see ActiveMaxLot())
//  InpApplyLossSmoothToAutoLots → InpApplyLossSmoothToAuto
//  InpUseSymbolPresets        →  InpUseSymbolPresetMap
//  InpPresetCSV               →  (see SymbolPresetRiskMultiplier below)
//  InpScoreMinModerate        →  InpModerateMinScore
//  InpScoreMinScalper         →  InpScalpMinScore
//  InpUsePortfolioEngine      →  InpUsePortfolioWatchlist
//  InpPortfolioMaxRankToTrade →  InpPortfolioMaxTradableRanks
//  InpPortfolioScoreGapBlock  →  InpPortfolioMinScoreGap
//  InpUseReverseExit          →  InpCloseOnOppositeSignal
//════════════════════════════════════════════════════════════════════

// P4 compatibility aliases are defined in P1B_COMPAT (before P4 in assembly).
// They are NOT redefined here to avoid macro-redefinition errors.
// InpUseReverseExit → InpCloseOnOppositeSignal is also in P1B_COMPAT.

//─── Mode-aware lot/risk accessors (inline functions — zero overhead) ─
//    Used by P4's ResolveModeLotSize and TryNewEntry
//
//    v6.3g FIX: Added BOT_MODE_HFT branches to all four accessors.
//    Previously HFT fell through to Moderate values, causing:
//      • ActiveRiskPct()  → InpModerateRiskPercent  (WRONG: should be InpHFTRiskPercent)
//      • ActiveManualLot()→ InpModerateManualLot    (WRONG: should be InpHFTManualLot)
//    This broke lot sizing, gRt_RiskPct baseline, and risk profile scaling.
double ActiveRiskPct()
{
   if(InpMode == BOT_MODE_HFT || InpMode == BOT_MODE_HFT_PURE) return InpHFTRiskPercent;
   if(InpMode == BOT_MODE_SCALPING) return InpScalpRiskPercent;
   return InpModerateRiskPercent;
}
double ActiveManualLot()
{
   if(InpMode == BOT_MODE_HFT || InpMode == BOT_MODE_HFT_PURE) return InpHFTManualLot;
   if(InpMode == BOT_MODE_SCALPING) return InpScalpManualLot;
   return InpModerateManualLot;
}
double ActiveMinLot()
{
   // HFT shares Moderate min/max caps (no dedicated HFT inputs for these)
   return (InpMode == BOT_MODE_SCALPING) ? InpScalpMinLot : InpModerateMinLot;
}
double ActiveMaxLot()
{
   return (InpMode == BOT_MODE_SCALPING) ? InpScalpMaxLot : InpModerateMaxLot;
}

//─── Override ClampModeLot (P4) to use correct mode-split caps ────────
//    This re-definition supersedes P4's version in the merged file.
//    (MQL5: later-defined function with same name → linker uses last)
//    Note: in practice, use unique naming in final assembly to avoid any
//    duplicate symbol warning; this pattern is for demonstration.

//════════════════════════════════════════════════════════════════════
//  PART 5 — ADDITIONAL GLOBAL STATE
//  Declared here (not in P1) for new engines introduced in Part 5.
//════════════════════════════════════════════════════════════════════

//─── Portfolio watchlist handle arrays (persistent, created in ParseWatchlistCSV) ──
string  g_WatchSymbols[32];               // Parsed symbol names
int     g_WatchCount   = 0;               // Number of valid watchlist symbols
int     g_hPortEMA9H1[32];               // H1 EMA9 handle per watchlist symbol
int     g_hPortEMA34H1[32];              // H1 EMA34 handle
int     g_hPortRSIH1[32];               // H1 RSI handle
int     g_hPortATRM5[32];               // M5 ATR handle
int     g_hPortEMA9M5[32];              // M5 EMA9 (for LTF cross)
int     g_hPortEMA34M5[32];             // M5 EMA34 (for LTF cross)
bool    g_PortHandlesReady[32];          // true when all handles valid

//─── Volume momentum engine handles ──────────────────────────────────
int     g_hVolM5 = INVALID_HANDLE;      // M5 tick volume indicator handle
int     g_hVolM1 = INVALID_HANDLE;      // M1 tick volume indicator handle

//─── Regime engine: ATR history buffer ───────────────────────────────
double  g_RegimeATRBuf[50];             // Rolling ATR history for average
int     g_RegimeATRBufCount = 0;        // Filled slot count

//─── Symbol profile (loaded in OnInit, immutable after) ──────────────
string  g_AssetClass = "FOREX";         // Detected asset class label

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE 10 — BROKER SANITY + BLACKOUT ENGINE
//  Runs as the FIRST operation in OnTick (before any signal logic).
//  Populates gBroker (BrokerSanityState) completely before any engine
//  reads from it. The hostileNow composite flag gates scalp exits,
//  regime classification, and score penalty application.
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §10.1 — BLACKOUT WINDOW PARSER
//  Format: "HHMM-HHMM" (e.g. "2200-0200" = block 22:00 to 02:00)
//  "0000-0000" = disabled window (both start and end zero)
//════════════════════════════════════════════════════════════════════

bool ParseBlackoutWindow(string windowStr, int &startMins, int &endMins)
{
   StringTrimLeft(windowStr);
   StringTrimRight(windowStr);

   // Disabled window
   if(windowStr == "0000-0000" || windowStr == "" || StringLen(windowStr) < 9)
   {
      startMins = 0;
      endMins   = 0;
      return false;
   }

   // Split on '-'
   string parts[];
   if(StringSplit(windowStr, '-', parts) < 2)
   {
      Print("⚠️ E10: ParseBlackoutWindow — invalid format: '", windowStr, "'");
      return false;
   }

   string s = parts[0]; // "HHMM"
   string e = parts[1]; // "HHMM"

   if(StringLen(s) < 4 || StringLen(e) < 4) return false;

   int sh = (int)StringToInteger(StringSubstr(s, 0, 2));
   int sm = (int)StringToInteger(StringSubstr(s, 2, 2));
   int eh = (int)StringToInteger(StringSubstr(e, 0, 2));
   int em = (int)StringToInteger(StringSubstr(e, 2, 2));

   // Validate ranges
   if(sh > 23 || sm > 59 || eh > 23 || em > 59) return false;

   startMins = sh * 60 + sm; // minutes since midnight
   endMins   = eh * 60 + em;

   return true;
}

//--- Check if current broker time is inside any of the 3 blackout windows
bool IsInBlackoutWindow()
{
   if(!InpUseManualBlackout) return false;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int nowMins = now.hour * 60 + now.min;

   string wins[3];
   wins[0] = InpBlackoutWindow1;
   wins[1] = InpBlackoutWindow2;
   wins[2] = InpBlackoutWindow3;

   for(int i = 0; i < 3; i++)
   {
      int startM, endM;
      if(!ParseBlackoutWindow(wins[i], startM, endM)) continue;
      if(startM == 0 && endM == 0) continue; // disabled

      // Handle midnight crossing (e.g. 22:00 → 02:00)
      if(endM < startM) // wraps midnight
      {
         if(nowMins >= startM || nowMins <= endM) return true;
      }
      else // normal range (e.g. 07:00 → 22:00)
      {
         if(nowMins >= startM && nowMins <= endM) return true;
      }
   }
   return false;
}

//════════════════════════════════════════════════════════════════════
//  §10.2 — RefreshBrokerSanity() — Every-Tick Hostility Monitor
//  Must be called as the FIRST non-tick-buffer operation in OnTick.
//  All sub-checks are guarded by their respective feature toggles.
//  Populates gBroker completely each tick — no partial updates.
//════════════════════════════════════════════════════════════════════

void RefreshBrokerSanity()
{
   if(!InpUseBrokerSanityChecks)
   {
      // Feature disabled — reset all flags to clean state
      gBroker.spreadShock       = false;
      gBroker.tickVelocityShock = false;
      gBroker.gapShock          = false;
      gBroker.stopLevelHostile  = false;
      gBroker.freezeLevelHostile = false;
      gBroker.pendingDistanceBad = false;
      gBroker.blackoutActive    = false;
      gBroker.hostileNow        = false;
      return;
   }

   double atr      = GetATR(IDX_M5, 1);  // last closed bar ATR
   double ask      = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   double spreadPt = (ask - bid) / gPoint;

   //── Spread shock check ─────────────────────────────────────────────
   // Cap = ATR × SpreadATRFactor × RegimeMultiplier (wider allowance in EXPLOSIVE)
   double spreadCap = (atr / gPoint) * InpSpreadATRFactor * RegimeSpreadMultiplier();
   gBroker.spreadNow = spreadPt;
   gBroker.spreadCap = spreadCap;
   gBroker.spreadShock = InpUseSpreadShockFilter
                         && (spreadPt > spreadCap * InpSpreadShockFactor);

   //── Tick velocity shock check ──────────────────────────────────────
   // Compute price range across last InpVelocitySampleTicks entries
   // in the circular tick buffer (shared with spike engine)
   gBroker.tickVelocityShock = false;
   gBroker.velocityPts       = 0.0;

   if(InpUseTickVelocityFilter && gSpike.tickBufCount >= 2)
   {
      int samples  = MathMin(gSpike.tickBufCount, InpVelocitySampleTicks);
      double maxP  = -1e15, minP = 1e15;
      int startIdx = (gSpike.tickBufIdx - samples + 64) % 64;

      for(int i = 0; i < samples; i++)
      {
         int bi  = (startIdx + i) % 64;
         double p = gSpike.tickPriceBuf[bi];
         if(p > maxP) maxP = p;
         if(p < minP) minP = p;
      }

      gBroker.velocityPts       = SafeDiv(maxP - minP, gPoint);
      gBroker.tickVelocityShock = (gBroker.velocityPts > SafeDiv(atr, gPoint) * InpTickVelocityATRFactor);
   }

   //── Bar gap shock check ────────────────────────────────────────────
   // Gap = |current bar open − previous bar close| on M5
   gBroker.gapShock = false;
   gBroker.lastGap  = 0.0;

   if(InpUseGapShockFilter)
   {
      double curBarOpen[1];
      if(CopyOpen(gSymbol, PERIOD_M5, 0, 1, curBarOpen) >= 1)
      {
         double prevClose = gTF[IDX_M5].close0; // last closed bar's close
         gBroker.lastGap  = MathAbs(curBarOpen[0] - prevClose) / gPoint;
         gBroker.gapShock = (gBroker.lastGap > SafeDiv(atr, gPoint) * InpGapATRFactor);
      }
   }

   //── Stop level hostility check ─────────────────────────────────────
   // If broker's minimum stop distance exceeds a fraction of ATR,
   // it becomes impossible to place tight SLs → hostile for scalping
   gBroker.stopLevelHostile = false;
   if(InpUseStopLevelCheck)
   {
      long   stopLvlRaw = SymbolInfoInteger(gSymbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStop    = stopLvlRaw * gPoint;
      gBroker.stopLevelHostile = (minStop > atr * InpMaxStopLevelATRFactor);
   }

   //── Freeze level hostility check ───────────────────────────────────
   // Freeze level > 0 means open positions cannot be modified within
   // that distance from price — hostile for TSL management
   gBroker.freezeLevelHostile = false;
   if(InpUseFreezeLevelCheck)
   {
      long   freezeLvlRaw = SymbolInfoInteger(gSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double freezeLvl    = freezeLvlRaw * gPoint;
      // Hostile if freeze level is > 20% of ATR
      gBroker.freezeLevelHostile = (freezeLvl > atr * 0.20 && freezeLvlRaw > 0);
   }

   //── Pending distance check (scalper context) ───────────────────────
   // Checks whether the best limit entry price would be within
   // SYMBOL_TRADE_STOPS_LEVEL of current price (invalid pending)
   gBroker.pendingDistanceBad = false;
   if(InpMode == BOT_MODE_SCALPING && InpUseDynamicSpreadFilter)
   {
      double offsetDist = (double)InpPendingOffsetPoints * gPoint;
      double limitPrice = (gSignal.bias == BIAS_BULL) ? (bid - offsetDist) : (ask + offsetDist);
      double pendingDist = MathAbs(bid - limitPrice) / gPoint;
      // Pending too close: broker will reject (stops level violation)
      gBroker.pendingDistanceBad = (pendingDist < gMinStopLevel / gPoint * 1.2);
   }

   //── Manual blackout windows ────────────────────────────────────────
   gBroker.blackoutActive = IsInBlackoutWindow();

   //── Spike propagation ──────────────────────────────────────────────
   // Spike state is managed by Spike Engine (called earlier in OnTick)
   // Here we just copy the result into gBroker for composite evaluation
   gBroker.spikeDetected = gSpike.spikeDetected;
   gBroker.newsActive    = gNews.active;

   //── hostileNow COMPOSITE ───────────────────────────────────────────
   // True when ANY critical condition is active. Used by:
   // - Regime engine (HOSTILE classification)
   // - HandleHostileScalpExposure (protective close)
   // - TryNewEntry (implicit via safety checks)
   gBroker.hostileNow = gBroker.spreadShock
                      || gBroker.tickVelocityShock
                      || gBroker.gapShock
                      || gBroker.stopLevelHostile
                      || gBroker.freezeLevelHostile
                      || gBroker.spikeDetected;

   // Build human-readable reason string (for PushDiag and Telegram)
   if(gBroker.hostileNow)
   {
      string reasons = "";
      if(gBroker.spreadShock)        reasons += "SpreadShock ";
      if(gBroker.tickVelocityShock)  reasons += "VelShock ";
      if(gBroker.gapShock)           reasons += "GapShock ";
      if(gBroker.stopLevelHostile)   reasons += "StopLvlHostile ";
      if(gBroker.freezeLevelHostile) reasons += "FreezeLvlHostile ";
      if(gBroker.spikeDetected)      reasons += "SPIKE ";
      StringTrimRight(reasons);   // modifies in-place (void in MQL5)
      gBroker.reason = reasons;
   }
   else
   {
      gBroker.reason = "CLEAN";
   }
}

//════════════════════════════════════════════════════════════════════
//  §10.3 — HandleHostileScalpExposure()
//  Protective risk reduction: close PROFITABLE scalp positions when
//  broker conditions turn hostile or a spike is detected.
//  Logic: only close PROFITABLE positions (float > 0) to lock in
//  gains. Losing positions are left for SL management — closing them
//  would crystalize losses at the worst possible moment.
//════════════════════════════════════════════════════════════════════

void HandleHostileScalpExposure()
{
   if(!InpUseScalpHostileExit) return;

   // Only act when hostile or spike detected
   bool shouldAct = gBroker.hostileNow || gSpike.spikeDetected;
   if(!shouldAct) return;

   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active)        continue;
      if(!gRec[i].isScalpMode)   continue; // only scalp positions
      if(gRec[i].symbol != gSymbol) continue;

      ulong ticket = gRec[i].ticket;
      if(!PositionExistsByTicket(ticket)) continue;

      // Only close positions with positive floating P&L
      double floatPL = GetPositionFloatPL(ticket);
      if(floatPL <= 0.0)
      {
         // Losing position — skip (SL will handle it)
         PushDiag("⚠️ E10: Hostile — scalp ticket=" + IntegerToString(ticket)
                  + " at loss=" + DoubleToString(floatPL, 2) + " → not closing (SL active)");
         continue;
      }

      // Close full remaining volume to secure profit
      string reason = gSpike.spikeDetected ? "SPIKE_EXIT" : "HOSTILE_SCALP_EXIT";
      bool   ok     = PartialCloseVolumeManagedFull(ticket, reason);

      // Safety event + journal
      RegisterSafetyEvent(reason,
         "ticket=" + IntegerToString(ticket)
         + " PL=" + DoubleToString(floatPL, 2)
         + " broker=" + gBroker.reason);

      JournalWrite("SAFETY",
                   reason,
                   IntegerToString(ticket),
                   DoubleToString(floatPL, 2),
                   gBroker.reason);

      // Telegram alert (queued)
      string emoji   = gSpike.spikeDetected ? "🚨" : "☠️";
      string tgMsg   = "══════════════════════════\n"
                      + emoji + " HOSTILE EXIT — " + reason + "\n"
                      + "──────────────────────────\n"
                      + "📌 " + gSymbol + " ticket=" + IntegerToString(ticket) + "\n"
                      + "💰 P&L secured: +" + DoubleToString(floatPL, 2) + "\n"
                      + "🔬 Reason: " + gBroker.reason + "\n"
                      + "⏰ " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n"
                      + "══════════════════════════";
      TGEnqueue(MSG_EXIT, tgMsg, true /* priority */);

      PushDiag(emoji + " E10: " + reason + " ticket=" + IntegerToString(ticket)
               + " PL=+" + DoubleToString(floatPL, 2) + " secured");
   }
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE 11 — REGIME CLASSIFICATION ENGINE
//  ATR-ratio based 4-state market character classifier.
//  Provides per-regime lot multipliers, score adjustments,
//  spread cap multipliers, and scalp suppression signals.
//  RefreshRegimeState called every tick (lightweight calculation).
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §11.1 — RefreshRegimeState() — ATR-Based Market Character
//  Decision tree (spec §Engine 13 / Regime Engine):
//    HOSTILE   — broker hostile flags or spike active
//    EXPLOSIVE — atrRatio > InpExplosiveATRRatioMin (1.50)
//    QUIET     — atrRatio < InpQuietATRRatioMax (0.70)
//    NORMAL    — all other conditions
//════════════════════════════════════════════════════════════════════

void RefreshRegimeState()
{
   if(!InpUseRegimeEngine) return;

   double atrNow = GetATR(IDX_M5, 1);  // last closed bar ATR on M5
   if(atrNow <= 0.0)
   {
      gRegime.regime = REGIME_UNKNOWN;
      gRegime.label  = "UNKNOWN";
      return;
   }

   // Compute rolling ATR average over InpRegimeLookbackBars
   double atrBuf[50];
   int    copied = CopyBuffer(gTF[IDX_M5].hATR, 0, 1, InpRegimeLookbackBars, atrBuf);
   double atrAvg = 0.0;

   if(copied > 0)
   {
      double sum = 0.0;
      for(int i = 0; i < copied; i++) sum += atrBuf[i];
      atrAvg = SafeDiv(sum, copied);
   }
   else
   {
      // Fallback: use current ATR as its own average
      atrAvg = atrNow;
   }

   double atrRatio = SafeDiv(atrNow, atrAvg);
   double spreadNow = GetSpreadPoints();

   // Store in global state
   gRegime.atrNow    = atrNow;
   gRegime.atrAvg    = atrAvg;
   gRegime.atrRatio  = atrRatio;
   gRegime.spreadNow = spreadNow;
   gRegime.spreadCap = (atrAvg / gPoint) * InpSpreadATRFactor;

   // ── Decision tree (priority: HOSTILE overrides ATR ratio) ──────
   ENUM_MARKET_REGIME prev = gRegime.regime;

   if(gBroker.hostileNow || gSpike.spikeDetected || gBroker.spreadShock || gBroker.tickVelocityShock)
   {
      gRegime.regime = REGIME_HOSTILE;
      gRegime.label  = "HOSTILE";
   }
   else if(atrRatio > InpExplosiveATRRatioMin)
   {
      gRegime.regime = REGIME_EXPLOSIVE;
      gRegime.label  = "EXPLOSIVE";
   }
   else if(atrRatio < InpQuietATRRatioMax)
   {
      gRegime.regime = REGIME_QUIET;
      gRegime.label  = "QUIET";
   }
   else
   {
      gRegime.regime = REGIME_NORMAL;
      gRegime.label  = "NORMAL";
   }

   // Scalp suppressor determination
   gRegime.suppressScalp = RegimeSuppressScalper();

   // Log regime transitions (not every tick — only on change)
   if(gRegime.regime != prev)
   {
      PushDiag("🌡️ E11: Regime → " + gRegime.label
               + " (ATR=" + DoubleToString(atrNow, gDigits + 2)
               + " ratio=" + DoubleToString(atrRatio, 3) + ")");
      JournalWrite("REGIME_CHANGE", gRegime.label,
                   "ratio=" + DoubleToString(atrRatio, 3),
                   "atrNow=" + DoubleToString(atrNow, gDigits + 2),
                   "atrAvg=" + DoubleToString(atrAvg, gDigits + 2));

      // Trigger pending reprice recovery on HOSTILE→NORMAL transition
      if(prev == REGIME_HOSTILE && gRegime.regime == REGIME_NORMAL)
      {
         PushDiag("🔧 E11: Regime HOSTILE→NORMAL — triggering pending reprice recovery");
         ProcessModifyRecovery(); // defined in P4
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  §11.2 — REGIME EFFECT FUNCTIONS
//  Called by ResolveModeLotSize, TryNewEntry score gate,
//  RefreshBrokerSanity spread cap, and TryNewEntry scalp gate.
//  All functions are tiny — called every tick or every entry attempt.
//════════════════════════════════════════════════════════════════════

//--- Lot multiplier by regime (applied as Layer 4 in ResolveModeLotSize)
double RegimeLotMultiplier()
{
   if(!InpUseRegimeEngine) return 1.00;

   switch(gRegime.regime)
   {
      case REGIME_QUIET:     return InpRegimeQuietLotMult;    // 0.75× — low vol = small position
      case REGIME_NORMAL:    return 1.00;                     // full lot in normal conditions
      case REGIME_EXPLOSIVE: return InpRegimeExplosiveLotMult;// 0.60× — big candles = big risk
      case REGIME_HOSTILE:   return InpRegimeHostileLotMult;  // 0.35× — near-minimum exposure
      default:               return 1.00;
   }
}

//--- Score adjustment by regime (added to dynamic minimum in TryNewEntry step 11)
//    Positive = raises min required (harder to qualify)
//    Negative = lowers min required (easier to trigger)
int RegimeScoreAdjustment()
{
   if(!InpUseRegimeEngine) return 0;

   switch(gRegime.regime)
   {
      case REGIME_QUIET:     return  5;   // +5: tighter entry criteria in quiet
      case REGIME_NORMAL:    return  0;   // ±0: no adjustment
      case REGIME_EXPLOSIVE: return -3;   // -3: slight boost in momentum
      case REGIME_HOSTILE:   return 15;   // +15: extremely hard to qualify (near-block)
      default:               return  0;
   }
}

//--- Spread cap multiplier by regime
//    Applied in RefreshBrokerSanity: spreadCap × this multiplier
double RegimeSpreadMultiplier()
{
   if(!InpUseRegimeEngine) return 1.00;

   switch(gRegime.regime)
   {
      case REGIME_QUIET:     return 0.80; // 0.80× — tight tolerance in quiet market
      case REGIME_NORMAL:    return 1.00; // standard
      case REGIME_EXPLOSIVE: return 1.20; // 1.20× — wider tolerance in fast market
      case REGIME_HOSTILE:   return 0.60; // 0.60× — very tight (near-impossible to pass)
      default:               return 1.00;
   }
}

//--- Returns true when scalping should be suppressed in current regime
bool RegimeSuppressScalper()
{
   if(!InpUseRegimeScalpSuppress) return false;

   // Always suppress in HOSTILE (non-negotiable — market is too dangerous)
   if(gRegime.regime == REGIME_HOSTILE) return true;

   // Optionally suppress in QUIET (low volatility → scalp targets unreachable)
   if(gRegime.regime == REGIME_QUIET)   return true;

   return false;
}

//--- HFT-specific regime suppression  — v6.3c
//    HFT trades in 1-2 minutes, does not need H1/H4 alignment.
//    Only hard-block when execution itself is compromised:
//      a) Spike active  → tick data garbage, fills impossible
//      b) Extreme spread shock  → cost kills HFT edge immediately
//    QUIET regime does NOT suppress HFT — low volatility with clear M1
//    momentum is a VALID HFT environment (small, tight, predictable moves).
//    HOSTILE regime via gapShock / stopLevelHostile / freezeLevel does NOT
//    suppress HFT either — those conditions affect limit-order scalp, not
//    market-order HFT with M1-ATR-based ultra-tight SLs.
bool HFTRegimeSuppressed()
{
   if(!InpUseRegimeEngine) return false;

   // Hard block 1: Spike active — M1 tick data is invalid
   if(gSpike.spikeActive)  return true;

   // Hard block 2: Spread shock — HFT edge destroyed by cost
   //   Use double the normal spread cap threshold for HFT
   //   (HFT max spread factor is wider via gRt_MaxSpreadATR)
   if(gBroker.spreadShock) return true;

   // All other conditions (QUIET, HOSTILE-via-gap, freeze-level, stop-level)
   // do not suppress HFT — the M1 signal and ultra-tight SL handle these.
   return false;
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE 12 — PORTFOLIO WATCHLIST ENGINE
//  Multi-symbol quick-scorer running in OnTimer at configurable
//  intervals. Assigns ranks to watchlist symbols and gates entries
//  on the current chart symbol based on portfolio rank arbitration.
//  Max 32 symbols. Quick score = 7-dim lightweight evaluation.
//  Full Fib/Pivot/MTF cascade NOT run per-symbol (too expensive).
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §12.1 — ParseWatchlistCSV()
//  Parses InpPortfolioWatchlist into g_WatchSymbols[] array.
//  Creates persistent indicator handles for each symbol.
//  Called ONCE from OnInit.
//════════════════════════════════════════════════════════════════════

void ParseWatchlistCSV()
{
   g_WatchCount = 0;
   ArrayInitialize(g_hPortEMA9H1,  INVALID_HANDLE);
   ArrayInitialize(g_hPortEMA34H1, INVALID_HANDLE);
   ArrayInitialize(g_hPortRSIH1,   INVALID_HANDLE);
   ArrayInitialize(g_hPortATRM5,   INVALID_HANDLE);
   ArrayInitialize(g_hPortEMA9M5,  INVALID_HANDLE);
   ArrayInitialize(g_hPortEMA34M5, INVALID_HANDLE);
   ArrayInitialize(g_PortHandlesReady, false);

   if(!InpUsePortfolioWatchlist) return;
   if(StringLen(InpPortfolioWatchlist) == 0) return;

   string syms[];
   int n = StringSplit(InpPortfolioWatchlist, ',', syms);

   for(int i = 0; i < n && g_WatchCount < 32; i++)
   {
      string sym = syms[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0) continue;

      // Verify symbol exists in MarketWatch
      if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
      {
         // Try to add symbol to MarketWatch
         if(!SymbolSelect(sym, true))
         {
            Print("⚠️ E12: Symbol '", sym, "' not found in Market Watch — skipping");
            continue;
         }
      }

      g_WatchSymbols[g_WatchCount] = sym;

      // Create persistent handles for this symbol
      g_hPortEMA9H1[g_WatchCount]  = iMA(sym, PERIOD_H1, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
      g_hPortEMA34H1[g_WatchCount] = iMA(sym, PERIOD_H1, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
      g_hPortRSIH1[g_WatchCount]   = iRSI(sym, PERIOD_H1, InpRSIPeriod, PRICE_CLOSE);
      g_hPortATRM5[g_WatchCount]   = iATR(sym, PERIOD_M5, InpATRPeriod);
      g_hPortEMA9M5[g_WatchCount]  = iMA(sym, PERIOD_M5, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
      g_hPortEMA34M5[g_WatchCount] = iMA(sym, PERIOD_M5, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);

      // Validate all handles
      bool valid = (g_hPortEMA9H1[g_WatchCount]  != INVALID_HANDLE) &&
                   (g_hPortEMA34H1[g_WatchCount] != INVALID_HANDLE) &&
                   (g_hPortRSIH1[g_WatchCount]   != INVALID_HANDLE) &&
                   (g_hPortATRM5[g_WatchCount]   != INVALID_HANDLE) &&
                   (g_hPortEMA9M5[g_WatchCount]  != INVALID_HANDLE) &&
                   (g_hPortEMA34M5[g_WatchCount] != INVALID_HANDLE);

      g_PortHandlesReady[g_WatchCount] = valid;

      if(valid)
         Print("✅ E12: Watchlist[", g_WatchCount, "] '", sym, "' — handles created");
      else
         Print("⚠️ E12: Watchlist[", g_WatchCount, "] '", sym, "' — some handles failed (data may be unavailable)");

      g_WatchCount++;
   }

   Print("✅ E12: Portfolio watchlist parsed — ", g_WatchCount, " symbols");
}

//--- Release all watchlist indicator handles (called from OnDeinit)
void ReleaseWatchlistHandles()
{
   for(int i = 0; i < g_WatchCount; i++)
   {
      if(g_hPortEMA9H1[i]  != INVALID_HANDLE) IndicatorRelease(g_hPortEMA9H1[i]);
      if(g_hPortEMA34H1[i] != INVALID_HANDLE) IndicatorRelease(g_hPortEMA34H1[i]);
      if(g_hPortRSIH1[i]   != INVALID_HANDLE) IndicatorRelease(g_hPortRSIH1[i]);
      if(g_hPortATRM5[i]   != INVALID_HANDLE) IndicatorRelease(g_hPortATRM5[i]);
      if(g_hPortEMA9M5[i]  != INVALID_HANDLE) IndicatorRelease(g_hPortEMA9M5[i]);
      if(g_hPortEMA34M5[i] != INVALID_HANDLE) IndicatorRelease(g_hPortEMA34M5[i]);
   }
}

//════════════════════════════════════════════════════════════════════
//  §12.2 — QuickScoreSymbol()
//  Lightweight 7-dimension score for one watchlist symbol.
//  Uses pre-created persistent handles — no handle creation here.
//  Score dimensions (max 85 pts):
//    1. H1 EMA9 vs EMA34 macro alignment:  +20 pts
//    2. H1 RSI quadrant (strong direction): +15 pts
//    3. M5 fresh EMA cross (LTF trigger):   +15 pts
//    4. M5 pattern active (simplified):     +12 pts
//    5. M5 ATR burst (range vs ATR):        +10 pts
//    6. Spread within cap:                   +8 pts
//    7. Session active:                      +5 pts
//════════════════════════════════════════════════════════════════════

void QuickScoreSymbol(int wIdx, PortfolioCandidate &cand)
{
   string sym = g_WatchSymbols[wIdx];

   // Zero-initialize candidate
   cand.valid       = false;
   cand.symbol      = sym;
   cand.bias        = BIAS_NONE;
   cand.bullScore   = 0;
   cand.bearScore   = 0;
   cand.finalScore  = 0;
   cand.rank        = 99;
   cand.tradable    = false;
   cand.spreadOK    = false;
   cand.burstOK     = false;
   cand.macroOK     = false;
   cand.triggerOK   = false;
   cand.rsiOK       = false;
   cand.sessionOK   = false;
   cand.hasExposure = false;
   cand.reason      = "";

   if(!g_PortHandlesReady[wIdx]) { cand.reason = "handles_not_ready"; return; }

   // ── Read indicator buffers ─────────────────────────────────────
   double ema9H1[2], ema34H1[2], rsiH1[2], atrM5[2], ema9M5[3], ema34M5[3];
   bool dataOK = (CopyBuffer(g_hPortEMA9H1[wIdx],  0, 0, 2, ema9H1)  >= 2) &&
                 (CopyBuffer(g_hPortEMA34H1[wIdx], 0, 0, 2, ema34H1) >= 2) &&
                 (CopyBuffer(g_hPortRSIH1[wIdx],   0, 0, 2, rsiH1)   >= 2) &&
                 (CopyBuffer(g_hPortATRM5[wIdx],   0, 0, 2, atrM5)   >= 2) &&
                 (CopyBuffer(g_hPortEMA9M5[wIdx],  0, 0, 3, ema9M5)  >= 3) &&
                 (CopyBuffer(g_hPortEMA34M5[wIdx], 0, 0, 3, ema34M5) >= 3);

   if(!dataOK) { cand.reason = "buffer_read_failed"; return; }

   // ── Determine raw bias from H1 EMA alignment ──────────────────
   bool isMacroBull = (ema9H1[0] > ema34H1[0]);
   bool isMacroBear = (ema9H1[0] < ema34H1[0]);
   cand.macroOK = (isMacroBull || isMacroBear);

   int bullScore = 0, bearScore = 0;

   //── Dimension 1: Macro EMA alignment (H1) +20 ─────────────────
   if(isMacroBull) bullScore += 20;
   if(isMacroBear) bearScore += 20;

   //── Dimension 2: RSI quadrant (H1) +15 ────────────────────────
   // STRONG BULL: RSI > 50 and rising
   // STRONG BEAR: RSI < 50 and falling
   double rsiSlope = rsiH1[0] - rsiH1[1]; // current minus prior
   bool rsiStrongBull = (rsiH1[0] > 50.0 && rsiSlope > 0.0);
   bool rsiStrongBear = (rsiH1[0] < 50.0 && rsiSlope < 0.0);
   if(rsiStrongBull) { bullScore += 15; cand.rsiOK = true; }
   if(rsiStrongBear) { bearScore += 15; cand.rsiOK = true; }

   //── Dimension 3: M5 fresh EMA cross +15 ───────────────────────
   // Bull cross: EMA9 crossed above EMA34 (bar[1] below, bar[0] above)
   bool freshBullCross = (ema9M5[1] <= ema34M5[1] && ema9M5[0] > ema34M5[0]);
   bool freshBearCross = (ema9M5[1] >= ema34M5[1] && ema9M5[0] < ema34M5[0]);
   // Also check 2 bars back for "recent" cross
   if(!freshBullCross)
      freshBullCross = (ema9M5[2] <= ema34M5[2] && ema9M5[1] > ema34M5[1]);
   if(!freshBearCross)
      freshBearCross = (ema9M5[2] >= ema34M5[2] && ema9M5[1] < ema34M5[1]);

   if(freshBullCross) { bullScore += 15; cand.triggerOK = true; }
   if(freshBearCross) { bearScore += 15; cand.triggerOK = true; }

   //── Dimension 4: Pattern active (simplified) +12 ─────────────
   // Quick check: is current M5 bar strongly directional (body > 70% of range)?
   double barHigh[1], barLow[1], barOpen[1], barClose[1];
   bool hasPrice = (CopyHigh(sym,  PERIOD_M5, 1, 1, barHigh)  >= 1) &&
                   (CopyLow(sym,   PERIOD_M5, 1, 1, barLow)   >= 1) &&
                   (CopyOpen(sym,  PERIOD_M5, 1, 1, barOpen)  >= 1) &&
                   (CopyClose(sym, PERIOD_M5, 1, 1, barClose) >= 1);

   if(hasPrice)
   {
      double range = barHigh[0] - barLow[0];
      double body  = MathAbs(barClose[0] - barOpen[0]);
      bool strongBar = (range > 0.0 && SafeDiv(body, range) > 0.65);

      if(strongBar && barClose[0] > barOpen[0]) bullScore += 12; // strong bull bar
      if(strongBar && barClose[0] < barOpen[0]) bearScore += 12; // strong bear bar
   }

   //── Dimension 5: ATR burst +10 ────────────────────────────────
   if(hasPrice && atrM5[0] > 0.0)
   {
      double barRange = barHigh[0] - barLow[0];
      double burstThresh = atrM5[0] * InpScalpBurstATRFactor; // e.g. ATR × 1.25
      if(barRange > burstThresh)
      {
         cand.burstOK = true;
         if(barClose[0] > barOpen[0]) bullScore += 10;
         if(barClose[0] < barOpen[0]) bearScore += 10;
      }
   }

   //── Dimension 6: Spread within cap +8 ────────────────────────
   double symAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
   double symBid = SymbolInfoDouble(sym, SYMBOL_BID);
   double symPt  = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(symPt > 0.0 && atrM5[0] > 0.0)
   {
      double symSpread = (symAsk - symBid) / symPt;
      double symCap    = (atrM5[0] / symPt) * InpSpreadATRFactor;
      if(symSpread <= symCap)
      {
         cand.spreadOK = true;
         bullScore += 8;
         bearScore += 8; // spread affects both sides equally
      }
   }

   //── Dimension 7: Session active +5 ───────────────────────────
   // Simplified: London (07:00-17:00) or NY (13:00-22:00) overlaps
   bool sessOK = IsInSession(InpSessionStartHour, InpSessionEndHour);
   if(sessOK)
   {
      cand.sessionOK = true;
      bullScore += 5;
      bearScore += 5;
   }

   //── Determine final score and bias ────────────────────────────
   cand.bullScore  = bullScore;
   cand.bearScore  = bearScore;

   if(bullScore >= bearScore && bullScore >= InpPortfolioMinCandScore)
   {
      cand.bias       = BIAS_BULL;
      cand.finalScore = bullScore;
      cand.tradable   = true;
   }
   else if(bearScore > bullScore && bearScore >= InpPortfolioMinCandScore)
   {
      cand.bias       = BIAS_BEAR;
      cand.finalScore = bearScore;
      cand.tradable   = true;
   }
   else
   {
      cand.bias       = BIAS_NONE;
      cand.finalScore = MathMax(bullScore, bearScore);
      cand.tradable   = false;
      cand.reason     = "score_below_min(" + IntegerToString(InpPortfolioMinCandScore) + ")";
   }

   // Check if this symbol already has exposure (for risk throttle)
   if(InpPortfolioSkipWithExposure)
   {
      for(int r = 0; r < 100; r++)
      {
         if(gRec[r].active && gRec[r].symbol == sym)
         {
            cand.hasExposure = true;
            cand.reason += " has_exposure";
            break;
         }
      }
   }

   cand.valid = true;
}

//════════════════════════════════════════════════════════════════════
//  §12.3 — ScanPortfolioWatchlist()
//  Full multi-symbol scan with ranking and arbitration.
//  Called from OnTimer at InpPortfolioScanIntervalSec intervals.
//  Stores results in gPortCand[] for TryNewEntry arbitration.
//════════════════════════════════════════════════════════════════════

void ScanPortfolioWatchlist()
{
   if(!InpUsePortfolioWatchlist) return;
   if(g_WatchCount == 0) return;

   PushDiag("📊 E12: Portfolio scan — " + IntegerToString(g_WatchCount) + " symbols");

   // ── Score all watchlist symbols ────────────────────────────────
   PortfolioCandidate candidates[32];
   int validCount = 0;

   for(int i = 0; i < g_WatchCount; i++)
   {
      QuickScoreSymbol(i, candidates[i]);
      if(candidates[i].valid) validCount++;
   }

   // ── Sort by finalScore descending (simple bubble sort — N≤32) ──
   for(int i = 0; i < g_WatchCount - 1; i++)
   {
      for(int j = 0; j < g_WatchCount - i - 1; j++)
      {
         if(candidates[j].finalScore < candidates[j + 1].finalScore)
         {
            PortfolioCandidate tmp = candidates[j];
            candidates[j]         = candidates[j + 1];
            candidates[j + 1]     = tmp;
         }
      }
   }

   // ── Assign ranks and copy to global state ─────────────────────
   for(int i = 0; i < g_WatchCount; i++)
   {
      candidates[i].rank = i + 1; // 1-based rank (1 = highest score)
      gPortCand[i]       = candidates[i];
   }
   // Clear remaining slots
   for(int i = g_WatchCount; i < 32; i++)
   {
      gPortCand[i].valid = false;
      gPortCand[i].rank  = 99;
   }

   gLastPortScan = TimeCurrent();

   // Log top-3 results
   for(int i = 0; i < MathMin(3, g_WatchCount); i++)
   {
      if(!gPortCand[i].valid) continue;
      string biasStr = (gPortCand[i].bias == BIAS_BULL) ? "BULL"
                      : (gPortCand[i].bias == BIAS_BEAR) ? "BEAR" : "NONE";
      PushDiag("  #" + IntegerToString(i + 1) + " " + gPortCand[i].symbol
               + " " + biasStr + " score=" + IntegerToString(gPortCand[i].finalScore)
               + (gPortCand[i].hasExposure ? " [EXPOSURE]" : ""));
   }
}

//--- Returns the current chart symbol's rank from gPortCand[] (-1 if not found)
int GetChartSymbolRank()
{
   for(int i = 0; i < 32; i++)
   {
      if(!gPortCand[i].valid) continue;
      if(gPortCand[i].symbol == gSymbol) return gPortCand[i].rank;
   }
   return -1; // not in watchlist
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE v5.0a — SPIKE DETECTION ENGINE
//  64-slot circular rolling tick-price buffer.
//  Detects price velocity spikes by comparing tick range within a
//  configurable time window against an ATR-based threshold.
//  UpdateTickBuffer: called as FIRST operation every tick.
//  EvaluateSpikeDetection: called after buffer update.
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §v5.0a.1 — UpdateTickBuffer()
//  Maintains a 64-slot circular buffer of bid prices and timestamps.
//  MUST be called before any other engine on every tick.
//════════════════════════════════════════════════════════════════════

void UpdateTickBuffer()
{
   if(!InpUseSpikeDetection) return;

   double bid = SymbolInfoDouble(gSymbol, SYMBOL_BID);

   // Write to current slot
   gSpike.tickPriceBuf[gSpike.tickBufIdx] = bid;
   gSpike.tickTimeBuf[gSpike.tickBufIdx]  = TimeCurrent();

   // Advance circular index (wraps at 64)
   gSpike.tickBufIdx = (gSpike.tickBufIdx + 1) % 64;

   // Increment fill count (caps at 64)
   if(gSpike.tickBufCount < 64) gSpike.tickBufCount++;
}

//════════════════════════════════════════════════════════════════════
//  §v5.0a.2 — EvaluateSpikeDetection()
//  Scans the tick buffer for the configured time window.
//  Spike = price range in window > ATR × InpSpikeATRFactor.
//  Auto-clears when range returns below threshold.
//════════════════════════════════════════════════════════════════════

void EvaluateSpikeDetection()
{
   if(!InpUseSpikeDetection)
   {
      gSpike.spikeDetected = false;
      return;
   }

   if(gSpike.tickBufCount < 2)
   {
      gSpike.spikeDetected = false;
      return;
   }

   datetime windowStart = TimeCurrent() - (datetime)InpSpikeWindowSec;

   // Scan buffer for ticks within the rolling time window
   double maxP = -1e15, minP = 1e15;
   int    validTicks = 0;

   for(int i = 0; i < gSpike.tickBufCount; i++)
   {
      int bi = (gSpike.tickBufIdx - 1 - i + 64) % 64; // read backwards from most recent
      if(gSpike.tickTimeBuf[bi] < windowStart) break;  // outside window — stop scanning

      double p = gSpike.tickPriceBuf[bi];
      if(p > maxP) maxP = p;
      if(p < minP) minP = p;
      validTicks++;
   }

   if(validTicks < 2)
   {
      gSpike.spikeDetected = false;
      return;
   }

   double rangeInWindow = maxP - minP;
   double atrThreshold  = GetATR(IDX_M5, 1) * InpSpikeATRFactor;

   bool prevSpike = gSpike.spikeDetected;

   if(rangeInWindow > atrThreshold && atrThreshold > 0.0)
   {
      gSpike.spikeDetected   = true;
      gSpike.lastSpikeRange  = rangeInWindow;
      gSpike.reason          = "SPIKE: range=" + DoubleToString(rangeInWindow / gPoint, 1)
                              + "pt > ATR×" + DoubleToString(InpSpikeATRFactor, 2)
                              + "=" + DoubleToString(atrThreshold / gPoint, 1) + "pt";

      if(!prevSpike) // log only on new detection
      {
         gSpike.spikeStartTime = TimeCurrent();
         PushDiag("🚨 E_SPIKE: " + gSpike.reason);
         JournalWrite("SPIKE_DETECTED",
                      DoubleToString(rangeInWindow / gPoint, 1) + "pt",
                      "thresh=" + DoubleToString(atrThreshold / gPoint, 1) + "pt",
                      IntegerToString(validTicks) + "ticks");

         // Telegram spike alert
         if(InpUseTelegram)
         {
            string tgMsg = "🚨 SPIKE DETECTED\n"
                          + "📌 " + gSymbol + "\n"
                          + "📊 Range: " + DoubleToString(rangeInWindow / gPoint, 1) + "pt"
                          + " > threshold " + DoubleToString(atrThreshold / gPoint, 1) + "pt\n"
                          + "⏰ " + TimeToString(TimeCurrent(), TIME_SECONDS);
            TGEnqueue(MSG_SPIKE, tgMsg, true);
         }
      }

      // Handle protective scalp close
      if(InpCloseScalpOnSpike)
         HandleHostileScalpExposure();
   }
   else
   {
      // Auto-clear: range returned below threshold
      if(prevSpike)
      {
         gSpike.spikeDetected  = false;
         gSpike.spikeClearTime = TimeCurrent();
         PushDiag("✅ E_SPIKE: Cleared — range=" + DoubleToString(rangeInWindow / gPoint, 1) + "pt");
         JournalWrite("SPIKE_CLEARED",
                      DoubleToString(rangeInWindow / gPoint, 1) + "pt",
                      "was=" + DoubleToString(gSpike.lastSpikeRange / gPoint, 1) + "pt");
      }
      gSpike.spikeDetected = false;
   }
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE v5.0b — NEWS FILTER ENGINE
//  Two-mode news detection:
//    1. Scheduled: explicit windows from InpNewsWindowCSV CSV string
//    2. Implied:   automatic detection via spread/ATR anomaly
//  ParseNewsWindowCSV: called once from OnInit.
//  CheckNewsWindowActive + CheckImpliedNewsFilter: called every tick.
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §v5.0b.1 — ParseNewsWindowCSV()
//  Parses InpNewsWindowCSV into gNews struct arrays.
//  Format: "WEEKDAY,HH:MM,DURATION_MIN;..."
//  Example: "3,14:30,15;5,08:30,10" (Wed 14:30 for 15min + Fri 08:30 for 10min)
//════════════════════════════════════════════════════════════════════

void ParseNewsWindowCSV()
{
   gNews.parsedCount       = 0;
   gNews.active            = false;
   gNews.impliedBySpread   = false;

   if(!InpUseNewsFilter) return;
   if(StringLen(InpNewsWindowCSV) == 0) return;

   string windowTokens[];
   int nWindows = StringSplit(InpNewsWindowCSV, ';', windowTokens);

   for(int i = 0; i < nWindows && gNews.parsedCount < 10; i++)
   {
      string tok = windowTokens[i];
      StringTrimLeft(tok);
      StringTrimRight(tok);
      if(StringLen(tok) == 0) continue;

      // Split each window token on ','
      string fields[];
      int nFields = StringSplit(tok, ',', fields);
      if(nFields < 3)
      {
         Print("⚠️ News CSV parse error: '", tok, "' — expected WEEKDAY,HH:MM,DURATION");
         continue;
      }

      // Parse weekday (0=Sunday, 1=Monday, ..., 6=Saturday)
      int weekday = (int)StringToInteger(fields[0]);
      if(weekday < 0 || weekday > 6)
      {
         Print("⚠️ News CSV parse error: weekday '", fields[0], "' out of range 0-6");
         continue;
      }

      // Parse HH:MM time
      string timeParts[];
      if(StringSplit(fields[1], ':', timeParts) < 2)
      {
         Print("⚠️ News CSV parse error: time '", fields[1], "' not HH:MM format");
         continue;
      }
      int hour = (int)StringToInteger(timeParts[0]);
      int min  = (int)StringToInteger(timeParts[1]);
      if(hour < 0 || hour > 23 || min < 0 || min > 59)
      {
         Print("⚠️ News CSV parse error: time '", fields[1], "' hour/min out of range");
         continue;
      }

      // Parse duration in minutes
      int durationMin = (int)StringToInteger(fields[2]);
      if(durationMin < 1 || durationMin > 480)
      {
         Print("⚠️ News CSV parse error: duration '", fields[2], "' out of range 1-480");
         continue;
      }

      // Store in gNews arrays
      int idx = gNews.parsedCount;
      gNews.weekday[idx]     = weekday;
      gNews.startHour[idx]   = hour;
      gNews.startMin[idx]    = min;
      gNews.durationMin[idx] = durationMin;
      gNews.parsedCount++;

      Print("✅ News window[", idx, "]: weekday=", weekday, " ", hour, ":", (min<10?"0":""), min,
            " duration=", durationMin, "min (±pre/post buffer)");
   }

   Print("✅ E_NEWS: Parsed ", gNews.parsedCount, " news windows from CSV");
}

//════════════════════════════════════════════════════════════════════
//  §v5.0b.2 — CheckNewsWindowActive()
//  Runtime evaluation against parsed news schedules.
//  Pre-buffer: block InpNewsPreBufferMin before window start.
//  Post-buffer: block InpNewsPostBufferMin after window end.
//  Called every tick.
//════════════════════════════════════════════════════════════════════

void CheckNewsWindowActive()
{
   if(!InpUseNewsFilter || gNews.parsedCount == 0) return;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   int nowSecs    = now.hour * 3600 + now.min * 60 + now.sec;
   int nowWeekday = now.day_of_week;

   bool anyActive = false;
   datetime windowEnd = 0;

   for(int i = 0; i < gNews.parsedCount; i++)
   {
      if(gNews.weekday[i] != nowWeekday) continue; // wrong day

      // Window timing in seconds since midnight
      int winStartSecs     = gNews.startHour[i] * 3600 + gNews.startMin[i] * 60;
      int blockStartSecs   = winStartSecs - InpNewsPreBufferMin * 60;  // pre-buffer
      int blockEndSecs     = winStartSecs + gNews.durationMin[i] * 60
                           + InpNewsPostBufferMin * 60;                 // post-buffer

      // Clamp to valid range
      if(blockStartSecs < 0) blockStartSecs = 0;
      if(blockEndSecs > 86400) blockEndSecs = 86400;

      if(nowSecs >= blockStartSecs && nowSecs <= blockEndSecs)
      {
         anyActive = true;
         windowEnd = TimeCurrent() + (datetime)(blockEndSecs - nowSecs);

         // Log and alert only on new activation (edge detection)
         if(!gNews.active || !gNews.impliedBySpread)
         {
            string winLabel = "Wed"; // simplified — use weekday names
            switch(gNews.weekday[i])
            {
               case 0: winLabel="Sun"; break;
               case 1: winLabel="Mon"; break;
               case 2: winLabel="Tue"; break;
               case 3: winLabel="Wed"; break;
               case 4: winLabel="Thu"; break;
               case 5: winLabel="Fri"; break;
               case 6: winLabel="Sat"; break;
            }
            string tLabel = winLabel + " "
                           + (gNews.startHour[i] < 10 ? "0" : "") + IntegerToString(gNews.startHour[i])
                           + ":" + (gNews.startMin[i] < 10 ? "0" : "") + IntegerToString(gNews.startMin[i])
                           + " +" + IntegerToString(gNews.durationMin[i]) + "min";

            gNews.windowLabel = tLabel;
            gNews.windowEnd   = windowEnd;

            JournalWrite("NEWS_WINDOW_START", tLabel, "entries paused");
            PushDiag("📰 E_NEWS: WINDOW ACTIVE — " + tLabel);

            if(InpNewsTelegramAlert)
            {
               string tgMsg = "══════════════════════════\n"
                             "📰 NEWS WINDOW ACTIVE\n"
                             "──────────────────────────\n"
                             + "📌 " + gSymbol + "\n"
                             + "📅 " + tLabel + "\n"
                             + "🚫 New entries paused\n"
                             + "🕐 Window closes: "
                             + TimeToString(windowEnd, TIME_MINUTES) + "\n"
                             + "══════════════════════════";
               TGEnqueue(MSG_NEWS, tgMsg, false);
            }
         }
         break;
      }
   }

   // State transition: window ended
   if(!anyActive && gNews.active && !gNews.impliedBySpread)
   {
      JournalWrite("NEWS_WINDOW_END", gNews.windowLabel, "entries re-enabled");
      PushDiag("📰 E_NEWS: Window cleared — " + gNews.windowLabel);

      if(InpNewsTelegramAlert)
      {
         string tgMsg = "📰 NEWS WINDOW CLEARED\n"
                       + "📌 " + gSymbol + " | Entries re-enabled\n"
                       + TimeToString(TimeCurrent(), TIME_SECONDS);
         TGEnqueue(MSG_NEWS, tgMsg, false);
      }

      gNews.active      = false;
      gNews.windowLabel = "";
      gNews.windowEnd   = 0;
   }
   else if(anyActive)
   {
      gNews.active    = true;
      gNews.windowEnd = windowEnd;
   }
}

//════════════════════════════════════════════════════════════════════
//  §v5.0b.3 — CheckImpliedNewsFilter()
//  Automatic news detection via spread/ATR anomaly.
//  Triggers when: spread > ATR × InpNewsImpliedSpreadMult
//  This catches unscheduled high-impact events that weren't in the CSV.
//════════════════════════════════════════════════════════════════════

void CheckImpliedNewsFilter()
{
   if(!InpUseNewsFilter || !InpUseImpliedNewsFilter) return;

   double atrVal    = GetATR(IDX_M5, 1);
   double spreadPt  = GetSpreadPoints();
   double implThresh = (atrVal / gPoint) * InpNewsImpliedSpreadMult;

   bool impliedNow = (atrVal > 0.0 && spreadPt > implThresh);
   bool prevImplied = gNews.impliedBySpread;

   if(impliedNow)
   {
      gNews.impliedBySpread = true;
      gNews.active          = true;

      if(!prevImplied)
      {
         PushDiag("📰 E_NEWS: IMPLIED window — spread " + DoubleToString(spreadPt, 1)
                  + "pt > " + DoubleToString(implThresh, 1) + "pt (ATR×" + DoubleToString(InpNewsImpliedSpreadMult, 2) + ")");
         JournalWrite("NEWS_IMPLIED_START",
                      "spread=" + DoubleToString(spreadPt, 1),
                      "thresh=" + DoubleToString(implThresh, 1));

         if(InpNewsTelegramAlert)
         {
            string tgMsg = "📰 NEWS (Implied) ACTIVE\n"
                          + "📌 " + gSymbol + "\n"
                          + "📡 Spread spike: " + DoubleToString(spreadPt, 1)
                          + "pt > " + DoubleToString(implThresh, 1) + "pt\n"
                          + TimeToString(TimeCurrent(), TIME_SECONDS);
            TGEnqueue(MSG_NEWS, tgMsg, false);
         }
      }
   }
   else
   {
      if(prevImplied)
      {
         gNews.impliedBySpread = false;
         // Only clear gNews.active if no scheduled window is also active
         if(gNews.windowEnd == 0 || TimeCurrent() > gNews.windowEnd)
         {
            gNews.active = false;
            PushDiag("📰 E_NEWS: IMPLIED window cleared");
            JournalWrite("NEWS_IMPLIED_CLEAR",
                         "spread=" + DoubleToString(spreadPt, 1),
                         "thresh=" + DoubleToString(implThresh, 1));
         }
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE v5.0c — VOLUME MOMENTUM ENGINE
//  Relative tick-volume comparison: current bar vs N-bar average.
//  Broker-agnostic: uses ratio (not absolute) to handle tick volume
//  variance across brokers and symbols.
//  Bull confirmed: curVol > avgVol × InpVolMomBullFactor AND close>open
//  Bear confirmed: curVol > avgVol × InpVolMomBearFactor AND close<open
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §v5.0c.1 — InitVolumeHandles()
//  Creates M5 and M1 tick volume indicator handles.
//  Graceful degradation: if either fails → InpUseVolumeMomentum
//  is treated as disabled for that session (no INIT_FAILED).
//  Called once from OnInit.
//════════════════════════════════════════════════════════════════════

void InitVolumeHandles()
{
   if(!InpUseVolumeMomentum) return;

   g_hVolM5 = iVolumes(gSymbol, PERIOD_M5, VOLUME_TICK);
   g_hVolM1 = iVolumes(gSymbol, PERIOD_M1, VOLUME_TICK);

   if(g_hVolM5 == INVALID_HANDLE || g_hVolM1 == INVALID_HANDLE)
   {
      Print("⚠️ E_VOLMOM: Tick volume handles failed — volume momentum disabled for this session");
      Print("   M5 handle: ", g_hVolM5, " | M1 handle: ", g_hVolM1);
      // Graceful degradation: feature continues but contributes 0 pts to score
      g_hVolM5 = INVALID_HANDLE;
      g_hVolM1 = INVALID_HANDLE;
      gVolMom.label = "UNAVAILABLE";
   }
   else
   {
      Print("✅ E_VOLMOM: Volume handles created — M5=", g_hVolM5, " M1=", g_hVolM1);
      gVolMom.label = "READY";
   }
}

//--- Release volume handles (called from OnDeinit)
void ReleaseVolumeHandles()
{
   if(g_hVolM5 != INVALID_HANDLE) { IndicatorRelease(g_hVolM5); g_hVolM5 = INVALID_HANDLE; }
   if(g_hVolM1 != INVALID_HANDLE) { IndicatorRelease(g_hVolM1); g_hVolM1 = INVALID_HANDLE; }
}

//════════════════════════════════════════════════════════════════════
//  §v5.0c.2 — RefreshVolumeMomentum()
//  Per-bar evaluation (not per-tick — volume on incomplete bar
//  is meaningless for confirmation).
//  Called from ValidateMasterSignal once per new M5 bar.
//════════════════════════════════════════════════════════════════════

void RefreshVolumeMomentum()
{
   if(!InpUseVolumeMomentum) return;

   // Reset both flags before evaluation (not sticky across bars)
   gVolMom.bullConfirmed = false;
   gVolMom.bearConfirmed = false;
   gVolMom.ratio         = 0.0;
   gVolMom.label         = "WEAK";

   // Handle unavailable (graceful degradation)
   if(g_hVolM5 == INVALID_HANDLE) { gVolMom.label = "UNAVAILABLE"; return; }

   // Load volume array: InpVolMomLookback+1 bars (current + average window)
   // Shift 0 = current (incomplete) bar, Shift 1 = last closed bar
   double volBuf[];  // CopyBuffer always returns double — cast to long below
   int  lookback = InpVolMomLookback + 1; // extra bar for current incomplete
   if(CopyBuffer(g_hVolM5, 0, 0, lookback + 1, volBuf) < lookback)
   {
      gVolMom.label = "BUFFER_FAIL";
      return;
   }

   // Current bar = volBuf[1] (shift 1 = last closed bar in CopyBuffer arrays)
   // Average = mean of volBuf[1] through volBuf[InpVolMomLookback] (closed bars only)
   long currentVol = (long)volBuf[1]; // last fully closed bar (cast from indicator double buffer)
   gVolMom.currentVol = currentVol;

   double sum = 0.0;
   int    count = 0;
   for(int i = 1; i <= InpVolMomLookback && i < lookback + 1; i++)
   {
      sum += (double)volBuf[i];
      count++;
   }

   if(count == 0) { gVolMom.label = "NO_HISTORY"; return; }
   gVolMom.avgVol = sum / count;

   // Ratio: how much larger is current bar vs average?
   gVolMom.ratio = SafeDiv((double)currentVol, gVolMom.avgVol);

   // Direction gate: use M5 bar direction from TFState cache
   double close0 = gTF[IDX_M5].close0; // last closed bar close
   double open0  = 0.0;
   // Get last closed bar open price
   double openBuf[1];
   if(CopyOpen(gSymbol, PERIOD_M5, 1, 1, openBuf) >= 1) open0 = openBuf[0];

   bool closedBullBar = (close0 > open0 && open0 > 0.0);
   bool closedBearBar = (close0 < open0 && open0 > 0.0);

   // Bull volume confirmation: vol > avg × factor AND bullish close
   gVolMom.bullConfirmed = (currentVol > gVolMom.avgVol * InpVolMomBullFactor) && closedBullBar;

   // Bear volume confirmation: vol > avg × factor AND bearish close
   gVolMom.bearConfirmed = (currentVol > gVolMom.avgVol * InpVolMomBearFactor) && closedBearBar;

   // Build label for dashboard and Telegram
   if(gVolMom.bullConfirmed)
      gVolMom.label = "BULL_CONFIRMED (×" + DoubleToString(gVolMom.ratio, 2) + ")";
   else if(gVolMom.bearConfirmed)
      gVolMom.label = "BEAR_CONFIRMED (×" + DoubleToString(gVolMom.ratio, 2) + ")";
   else
      gVolMom.label = "WEAK (×" + DoubleToString(gVolMom.ratio, 2) + ")";

   // Debug log (once per bar, only if verbose mode)
   if(InpUseVerboseTGDiag)
      PushDiag("📊 VolMom: " + gVolMom.label
               + " vol=" + IntegerToString(currentVol)
               + " avg=" + DoubleToString(gVolMom.avgVol, 1));
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE SUP — SYMBOL PROFILE ENGINE
//  Auto-detects asset class from symbol name and configures
//  per-class runtime parameters: session hours, spread factor,
//  SL ATR multiplier, pending offset, max slippage.
//  LoadSymbolProfile: called once from OnInit, never again.
//  Populates gProfile (SymbolProfileRuntime).
//════════════════════════════════════════════════════════════════════

//--- Asset class detector: returns string label from symbol name
string GetSymbolAssetClass(string sym)
{
   StringToUpper(sym); // normalize to uppercase for comparison

   // METALS: Gold, Silver, Platinum, Palladium
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0) return "METAL_GOLD";
   if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0) return "METAL_SILVER";
   if(StringFind(sym, "XPT") >= 0 || StringFind(sym, "PLAT") >= 0)   return "METAL_PGM";

   // CRYPTO: Bitcoin, Ethereum, major altcoins
   if(StringFind(sym, "BTC") >= 0)  return "CRYPTO_BTC";
   if(StringFind(sym, "ETH") >= 0)  return "CRYPTO_ETH";
   if(StringFind(sym, "LTC") >= 0 || StringFind(sym, "XRP") >= 0 || StringFind(sym, "BNB") >= 0)
      return "CRYPTO_ALT";

   // INDICES: US and European equity indices
   if(StringFind(sym, "US30")  >= 0 || StringFind(sym, "DJI")  >= 0) return "INDEX_DJI";
   if(StringFind(sym, "NAS")   >= 0 || StringFind(sym, "NDX")  >= 0) return "INDEX_NAS";
   if(StringFind(sym, "SPX")   >= 0 || StringFind(sym, "SP500")>= 0) return "INDEX_SPX";
   if(StringFind(sym, "DAX")   >= 0 || StringFind(sym, "GER")  >= 0) return "INDEX_DAX";
   if(StringFind(sym, "FTSE")  >= 0 || StringFind(sym, "UK100")>= 0) return "INDEX_FTSE";

   // OIL/ENERGY
   if(StringFind(sym, "OIL") >= 0 || StringFind(sym, "WTI") >= 0 || StringFind(sym, "BRENT") >= 0)
      return "ENERGY_OIL";

   // FOREX JPY pairs (special pip handling — 3/5 digit pricing)
   if(StringFind(sym, "JPY") >= 0) return "FOREX_JPY";

   // Default: standard FOREX major/minor/exotic
   return "FOREX";
}

//--- Main profile loader — called once from OnInit
void LoadSymbolProfile()
{
   string cls = GetSymbolAssetClass(gSymbol);
   g_AssetClass = cls;
   gProfile.assetClass = cls;

   // ── Configure per-class defaults ────────────────────────────────
   // These are runtime defaults that CAN be overridden by user inputs.
   // The profile is used to SET sensible defaults, not to enforce limits.

   if(cls == "METAL_GOLD")      // XAUUSD — highest volume, widest spread
   {
      gProfile.spreadFactor         = 2.00; // gold spreads are wider (2× base)
      gProfile.pendingOffsetPoints  = 20.0; // wider offset needed
      gProfile.maxSlippage          = 30.0; // higher slippage tolerance
      gProfile.scalpATRMin          = 1.00; // gold ATR larger — wider SL
      gProfile.scalpATRMax          = 1.20;
      gProfile.moderateSLATR        = 1.80; // deeper swing anchor
      gProfile.sessionStartHour     = 7;    // London open
      gProfile.sessionEndHour       = 22;   // NY close
      gProfile.slDistMultiplier     = 1.30; // gold volatility requires 30% wider SL
   }
   else if(cls == "METAL_SILVER" || cls == "METAL_PGM")
   {
      gProfile.spreadFactor         = 2.50;
      gProfile.pendingOffsetPoints  = 25.0;
      gProfile.maxSlippage          = 35.0;
      gProfile.scalpATRMin          = 1.00;
      gProfile.scalpATRMax          = 1.25;
      gProfile.moderateSLATR        = 1.80;
      gProfile.sessionStartHour     = 7;
      gProfile.sessionEndHour       = 22;
      gProfile.slDistMultiplier     = 1.40; // silver/PGM highly volatile — 40% wider
   }
   else if(cls == "CRYPTO_BTC" || cls == "CRYPTO_ETH")
   {
      gProfile.spreadFactor         = 4.00; // crypto spreads very wide
      gProfile.pendingOffsetPoints  = 50.0;
      gProfile.maxSlippage          = 100.0; // crypto slippage severe
      gProfile.scalpATRMin          = 1.00;
      gProfile.scalpATRMax          = 1.50;
      gProfile.moderateSLATR        = 2.00;
      gProfile.sessionStartHour     = 0;  // crypto trades 24/7
      gProfile.sessionEndHour       = 23;
      gProfile.slDistMultiplier     = 1.50; // BTC/ETH extreme moves — 50% wider SL
   }
   else if(cls == "CRYPTO_ALT")
   {
      gProfile.spreadFactor         = 5.00;
      gProfile.pendingOffsetPoints  = 75.0;
      gProfile.maxSlippage          = 150.0;
      gProfile.scalpATRMin          = 1.20;
      gProfile.scalpATRMax          = 1.60;
      gProfile.moderateSLATR        = 2.00;
      gProfile.sessionStartHour     = 0;
      gProfile.sessionEndHour       = 23;
      gProfile.slDistMultiplier     = 1.80; // altcoins most volatile — 80% wider SL
   }
   else if(StringFind(cls, "INDEX") >= 0) // all equity indices
   {
      gProfile.spreadFactor         = 1.50;
      gProfile.pendingOffsetPoints  = 30.0;
      gProfile.maxSlippage          = 50.0;
      gProfile.scalpATRMin          = 0.90;
      gProfile.scalpATRMax          = 1.10;
      gProfile.moderateSLATR        = 1.60;
      gProfile.sessionStartHour     = 8;  // EU/US session (index-specific)
      gProfile.sessionEndHour       = 22;
      gProfile.slDistMultiplier     = 1.20; // equity indices moderate volatility
   }
   else if(cls == "ENERGY_OIL")
   {
      gProfile.spreadFactor         = 2.00;
      gProfile.pendingOffsetPoints  = 20.0;
      gProfile.maxSlippage          = 40.0;
      gProfile.scalpATRMin          = 1.00;
      gProfile.scalpATRMax          = 1.20;
      gProfile.moderateSLATR        = 1.70;
      gProfile.sessionStartHour     = 7;
      gProfile.sessionEndHour       = 22;
      gProfile.slDistMultiplier     = 1.30; // oil sharp moves — 30% wider SL
   }
   else if(cls == "FOREX_JPY")  // JPY pairs: 3-digit spread in points
   {
      gProfile.spreadFactor         = 1.20;
      gProfile.pendingOffsetPoints  = 10.0;
      gProfile.maxSlippage          = 20.0;
      gProfile.scalpATRMin          = 0.80;
      gProfile.scalpATRMax          = 1.00;
      gProfile.moderateSLATR        = 1.50;
      gProfile.sessionStartHour     = 0;  // Tokyo open included for JPY
      gProfile.sessionEndHour       = 22;
      gProfile.slDistMultiplier     = 1.00; // JPY pairs standard baseline
   }
   else // FOREX (majors, minors, exotics)
   {
      gProfile.spreadFactor         = 1.00; // baseline
      gProfile.pendingOffsetPoints  = 15.0;
      gProfile.maxSlippage          = 25.0;
      gProfile.scalpATRMin          = 0.80;
      gProfile.scalpATRMax          = 1.00;
      gProfile.moderateSLATR        = 1.50;
      gProfile.sessionStartHour     = 7;   // London open
      gProfile.sessionEndHour       = 22;  // NY close
      gProfile.slDistMultiplier     = 1.00; // standard baseline multiplier
   }

   Print("✅ Symbol Profile: ", gSymbol, " | Class=", cls,
         " | SessHours=", gProfile.sessionStartHour, "-", gProfile.sessionEndHour,
         " | ModSLATR=", DoubleToString(gProfile.moderateSLATR, 2),
         " | SlipMax=", DoubleToString(gProfile.maxSlippage, 0));
}

//════════════════════════════════════════════════════════════════════
//  §SUP — Symbol Preset Risk Multiplier (OVERRIDES P4 VERSION)
//  This version uses the actual P1 input structure:
//  InpUseSymbolPresetMap, InpPresetScalpList, InpPresetModerateList,
//  InpPresetScalpRiskMult, InpPresetModerateRiskMult
//  Supersedes P4's SymbolPresetRiskMultiplier (which assumed InpPresetCSV)
//════════════════════════════════════════════════════════════════════

double SymbolPresetRiskMultiplierV2()
{
   if(!InpUseSymbolPresetMap) return 1.00;

   // Check scalp preset list
   string scalpSyms[];
   int ns = StringSplit(InpPresetScalpList, ',', scalpSyms);
   for(int i = 0; i < ns; i++)
   {
      string s = scalpSyms[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(s == gSymbol) return InpPresetScalpRiskMult; // e.g. 1.10
   }

   // Check moderate preset list
   string modSyms[];
   int nm = StringSplit(InpPresetModerateList, ',', modSyms);
   for(int i = 0; i < nm; i++)
   {
      string s = modSyms[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(s == gSymbol) return InpPresetModerateRiskMult; // e.g. 0.90
   }

   return 1.00; // not in any preset list
}

//════════════════════════════════════════════════════════════════════
//  §SUP — Loss Cooldown corrected to use P1 inputs
//  Supersedes P4's hardcoded 90/180/300 values with configurable inputs
//════════════════════════════════════════════════════════════════════

double LossCooldownSeconds_v2()
{
   if(!InpUseLossStreakCooldown) return 0.0;
   if(gConsecLosses <= 0) return 0.0;
   if(gConsecLosses == 1) return (double)InpLossStreakCooldown1Sec;  // 90s default
   if(gConsecLosses == 2) return (double)InpLossStreakCooldown2Sec;  // 180s default
   return (double)InpLossStreakCooldown3Sec;                          // 300s default for 3+
}

//--- Updated LossCooldownOK using configurable thresholds
bool LossCooldownOK_v2()
{
   double needed  = LossCooldownSeconds_v2();
   if(needed <= 0.0) return true;
   double elapsed = (double)(TimeCurrent() - gLastEntryTime);
   return (elapsed >= needed);
}

//════════════════════════════════════════════════════════════════════
//  ENGINE v5.1 — BUY/SELL PRESSURE ENGINE  (SESSION-BASED)
//
//  Faithful implementation of TradingView "Day Buy Sell Volume label"
//  by @badshah_e_alam — SESSION-ACCURATE, multi-TF version:
//
//  ALGORITHM (per bar):
//    Buy  Force = ((close - low)  / range) × volume
//    Sell Force = ((high  - close) / range) × volume
//    Wick boost: upper wick > 25% range → extra sell pressure
//                lower wick > 25% range → extra buy  pressure
//    Body boost: strong-body bars (>50% of range) get extra directional weight
//    Institutional: bars >2.5× previous range → extra directional force
//    Current bar: real-time partial bar included at 50% weight
//
//  SESSION SCOPE:
//    Uses iBarShift(D1) to find bars since day/session open.
//    Each TF (M1, M5, M15, H1, H4) accumulates from session start.
//    Result is stored per-TF in gBSP struct for dashboard display.
//
//  COMPOSITE WEIGHTING:
//    Final: M1=10% + M5=25% + M15=15% + H1=35% + H4=15%
//════════════════════════════════════════════════════════════════════

// BSP Engine v6.3g — Rolling Candle-Wise with Exponential Decay
// Replaces session-accumulation (v5.1) which diluted HFT signals by averaging
// all-day bars. New engine uses a finite rolling window (N bars back) with
// exponential decay weighting: most-recent bars dominate, older bars fade.
// Mode-specific composites ensure HFT uses ultra-short TFs while MODERATE
// correctly weights H1/H4 context.
bool g_BSPHandlesReady = false;

// ── Init / Release ────────────────────────────────────────────────────
void InitBSPHandles()
{
   double testC[];
   int got = CopyClose(gSymbol, PERIOD_M1, 1, 5, testC);
   if(got >= 1)
   {
      g_BSPHandlesReady = true;
      JournalInfo("BSP", "Buy/Sell Pressure Engine v6.3g (rolling candle-wise, exp-decay) — ready");
   }
   else
   {
      // Non-fatal: engine will retry on each RefreshBuySellPressure call.
      // Do NOT block here — blocking was the root cause of BSP being disabled
      // for the entire session when M1 data wasn't yet available at OnInit.
      g_BSPHandlesReady = false;
      JournalWarn("BSP", "BSP Engine v6.3g — M1 data not ready at init, will retry on first tick");
   }
}

void ReleaseBSPHandles()
{
   g_BSPHandlesReady = false;
}

//--------------------------------------------------------------------
// CalcCandleWindowBSP()
//
//   Rolling N-bar candle-wise Buy/Sell Pressure with exponential decay.
//   Most-recent completed bar (index=1) has weight=1.0.
//   Each older bar has weight multiplied by decayFactor (0.85–0.95).
//
//   Core BSP formula per bar (faithful @badshah_e_alam implementation):
//     buyForce  = ((close - low)  / range) × volume × weight
//     sellForce = ((high  - close) / range) × volume × weight
//     + wick enhancement (hidden liquidity)
//     + strong-body directional boost
//     + institutional block detection (2.5× range expansion)
//
//   Velocity: pressure trend = recent-half buyPct minus older-half buyPct.
//   Positive velocity → buy pressure accelerating.
//   Negative velocity → buy pressure decelerating (sell momentum building).
//
//   Parameters:
//     tf          — timeframe to analyze
//     lookback    — number of completed bars to include (capped at 200)
//     decayFactor — exponential weight per bar older (0.85=fast decay, 0.95=slow)
//     outSellPct  — sell pressure output [0–100]
//     outVelocity — pressure trend [-50 to +50, positive = bull accelerating]
//
//   Returns: buyPct [0–100]
//--------------------------------------------------------------------
double CalcCandleWindowBSP(ENUM_TIMEFRAMES tf,
                            int             lookback,
                            double          decayFactor,
                            double         &outSellPct,
                            double         &outVelocity)
{
   outSellPct  = 50.0;
   outVelocity = 0.0;

   int bars = MathMin(MathMax(lookback, 2), 200);

   double o[], h[], l[], c[];
   long   tv[];

   int got = CopyOpen(gSymbol, tf, 1, bars, o);
   if(got < 1) return 50.0;
   bars = got;  // actual bars available (may be less than requested during warmup)

   if(CopyHigh      (gSymbol, tf, 1, bars, h)  < bars) return 50.0;
   if(CopyLow       (gSymbol, tf, 1, bars, l)  < bars) return 50.0;
   if(CopyClose     (gSymbol, tf, 1, bars, c)  < bars) return 50.0;
   if(CopyTickVolume(gSymbol, tf, 1, bars, tv) < bars)
   { ArrayResize(tv, bars); ArrayInitialize(tv, 1LL); }

   // Pass 1: compute weighted forces across all bars
   // Index 0 = most-recent completed bar (weight = 1.0)
   // Index N = oldest bar (weight = decayFactor^N)
   double totalBuy  = 0.0, totalSell  = 0.0;
   double recentBuy = 0.0, recentSell = 0.0;  // first half (newer)
   double olderBuy  = 0.0, olderSell  = 0.0;  // second half (older)
   int    halfPoint = bars / 2;

   double weight = 1.0;
   for(int i = 0; i < bars; i++)
   {
      double range = h[i] - l[i];
      if(range < DBL_EPSILON) { weight *= decayFactor; continue; }

      double vol    = (double)MathMax(1LL, tv[i]);
      double bForce = ((c[i] - l[i]) / range) * vol * weight;
      double sForce = ((h[i] - c[i]) / range) * vol * weight;

      // Wick enhancement: large wicks reveal absorbed liquidity
      double upper  = h[i] - MathMax(o[i], c[i]);
      double lower  = MathMin(o[i], c[i]) - l[i];
      double wickW  = 0.30 * vol * weight;
      if(upper > range * 0.25) sForce += wickW * (upper / range);
      if(lower > range * 0.25) bForce += wickW * (lower / range);

      // Strong-body directional boost: decisive bars get extra weight
      double bodyPct = MathAbs(c[i] - o[i]) / range;
      if(bodyPct > 0.50)
      {
         double boost = bodyPct * vol * 0.15 * weight;
         if(c[i] >= o[i]) bForce += boost;
         else              sForce += boost;
      }

      // Institutional block: sudden 2.5× range expansion → smart money move
      if(i > 0)
      {
         double prevRange = h[i-1] - l[i-1];
         if(prevRange > DBL_EPSILON && range > prevRange * 2.5)
         {
            double instW = ((range - prevRange * 2.5) / range) * vol * 0.50 * weight;
            if(c[i] >= o[i]) bForce += instW;
            else              sForce += instW;
         }
      }

      totalBuy  += bForce;
      totalSell += sForce;

      // Split for velocity computation
      if(i < halfPoint) { recentBuy += bForce; recentSell += sForce; }
      else              { olderBuy  += bForce; olderSell  += sForce; }

      weight *= decayFactor;
   }

   // Include current partial bar at 50% weight (real-time update)
   double cO[1], cH[1], cL[1], cC[1];
   long   cTV[1];
   if(CopyOpen(gSymbol,tf,0,1,cO)>0 && CopyHigh(gSymbol,tf,0,1,cH)>0 &&
      CopyLow (gSymbol,tf,0,1,cL)>0 && CopyClose(gSymbol,tf,0,1,cC)>0)
   {
      double cRange = cH[0] - cL[0];
      if(cRange > DBL_EPSILON)
      {
         if(CopyTickVolume(gSymbol,tf,0,1,cTV) < 1) cTV[0] = 1LL;
         double cVol  = (double)MathMax(1LL, cTV[0]);
         double cBuy  = ((cC[0]-cL[0])/cRange) * cVol * 0.50;
         double cSell = ((cH[0]-cC[0])/cRange) * cVol * 0.50;
         totalBuy  += cBuy;
         totalSell += cSell;
         recentBuy += cBuy;   // current bar counts as "recent"
         recentSell+= cSell;
      }
   }

   double total = totalBuy + totalSell;
   if(total < DBL_EPSILON) { outSellPct = 50.0; outVelocity = 0.0; return 50.0; }

   double buyPct   = (totalBuy / total) * 100.0;
   outSellPct      = 100.0 - buyPct;

   // Velocity: compare recent-half pressure vs older-half pressure
   // Positive = buy pressure accelerating; Negative = sell accelerating
   double recentTotal = recentBuy + recentSell;
   double olderTotal  = olderBuy  + olderSell;
   double recentBuyPct = (recentTotal > DBL_EPSILON) ? (recentBuy  / recentTotal) * 100.0 : 50.0;
   double olderBuyPct  = (olderTotal  > DBL_EPSILON) ? (olderBuy   / olderTotal)  * 100.0 : 50.0;
   outVelocity = recentBuyPct - olderBuyPct;  // range roughly [-50, +50]

   return buyPct;
}

//--------------------------------------------------------------------
// RefreshBuySellPressure()  — Engine v6.3g
//
//   Mode-specific rolling-window composites replace session-wide averaging:
//
//   HFT:      M1[20, d=0.88]×40% + M3[15, d=0.90]×25% + M5[12, d=0.92]×20%
//             + tick_flow[64-tick rolling]×15%
//             → hftRollingBuyPct / hftBuyPct (legacy alias)
//
//   SCALP:    M5[30, d=0.90]×45% + M15[20, d=0.92]×35% + M1[15, d=0.85]×20%
//             → scalpRollingBuyPct / buyPct
//
//   MODERATE: H1[20, d=0.92]×45% + H4[10, d=0.95]×35% + M15[20, d=0.90]×20%
//             → modRollingBuyPct / buyPct
//
//   Per-TF session values still computed for dashboard display.
//--------------------------------------------------------------------
void RefreshBuySellPressure()
{
   // Self-heal: retry initialization if it failed at OnInit (happens when
   // the terminal hasn't loaded historical data yet on first attach).
   if(!g_BSPHandlesReady)
   {
      double testC[];
      if(CopyClose(gSymbol, PERIOD_M1, 1, 3, testC) >= 1)
      {
         g_BSPHandlesReady = true;
         JournalInfo("BSP","BSP Engine v6.3g — data now available, engine activated");
      }
      else
         return;  // still not ready — skip silently, retry next tick
   }

   // ── Per-TF session pressures for dashboard display ─────────────────
   // Compact single-pass session calc (no lambda — MQL5 doesn't support closures).
   // Used only for dashboard charts; actual signal engine uses rolling windows below.
   {
      ENUM_TIMEFRAMES dashTFs[8] = {PERIOD_M1,PERIOD_M3,PERIOD_M5,PERIOD_M6,
                                    PERIOD_M10,PERIOD_M15,PERIOD_H1,PERIOD_H4};
      for(int _t=0; _t<8; _t++)
      {
         ENUM_TIMEFRAMES tf = dashTFs[_t];
         datetime dayStart = iTime(gSymbol, PERIOD_D1, 0);
         double bOut=50.0, sOut=50.0;
         if(dayStart != 0)
         {
            int nBars = iBarShift(gSymbol, tf, dayStart, false);
            if(nBars < 1)   nBars = 1;
            if(nBars > 200) nBars = 200;
            double o2[],h2[],l2[],c2[]; long tv2[];
            int got2 = CopyOpen(gSymbol, tf, 1, nBars, o2);
            if(got2 >= 1)
            {
               nBars = got2;
               bool ok = CopyHigh (gSymbol,tf,1,nBars,h2)>=nBars &&
                         CopyLow  (gSymbol,tf,1,nBars,l2)>=nBars &&
                         CopyClose(gSymbol,tf,1,nBars,c2)>=nBars;
               if(ok)
               {
                  if(CopyTickVolume(gSymbol,tf,1,nBars,tv2)<nBars)
                  { ArrayResize(tv2,nBars); ArrayInitialize(tv2,1LL); }
                  double tB=0,tS=0;
                  for(int i=0;i<nBars;i++)
                  {
                     double rng=h2[i]-l2[i]; if(rng<DBL_EPSILON) continue;
                     double v=(double)MathMax(1LL,tv2[i]);
                     tB+=((c2[i]-l2[i])/rng)*v; tS+=((h2[i]-c2[i])/rng)*v;
                  }
                  double tot=tB+tS;
                  bOut = (tot>DBL_EPSILON) ? (tB/tot)*100.0 : 50.0;
                  sOut = 100.0 - bOut;
               }
            }
         }
         switch(_t)
         {
            case 0: gBSP.buyPctM1 =bOut; gBSP.sellPctM1 =sOut; break;
            case 1: gBSP.buyPctM3 =bOut; gBSP.sellPctM3 =sOut; break;
            case 2: gBSP.buyPctM5 =bOut; gBSP.sellPctM5 =sOut; break;
            case 3: gBSP.buyPctM6 =bOut; gBSP.sellPctM6 =sOut; break;
            case 4: gBSP.buyPctM10=bOut; gBSP.sellPctM10=sOut; break;
            case 5: gBSP.buyPctM15=bOut; gBSP.sellPctM15=sOut; break;
            case 6: gBSP.buyPctH1 =bOut; gBSP.sellPctH1 =sOut; break;
            case 7: gBSP.buyPctH4 =bOut; gBSP.sellPctH4 =sOut; break;
         }
      }
   }

   // ── Current partial bar (real-time) ────────────────────────────────
   {
      double cO[1],cH[1],cL[1],cC[1]; long cTV[1];
      if(CopyOpen(gSymbol,PERIOD_M5,0,1,cO)>0 && CopyHigh(gSymbol,PERIOD_M5,0,1,cH)>0 &&
         CopyLow (gSymbol,PERIOD_M5,0,1,cL)>0 && CopyClose(gSymbol,PERIOD_M5,0,1,cC)>0)
      {
         double cR=cH[0]-cL[0];
         if(cR>DBL_EPSILON)
         {
            if(CopyTickVolume(gSymbol,PERIOD_M5,0,1,cTV)<1) cTV[0]=1LL;
            double cV=(double)MathMax(1LL,cTV[0]);
            double cB=((cC[0]-cL[0])/cR)*cV;
            double cS=((cH[0]-cC[0])/cR)*cV;
            double cT=cB+cS;
            gBSP.curBarBuyPct  = (cT>DBL_EPSILON) ? (cB/cT)*100.0 : 50.0;
            gBSP.curBarSellPct = 100.0 - gBSP.curBarBuyPct;
         }
      }
   }

   // ── Tick-level order flow ───────────────────────────────────────────
   gBSP.tickFlowBull = gHFTOrderFlowBull;
   gBSP.tickFlowBear = 1.0 - gHFTOrderFlowBull;
   double tickBuyPct = gBSP.tickFlowBull * 100.0;

   // ══════════════════════════════════════════════════════════════════
   // MODE-SPECIFIC ROLLING-WINDOW COMPOSITES
   // ══════════════════════════════════════════════════════════════════

   if(gBotMode == BOT_MODE_HFT)
   {
      // HFT composite: ultra-short rolling windows with fast decay
      // M1[20 bars, d=0.88] × 40%  — highest resolution, fastest signal
      // M3[15 bars, d=0.90] × 25%  — smoothed micro-structure
      // M5[12 bars, d=0.92] × 20%  — intermediate structure
      // tick flow [64-tick]  × 15%  — real-time order flow edge
      double sM1, sM3, sM5;
      double vM1, vM3, vM5;
      double bM1 = CalcCandleWindowBSP(PERIOD_M1, 20, 0.88, sM1, vM1);
      double bM3 = CalcCandleWindowBSP(PERIOD_M3, 15, 0.90, sM3, vM3);
      double bM5 = CalcCandleWindowBSP(PERIOD_M5, 12, 0.92, sM5, vM5);

      // Store per-TF rolling values so dashboard & logs can prove they differ from session BSP
      gBSP.hftRollingM1BuyPct = bM1;
      gBSP.hftRollingM3BuyPct = bM3;
      gBSP.hftRollingM5BuyPct = bM5;

      gBSP.hftRollingBuyPct  = bM1*0.40 + bM3*0.25 + bM5*0.20 + tickBuyPct*0.15;
      gBSP.hftRollingSellPct = 100.0 - gBSP.hftRollingBuyPct;

      // Velocity: weighted average of per-TF velocities (M1 most important)
      gBSP.hftVelocity = vM1*0.55 + vM3*0.30 + vM5*0.15;

      // Rolling BSP log — proves per-TF divergence vs session-cumulative dashboard values
      // Session BSP (gBSP.buyPctM1/M3/M5) converges at session open; rolling does NOT.
      static datetime _lastBSPLog = 0;
      if(TimeLocal() - _lastBSPLog >= 30)
      {
         _lastBSPLog = TimeLocal();
         JournalInfo("BSP_HFT", StringFormat(
            "ROLLING  M1=%.1f%% M3=%.1f%% M5=%.1f%% tick=%.1f%% → composite=%.1f%%  vel=%.1f",
            bM1, bM3, bM5, tickBuyPct, gBSP.hftRollingBuyPct, gBSP.hftVelocity));
         JournalInfo("BSP_HFT", StringFormat(
            "SESSION  M1=%.1f%% M3=%.1f%% M5=%.1f%%  (all TFs same = normal at session open)",
            gBSP.buyPctM1, gBSP.buyPctM3, gBSP.buyPctM5));
      }

      // Legacy aliases — ComputeHFTEntrySignal uses hftBuyPct/hftSellPct
      gBSP.hftBuyPct  = gBSP.hftRollingBuyPct;
      gBSP.hftSellPct = gBSP.hftRollingSellPct;

      // For standard composite fields (used by label/dominant flags)
      gBSP.buyPct  = gBSP.hftRollingBuyPct;
      gBSP.sellPct = gBSP.hftRollingSellPct;
   }
   else if(gBotMode == BOT_MODE_SCALPING)
   {
      // SCALP composite: balanced short-medium TFs
      // M5[30 bars, d=0.90]  × 45%  — core scalp structure
      // M15[20 bars, d=0.92] × 35%  — session context
      // M1[15 bars, d=0.85]  × 20%  — micro entry timing
      double sM5, sM15, sM1;
      double vM5, vM15, vM1;
      double bM5  = CalcCandleWindowBSP(PERIOD_M5,  30, 0.90, sM5,  vM5);
      double bM15 = CalcCandleWindowBSP(PERIOD_M15, 20, 0.92, sM15, vM15);
      double bM1  = CalcCandleWindowBSP(PERIOD_M1,  15, 0.85, sM1,  vM1);

      gBSP.scalpRollingBuyPct  = bM5*0.45 + bM15*0.35 + bM1*0.20;
      gBSP.scalpRollingSellPct = 100.0 - gBSP.scalpRollingBuyPct;

      gBSP.buyPct  = gBSP.scalpRollingBuyPct;
      gBSP.sellPct = gBSP.scalpRollingSellPct;

      // hftBuyPct kept for legacy (ComputeHFTEntrySignal fallback)
      gBSP.hftBuyPct  = gBSP.scalpRollingBuyPct;
      gBSP.hftSellPct = gBSP.scalpRollingSellPct;
   }
   else // BOT_MODE_MODERATE
   {
      // MODERATE composite: longer-term TFs for swing/position context
      // H1[20 bars, d=0.92]  × 45%  — trend anchor
      // H4[10 bars, d=0.95]  × 35%  — macro direction
      // M15[20 bars, d=0.90] × 20%  — intraday entry timing
      double sH1, sH4, sM15;
      double vH1, vH4, vM15;
      double bH1  = CalcCandleWindowBSP(PERIOD_H1,  20, 0.92, sH1,  vH1);
      double bH4  = CalcCandleWindowBSP(PERIOD_H4,  10, 0.95, sH4,  vH4);
      double bM15 = CalcCandleWindowBSP(PERIOD_M15, 20, 0.90, sM15, vM15);

      gBSP.modRollingBuyPct  = bH1*0.45 + bH4*0.35 + bM15*0.20;
      gBSP.modRollingSellPct = 100.0 - gBSP.modRollingBuyPct;

      gBSP.buyPct  = gBSP.modRollingBuyPct;
      gBSP.sellPct = gBSP.modRollingSellPct;

      gBSP.hftBuyPct  = gBSP.modRollingBuyPct;
      gBSP.hftSellPct = gBSP.modRollingSellPct;
   }

   gBSP.totalBuyForce  = gBSP.buyPct;
   gBSP.totalSellForce = gBSP.sellPct;

   gBSP.bullDominant = (gBSP.buyPct  >= 58.0);
   gBSP.bearDominant = (gBSP.sellPct >= 58.0);

   if(gBSP.bullDominant)      gBSP.label = "BUY DOMINANT";
   else if(gBSP.bearDominant) gBSP.label = "SELL DOMINANT";
   else                        gBSP.label = "NEUTRAL";
}

//--------------------------------------------------------------------
// ScoreBuySellPressure()  — Mode-aware BSP entry score contribution
//
//   HFT:      ±20 pts  (uses hftRollingBuyPct — highest responsiveness)
//             Velocity bonus: +3 pts when pressure accelerating in direction
//   SCALP:    ±12 pts  (uses scalpRollingBuyPct)
//   MODERATE: ±8  pts  (uses modRollingBuyPct — conservative)
//
//   Scoring bands (% of bias-direction pressure):
//     ≥75%: full score    (strong, clean flow)
//     ≥68%: 80% of max    (clear directional imbalance)
//     ≥62%: 60% of max    (moderate edge)
//     ≥56%: 30% of max    (slight lean)
//     ≥50%: 10% of max    (marginal)
//     <50%: penalty        (opposing flow — caution)
//--------------------------------------------------------------------
int ScoreBuySellPressure(ENUM_BIAS emaBias)
{
   if(!g_BSPHandlesReady) return 0;

   int    maxPts;
   double buyPct, sellPct;

   if(gBotMode == BOT_MODE_HFT)
   {
      maxPts  = 20;
      buyPct  = gBSP.hftRollingBuyPct;
      sellPct = gBSP.hftRollingSellPct;
   }
   else if(gBotMode == BOT_MODE_SCALPING)
   {
      maxPts  = 12;
      buyPct  = gBSP.scalpRollingBuyPct;
      sellPct = gBSP.scalpRollingSellPct;
   }
   else // MODERATE
   {
      maxPts  = 8;
      buyPct  = gBSP.modRollingBuyPct;
      sellPct = gBSP.modRollingSellPct;
   }

   int sc = 0;
   if(emaBias == BIAS_BULL)
   {
      if     (buyPct >= 75.0) sc =  maxPts;
      else if(buyPct >= 68.0) sc =  (int)MathRound(maxPts * 0.80);
      else if(buyPct >= 62.0) sc =  (int)MathRound(maxPts * 0.60);
      else if(buyPct >= 56.0) sc =  (int)MathRound(maxPts * 0.30);
      else if(buyPct >= 50.0) sc =  (int)MathRound(maxPts * 0.10);
      else                    sc = -(int)MathRound(maxPts * 0.40);  // opposing flow penalty
   }
   else if(emaBias == BIAS_BEAR)
   {
      if     (sellPct >= 75.0) sc = -maxPts;
      else if(sellPct >= 68.0) sc = -(int)MathRound(maxPts * 0.80);
      else if(sellPct >= 62.0) sc = -(int)MathRound(maxPts * 0.60);
      else if(sellPct >= 56.0) sc = -(int)MathRound(maxPts * 0.30);
      else if(sellPct >= 50.0) sc = -(int)MathRound(maxPts * 0.10);
      else                     sc =  (int)MathRound(maxPts * 0.40);
   }
   else // BIAS_NONE
   {
      if     (buyPct  >= 65.0) sc =  (int)MathRound(maxPts * 0.50);
      else if(sellPct >= 65.0) sc = -(int)MathRound(maxPts * 0.50);
   }

   // HFT velocity bonus: pressure accelerating in signal direction adds +3
   if(gBotMode == BOT_MODE_HFT)
   {
      if(emaBias == BIAS_BULL && gBSP.hftVelocity >  5.0) sc += 3;
      if(emaBias == BIAS_BEAR && gBSP.hftVelocity < -5.0) sc -= 3;
      sc = MathMax(-maxPts, MathMin(maxPts, sc));
   }

   return sc;
}

//════════════════════════════════════════════════════════════════════
//  END OF PART 5
//  Next: Part 6 — Telegram Engine, Dashboard (CCanvas + WebView),
//               Update/Patch Engine, JSON Writer
//════════════════════════════════════════════════════════════════════


#endif // SKP_P5_BSP_MQH
