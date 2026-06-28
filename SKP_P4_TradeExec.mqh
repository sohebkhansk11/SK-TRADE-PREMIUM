#ifndef SKP_P4_TRADEEXEC_MQH
#define SKP_P4_TRADEEXEC_MQH

//════════════════════════════════════════════════════════════════════
//  ⚙️  SK TRADE PREMIUM BOT v6.0 — PART 4
//  ENGINE 7  — Trade Execution Engine
//  ENGINE 8  — Position Management Engine
//  ENGINE 9  — Safety Vault Engine
//  ─────────────────────────────────────────────────────────────────
//  Spec refs: v6.md §Engine 7-9, Analysis 1 (all 7 critical fixes),
//             Analysis 2.docx (exhaustion latch, TP virtual/hard split,
//             TSL rate-limit, async emergency close, lot zero-guard)
//  ─────────────────────────────────────────────────────────────────
//  ABSOLUTE ENGINEERING CONTRACTS (violation = system bug):
//  ✅  TP3 ONLY is sent to broker as hard TP. TP1/TP2 are VIRTUAL.
//  ✅  SafeDiv() wraps ALL financial divisions — zero-divide immunity.
//  ✅  NormalizeLotSafe() called before EVERY broker lot submission.
//  ✅  exhaustionHit = true PERMANENTLY after first 50% exhaustion exit.
//  ✅  TSL only modifies if |newSL − curSL| >= tslStep × 0.50.
//  ✅  TGEnqueue() NEVER called from hot tick path — only from
//      PlaceTrade / management events (still within OnTick dispatch
//      but queued for OnTimer delivery — no HTTP in OnTick).
//  ✅  EmergencyCloseAll: attempt → if fail → RetryAction queue.
//  ✅  No Sleep() anywhere in this file.
//════════════════════════════════════════════════════════════════════

//— Scalper profit-lock R-multiple thresholds (hardcoded, spec §Engine 8)
#define SCALP_LOCK_R1  0.60   // Lock step 1 trigger: 0.60R profit
#define SCALP_LOCK_R2  0.90   // Lock step 2 trigger: 0.90R profit
#define SCALP_LOCK_R3  1.20   // Lock step 3 trigger: 1.20R profit

//— Maximum retry attempts for queued actions before giving up
#define RETRY_MAX_ATTEMPTS  4
#define RETRY_INTERVAL_SEC  3

//════════════════════════════════════════════════════════════════════
//  §7.0b — MARKET-STATE GUARD  (retry-storm fix, v6.5)
//
//  Root cause of the 48× "market closed" retry storm seen at session
//  rollover / weekend: close & modify orders were fired blind, each
//  failed with TRADE_RETCODE_MARKET_CLOSED (10018), re-queued, and the
//  retry queue hammered the broker every few seconds with no awareness
//  that the trading session was simply shut.
//
//  IsMarketTradeable() answers "can the broker accept an order RIGHT NOW"
//  deterministically (works in tester) using the symbol's own session
//  schedule.  It is intentionally FAIL-OPEN: if the broker exposes no
//  session data we assume the market is open so we never wrongly block a
//  legitimate close.  Used only to *defer* retries/closes, never to block
//  fresh entries.
//════════════════════════════════════════════════════════════════════
bool IsMarketTradeable()
{
   // 1) Terminal / EA must be allowed to trade at all
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           return false;

   // 2) Symbol must not be flat-out disabled
   long tmode = SymbolInfoInteger(gSymbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_MODE_DISABLED) return false;

   // 3) Current server time must fall inside a declared trade session.
   //    SymbolInfoSessionTrade returns from/to as seconds-since-midnight.
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)now.day_of_week;
   uint secOfDay = (uint)(now.hour * 3600 + now.min * 60 + now.sec);

   datetime fromT = 0, toT = 0;
   bool gotAny = false, inSession = false;
   for(int s = 0; s < 20; s++)
   {
      if(!SymbolInfoSessionTrade(gSymbol, dow, (uint)s, fromT, toT)) break;
      gotAny = true;
      uint f = (uint)fromT;
      uint t = (uint)toT;
      if(secOfDay >= f && secOfDay < t) { inSession = true; break; }
   }

   if(!gotAny) return true;   // broker exposes no schedule → assume open (fail-open)
   return inSession;
}

//— Dedup helper: is a retry of this kind for this ticket already queued?
bool RetryQueuedFor(ulong ticket, int kind)
{
   for(int i = 0; i < 64; i++)
      if(gRetry[i].used && gRetry[i].ticket == ticket && gRetry[i].kind == kind)
         return true;
   return false;
}

//════════════════════════════════════════════════════════════════════
//  §7.1 — POSITION AND ORDER UTILITY HELPERS
//  Low-level position/order accessors used throughout Engines 7 & 8.
//  All selectors return safe defaults if PositionSelectByTicket fails.
//════════════════════════════════════════════════════════════════════

//--- Returns true if a live broker position with this ticket exists
bool PositionExistsByTicket(ulong ticket)
{
   return PositionSelectByTicket(ticket);
}

//--- Returns true if EA has any active tracked position on this symbol
bool HasExposureOnSymbol()
{
   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active) continue;
      if(gRec[i].symbol != gSymbol) continue;
      if(PositionExistsByTicket(gRec[i].ticket)) return true;
   }
   return false;
}

//--- Get floating profit/loss of a specific position (0.0 if not found)
double GetPositionFloatPL(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_PROFIT);
}

//--- Get current broker-side stop loss of a position
double GetPositionCurrentSL(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_SL);
}

//--- Get current broker-side take profit of a position
double GetPositionCurrentTP(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_TP);
}

//--- Get current open volume (remaining lots) of a position
double GetPositionCurrentVolume(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_VOLUME);
}

//--- Get position open price (actual broker fill price)
double GetPositionOpenPrice(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_PRICE_OPEN);
}

//--- Get position type as ENUM_ORDER_TYPE (BUY=0, SELL=1)
//    Note: POSITION_TYPE_BUY=0, POSITION_TYPE_SELL=1 == ORDER_TYPE_BUY/SELL
ENUM_ORDER_TYPE GetPositionSide(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return ORDER_TYPE_BUY; // safe default
   long t = PositionGetInteger(POSITION_TYPE);
   return (t == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
}

//--- Count all active EA positions tracked in gRec[]
int GetOpenPositionCount()
{
   int cnt = 0;
   for(int i = 0; i < 100; i++)
      if(gRec[i].active && PositionExistsByTicket(gRec[i].ticket)) cnt++;
   return cnt;
}

//--- Check if a pending order ticket is still alive at broker
bool PendingOrderExists(ulong ticket)
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong t = OrderGetTicket(i);
      if(t == ticket) return true;
   }
   return false;
}

//--- Get the bid/ask price for the current execution side
double GetExecutionPrice(ENUM_BIAS bias)
{
   if(bias == BIAS_BULL) return SymbolInfoDouble(gSymbol, SYMBOL_ASK);
   if(bias == BIAS_BEAR) return SymbolInfoDouble(gSymbol, SYMBOL_BID);
   return SymbolInfoDouble(gSymbol, SYMBOL_BID);
}

//--- Current bid (for BUY TSL trailing reference)
double GetBid() { return SymbolInfoDouble(gSymbol, SYMBOL_BID); }
//--- Current ask (for SELL TSL trailing reference)
double GetAsk() { return SymbolInfoDouble(gSymbol, SYMBOL_ASK); }

//════════════════════════════════════════════════════════════════════
//  §7.2 — TRADE RECORD MANAGEMENT
//  gRec[100] — active position tracker (all EA-managed positions)
//  gPlan[20] — scalp pending order intent binding
//  FIFO search: O(N) but arrays are small (100/20 max) — acceptable.
//════════════════════════════════════════════════════════════════════

//--- Find first free slot in gRec[] (-1 if full)
int FindFreeRecordSlot()
{
   for(int i = 0; i < 100; i++)
      if(!gRec[i].active) return i;
   Print("🚨 E7: gRec[] FULL — 100 positions tracked, cannot add more");
   return -1;
}

//--- Find first free slot in gPlan[] (-1 if full)
int FindFreePendingSlot()
{
   for(int i = 0; i < 20; i++)
      if(!gPlan[i].active) return i;
   Print("🚨 E7: gPlan[] FULL — 20 pending plans at capacity");
   return -1;
}

//--- Find trade record by broker ticket (-1 if not tracked)
int FindRecordByTicket(ulong ticket)
{
   for(int i = 0; i < 100; i++)
      if(gRec[i].active && gRec[i].ticket == ticket) return i;
   return -1;
}

//--- Find pending plan by order ticket (-1 if not found)
int FindPendingByTicket(ulong ticket)
{
   for(int i = 0; i < 20; i++)
      if(gPlan[i].active && gPlan[i].orderTicket == ticket) return i;
   return -1;
}

//--- Reset a trade record to empty/inactive (zero all critical fields)
void ClearRecord(int idx)
{
   if(idx < 0 || idx >= 100) return;
   gRec[idx].active          = false;
   gRec[idx].ticket          = 0;
   gRec[idx].symbol          = "";
   gRec[idx].posType         = ORDER_TYPE_BUY;
   gRec[idx].initialVolume   = 0.0;
   gRec[idx].entryPrice      = 0.0;
   gRec[idx].stopLoss        = 0.0;
   gRec[idx].initialSL       = 0.0;
   gRec[idx].hardTP3         = 0.0;
   gRec[idx].tp1Price        = 0.0;
   gRec[idx].tp2Price        = 0.0;
   gRec[idx].tp3Price        = 0.0;
   gRec[idx].riskDistance    = 0.0;
   gRec[idx].tslStep         = 0.0;
   gRec[idx].tp1Hit          = false;
   gRec[idx].tp2Hit          = false;
   gRec[idx].breakEvenSet    = false;
   gRec[idx].tslActive       = false;
   gRec[idx].exhaustionHit   = false;
   gRec[idx].exhaustionCount = 0;
   gRec[idx].isScalpMode     = false;
   gRec[idx].scalpTSLOnTick  = false;
   gRec[idx].softTPMode      = false;
   gRec[idx].softTPPrice     = 0.0;
   gRec[idx].bestPrice       = 0.0;
   gRec[idx].atrAtEntry      = 0.0;
   gRec[idx].spreadAtEntry   = 0.0;
   gRec[idx].entryReason     = "";
   gRec[idx].createdAt       = 0;
   gRec[idx].lastManageAt    = 0;
}

//--- Reset a pending plan to empty/inactive
void ClearPendingPlan(int idx)
{
   if(idx < 0 || idx >= 20) return;
   gPlan[idx].active         = false;
   gPlan[idx].orderTicket    = 0;
   gPlan[idx].symbol         = "";
   gPlan[idx].bias           = BIAS_NONE;
   gPlan[idx].mode           = 0;
   gPlan[idx].lot            = 0.0;
   gPlan[idx].entry          = 0.0;
   gPlan[idx].sl             = 0.0;
   gPlan[idx].tp1            = 0.0;
   gPlan[idx].tp2            = 0.0;
   gPlan[idx].tp3            = 0.0;
   gPlan[idx].riskDistance   = 0.0;
   gPlan[idx].createdAt      = 0;
}

//--- Register a newly filled market position into gRec[]
void RegisterTradeRecord(ulong ticket, ENUM_ORDER_TYPE posType,
                         double entry,  double sl,
                         double tp1,    double tp2,  double tp3,
                         double lot,    double atr,  string reason)
{
   int idx = FindFreeRecordSlot();
   if(idx < 0)
   {
      JournalWrite("RECORD_OVERFLOW", IntegerToString(ticket));
      PushDiag("🚨 E7: TradeRecord FULL — ticket=" + IntegerToString(ticket) + " UNTRACKED!");
      return;
   }

   // HFT uses tick-level management same as SCALP (softTP, scalpOnTick, TSL on tick).
   bool isScalp = (InpMode == BOT_MODE_SCALPING || InpMode == BOT_MODE_HFT || InpMode == BOT_MODE_HFT_PURE);

   gRec[idx].active          = true;
   gRec[idx].ticket          = ticket;
   gRec[idx].symbol          = gSymbol;
   gRec[idx].posType         = posType;
   gRec[idx].initialVolume   = lot;
   gRec[idx].entryPrice      = entry;
   gRec[idx].stopLoss        = sl;
   gRec[idx].initialSL       = sl;
   gRec[idx].hardTP3         = tp3;
   gRec[idx].tp1Price        = tp1;
   gRec[idx].tp2Price        = tp2;
   gRec[idx].tp3Price        = tp3;
   gRec[idx].riskDistance    = MathAbs(entry - sl);
   // TSL step: Moderate uses 1.2×ATR, Scalp uses fraction ATR
   gRec[idx].tslStep         = isScalp
                               ? (atr * InpScalpTSLATRFraction)
                               : (atr * InpModerateTSLATR);
   gRec[idx].tp1Hit          = false;
   gRec[idx].tp2Hit          = false;
   gRec[idx].breakEvenSet    = false;
   gRec[idx].tslActive       = false;
   // 🔒 exhaustionHit starts false — set PERMANENTLY on first 50% close
   gRec[idx].exhaustionHit   = false;
   gRec[idx].exhaustionCount = 0;
   gRec[idx].isScalpMode     = isScalp;
   // HFT always uses tick-level TSL (isScalp=true for HFT via Fix 7).
   // Without this, isScalpMode=true + scalpTSLOnTick=false creates a dead path
   // where neither scalp-tick TSL nor moderate bar-TSL executes.
   gRec[idx].scalpTSLOnTick  = (isScalp && (gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE))
                               ? true : InpScalpTSLOnTick;
   gRec[idx].softTPMode      = isScalp; // scalp uses soft/virtual TP mode
   gRec[idx].softTPPrice     = tp1;     // scalp soft TP initialised to TP1
   gRec[idx].bestPrice       = entry;   // high-watermark for TSL starts at entry
   gRec[idx].atrAtEntry      = atr;
   gRec[idx].spreadAtEntry   = GetSpreadPoints();
   gRec[idx].createdAt       = TimeCurrent();
   gRec[idx].lastManageAt    = TimeCurrent();
   gRec[idx].entryReason     = reason;

   PushDiag("✅ E7: Rec[" + IntegerToString(idx) + "] ticket=" + IntegerToString(ticket)
            + " " + (posType == ORDER_TYPE_BUY ? "BUY" : "SELL")
            + " @" + DoubleToString(entry, gDigits)
            + " lot=" + DoubleToString(lot, 2)
            + " SL=" + DoubleToString(sl, gDigits)
            + " TP3=" + DoubleToString(tp3, gDigits));
}

//--- Register a newly placed scalp pending order into gPlan[]
void RegisterPendingPlan(ulong orderTicket, ENUM_BIAS bias,
                         double entry, double sl,
                         double tp1,   double tp2, double tp3,
                         double lot,   double atr)
{
   int idx = FindFreePendingSlot();
   if(idx < 0)
   {
      JournalWrite("PENDING_OVERFLOW", IntegerToString(orderTicket));
      PushDiag("🚨 E7: PendingPlan FULL — order=" + IntegerToString(orderTicket) + " untracked!");
      return;
   }

   gPlan[idx].active         = true;
   gPlan[idx].orderTicket    = orderTicket;
   gPlan[idx].symbol         = gSymbol;
   gPlan[idx].bias           = bias;
   gPlan[idx].mode           = InpMode;
   gPlan[idx].lot            = lot;
   gPlan[idx].entry          = entry;
   gPlan[idx].sl             = sl;
   gPlan[idx].tp1            = tp1;
   gPlan[idx].tp2            = tp2;
   gPlan[idx].tp3            = tp3;
   gPlan[idx].riskDistance   = MathAbs(entry - sl);
   gPlan[idx].createdAt      = TimeCurrent();

   PushDiag("📋 E7: Plan[" + IntegerToString(idx) + "] order=" + IntegerToString(orderTicket)
            + " " + (bias == BIAS_BULL ? "BUYLIMIT" : "SELLLIMIT")
            + " @" + DoubleToString(entry, gDigits)
            + " lot=" + DoubleToString(lot, 2));
}

//════════════════════════════════════════════════════════════════════
//  §7.3 — LOT SIZE RESOLUTION — 6-LAYER MULTIPLIER STACK
//  Applied in STRICT sequence — never reorder layers.
//  Any layer returning 0 aborts the entire chain (fail-safe).
//
//  Layer 1: Base lot — Auto (risk%) or Manual (fixed)
//  Layer 2: Loss smoothening — stepped table per consecutive losses
//  Layer 3: Portfolio rank multiplier — watchlist arbitration
//  Layer 4: Regime lot multiplier — from Engine 11 (RegimeLotMultiplier)
//  Layer 5: Symbol preset override — per-CSV-entry risk scale
//  Layer 6: Clamp [MinLotCap, MaxLotCap] + NormalizeLotSafe
//════════════════════════════════════════════════════════════════════

