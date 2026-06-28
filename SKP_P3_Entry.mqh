#ifndef SKP_P3_ENTRY_MQH
#define SKP_P3_ENTRY_MQH

//+------------------------------------------------------------------+
//| SK_TRADE_PREMIUM_BOT_P3.mq5                                      |
//|                                                                  |
//|  ENGINE 4 — LOT RESOLUTION & SL/TP CALCULATION STACK            |
//|  ENGINE 5 — POSITION MANAGEMENT SUB-FUNCTIONS                   |
//|  ENGINE 6 — SAFETY VAULT SUB-FUNCTIONS & RETRY QUEUE            |
//|                                                                  |
//|  ASSEMBLY ORDER:  P1 → P2 → P3 → P4 → P5 → P6 → P7            |
//|  DO NOT COMPILE STANDALONE — requires P1, P2 definitions        |
//|                                                                  |
//|  This file contains every function called from P7 OnTick step 8 |
//|  and all sub-functions invoked by P4 Engines 7-9.               |
//+------------------------------------------------------------------+

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 4 — LOT RESOLUTION STACK & ENTRY LEVEL CALCULATOR
//  6-layer resolution: Symbol Preset → Regime → Loss Smooth →
//  Risk % → Min/Max clamp → NormalizeLot
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 4.1  SL/TP ENTRY LEVEL CALCULATOR
//       Computes SL, TP1, TP2, TP3 from ATR-based risk distance.
//       outRiskDist = SL distance in price units.
//--------------------------------------------------------------------
struct EntryLevels
{
   double sl;           // stop loss price
   double tp1;          // virtual TP1 (30% partial close)
   double tp2;          // virtual TP2 (40% partial close)
   double tp3;          // broker hard TP (30% runner target)
   double riskDistance; // |entry - sl|
   double atrUsed;      // ATR at time of calc
};

EntryLevels CalculateEntryLevels(ENUM_ORDER_TYPE orderType, double entryPrice)
{
   EntryLevels lvl;
   lvl.sl = lvl.tp1 = lvl.tp2 = lvl.tp3 = lvl.riskDistance = lvl.atrUsed = 0;

   double atrH1 = GetATR(IDX_H1, 1);
   double atrM5 = GetATR(IDX_M5, 1);
   // v6.3c FIX: HFT SL is based on M1 ATR (not H1). Do not require H1 ATR for HFT —
   //            if H1 indicator is still warming up, CalculateEntryLevels would return
   //            zero levels → EntryQualityGatePass silently fails → no trades placed.
   if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
   {
      if(atrM5 < DBL_EPSILON) return lvl;   // HFT only needs M5 (M1 has internal fallback)
   }
   else
   {
      if(atrH1 < DBL_EPSILON || atrM5 < DBL_EPSILON) return lvl;
   }

   lvl.atrUsed = (atrH1 > DBL_EPSILON) ? atrH1 : atrM5;

   // SL distance: based on mode and asset class
   // HFT:    ultra-tight SL (0.3 × M1 ATR)
   // Scalp:  tighter SL (0.8 × M5 ATR)
   // Moderate: wider SL (1.5 × H1 ATR)
   double slDist;
   if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
   {
      double atrM1 = GetATR(IDX_M1, 1);
      if(atrM1 < DBL_EPSILON) atrM1 = atrM5 * 0.4; // fallback if M1 ATR not ready
      slDist = atrM1 * InpHFTSLATRMult;
      lvl.atrUsed = atrM1;
      // Spread floor: HFT SL must be at least 3× current spread so it can survive bid-ask noise
      double curSpread = SymbolInfoDouble(gSymbol, SYMBOL_ASK) - SymbolInfoDouble(gSymbol, SYMBOL_BID);
      if(curSpread > DBL_EPSILON) slDist = MathMax(slDist, curSpread * 3.0);
   }
   else if(gBotMode == BOT_MODE_SCALPING)
      slDist = atrM5 * InpScalpSLATRMin;
   else
      slDist = atrH1 * 1.50;

   // Apply asset class profile adjustments
   // GUARD: slDistMultiplier defaults to 0 if LoadSymbolProfile missed a branch — treat as 1.0
   slDist *= (gProfile.slDistMultiplier > DBL_EPSILON ? gProfile.slDistMultiplier : 1.0);

   // Enforce minimum: must clear broker minimum stop level
   double minStopDist = (double)SymbolInfoInteger(gSymbol, SYMBOL_TRADE_STOPS_LEVEL) * gPoint;
   // When broker stops level is 0 (common for crypto CFDs), use 10% of M5 ATR as floor
   if(minStopDist < gPoint * 5) minStopDist = atrM5 * 0.10;
   if(slDist < minStopDist * 1.20)
      slDist = minStopDist * 1.20;  // 20% buffer above minimum

   lvl.riskDistance = slDist;

   // TP distances (R multiples of SL distance)
   // HFT:      TP1=0.4R, TP2=0.8R, TP3=1.2R  (quick profits, rarely reaches TP3)
   // Scalp:    TP1=0.8R, TP2=1.5R, TP3=2.5R
   // Moderate: TP1=1.0R, TP2=2.0R, TP3=3.5R
   double tp1R, tp2R, tp3R;
   if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
   { tp1R=InpHFTTP1R; tp2R=InpHFTTP2R; tp3R=1.20; }
   else if(gBotMode == BOT_MODE_SCALPING)
   { tp1R=InpScalpTP1R; tp2R=1.50; tp3R=2.50; }
   else
   { tp1R=1.00; tp2R=2.00; tp3R=3.50; }

   if(orderType == ORDER_TYPE_BUY)
   {
      lvl.sl  = entryPrice - slDist;
      lvl.tp1 = entryPrice + slDist * tp1R;
      lvl.tp2 = entryPrice + slDist * tp2R;
      lvl.tp3 = entryPrice + slDist * tp3R;
   }
   else
   {
      lvl.sl  = entryPrice + slDist;
      lvl.tp1 = entryPrice - slDist * tp1R;
      lvl.tp2 = entryPrice - slDist * tp2R;
      lvl.tp3 = entryPrice - slDist * tp3R;
   }

   // Normalise to tick size
   lvl.sl  = NormalizeDouble(lvl.sl,  gDigits);
   lvl.tp1 = NormalizeDouble(lvl.tp1, gDigits);
   lvl.tp2 = NormalizeDouble(lvl.tp2, gDigits);
   lvl.tp3 = NormalizeDouble(lvl.tp3, gDigits);

   return lvl;
}