//--- LAYER 2: Loss smoothening stepped table
//    Spec table: 0=1.00 | 1=0.85 | 2=0.70 | 3=0.55 | 4+=0.45
//    Activation: only applies when gConsecLosses >= InpConsecutiveLossForSmooth
double LossSmoothLotMultiplierEx()
{
   // Not yet at activation threshold — full lot
   if(gConsecLosses < InpConsecutiveLossForSmooth) return 1.00;

   // Stepped table (floor at 4+ losses)
   if(gConsecLosses <= 0) return 1.00;
   if(gConsecLosses == 1) return 0.85;
   if(gConsecLosses == 2) return 0.70;
   if(gConsecLosses == 3) return 0.55;
   return 0.45;  // 4 or more consecutive losses — hard floor
}

//--- LAYER 3: Portfolio rank multiplier
//    Rank 1 (top) = 1.00×  |  Rank 2 = 0.70×  |  Rank 3 = 0.50×  |  Rank 4+ = 0.35×
double CalcPortfolioRankMultiplier()
{
   if(!InpUsePortfolioEngine) return 1.00;

   for(int i = 0; i < 32; i++)
   {
      if(!gPortCand[i].valid) continue;
      if(gPortCand[i].symbol != gSymbol) continue;
      switch(gPortCand[i].rank)
      {
         case 1:  return 1.00;
         case 2:  return 0.70;
         case 3:  return 0.50;
         default: return 0.35;
      }
   }
   return 1.00; // chart symbol not in watchlist → full risk
}

//--- LAYER 5: Symbol preset risk multiplier (CSV-defined per-symbol)
//    CSV format: "SYMBOL,MODE,RISK_MULT,SCALP_MULT;..."
double SymbolPresetRiskMultiplier()
{
   if(!InpUseSymbolPresets) return 1.00;

   string entries[];
   int n = StringSplit(InpPresetCSV, ';', entries);
   for(int i = 0; i < n; i++)
   {
      string fields[];
      if(StringSplit(entries[i], ',', fields) < 3) continue;
      StringTrimLeft(fields[0]);
      StringTrimRight(fields[0]);
      if(fields[0] != gSymbol) continue;

      // fields[2] = risk multiplier for this symbol
      double mult = StringToDouble(fields[2]);
      if(mult <= 0.0) mult = 1.00;
      return Clamp(mult, 0.05, 10.00); // hard sanity bounds
   }
   return 1.00; // symbol not in preset CSV
}

//--- LAYER 6: Clamp lot to [MinLotCap, MaxLotCap] configured bounds
double ClampModeLot(double lot)
{
   double minCap = (InpMinLotCap > 0.0) ? InpMinLotCap : gMinLot;
   double maxCap = (InpMaxLotCap > 0.0) ? InpMaxLotCap : gMaxLot;
   return Clamp(lot, minCap, maxCap);
}

//--- LAYER 1a: Full risk-based lot calculation with complete zero-divide protection
double CalcLotByRiskPercentEx(double entry, double sl, double riskPct)
{
   // Zero-divide guard: stop distance must be meaningful
   double stopDist = MathAbs(entry - sl);
   if(stopDist < gPoint * 0.1)
   {
      PushDiag("⚠️ E7: CalcLot — SL distance near zero ("
               + DoubleToString(stopDist, gDigits + 2) + ") → LOT_RESOLVE_FAIL");
      JournalWrite("LOT_RESOLVE_FAIL", "ZERO_SL_DIST",
                   "entry=" + DoubleToString(entry, gDigits),
                   "sl=" + DoubleToString(sl, gDigits),
                   "dist=" + DoubleToString(stopDist, gDigits + 2));
      return 0.0;
   }

   // Equity and risk money
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * Clamp(riskPct, 0.001, 25.0) / 100.0;

   // Point monetary value — zero-divide guarded (tickSize could theoretically be 0)
   double pointVal = SafeDiv(gTickValue, gTickSize);
   if(pointVal <= 0.0)
   {
      PushDiag("⚠️ E7: CalcLot — tickValue/tickSize invalid (pointVal=" + DoubleToString(pointVal, 6) + ")");
      JournalWrite("LOT_RESOLVE_FAIL", "INVALID_POINT_VAL",
                   "tickVal=" + DoubleToString(gTickValue, 6),
                   "tickSz=" + DoubleToString(gTickSize, 6));
      return 0.0;
   }

   // Core lot formula: Risk$ ÷ (StopDistance × PointValue)
   double rawLot = SafeDiv(riskMoney, stopDist * pointVal);

   return rawLot;
}

//─────────────────────────────────────────────────────────────────────
//  MASTER LOT RESOLVER — applies all 6 layers in strict sequence
//─────────────────────────────────────────────────────────────────────
double ResolveModeLotSize(double entry, double sl)
{
   double lot = 0.0;

   //── Layer 1: Base lot ─────────────────────────────────────────────
   if(InpLotMode == LOT_MODE_AUTO)
   {
      lot = CalcLotByRiskPercentEx(entry, sl, InpRiskPercent);
   }
   else // LOT_MODE_MANUAL
   {
      lot = InpManualLot;
   }

   if(lot <= 0.0)
   {
      JournalWrite("LOT_RESOLVE_FAIL", "BASE_ZERO",
                   (InpLotMode == LOT_MODE_AUTO ? "AUTO" : "MANUAL"),
                   "entry=" + DoubleToString(entry, gDigits),
                   "sl=" + DoubleToString(sl, gDigits));
      return 0.0; // abort chain — no lot, no trade
   }

   //── Layer 2: Loss smoothening ─────────────────────────────────────
   double smooth = LossSmoothLotMultiplierEx();
   lot *= smooth;
   if(smooth < 1.00)
      PushDiag("📉 E7: LossSmooth ×" + DoubleToString(smooth, 2)
               + " (losses=" + IntegerToString(gConsecLosses) + ") → lot=" + DoubleToString(lot, 4));

   //── Layer 3: Portfolio rank multiplier ───────────────────────────
   double portMult = CalcPortfolioRankMultiplier();
   lot *= portMult;
   if(portMult < 1.00)
      PushDiag("📊 E7: Portfolio ×" + DoubleToString(portMult, 2) + " → lot=" + DoubleToString(lot, 4));

   //── Layer 4: Regime lot multiplier ───────────────────────────────
   // RegimeLotMultiplier() defined in Engine 11 (Part 5), available at link time
   double regMult = RegimeLotMultiplier();
   lot *= regMult;
   if(regMult != 1.00)
      PushDiag("🌊 E7: Regime[" + gRegime.label + "] ×" + DoubleToString(regMult, 2)
               + " → lot=" + DoubleToString(lot, 4));

   //── Layer 5: Symbol preset ────────────────────────────────────────
   double presetMult = SymbolPresetRiskMultiplier();
   lot *= presetMult;
   if(presetMult != 1.00)
      PushDiag("🎯 E7: Preset ×" + DoubleToString(presetMult, 2) + " → lot=" + DoubleToString(lot, 4));

   //── Layer 6: Clamp + normalize ───────────────────────────────────
   lot = ClampModeLot(lot);
   lot = NormalizeLotSafe(lot); // floor to lotStep, clamp to [min, max]

   // Final validity gate: must meet broker minimum
   if(lot < gMinLot)
   {
      PushDiag("⚠️ E7: Final lot " + DoubleToString(lot, 4)
               + " < minLot " + DoubleToString(gMinLot, 4) + " → trade aborted");
      JournalWrite("LOT_RESOLVE_FAIL", "BELOW_MIN",
                   "lot=" + DoubleToString(lot, 4),
                   "min=" + DoubleToString(gMinLot, 4));
      return 0.0;
   }

   return lot;
}

//════════════════════════════════════════════════════════════════════
//  §7.4 — STOP LOSS CALCULATION
//  Moderate: fractal swing anchor ± ATR × multiplier (larger wins)
//  Scalp:    randomized ATR range [SLATRMin, SLATRMax] (anti-detection)
//  Guard:    SL forced to be at least SYMBOL_TRADE_STOPS_LEVEL from price
//════════════════════════════════════════════════════════════════════

double CalcSL(ENUM_BIAS bias, double price, double atrVal)
{
   if(atrVal <= 0.0) atrVal = GetATR(IDX_M5, 1); // fallback re-read
   double sl        = 0.0;
   double minStop   = gMinStopLevel; // pre-cached: SYMBOL_TRADE_STOPS_LEVEL × Point

   if(InpMode == BOT_MODE_HFT || InpMode == BOT_MODE_HFT_PURE)
   {
      // HFT: tight ATR-based SL with hard spread floor (3× spread minimum).
      // gRt_HFTSLatrMult is set by ApplySubMode() — 0.20–0.40 typical.
      double spread   = SymbolInfoDouble(gSymbol, SYMBOL_ASK) - SymbolInfoDouble(gSymbol, SYMBOL_BID);
      double slDist   = MathMax(atrVal * gRt_HFTSLatrMult, spread * 3.0);
      sl = (bias == BIAS_BULL) ? (price - slDist) : (price + slDist);
   }
   else if(InpMode == BOT_MODE_MODERATE)
   {
      if(bias == BIAS_BULL)
      {
         // Use fractal swing low as primary SL anchor
         double swingLow  = DetectSwingLow(IDX_M5, InpSwingLookbackBars);
         double slBySwing = swingLow - atrVal * 0.08;          // small ATR buffer below swing
         double slByATR   = price - atrVal * InpModerateSLATR; // minimum ATR distance
         // Take the more conservative (further from price) of the two
         sl = MathMin(slBySwing, slByATR);
      }
      else // BIAS_BEAR
      {
         double swingHigh = DetectSwingHigh(IDX_M5, InpSwingLookbackBars);
         double slBySwing = swingHigh + atrVal * 0.08;
         double slByATR   = price + atrVal * InpModerateSLATR;
         sl = MathMax(slBySwing, slByATR); // more conservative = further from price
      }
   }
   else // BOT_MODE_SCALPING — randomized ATR range (anti-HFT pattern detection)
   {
      // Randomize SL distance within [SLATRMin, SLATRMax]
      double range    = InpScalpSLATRMax - InpScalpSLATRMin;
      double randFrac = InpScalpSLATRMin + (MathRand() / 32767.0) * range;
      double slDist   = atrVal * randFrac;
      sl = (bias == BIAS_BULL) ? (price - slDist) : (price + slDist);
   }

   //── Broker stop level guard: enforce minimum distance from current price ──
   // SL must be >= SYMBOL_TRADE_STOPS_LEVEL away (broker requirement)
   // We add 10% buffer to avoid borderline rejections (Error 130)
   double requiredDist = minStop * 1.10;

   if(bias == BIAS_BULL)
   {
      // BUY: SL must be BELOW price
      if(price - sl < requiredDist)
      {
         sl = NormalizePrice(price - requiredDist);
         PushDiag("🔧 E7: CalcSL — BUY SL adjusted to meet stops level: SL=" + DoubleToString(sl, gDigits));
      }
   }
   else
   {
      // SELL: SL must be ABOVE price
      if(sl - price < requiredDist)
      {
         sl = NormalizePrice(price + requiredDist);
         PushDiag("🔧 E7: CalcSL — SELL SL adjusted to meet stops level: SL=" + DoubleToString(sl, gDigits));
      }
   }

   return NormalizePrice(sl);
}

//════════════════════════════════════════════════════════════════════
//  §7.5 — TIERED TP CALCULATION
//  TP1 (30%) and TP2 (40%) are VIRTUAL — managed internally by E8.
//  TP3 (30%) is the ONLY level sent to broker as hard order TP.
//  This separation is the fix for the Analysis 2.docx "TP1 hard
//  target conflict" bug — TP1/TP2 at broker would cause premature
//  position closure, skipping the managed partial close logic.
//════════════════════════════════════════════════════════════════════

TieredTP CalcTieredTP(ENUM_BIAS bias, double entry, double sl, double atrVal)
{
   TieredTP tp;
   ZeroMemory(tp);  // explicit zero-init — suppresses MetaEditor uninitialized-variable warning
   double riskDist = MathAbs(entry - sl);
   int    dir      = (bias == BIAS_BULL) ? 1 : -1; // direction multiplier

   if(riskDist <= 0.0)
   {
      // Degenerate SL placement — return zero TP struct
      PushDiag("⚠️ E7: CalcTieredTP — riskDist=0, cannot compute TP levels");
      return tp;
   }

   if(InpMode == BOT_MODE_HFT || InpMode == BOT_MODE_HFT_PURE)
   {
      // HFT: R-multiples driven by gRt_HFTTPr1/gRt_HFTTPr2 (set by ApplySubMode).
      // TP1 = fast grab (40% close), TP2 = continuation (40% close), TP3 = runner (20% hard).
      // Default OrderFlowSniper: tp1R=0.40, tp2R=0.80, tp3R=1.20.
      tp.tp1         = NormalizePrice(entry + dir * riskDist * gRt_HFTTPr1);
      tp.tp2         = NormalizePrice(entry + dir * riskDist * gRt_HFTTPr2);
      tp.tp3         = NormalizePrice(entry + dir * riskDist * (gRt_HFTTPr2 + 0.40));
      tp.tp1VolPct   = 0.40;
      tp.tp2VolPct   = 0.40;
      tp.tp3VolPct   = 0.20;
      tp.tslStep     = atrVal * 0.15;  // tight 0.15× ATR trail for HFT
      tp.isScalpMode = true;           // enables tick-level management
      tp.scalpOnTick = InpScalpTSLOnTick;
      tp.softTP      = true;
      tp.softTPPrice = tp.tp1;
   }
   else if(InpMode == BOT_MODE_MODERATE)
   {
      // R-multiple targets from spec: 0.5R / 1.0R / 1.5R
      tp.tp1         = NormalizePrice(entry + dir * riskDist * InpModerateTP1R); // 0.50R virtual
      tp.tp2         = NormalizePrice(entry + dir * riskDist * InpModerateTP2R); // 1.00R virtual
      tp.tp3         = NormalizePrice(entry + dir * riskDist * InpModerateTP3R); // 1.50R hard
      tp.tp1VolPct   = 0.30; // close 30% at TP1
      tp.tp2VolPct   = 0.40; // close 40% at TP2
      tp.tp3VolPct   = 0.30; // remaining 30% via broker hard TP3
      tp.tslStep     = atrVal * InpModerateTSLATR; // 1.2× ATR trail step
      tp.isScalpMode = false;
      tp.scalpOnTick = false;
      tp.softTP      = false;
      tp.softTPPrice = 0.0;
   }
   else // BOT_MODE_SCALPING
   {
      // Scalp targets: compact 0.5R / 1.0R / 1.5R but TSL-managed
      tp.tp1         = NormalizePrice(entry + dir * riskDist * 0.50); // soft virtual 0.5R
      tp.tp2         = NormalizePrice(entry + dir * riskDist * 1.00); // soft virtual 1.0R
      tp.tp3         = NormalizePrice(entry + dir * riskDist * 1.50); // hard broker TP
      tp.tp1VolPct   = 0.30;
      tp.tp2VolPct   = 0.40;
      tp.tp3VolPct   = 0.30;
      tp.tslStep     = atrVal * InpScalpTSLATRFraction; // 0.35× ATR fractional step
      tp.isScalpMode = true;
      tp.scalpOnTick = InpScalpTSLOnTick;
      tp.softTP      = true;
      tp.softTPPrice = tp.tp1; // initial soft target = TP1
   }

   return tp;
}

//════════════════════════════════════════════════════════════════════
//  §7.6 — PARTIAL CLOSE ENGINE
//  Uses direct OrderSend (MqlTradeRequest) for full MT5 compatibility.
//  CTrade::PositionClose used for full close (more reliable).
//  Dust guard: never attempt close below gMinLot.
//  Residual guard: remaining volume after close must be >= gMinLot or 0.
//════════════════════════════════════════════════════════════════════

//--- Partial close: close a specific volume of an open position
bool PartialCloseVolumeManaged(ulong ticket, double closeVol, string reason)
{
   if(!PositionSelectByTicket(ticket))
   {
      PushDiag("⚠️ E7: PartialClose — ticket " + IntegerToString(ticket) + " not found at broker");
      return false;
   }

   double curVol  = PositionGetDouble(POSITION_VOLUME);
   long   posType = PositionGetInteger(POSITION_TYPE);

   // Normalize and cap closeVol to current remaining volume
   closeVol = NormalizeLotSafe(MathMin(closeVol, curVol));

   // Dust guard: minimum lot check on close volume
   if(closeVol < gMinLot)
   {
      PushDiag("⚠️ E7: PartialClose DUST GUARD — closeVol "
               + DoubleToString(closeVol, 4) + " < minLot " + DoubleToString(gMinLot, 4) + " → skipped");
      return false;
   }

   // Residual guard: remaining volume must be >= gMinLot OR exactly zero
   double residual = NormalizeLotSafe(curVol - closeVol);
   if(residual > 0.0 && residual < gMinLot)
   {
      // Residual would be a dust fragment — upgrade to full close
      closeVol = NormalizeLotSafe(curVol);
      PushDiag("🔧 E7: PartialClose dust residual → upgraded to full close (" + DoubleToString(closeVol, 4) + " lot)");
   }

   // Market-state guard (v6.5): if the session is shut, do NOT fire a blind
   // close that will just bounce with rc=10018. Queue ONE retry and bail —
   // this is what kills the rollover/weekend retry storm.
   if(!IsMarketTradeable())
   {
      if(!RetryQueuedFor(ticket, 2))
      {
         for(int i = 0; i < 64; i++)
         {
            if(gRetry[i].used) continue;
            gRetry[i].used     = true;
            gRetry[i].kind     = 2;
            gRetry[i].ticket   = ticket;
            gRetry[i].volume   = closeVol;
            gRetry[i].attempts = 0;                       // not a real attempt — market was closed
            gRetry[i].nextTry  = TimeCurrent() + RETRY_INTERVAL_SEC;
            gRetry[i].note     = "PartClose:" + reason + " (deferred — market closed)";
            break;
         }
      }
      return false;
   }

   // Build trade request for counter-order partial close
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.position  = ticket;
   req.symbol    = gSymbol;
   req.volume    = closeVol;
   // Counter-order: SELL to close BUY, BUY to close SELL
   req.type      = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.price     = (req.type == ORDER_TYPE_SELL)
                   ? SymbolInfoDouble(gSymbol, SYMBOL_BID)
                   : SymbolInfoDouble(gSymbol, SYMBOL_ASK);
   req.deviation  = (ulong)InpMaxSlippagePoints;
   req.magic      = (ulong)InpMagic;
   req.comment    = "SKP-PC-" + reason;
   req.type_filling = ORDER_FILLING_IOC; // IOC allows partial fills gracefully

   bool ok = OrderSend(req, res);
   int  rc = (int)res.retcode;

   PushExecTelemetry("PARTIAL_CLOSE",
                     (posType == POSITION_TYPE_BUY ? "SELL" : "BUY"),
                     ok, rc,
                     reason + " vol=" + DoubleToString(closeVol, 4));

   if(ok || rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED)
   {
      JournalWrite("PARTIAL_CLOSE",
                   IntegerToString(ticket),
                   DoubleToString(closeVol, 4),
                   reason,
                   DoubleToString(GetPositionFloatPL(ticket), 2));
      PushDiag("✅ E7: Partial close " + DoubleToString(closeVol, 4) + " lot — " + reason);
      return true;
   }
   else
   {
      // Queue for OnTimer retry
      for(int i = 0; i < 64; i++)
      {
         if(gRetry[i].used) continue;
         gRetry[i].used     = true;
         gRetry[i].kind     = 2; // kind=2: partial close retry
         gRetry[i].ticket   = ticket;
         gRetry[i].volume   = closeVol;
         gRetry[i].attempts = 0;
         gRetry[i].nextTry  = TimeCurrent() + RETRY_INTERVAL_SEC;
         gRetry[i].note     = "PartClose:" + reason + " rc=" + RetcodeStr(rc);
         break;
      }
      PushDiag("⚠️ E7: PartialClose FAILED rc=" + RetcodeStr(rc) + " — queued for retry");
      return false;
   }
}

//--- Full close: close entire remaining volume (spike exit / hostile exit)
bool PartialCloseVolumeManagedFull(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket))
   {
      PushDiag("⚠️ E7: FullClose — ticket " + IntegerToString(ticket) + " not found");
      return false;
   }

   double curVol = NormalizeLotSafe(PositionGetDouble(POSITION_VOLUME));
   if(curVol < gMinLot)
   {
      PushDiag("⚠️ E7: FullClose DUST GUARD — curVol " + DoubleToString(curVol, 4) + " < minLot");
      return false;
   }

   // Market-state guard (v6.5): defer instead of spamming a closed session.
   if(!IsMarketTradeable())
   {
      if(!RetryQueuedFor(ticket, 3))
      {
         for(int i = 0; i < 64; i++)
         {
            if(gRetry[i].used) continue;
            gRetry[i].used     = true;
            gRetry[i].kind     = 3;
            gRetry[i].ticket   = ticket;
            gRetry[i].volume   = curVol;
            gRetry[i].attempts = 0;
            gRetry[i].nextTry  = TimeCurrent() + RETRY_INTERVAL_SEC;
            gRetry[i].note     = "FullClose:" + reason + " (deferred — market closed)";
            break;
         }
      }
      return false;
   }

   gTrade.SetExpertMagicNumber((ulong)InpMagic);
   gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   bool ok = gTrade.PositionClose(ticket);
   int  rc = (int)gTrade.ResultRetcode();

   PushExecTelemetry("FULL_CLOSE", "EXIT", ok, rc, reason + " vol=" + DoubleToString(curVol, 4));

   if(ok)
   {
      JournalWrite("FULL_CLOSE", IntegerToString(ticket), DoubleToString(curVol, 4), reason);
      PushDiag("✅ E7: Full close ticket=" + IntegerToString(ticket) + " — " + reason);
      return true;
   }
   else
   {
      // Queue panic-close retry (kind=3) for OnTimer
      for(int i = 0; i < 64; i++)
      {
         if(gRetry[i].used) continue;
         gRetry[i].used     = true;
         gRetry[i].kind     = 3; // kind=3: panic close
         gRetry[i].ticket   = ticket;
         gRetry[i].volume   = curVol;
         gRetry[i].attempts = 0;
         gRetry[i].nextTry  = TimeCurrent() + RETRY_INTERVAL_SEC;
         gRetry[i].note     = "FullClose:" + reason + " rc=" + RetcodeStr(rc);
         break;
      }
      PushDiag("🚨 E7: FullClose FAILED rc=" + RetcodeStr(rc) + " — queued panic retry");
      return false;
   }
}

//════════════════════════════════════════════════════════════════════
//  §7.7 — POSITION MODIFY WITH RATE-LIMIT AND RETRY QUEUE
//  Rate-limit guard: |newSL − curSL| must be >= tslStep × 0.50
//  This prevents broker spam and Error 130 on micro-tick movements
//  (Analysis 2.docx §TSL server spam fix).
//════════════════════════════════════════════════════════════════════

bool ModifySLTP(ulong ticket, double newSL, double newTP,
                string why, bool bypassRateLimit = false)
{
   if(!PositionSelectByTicket(ticket)) return false;

   double curSL       = PositionGetDouble(POSITION_SL);
   double curTP       = PositionGetDouble(POSITION_TP);
   ENUM_ORDER_TYPE side = GetPositionSide(ticket);

   //── Rate-limit: skip micro-adjustments ──────────────────────────
   if(!bypassRateLimit)
   {
      int recIdx = FindRecordByTicket(ticket);
      double tslStep = 0.0;
      if(recIdx >= 0)
         tslStep = gRec[recIdx].tslStep;
      else
         tslStep = GetATR(IDX_M5, 1) * InpModerateTSLATR;

      // Only modify if move is >= 50% of TSL step (Error 130 prevention)
      if(tslStep > 0.0 && MathAbs(newSL - curSL) < tslStep * 0.50)
         return true; // micro-move — silently skip, not an error
   }

   //── Directional guard: SL for BUY moves UP only, SELL moves DOWN only ──
   // A SL that moves in the wrong direction would widen stop — reject
   if(side == ORDER_TYPE_BUY  && newSL <= curSL && curSL > 0.0) return true;
   if(side == ORDER_TYPE_SELL && newSL >= curSL && curSL > 0.0) return true;

   //── Broker minimum stop level guard ─────────────────────────────
   double livePrice = (side == ORDER_TYPE_BUY) ? GetBid() : GetAsk();
   double requiredDist = gMinStopLevel * 1.10;
   if(side == ORDER_TYPE_BUY  && livePrice - newSL < requiredDist)
      newSL = NormalizePrice(livePrice - requiredDist);
   if(side == ORDER_TYPE_SELL && newSL - livePrice < requiredDist)
      newSL = NormalizePrice(livePrice + requiredDist);

   // Normalize prices before sending
   newSL = NormalizePrice(newSL);
   newTP = NormalizePrice(newTP);

   gTrade.SetExpertMagicNumber((ulong)InpMagic);
   gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   bool ok = gTrade.PositionModify(ticket, newSL, newTP);
   int  rc = (int)gTrade.ResultRetcode();

   PushExecTelemetry("MODIFY_SL",
                     (side == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                     ok, rc,
                     why + " newSL=" + DoubleToString(newSL, gDigits));

   if(ok)
   {
      // Sync the record immediately so next rate-limit check uses fresh value
      int idx = FindRecordByTicket(ticket);
      if(idx >= 0) gRec[idx].stopLoss = newSL;
      PushDiag("✅ E7: SL→" + DoubleToString(newSL, gDigits) + " — " + why);
   }
   else
   {
      // Push to gModRecover[] queue for OnTimer retry
      for(int i = 0; i < 32; i++)
      {
         if(gModRecover[i].active) continue;
         gModRecover[i].active  = true;
         gModRecover[i].ticket  = ticket;
         gModRecover[i].sl      = newSL;
         gModRecover[i].tp      = newTP;
         gModRecover[i].tries   = 0;
         gModRecover[i].nextTry = TimeCurrent() + RETRY_INTERVAL_SEC;
         gModRecover[i].why     = why + " rc=" + RetcodeStr(rc);
         break;
      }
      PushDiag("⚠️ E7: ModifySL FAILED rc=" + RetcodeStr(rc) + " — queued ModRecover");
   }

   return ok;
}

//════════════════════════════════════════════════════════════════════
//  §7.8 — TELEGRAM ENTRY MESSAGE BUILDER
//  Full institutional-grade entry alert with all metadata fields.
//  String is ONLY passed to TGEnqueue() — never sent directly.
//  TGEnqueue defined in Engine (Telegram) → Part 6.
//════════════════════════════════════════════════════════════════════

string BuildEntryMessageEx(ENUM_BIAS bias,
                           double entry, double sl,
                           double tp1,   double tp2, double tp3,
                           double lot)
{
   string sideEmoji = (bias == BIAS_BULL) ? "🟢" : "🔴";
   string side      = (bias == BIAS_BULL) ? "BUY"   : "SELL";
   string modeStr   = (InpMode == BOT_MODE_SCALPING) ? "SCALPER 🔥" : "MODERATE 🏛️";
   string lotModeStr= (InpLotMode == LOT_MODE_AUTO) ? "AUTO" : "MANUAL";
   string riskStr   = (InpLotMode == LOT_MODE_AUTO)
                      ? DoubleToString(InpRiskPercent, 2) + "%"
                      : "fixed";

   // Score display
   string bullScore = IntegerToString(gScoreSnap.bull);
   string bearScore = IntegerToString(gScoreSnap.bear);
   string decision  = gScoreSnap.decision;

   // Volume momentum state
   string volStr;
   if(InpUseVolumeMomentum)
   {
      bool volOK = (bias == BIAS_BULL) ? gVolMom.bullConfirmed : gVolMom.bearConfirmed;
      volStr = volOK ? "✅ CONFIRMED" : "⚠️ WEAK";
   }
   else volStr = "— (disabled)";

   // Pattern name
   string patStr = (gPattern.name != "") ? gPattern.name : "None";

   // Regime
   string regStr = gRegime.label;

   // Consecutive loss context
   string lossCtx = (gConsecLosses > 0)
                    ? " | ⚠️ Losses: " + IntegerToString(gConsecLosses)
                    : "";

   // Risk distance and R-value context
   double riskDist = MathAbs(entry - sl);
   double riskPts  = SafeDiv(riskDist, gPoint);

   string msg =
      "══════════════════════════\n"
      + sideEmoji + " NEW " + side + " EXECUTION\n"
      + "──────────────────────────\n"
      + "📌 Symbol:  " + gSymbol + "\n"
      + "📊 Mode:    " + modeStr + "\n"
      + "🎯 Lot:     " + DoubleToString(lot, 2)
      +    " [" + lotModeStr + " " + riskStr + "]\n"
      + "📐 Risk:    " + DoubleToString(riskPts, 1) + " pts"
      + " (" + DoubleToString(riskDist, gDigits) + ")\n"
      + "──────────────────────────\n"
      + "📥 Entry:   " + DoubleToString(entry, gDigits) + "\n"
      + "🛑 SL:      " + DoubleToString(sl,    gDigits) + "\n"
      + "1️⃣ TP1:    " + DoubleToString(tp1,   gDigits) + " (virtual 30%)\n"
      + "2️⃣ TP2:    " + DoubleToString(tp2,   gDigits) + " (virtual 40%)\n"
      + "3️⃣ TP3:    " + DoubleToString(tp3,   gDigits) + " (hard broker)\n"
      + "──────────────────────────\n"
      + "📈 Score:   BULL " + bullScore + " | BEAR " + bearScore
      +    " [" + decision + "]\n"
      + "📊 Volume:  " + volStr + "\n"
      + "🎨 Pattern: " + patStr + "\n"
      + "🌍 Regime:  " + regStr + lossCtx + "\n"
      + "💬 Reason:  " + gSignal.liveReason + "\n"
      + "⏰ " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\n"
      + "══════════════════════════";

   return msg;
}

//════════════════════════════════════════════════════════════════════
//  §7.9 — MAIN ORDER PLACEMENT — PlaceTrade()
//  Moderate path: CTrade.Buy/Sell market order, hard TP = TP3 only.
//  Scalp path:    CTrade.BuyLimit/SellLimit at confluence offset,
//                 expiry = InpPendingExpiryMinutes × 60 seconds.
//  Both paths register the trade/plan and queue a Telegram alert.
//════════════════════════════════════════════════════════════════════

bool PlaceTrade(ENUM_BIAS bias)
{
   if(bias == BIAS_NONE) return false;

   //── One-exposure guard (fast path before expensive calls) ────────
   if(InpOneExposurePerSymbol && HasExposureOnSymbol())
   {
      PushDiag("🚫 E7: PlaceTrade blocked — already exposed on " + gSymbol);
      return false;
   }

   //── Get live execution price ──────────────────────────────────────
   double ask   = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   double price = (bias == BIAS_BULL) ? ask : bid;

   //── Validate ATR (required for SL/lot sizing) ─────────────────────
   double atrVal = GetATR(IDX_M5, 1);
   if(atrVal <= 0.0)
   {
      PushDiag("⚠️ E7: PlaceTrade — ATR zero/invalid, cannot size position");
      JournalWrite("PLACE_FAIL", "ATR_INVALID", gSymbol, DoubleToString(price, gDigits));
      return false;
   }

   //── Calculate SL ──────────────────────────────────────────────────
   double sl = CalcSL(bias, price, atrVal);

   //── Calculate tiered TP levels (TP3 = broker hard TP) ─────────────
   TieredTP tp = CalcTieredTP(bias, price, sl, atrVal);
   if(tp.tp3 == 0.0)
   {
      PushDiag("⚠️ E7: PlaceTrade — TP3 degenerate (riskDist=0)");
      return false;
   }

   //── Resolve lot through all 6 layers ──────────────────────────────
   double lot = ResolveModeLotSize(price, sl);
   if(lot <= 0.0)
   {
      PushDiag("🚫 E7: PlaceTrade — lot resolution returned 0 → trade aborted");
      return false;
   }

   //── Configure trade object ────────────────────────────────────────
   gTrade.SetExpertMagicNumber((ulong)InpMagic);
   gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   gTrade.SetTypeFilling(ORDER_FILLING_FOK); // broker may override with IOC

   bool  ok  = false;
   ulong tkt = 0;

   //══════════════════════════════════════════════════════════════════
   //  MODERATE MODE: Market order — CTrade.Buy/Sell
   //  TP3 sent to broker as hard order TP. TP1/TP2 NOT sent.
   //══════════════════════════════════════════════════════════════════
   if(InpMode == BOT_MODE_MODERATE)
   {
      if(bias == BIAS_BULL)
         ok = gTrade.Buy (lot, gSymbol, 0.0 /*market*/, sl, tp.tp3, "SKP-MOD-BUY");
      else
         ok = gTrade.Sell(lot, gSymbol, 0.0 /*market*/, sl, tp.tp3, "SKP-MOD-SEL");

      int rc = (int)gTrade.ResultRetcode();
      PushExecTelemetry("ENTRY_MARKET",
                        (bias == BIAS_BULL ? "BUY" : "SELL"),
                        ok, rc,
                        "lot=" + DoubleToString(lot, 4)
                        + " SL=" + DoubleToString(sl, gDigits)
                        + " TP3=" + DoubleToString(tp.tp3, gDigits));

      if(ok)
      {
         // Re-read actual fill from broker (requote can shift entry price)
         // After CTrade.Buy, select the position by symbol
         if(PositionSelect(gSymbol))
         {
            tkt = (ulong)PositionGetInteger(POSITION_TICKET);
            double actualEntry = PositionGetDouble(POSITION_PRICE_OPEN);
            double actualSL    = PositionGetDouble(POSITION_SL);

            // Recompute TP from actual entry in case of requote drift
            TieredTP tpActual  = CalcTieredTP(bias, actualEntry, actualSL, atrVal);

            // Register in tracking array
            RegisterTradeRecord(tkt,
               (bias == BIAS_BULL ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),
               actualEntry, actualSL,
               tpActual.tp1, tpActual.tp2, tpActual.tp3,
               lot, atrVal, gSignal.liveReason);

            // Update stats
            gLastSignalTime = TimeCurrent();
            gLastEntryTime  = TimeCurrent();
            gPerf.totalTrades++;
            gPerf.modeTrades[0]++;  // mode 0 = MODERATE

            // Journal entry
            JournalWrite("ENTRY_MARKET",
               (bias == BIAS_BULL ? "BUY" : "SELL"),
               DoubleToString(actualEntry, gDigits),
               DoubleToString(actualSL,    gDigits),
               DoubleToString(tpActual.tp3, gDigits),
               DoubleToString(lot, 4));

            // Telegram (async via queue — NOT sent directly here)
            string tgMsg = BuildEntryMessageEx(bias, actualEntry, actualSL,
                              tpActual.tp1, tpActual.tp2, tpActual.tp3, lot);
            TGEnqueue(MSG_ENTRY, tgMsg, true /* priority */);

            PushDiag("✅ E7: MARKET " + (bias==BIAS_BULL?"BUY":"SELL")
                     + " ticket=" + IntegerToString(tkt)
                     + " @" + DoubleToString(actualEntry, gDigits)
                     + " lot=" + DoubleToString(lot, 2));
         }
         else
         {
            // Position select failed after successful send — edge case
            // Broker accepted the order but we can't read the ticket
            PushDiag("⚠️ E7: Market order sent OK but PositionSelect failed — SyncRecords will recover");
         }
      }
      else
      {
         PushDiag("🚫 E7: Market " + (bias==BIAS_BULL?"BUY":"SELL")
                  + " FAILED rc=" + RetcodeStr(rc)
                  + " lot=" + DoubleToString(lot, 2));
         JournalWrite("ENTRY_FAIL",
            (bias==BIAS_BULL?"BUY":"SELL"), RetcodeStr(rc), DoubleToString(lot, 4));
      }
   }

   //══════════════════════════════════════════════════════════════════
   //  SCALPING MODE: Pending limit order — CTrade.BuyLimit/SellLimit
   //  Placed at confluence zone minus offset (bias-aware).
   //  TP3 sent as hard broker TP. TP1/TP2 = virtual managed internally.
   //══════════════════════════════════════════════════════════════════
   else // BOT_MODE_SCALPING
   {
      // Calculate limit price offset from current market price
      double offsetDist  = InpPendingOffsetPoints * gPoint;
      double limitPrice  = 0.0;

      if(bias == BIAS_BULL)
         limitPrice = NormalizePrice(bid - offsetDist); // BuyLimit below bid
      else
         limitPrice = NormalizePrice(ask + offsetDist); // SellLimit above ask

      // Recalculate SL and TP from the actual limit price (not market price)
      double slFromLimit  = CalcSL(bias, limitPrice, atrVal);
      TieredTP tpFromLimit = CalcTieredTP(bias, limitPrice, slFromLimit, atrVal);

      // Lot size from limit price context
      double limitLot = ResolveModeLotSize(limitPrice, slFromLimit);
      if(limitLot <= 0.0)
      {
         PushDiag("🚫 E7: Scalp limit lot=0 → abort");
         return false;
      }

      // Expiry time for the pending order
      datetime expiry = TimeCurrent() + (datetime)(InpPendingExpiryMinutes * 60);

      gTrade.SetExpertMagicNumber((ulong)InpMagic);
      gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);

      if(bias == BIAS_BULL)
         ok = gTrade.BuyLimit(limitLot, limitPrice, gSymbol,
                              slFromLimit, tpFromLimit.tp3,
                              ORDER_TIME_SPECIFIED, expiry, "SKP-SCALP-BL");
      else
         ok = gTrade.SellLimit(limitLot, limitPrice, gSymbol,
                               slFromLimit, tpFromLimit.tp3,
                               ORDER_TIME_SPECIFIED, expiry, "SKP-SCALP-SL");

      int rc = (int)gTrade.ResultRetcode();
      PushExecTelemetry("ENTRY_PENDING",
                        (bias == BIAS_BULL ? "BUYLIMIT" : "SELLLIMIT"),
                        ok, rc,
                        "limit=" + DoubleToString(limitPrice, gDigits)
                        + " SL=" + DoubleToString(slFromLimit, gDigits)
                        + " TP3=" + DoubleToString(tpFromLimit.tp3, gDigits));

      if(ok)
      {
         ulong ordTkt = gTrade.ResultOrder();
         RegisterPendingPlan(ordTkt, bias, limitPrice, slFromLimit,
                             tpFromLimit.tp1, tpFromLimit.tp2, tpFromLimit.tp3,
                             limitLot, atrVal);

         gLastSignalTime = TimeCurrent();
         gLastEntryTime  = TimeCurrent();
         gPerf.modeTrades[1]++; // mode 1 = SCALPING

         // Journal
         JournalWrite("ENTRY_PENDING",
            (bias == BIAS_BULL ? "BUYLIMIT" : "SELLLIMIT"),
            DoubleToString(limitPrice,    gDigits),
            DoubleToString(slFromLimit,   gDigits),
            DoubleToString(tpFromLimit.tp3, gDigits),
            DoubleToString(limitLot, 4));

         // Telegram — queued, never direct (Analysis 2.docx fix)
         string tgMsg = "📋 PENDING " +
                        BuildEntryMessageEx(bias, limitPrice, slFromLimit,
                           tpFromLimit.tp1, tpFromLimit.tp2, tpFromLimit.tp3, limitLot);
         TGEnqueue(MSG_PENDING, tgMsg, false);

         PushDiag("📋 E7: SCALP PENDING " + (bias==BIAS_BULL?"BUYLIMIT":"SELLLIMIT")
                  + " @" + DoubleToString(limitPrice, gDigits)
                  + " lot=" + DoubleToString(limitLot, 2)
                  + " exp=" + TimeToString(expiry, TIME_SECONDS)
                  + " ticket=" + IntegerToString(ordTkt));
      }
      else
      {
         PushDiag("🚫 E7: Scalp pending FAILED rc=" + RetcodeStr(rc));
         JournalWrite("ENTRY_FAIL",
            (bias==BIAS_BULL?"BUYLIMIT":"SELLLIMIT"), RetcodeStr(rc), DoubleToString(limitLot, 4));
      }
   }

   return ok;
}