//--------------------------------------------------------------------
// 4.2  6-LAYER LOT RESOLUTION STACK
//       Layer 1: Manual override (if InpLotControlMode == 1)
//       Layer 2: Symbol preset risk multiplier
//       Layer 3: Regime lot multiplier
//       Layer 4: Loss smoothing (consecutive loss reduction)
//       Layer 5: Risk % → lot size (account balance × risk ÷ risk$)
//       Layer 6: Min/Max clamp + NormalizeLotSafe
//--------------------------------------------------------------------
double ResolveLotSize(double riskDistance, ENUM_ORDER_TYPE orderType)
{
   // Layer 1: Manual lot override
   if(InpLotControlMode == 1)
   {
      double manualLot = ActiveManualLot();   // P5 accessor
      return NormalizeLotSafe(manualLot, gSymbol);
   }

   // Layer 2: Symbol preset risk multiplier (P5 V2 function)
   double presetMult = SymbolPresetRiskMultiplierV2(gSymbol);

   // Layer 3: Regime lot multiplier (P5 Engine 11)
   double regimeMult = RegimeLotMultiplier();

   // Layer 4: Loss smoothing factor
   double smoothMult = 1.0;
   if(InpApplyLossSmoothToAuto && gConsecLosses > 0)
   {
      // Each consecutive loss reduces lot by 10%, min 50% of original
      smoothMult = MathMax(0.50, 1.0 - (double)gConsecLosses * 0.10);
   }

   // Layer 5: Risk % → lot size
   // v6.3g FIX: Use gRt_RiskPct (written by ApplyRiskProfile/ApplySubMode) so that
   //            risk profile changes (AGGRESSIVE/MED-RISK/LOW-RISK) actually affect
   //            position sizing.  Previously ActiveRiskPct() returned the raw input
   //            with no profile scaling, making the risk profile dropdown inert.
   //            Falls back to ActiveRiskPct() only if gRt_RiskPct was never initialised.
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskPct  = (gRt_RiskPct > 0.0) ? gRt_RiskPct : ActiveRiskPct();
   double riskUSD  = balance * (riskPct / 100.0);

   // riskUSD = lot × (riskDistance / gPoint) × gTickValue
   // → lot = riskUSD / ((riskDistance / gPoint) × gTickValue)
   double riskPerLot = SafeDiv(riskDistance, gPoint) * gTickValue;
   double rawLot     = SafeDiv(riskUSD, riskPerLot);

   // Apply all multipliers (now includes gRt_LotMultiplier from ApplyRiskProfile)
   rawLot *= presetMult * regimeMult * smoothMult * MathMax(0.10, gRt_LotMultiplier);

   // Size-from-edge: scale by the AI win-probability edge (1.0× when disabled).
   // gLastAIProb was refreshed by Gate-15 in CanAttemptEntry earlier this tick.
   rawLot *= AI_EdgeLotMult();

   // Layer 6: Clamp to mode-specific min/max then normalise
   double minLot = ActiveMinLot();
   double maxLot = ActiveMaxLot();
   rawLot = MathMax(minLot, MathMin(maxLot, rawLot));

   return NormalizeLotSafe(rawLot, gSymbol);
}

//--------------------------------------------------------------------
// 4.3  PENDING ORDER OFFSET CALCULATOR (scalp limit orders)
//       Returns the offset (in price units) from current price to
//       place the limit order.
//--------------------------------------------------------------------
double GetScalpPendingOffset()
{
   // InpPendingOffsetPoints is declared in P1 as double
   return InpPendingOffsetPoints * gPoint;
}

//--------------------------------------------------------------------
// 4.4  ENTRY QUALITY GATE (pre-trade validation)
//       Called from TryNewEntry before lot calculation.
//       Returns true if all pre-entry numeric checks pass.
//--------------------------------------------------------------------
bool EntryQualityGatePass(ENUM_ORDER_TYPE orderType, const EntryLevels &lvl)
{
   // Verify SL is meaningful
   if(lvl.riskDistance < gPoint * 2)
   {
      JournalWarn("EntryGate","SL distance too small: "+DoubleToString(lvl.riskDistance/gPoint,1)+" pts");
      return false;
   }

   // Verify TP3 is in correct direction
   double price = (orderType==ORDER_TYPE_BUY) ?
                  SymbolInfoDouble(gSymbol,SYMBOL_ASK) :
                  SymbolInfoDouble(gSymbol,SYMBOL_BID);

   if(orderType==ORDER_TYPE_BUY  && lvl.tp3 <= price) { JournalWarn("EntryGate","TP3 below current price for BUY");  return false; }
   if(orderType==ORDER_TYPE_SELL && lvl.tp3 >= price) { JournalWarn("EntryGate","TP3 above current price for SELL"); return false; }

   // Verify SL is in correct direction
   if(orderType==ORDER_TYPE_BUY  && lvl.sl >= price) { JournalWarn("EntryGate","SL above price for BUY");  return false; }
   if(orderType==ORDER_TYPE_SELL && lvl.sl <= price) { JournalWarn("EntryGate","SL below price for SELL"); return false; }

   // Broker stop level check
   double minSL = (double)SymbolInfoInteger(gSymbol,SYMBOL_TRADE_STOPS_LEVEL) * gPoint;
   if(MathAbs(price - lvl.sl) < minSL)
   { JournalWarn("EntryGate","SL violates broker minimum stop level"); return false; }

   return true;
}