//════════════════════════════════════════════════════════════════════
//  §7.10 — STALE PENDING ORDER CLEANUP
//  Called exclusively from OnTimer (never from OnTick).
//  Iterates gPlan[] and cancels scalp orders that have exceeded
//  InpScalpPendingMaxAgeSec. Queues retry if OrderDelete fails.
//════════════════════════════════════════════════════════════════════

void CancelStalePendingOrders()
{
   for(int i = 0; i < 20; i++)
   {
      if(!gPlan[i].active) continue;
      if(gPlan[i].mode != BOT_MODE_SCALPING) continue; // only scalp pending

      long ageSeconds = (long)(TimeCurrent() - gPlan[i].createdAt);
      if(ageSeconds < InpScalpPendingMaxAgeSec) continue; // not yet stale

      // Verify order still exists at broker before trying to delete
      ulong ord = gPlan[i].orderTicket;
      if(!PendingOrderExists(ord))
      {
         // Order already filled or cancelled externally — just clean up our record
         PushDiag("🔧 E7: Stale pending order=" + IntegerToString(ord) + " already gone at broker — clearing plan");
         ClearPendingPlan(i);
         continue;
      }

      // Attempt deletion
      gTrade.SetExpertMagicNumber((ulong)InpMagic);
      bool ok = gTrade.OrderDelete(ord);
      int  rc = (int)gTrade.ResultRetcode();

      PushExecTelemetry("CANCEL_PENDING", "DELETE", ok, rc,
                        "age=" + IntegerToString(ageSeconds) + "s"
                        + " max=" + IntegerToString(InpScalpPendingMaxAgeSec) + "s");

      if(ok)
      {
         JournalWrite("SCALP_PENDING_CANCEL_AGE",
            IntegerToString(ord),
            "age=" + IntegerToString(ageSeconds) + "s",
            "threshold=" + IntegerToString(InpScalpPendingMaxAgeSec) + "s");
         PushDiag("🗑️ E7: Stale pending deleted — order=" + IntegerToString(ord)
                  + " age=" + IntegerToString(ageSeconds) + "s");
         ClearPendingPlan(i);
      }
      else
      {
         PushDiag("⚠️ E7: StaleDelete FAILED rc=" + RetcodeStr(rc)
                  + " order=" + IntegerToString(ord) + " — queuing retry");
         // Retry queue (kind=4: delete pending order)
         for(int r = 0; r < 64; r++)
         {
            if(gRetry[r].used) continue;
            gRetry[r].used     = true;
            gRetry[r].kind     = 4;
            gRetry[r].ticket   = ord;
            gRetry[r].volume   = 0.0;
            gRetry[r].attempts = 0;
            gRetry[r].nextTry  = TimeCurrent() + RETRY_INTERVAL_SEC;
            gRetry[r].note     = "StaleCancel rc=" + RetcodeStr(rc);
            break;
         }
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  §7.11 — TryNewEntry() — COMPLETE GUARDED ENTRY PIPELINE
//  19-step guard sequence that all must pass before PlaceTrade().
//  Returns true only if an order was actually placed.
//  STRICT step ordering — never reorder (downstream state depends on
//  earlier checks having already filtered their conditions).
//════════════════════════════════════════════════════════════════════

bool TryNewEntry()
{
   //── Step 1: Master bot-level gate ────────────────────────────────
   if(!InpEnableBot)
   {
      gSignal.blockReason = "❌ Bot disabled (InpEnableBot=false)";
      return false;
   }
   if(gBotPaused)
   {
      gSignal.blockReason = "⏸️ Bot paused (button or InpPauseByButtonAtStart)";
      return false;
   }
   if(gEmergencyHalt)
   {
      gSignal.blockReason = "🚨 Emergency halt — equity floor breached";
      return false;
   }

   //── Step 2: Safety vault lock (all 9 lock types) ─────────────────
   // CheckSafetyLockAdvanced() is lightweight (reads globals, no broker calls)
   ENUM_SAFETY_LOCK lockState = CheckSafetyLockAdvanced();
   if(lockState != LOCK_NONE)
   {
      // LOCK_GLOBAL_DD: blocks new entries but allows management
      // LOCK_EQUITY_FLOOR / LOCK_DAILY_LOSS: blocks everything
      gSignal.blockReason = "🔒 Safety lock: " + EnumToString(lockState);
      return false;
   }

   //── Step 3: News filter — hard block (−999 pts also applied in score) ──
   if(InpUseNewsFilter && gNews.active)
   {
      gSignal.blockReason  = "📰 News window active — entries paused";
      gSignal.newsBlocked  = true;
      return false;
   }

   //── Step 4: Spike detection block ────────────────────────────────
   if(InpBlockEntryOnSpike && gSpike.spikeDetected)
   {
      gSignal.blockReason  = "🚨 Spike: " + gSpike.reason;
      gSignal.spikeBlocked = true;
      return false;
   }

   //── Step 5: Loss streak tiered cooldown ──────────────────────────
   if(!LossCooldownOK())
   {
      long elapsed = (long)(TimeCurrent() - gLastEntryTime);
      long needed  = (long)LossCooldownSeconds();
      gSignal.blockReason = "⏱️ Loss cooldown: " + IntegerToString(needed - elapsed)
                           + "s remaining (losses=" + IntegerToString(gConsecLosses) + ")";
      return false;
   }

   //── Step 6: Signal cooldown (anti-churn time gate) ───────────────
   if(!SignalCooldownOK())
   {
      gSignal.blockReason = "⏱️ Signal cooldown — waiting " + IntegerToString(InpSignalCooldownSeconds) + "s";
      return false;
   }

   //── Step 7: Drawdown guard (blocks new entries, management continues)
   if(gSafetyLock == LOCK_GLOBAL_DD)
   {
      gSignal.blockReason = "🛡️ Global DD guard — no new entries (management continues)";
      return false;
   }

   //── Step 8: Daily loss sleep mode ────────────────────────────────
   if(gSafetyLock == LOCK_DAILY_LOSS)
   {
      gSignal.blockReason = "💤 Daily loss limit reached — sleep mode until session reset";
      return false;
   }

   //── Step 9: Macro divergence lock ────────────────────────────────
   if(gSafetyLock == LOCK_MACRO_DIVERGENCE || gSignal.macroDivergent)
   {
      gSignal.blockReason = "⛔ Macro divergence: H1 vs SMA800 conflict";
      gPerf.blockedMacro++;
      return false;
   }

   //── Step 10: Direction allow guards ──────────────────────────────
   ENUM_BIAS bias = gSignal.bias;
   if(bias == BIAS_NONE)
   {
      gSignal.blockReason = "⏳ No signal bias — pipeline returned NONE";
      return false;
   }
   // v6.3d: Use runtime toggle globals (gRtAllowBuy/gRtAllowSell) instead of frozen
   // input parameters — allows dashboard BUY/SELL buttons to actually change direction.
   if(bias == BIAS_BULL && !gRtAllowBuy)
   {
      gSignal.blockReason = "BUY direction disabled (dashboard toggle)";
      PushEAEvent("DirFilter","BLOCKED — BUY direction OFF");
      return false;
   }
   if(bias == BIAS_BEAR && !gRtAllowSell)
   {
      gSignal.blockReason = "SELL direction disabled (dashboard toggle)";
      PushEAEvent("DirFilter","BLOCKED — SELL direction OFF");
      return false;
   }

   //── Step 11: Dynamic score threshold gate ────────────────────────
   // Base minimum depends on mode; escalated by consecutive losses and regime
   int baseMin    = (InpMode == BOT_MODE_SCALPING) ? InpScoreMinScalper : InpScoreMinModerate;
   // Loss streak raises the bar (harder to enter during drawdown)
   int dynamicMin = baseMin + (gConsecLosses * InpLossStreakPenaltyStep);
   // Regime score adjustment (Engine 11): QUIET+5, NORMAL±0, EXPLOSIVE-3, HOSTILE+15
   dynamicMin    += RegimeScoreAdjustment();
   // Cap total penalty escalation to prevent infinite blocking
   dynamicMin     = (int)Clamp((double)dynamicMin, (double)baseMin, (double)(baseMin + 60));

   int score = (bias == BIAS_BULL) ? gScoreSnap.bull : gScoreSnap.bear;
   if(score < dynamicMin)
   {
      gSignal.blockReason = "📊 Score " + IntegerToString(score)
                           + " < dynamic min " + IntegerToString(dynamicMin)
                           + " (base=" + IntegerToString(baseMin)
                           + " lossPen=" + IntegerToString(gConsecLosses * InpLossStreakPenaltyStep)
                           + " regimePen=" + IntegerToString(RegimeScoreAdjustment()) + ")";
      gLastRejectLabel = gSignal.blockReason;
      return false;
   }

   //── Step 12: Broker sanity + blackout ────────────────────────────
   if(gBroker.blackoutActive)
   {
      gSignal.blockReason = "⏰ Manual blackout window active";
      return false;
   }
   if(gBroker.hostileNow)
   {
      gSignal.blockReason = "☠️ Broker hostile — " + gBroker.reason;
      return false;
   }

   //── Step 13: Dynamic spread gate ─────────────────────────────────
   double spreadNow = GetSpreadPoints();
   double atrVal    = GetATR(IDX_M5, 1);
   // Spread cap = ATR × factor × regime multiplier (wider in EXPLOSIVE)
   double spreadCap = (atrVal / gPoint) * InpSpreadATRFactor * RegimeSpreadMultiplier();

   if(spreadNow > spreadCap)
   {
      gSignal.blockReason  = "📡 Spread " + DoubleToString(spreadNow, 1)
                            + "pt > cap " + DoubleToString(spreadCap, 1) + "pt";
      gSignal.spreadBlocked = true;
      gPerf.blockedSpread++;
      gHighSpreadCount++;
      if(gHighSpreadCount >= 5) gSpreadPaused = true;
      return false;
   }
   else
   {
      // Clean spread tick — reset consecutive counter
      if(gHighSpreadCount > 0) gHighSpreadCount = 0;
      if(gSpreadPaused)        gSpreadPaused = false;
   }

   //── Step 14: One-exposure guard ──────────────────────────────────
   if(InpOneExposurePerSymbol && HasExposureOnSymbol())
   {
      gSignal.blockReason = "🔒 One-exposure guard: already open on " + gSymbol;
      return false;
   }

   //── Step 15: ADX confirmation (H1 gatekeeper — freshness guard) ──
   if(InpUseADXFilter && !ADXTrendConfirmed(IDX_H1))
   {
      gSignal.blockReason  = "📉 ADX H1 gatekeeper: trend insufficient";
      gSignal.adxBlocked   = true;
      gPerf.blockedADX++;
      return false;
   }

   //── Step 16: Regime-level scalp suppressor ────────────────────────
   if(InpMode == BOT_MODE_SCALPING && RegimeSuppressScalper())
   {
      gSignal.blockReason = "🌊 Regime [" + gRegime.label + "] suppresses scalp entries";
      return false;
   }

   //── Step 17: Volume momentum hard gate (scalp only, if required) ──
   if(InpMode == BOT_MODE_SCALPING && InpScalpRequireVolumeMom && InpUseVolumeMomentum)
   {
      bool volOK = (bias == BIAS_BULL) ? gVolMom.bullConfirmed : gVolMom.bearConfirmed;
      if(!volOK)
      {
         gSignal.blockReason = "📊 Scalp hard gate: volume momentum NOT confirmed ("
                              + gVolMom.label + ")";
         PushDiag("📊 Vol gate BLOCKED: " + gVolMom.label);
         return false;
      }
   }

   //── Step 18: Portfolio rank arbitration ───────────────────────────
   if(InpUsePortfolioEngine)
   {
      int myRank = -1;
      for(int i = 0; i < 32; i++)
      {
         if(!gPortCand[i].valid)            continue;
         if(gPortCand[i].symbol != gSymbol) continue;
         myRank = gPortCand[i].rank;
         break;
      }

      // Rank too low for trading
      if(myRank > 0 && myRank > InpPortfolioMaxRankToTrade)
      {
         gSignal.blockReason = "📊 Portfolio rank " + IntegerToString(myRank)
                              + " > max allowed " + IntegerToString(InpPortfolioMaxRankToTrade);
         return false;
      }

      // Score gap check: top symbol dominates too much
      if(gPortCand[0].valid && myRank > 1)
      {
         int topScore = gPortCand[0].finalScore;
         int scoreGap = topScore - score;
         if(scoreGap > InpPortfolioScoreGapBlock)
         {
            gSignal.blockReason = "📊 Portfolio: score gap " + IntegerToString(scoreGap)
                                 + " pts (top=" + IntegerToString(topScore)
                                 + " mine=" + IntegerToString(score)
                                 + " max gap=" + IntegerToString(InpPortfolioScoreGapBlock) + ")";
            return false;
         }
      }
   }

   //── Step 19: Session filter (London/NY only) ─────────────────────
   if(InpUseSessionFilter && !IsLondonNYSession())
   {
      gSignal.blockReason  = "🕐 Outside London+NY session hours";
      gSignal.sessionBlocked = true;
      gPerf.blockedSession++;
      return false;
   }

   //── Step 20: ATR minimum entry size guard ─────────────────────────
   // Prevents entries in micro-volatility where SL/spread eat R value
   if(atrVal < (double)InpMinATRForEntry * gPoint)
   {
      gSignal.blockReason = "📐 ATR " + DoubleToString(atrVal/gPoint, 1)
                           + "pt < minimum " + IntegerToString(InpMinATRForEntry) + "pt";
      return false;
   }

   //── ALL GUARDS PASSED — Execute PlaceTrade() ─────────────────────
   gSignal.blockReason  = ""; // clear any residual block reason
   gSignal.staleBlocked = false;

   PushDiag("🚀 E7: ALL guards passed → PlaceTrade("
            + (bias == BIAS_BULL ? "BULL" : "BEAR")
            + ") score=" + IntegerToString(score)
            + "/" + IntegerToString(dynamicMin)
            + " lot=" + gSymbol);

   bool result = PlaceTrade(bias);
   if(!result)
      PushDiag("⚠️ E7: PlaceTrade returned false (broker reject or lot fail)");

   return result;
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE 8 — POSITION MANAGEMENT ENGINE
//  Manages ALL active positions from the gRec[] array on every tick.
//  Implements:
//    — Virtual TP1 (30%) and TP2 (40%) partial close logic
//    — Breakeven move after TP1
//    — Moderate bar-close TSL (rate-limited)
//    — Scalp tick-by-tick TSL with profit-lock stepping
//    — RSI exhaustion exit with ONE-TIME LATCH (Analysis 2 fix)
//    — Opposing EMA cross reverse exit
//    — Record sync and broker-state reconciliation
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §8.1 — TELEGRAM TP/EXIT MESSAGE BUILDER
//════════════════════════════════════════════════════════════════════

string BuildTPMessage(int tpNum, double price, double closedVol, int idx)
{
   if(idx < 0 || idx >= 100) return "";

   string sideStr = (gRec[idx].posType == ORDER_TYPE_BUY) ? "🟢 BUY" : "🔴 SELL";
   string pnl     = DoubleToString(GetPositionFloatPL(gRec[idx].ticket), 2);
   string entry   = DoubleToString(gRec[idx].entryPrice, gDigits);
   string vol     = DoubleToString(closedVol, 4);
   string pctStr  = (tpNum == 1) ? "30%" : (tpNum == 2) ? "40%" : "30%";
   string tpEmoji = (tpNum == 1) ? "1️⃣" : (tpNum == 2) ? "2️⃣" : "3️⃣";

   return "══════════════════════════\n"
         + tpEmoji + " TP" + IntegerToString(tpNum) + " HIT — " + sideStr + "\n"
         + "──────────────────────────\n"
         + "📌 " + gSymbol + " | " + DoubleToString(price, gDigits) + "\n"
         + "📥 Entry:    " + entry + "\n"
         + "📦 Closed:   " + vol + " lot (" + pctStr + ")\n"
         + "💰 Float P&L: $" + pnl + "\n"
         + "⏰ " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n"
         + "══════════════════════════";
}

string BuildExitMessage(ulong ticket, string reason, double closedVol)
{
   string side = "";
   string entry = "", pnl = "";
   if(PositionSelectByTicket(ticket))
   {
      long t = PositionGetInteger(POSITION_TYPE);
      side  = (t == POSITION_TYPE_BUY) ? "🟢 BUY" : "🔴 SELL";
      entry = DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), gDigits);
      pnl   = DoubleToString(PositionGetDouble(POSITION_PROFIT), 2);
   }
   return "══════════════════════════\n"
         + "🚪 EXIT — " + side + "\n"
         + "📌 " + gSymbol + "\n"
         + "📥 Entry:  " + entry + "\n"
         + "📦 Closed: " + DoubleToString(closedVol, 4) + " lot\n"
         + "💰 P&L:    $" + pnl + "\n"
         + "💬 Reason: " + reason + "\n"
         + "⏰ " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n"
         + "══════════════════════════";
}

//════════════════════════════════════════════════════════════════════
//  §8.1b — CURRENT PROFIT IN R-MULTIPLES (live price)
//  Shared by the breakeven-arm delay gate (InpScalpBEArmR).
//════════════════════════════════════════════════════════════════════
double RecordProfitR(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active)   return 0.0;
   if(gRec[idx].riskDistance <= 0.0)                return 0.0;
   if(!PositionSelectByTicket(gRec[idx].ticket))    return 0.0;
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double dist  = (gRec[idx].posType == ORDER_TYPE_BUY)
                  ? (price - gRec[idx].entryPrice)
                  : (gRec[idx].entryPrice - price);
   return dist / gRec[idx].riskDistance;
}

//════════════════════════════════════════════════════════════════════
//  §8.2 — MOVE TO BREAKEVEN
//  Sets SL to exact entry price after TP1 hit.
//  Guard: entryPrice must be >= SYMBOL_TRADE_STOPS_LEVEL away
//  from current price. On fail → queue in gModRecover[].
//════════════════════════════════════════════════════════════════════

void MoveToBreakevenAdvanced(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;
   if(gRec[idx].breakEvenSet) return; // already at BE — skip

   // BE-arm delay (v6.5): keep the runner unchoked until it has banked
   // InpScalpBEArmR of risk. 0 = arm immediately (legacy behaviour).
   if(InpScalpBEArmR > 0.0 && RecordProfitR(idx) < InpScalpBEArmR) return;

   ulong  ticket    = gRec[idx].ticket;
   double entry     = gRec[idx].entryPrice;
   double curSL     = gRec[idx].stopLoss;
   double hardTP3   = gRec[idx].hardTP3;
   ENUM_ORDER_TYPE side = gRec[idx].posType;

   // Verify SL isn't already at or better than entry
   if(side == ORDER_TYPE_BUY  && curSL >= entry - gPoint) { gRec[idx].breakEvenSet = true; return; }
   if(side == ORDER_TYPE_SELL && curSL <= entry + gPoint) { gRec[idx].breakEvenSet = true; return; }

   // bypassRateLimit=true: BE move is not a TSL micro-adjustment — always send it
   bool ok = ModifySLTP(ticket, entry, hardTP3, "BREAKEVEN", true);
   if(ok)
   {
      gRec[idx].stopLoss    = entry;
      gRec[idx].breakEvenSet = true;
      PushDiag("🔒 E8: BE set ticket=" + IntegerToString(ticket)
               + " SL=" + DoubleToString(entry, gDigits));
      JournalWrite("BREAKEVEN_SET", IntegerToString(ticket),
                   DoubleToString(entry, gDigits));
   }
   // On fail: ModifySLTP already queued to gModRecover[] — no action needed here
}

//════════════════════════════════════════════════════════════════════
//  §8.3 — MODERATE BAR-CLOSE TSL
//  Trails SL behind current price by trailStep = ATR × 1.2.
//  Rate-limited: only modifies if move >= tslStep × 0.50.
//  Direction guard: BUY SL only moves UP; SELL SL only moves DOWN.
//  Only activates after TP1 hit (tslActive=true).
//════════════════════════════════════════════════════════════════════

void ManageTrailing(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;
   if(!gRec[idx].tslActive) return; // TSL only after TP1

   ulong  ticket   = gRec[idx].ticket;
   double curSL    = gRec[idx].stopLoss;
   double hardTP3  = gRec[idx].hardTP3;
   ENUM_ORDER_TYPE side = gRec[idx].posType;

   // Recalculate trail step from current ATR (market conditions evolve)
   double atr       = GetATR(IDX_M5, 1);
   double trailStep = atr * InpModerateTSLATR;
   gRec[idx].tslStep = trailStep; // refresh stored step

   double newSL = 0.0;
   if(side == ORDER_TYPE_BUY)
   {
      double bid = GetBid();
      newSL = bid - trailStep;
      // Update high-watermark
      if(bid > gRec[idx].bestPrice) gRec[idx].bestPrice = bid;
      // Direction guard: only move SL up
      if(newSL <= curSL) return;
   }
   else // ORDER_TYPE_SELL
   {
      double ask = GetAsk();
      newSL = ask + trailStep;
      // Update low-watermark
      if(ask < gRec[idx].bestPrice || gRec[idx].bestPrice == 0.0)
         gRec[idx].bestPrice = ask;
      // Direction guard: only move SL down
      if(newSL >= curSL && curSL > 0.0) return;
   }

   // Rate-limit guard (core fix from Analysis 2.docx)
   // Skip if move is less than 50% of trailStep — prevents Error 130 broker spam
   if(trailStep > 0.0 && MathAbs(newSL - curSL) < trailStep * 0.50) return;

   // Send modification (with built-in rate-limit check = bypassed since we already did it)
   ModifySLTP(ticket, newSL, hardTP3, "TSL-MODERATE", true);
}

//════════════════════════════════════════════════════════════════════
//  §8.4 — SCALP TICK-BY-TICK TSL WITH PROFIT-LOCK STEPS
//  Runs on every tick when InpScalpTSLOnTick=true.
//  Tracks bestPrice (high-watermark) and applies 3-tier profit locks:
//    R1=0.60 → SL to entry + ATR × InpScalpProfitLockATR1
//    R2=0.90 → SL to entry + ATR × InpScalpProfitLockATR2
//    R3=1.20 → SL to entry + ATR × InpScalpProfitLockATR3
//  Fast BE: if InpScalpLockBEFast and profit >= InpScalpFastBER × risk,
//           move to breakeven immediately (before R1 step).
//════════════════════════════════════════════════════════════════════

void ManageScalpTickTrailing(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;
   if(!gRec[idx].tslActive)       return; // only after TP1
   if(!gRec[idx].scalpTSLOnTick)  return; // tick TSL must be enabled

   ulong  ticket    = gRec[idx].ticket;
   double curSL     = gRec[idx].stopLoss;
   double hardTP3   = gRec[idx].hardTP3;
   double entry     = gRec[idx].entryPrice;
   double riskDist  = gRec[idx].riskDistance;
   double atr       = gRec[idx].atrAtEntry; // use entry ATR for lock steps (stable reference)
   ENUM_ORDER_TYPE side = gRec[idx].posType;

   if(riskDist <= 0.0) return; // degenerate record

   // Live price reference
   double livePrice = (side == ORDER_TYPE_BUY) ? GetBid() : GetAsk();

   // Update best price (high-watermark for BUY, low-watermark for SELL)
   if(side == ORDER_TYPE_BUY)
   {
      if(livePrice > gRec[idx].bestPrice) gRec[idx].bestPrice = livePrice;
   }
   else
   {
      if(gRec[idx].bestPrice == 0.0 || livePrice < gRec[idx].bestPrice)
         gRec[idx].bestPrice = livePrice;
   }

   double bestPrice = gRec[idx].bestPrice;

   // Current profit in R-multiples
   double profitDist = (side == ORDER_TYPE_BUY)
                       ? (bestPrice - entry)
                       : (entry - bestPrice);
   double profitR    = SafeDiv(profitDist, riskDist); // R ratio at best price

   // TSL step for tick trailing (fractional ATR)
   double step = atr * InpScalpTSLATRFraction;
   gRec[idx].tslStep = step;

   // v6.3g FIX: Detect HFT positions and route to dedicated HFT profit-lock thresholds.
   //   HFT mode flags positions with isScalpMode=true (same tick-trailing path as Scalp)
   //   but uses much tighter R-levels because HFT TP range is only 0.40–0.80R.
   //   InpHFTProfitLockR1/R2 (declared in P1) were previously NEVER used anywhere.
   bool   isHFTRec  = (gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE);
   // Fast BE threshold and gate
   double fastBER   = isHFTRec ? InpHFTFastBER      : InpScalpFastBER;
   bool   useFastBE = isHFTRec ? true                : InpScalpLockBEFast; // always ON for HFT

   //── Fast BE Lock ─────────────────────────────────────────────────
   if(useFastBE && !gRec[idx].breakEvenSet)
   {
      if(profitR >= fastBER) // HFT default: 0.25R | Scalp default: 0.35R
      {
         MoveToBreakevenAdvanced(idx);
         PushDiag("⚡ E8: " + (isHFTRec ? "HFT" : "Scalp") + "FastBE triggered at "
                  + DoubleToString(profitR, 2) + "R");
      }
   }

   //── Profit Lock Steps (HFT 2-tier / Scalp 3-tier) ─────────────────
   // v6.3g FIX: HFT uses InpHFTProfitLockR1/R2 (0.30/0.60R — tight).
   //            Scalp uses SCALP_LOCK_R1/R2/R3 (0.60/0.90/1.20R — wider).
   //            ATR lock buffers are proportionally tighter for HFT.
   bool   useLock  = isHFTRec ? InpHFTUseProfitLock     : InpScalpUseProfitLockSteps;
   double lockR1   = isHFTRec ? InpHFTProfitLockR1       : SCALP_LOCK_R1;  // HFT:0.30  Scalp:0.60
   double lockR2   = isHFTRec ? InpHFTProfitLockR2       : SCALP_LOCK_R2;  // HFT:0.60  Scalp:0.90
   double lockR3   = isHFTRec ? InpHFTProfitLockR2       : SCALP_LOCK_R3;  // HFT:same  Scalp:1.20
   double lockATR1 = isHFTRec ? 0.05 : InpScalpProfitLockATR1;  // HFT:0.05×ATR  Scalp:0.10×ATR
   double lockATR2 = isHFTRec ? 0.10 : InpScalpProfitLockATR2;  // HFT:0.10×ATR  Scalp:0.20×ATR
   double lockATR3 = isHFTRec ? 0.10 : InpScalpProfitLockATR3;  // HFT:same R2   Scalp:0.35×ATR

   double lockSL = 0.0;
   string lockLabel = "";

   if(profitR >= lockR3 && useLock)
   {
      double lockDist = atr * lockATR3;
      lockSL = (side == ORDER_TYPE_BUY) ? (entry + lockDist) : (entry - lockDist);
      lockLabel = "LOCK-R3(" + DoubleToString(lockR3, 2) + "R)";
   }
   else if(profitR >= lockR2 && useLock)
   {
      double lockDist = atr * lockATR2;
      lockSL = (side == ORDER_TYPE_BUY) ? (entry + lockDist) : (entry - lockDist);
      lockLabel = "LOCK-R2(" + DoubleToString(lockR2, 2) + "R)";
   }
   else if(profitR >= lockR1 && useLock)
   {
      double lockDist = atr * lockATR1;
      lockSL = (side == ORDER_TYPE_BUY) ? (entry + lockDist) : (entry - lockDist);
      lockLabel = "LOCK-R1(" + DoubleToString(lockR1, 2) + "R)";
   }

   // Determine final SL: max of lock SL and active trailing SL
   double trailSL = 0.0;
   if(side == ORDER_TYPE_BUY)
   {
      trailSL = bestPrice - step;
      // Final SL = more conservative (higher) of lock and trail
      double finalSL = (lockSL > 0.0) ? MathMax(lockSL, trailSL) : trailSL;
      // Direction guard: BUY SL only moves up
      if(finalSL <= curSL) return;
      // Rate-limit guard: skip if move < 50% of step
      if(step > 0.0 && MathAbs(finalSL - curSL) < step * 0.50) return;
      if(lockLabel != "")
         PushDiag("🔒 E8: ScalpLock " + lockLabel + " SL→" + DoubleToString(finalSL, gDigits));
      ModifySLTP(ticket, finalSL, hardTP3, "SCALP-TSL-" + lockLabel, true);
   }
   else // ORDER_TYPE_SELL
   {
      trailSL = bestPrice + step;
      double finalSL = (lockSL > 0.0) ? MathMin(lockSL, trailSL) : trailSL;
      // Direction guard: SELL SL only moves down
      if(curSL > 0.0 && finalSL >= curSL) return;
      // Rate-limit guard
      if(step > 0.0 && MathAbs(finalSL - curSL) < step * 0.50) return;
      if(lockLabel != "")
         PushDiag("🔒 E8: ScalpLock " + lockLabel + " SL→" + DoubleToString(finalSL, gDigits));
      ModifySLTP(ticket, finalSL, hardTP3, "SCALP-TSL-" + lockLabel, true);
   }
}

//════════════════════════════════════════════════════════════════════
//  §8.5 — RSI EXHAUSTION EXIT — ONE-TIME LATCH
//  Analysis 2.docx §Bug 4: Without the exhaustionHit latch, every
//  subsequent tick with RSI exhausted would close another 50% → a
//  halving loop that drills position to zero over ~10 ticks.
//  Fix: exhaustionHit = true IMMEDIATELY and PERMANENTLY on first
//  detection. No second activation possible on the same TradeRecord.
//════════════════════════════════════════════════════════════════════

void ManageExhaustion(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;
   if(!InpRSIExhaustionExit) return; // feature disabled globally

   // 🔒 ONE-TIME LATCH: if already triggered on this trade → NEVER re-enter
   if(gRec[idx].exhaustionHit) return;

   ulong  ticket = gRec[idx].ticket;
   ENUM_ORDER_TYPE side = gRec[idx].posType;

   // Check for InpRSIExhaustionBars consecutive counter-trend RSI bars
   // RSIExhaustionDetected() defined in Engine 2 (Part 2)
   if(!RSIExhaustionDetected(IDX_M5, side)) return; // not yet exhausted

   // ── EXHAUSTION DETECTED ───────────────────────────────────────
   // Immediately set the latch to prevent ANY future re-entry on this trade
   gRec[idx].exhaustionHit = true; // 🔒 PERMANENT

   // Close 50% of REMAINING volume (not initial — position may have been partially closed)
   double curVol   = GetPositionCurrentVolume(ticket);
   double closeVol = NormalizeLotSafe(curVol * 0.50);

   if(closeVol < gMinLot)
   {
      // Remaining volume too small — close all
      PushDiag("⚠️ E8: Exhaustion — closeVol dust (" + DoubleToString(closeVol, 4)
               + ") → upgrade to full close");
      closeVol = NormalizeLotSafe(curVol);
   }

   bool ok = PartialCloseVolumeManaged(ticket, closeVol, "RSI_EXHAUSTION");

   // Journal and stats
   JournalWrite("EXHAUSTION_EXIT",
                IntegerToString(ticket),
                DoubleToString(closeVol, 4),
                "M5_RSI_" + IntegerToString(InpRSIExhaustionBars) + "bars",
                DoubleToString(GetPositionFloatPL(ticket), 2));

   // Telegram — queued via TGEnqueue (never direct)
   string tgMsg = "══════════════════════════\n"
                 "⚠️ RSI EXHAUSTION EXIT\n"
                 "──────────────────────────\n"
                 + "📌 " + gSymbol + " ticket=" + IntegerToString(ticket) + "\n"
                 + "📦 Closed: " + DoubleToString(closeVol, 4) + " lot (50% of remaining)\n"
                 + "🔒 Latch: exhaustionHit=true (ONE-TIME ONLY)\n"
                 + "💰 P&L: $" + DoubleToString(GetPositionFloatPL(ticket), 2) + "\n"
                 + "⏰ " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n"
                 + "══════════════════════════";
   TGEnqueue(MSG_EXIT, tgMsg, false);

   PushDiag((ok ? "✅" : "⚠️") + " E8: EXHAUSTION EXIT "
            + DoubleToString(closeVol, 4) + " lot, ticket=" + IntegerToString(ticket)
            + " [LATCH SET — no re-entry]");
}

//════════════════════════════════════════════════════════════════════
//  §8.6 — OPPOSING EMA CROSS REVERSE EXIT
//  If a BUY position detects CrossedDown on M5 → close full position.
//  If a SELL position detects CrossedUp on M5 → close full position.
//  This is a market-structure invalidation — do not wait for SL/TP.
//════════════════════════════════════════════════════════════════════

void ManageReverseExit(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;
   if(!InpUseReverseExit) return; // feature disabled globally

   ulong  ticket = gRec[idx].ticket;
   ENUM_ORDER_TYPE side = gRec[idx].posType;

   // CrossedDown/CrossedUp from Engine 2 (Part 2)
   bool reversalDetected = (side == ORDER_TYPE_BUY)
                           ? CrossedDown(IDX_M5)  // EMA9 crossed below EMA34 on M5
                           : CrossedUp(IDX_M5);   // EMA9 crossed above EMA34 on M5

   if(!reversalDetected) return;

   // Reversal confirmed — close full remaining volume immediately
   double curVol = GetPositionCurrentVolume(ticket);

   PushDiag("🔄 E8: Reverse EMA cross — closing ticket=" + IntegerToString(ticket)
            + " vol=" + DoubleToString(curVol, 4));

   bool ok = PartialCloseVolumeManagedFull(ticket, "REVERSE_EMA_CROSS");

   JournalWrite("REVERSE_EXIT",
                IntegerToString(ticket),
                DoubleToString(curVol, 4),
                (side == ORDER_TYPE_BUY ? "CrossedDown" : "CrossedUp"));

   string tgMsg = BuildExitMessage(ticket, "🔄 Reverse EMA Cross on M5", curVol);
   TGEnqueue(MSG_EXIT, tgMsg, false);
}

//════════════════════════════════════════════════════════════════════
//  §8.7 — ManageTradeRecordAdvanced() — CORE MANAGEMENT LOOP
//  Called for every active gRec[idx] on each tick.
//  Sequence (strict):
//    1. Position existence check (clear stale records)
//    2. TP1 virtual partial close (30%) + trigger BE + TSL arm
//    3. TP2 virtual partial close (40%)
//    4. Exhaustion exit check (latch-guarded)
//    5. Reverse cross exit check
//    6. TSL management (mode-appropriate)
//════════════════════════════════════════════════════════════════════

void ManageTradeRecordAdvanced(int idx)
{
   if(idx < 0 || idx >= 100) return;
   if(!gRec[idx].active)     return;

   ulong  ticket = gRec[idx].ticket;

   //── 1. Position existence check ───────────────────────────────────
   if(!PositionExistsByTicket(ticket))
   {
      // Position no longer exists — closed by SL, broker TP3, or external action
      PushDiag("🔔 E8: Position " + IntegerToString(ticket) + " closed externally → clearing record");
      ClearRecord(idx);
      return;
   }

   //── Get live reference prices ─────────────────────────────────────
   double livePrice = 0.0;
   ENUM_ORDER_TYPE side = gRec[idx].posType;
   if(side == ORDER_TYPE_BUY)
      livePrice = GetBid(); // profit realized at bid for BUY
   else
      livePrice = GetAsk(); // profit realized at ask for SELL

   double tp1Price  = gRec[idx].tp1Price;
   double tp2Price  = gRec[idx].tp2Price;
   double initVol   = gRec[idx].initialVolume;
   double hardTP3   = gRec[idx].hardTP3;

   //── 2. TP1 Virtual Partial Close ─────────────────────────────────
   if(!gRec[idx].tp1Hit)
   {
      bool tp1Reached = (side == ORDER_TYPE_BUY)
                        ? (livePrice >= tp1Price)
                        : (livePrice <= tp1Price);
      if(tp1Reached)
      {
         // Close 30% of initial volume (dust-guarded internally)
         double closeVol = NormalizeLotSafe(initVol * 0.30);
         bool   ok       = PartialCloseVolumeManaged(ticket, closeVol, "TP1_PARTIAL_30");

         if(ok)
         {
            gRec[idx].tp1Hit   = true;
            gRec[idx].tslActive = true; // arm TSL after TP1

            // Move SL to exact entry (breakeven) — critical risk management
            MoveToBreakevenAdvanced(idx);

            // Stats
            gPerf.tp1Hits++;

            // Journal
            JournalWrite("TP1_HIT",
                         IntegerToString(ticket),
                         DoubleToString(livePrice, gDigits),
                         DoubleToString(closeVol, 4),
                         "BE armed");

            // Telegram TP1 alert (queued)
            TGEnqueue(MSG_TP1, BuildTPMessage(1, livePrice, closeVol, idx), false);

            PushDiag("1️⃣ E8: TP1 hit @" + DoubleToString(livePrice, gDigits)
                     + " ticket=" + IntegerToString(ticket)
                     + " closed=" + DoubleToString(closeVol, 4) + " | TSL ARMED | BE SET");
         }
         else
         {
            PushDiag("⚠️ E8: TP1 partial close failed — will retry next tick");
            // PartialClose already queued retry — next tick will re-evaluate
         }
      }
   }

   //── 3. TP2 Virtual Partial Close ─────────────────────────────────
   if(gRec[idx].tp1Hit && !gRec[idx].tp2Hit)
   {
      bool tp2Reached = (side == ORDER_TYPE_BUY)
                        ? (livePrice >= tp2Price)
                        : (livePrice <= tp2Price);
      if(tp2Reached)
      {
         // Close 40% of initial volume
         double closeVol = NormalizeLotSafe(initVol * 0.40);
         bool   ok       = PartialCloseVolumeManaged(ticket, closeVol, "TP2_PARTIAL_40");

         if(ok)
         {
            gRec[idx].tp2Hit = true;
            gPerf.tp2Hits++;

            JournalWrite("TP2_HIT",
                         IntegerToString(ticket),
                         DoubleToString(livePrice, gDigits),
                         DoubleToString(closeVol, 4));

            TGEnqueue(MSG_TP2, BuildTPMessage(2, livePrice, closeVol, idx), false);

            PushDiag("2️⃣ E8: TP2 hit @" + DoubleToString(livePrice, gDigits)
                     + " ticket=" + IntegerToString(ticket)
                     + " closed=" + DoubleToString(closeVol, 4) + " | Remaining → TP3 at broker");
         }
      }
   }

   //── 4. RSI Exhaustion Exit (ONE-TIME LATCH) ───────────────────────
   ManageExhaustion(idx);

   //── 5. Reverse EMA Cross Exit ─────────────────────────────────────
   ManageReverseExit(idx);

   //── 6. TSL Management (mode-appropriate, only after TP1) ──────────
   if(gRec[idx].tslActive)
   {
      if(gRec[idx].isScalpMode && gRec[idx].scalpTSLOnTick)
         ManageScalpTickTrailing(idx); // tick-by-tick for scalp / HFT
      else
         ManageTrailing(idx);          // bar-close TSL for moderate,
                                       // AND fallback for scalp with tick-TSL off
      // Dead-path fix: isScalpMode=true + scalpTSLOnTick=false previously fell through
      // with no TSL at all. Now always falls to ManageTrailing() as a safe floor.
   }

   // Update management timestamp
   gRec[idx].lastManageAt = TimeCurrent();
}

//════════════════════════════════════════════════════════════════════
//  §8.8 — RunAllPositionManagement()
//  Iterates all active gRec[] slots. Called from OnTick fast path.
//  Handles pending-to-position promotion from gPlan[] array.
//════════════════════════════════════════════════════════════════════

void RunAllPositionManagement()
{
   // ── Manage active market positions ────────────────────────────
   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active) continue;
      ManageTradeRecordAdvanced(i);
   }

   // ── Check for filled pending orders (gPlan[] → gRec[] promotion) ─
   for(int i = 0; i < 20; i++)
   {
      if(!gPlan[i].active) continue;

      ulong ordTkt = gPlan[i].orderTicket;

      // If the order ticket no longer exists as a pending order,
      // it was either filled (→ find matching position) or cancelled
      if(!PendingOrderExists(ordTkt))
      {
         // Try to find the resulting position by magic and symbol
         bool foundPos = false;
         for(int p = 0; p < PositionsTotal(); p++)
         {
            ulong posTkt = PositionGetTicket(p);
            if(!PositionSelectByTicket(posTkt)) continue;
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
            if(PositionGetString(POSITION_SYMBOL) != gPlan[i].symbol) continue;
            // Check if already tracked
            if(FindRecordByTicket(posTkt) >= 0) continue;

            // Untracked EA position on our symbol — this is the filled scalp
            double fillEntry = PositionGetDouble(POSITION_PRICE_OPEN);
            double fillSL    = PositionGetDouble(POSITION_SL);
            double fillVol   = PositionGetDouble(POSITION_VOLUME);
            long   posType   = PositionGetInteger(POSITION_TYPE);
            double atr       = gPlan[i].riskDistance > 0
                               ? gPlan[i].riskDistance / (0.8 * InpScalpSLATRMin + 0.2)
                               : GetATR(IDX_M5, 1); // best estimate of ATR at fill

            RegisterTradeRecord(posTkt,
               (posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),
               fillEntry, fillSL,
               gPlan[i].tp1, gPlan[i].tp2, gPlan[i].tp3,
               fillVol, atr, "SCALP_FILL_FROM_PLAN");

            JournalWrite("SCALP_FILL",
               IntegerToString(posTkt),
               DoubleToString(fillEntry, gDigits),
               DoubleToString(fillVol, 4));

            PushDiag("✅ E8: Scalp filled — plan→record promoted, ticket=" + IntegerToString(posTkt));

            ClearPendingPlan(i); // clear the plan slot
            foundPos = true;
            break;
         }

         if(!foundPos)
         {
            // Plan order gone and no matching position → order expired/cancelled
            PushDiag("🗑️ E8: Plan " + IntegerToString(i) + " order=" + IntegerToString(ordTkt) + " expired/cancelled → cleared");
            JournalWrite("PENDING_EXPIRED", IntegerToString(ordTkt));
            ClearPendingPlan(i);
         }
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  §8.9 — SyncRecordsFromBroker()
//  Reconciliation engine: ensures gRec[] matches broker reality.
//  Called from OnTick (lightweight) + OnTimer (thorough sweep).
//  Handles EA restart recovery: rebuilds TradeRecords for any
//  untracked EA positions found at broker.
//════════════════════════════════════════════════════════════════════

void SyncRecordsFromBroker()
{
   // ── Pass 1: Remove stale records for closed positions ──────────
   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active) continue;
      if(!PositionExistsByTicket(gRec[i].ticket))
      {
         PushDiag("🔄 E8: Sync — position " + IntegerToString(gRec[i].ticket) + " gone → clearing record");
         ClearRecord(i);
      }
   }

   // ── Pass 2: Discover and recover untracked EA positions ────────
   // This handles EA restart scenarios where gRec[] was wiped but
   // positions are still open at the broker
   for(int p = 0; p < PositionsTotal(); p++)
   {
      ulong tkt = PositionGetTicket(p);
      if(!PositionSelectByTicket(tkt)) continue;

      // Only our EA's positions
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol)  continue;

      // Already tracked?
      if(FindRecordByTicket(tkt) >= 0) continue;

      // ── UNTRACKED EA POSITION FOUND — REBUILD RECORD ──────────
      double fillEntry = PositionGetDouble(POSITION_PRICE_OPEN);
      double fillSL    = PositionGetDouble(POSITION_SL);
      double fillTP    = PositionGetDouble(POSITION_TP);
      double fillVol   = PositionGetDouble(POSITION_VOLUME);
      long   posType   = PositionGetInteger(POSITION_TYPE);
      double atr       = GetATR(IDX_M5, 1);

      // Reconstruct virtual TP1/TP2 from risk distance
      double riskDist = MathAbs(fillEntry - fillSL);
      int    dir      = (posType == POSITION_TYPE_BUY) ? 1 : -1;
      double tp1      = NormalizePrice(fillEntry + dir * riskDist * InpModerateTP1R);
      double tp2      = NormalizePrice(fillEntry + dir * riskDist * InpModerateTP2R);
      double tp3      = (fillTP > 0.0) ? fillTP
                        : NormalizePrice(fillEntry + dir * riskDist * InpModerateTP3R);

      RegisterTradeRecord(tkt,
         (posType == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),
         fillEntry, fillSL, tp1, tp2, tp3,
         fillVol, atr, "RECOVERED_FROM_BROKER");

      JournalWrite("RECORD_RECOVERED",
                   IntegerToString(tkt),
                   DoubleToString(fillEntry, gDigits),
                   DoubleToString(fillSL, gDigits),
                   "tp1=" + DoubleToString(tp1, gDigits),
                   "tp3=" + DoubleToString(tp3, gDigits));

      PushDiag("🔄 E8: Record REBUILT from broker — ticket=" + IntegerToString(tkt)
               + " entry=" + DoubleToString(fillEntry, gDigits)
               + " SL=" + DoubleToString(fillSL, gDigits)
               + " (EA restart recovery)");
   }
}

//════════════════════════════════════════════════════════════════════
//  §8.10 — ProcessRetryQueue()
//  Processes queued retry actions from gRetry[] array.
//  Called from OnTimer (never from OnTick hot path).
//  Attempt limit = RETRY_MAX_ATTEMPTS. After max → log and abandon.
//
//  kind=1: SL/TP modify retry
//  kind=2: Partial close retry
//  kind=3: Panic full close retry (Emergency)
//  kind=4: Delete pending order retry
//════════════════════════════════════════════════════════════════════

void ProcessRetryQueue()
{
   datetime now = TimeCurrent();

   // Market-state guard (v6.5): if the session is shut, defer EVERY queued
   // close/modify by one interval WITHOUT consuming an attempt. This is the
   // core fix for the rollover/weekend retry storm — the queue idles quietly
   // instead of burning all 4 attempts against a closed market and abandoning
   // a still-open position. Pending-order deletes (kind=4) are left alone:
   // those are local cancels the broker accepts even when flat-closed.
   static datetime _lastClosedLog = 0;
   if(!IsMarketTradeable())
   {
      bool anyTradeRetry = false;
      for(int i = 0; i < 64; i++)
      {
         if(!gRetry[i].used) continue;
         if(gRetry[i].kind == 4) continue;          // local pending-delete is fine
         gRetry[i].nextTry = now + RETRY_INTERVAL_SEC;
         anyTradeRetry = true;
      }
      if(anyTradeRetry && (now - _lastClosedLog) >= 30)
      {
         _lastClosedLog = now;
         PushDiag("⏸️ E8: Retry queue paused — market closed (deferring close/modify, no attempts burned)");
      }
      // fall through so kind==4 deletes can still run below
   }

   for(int i = 0; i < 64; i++)
   {
      if(!gRetry[i].used)         continue;
      if(now < gRetry[i].nextTry) continue; // not yet time to retry

      gRetry[i].attempts++;

      // Give up after max attempts
      if(gRetry[i].attempts > RETRY_MAX_ATTEMPTS)
      {
         PushDiag("🚫 E8: Retry[" + IntegerToString(i) + "] ABANDONED after "
                  + IntegerToString(gRetry[i].attempts - 1) + " attempts — "
                  + gRetry[i].note);
         JournalWrite("RETRY_ABANDONED",
                      IntegerToString(gRetry[i].kind),
                      IntegerToString(gRetry[i].ticket),
                      gRetry[i].note,
                      "attempts=" + IntegerToString(gRetry[i].attempts - 1));
         gRetry[i].used = false;
         continue;
      }

      bool ok  = false;
      ulong tk = gRetry[i].ticket;

      switch(gRetry[i].kind)
      {
         case 1: // SL/TP modify
            ok = ModifySLTP(tk, gRetry[i].price1, gRetry[i].price2,
                            "RETRY:" + gRetry[i].note, true);
            break;

         case 2: // Partial close
            ok = PartialCloseVolumeManaged(tk, gRetry[i].volume,
                                           "RETRY:" + gRetry[i].note);
            break;

         case 3: // Panic full close (emergency)
         {
            gTrade.SetExpertMagicNumber((ulong)InpMagic);
            gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints * 3); // wider on retry
            ok = gTrade.PositionClose(tk);
            if(ok)
            {
               JournalWrite("RETRY_PANIC_OK", IntegerToString(tk), gRetry[i].note,
                            "attempt=" + IntegerToString(gRetry[i].attempts));
            }
            break;
         }

         case 4: // Delete pending order
         {
            gTrade.SetExpertMagicNumber((ulong)InpMagic);
            ok = gTrade.OrderDelete(tk);
            if(ok)
            {
               // Find and clear the matching pending plan
               int planIdx = FindPendingByTicket(tk);
               if(planIdx >= 0) ClearPendingPlan(planIdx);
               JournalWrite("RETRY_DELETE_OK", IntegerToString(tk), gRetry[i].note);
            }
            break;
         }
      }

      if(ok)
      {
         PushDiag("✅ E8: Retry[" + IntegerToString(i) + "] succeeded on attempt "
                  + IntegerToString(gRetry[i].attempts) + " — " + gRetry[i].note);
         gRetry[i].used = false; // done — free the slot
      }
      else
      {
         // Schedule next retry with increasing interval (backoff)
         gRetry[i].nextTry = now + (datetime)(RETRY_INTERVAL_SEC * gRetry[i].attempts);
         PushDiag("⚠️ E8: Retry[" + IntegerToString(i) + "] attempt "
                  + IntegerToString(gRetry[i].attempts) + " failed — next in "
                  + IntegerToString(RETRY_INTERVAL_SEC * gRetry[i].attempts) + "s");
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  §8.11 — ProcessModifyRecovery()
//  Processes queued SL/TP modification tasks from gModRecover[].
//  Called from OnTimer. Supports 3-stage recovery escalation:
//    RECOVERY_REPRICE_PENDING: reprice pending order at new level
//    RECOVERY_FALLBACK_MARKET: convert failed pending to market order
//    RECOVERY_DROP_SIGNAL:     abandon — cancel order and log
//════════════════════════════════════════════════════════════════════

void ProcessModifyRecovery()
{
   datetime now = TimeCurrent();

   for(int i = 0; i < 32; i++)
   {
      if(!gModRecover[i].active)      continue;
      if(now < gModRecover[i].nextTry) continue;

      gModRecover[i].tries++;
      ulong tkt = gModRecover[i].ticket;

      // Verify position still exists before retrying
      if(!PositionExistsByTicket(tkt))
      {
         // Position gone — nothing to modify
         PushDiag("🔧 E8: ModRecover[" + IntegerToString(i) + "] ticket=" + IntegerToString(tkt) + " gone → cleared");
         gModRecover[i].active = false;
         continue;
      }

      gTrade.SetExpertMagicNumber((ulong)InpMagic);
      gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
      bool ok = gTrade.PositionModify(tkt, gModRecover[i].sl, gModRecover[i].tp);
      int  rc = (int)gTrade.ResultRetcode();

      if(ok)
      {
         // Update record
         int recIdx = FindRecordByTicket(tkt);
         if(recIdx >= 0) gRec[recIdx].stopLoss = gModRecover[i].sl;

         PushDiag("✅ E8: ModRecover[" + IntegerToString(i) + "] success on try "
                  + IntegerToString(gModRecover[i].tries)
                  + " SL=" + DoubleToString(gModRecover[i].sl, gDigits));
         JournalWrite("MODIFY_RECOVERY_OK", IntegerToString(tkt),
                      DoubleToString(gModRecover[i].sl, gDigits),
                      "try=" + IntegerToString(gModRecover[i].tries));
         gModRecover[i].active = false;
      }
      else
      {
         if(gModRecover[i].tries >= 3)
         {
            // After 3 failures — drop and log (spec: RECOVERY_DROP_SIGNAL)
            PushDiag("🚫 E8: ModRecover[" + IntegerToString(i) + "] DROPPED after 3 fails — "
                     + gModRecover[i].why + " rc=" + RetcodeStr(rc));
            JournalWrite("MODIFY_RECOVERY_FAIL", IntegerToString(tkt),
                         RetcodeStr(rc), gModRecover[i].why,
                         "tries=" + IntegerToString(gModRecover[i].tries));
            gModRecover[i].active = false;
         }
         else
         {
            // Retry with backoff
            gModRecover[i].nextTry = now + (datetime)(RETRY_INTERVAL_SEC * gModRecover[i].tries);
            PushDiag("⚠️ E8: ModRecover[" + IntegerToString(i) + "] try "
                     + IntegerToString(gModRecover[i].tries) + " failed rc=" + RetcodeStr(rc)
                     + " — retry in " + IntegerToString(RETRY_INTERVAL_SEC * gModRecover[i].tries) + "s");
         }
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  ⚙️  ENGINE 9 — SAFETY VAULT ENGINE (THE VAULT)
//  Monitors all risk conditions on every tick.
//  Implements 9 distinct lock states with hysteresis and cascaded
//  responses. Non-blocking emergency close via RetryAction queue.
//  Loss-streak cooldown: tiered wait (90s / 180s / 300s).
//  Daily PnL tracking with new-day auto-reset at broker day open.
//════════════════════════════════════════════════════════════════════

//════════════════════════════════════════════════════════════════════
//  §9.1 — EQUITY PEAK TRACKER
//  Maintains gPeakEquity for global drawdown calculation.
//  Only moves upward — equity peaks are never "re-set".
//════════════════════════════════════════════════════════════════════

void UpdatePeakEquity()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > gPeakEquity)
   {
      gPeakEquity = equity;
      // No logging here — called every tick, must be ultra-lightweight
   }
}

//════════════════════════════════════════════════════════════════════
//  §9.2 — DAILY STATS MANAGER
//  Resets daily PnL counter when a new broker day begins.
//  Tracks weekly PnL separately for weekly Telegram report.
//════════════════════════════════════════════════════════════════════

void UpdateDailyStats()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   MqlDateTime lastReset;
   TimeToStruct(gLastDailyReset, lastReset);

   // New day detected (day-of-year comparison)
   bool newDay = (now.day_of_year != lastReset.day_of_year || now.year != lastReset.year);

   if(newDay)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      PushDiag("📅 E9: New day detected — resetting daily stats | DayPnL="
               + DoubleToString(gDailyClosedPnL, 2)
               + " | DayStart equity→" + DoubleToString(equity, 2));

      // Archive yesterday's PnL for weekly tracking
      gTGWeeklyPnL += gDailyClosedPnL;

      // Log new day start
      JournalWrite("DAY_START",
                   TimeToString(TimeCurrent(), TIME_DATE),
                   DoubleToString(equity, 2),
                   "prev_day_pnl=" + DoubleToString(gDailyClosedPnL, 2));

      // Reset daily counters
      gDailyClosedPnL = 0.0;
      gDayStartEquity = equity;
      gLastDailyReset = TimeCurrent();

      // Lift daily loss sleep mode if active (new day = fresh chance)
      if(gSafetyLock == LOCK_DAILY_LOSS)
      {
         gSafetyLock = LOCK_NONE;
         PushDiag("✅ E9: Daily loss lock LIFTED on new day reset");
         JournalWrite("DAILY_LOCK_LIFT", TimeToString(TimeCurrent(), TIME_DATE));
      }
   }

   // Weekly reset check (Sunday = new week for most brokers)
   MqlDateTime lastWeek;
   TimeToStruct(gLastWeeklyReset, lastWeek);
   bool newWeek = (now.day_of_week == 0 && lastWeek.day_of_week != 0); // Sunday
   if(newWeek)
   {
      JournalWrite("WEEK_START",
                   TimeToString(TimeCurrent(), TIME_DATE),
                   "weekly_pnl=" + DoubleToString(gTGWeeklyPnL, 2));
      gTGWeeklyPnL    = 0.0;
      gLastWeeklyReset = TimeCurrent();
   }
}

//════════════════════════════════════════════════════════════════════
//  §9.3 — LOSS STREAK COOLDOWN SYSTEM
//  Tiered wait time between entries after consecutive losses:
//    1 loss  → 90s
//    2 losses → 180s
//    3+ losses → 300s
//  Prevents revenge trading after drawdown sequences.
//════════════════════════════════════════════════════════════════════

double LossCooldownSeconds()
{
   if(gConsecLosses <= 0) return 0.0;
   if(gConsecLosses == 1) return 90.0;
   if(gConsecLosses == 2) return 180.0;
   return 300.0; // 3+ losses
}

bool LossCooldownOK()
{
   double needed = LossCooldownSeconds();
   if(needed <= 0.0) return true; // no cooldown needed
   double elapsed = (double)(TimeCurrent() - gLastEntryTime);
   return (elapsed >= needed);
}

//════════════════════════════════════════════════════════════════════
//  §9.4 — CheckSafetyLockAdvanced() — ALL 9 LOCK TYPES
//  Returns the highest-priority active lock, evaluated in cascade order.
//  Caller (TryNewEntry, RunVaultChecks) acts on the returned enum.
//  Each check is a single condition read — no broker calls here.
//
//  Priority order (highest = most critical):
//   1. LOCK_EQUITY_FLOOR  — Hard floor breach → emergency halt
//   2. LOCK_DAILY_LOSS    — Daily loss limit exceeded → sleep mode
//   3. LOCK_GLOBAL_DD     — Global drawdown guard (blocks entries only)
//   4. LOCK_MANUAL_PAUSE  — Button or startup pause
//   5. LOCK_MACRO_DIVERGENCE — H1 vs SMA800 mismatch
//   6. LOCK_SPREAD        — Persistent spread shock (5+ ticks)
//   7. LOCK_STALE_DATA    — Indicator data freshness failure
//   8. LOCK_SPIKE         — Active price spike detected (v5.0)
//   9. LOCK_NEWS          — Active news window (v5.0)
//  10. LOCK_NONE          — All clear
//════════════════════════════════════════════════════════════════════

ENUM_SAFETY_LOCK CheckSafetyLockAdvanced()
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);

   //─── 1. Equity Floor — hard dollar floor, blocks entries if equity < floor ─────
   if(InpEquityFloor > 0.0 && equity < InpEquityFloor)
   {
      return LOCK_EQUITY_FLOOR;
   }

   //── 2. Daily Loss Limit — sleep mode until new day ───────────────
   if(gDayStartEquity > 0.0)
   {
      double dailyLossPct = SafeDiv(MathAbs(gDailyClosedPnL), gDayStartEquity) * 100.0;
      // Also include current floating loss in daily calculation
      double floatLoss = equity - gDayStartEquity;
      if(floatLoss < 0.0)
         dailyLossPct = SafeDiv(MathAbs(floatLoss), gDayStartEquity) * 100.0;
      // Use the worse of closed vs floating loss
      double effectiveLossPct = MathMax(dailyLossPct,
                                SafeDiv(MathAbs(MathMin(gDailyClosedPnL, 0.0)), gDayStartEquity) * 100.0);

      // v6.3g FIX: Use gRt_DailyDDPct (set by ApplySubMode per sub-mode/profile) instead
      // of the raw input InpMaxDailyLossPercent.  Previously this vault check ignored the
      // HFT/Scalp/Moderate DD limits and always used the shared input value.
      double ddCeiling = (gRt_DailyDDPct > 0.0) ? gRt_DailyDDPct : InpMaxDailyLossPercent;
      if(effectiveLossPct >= ddCeiling)
         return LOCK_DAILY_LOSS;
   }

   //── 3. Global Drawdown Guard (hysteresis) ────────────────────────
   // Blocks new entries when DD > threshold. Releases when DD recovers
   // to 50% of threshold (hysteresis prevents oscillation at boundary).
   if(gPeakEquity > 0.0)
   {
      double ddPct = SafeDiv(gPeakEquity - equity, gPeakEquity) * 100.0;
      if(ddPct >= InpMaxGlobalDrawdownPercent)
      {
         // Block new entries; hysteresis: release only when DD < threshold × 0.50
         return LOCK_GLOBAL_DD;
      }
      // Hysteresis release: was previously in DD guard, now check if recovered to 50%
      // (This is handled in HandleSafetyState — here we just report current state)
   }

   //── 4. Manual Pause ───────────────────────────────────────────────
   if(gBotPaused)
      return LOCK_MANUAL_PAUSE;

   //── 5. Macro Divergence ───────────────────────────────────────────
   if(gSignal.macroDivergent)
      return LOCK_MACRO_DIVERGENCE;

   //── 6. Persistent Spread Shock (5+ consecutive ticks over cap) ───
   if(gSpreadPaused)
      return LOCK_SPREAD;

   //── 7. Stale Indicator Data ───────────────────────────────────────
   // Check if any enabled TF has stale data (ready=false)
   for(int t = 0; t < TF_COUNT; t++)
   {
      if(!gTF[t].enabled) continue;
      if(!gTF[t].ready)
         return LOCK_STALE_DATA;
   }

   //── 8. Spike Detection (v5.0) ─────────────────────────────────────
   if(InpBlockEntryOnSpike && gSpike.spikeDetected)
      return LOCK_SPIKE;

   //── 9. Active News Window (v5.0) ──────────────────────────────────
   if(InpUseNewsFilter && gNews.active)
      return LOCK_NEWS;

   return LOCK_NONE; // ✅ All clear
}