//--------------------------------------------------------------------
// 4.5  TryNewEntry — 20-STEP ENTRY GATE PIPELINE
//       Master entry decision function.  All 20 steps must pass
//       before a single order is submitted.
//       Populates gPlan[] and calls PlaceTrade (P4) on success.
//--------------------------------------------------------------------
void TryNewEntry(ENUM_BIAS bias, int score)
{
   // ── GATE 1: Bias non-neutral ──────────────────────────────────
   if(bias == BIAS_NONE) return;

   // ── GATE 2: Safety lock (already checked in CanAttemptEntry,
   //            but double-check here as defence-in-depth) ────────
   if(CheckSafetyLockAdvanced()) return;

   // ── GATE 3: Manual pause ─────────────────────────────────────
   if(gManualPause) return;

   // ── GATE 4: Score threshold — use runtime shadow globals set by ApplySubMode/ApplyRiskProfile
   // v6.3c FIX: was using raw Inp* inputs which ignored ApplySubMode() overrides (e.g.
   // ORDERFLOW_SNIPER set gRt_HFTMinScore=48 but InpHFTMinScore=52 still blocked score 49-51)
   int minS = (gBotMode==BOT_MODE_HFT)      ? gRt_HFTMinScore     :
              (gBotMode==BOT_MODE_SCALPING)  ? gRt_ScalpMinScore   : gRt_ModMinScore;
   // v6.3g: HFT loss-streak escalation — raise the bar dynamically during a losing run.
   // Each consecutive loss adds +3 pts to the entry threshold (max +15).
   // This forces HFT to only trade its highest-conviction signals while capital is eroding.
   if(gBotMode == BOT_MODE_HFT && gConsecLosses > 0)
   {
      int lossPenalty = MathMin(gConsecLosses * 3, 15);
      minS += lossPenalty;
   }
   if(score < minS)
   { JournalInfo("TryEntry","Score %d < min %d [gRt+streak] — no entry",score,minS);
     PushEAEvent("Gate4-Score",StringFormat("BLOCKED — score %d < min %d (losses=%d)",score,minS,gConsecLosses)); return; }

   // ── GATE 5: Engine 1-3 hard filters ──────────────────────────
   if(!EngineFiltersPass(bias)) return;

   // ── GATE 6: Session gate ──────────────────────────────────────
   if(!SessionPassesEntryGate())
   { JournalInfo("TryEntry","Session gate failed"); return; }

   // ── GATE 7: News window ───────────────────────────────────────
   // CheckNewsWindowActive() is void (P5) — reads gNews.active set by RefreshBrokerState
   if(gNews.active) return;

   // ── GATE 8: Implied news ──────────────────────────────────────
   // CheckImpliedNewsFilter() is void — state already updated by P5 RefreshBrokerState
   if(gImpliedNewsActive) return;

   // ── GATE 9: Blackout window ───────────────────────────────────
   if(IsInBlackoutWindow()) return;

   // ── GATE 10: Regime — scalp/HFT suppression ──────────────────
   // Scalp: suppress in HOSTILE + QUIET (targets unreachable in low vol)
   if(gBotMode==BOT_MODE_SCALPING && RegimeSuppressScalper()) return;
   // HFT: only suppress on spike or extreme spread — NOT on QUIET/HOSTILE-gap
   // HFT trades M1 momentum (1-2 min hold); low volatility is still tradeable
   if((gBotMode==BOT_MODE_HFT || gBotMode==BOT_MODE_HFT_PURE) && HFTRegimeSuppressed()) return;

   // ── GATE 11: Loss streak cooldown ────────────────────────────
   if(!LossCooldownOK_v2()) return;

   // ── GATE 12: Maximum concurrent open positions ────────────────
   int openCount = 0;
   for(int i=0;i<100;i++) if(gRec[i].active) openCount++;
   if(openCount >= InpMaxOpenTrades)
   { JournalInfo("TryEntry","Max open trades %d reached",InpMaxOpenTrades); return; }

   // ── GATE 13: Portfolio ranking gate ──────────────────────────
   if(InpUsePortfolioWatchlist)
   {
      int myRank = GetChartSymbolRank();
      if(myRank <= 0 || myRank > InpPortfolioMaxTradableRanks)
      { JournalInfo("TryEntry","Portfolio rank %d outside tradable range",myRank); return; }
      // Score gap gate: this symbol's score vs #1 ranked
      if(myRank > 1 && gPortCand[0].finalScore - score > InpPortfolioMinScoreGap)
      { JournalInfo("TryEntry","Score gap too large vs top-ranked symbol"); return; }
   }

   // ── GATE 14: No existing position in same direction ───────────
   for(int i=0;i<100;i++)
   {
      if(!gRec[i].active) continue;
      if(gRec[i].symbol != gSymbol) continue;
      bool sameDir = (bias==BIAS_BULL && gRec[i].posType==ORDER_TYPE_BUY) ||
                     (bias==BIAS_BEAR && gRec[i].posType==ORDER_TYPE_SELL);
      if(sameDir)
      { JournalInfo("TryEntry","Already have "+(gRec[i].posType==ORDER_TYPE_BUY?"BUY":"SELL")+" on "+gSymbol+" — no duplicate"); return; }
   }

   // ── GATE 15: Spread gate (real-time, mode-sensitive) ─────────
   {
      double spread = (SymbolInfoDouble(gSymbol,SYMBOL_ASK)-SymbolInfoDouble(gSymbol,SYMBOL_BID))/gPoint;
      double maxSpr;
      if(gBotMode == BOT_MODE_HFT_PURE)
      {
         // HFT PURE: fixed absolute cap (set by user via InpHFTMaxSpreadPts).
         // ATR-ratio method was producing 13-36pt limits on XAUUSD Asian session
         // vs actual 39-47pt spreads — blocked every entry 01:00-08:00.
         maxSpr = InpHFTMaxSpreadPts;
      }
      else
      {
         double atrPts = GetATR(IDX_M5,1)/gPoint;
         double sxFact = (gBotMode==BOT_MODE_HFT) ? InpHFTMaxSpreadFactor : InpSpreadATRFactor;
         maxSpr = (atrPts>0) ? atrPts*sxFact*RegimeSpreadMultiplier() : 999;
      }
      if(spread > maxSpr)
      { JournalInfo("TryEntry",StringFormat("Spread %.1f > max %.1f pts — skipping",spread,maxSpr)); return; }
   }

   // ── GATES 16a-16e: HFT-specific extra guards ─────────────────
   // v6.3c: ALL gates now push to PushEAEvent so WriteSignalCSV captures accurate
   //        block reasons (previously gates were silent — CSV always showed stale "SubMode").
   if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
   {
      // 16a: Minimum tick velocity (active market required)
      // v6.3c FIX: skip gate during warmup (gHFTTickRate==0 means ring not filled yet)
      //            Previously gHFTTickRate=0 always failed the 4.0/s check → total block.
      if(InpHFTTickVelocityMin > 0 && gHFTTickRate > 0 &&
         gHFTTickRate < InpHFTTickVelocityMin)
      {
         string g16a = StringFormat("BLOCKED — HFT tick rate %.1f/s < min %.1f/s",
                                     gHFTTickRate, InpHFTTickVelocityMin);
         JournalInfo("TryEntry", g16a);
         PushEAEvent("Gate16a-TickRate", g16a);
         return;
      }
      // 16b: Order flow imbalance (directional bias in recent ticks)
      // HFT_PURE SKIP: direction already confirmed at 60% by gPressEng in ComputeHFTPureSignal.
      //   gHFTOrderFlowBull is a 64-tick cross-bar rolling buffer — a different metric that
      //   can read 50% even when current-bar pressure is 65%+, causing contradictory blocks.
      // v6.3c FIX: skip gate if gHFTOrderFlowBull not yet initialized (0.0 = ring empty).
      if(gBotMode != BOT_MODE_HFT_PURE)
      {
         bool bullBias = (bias == BIAS_BULL);
         double flowBias = bullBias ? gHFTOrderFlowBull : (1.0 - gHFTOrderFlowBull);
         bool flowInitialized = (gHFTOrderFlowBull > DBL_EPSILON &&
                                 gHFTOrderFlowBull < 1.0 - DBL_EPSILON);
         if(flowInitialized && flowBias < InpHFTOrderFlowBiasMin)
         {
            string g16b = StringFormat("BLOCKED — HFT order flow %.0f%% < min %.0f%%",
                                        flowBias*100, InpHFTOrderFlowBiasMin*100);
            JournalInfo("TryEntry", g16b);
            PushEAEvent("Gate16b-OrderFlow", g16b);
            return;
         }
      }
      // 16c: Hourly rate limiter
      if(gHFTTradesThisHour >= InpHFTMaxTradesPerHour)
      {
         string g16c = StringFormat("BLOCKED — HFT rate limit %d/%d trades/hr",
                                     gHFTTradesThisHour, InpHFTMaxTradesPerHour);
         JournalInfo("TryEntry", g16c);
         PushEAEvent("Gate16c-RateLimit", g16c);
         return;
      }
      // 16d: Low-volume session suppression
      // v6.3c FIX: only block truly CLOSED market, NOT Sydney.
      //            Sydney/Tokyo have sufficient M1 volatility for HFT (1-2 min trades).
      //            Previous code blocked "SYDNEY" → no HFT during Asian session (20:00-23:00 UTC).
      if(InpHFTSuppressLowVolSession)
      {
         string sess = GetSessionName();
         if(sess=="CLOSED")
         {
            string g16d = StringFormat("BLOCKED — HFT session CLOSED (market offline)",sess);
            JournalInfo("TryEntry", g16d);
            PushEAEvent("Gate16d-Session", g16d);
            return;
         }
      }
      // 16e: HFT post-exit cooldown (much shorter than scalp)
      if(gHFTLastExitTime > 0 &&
         (TimeLocal()-gHFTLastExitTime) < (datetime)InpHFTPostExitCooldownSec)
      {
         string g16e = StringFormat("BLOCKED — HFT exit cooldown %ds remaining",
                       InpHFTPostExitCooldownSec-(int)(TimeLocal()-gHFTLastExitTime));
         JournalInfo("TryEntry", g16e);
         PushEAEvent("Gate16e-Cooldown", g16e);
         return;
      }
   }

   // ── GATE 16: Spike hard-block (beyond 3× threshold) ──────────
   if(gSpike.spikeActive)
   {
      double atr  = GetATR(IDX_M5,1);
      double ratio= SafeDiv(gSpike.spikeRange, atr);
      if(ratio > InpSpikeATRFactor * 3.0)
      { JournalInfo("TryEntry",StringFormat("Spike ratio %.2fx — hard block",ratio)); return; }
   }

   // ── GATE 17: Determine order type ────────────────────────────
   ENUM_ORDER_TYPE orderType = (bias==BIAS_BULL) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   // ── GATE 18: Calculate entry levels ──────────────────────────
   double entryPrice;
   if(orderType==ORDER_TYPE_BUY)
      entryPrice = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
   else
      entryPrice = SymbolInfoDouble(gSymbol, SYMBOL_BID);

   // HFT mode: market order (no offset) — speed is the edge
   // Scalp mode: limit order at offset for better fill pricing
   if(gBotMode == BOT_MODE_HFT)
   {
      // entryPrice stays at market (ASK for BUY, BID for SELL) — no offset
      // PlaceTrade will use ORDER_TYPE_BUY / ORDER_TYPE_SELL (market orders)
   }
   else if(gBotMode == BOT_MODE_SCALPING)
   {
      double offset = GetScalpPendingOffset();
      entryPrice = (orderType==ORDER_TYPE_BUY) ?
                   entryPrice - offset : entryPrice + offset;
   }

   EntryLevels lvl = CalculateEntryLevels(orderType, entryPrice);
   if(!EntryQualityGatePass(orderType, lvl)) return;

   // ── GATE 19: Resolve lot size ─────────────────────────────────
   double lot = ResolveLotSize(lvl.riskDistance, orderType);
   if(lot < gMinLot)
   { JournalWarn("TryEntry","Resolved lot %.4f < minLot %.4f — skip",lot,gMinLot); return; }

   // ── GATE 20: Find free gRec slot ─────────────────────────────
   int slot = -1;
   for(int i=0;i<100;i++) if(!gRec[i].active){slot=i;break;}
   if(slot < 0)
   { JournalError("TryEntry","gRec[] FULL — cannot enter"); return; }

   // ── FIRE: Populate plan and submit order ─────────────────────
   // Pre-populate gRec slot so deal handler can find it immediately
   gRec[slot].active        = true;
   gRec[slot].symbol        = gSymbol;
   gRec[slot].posType       = orderType;
   gRec[slot].initialVolume = lot;
   gRec[slot].entryPrice    = entryPrice;
   gRec[slot].stopLoss      = lvl.sl;
   gRec[slot].hardTP3       = lvl.tp3;
   gRec[slot].tp1Price      = lvl.tp1;
   gRec[slot].tp2Price      = lvl.tp2;
   gRec[slot].tp3Price      = lvl.tp3;
   gRec[slot].riskDistance  = lvl.riskDistance;
   gRec[slot].atrAtEntry    = lvl.atrUsed;
   gRec[slot].tslStep       = lvl.atrUsed * 0.30;
   // HFT reuses scalp tick-TSL logic (same per-tick profit lock, faster parameters)
   gRec[slot].isScalpMode   = (gBotMode==BOT_MODE_SCALPING || gBotMode==BOT_MODE_HFT || gBotMode==BOT_MODE_HFT_PURE);
   gRec[slot].scalpTSLOnTick= (gBotMode==BOT_MODE_SCALPING || gBotMode==BOT_MODE_HFT || gBotMode==BOT_MODE_HFT_PURE);
   gRec[slot].softTPMode    = true;
   gRec[slot].softTPPrice   = lvl.tp3;
   gRec[slot].bestPrice     = entryPrice;
   gRec[slot].createdAt     = TimeLocal();
   gRec[slot].tp1Hit        = false;
   gRec[slot].tp2Hit        = false;
   gRec[slot].breakEvenSet  = false;
   gRec[slot].tslActive     = false;
   gRec[slot].exhaustionHit = false;
   gRec[slot].exhaustionCount=0;
   gRec[slot].ticket        = 0;   // filled after PlaceTrade confirms

   // Build entry reason string
   string modeTag = (gBotMode==BOT_MODE_HFT_PURE) ? "HFT-PURE" :
                    (gBotMode==BOT_MODE_HFT)      ? "HFT"      :
                    (gBotMode==BOT_MODE_SCALPING)  ? "SCALP"    : "MOD";
   gRec[slot].entryReason = StringFormat("%s sc=%d bias=%s sess=%s reg=%s",
      modeTag, score, bias==BIAS_BULL?"BULL":"BEAR",
      GetSessionName(), RegimeToString(gRegime.regime));

   // Call P4 PlaceTrade (submits order, sets gRec[slot].ticket on success)
   bool placed = PlaceTrade(slot, orderType, lot, entryPrice, lvl.sl, lvl.tp3);

   if(!placed)
   {
      // Undo slot reservation on failure
      gRec[slot].active  = false;
      gRec[slot].ticket  = 0;
      JournalError("TryEntry","PlaceTrade returned false — slot freed");
   }
   else
   {
      // HFT: increment hourly rate counter on successful entry
      if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
         gHFTTradesThisHour++;

      JournalInfo("TryEntry",StringFormat(
         "%s ORDER SUBMITTED: %s %s V=%.2f E=%.5f SL=%.5f TP3=%.5f Score=%d",
         modeTag, orderType==ORDER_TYPE_BUY?"BUY":"SELL", gSymbol,
         lot, entryPrice, lvl.sl, lvl.tp3, score));
      UINeedRedraw();
   }
}

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 5 — POSITION MANAGEMENT SUB-FUNCTIONS
//  Called per-position from P7 OnTick step 8.  Each function is
//  idempotent (safe to call every tick; includes its own guards).
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 5.1  BREAKEVEN MANAGEMENT
//       Activates after TP1 is hit.  Moves SL to entry price + 1 pt
//       buffer.  ONE-TIME activation (breakEvenSet latch).
//--------------------------------------------------------------------
void ManageBreakeven(int idx)
{
   if(idx<0||idx>=100||!gRec[idx].active) return;
   // direct gRec[idx] access — MQL5 does not support local struct references

   // Only activate AFTER TP1 hit and not already set
   if(!gRec[idx].tp1Hit)     return;
   if(gRec[idx].breakEvenSet) return;

   // BE-arm delay (v6.5): mirror the P4 gate so neither BE path chokes the
   // runner before it has banked InpScalpBEArmR (0 = arm at TP1 as before).
   if(InpScalpBEArmR > 0.0 && RecordProfitR(idx) < InpScalpBEArmR) return;

   // Compute BE price: entry + 1 point buffer (direction-aware)
   double bePx;
   if(gRec[idx].posType==ORDER_TYPE_BUY)
      bePx = gRec[idx].entryPrice + gPoint;      // 1pt above entry
   else
      bePx = gRec[idx].entryPrice - gPoint;

   // Only move SL if it would be an improvement
   bool improvement = (gRec[idx].posType==ORDER_TYPE_BUY  && bePx > gRec[idx].stopLoss) ||
                      (gRec[idx].posType==ORDER_TYPE_SELL && bePx < gRec[idx].stopLoss);
   if(!improvement) return;

   // Submit SL modification via ModifySLTP (P4)
   if(ModifySLTP(idx, bePx, gRec[idx].hardTP3))
   {
      gRec[idx].stopLoss     = bePx;
      gRec[idx].breakEvenSet = true;
      JournalInfo("ManageBE",StringFormat("BE set TKT=%llu SL=%.5f",gRec[idx].ticket,bePx));
      TGAlert_BreakevenSet(idx);
      UINeedRedraw();
   }
}