//════════════════════════════════════════════════════════════════════
//  §9.5 — EmergencyCloseAll() — NON-BLOCKING PANIC CLOSE
//  Analysis 2.docx §Async Emergency Close fix:
//  Attempts close for each position in ONE pass (no loop-retry here).
//  Failures are queued to gRetry[] (kind=3) for OnTimer processing.
//  No Sleep(), no blocking retry loops.
//════════════════════════════════════════════════════════════════════

void EmergencyCloseAll(string reason)
{
   PushDiag("🚨 E9: EMERGENCY CLOSE ALL — reason: " + reason);
   JournalWrite("EMERGENCY_CLOSE_ALL", reason,
                "equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));

   // ── Close all open positions (backwards loop for safe deletion) ──
   int posTotal = PositionsTotal();
   for(int i = posTotal - 1; i >= 0; i--)
   {
      ulong tkt = PositionGetTicket(i);
      if(!PositionSelectByTicket(tkt)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol)  continue;

      gTrade.SetExpertMagicNumber((ulong)InpMagic);
      gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints * 3); // wide on emergency
      bool ok = gTrade.PositionClose(tkt);
      int  rc = (int)gTrade.ResultRetcode();

      if(ok)
      {
         PushDiag("✅ E9: Emergency closed position " + IntegerToString(tkt));
         JournalWrite("EMERGENCY_POS_CLOSED", IntegerToString(tkt), reason);
         // Clear the tracking record
         int recIdx = FindRecordByTicket(tkt);
         if(recIdx >= 0) ClearRecord(recIdx);
      }
      else
      {
         PushDiag("⚠️ E9: Emergency close FAILED ticket=" + IntegerToString(tkt)
                  + " rc=" + RetcodeStr(rc) + " → retry queue");

         // Queue panic close for OnTimer retry (kind=3)
         for(int r = 0; r < 64; r++)
         {
            if(gRetry[r].used) continue;
            gRetry[r].used     = true;
            gRetry[r].kind     = 3; // panic close
            gRetry[r].ticket   = tkt;
            gRetry[r].volume   = GetPositionCurrentVolume(tkt);
            gRetry[r].attempts = 0;
            gRetry[r].nextTry  = TimeCurrent() + 2;
            gRetry[r].note     = "EMERGENCY:" + reason;
            break;
         }
      }
   }

   // ── Cancel all pending orders ──────────────────────────────────
   int ordTotal = OrdersTotal();
   for(int i = ordTotal - 1; i >= 0; i--)
   {
      ulong ord = OrderGetTicket(i);
      if(!OrderSelect(ord)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != gSymbol)  continue;

      gTrade.SetExpertMagicNumber((ulong)InpMagic);
      bool ok = gTrade.OrderDelete(ord);
      if(ok)
      {
         JournalWrite("EMERGENCY_ORDER_DELETED", IntegerToString(ord));
         int planIdx = FindPendingByTicket(ord);
         if(planIdx >= 0) ClearPendingPlan(planIdx);
      }
      else
      {
         for(int r = 0; r < 64; r++)
         {
            if(gRetry[r].used) continue;
            gRetry[r].used     = true;
            gRetry[r].kind     = 4; // delete order
            gRetry[r].ticket   = ord;
            gRetry[r].attempts = 0;
            gRetry[r].nextTry  = TimeCurrent() + 2;
            gRetry[r].note     = "EMERGENCY_ORDER:" + reason;
            break;
         }
      }
   }

   // Telegram emergency alert (priority — top of queue)
   string tgMsg = "🚨 EMERGENCY CLOSE ALL\n"
                 + "📌 Symbol: " + gSymbol + "\n"
                 + "💬 Reason: " + reason + "\n"
                 + "💰 Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n"
                 + "⏰ " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   TGEnqueue(MSG_INFO, tgMsg, true /* priority */);

   RegisterSafetyEvent("EMERGENCY_CLOSE", reason);
}

//════════════════════════════════════════════════════════════════════
//  §9.6 — HandleSafetyState()
//  Reacts to the lock state returned by CheckSafetyLockAdvanced().
//  Applies state transitions, triggers emergency actions, and sends
//  Telegram alerts for each distinct new event (prevents spam).
//════════════════════════════════════════════════════════════════════

void HandleSafetyState(ENUM_SAFETY_LOCK lockState)
{
   static ENUM_SAFETY_LOCK lastLock = LOCK_NONE; // detect state transitions

   bool isNewLock = (lockState != lastLock && lockState != LOCK_NONE);

   switch(lockState)
   {
      case LOCK_EQUITY_FLOOR:
         if(!gEmergencyHalt)
         {
            gEmergencyHalt = true; // set halt flag FIRST (prevents recursive trigger)
            PushDiag("🚨🚨 E9: EQUITY FLOOR BREACHED! Halting all trading permanently this session");
            double _p4flr = InpEquityFloor;
            RegisterSafetyEvent("EQUITY_FLOOR_BREACH",
                                "equity=" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)
                                + " floor=$" + DoubleToString(_p4flr, 2));
                        EmergencyCloseAll("EQUITY_FLOOR_BREACH");
            // gEmergencyHalt prevents any further entry or management
         }
         break;

      case LOCK_DAILY_LOSS:
         if(isNewLock)
         {
            PushDiag("💤 E9: Daily loss limit reached — SLEEP MODE activated");
            RegisterSafetyEvent("DAILY_LOSS_LOCK",
                                "dailyPnL=" + DoubleToString(gDailyClosedPnL, 2)
                                + " limit=" + DoubleToString(InpMaxDailyLossPercent, 1) + "%");
            string tgMsg = "💤 SLEEP MODE ACTIVATED\n"
                          + "📌 " + gSymbol + "\n"
                          + "📉 Daily P&L limit reached (" + DoubleToString(InpMaxDailyLossPercent, 1) + "%)\n"
                          + "⏰ Resumes at next day open\n"
                          + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
            TGEnqueue(MSG_LOCK, tgMsg, true);
         }
         break;

      case LOCK_GLOBAL_DD:
      {
         // Hysteresis release: once in DD guard, release at 50% recovery
         double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
         double ddPct   = SafeDiv(gPeakEquity - equity, gPeakEquity) * 100.0;
         double releasePct = InpMaxGlobalDrawdownPercent * 0.50; // 50% of threshold

         if(lastLock == LOCK_GLOBAL_DD && ddPct < releasePct)
         {
            // Hysteresis: DD recovered past release point → lift guard
            PushDiag("✅ E9: DD guard LIFTED via hysteresis: DD=" + DoubleToString(ddPct, 2)
                     + "% < release=" + DoubleToString(releasePct, 2) + "%");
            JournalWrite("DD_GUARD_LIFT",
                         DoubleToString(ddPct, 2) + "%",
                         "release=" + DoubleToString(releasePct, 2) + "%");
            gSafetyLock = LOCK_NONE; // force lift — RunVaultChecks will re-evaluate
            break;
         }

         if(isNewLock)
         {
            PushDiag("🛡️ E9: Global DD guard ACTIVE — no new entries until recovery");
            RegisterSafetyEvent("DD_GUARD_ACTIVATE",
                                "DD=" + DoubleToString(ddPct, 2)
                                + "% limit=" + DoubleToString(InpMaxGlobalDrawdownPercent, 2) + "%");
            string tgMsg = "🛡️ DRAWDOWN GUARD ACTIVE\n"
                          + "📌 " + gSymbol + "\n"
                          + "📉 DD: " + DoubleToString(ddPct, 2)
                          + "% / " + DoubleToString(InpMaxGlobalDrawdownPercent, 2) + "% limit\n"
                          + "🔒 New entries blocked | Management continues\n"
                          + "💰 Equity: $" + DoubleToString(equity, 2) + "\n"
                          + TimeToString(TimeCurrent(), TIME_SECONDS);
            TGEnqueue(MSG_DRAWDOWN, tgMsg, true);
         }
         break;
      }

      case LOCK_SPREAD:
         if(isNewLock)
         {
            PushDiag("📡 E9: Spread lock — " + IntegerToString(gHighSpreadCount)
                     + " consecutive high-spread ticks");
            RegisterSafetyEvent("SPREAD_LOCK",
                                "spread=" + DoubleToString(gBroker.spreadNow, 1)
                                + " cap=" + DoubleToString(gBroker.spreadCap, 1));
         }
         break;

      case LOCK_STALE_DATA:
         if(isNewLock)
         {
            PushDiag("⚠️ E9: Stale data lock — some TF indicators not ready");
            RegisterSafetyEvent("STALE_DATA_LOCK", "Check indicator handles");
         }
         break;

      case LOCK_SPIKE:
         if(isNewLock)
         {
            PushDiag("🚨 E9: Spike lock — " + gSpike.reason);
            RegisterSafetyEvent("SPIKE_LOCK", gSpike.reason);
         }
         break;

      case LOCK_NEWS:
         if(isNewLock)
         {
            PushDiag("📰 E9: News lock active — entries paused");
            RegisterSafetyEvent("NEWS_LOCK", "News window active");
         }
         break;

      case LOCK_NONE:
         // Lock lifted — log transition if previously locked
         if(lastLock != LOCK_NONE && lastLock != LOCK_GLOBAL_DD)
         {
            PushDiag("✅ E9: Safety lock LIFTED — was [" + EnumToString(lastLock) + "]");
            JournalWrite("LOCK_LIFTED", EnumToString(lastLock));
         }
         break;

      default:
         break;
   }

   lastLock = lockState;
}