//--------------------------------------------------------------------
// 5.2  TRAILING STOP MANAGEMENT
//       MODERATE MODE: bar-close TSL — only moves SL on closed H1 bar.
//         Rate-limit: SL change must be ≥ 0.5 × tslStep to submit.
//       SCALP MODE:   tick-by-tick TSL with 3-tier profit locks.
//         R1=InpScalpProfitLockR1, R2=InpScalpProfitLockR2, R3=InpScalpProfitLockR3
//--------------------------------------------------------------------
void ManageTrailingStop(int idx)
{
   if(idx<0||idx>=100||!gRec[idx].active) return;
   // direct gRec[idx] access — MQL5 does not support local struct references
   if(!gRec[idx].tslActive && !gRec[idx].tp1Hit) return;  // TSL not yet active (activates at TP1)

   if(!PositionSelectByTicket(gRec[idx].ticket)) return;
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);

   // ── SCALP: Tick-by-tick 3-tier profit lock ──────────────────
   if(gRec[idx].isScalpMode && gRec[idx].scalpTSLOnTick)
   {
      double profitR = SafeDiv(
         (gRec[idx].posType==ORDER_TYPE_BUY ? price-gRec[idx].entryPrice : gRec[idx].entryPrice-price),
         gRec[idx].riskDistance);

      double lockSL = gRec[idx].stopLoss;

      // Tier 1: profit ≥ R1 → lock at entry (BE already handled by ManageBreakeven)
      // Tier 2: profit ≥ R2 → lock at R1 profit level
      // Tier 3: profit ≥ R3 → lock at R2 profit level
      if(profitR >= InpScalpProfitLockR3)
      {
         // Lock at R2 profit
         double lockPx = (gRec[idx].posType==ORDER_TYPE_BUY) ?
                         gRec[idx].entryPrice + gRec[idx].riskDistance * InpScalpProfitLockR2 :
                         gRec[idx].entryPrice - gRec[idx].riskDistance * InpScalpProfitLockR2;
         lockSL = lockPx;
      }
      else if(profitR >= InpScalpProfitLockR2)
      {
         // Lock at R1 profit
         double lockPx = (gRec[idx].posType==ORDER_TYPE_BUY) ?
                         gRec[idx].entryPrice + gRec[idx].riskDistance * InpScalpProfitLockR1 :
                         gRec[idx].entryPrice - gRec[idx].riskDistance * InpScalpProfitLockR1;
         lockSL = lockPx;
      }

      // Only move if improvement AND meaningful change (≥ 0.5 tslStep)
      bool isImprovement = (gRec[idx].posType==ORDER_TYPE_BUY  && lockSL > gRec[idx].stopLoss + gRec[idx].tslStep*0.50) ||
                           (gRec[idx].posType==ORDER_TYPE_SELL && lockSL < gRec[idx].stopLoss - gRec[idx].tslStep*0.50);
      if(isImprovement)
      {
         if(ModifySLTP(idx, lockSL, gRec[idx].hardTP3))
         {
            gRec[idx].stopLoss  = lockSL;
            gRec[idx].tslActive = true;
            JournalInfo("TSL-Scalp",StringFormat("TKT=%llu ProfitR=%.2f SL→%.5f",
                                                   gRec[idx].ticket,profitR,lockSL));
         }
      }

      // Update best price tracker
      if(gRec[idx].posType==ORDER_TYPE_BUY  && price>gRec[idx].bestPrice) gRec[idx].bestPrice=price;
      if(gRec[idx].posType==ORDER_TYPE_SELL && price<gRec[idx].bestPrice) gRec[idx].bestPrice=price;
      return;
   }

   // ── MODERATE: Bar-close TSL (only on new H1 bar) ─────────────
   if(!gRec[idx].isScalpMode)
   {
      if(!gTF[IDX_H1].newBar) return;  // only process on bar close

      double atr = GetATR(IDX_H1, 1);
      if(atr < DBL_EPSILON) return;

      // Trail distance: 1.0 × ATR below price (buy) or above price (sell)
      double trailDist = atr * 1.00;
      double newSL;
      if(gRec[idx].posType==ORDER_TYPE_BUY)
      {
         newSL = price - trailDist;
         if(newSL <= gRec[idx].stopLoss + gRec[idx].tslStep*0.50) return; // rate limit: < 0.5 step = skip
         if(newSL <= gRec[idx].entryPrice && !gRec[idx].breakEvenSet) return; // never trail below entry before BE
      }
      else
      {
         newSL = price + trailDist;
         if(newSL >= gRec[idx].stopLoss - gRec[idx].tslStep*0.50) return;
         if(newSL >= gRec[idx].entryPrice && !gRec[idx].breakEvenSet) return;
      }

      if(ModifySLTP(idx, newSL, gRec[idx].hardTP3))
      {
         gRec[idx].stopLoss  = newSL;
         gRec[idx].tslActive = true;
         JournalInfo("TSL-Mod",StringFormat("TKT=%llu H1bar SL→%.5f",gRec[idx].ticket,newSL));
      }
   }
}

//--------------------------------------------------------------------
// 5.3  RSI EXHAUSTION MANAGEMENT  — defined in P4 §8.5 (ManageExhaustion)
//       Full implementation: InpRSIExhaustionExit guard + RSIExhaustionDetected()
//       multi-bar check + PushDiag + TGEnqueue. Called from ManageTradeRecordAdvanced.
//--------------------------------------------------------------------
// void ManageExhaustion(int idx) — P4 §8.5

//--------------------------------------------------------------------
// 5.4  VIRTUAL TP1 / TP2 HIT DETECTION AND PARTIAL CLOSE EXECUTION
//       Compares live price against tp1Price and tp2Price.
//       On hit: closes the appropriate percentage and sets latch.
//--------------------------------------------------------------------
void ManagePartialCloseCheck(int idx)
{
   if(idx<0||idx>=100||!gRec[idx].active) return;
   // direct gRec[idx] access — MQL5 does not support local struct references

   if(!PositionSelectByTicket(gRec[idx].ticket)) return;
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double currentVol = PositionGetDouble(POSITION_VOLUME);

   // ── TP1 hit check (30% close) ─────────────────────────────────
   if(!gRec[idx].tp1Hit)
   {
      bool tp1Reached = (gRec[idx].posType==ORDER_TYPE_BUY  && price >= gRec[idx].tp1Price) ||
                        (gRec[idx].posType==ORDER_TYPE_SELL && price <= gRec[idx].tp1Price);
      if(tp1Reached)
      {
         double closeVol = NormalizeLotSafe(gRec[idx].initialVolume * 0.30, gSymbol);
         if(closeVol > currentVol) closeVol = currentVol;
         if(closeVol < gMinLot)    closeVol = currentVol;  // close all if too small

         if(PartialCloseVolumeManaged(idx, closeVol, "TP1-30PCT"))
         {
            gRec[idx].tp1Hit  = true;
            gRec[idx].tslActive = true;   // activate TSL after TP1
            JournalInfo("TP1",StringFormat("TKT=%llu TP1 hit price=%.5f closed %.2f",
                                            gRec[idx].ticket,price,closeVol));
            TGAlert_TP1Hit(idx);
            UINeedRedraw();
         }
         return;
      }
   }

   // ── TP2 hit check (40% close) — only after TP1 ─────────────────
   if(gRec[idx].tp1Hit && !gRec[idx].tp2Hit)
   {
      bool tp2Reached = (gRec[idx].posType==ORDER_TYPE_BUY  && price >= gRec[idx].tp2Price) ||
                        (gRec[idx].posType==ORDER_TYPE_SELL && price <= gRec[idx].tp2Price);
      if(tp2Reached)
      {
         double closeVol = NormalizeLotSafe(gRec[idx].initialVolume * 0.40, gSymbol);
         if(closeVol > currentVol) closeVol = currentVol;
         if(closeVol < gMinLot)    closeVol = currentVol;

         if(PartialCloseVolumeManaged(idx, closeVol, "TP2-40PCT"))
         {
            gRec[idx].tp2Hit = true;
            JournalInfo("TP2",StringFormat("TKT=%llu TP2 hit price=%.5f closed %.2f",
                                            gRec[idx].ticket,price,closeVol));
            TGAlert_TP2Hit(idx);
            UINeedRedraw();
         }
      }
   }
}