//════════════════════════════════════════════════════════════════════
//  §9.7 — RunVaultChecks() — MAIN VAULT EVALUATION PIPELINE
//  Called every tick from OnTick hot path (after broker sanity).
//  Sequence:
//    1. Update equity peak
//    2. Update daily stats (day transition detection)
//    3. Evaluate all 9 lock conditions
//    4. Set global gSafetyLock
//    5. Handle state transitions and trigger emergency actions
//════════════════════════════════════════════════════════════════════

void RunVaultChecks()
{
   // Step 1: Track equity peak (for global DD calculation)
   UpdatePeakEquity();

   // Step 2: Daily/weekly stats and day-transition reset
   UpdateDailyStats();

   // Step 3: Evaluate lock state (priority-ordered cascade)
   ENUM_SAFETY_LOCK currentLock = CheckSafetyLockAdvanced();

   // Step 4: Persist to global state (read by TryNewEntry and all engines)
   gSafetyLock = currentLock;

   // Step 5: React to state (emergency actions, Telegram, journal)
   HandleSafetyState(currentLock);
}

//════════════════════════════════════════════════════════════════════
//  §9.8 — OnTradeTransaction Integration Helpers
//  Called from OnTradeTransaction to update P&L tracking and record
//  TP3 / SL hit events (which close positions at broker side).
//════════════════════════════════════════════════════════════════════

//--- Called when a deal closes (DEAL_ENTRY_OUT from OnTradeTransaction)
void OnPositionClosed(ulong ticket, double profit, string dealComment)
{
   // Update daily closed P&L accumulator
   gDailyClosedPnL += profit;
   gTGGrossPnL     += profit;
   gTGTotalTrades++;

   bool isWin = (profit > 0.0);
   if(isWin)
   {
      gTGWinTrades++;
      gConsecWins++;
      gConsecLosses = 0; // reset loss streak on win
      gPerf.winTrades++;
      gPerf.grossProfit += profit;
      if(profit > gTGMaxWin) gTGMaxWin = profit;
   }
   else
   {
      gTGLossTrades++;
      gConsecLosses++;
      gConsecWins = 0;
      gPerf.lossTrades++;
      gPerf.grossLoss += MathAbs(profit);
      if(profit < gTGMaxLoss) gTGMaxLoss = profit;
   }
   gPerf.netProfit = gPerf.grossProfit - gPerf.grossLoss;

   // Find record by ticket and determine close type
   int idx = FindRecordByTicket(ticket);
   string closeType = "UNKNOWN";
   bool isSL = false;

   if(idx >= 0)
   {
      // TP3 hit detection: check if closing price is at/near hardTP3
      double closePrice = PositionGetDouble(POSITION_PRICE_CURRENT); // approximate
      double tp3        = gRec[idx].hardTP3;
      double distToTP3  = MathAbs(closePrice - tp3);

      if(isWin && distToTP3 < gPoint * 5.0)
      {
         closeType = "TP3";
         gPerf.tp3Hits++;
         PushDiag("3️⃣ E8: TP3 hit detected for ticket=" + IntegerToString(ticket));
      }
      else if(!isWin)
      {
         closeType = "SL";
         isSL = true;
         gPerf.slHits++;
      }
      else
      {
         closeType = "MANUAL_OR_TSL";
      }

      ClearRecord(idx); // position fully closed → free the slot
   }

   // Journal the closure
   JournalWrite("DEAL_CLOSE",
                IntegerToString(ticket),
                closeType,
                DoubleToString(profit, 2),
                "consec_losses=" + IntegerToString(gConsecLosses));

   // Telegram exit alert (queued)
   string sideEmoji  = isWin ? "✅" : "❌";
   string closeEmoji = (closeType == "TP3") ? "3️⃣"
                      : (closeType == "SL")  ? "🛑" : "🚪";

   string tgMsg = "══════════════════════════\n"
                 + sideEmoji + " POSITION CLOSED\n"
                 + "──────────────────────────\n"
                 + "📌 " + gSymbol + " | " + closeType + "\n"
                 + "💰 P&L: " + (profit >= 0 ? "+" : "") + DoubleToString(profit, 2) + "\n"
                 + "📊 Session: W=" + IntegerToString(gTGWinTrades)
                 + " L=" + IntegerToString(gTGLossTrades) + "\n"
                 + "📉 Net: " + DoubleToString(gTGGrossPnL, 2) + "\n"
                 + "🔢 ConsecLosses: " + IntegerToString(gConsecLosses) + "\n"
                 + "⏰ " + TimeToString(TimeCurrent(), TIME_SECONDS) + "\n"
                 + "══════════════════════════";

   ENUM_QUEUE_MSG msgType = (closeType == "SL") ? MSG_SL : MSG_EXIT;
   TGEnqueue(msgType, tgMsg, false);

   PushDiag(sideEmoji + " E9: Position closed ticket=" + IntegerToString(ticket)
            + " type=" + closeType
            + " PnL=" + DoubleToString(profit, 2)
            + " consecLoss=" + IntegerToString(gConsecLosses));
}

//--- Called when a deal opens (DEAL_ENTRY_IN from OnTradeTransaction)
//    Used to confirm scalp pending→position fill for plan promotion
void OnDealOpened(ulong dealTicket, ulong posTicket)
{
   // Check if this matches any pending plan (scalp order fill)
   for(int i = 0; i < 20; i++)
   {
      if(!gPlan[i].active) continue;
      // The pending order ticket becomes the position ticket on fill
      // Match by checking if existing plan for this symbol with recent timing
      if(gPlan[i].symbol != gSymbol) continue;
      if(TimeCurrent() - gPlan[i].createdAt > (datetime)InpScalpPendingMaxAgeSec) continue;
      // If position appears and plan exists — likely the fill
      if(FindRecordByTicket(posTicket) < 0) // not yet tracked
      {
         PushDiag("📋 E9: OnDealOpened — scalp fill detected, plan[" + IntegerToString(i)
                  + "] → pos ticket=" + IntegerToString(posTicket));
         // RunAllPositionManagement() will handle promotion on next tick
         break;
      }
   }
}

//════════════════════════════════════════════════════════════════════
//  END OF PART 4 — Engines 7, 8, 9
//  Next: Part 5 — Engines 10 (Broker Sanity), 11 (Regime),
//               12 (Portfolio), 13 (Lot Control), v5.0 engines
//               (Spike Detection, News Filter, Volume Momentum),
//               Symbol Profile Engine
//════════════════════════════════════════════════════════════════════


#endif // SKP_P4_TRADEEXEC_MQH