//--------------------------------------------------------------------
// 5.5  REVERSE EMA CROSS EXIT  — defined in P4 §8.6 (ManageReverseExit)
//       Full implementation: InpUseReverseExit guard + CrossedDown/CrossedUp on M5
//       + PartialCloseVolumeManagedFull + BuildExitMessage. Called from
//       ManageTradeRecordAdvanced.
//--------------------------------------------------------------------
// void ManageReverseExit(int idx) — P4 §8.6

//--------------------------------------------------------------------
// 5.6  PENDING ORDER AGE CHECK  (scalp limit orders only)
//       Cancels pending limit orders that have exceeded InpScalpPendingMaxAgeSec
//--------------------------------------------------------------------
void ManagePendingOrderAge(int idx)
{
   if(idx<0||idx>=100||!gRec[idx].active) return;
   // direct gRec[idx] access — MQL5 does not support local struct references

   // Only applies to scalp mode pending orders (ticket exists but position not yet open)
   if(!gRec[idx].isScalpMode) return;
   if(PositionSelectByTicket(gRec[idx].ticket)) return;  // position is open — not pending

   // Check if the order still exists as a pending order
   if(!OrderSelect(gRec[idx].ticket)) return;  // order doesn't exist either — orphaned slot

   ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(ot != ORDER_TYPE_BUY_LIMIT && ot != ORDER_TYPE_SELL_LIMIT) return;

   int ageSeconds = (int)(TimeLocal() - gRec[idx].createdAt);
   if(ageSeconds > InpScalpPendingMaxAgeSec)
   {
      JournalInfo("PendingAge",StringFormat("TKT=%llu limit order aged %ds > %ds — cancelling",
                                             gRec[idx].ticket, ageSeconds, InpScalpPendingMaxAgeSec));
      if(gTrade.OrderDelete(gRec[idx].ticket))
      {
         gRec[idx].active = false;
         gRec[idx].ticket = 0;
         UINeedRedraw();
      }
      else
         JournalError("PendingAge",StringFormat("OrderDelete failed ERR=%d TKT=%llu",
                                                 GetLastError(), gRec[idx].ticket));
   }
}

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 6 — SAFETY VAULT SUB-FUNCTIONS & RETRY QUEUE
//  These are sub-functions called by CheckSafetyLockAdvanced (P4)
//  and directly from P7 OnTick step 13 for hot-path evaluation.
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 6.1  EQUITY FLOOR LOCK
//       Blocks all entries if equity falls below InpEquityFloorPct
//       of account balance.
//--------------------------------------------------------------------
void CheckEquityFloor()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance < DBL_EPSILON) return;

   double eqPct = SafeDiv(equity, balance) * 100.0;
   bool   below = (eqPct < InpEquityFloorPct);

   if(below && !gSafety.lockEquityFloor)
   {
      gSafety.lockEquityFloor = true;
      JournalError("SafeEQ",StringFormat("EQUITY FLOOR LOCK: eq=%.2f bal=%.2f (%.1f%% < %.1f%%)",
                                          equity,balance,eqPct,InpEquityFloorPct));
      TGAlert_SafetyLock("EQUITY_FLOOR",
                         StringFormat("Equity %.1f%% below floor %.1f%%",eqPct,InpEquityFloorPct));
   }
   else if(!below && gSafety.lockEquityFloor)
   {
      gSafety.lockEquityFloor = false;
      TGAlert_SafetyRelease("EQUITY_FLOOR");
      JournalInfo("SafeEQ","Equity floor lock released");
   }
}

//--------------------------------------------------------------------
// 6.2  DAILY LOSS LIMIT LOCK
//       Blocks entries if gDailyClosedPnL exceeds InpDailyLossPct
//       of daily start balance.
//--------------------------------------------------------------------
void CheckDailyLossLimit()
{
   if(gDailyStartBalance < DBL_EPSILON) return;
   // Use sub-mode DD ceiling (gRt_DailyDDPct) — set by ApplySubMode() in OnInit.
   // Falls back to InpMaxDailyLossPercent if ApplySubMode was never called.
   double ddLimit = (gRt_DailyDDPct > 0.0) ? gRt_DailyDDPct : InpDailyLossPct;
   // v6.3g: Include floating (unrealized) loss from open positions so HFT can't hide
   // catastrophic open drawdown behind gDailyClosedPnL (which only counts closed trades).
   double floatingLoss = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
   double combinedLoss = MathMin(0.0, gDailyClosedPnL) + MathMin(0.0, floatingLoss);
   double dailyLossPct = SafeDiv(MathAbs(combinedLoss), gDailyStartBalance) * 100.0;
   bool   breached     = (dailyLossPct >= ddLimit);

   if(breached && !gSafety.lockDailyLoss)
   {
      gSafety.lockDailyLoss = true;
      JournalError("SafeDL",StringFormat("DAILY LOSS LOCK [%s]: %.2f (%.1f%% >= %.1f%%)",
                                          SubModeName(), gDailyClosedPnL, dailyLossPct, ddLimit));
      TGAlert_SafetyLock("DAILY_LOSS",
                         StringFormat("Daily loss %.1f%% breached [%s] limit %.1f%%",
                                      dailyLossPct, SubModeName(), ddLimit));
      EmergencyCloseAll("DailyLossLimit");
   }
   // Daily loss lock releases only on next day (CheckDailyReset in P7)
}

//--------------------------------------------------------------------
// 6.3  GLOBAL DRAWDOWN LOCK  (with 50% hysteresis release)
//       Engages at InpGlobalDDPct.  Releases at 50% of that level.
//--------------------------------------------------------------------
void CheckGlobalDrawdown()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance < DBL_EPSILON) return;

   // Update high-water mark
   if(equity > gSafety.ddHighWaterMark) gSafety.ddHighWaterMark = equity;

   double ddPct = SafeDiv(gSafety.ddHighWaterMark - equity, gSafety.ddHighWaterMark) * 100.0;
   gSafety.globalDDPct = ddPct;
   gSafety.globalDDHysteresisPct = InpGlobalDDPct * 0.50;   // release at 50% of trigger

   if(!gSafety.lockGlobalDD)
   {
      if(ddPct >= InpGlobalDDPct)
      {
         gSafety.lockGlobalDD = true;
         JournalError("SafeDD",StringFormat("GLOBAL DD LOCK: %.1f%% ≥ %.1f%%",ddPct,InpGlobalDDPct));
         TGAlert_SafetyLock("GLOBAL_DD",
                            StringFormat("Global DD %.1f%% ≥ limit %.1f%%",ddPct,InpGlobalDDPct));
         EmergencyCloseAll("GlobalDrawdownLimit");
      }
   }
   else
   {
      // Hysteresis: release only when DD recovers to 50% of limit
      if(ddPct < gSafety.globalDDHysteresisPct)
      {
         gSafety.lockGlobalDD = false;
         TGAlert_SafetyRelease("GLOBAL_DD");
         JournalInfo("SafeDD",StringFormat("Global DD lock released at %.1f%%",ddPct));
      }
   }
}

//--------------------------------------------------------------------
// 6.4  RETRY QUEUE PROCESSOR  — defined in P4 §8.10 (ProcessRetryQueue)
//       Full implementation: TimeCurrent(), gRetry[].used/.nextTry/.price1/.price2
//       /.volume/.note — handles kinds 1(SLTP modify), 2(partial close),
//       3(panic close), 4(cancel pending). Called from P7 OnTick step 11.
//--------------------------------------------------------------------
// void ProcessRetryQueue() — P4 §8.10

//--------------------------------------------------------------------
// 6.5  ENQUEUE RETRY RECORD  (safe to call from anywhere)
//--------------------------------------------------------------------
bool EnqueueRetry(int kind, ulong ticket, double price1=0, double price2=0)
{
   for(int i=0;i<64;i++)
   {
      if(gRetry[i].active) continue;
      gRetry[i].active      = true;
      gRetry[i].kind        = kind;
      gRetry[i].ticket      = ticket;
      gRetry[i].retryPrice  = price1;
      gRetry[i].retryPrice2 = price2;
      gRetry[i].attempts    = 0;
      gRetry[i].createdAt   = TimeLocal();
      return true;
   }
   JournalError("EnqueueRetry","gRetry[] FULL — retry dropped kind="+IntegerToString(kind));
   return false;
}

// ─── END OF ENGINES 4-6 ──────────────────────────────────────────────

//====================================================================
//  ┌────────────────────────────────────────────────────────────────┐
//  │   END OF PART 3                                                 │
//  │                                                                  │
//  │   All 7 parts complete:                                          │
//  │   P1 — Inputs / Structs / Globals / Helpers                     │
//  │   P2 — Engines 1-3  (Trend Matrix / Divergence / Session/Pat)  │
//  │   P3 — Engines 4-6  (Lot Resolve / Mgmt / Safety / Retry)      │
//  │   P4 — Engines 7-9  (Trade Exec / Position Mgmt / Safety Vault) │
//  │   P5 — Engines 10-12 + v5.0 (Broker / Regime / Portfolio /      │
//  │                               Spike / News / Volume / Profile)  │
//  │   P6 — Engines 13-15 (Telegram / Dashboard / Patch Engine)     │
//  │   P7 — Event Handlers (OnInit / OnTick / OnTimer / etc.)       │
//  │                                                                  │
//  │   Assemble P1→P2→P3→P4→P5→P6→P7 into one .mq5 file.          │
//  │   Follow the assembly checklist in P7 Section 7.16.             │
//  └────────────────────────────────────────────────────────────────┘
//====================================================================


#endif // SKP_P3_ENTRY_MQH
