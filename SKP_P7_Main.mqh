#ifndef SKP_P7_MAIN_MQH
#define SKP_P7_MAIN_MQH

//+------------------------------------------------------------------+
//| SK_TRADE_PREMIUM_BOT_P7.mq5                                      |
//|                                                                  |
//|  MAIN EVENT HANDLERS — FINAL ASSEMBLY FILE                      |
//|                                                                  |
//|  SECTION 7.1  — Supplemental constants & state globals          |
//|  SECTION 7.2  — CopyBuffer read utilities                       |
//|  SECTION 7.3  — Indicator handle init / release                 |
//|  SECTION 7.4  — Bar data refresh (all 6 timeframes)             |
//|  SECTION 7.5  — Broker position recovery (EA restart)           |
//|  SECTION 7.6  — Closed position reconciliation                  |
//|  SECTION 7.7  — 7-component entry signal scorer                 |
//|  SECTION 7.8  — Entry filter chain (all gates)                  |
//|  SECTION 7.9  — Daily P&L reset                                 |
//|  SECTION 7.10 — OnInit   (10-step initialization)               |
//|  SECTION 7.11 — OnDeinit (full cleanup)                         |
//|  SECTION 7.12 — OnTick   (16-step hot path — no blocking I/O)   |
//|  SECTION 7.13 — OnTimer  (9-step  async path)                   |
//|  SECTION 7.14 — OnTradeTransaction (deal/order processing)      |
//|  SECTION 7.15 — OnChartEvent (dashboard delegation)             |
//|  SECTION 7.16 — Assembly instructions & verification checklist  |
//|                                                                  |
//|  ASSEMBLY ORDER:  P1→P2→P3→P4→P5→P6→P7                        |
//|  This is the LAST file.  Do NOT compile any part standalone.    |
//|                                                                  |
//|  NASA-Grade MQL5 EA — Production Tier Engineering               |
//|  SK TRADE PREMIUM Development Team — Version 6.0 Part 7 (Final) |
//+------------------------------------------------------------------+

//====================================================================
// 7.1  SUPPLEMENTAL CONSTANTS AND STATE GLOBALS
//====================================================================

// Indicator fast/slow EMA periods (core strategy — not exposed as inputs
// to prevent accidental deoptimisation; change only with full backtest)
#define EA_EMA_FAST      9
#define EA_EMA_SLOW      34
#define EA_RSI_PERIOD    14
#define EA_MACD_FAST     12
#define EA_MACD_SLOW     26
#define EA_MACD_SIG      9
#define EA_BB_PERIOD     20
#define EA_BB_SHIFT      0
#define EA_BB_DEVIATION  2.0
#define EA_STOCH_K       5
#define EA_STOCH_D       3
#define EA_STOCH_SLOW    3

// TF_COUNT defined in P1B_COMPAT — not redefined here

// Signal refresh throttle — only recompute full signal on new bar
// (saves CPU; scalp mode uses M5 bar trigger, moderate uses H1 bar trigger)
datetime  gLastSigBarTimeH1   = 0;   // last H1 bar open time at signal compute
datetime  gLastSigBarTimeM5   = 0;   // last M5 bar open time at signal compute
bool      gSigRefreshNeeded   = true;// force first-tick evaluation
ENUM_BIAS gLastBias           = BIAS_NONE; // cached from last ComputeEntrySignal

// Daily session tracking
datetime  gTodayDate          = 0;   // current trading day (DATE portion only)
// gDailyStartBalance declared in P1B_COMPAT shim — do not redeclare here

// Tick counter (for N-tick throttled tasks)
ulong     gTickCount          = 0;

// Portfolio scan interval tracking
datetime  gPortNextScanAt     = 0;   // epoch when next portfolio scan is due

// Pending scalp order expiry check (last time we checked)
datetime  gLastPendingAgeChk  = 0;

// HFT bidirectional engine state — tracks last direction and entry timestamp
// for the bidirectional cooldown gate.  Written by TryNewEntry when placing
// an HFT trade; read by CanAttemptEntry and ComputeHFTEntrySignal.
ENUM_BIAS  gHFTLastEntryBias = BIAS_NONE;   // direction of last confirmed HFT entry
ulong      gHFTLastEntryMs   = 0;            // GetTickCount64() at last HFT entry

// Gate B (EMA touch zone) extra handles for M30 and H2.
// These TFs are not in the main 9-slot TF_COUNT array so they get dedicated handles.
// Initialized in InitAllIndicatorHandles, released in ReleaseAllIndicatorHandles.
int g_hEMA9_M30  = INVALID_HANDLE, g_hEMA21_M30 = INVALID_HANDLE, g_hEMA34_M30 = INVALID_HANDLE;
int g_hEMA9_H2   = INVALID_HANDLE, g_hEMA21_H2  = INVALID_HANDLE, g_hEMA34_H2  = INVALID_HANDLE;

// Broker sanity: last time RefreshBrokerSanity was called from OnTimer
datetime  gLastBrokerSanityAt = 0;
#define   BROKER_SANITY_INTERVAL_SEC  2   // run every 2s from OnTimer

// News filter: last time alert was sent (avoid flooding)
datetime  gLastNewsAlertAt    = 0;
#define   NEWS_ALERT_COOLDOWN_SEC  300

// Spike alert: last time spike Telegram was sent
datetime  gLastSpikeAlertAt   = 0;
#define   SPIKE_ALERT_COOLDOWN_SEC 60

// Regime alert: previous regime for change detection
ENUM_MARKET_REGIME gLastAlertedRegime = REGIME_NORMAL;

//====================================================================
// 7.2  COPYBUFFER READ UTILITIES
//       All indicator reads go through these helpers to ensure uniform
//       error handling and AS_SERIES alignment.  Returns EMPTY_VALUE
//       on any failure; callers must guard against EMPTY_VALUE.
//====================================================================

// Read single value from any indicator buffer (shift=0 → newest closed bar)
double GetBufVal(int handle, int bufIdx, int shift)
{
   if(handle == INVALID_HANDLE) return EMPTY_VALUE;
   double arr[];  // dynamic array — ArraySetAsSeries requires dynamic allocation in MQL5
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, bufIdx, shift, 1, arr) <= 0) return EMPTY_VALUE;
   return arr[0];
}

// Read two consecutive values in one call — arr[0]=shift, arr[1]=shift+1
bool GetBufVal2(int handle, int bufIdx, int shift, double &v0, double &v1)
{
   if(handle == INVALID_HANDLE) return false;
   double arr[];  // dynamic array — ArraySetAsSeries requires dynamic allocation in MQL5
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, bufIdx, shift, 2, arr) < 2) return false;
   v0 = arr[0]; v1 = arr[1];
   return true;
}

// Convenience wrappers for common indicators
double GetEMA9  (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hEMA9,  0, shift); }
double GetEMA21 (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hEMA21, 0, shift); }
double GetEMA34 (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hEMA34, 0, shift); }
double GetRSI   (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hRSI,   0, shift); }
double GetATR   (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hATR,   0, shift); }

// MACD: buffer 0 = main line, buffer 1 = signal line
double GetMACDMain(int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hMACD, 0, shift); }
double GetMACDSig (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hMACD, 1, shift); }

// Bollinger: buffer 0 = base/mid, buffer 1 = upper, buffer 2 = lower
double GetBBMid  (int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hBB, 0, shift); }
double GetBBUpper(int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hBB, 1, shift); }
double GetBBLower(int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hBB, 2, shift); }

// Stochastic: buffer 0 = %K, buffer 1 = %D
double GetStochK(int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hStoch, 0, shift); }
double GetStochD(int tfIdx, int shift) { return GetBufVal(gTF[tfIdx].hStoch, 1, shift); }

//====================================================================
// 7.3  INDICATOR HANDLE INITIALISATION AND RELEASE
//       Creates all per-timeframe handles for gTF[0..TF_COUNT-1].
//       Called ONCE from OnInit.  All handles are persistent for the
//       EA lifetime.  No handles are created in OnTick/OnTimer.
//====================================================================

// Timeframe list aligned with gTF[] indices (IDX_M1=0 … IDX_D1=5, IDX_M3=6 … IDX_M10=8)
// IDX_M1/M5/M15/H1/H4/D1 are #defined in P1.  IDX_M3/M6/M10 are HFT extended.
static const ENUM_TIMEFRAMES TF_LIST[TF_COUNT] =
   { PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1,
     PERIOD_M3,  PERIOD_M6,  PERIOD_M10 };

bool InitAllIndicatorHandles()
{
   bool ok = true;

   for(int i = 0; i < TF_COUNT; i++)
   {
      ENUM_TIMEFRAMES tf = TF_LIST[i];
      gTF[i].tf = tf;

      // EMA 9 (fast)
      gTF[i].hEMA9 = iMA(gSymbol, tf, EA_EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
      if(gTF[i].hEMA9 == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("EMA9 TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // EMA 34 (slow)
      gTF[i].hEMA34 = iMA(gSymbol, tf, EA_EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);
      if(gTF[i].hEMA34 == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("EMA34 TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // EMA 21 — second bias pair for HFT dual-EMA system (EMA9 vs EMA21)
      gTF[i].hEMA21 = iMA(gSymbol, tf, 21, 0, MODE_EMA, PRICE_CLOSE);
      if(gTF[i].hEMA21 == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("EMA21 TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // RSI 14
      gTF[i].hRSI = iRSI(gSymbol, tf, EA_RSI_PERIOD, PRICE_CLOSE);
      if(gTF[i].hRSI == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("RSI TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // ATR (period from input, shared with regime engine)
      gTF[i].hATR = iATR(gSymbol, tf, InpRegimeATRPeriod);
      if(gTF[i].hATR == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("ATR TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // MACD 12/26/9 (only H1 and M5 needed for signal; create all for flexibility)
      gTF[i].hMACD = iMACD(gSymbol, tf, EA_MACD_FAST, EA_MACD_SLOW, EA_MACD_SIG, PRICE_CLOSE);
      if(gTF[i].hMACD == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("MACD TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // Bollinger Bands 20/2.0
      gTF[i].hBB = iBands(gSymbol, tf, EA_BB_PERIOD, EA_BB_SHIFT, EA_BB_DEVIATION, PRICE_CLOSE);
      if(gTF[i].hBB == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("BB TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }

      // Stochastic 5/3/3
      gTF[i].hStoch = iStochastic(gSymbol, tf, EA_STOCH_K, EA_STOCH_D, EA_STOCH_SLOW,
                                   MODE_SMA, STO_LOWHIGH);
      if(gTF[i].hStoch == INVALID_HANDLE)
      { JournalError("InitHandles", StringFormat("Stoch TF=%d ERR=%d", (int)tf, GetLastError())); ok=false; }
   }

   // Gate B extra TF handles (M30, H2 — EMA9/21/34 only, not in TF_COUNT array)
   g_hEMA9_M30  = iMA(gSymbol, PERIOD_M30, EA_EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA21_M30 = iMA(gSymbol, PERIOD_M30, 21,          0, MODE_EMA, PRICE_CLOSE);
   g_hEMA34_M30 = iMA(gSymbol, PERIOD_M30, EA_EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA9_H2   = iMA(gSymbol, PERIOD_H2,  EA_EMA_FAST, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA21_H2  = iMA(gSymbol, PERIOD_H2,  21,          0, MODE_EMA, PRICE_CLOSE);
   g_hEMA34_H2  = iMA(gSymbol, PERIOD_H2,  EA_EMA_SLOW, 0, MODE_EMA, PRICE_CLOSE);
   if(g_hEMA9_M30==INVALID_HANDLE || g_hEMA21_M30==INVALID_HANDLE || g_hEMA34_M30==INVALID_HANDLE ||
      g_hEMA9_H2 ==INVALID_HANDLE || g_hEMA21_H2 ==INVALID_HANDLE || g_hEMA34_H2 ==INVALID_HANDLE)
   { JournalError("InitHandles","GateB extra TF handles FAILED (M30/H2) — check broker data"); ok=false; }
   else
      JournalInfo("InitHandles","GateB extra TF handles OK (M30 + H2 EMA9/21/34)");

   if(ok)
      JournalInfo("InitHandles", StringFormat("All %d×8=%d indicator handles created (incl. EMA21)",
                                               TF_COUNT, TF_COUNT*8));
   else
      JournalError("InitHandles", "One or more handles FAILED — check symbol & broker data");

   return ok;
}

void ReleaseAllIndicatorHandles()
{
   for(int i = 0; i < TF_COUNT; i++)
   {
      if(gTF[i].hEMA9  != INVALID_HANDLE) { IndicatorRelease(gTF[i].hEMA9);  gTF[i].hEMA9  = INVALID_HANDLE; }
      if(gTF[i].hEMA34 != INVALID_HANDLE) { IndicatorRelease(gTF[i].hEMA34); gTF[i].hEMA34 = INVALID_HANDLE; }
      if(gTF[i].hEMA21 != INVALID_HANDLE) { IndicatorRelease(gTF[i].hEMA21); gTF[i].hEMA21 = INVALID_HANDLE; }
      if(gTF[i].hRSI   != INVALID_HANDLE) { IndicatorRelease(gTF[i].hRSI);   gTF[i].hRSI   = INVALID_HANDLE; }
      if(gTF[i].hATR   != INVALID_HANDLE) { IndicatorRelease(gTF[i].hATR);   gTF[i].hATR   = INVALID_HANDLE; }
      if(gTF[i].hMACD  != INVALID_HANDLE) { IndicatorRelease(gTF[i].hMACD);  gTF[i].hMACD  = INVALID_HANDLE; }
      if(gTF[i].hBB    != INVALID_HANDLE) { IndicatorRelease(gTF[i].hBB);    gTF[i].hBB    = INVALID_HANDLE; }
      if(gTF[i].hStoch != INVALID_HANDLE) { IndicatorRelease(gTF[i].hStoch); gTF[i].hStoch = INVALID_HANDLE; }
   }
   // Gate B extra TF handles (M30, H2)
   if(g_hEMA9_M30 !=INVALID_HANDLE){IndicatorRelease(g_hEMA9_M30 );g_hEMA9_M30 =INVALID_HANDLE;}
   if(g_hEMA21_M30!=INVALID_HANDLE){IndicatorRelease(g_hEMA21_M30);g_hEMA21_M30=INVALID_HANDLE;}
   if(g_hEMA34_M30!=INVALID_HANDLE){IndicatorRelease(g_hEMA34_M30);g_hEMA34_M30=INVALID_HANDLE;}
   if(g_hEMA9_H2  !=INVALID_HANDLE){IndicatorRelease(g_hEMA9_H2  );g_hEMA9_H2  =INVALID_HANDLE;}
   if(g_hEMA21_H2 !=INVALID_HANDLE){IndicatorRelease(g_hEMA21_H2 );g_hEMA21_H2 =INVALID_HANDLE;}
   if(g_hEMA34_H2 !=INVALID_HANDLE){IndicatorRelease(g_hEMA34_H2 );g_hEMA34_H2 =INVALID_HANDLE;}
   JournalInfo("ReleaseHandles", "All per-TF indicator handles released");
}

//====================================================================
// 7.4  BAR DATA REFRESH
//       Copies OHLC for both current (shift=0, partial) and completed
//       (shift=1, closed) bars into gTF[i].  Sets newBar flag when
//       bar open time changes.  Called once per tick at the TOP of
//       OnTick before any signal or management logic.
//====================================================================
void RefreshBarData()
{
   for(int i = 0; i < TF_COUNT; i++)
   {
      datetime times[1];
      if(CopyTime(gSymbol, gTF[i].tf, 0, 1, times) < 1) continue;

      gTF[i].newBar = (times[0] != gTF[i].barTime0);
      if(gTF[i].newBar)
      {
         // Shift: previous becomes bar1, incoming becomes bar0
         gTF[i].barTime1 = gTF[i].barTime0;
         gTF[i].open1    = gTF[i].open0;
         gTF[i].high1    = gTF[i].high0;
         gTF[i].low1     = gTF[i].low0;
         gTF[i].close1   = gTF[i].close0;

         gTF[i].barTime0 = times[0];
      }

      // Always refresh current-bar OHLC (partial bar updates every tick)
      // Dynamic arrays required — ArraySetAsSeries cannot be used on static-size arrays in MQL5
      double o[], h[], l[], c[];
      ArraySetAsSeries(o,true); ArraySetAsSeries(h,true);
      ArraySetAsSeries(l,true); ArraySetAsSeries(c,true);

      if(CopyOpen (gSymbol, gTF[i].tf, 0, 1, o) > 0) gTF[i].open0  = o[0];
      if(CopyHigh (gSymbol, gTF[i].tf, 0, 1, h) > 0) gTF[i].high0  = h[0];
      if(CopyLow  (gSymbol, gTF[i].tf, 0, 1, l) > 0) gTF[i].low0   = l[0];
      if(CopyClose(gSymbol, gTF[i].tf, 0, 1, c) > 0) gTF[i].close0 = c[0];
   }
}

//====================================================================
// 7.5  BROKER POSITION RECOVERY  (called once from OnInit)
//       Rebuilds gRec[] from live broker positions after EA restart.
//       Without recovery, the EA cannot manage positions that were
//       opened before the restart — they would drift unprotected.
//====================================================================
void RecoverOpenPositions()
{
   int   recovered = 0;
   ulong magic     = (ulong)InpMagicNumber;

   for(int pi = 0; pi < PositionsTotal(); pi++)
   {
      ulong tkt = PositionGetTicket(pi);
      if(tkt == 0) continue;
      if(!PositionSelectByTicket(tkt)) continue;

      // Only recover positions belonging to this EA on this symbol
      if(PositionGetString(POSITION_SYMBOL) != gSymbol)    continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      // Find a free gRec slot
      int slot = -1;
      for(int si = 0; si < 100; si++)
         if(!gRec[si].active) { slot = si; break; }
      if(slot < 0)
      { JournalError("RecoverPos","gRec[] FULL — cannot recover ticket "+IntegerToString(tkt)); continue; }

      // No local struct reference (MQL5 disallows local &ref) — use gRec[slot] directly
      gRec[slot].active       = true;
      gRec[slot].ticket       = tkt;
      gRec[slot].symbol       = gSymbol;

      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      gRec[slot].posType      = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      gRec[slot].initialVolume= PositionGetDouble(POSITION_VOLUME);  // note: may be reduced if partial closed
      gRec[slot].entryPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
      gRec[slot].stopLoss     = PositionGetDouble(POSITION_SL);
      gRec[slot].hardTP3      = PositionGetDouble(POSITION_TP);
      gRec[slot].tp3Price     = gRec[slot].hardTP3;
      gRec[slot].createdAt    = (datetime)PositionGetInteger(POSITION_TIME);
      gRec[slot].entryReason  = "RECOVERED";

      // Risk distance approximation from preserved SL
      gRec[slot].riskDistance = (gRec[slot].stopLoss > DBL_EPSILON) ?
                       MathAbs(gRec[slot].entryPrice - gRec[slot].stopLoss) : GetATR(IDX_H1, 1) * 1.5;

      // ATR at entry — use current H1 ATR as best approximation
      gRec[slot].atrAtEntry   = GetATR(IDX_H1, 1);

      // Determine mode (scalp or moderate) from spread at entry (unknown → use symbol preset)
      bool isScalp = false;
      string presetList = InpPresetScalpList;
      if(StringLen(presetList) > 0)
      {
         string arr[]; int n = StringSplit(presetList, ',', arr);
         for(int si2=0; si2<n; si2++)
         {
            string tmp = arr[si2];
            StringTrimLeft(tmp);   // void in MQL5 — modifies in-place
            StringTrimRight(tmp);  // void in MQL5 — modifies in-place
            if(tmp == gSymbol) { isScalp=true; break; }
         }
      }
      gRec[slot].isScalpMode  = isScalp;

      // Estimate TP1/TP2 from 1R/2R if not available
      double rD = gRec[slot].riskDistance;
      if(gRec[slot].posType == ORDER_TYPE_BUY)
      {
         gRec[slot].tp1Price = gRec[slot].entryPrice + rD * 1.0;
         gRec[slot].tp2Price = gRec[slot].entryPrice + rD * 2.0;
      }
      else
      {
         gRec[slot].tp1Price = gRec[slot].entryPrice - rD * 1.0;
         gRec[slot].tp2Price = gRec[slot].entryPrice - rD * 2.0;
      }

      // Detect pre-existing breakeven (SL at or past entry)
      if(gRec[slot].posType == ORDER_TYPE_BUY  && gRec[slot].stopLoss >= gRec[slot].entryPrice - gPoint * 2) gRec[slot].breakEvenSet = true;
      if(gRec[slot].posType == ORDER_TYPE_SELL && gRec[slot].stopLoss <= gRec[slot].entryPrice + gPoint * 2) gRec[slot].breakEvenSet = true;

      // TSL step from ATR
      gRec[slot].tslStep      = gRec[slot].atrAtEntry * 0.30;
      gRec[slot].bestPrice    = gRec[slot].entryPrice;
      gRec[slot].lastManageAt = TimeLocal();

      // Scalp-specific
      gRec[slot].scalpTSLOnTick = isScalp;
      gRec[slot].softTPMode     = true;
      gRec[slot].softTPPrice    = gRec[slot].tp3Price;

      recovered++;
      JournalInfo("RecoverPos", StringFormat("Slot[%d] TKT=%llu %s V=%.2f E=%.5f SL=%.5f TP3=%.5f BE=%s",
                                              slot, tkt,
                                              gRec[slot].posType==ORDER_TYPE_BUY?"BUY":"SEL",
                                              gRec[slot].initialVolume, gRec[slot].entryPrice,
                                              gRec[slot].stopLoss, gRec[slot].hardTP3,
                                              gRec[slot].breakEvenSet?"YES":"no"));
   }

   if(recovered > 0)
      JournalInfo("RecoverPos", StringFormat("Recovered %d open position(s) from broker", recovered));
   else
      JournalInfo("RecoverPos", "No positions to recover — clean start");
}

//====================================================================
// 7.6  CLOSED POSITION RECONCILIATION  (called every tick)
//       Scans gRec[] for positions that are active in our records
//       but no longer present in the broker terminal.  When found:
//       — fetches PnL from deal history
//       — classifies close reason (TP1/TP2/TP3/SL/REVERSE/MANUAL)
//       — fires Telegram alert and updates gPerf
//       — marks gRec[slot].active = false
//====================================================================
void CheckPositionsClosed()
{
   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active) continue;

      // Fast broker check: does position still exist?
      if(PositionSelectByTicket(gRec[i].ticket)) continue;   // still open

      // Position gone — determine closure reason and PnL from history
      double closedPnL  = 0.0;
      string closeReason= "UNKNOWN";

      if(HistorySelectByPosition(gRec[i].ticket))
      {
         int dealsTotal = HistoryDealsTotal();
         for(int di = dealsTotal - 1; di >= 0; di--)
         {
            ulong  dTkt    = HistoryDealGetTicket(di);
            if(!HistoryDealSelect(dTkt)) continue;
            ulong  dPosId  = (ulong)HistoryDealGetInteger(dTkt, DEAL_POSITION_ID);
            if(dPosId != gRec[i].ticket) continue;

            ENUM_DEAL_ENTRY dEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dTkt, DEAL_ENTRY);
            if(dEntry != DEAL_ENTRY_OUT && dEntry != DEAL_ENTRY_INOUT) continue;

            closedPnL  += HistoryDealGetDouble(dTkt, DEAL_PROFIT)
                        + HistoryDealGetDouble(dTkt, DEAL_COMMISSION)
                        + HistoryDealGetDouble(dTkt, DEAL_SWAP);

            string comment = HistoryDealGetString(dTkt, DEAL_COMMENT);
            if(StringFind(comment, "sl") >= 0 || StringFind(comment, "SL") >= 0)
               closeReason = "SL";
            else if(StringFind(comment, "tp") >= 0 || StringFind(comment, "TP") >= 0)
               closeReason = "TP3";
            else if(gRec[i].tp2Hit)
               closeReason = "TSL_OR_MANUAL";
            else
               closeReason = "MANUAL";
         }
      }

      // Update session performance metrics
      gDailyClosedPnL += closedPnL;
      gPerf.totalTrades++;
      if(closedPnL >= 0) { gPerf.winTrades++;  gConsecWins++;  gConsecLosses = 0; gPerf.totalProfit += closedPnL; }
      else               { gPerf.lossTrades++; gConsecLosses++; gConsecWins  = 0; gPerf.totalLoss   += closedPnL; }
      if(closedPnL > gPerf.bestTrade)  gPerf.bestTrade  = closedPnL;
      if(closedPnL < gPerf.worstTrade) gPerf.worstTrade = closedPnL;

      // Telegram alert
      if(closeReason == "SL")
         TGAlert_StopLoss(i, closedPnL);
      else
         TGAlert_TP3Hit(i, closedPnL);

      JournalInfo("ClosedPos", StringFormat("TKT=%llu  PnL=%.2f  Reason=%s  W:%d L:%d",
                                             gRec[i].ticket, closedPnL, closeReason,
                                             gConsecWins, gConsecLosses));

      // Mark slot free
      gRec[i].active  = false;
      gRec[i].ticket  = 0;

      UINeedRedraw();
   }
}

//====================================================================
// 7.7  7-COMPONENT ENTRY SIGNAL SCORER
//       Computes total score [0..85] and fills gScoreComp[7].
//       Sets gLastScore.  Returns dominant bias (BULL/BEAR/NONE).
//       USES shift=1 (completed bars) for all indicator reads to
//       avoid acting on partially formed bar values.
//
//       Component weights (max points, ± direction):
//         [0] EMA Cross H1+M5   max ±20
//         [1] RSI H1            max ±15
//         [2] MACD H1           max ±15
//         [3] Bollinger H1      max ±10
//         [4] Stochastic H1     max ±10
//         [5] Volume Momentum   max ±10
//         [6] Regime Adjust     max  +5 (additive, not directional)
//         SPIKE PENALTY         −30  (applied post-sum if spikeActive)
//         TOTAL MAX             = 85 pts
//====================================================================

// Sub-scorer 1: EMA Cross (H1 primary, M5 confirmation) → ±20 pts
int ScoreEMACross(ENUM_BIAS &emaBias)
{
   int score = 0;

   // H1: primary trend direction
   double h1_e9_0 = GetEMA9 (IDX_H1, 1);   double h1_e9_1 = GetEMA9 (IDX_H1, 2);
   double h1_e34_0= GetEMA34(IDX_H1, 1);   double h1_e34_1= GetEMA34(IDX_H1, 2);

   bool h1Valid = (h1_e9_0!=EMPTY_VALUE && h1_e34_0!=EMPTY_VALUE &&
                   h1_e9_1!=EMPTY_VALUE && h1_e34_1!=EMPTY_VALUE);

   int h1Dir = 0;
   bool h1FreshCross = false;
   if(h1Valid)
   {
      if(h1_e9_0 > h1_e34_0) h1Dir = 1;
      else if(h1_e9_0 < h1_e34_0) h1Dir = -1;

      // Fresh cross: previous relationship was OPPOSITE
      if(h1Dir == 1  && h1_e9_1 <= h1_e34_1) h1FreshCross = true;
      if(h1Dir == -1 && h1_e9_1 >= h1_e34_1) h1FreshCross = true;

      score += h1Dir * (h1FreshCross ? 12 : 8);   // fresh cross premium
   }

   // M5: confirmation filter — only add if SAME direction as H1
   double m5_e9_0 = GetEMA9 (IDX_M5, 1);   double m5_e9_1 = GetEMA9 (IDX_M5, 2);
   double m5_e34_0= GetEMA34(IDX_M5, 1);   double m5_e34_1= GetEMA34(IDX_M5, 2);

   bool m5Valid = (m5_e9_0!=EMPTY_VALUE && m5_e34_0!=EMPTY_VALUE &&
                   m5_e9_1!=EMPTY_VALUE && m5_e34_1!=EMPTY_VALUE);
   if(m5Valid)
   {
      int m5Dir = 0;
      if(m5_e9_0 > m5_e34_0) m5Dir = 1;
      else if(m5_e9_0 < m5_e34_0) m5Dir = -1;

      bool m5FreshCross = false;
      if(m5Dir== 1 && m5_e9_1<=m5_e34_1) m5FreshCross=true;
      if(m5Dir==-1 && m5_e9_1>=m5_e34_1) m5FreshCross=true;

      if(m5Dir == h1Dir)   // aligned confirmation
         score += m5Dir * (m5FreshCross ? 6 : 4);
      // Divergent M5 vs H1: no penalty (just no bonus) — H1 dominates
   }

   // EMA separation magnitude bonus (trend strength)
   if(h1Valid && h1Dir != 0)
   {
      double sep = MathAbs(h1_e9_0 - h1_e34_0) / gPoint;
      double atr = GetATR(IDX_H1, 1);
      if(atr > DBL_EPSILON)
      {
         double sepRatio = SafeDiv(sep * gPoint, atr);
         if(sepRatio > 0.30) score += h1Dir * 2;  // meaningful separation bonus (capped)
      }
   }

   // Clamp component to ±20
   score = MathMax(-20, MathMin(20, score));
   emaBias = (score > 3) ? BIAS_BULL : (score < -3) ? BIAS_BEAR : BIAS_NONE;
   return score;
}

// Sub-scorer 2: RSI H1 → ±15 pts
int ScoreRSI(ENUM_BIAS emaBias)
{
   double rsi1 = GetRSI(IDX_H1, 1);   // current completed bar
   double rsi2 = GetRSI(IDX_H1, 2);   // previous bar (for momentum direction)
   if(rsi1 == EMPTY_VALUE) return 0;

   double rsiMom = (rsi2 != EMPTY_VALUE) ? (rsi1 - rsi2) : 0;   // rising or falling
   int    score  = 0;

   if(emaBias == BIAS_BULL)
   {
      if     (rsi1 >= 50 && rsi1 < 65) score = 15;           // sweet spot: bullish, not overbought
      else if(rsi1 >= 65 && rsi1 < 72) score = 10;           // elevated but tradeable
      else if(rsi1 >= 72 && rsi1 < 80) score = 3;            // overbought caution
      else if(rsi1 >= 80)              score = -10;           // extreme overbought: penalise longs
      else if(rsi1 >= 40 && rsi1 < 50) score = 2;            // sub-50 but near neutral
      else                             score = -8;            // below 40 with bull bias = divergence
   }
   else if(emaBias == BIAS_BEAR)
   {
      if     (rsi1 >  35 && rsi1 <= 50) score = -15;
      else if(rsi1 >  28 && rsi1 <= 35) score = -10;
      else if(rsi1 >  20 && rsi1 <= 28) score = -3;
      else if(rsi1 <= 20)               score = 10;           // extreme oversold: penalise shorts
      else if(rsi1 >  50 && rsi1 <= 60) score = -2;
      else                              score = 8;
   }
   else
   {
      // No bias: pure RSI momentum signal
      if(rsi1 > 60) score = 8;
      else if(rsi1 < 40) score = -8;
   }

   // Momentum confirmation: RSI moving in bias direction
   if(emaBias == BIAS_BULL && rsiMom > 0 && score > 0) score = MathMin(score+2, 15);
   if(emaBias == BIAS_BEAR && rsiMom < 0 && score < 0) score = MathMax(score-2, -15);

   // M5 RSI micro-confirmation
   double rsiM5 = GetRSI(IDX_M5, 1);
   if(rsiM5 != EMPTY_VALUE)
   {
      if(emaBias == BIAS_BULL && rsiM5 > 50 && score > 0) score = MathMin(score+2, 15);
      if(emaBias == BIAS_BEAR && rsiM5 < 50 && score < 0) score = MathMax(score-2, -15);
   }

   return MathMax(-15, MathMin(15, score));
}

// Sub-scorer 3: MACD H1 → ±15 pts
int ScoreMACD(ENUM_BIAS emaBias)
{
   double macdMain0 = GetMACDMain(IDX_H1, 1);
   double macdMain1 = GetMACDMain(IDX_H1, 2);
   double macdSig0  = GetMACDSig (IDX_H1, 1);
   double macdSig1  = GetMACDSig (IDX_H1, 2);
   if(macdMain0==EMPTY_VALUE || macdSig0==EMPTY_VALUE) return 0;

   int score = 0;

   // Main vs Signal line position
   bool   macdAboveSig = (macdMain0 > macdSig0);
   bool   freshMACross = false;
   if(macdMain1 != EMPTY_VALUE && macdSig1 != EMPTY_VALUE)
      freshMACross = (macdAboveSig && macdMain1 <= macdSig1) ||
                     (!macdAboveSig && macdMain1 >= macdSig1);

   if(emaBias == BIAS_BULL)
   {
      if(macdAboveSig)                  score += freshMACross ? 10 : 7;
      if(macdMain0 > 0)                 score += 4;              // above zero line
      if(macdMain1!=EMPTY_VALUE &&
         macdMain0 > macdMain1)         score += 2;              // histogram expanding
   }
   else if(emaBias == BIAS_BEAR)
   {
      if(!macdAboveSig)                 score -= freshMACross ? 10 : 7;
      if(macdMain0 < 0)                 score -= 4;
      if(macdMain1!=EMPTY_VALUE &&
         macdMain0 < macdMain1)         score -= 2;
   }
   else
   {
      // Unbiased: pure MACD direction
      if(macdAboveSig && macdMain0>0)   score = 8;
      else if(!macdAboveSig && macdMain0<0) score = -8;
      else if(macdAboveSig)             score = 4;
      else                              score = -4;
   }

   return MathMax(-15, MathMin(15, score));
}

// Sub-scorer 4: Bollinger Bands H1 → ±10 pts
int ScoreBollinger(ENUM_BIAS emaBias)
{
   double mid   = GetBBMid  (IDX_H1, 1);
   double upper = GetBBUpper(IDX_H1, 1);
   double lower = GetBBLower(IDX_H1, 1);
   double close = gTF[IDX_H1].close1;   // confirmed bar close
   if(mid==EMPTY_VALUE || upper==EMPTY_VALUE || close==0) return 0;

   int score = 0;

   // Price position relative to middle band
   double bandwidth  = (upper - lower);
   double midPos     = SafeDiv(close - lower, bandwidth);  // 0=lower, 0.5=mid, 1=upper

   if(emaBias == BIAS_BULL)
   {
      if(close > mid)   score += 6;   // above midline
      if(midPos > 0.60) score += 3;   // in upper half
      if(midPos > 0.85) score -= 4;   // near upper band: over-extension risk
      // Rising middle band (trend confirmation)
      double mid1 = GetBBMid(IDX_H1, 2);
      if(mid1 != EMPTY_VALUE && mid > mid1) score += 1;
   }
   else if(emaBias == BIAS_BEAR)
   {
      if(close < mid)   score -= 6;
      if(midPos < 0.40) score -= 3;
      if(midPos < 0.15) score += 4;   // near lower band: over-extension
      double mid1 = GetBBMid(IDX_H1, 2);
      if(mid1 != EMPTY_VALUE && mid < mid1) score -= 1;
   }
   else
   {
      // Unbiased: band position drive
      if(midPos > 0.65)      score = 6;
      else if(midPos < 0.35) score = -6;
   }

   return MathMax(-10, MathMin(10, score));
}

// Sub-scorer 5: Stochastic H1 → ±10 pts
int ScoreStochastic(ENUM_BIAS emaBias)
{
   double k0 = GetStochK(IDX_H1, 1);   double k1 = GetStochK(IDX_H1, 2);
   double d0 = GetStochD(IDX_H1, 1);   double d1 = GetStochD(IDX_H1, 2);
   if(k0==EMPTY_VALUE || d0==EMPTY_VALUE) return 0;

   int  score     = 0;
   bool kAboveD   = (k0 > d0);
   bool freshCross= false;
   if(k1!=EMPTY_VALUE && d1!=EMPTY_VALUE)
      freshCross = (kAboveD && k1<=d1) || (!kAboveD && k1>=d1);

   if(emaBias == BIAS_BULL)
   {
      if(kAboveD)             score += freshCross ? 7 : 5;
      if(k0 >= 20 && k0 < 80) score += 3;    // not in extreme zone: healthy momentum
      if(k0 >= 80)            score -= 5;     // overbought: penalise bull entry
      if(k1!=EMPTY_VALUE && k0 > k1) score += 1;   // K rising
   }
   else if(emaBias == BIAS_BEAR)
   {
      if(!kAboveD)             score -= freshCross ? 7 : 5;
      if(k0 >  20 && k0 < 80) score -= 3;
      if(k0 <= 20)             score += 5;    // oversold: penalise bear entry
      if(k1!=EMPTY_VALUE && k0 < k1) score -= 1;
   }
   else
   {
      if(kAboveD && k0 > 50)   score = 6;
      else if(!kAboveD && k0 < 50) score = -6;
   }

   return MathMax(-10, MathMin(10, score));
}

// Sub-scorer 6: Volume Momentum (from Engine v5.0c) → ±10 pts
int ScoreVolumeMomentum(ENUM_BIAS emaBias)
{
   if(!gVolMom.bullConfirmed && !gVolMom.bearConfirmed) return 0;  // neutral volume

   double ratio  = gVolMom.ratio;     // currentVol / avgVol
   int    maxPts = 10;

   // Scale score by ratio strength (ratio 1.3 = base, 2.0+ = full score)
   double ratioNorm = MathMin(SafeDiv(ratio - 1.0, 1.0), 1.0);  // 0 at ratio=1, 1 at ratio=2
   int    volPts    = (int)MathRound(maxPts * ratioNorm);

   if(emaBias == BIAS_BULL && gVolMom.bullConfirmed) return  volPts;
   if(emaBias == BIAS_BEAR && gVolMom.bearConfirmed) return -volPts;

   // Divergence: volume direction opposes EMA bias → small penalty
   if(emaBias == BIAS_BULL && gVolMom.bearConfirmed) return -MathMin(volPts/2, 4);
   if(emaBias == BIAS_BEAR && gVolMom.bullConfirmed) return  MathMin(volPts/2, 4);

   return 0;
}

// Sub-scorer 7: Regime adjustment → additive ±5
int ScoreRegimeAdj()
{
   return RegimeScoreAdjustment();   // defined in P5 Engine 11
}

//====================================================================
// 7.7b  HFT SEPARATE SIGNAL ENGINE — ComputeHFTEntrySignal()
//        Completely independent from the MODERATE/SCALPER scorer.
//        v6.3b: Uses M1/M3/M5/M6/M10/M15 (6 short timeframes).
//        M3/M6/M10 are HFT extended TFs (IDX 6-8) — added in v6.3b.
//        Higher TF data (H1/H4/D1) deliberately excluded — HFT can
//        go counter-trend on higher TFs for maximum short-burst capture.
//
//        Component weights (total honest max = 90 pts):
//          [0] M1 EMA9/34 cross + M15 alignment     max ±25
//          [1] M5 EMA9/34 alignment + cross          max ±15
//          [2] M1 RSI momentum                       max ±12
//          [3] M1 candle patterns (engulf/pin/burst) max ±10
//          [4] BSP M1+M5 composite pressure           max  ±8
//          [5] M1 MACD micro-cross                   max  ±8
//          [6] Volume momentum burst (gVolMom)        max  ±7
//          [7] M1 ATR vs M5 ATR volatility sweet-spot max  ±5
//          SPIKE PENALTY                              −30
//
//        Bidirectional: positive raw = BULL, negative raw = BEAR.
//        MathAbs(raw) is the gate score — same convention as main engine.
//        outBias anchored to M1 EMA9/34; overridden if score strongly
//        diverges (>15 pts opposite sign) — avoids stale-bias mismatch.
//====================================================================
// 7.7a  EMA TOUCH ZONE CHECK  (v6.4)
// Checks if bid is within InpHFTEMATouchATR × ATR(M1) of any EMA9/21/34
// on M1, M3, or M5 and that EMA is in the OPPOSITE direction to tradeBias.
//
// Returns:
//   0 = no opposing zone — proceed normally
//   1 = in opposing zone, no rejection — BLOCK (return BIAS_NONE)
//   2 = in opposing zone, rejection candle detected — FLIP bias
//
// Called from ComputeHFTEntrySignal AFTER dual-pair bias is set.
//====================================================================
int CheckEMATouchZoneHFT(ENUM_BIAS tradeBias)
{
   if(!InpHFTBlockEMATouchOpposite) return 0;
   if(tradeBias == BIAS_NONE)       return 0;

   double bid  = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   double atrM1 = GetATR(IDX_M1, 1);
   if(atrM1 <= DBL_EPSILON || atrM1 == EMPTY_VALUE) return 0;

   double zone = InpHFTEMATouchATR * atrM1;

   //── Scan EMA9/21/34 on 10 TFs: M1,M3,M5,M10,M15,M30,H1,H2,H4,D1 ──
   // 8 standard TFs use gTF[] handles; M30/H2 use g_hEMA*_M30/H2 globals.
   // Zone tolerance is always M1-ATR based (execution TF resolution).
   bool   inOpposingZone  = false;
   double hitEMAPrice     = 0.0;

   int h9s[10], h21s[10], h34s[10];
   h9s[0]=gTF[IDX_M1 ].hEMA9;  h21s[0]=gTF[IDX_M1 ].hEMA21;  h34s[0]=gTF[IDX_M1 ].hEMA34;
   h9s[1]=gTF[IDX_M3 ].hEMA9;  h21s[1]=gTF[IDX_M3 ].hEMA21;  h34s[1]=gTF[IDX_M3 ].hEMA34;
   h9s[2]=gTF[IDX_M5 ].hEMA9;  h21s[2]=gTF[IDX_M5 ].hEMA21;  h34s[2]=gTF[IDX_M5 ].hEMA34;
   h9s[3]=gTF[IDX_M10].hEMA9;  h21s[3]=gTF[IDX_M10].hEMA21;  h34s[3]=gTF[IDX_M10].hEMA34;
   h9s[4]=gTF[IDX_M15].hEMA9;  h21s[4]=gTF[IDX_M15].hEMA21;  h34s[4]=gTF[IDX_M15].hEMA34;
   h9s[5]=g_hEMA9_M30;          h21s[5]=g_hEMA21_M30;          h34s[5]=g_hEMA34_M30;
   h9s[6]=gTF[IDX_H1 ].hEMA9;  h21s[6]=gTF[IDX_H1 ].hEMA21;  h34s[6]=gTF[IDX_H1 ].hEMA34;
   h9s[7]=g_hEMA9_H2;           h21s[7]=g_hEMA21_H2;           h34s[7]=g_hEMA34_H2;
   h9s[8]=gTF[IDX_H4 ].hEMA9;  h21s[8]=gTF[IDX_H4 ].hEMA21;  h34s[8]=gTF[IDX_H4 ].hEMA34;
   h9s[9]=gTF[IDX_D1 ].hEMA9;  h21s[9]=gTF[IDX_D1 ].hEMA21;  h34s[9]=gTF[IDX_D1 ].hEMA34;

   for(int t = 0; t < 10 && !inOpposingZone; t++)
   {
      double ema9  = GetBufVal(h9s[t],  0, 1);
      double ema21 = GetBufVal(h21s[t], 0, 1);
      double ema34 = GetBufVal(h34s[t], 0, 1);

      double emas[3]; emas[0]=ema9; emas[1]=ema21; emas[2]=ema34;

      for(int e = 0; e < 3; e++)
      {
         if(emas[e] == EMPTY_VALUE || emas[e] <= 0.0) continue;
         if(MathAbs(bid - emas[e]) > zone)            continue;

         // In touch range — is this EMA resistance (BUY) or support (SELL)?
         bool emaAbove     = (emas[e] > bid);
         bool opposingZone = (tradeBias == BIAS_BULL && emaAbove) ||
                             (tradeBias == BIAS_BEAR && !emaAbove);

         if(opposingZone)
         {
            inOpposingZone = true;
            hitEMAPrice    = emas[e];
            break;
         }
      }
   }

   if(!inOpposingZone) return 0;   // no opposing EMA nearby

   if(!InpHFTAllowRejectionTrade)
   {
      JournalInfo("EMAZone", StringFormat(
         "BLOCKED — price %.5f in opposing EMA zone (EMA=%.5f zone=%.5f)",
         bid, hitEMAPrice, zone));
      return 1;
   }

   double bounceThresh = InpHFTEMARejectionPips * gPoint;   // broker points → price
   bool   rejectionOK  = false;
   string rejSrc       = "";

   //── Test 1: live bar (bar[0]) — trade can fire WITHIN the rejection candle ──
   // Uses current bid as the live "close". Detects bounce already forming this bar.
   {
      double o0    = iOpen(gSymbol, PERIOD_M1, 0);
      double h0    = iHigh(gSymbol, PERIOD_M1, 0);
      double l0    = iLow (gSymbol, PERIOD_M1, 0);
      double range0 = MathMax(h0 - l0, gPoint);

      if(o0 > 0.0)
      {
         if(tradeBias == BIAS_BULL)   // approaching resistance → bearish rejection forming
         {
            // Bounce: high entered zone and price has already fallen bounceThresh below high
            if((h0 - bid) >= bounceThresh) { rejectionOK = true; rejSrc = "bar0-bounce"; }
            // Pin forming: upper wick > 50% range, current price in lower 40%
            double uWick0  = h0 - MathMax(o0, bid);
            double cPos0   = (bid - l0) / range0;
            if(uWick0 > range0 * 0.50 && cPos0 < 0.40) { rejectionOK = true; rejSrc = "bar0-pin"; }
         }
         else  // BIAS_BEAR — approaching support → bullish rejection forming
         {
            // Bounce: low entered zone and price has already risen bounceThresh above low
            if((bid - l0) >= bounceThresh) { rejectionOK = true; rejSrc = "bar0-bounce"; }
            // Pin forming: lower wick > 50% range, current price in upper 60%
            double lWick0  = MathMin(o0, bid) - l0;
            double cPos0   = (bid - l0) / range0;
            if(lWick0 > range0 * 0.50 && cPos0 > 0.60) { rejectionOK = true; rejSrc = "bar0-pin"; }
         }
      }
   }

   //── Test 2: last closed bar (bar[1]) — classic closed-candle rejection ──────
   if(!rejectionOK)
   {
      double o1 = iOpen (gSymbol, PERIOD_M1, 1);
      double c1 = iClose(gSymbol, PERIOD_M1, 1);
      double h1 = iHigh (gSymbol, PERIOD_M1, 1);
      double l1 = iLow  (gSymbol, PERIOD_M1, 1);

      if(o1 > 0.0 && c1 > 0.0)
      {
         double range1 = MathMax(h1 - l1, gPoint);

         if(tradeBias == BIAS_BULL)
         {
            double uWick1   = h1 - MathMax(o1, c1);
            double closePos1 = (c1 - l1) / range1;
            if(uWick1 > range1 * 0.50 && closePos1 < 0.40) { rejectionOK = true; rejSrc = "bar1-pin"; }
            if((h1 - c1) >= bounceThresh)                   { rejectionOK = true; rejSrc = "bar1-bounce"; }
         }
         else
         {
            double lWick1   = MathMin(o1, c1) - l1;
            double closePos1 = (c1 - l1) / range1;
            if(lWick1 > range1 * 0.50 && closePos1 > 0.60) { rejectionOK = true; rejSrc = "bar1-pin"; }
            if((c1 - l1) >= bounceThresh)                   { rejectionOK = true; rejSrc = "bar1-bounce"; }
         }
      }
   }

   if(rejectionOK)
   {
      JournalInfo("EMAZone", StringFormat(
         "REJECTION [%s] — price %.5f bounced from EMA %.5f → bias FLIPPED to %s",
         rejSrc, bid, hitEMAPrice,
         tradeBias == BIAS_BULL ? "BEAR" : "BULL"));
      return 2;
   }

   // In zone but no rejection signal yet — block
   JournalInfo("EMAZone", StringFormat(
      "BLOCKED — in opposing EMA zone (EMA=%.5f), no rejection signal yet",
      hitEMAPrice));
   return 1;
}

//====================================================================
// 7.7c  HFT PURE SIGNAL ENGINE  (v6.5 — pressure-primary)
// ── GATE-ONLY MODE — no scoring, no threshold, just true/false. ──
//
// Returns 100 if ALL gates clear (direction set in outBias).
// Returns 0  if ANY gate blocks  (outBias = BIAS_NONE).
//
// DIRECTION: Sole source is real-time tick pressure dominance.
//   ratio ≥ InpHFTPressureMin (60%) → BULL
//   ratio ≤ 1 - InpHFTPressureMin  (40%) → BEAR
//   anything in between → no trade (indecisive market)
//   IsValid()=false (<5 ticks this bar) → wait silently, no trade
//
// Gate B  Touch zone: block if price in opposing EMA9/21/34 zone.
//                     Rejection candle at that level → counter-trade.
// Gate C  Spread:     live spread ≤ InpHFTMaxSpreadPts (fixed cap).
// Gate E  Volume:     last-closed M1 bar vol ≥ InpHFTMinVolRatio × 14-bar avg.
//
// All remaining safety checks (news, daily loss, max trades, safety lock,
// blackout, manual pause) are handled by the existing CanAttemptEntry()
// pipeline — no duplication needed here.
//====================================================================
int ComputeHFTPureSignal(ENUM_BIAS &outBias)
{
   outBias = BIAS_NONE;
   gHFTIsRejectionTrade = false;

   // State-change suppression: logs only when gate result changes.
   // key: 1=GateB-block, 2=GateC-block, 4=GateE-block,
   //      5=clear-BULL, 6=clear-BEAR, 8=pressure-indecisive
   static int s_lastKey = -1;

   // ── DIRECTION: Tick pressure dominance ────────────────────────
   // Wait silently until 5+ ticks classified in current bar.
   if(!gPressEng.IsValid())
   {
      gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
      return 0;
   }

   double ratio    = gPressEng.GetRatio();   // buy-tick fraction [0.0–1.0]
   ENUM_BIAS pureBias = BIAS_NONE;

   if(ratio >= InpHFTPressureMin)
      pureBias = BIAS_BULL;
   else if(ratio <= (1.0 - InpHFTPressureMin))
      pureBias = BIAS_BEAR;
   else
   {
      // Pressure indecisive — market not clearly directional, no trade
      if(8 != s_lastKey)
      {
         JournalInfo("HFTPure", StringFormat(
            "Direction: INDECISIVE — pressure %.1f%% (need ≥ %.0f%% buy or ≥ %.0f%% sell)",
            ratio * 100.0, InpHFTPressureMin * 100.0, InpHFTPressureMin * 100.0));
         s_lastKey = 8;
      }
      gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
      return 0;
   }

   // ── Gate B: EMA touch zone / rejection ────────────────────────
   // Blocks entry INTO opposing EMA S/R zone.
   // Rejection candle at that zone → flip to counter-trade.
   int zoneResult = CheckEMATouchZoneHFT(pureBias);
   if(zoneResult == 1)
   {
      if(1 != s_lastKey)
      {
         JournalInfo("HFTPure", StringFormat(
            "GateB: BLOCKED — pressure=%s but price in opposing EMA zone (no rejection)",
            pureBias == BIAS_BULL ? "BUY" : "SELL"));
         s_lastKey = 1;
      }
      gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
      return 0;
   }
   if(zoneResult == 2)
   {
      pureBias             = (pureBias == BIAS_BULL) ? BIAS_BEAR : BIAS_BULL;
      gHFTIsRejectionTrade = true;
   }

   // ── Gate C: Spread (fixed absolute cap) ────────────────────────
   double rawSpreadPts = (SymbolInfoDouble(gSymbol, SYMBOL_ASK) -
                          SymbolInfoDouble(gSymbol, SYMBOL_BID)) / MathMax(gPoint, DBL_EPSILON);
   if(rawSpreadPts > InpHFTMaxSpreadPts)
   {
      if(2 != s_lastKey)
      {
         JournalInfo("HFTPure", StringFormat("GateC: BLOCKED — spread %.1f pts > cap %.1f pts",
            rawSpreadPts, InpHFTMaxSpreadPts));
         s_lastKey = 2;
      }
      gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
      return 0;
   }

   // ── Gate E: Volume activity ratio ──────────────────────────────
   // Blocks trades on dead-quiet bars (low volume = unreliable pressure reading).
   double volRatioE = 1.0;
   if(InpHFTVolActivityGate)
   {
      long volBar1 = iVolume(gSymbol, PERIOD_M1, 1);
      if(volBar1 > 0)
      {
         double volSum = 0.0;
         int    volN   = 0;
         for(int _v = 1; _v <= 14; _v++)
         {
            long vv = iVolume(gSymbol, PERIOD_M1, _v);
            if(vv > 0) { volSum += (double)vv; volN++; }
         }
         if(volN >= 3)
         {
            double volAvg = volSum / volN;
            volRatioE     = (double)volBar1 / volAvg;
            if(volRatioE < InpHFTMinVolRatio)
            {
               if(4 != s_lastKey)
               {
                  JournalInfo("HFTPure", StringFormat(
                     "GateE: BLOCKED — vol ratio %.2f < min %.2f (bar1=%I64d avg=%.1f)",
                     volRatioE, InpHFTMinVolRatio, volBar1, volAvg));
                  s_lastKey = 4;
               }
               gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
               return 0;
            }
         }
      }
   }

   // ── All gates clear — fire ─────────────────────────────────────
   outBias       = pureBias;
   gLastBias     = pureBias;
   gLastScore    = 100;
   gLastRawScore = 100;
   int clearKey  = (pureBias == BIAS_BULL) ? 5 : 6;
   if(clearKey != s_lastKey)
   {
      JournalInfo("HFTPure", StringFormat(
         "ALL GATES CLEAR → %s | pressure=%.1f%% spread=%.1fpts vol=%.2f%s",
         pureBias == BIAS_BULL ? "BULL" : "BEAR",
         ratio * 100.0, rawSpreadPts, volRatioE,
         gHFTIsRejectionTrade ? " [EMA-rejection]" : ""));
      s_lastKey = clearKey;
   }
   return 100;
}

//====================================================================
// 7.7b  HFT ENTRY SIGNAL ENGINE  (v6.4)
// Timeframes: ONLY 1M, 3M, 5M, 6M, 10M, 15M  — no H1/H4/D1 ever.
// comps[11]:  [0..7] = standard components (written to gScoreComp[])
//             [8]  = M3 EMA bridge confirmation   → ±8
//             [9]  = M6 RSI momentum cross        → ±6
//             [10] = M10 ATR volatility bridge    → ±4
// All 11 contribute to raw score.  gScoreComp[8] stores only [0..7]
// so dashboard and JSON remain unchanged.
// BSP composite: M1×0.20 + M3×0.10 + M5×0.13 + M6×0.10 + M10×0.09
//               + M15×0.08 + tick×0.30 = 1.00
//====================================================================
int ComputeHFTEntrySignal(ENUM_BIAS &outBias)
{
   ENUM_BIAS hftBias = BIAS_NONE;
   int       comps[11];
   ArrayInitialize(comps, 0);

   // ── Comp [0]: DUAL-PAIR EMA BIAS + M15 alignment → ±18 (v6.4) ─────
   // Pair A: M1 EMA9 vs EMA34 — slower, trend-following
   // Pair B: M1 EMA9 vs EMA21 — faster, momentum-leading
   // Both agree     → bias set cleanly (bull/bear)
   // One pair mixed → candle tiebreak: last 3 M1 OR last M3 OR last M5 candle
   //                  At least ONE tiebreak check must pass; direction conflicts → NONE
   {
      double m1e9_0  = GetEMA9 (IDX_M1, 1);  double m1e9_1  = GetEMA9 (IDX_M1, 2);
      double m1e34_0 = GetEMA34(IDX_M1, 1);  double m1e34_1 = GetEMA34(IDX_M1, 2);
      double m1e21_0 = GetEMA21(IDX_M1, 1);  double m1e21_1 = GetEMA21(IDX_M1, 2);
      double m15e9   = GetEMA9 (IDX_M15, 1);
      double m15e34  = GetEMA34(IDX_M15, 1);

      bool pairA_valid = (m1e9_0 != EMPTY_VALUE && m1e34_0 != EMPTY_VALUE &&
                          m1e9_1 != EMPTY_VALUE && m1e34_1 != EMPTY_VALUE);
      bool pairB_valid = (m1e9_0 != EMPTY_VALUE && m1e21_0 != EMPTY_VALUE &&
                          m1e9_1 != EMPTY_VALUE && m1e21_1 != EMPTY_VALUE);
      bool m15Valid    = (m15e9  != EMPTY_VALUE && m15e34  != EMPTY_VALUE);

      if(!pairA_valid && !pairB_valid)
      {
         // Neither pair ready — warm-up
         static datetime lastHFTWarmup = 0;
         if(TimeLocal() - lastHFTWarmup >= 15)
         {
            JournalInfo("HFTEngine", "WARM-UP: M1 EMA pairs not ready — HFT score=0 (normal at startup)");
            PushEAEvent("HFTWarmUp", "WARM-UP: M1 indicators loading, HFT score=0");
            lastHFTWarmup = TimeLocal();
         }
         outBias = BIAS_NONE;
         gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
         return 0;
      }

      bool pairA_bull = pairA_valid ? (m1e9_0 > m1e34_0) : false;
      bool pairB_bull = pairB_valid ? (m1e9_0 > m1e21_0) : false;
      bool pairA_freshCross = pairA_valid && ((pairA_bull && m1e9_1 <= m1e34_1) || (!pairA_bull && m1e9_1 >= m1e34_1));
      bool pairB_freshCross = pairB_valid && ((pairB_bull && m1e9_1 <= m1e21_1) || (!pairB_bull && m1e9_1 >= m1e21_1));

      if(pairA_valid && pairB_valid)
      {
         if(pairA_bull && pairB_bull)
            hftBias = BIAS_BULL;   // both pairs agree BULL
         else if(!pairA_bull && !pairB_bull)
            hftBias = BIAS_BEAR;   // both pairs agree BEAR
         else
         {
            // Mixed pairs — candle tiebreak
            // BUY: last 3 M1 green OR last M3 green OR last M5 green (any one)
            bool m1_3green = (iClose(gSymbol,PERIOD_M1,1)>iOpen(gSymbol,PERIOD_M1,1)) &&
                             (iClose(gSymbol,PERIOD_M1,2)>iOpen(gSymbol,PERIOD_M1,2)) &&
                             (iClose(gSymbol,PERIOD_M1,3)>iOpen(gSymbol,PERIOD_M1,3));
            bool m3green   = (iClose(gSymbol,PERIOD_M3,1)>iOpen(gSymbol,PERIOD_M3,1));
            bool m5green   = (iClose(gSymbol,PERIOD_M5,1)>iOpen(gSymbol,PERIOD_M5,1));
            bool m1_3red   = (iClose(gSymbol,PERIOD_M1,1)<iOpen(gSymbol,PERIOD_M1,1)) &&
                             (iClose(gSymbol,PERIOD_M1,2)<iOpen(gSymbol,PERIOD_M1,2)) &&
                             (iClose(gSymbol,PERIOD_M1,3)<iOpen(gSymbol,PERIOD_M1,3));
            bool m3red     = (iClose(gSymbol,PERIOD_M3,1)<iOpen(gSymbol,PERIOD_M3,1));
            bool m5red     = (iClose(gSymbol,PERIOD_M5,1)<iOpen(gSymbol,PERIOD_M5,1));

            bool buyOK  = m1_3green || m3green || m5green;
            bool sellOK = m1_3red   || m3red   || m5red;

            if     (buyOK && !sellOK)  hftBias = BIAS_BULL;
            else if(sellOK && !buyOK)  hftBias = BIAS_BEAR;
            else                       hftBias = BIAS_NONE;  // ambiguous → suppress

            if(hftBias == BIAS_NONE)
            {
               outBias = BIAS_NONE; gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
               return 0;
            }
            JournalInfo("HFTEngine", StringFormat(
               "Mixed EMA pairs — candle tiebreak → %s (m1x3=%s m3=%s m5=%s)",
               hftBias==BIAS_BULL?"BULL":"BEAR",
               (hftBias==BIAS_BULL?m1_3green:m1_3red)?"YES":"no",
               (hftBias==BIAS_BULL?m3green:m3red)?"YES":"no",
               (hftBias==BIAS_BULL?m5green:m5red)?"YES":"no"));
         }
      }
      else
      {
         // Only one pair ready — use whichever is valid
         if(pairA_valid) hftBias = pairA_bull ? BIAS_BULL : BIAS_BEAR;
         else            hftBias = pairB_bull ? BIAS_BULL : BIAS_BEAR;
      }

      //── EMA Touch Zone check (v6.4) ────────────────────────────────
      // Must run BEFORE scoring so components reflect the (possibly flipped) bias.
      gHFTIsRejectionTrade = false;
      int zoneResult = CheckEMATouchZoneHFT(hftBias);
      if(zoneResult == 1)
      {
         // Blocked by opposing EMA zone, no rejection — suppress signal
         outBias = BIAS_NONE; gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
         return 0;
      }
      if(zoneResult == 2)
      {
         // Rejection candle detected — flip bias to counter-direction
         hftBias = (hftBias == BIAS_BULL) ? BIAS_BEAR : BIAS_BULL;
         gHFTIsRejectionTrade = true;
      }

      //── Comp[0] score: EMA strength + M15 macro + fresh cross bonus ─
      bool   mainBull    = (hftBias == BIAS_BULL);
      bool   freshCross  = (pairA_freshCross || pairB_freshCross);  // either pair just crossed
      bool   m15Bull     = m15Valid ? (m15e9 > m15e34) : mainBull;
      bool   m15Aligned  = (mainBull == m15Bull);

      int sc = mainBull ? 9 : -9;                              // base alignment
      sc    += mainBull ? (freshCross ? 6 : 0) : (freshCross ? -6 : 0);  // fresh cross bonus
      if(m15Valid)
         sc += m15Aligned ? (mainBull ? 3 : -3)
                          : (mainBull ? -2 :  2);              // M15 macro confirmation
      comps[0] = MathMax(-18, MathMin(18, sc));
   }

   // ── Comp [1]: M5 EMA9/34 alignment + cross confirmation → ±15 ───────
   {
      double m5e9_0  = GetEMA9 (IDX_M5, 1);  double m5e9_1  = GetEMA9 (IDX_M5, 2);
      double m5e34_0 = GetEMA34(IDX_M5, 1);  double m5e34_1 = GetEMA34(IDX_M5, 2);

      if(m5e9_0 != EMPTY_VALUE && m5e34_0 != EMPTY_VALUE &&
         m5e9_1 != EMPTY_VALUE && m5e34_1 != EMPTY_VALUE)
      {
         bool m5Bull       = (m5e9_0 > m5e34_0);
         bool m5FreshCross = (m5Bull && m5e9_1 <= m5e34_1) ||
                             (!m5Bull && m5e9_1 >= m5e34_1);
         bool aligned      = (hftBias == BIAS_BULL) ? m5Bull : !m5Bull;

         // v6.3g: Reduced from ±15→±10. M5 EMA is slow relative to HFT entry timing.
         int sc = 0;
         if(aligned)
         {
            sc  = (hftBias == BIAS_BULL) ? 7 : -7;   // was 10
            sc += m5FreshCross ? ((hftBias == BIAS_BULL) ? 3 : -3) : 0;  // was 5
         }
         else
         {
            // BiDir mode: M5 opposing M1 is NEUTRAL — HFT trades M1 micro-structure and is
            // explicitly permitted to go counter M5.  Penalising it double-applies the same
            // HTF bias gate that was deliberately removed from TryNewEntry.
            // Non-BiDir mode: keep the penalty so directional modes stay trend-aligned.
            sc = gRt_HFTBidir ? 0 : ((hftBias == BIAS_BULL) ? -4 : 4);
         }
         comps[1] = MathMax(-10, MathMin(10, sc));
      }
   }

   // ── Comp [2]: M1 RSI momentum → ±12 ────────────────────────────────
   {
      double rsi0 = GetRSI(IDX_M1, 1);
      double rsi1 = GetRSI(IDX_M1, 2);
      if(rsi0 != EMPTY_VALUE)
      {
         int sc = 0;
         if(hftBias == BIAS_BULL)
         {
            if     (rsi0 >= 60)  sc =  8;
            else if(rsi0 >= 50)  sc =  5;
            else if(rsi0 >= 40)  sc = -2;
            else                 sc = -7;
            if(rsi1 != EMPTY_VALUE)
               sc += (rsi0 > rsi1 + 2.0) ? 4 : (rsi0 > rsi1) ? 2 : 0;
            if     (rsi0 >= 80)  sc -= 8;   // overbought
            else if(rsi0 >= 75)  sc -= 4;
         }
         else  // BEAR
         {
            if     (rsi0 <= 40)  sc = -8;
            else if(rsi0 <= 50)  sc = -5;
            else if(rsi0 <= 60)  sc =  2;
            else                 sc =  7;
            if(rsi1 != EMPTY_VALUE)
               sc += (rsi0 < rsi1 - 2.0) ? -4 : (rsi0 < rsi1) ? -2 : 0;
            if     (rsi0 <= 20)  sc += 8;   // oversold
            else if(rsi0 <= 25)  sc += 4;
         }
         comps[2] = MathMax(-12, MathMin(12, sc));
      }
   }

   // ── Comp [3]: M1 candle pattern recognition → ±10 ───────────────────
   {
      double o0 = iOpen (gSymbol, PERIOD_M1, 1);
      double c0 = iClose(gSymbol, PERIOD_M1, 1);
      double h0 = iHigh (gSymbol, PERIOD_M1, 1);
      double l0 = iLow  (gSymbol, PERIOD_M1, 1);
      double o1 = iOpen (gSymbol, PERIOD_M1, 2);
      double c1 = iClose(gSymbol, PERIOD_M1, 2);
      double h1 = iHigh (gSymbol, PERIOD_M1, 2);
      double l1 = iLow  (gSymbol, PERIOD_M1, 2);

      if(o0 > 0 && c0 > 0)
      {
         double range0 = MathMax(h0 - l0, gPoint);
         double body0  = MathAbs(c0 - o0);
         int sc = 0;

         // Bull engulfing: bar[1] bearish, bar[0] bullish body engulfs bar[1]
         if(c1 < o1 && c0 > o0 && c0 > o1 && o0 < c1)
            sc += (hftBias == BIAS_BULL) ?  7 : -3;
         // Bear engulfing
         else if(c1 > o1 && c0 < o0 && o0 > c1 && c0 < o1)
            sc += (hftBias == BIAS_BEAR) ? -7 :  3;

         // Pin bar — hammer (lower wick > 60% range, close in upper 30%)
         double lWick     = MathMin(o0, c0) - l0;
         double uWick     = h0 - MathMax(o0, c0);
         double closePos  = SafeDiv(c0 - l0, range0);
         if(lWick > range0 * 0.60 && body0 < range0 * 0.30 && closePos > 0.70)
            sc += (hftBias == BIAS_BULL) ?  6 : -2;   // hammer: bullish signal
         if(uWick > range0 * 0.60 && body0 < range0 * 0.30 && closePos < 0.30)
            sc += (hftBias == BIAS_BEAR) ? -6 :  2;   // shooting star: bearish

         // Momentum burst: large directional body (>60% range) in bias direction
         if(c0 > o0 && body0 > range0 * 0.60)
            sc += (hftBias == BIAS_BULL) ?  4 : -1;
         if(c0 < o0 && body0 > range0 * 0.60)
            sc += (hftBias == BIAS_BEAR) ? -4 :  1;

         // Inside bar: consolidation → imminent breakout in bias direction
         if(h0 < h1 && l0 > l1)
            sc += (hftBias == BIAS_BULL) ?  2 : -2;

         comps[3] = MathMax(-10, MathMin(10, sc));
      }
   }

   // ── Comp [4]: HFT rolling BSP (M1/M3/M5 + 64-tick flow) → ±20 ───────
   // v6.3g: Upgraded from ±10 to ±20. Uses new hftRollingBuyPct (exponential
   // decay rolling window — NOT session accumulation which was causing neutral
   // readings at session start and lagged signals throughout the day).
   // Velocity bonus already included in ScoreBuySellPressure(); here we use
   // direct ScoreBuySellPressure() call which handles all the band logic.
   {
      // Direct delegation to the mode-aware ScoreBuySellPressure engine.
      // ScoreBuySellPressure() returns ±20 for HFT (updated in v6.3g).
      comps[4] = ScoreBuySellPressure(hftBias);
   }

   // ── Comp [5]: M1 MACD micro-cross → ±8 ─────────────────────────────
   {
      double mm0 = GetMACDMain(IDX_M1, 1);  double ms0 = GetMACDSig(IDX_M1, 1);
      double mm1 = GetMACDMain(IDX_M1, 2);  double ms1 = GetMACDSig(IDX_M1, 2);

      if(mm0 != EMPTY_VALUE && ms0 != EMPTY_VALUE)
      {
         bool   aboveSig    = (mm0 > ms0);
         bool   freshCross  = (mm1 != EMPTY_VALUE && ms1 != EMPTY_VALUE) &&
                              ((aboveSig && mm1 <= ms1) || (!aboveSig && mm1 >= ms1));
         bool   histPos     = (mm0 > 0);

         int sc = 0;
         if(hftBias == BIAS_BULL)
         {
            if(aboveSig) { sc += freshCross ? 6 : 4; sc += histPos ? 2 : 0; }
            else           sc  = -3;
         }
         else
         {
            if(!aboveSig) { sc += freshCross ? -6 : -4; sc += !histPos ? -2 : 0; }
            else            sc  =  3;
         }
         comps[5] = MathMax(-8, MathMin(8, sc));
      }
   }

   // ── Comp [6]: Volume momentum burst (from pre-computed gVolMom) → ±7 ─
   {
      // gVolMom is refreshed by RefreshVolumeMomentum() before signal compute.
      // Use ratio and directional confirmation directly.
      if(gVolMom.bullConfirmed || gVolMom.bearConfirmed)
      {
         double norm  = MathMin(SafeDiv(gVolMom.ratio - 1.0, 1.0), 1.0); // 0→ratio=1, 1→ratio=2
         int    vPts  = (int)MathRound(7.0 * norm);

         if(hftBias == BIAS_BULL)
            comps[6] = gVolMom.bullConfirmed ?  vPts : -MathMin(vPts / 2, 3);
         else
            comps[6] = gVolMom.bearConfirmed ? -vPts :  MathMin(vPts / 2, 3);
      }
   }

   // ── Comp [7]: M1 ATR vs M5 ATR volatility sweet-spot → ±5 ───────────
   // HFT needs enough volatility to reach TP but not so much it's chaotic.
   // Ideal: M1 ATR is 50–200% of M5 ATR.
   {
      double atrM1 = GetATR(IDX_M1, 1);
      double atrM5 = GetATR(IDX_M5, 1);
      if(atrM1 != EMPTY_VALUE && atrM5 != EMPTY_VALUE && atrM5 > DBL_EPSILON)
      {
         double ratio = SafeDiv(atrM1, atrM5);
         int sc = 0;
         if     (ratio >= 0.50 && ratio <= 2.00) sc = (hftBias == BIAS_BULL) ?  5 : -5; // sweet spot
         else if(ratio >= 0.30)                  sc = (hftBias == BIAS_BULL) ?  2 : -2; // low vol
         // ratio > 2.00: too chaotic for precision HFT → 0 contribution
         comps[7] = sc;
      }
   }

   // ── Comp [8]: M3 EMA bridge — confirmation between M1 and M5 → ±8 ──────
   // M3 fills the gap: M1 is fast/noisy, M5 is slow. M3 agreement = quality signal.
   {
      double m3e9_0  = GetEMA9 (IDX_M3, 1);  double m3e9_1  = GetEMA9 (IDX_M3, 2);
      double m3e34_0 = GetEMA34(IDX_M3, 1);  double m3e34_1 = GetEMA34(IDX_M3, 2);

      if(m3e9_0 != EMPTY_VALUE && m3e34_0 != EMPTY_VALUE &&
         m3e9_1 != EMPTY_VALUE && m3e34_1 != EMPTY_VALUE)
      {
         bool m3Bull  = (m3e9_0 > m3e34_0);
         bool aligned = (hftBias == BIAS_BULL) ? m3Bull : !m3Bull;
         bool fresh   = (m3Bull && m3e9_1 <= m3e34_1) || (!m3Bull && m3e9_1 >= m3e34_1);

         int sc = 0;
         // v6.3g: Reduced from ±8→±6. M3 EMA is already captured in BSP rolling composite;
         // double-weighting it inflated EMA dominance. Keep as structure filter only.
         if(aligned)
         {
            sc  = (hftBias == BIAS_BULL) ? 4 : -4;   // was 5
            sc += fresh ? ((hftBias == BIAS_BULL) ? 2 : -2) : 0;  // fresh cross bonus (was 3)
         }
         else
         {
            // BiDir mode: M3 is a lagging indicator relative to M1 HFT entry timing.
            // Opposing M3 is structurally expected in counter-trend HFT — treat as neutral.
            sc = gRt_HFTBidir ? 0 : ((hftBias == BIAS_BULL) ? -2 : 2);
         }
         comps[8] = MathMax(-6, MathMin(6, sc));
      }
   }

   // ── Comp [9]: M6 RSI momentum cross — medium short TF → ±6 ─────────────
   // M6 RSI bridges M5 and M10; strong directional confirmation.
   {
      double rsi6_0 = GetRSI(IDX_M6, 1);
      double rsi6_1 = GetRSI(IDX_M6, 2);

      if(rsi6_0 != EMPTY_VALUE)
      {
         int sc = 0;
         if(hftBias == BIAS_BULL)
         {
            if     (rsi6_0 >= 55)  sc =  4;
            else if(rsi6_0 >= 50)  sc =  2;
            else                   sc = -3;
            if(rsi6_1 != EMPTY_VALUE && rsi6_0 > rsi6_1 + 1.5) sc += 2;  // rising M6 RSI
            if(rsi6_0 >= 80) sc -= 4;   // overbought penalty
         }
         else  // BEAR
         {
            if     (rsi6_0 <= 45)  sc = -4;
            else if(rsi6_0 <= 50)  sc = -2;
            else                   sc =  3;
            if(rsi6_1 != EMPTY_VALUE && rsi6_0 < rsi6_1 - 1.5) sc -= 2;  // falling M6 RSI
            if(rsi6_0 <= 20) sc += 4;   // oversold bonus
         }
         comps[9] = MathMax(-6, MathMin(6, sc));
      }
   }

   // ── Comp [10]: M10 ATR volatility bridge — M5-to-M15 context → ±4 ──────
   // Compares M10 ATR vs M5 ATR.  Expanding short-TF volatility = momentum building.
   // Ratio > 1.1: M10 bars bigger than M5 bars → trending conditions → bonus.
   // Ratio > 2.5: explosive, chaotic → penalty.
   {
      double atrM5  = GetATR(IDX_M5,  1);
      double atrM10 = GetATR(IDX_M10, 1);

      if(atrM5 > DBL_EPSILON && atrM10 != EMPTY_VALUE && atrM10 > DBL_EPSILON)
      {
         double ratio = SafeDiv(atrM10, atrM5);
         int sc = 0;
         if     (ratio >= 1.50 && ratio <= 2.50)  sc = (hftBias == BIAS_BULL) ?  4 : -4;
         else if(ratio >= 1.10)                    sc = (hftBias == BIAS_BULL) ?  2 : -2;
         else if(ratio > 2.50)                     sc = (hftBias == BIAS_BULL) ? -2 :  2; // too volatile
         comps[10] = sc;
      }
   }

   // ── Apply weight multipliers (v6.4 — InpHFTW_* input parameters) ────
   // Each comp is multiplied by its weight after internal cap. 1.0=unchanged.
   // Weights allow real-time tuning of each component's signal authority.
   // Applied individually (MQL5 has no array-of-input-pointers)
   comps[0]  = (int)MathRound(comps[0]  * InpHFTW_EMA);
   comps[1]  = (int)MathRound(comps[1]  * InpHFTW_M5EMA);
   comps[2]  = (int)MathRound(comps[2]  * InpHFTW_RSI);
   comps[3]  = (int)MathRound(comps[3]  * InpHFTW_Pattern);
   comps[4]  = (int)MathRound(comps[4]  * InpHFTW_BSP);
   comps[5]  = (int)MathRound(comps[5]  * InpHFTW_MACD);
   comps[6]  = (int)MathRound(comps[6]  * InpHFTW_Volume);
   comps[7]  = (int)MathRound(comps[7]  * InpHFTW_ATR);
   comps[8]  = (int)MathRound(comps[8]  * InpHFTW_M3EMA);
   comps[9]  = (int)MathRound(comps[9]  * InpHFTW_M6RSI);
   comps[10] = (int)MathRound(comps[10] * InpHFTW_M10ATR);

   // ── Aggregate all 11 components ────────────────────────────────────────
   // comps[0..7] → gScoreComp[] (dashboard visible)
   // comps[8..10] → HFT extended (M3/M6/M10), contribute to score only
   int raw = 0;
   for(int c = 0; c < 8; c++)
   {
      gScoreComp[c] = comps[c];   // share with dashboard / CSV logger
      raw += comps[c];
   }
   // Add HFT extended components to score (not shown in dashboard individually)
   for(int c = 8; c < 11; c++)
      raw += comps[c];

   // Spike penalty (same as main engine)
   if(gSpike.spikeActive)
   {
      raw -= 30;
      JournalInfo("HFTEngine", StringFormat("Spike penalty -30. Raw->%d", raw));
   }

   int rawSigned = MathMax(-98, MathMin(98, raw));
   int absScore  = MathMin(98, (int)MathAbs((double)rawSigned));

   // Bias consistency check: if score strongly diverges from M1 EMA anchor, flip
   // (e.g., EMA says BULL but components give -20: treat as BEAR signal)
   if(rawSigned < -15 && hftBias == BIAS_BULL) hftBias = BIAS_BEAR;
   if(rawSigned >  15 && hftBias == BIAS_BEAR) hftBias = BIAS_BULL;
   // BiDir HFT: lower suppression threshold so direction is established even in low-vol
   // Asia sessions where M1/M5 conflict keeps raw scores in the 8-19 range.
   // Non-BiDir: keep 20 to require clear trend confluence before declaring bias.
   // Note: BIAS_NONE here → Gate 3 block.  Actual trade gate is gRt_HFTMinScore (≥48).
   int biasNoneThresh = gRt_HFTBidir ? 8 : 20;
   if(absScore < biasNoneThresh) hftBias = BIAS_NONE;   // score too weak — suppress

   gLastRawScore = rawSigned;
   gLastScore    = absScore;
   outBias       = hftBias;
   gLastBias     = hftBias;
   // v6.3c: WriteSignalCSV moved to OnTick AFTER TryNewEntry so gLastBlockGate/
   //        gLastBlockReason reflect the ACTUAL gate that blocked (not stale SubMode event)

   JournalInfo("HFTEngine", StringFormat(
      "Score=%d Bias=%s EMA[0]=%d M5[1]=%d RSI[2]=%d Pat[3]=%d BSP[4]=%d MACD[5]=%d Vol[6]=%d ATR[7]=%d M3[8]=%d M6[9]=%d M10[10]=%d",
      absScore,
      hftBias == BIAS_BULL ? "BULL" : hftBias == BIAS_BEAR ? "BEAR" : "NONE",
      comps[0], comps[1], comps[2], comps[3], comps[4], comps[5], comps[6], comps[7],
      comps[8], comps[9], comps[10]));

   return absScore;
}

// ── MASTER SIGNAL SCORER ─────────────────────────────────────────────
// Returns total score. Fills gScoreComp[8] and gLastScore.
// outBias = dominant direction (from EMA cross — the most reliable anchor)
// Component weights:
//   [0] EMA Cross H1+M5   max ±20
//   [1] RSI H1            max ±15
//   [2] MACD H1           max ±15
//   [3] Bollinger H1      max ±10
//   [4] Stochastic H1     max ±10
//   [5] Volume Momentum   max ±10
//   [6] Regime Adjust     max  +5
//   [7] Buy/Sell Pressure max  ±8   (v5.0d)
//   SPIKE PENALTY          −30
//   TOTAL HONEST MAX       = 93 pts
int ComputeEntrySignal(ENUM_BIAS &outBias)
{
   // ── Warm-up guard: test key indicators before full computation ──────────
   // If H1 EMA9 or M5 RSI are not ready, all 8 components will return 0 and
   // the score will be misleadingly 0.  Detect early and show clear event.
   {
      double testEMA = GetEMA9(IDX_H1, 1);
      double testRSI = GetRSI (IDX_M5, 1);
      if(testEMA == EMPTY_VALUE || testRSI == EMPTY_VALUE)
      {
         static datetime lastWarmupMsg = 0;
         if(TimeLocal() - lastWarmupMsg >= 15)   // throttle: once per 15s
         {
            JournalInfo("ScoreEngine", "WARM-UP: H1 EMA or M5 RSI not ready — score=0 until indicators calculate");
            PushEAEvent("WarmUp", "WARM-UP: indicators loading, score=0 (normal at startup)");
            lastWarmupMsg = TimeLocal();
         }
         outBias = BIAS_NONE;
         gLastScore = 0; gLastRawScore = 0; gLastBias = BIAS_NONE;
         return 0;
      }
   }

   ENUM_BIAS emaBias = BIAS_NONE;

   gScoreComp[0] = ScoreEMACross(emaBias);
   gScoreComp[1] = ScoreRSI(emaBias);
   gScoreComp[2] = ScoreMACD(emaBias);
   gScoreComp[3] = ScoreBollinger(emaBias);
   gScoreComp[4] = ScoreStochastic(emaBias);
   gScoreComp[5] = ScoreVolumeMomentum(emaBias);
   gScoreComp[6] = ScoreRegimeAdj();
   gScoreComp[7] = ScoreBuySellPressure(emaBias);  // v5.0d — multi-TF pressure

   int raw = 0;
   for(int c=0; c<8; c++) raw += gScoreComp[c];

   // Spike penalty: applied after all component scores
   if(gSpike.spikeActive)
   {
      raw -= 30;
      JournalInfo("Signal", StringFormat("Spike penalty -30 applied. Raw->%d", raw));
   }

   // Clamp signed raw (used for CSV diagnostics — negative = bearish components dominating)
   int rawSigned = MathMax(-93, MathMin(93, raw));

   // CRITICAL: Score = absolute value of signed raw.
   // Rationale: bearish indicators each return negative values. A strong SELL
   // setup produces raw ~ -70. MathAbs gives 70 — the "strength in the dominant
   // direction". This is then compared against the minimum threshold (e.g. 52).
   // Without this, a valid SELL signal with raw = -70 < 52 always fails Gate4.
   int absScore = MathMin(93, (int)MathAbs((double)rawSigned));

   gLastRawScore = rawSigned;   // signed diagnostic (written to CSV / debug)
   gLastScore    = absScore;    // gate-check score [0..93]
   outBias       = emaBias;
   gLastBias     = emaBias;
   // v6.3c: WriteSignalCSV moved to OnTick AFTER TryNewEntry — see HFT engine note above

   return absScore;
}

//====================================================================
// 7.8  ENTRY FILTER CHAIN
//       Sequential gate chain: ALL must pass before TryNewEntry().
//       Returns false (blocked) with a journal reason on first fail.
//       Does NOT place a trade — only decides whether to proceed.
//====================================================================
bool CanAttemptEntry(ENUM_BIAS bias, int score)
{
   // Macro helper: log + push to EA event log on each gate block
   #define GATE_BLOCK(gate, reason) \
      { JournalInfo("EntryGate","BLOCKED — " reason); PushEAEvent(gate, "BLOCKED — " reason); return false; }

   // Gate 0: MT5 Auto Trading must be enabled in the terminal
   // Without this, CTrade::OrderSend silently fails with "auto trading disabled by client".
   // Throttle to once per 30s — fires every new bar otherwise and floods the log.
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      static datetime _lastATWarn = 0;
      if(TimeLocal() - _lastATWarn >= 30)
      {
         JournalWarn("EntryGate","BLOCKED — MT5 Auto Trading is OFF. "
                     "Click the green robot button in the MT5 toolbar to enable it.");
         PushEAEvent("Gate0-AutoTrade",
                     "AUTO TRADING DISABLED — enable with the robot button in MT5 toolbar");
         _lastATWarn = TimeLocal();
      }
      return false;
   }
   // Also check if automated trading is allowed for this account/EA specifically
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      static datetime _lastAEWarn = 0;
      if(TimeLocal() - _lastAEWarn >= 60)
      {
         JournalWarn("EntryGate","BLOCKED — Broker has disabled automated trading on this account. "
                     "Check account settings or contact your broker.");
         PushEAEvent("Gate0-BrokerBlock","BROKER BLOCKED — auto trading not allowed on account");
         _lastAEWarn = TimeLocal();
      }
      return false;
   }

   // Gate 1: Safety lock
   if(CheckSafetyLockAdvanced())
   { JournalInfo("EntryGate","BLOCKED — safety lock active");
     PushEAEvent("Gate1-Safety","BLOCKED — safety lock active"); return false; }

   // Gate 2: Manual pause
   if(gManualPause)
   { JournalInfo("EntryGate","BLOCKED — manual pause");
     PushEAEvent("Gate2-Pause","BLOCKED — manual pause"); return false; }

   // Gate 3: Bias must be non-neutral
   if(bias == BIAS_NONE)
   { JournalInfo("EntryGate","BLOCKED — bias NONE (no directional consensus)");
     PushEAEvent("Gate3-Bias","BLOCKED — bias NONE: no directional consensus"); return false; }

   // Gate 4: Minimum score — driven by runtime profile shadow globals
   // gRt_HFTMinScore / gRt_ScalpMinScore / gRt_ModMinScore are set by
   // ApplyRiskProfile() (P1B_COMPAT) so presets override input defaults.
   int minS = (gBotMode==BOT_MODE_HFT)      ? gRt_HFTMinScore    :
              (gBotMode==BOT_MODE_SCALPING)  ? gRt_ScalpMinScore  : gRt_ModMinScore;

   // Gate 4 AI-LED (InpAIMode=4): the learned model REPLACES the score gate as the
   // entry decision-maker. Once it has trained on InpAIWarmupTrades closed trades,
   // entry is decided by P(win) ≥ InpAIPrimaryProb and the score THRESHOLD is
   // ignored — the score is now just feature f[0] feeding the model. This is the
   // genuine "replace the additive score". Until warmup completes, aiLedActive is
   // false and the proven score gate below runs instead (never trade an untrained
   // brain). aiLedActive stays in scope through Gate 15, which it supersedes.
   bool aiLedActive = (InpAIMode == 4 && gAIReady && gAITrainCount >= InpAIWarmupTrades);
   if(aiLedActive)
   {
      double prLed = AI_PredictWinProb(bias, score);   // also refreshes gLastAIProb
      if(prLed < InpAIPrimaryProb)
      {
         string g4led = StringFormat("BLOCKED — AI-LED P(win)=%.0f%% < %.0f%% (score %d, cliff removed)",
                          prLed*100.0, InpAIPrimaryProb*100.0, score);
         JournalInfo("EntryGate", g4led);
         PushEAEvent("Gate4-AILed", g4led);
         return false;
      }
      // Edge cleared — bypass the legacy score cliff entirely.
   }
   else if(score < minS)
   {
      // Gate 4 AI-RESCUE (BLEND mode only): the score is a hard cliff — a setup at
      // minS-1 is rejected even when the learned win-probability model rates it as
      // a strong trade. In BLEND mode, allow a near-miss (within InpAIRescueMargin
      // points) through when AI P(win) ≥ InpAIRescueProb. This is the direct fix for
      // "the scoring system itself is a drawback".
      bool rescued = false;
      if(InpAIMode == 3 && gAIReady && (minS - score) <= InpAIRescueMargin)
      {
         double pr = AI_PredictWinProb(bias, score);   // also refreshes gLastAIProb
         if(pr >= InpAIRescueProb)
         {
            rescued = true;
            string g4rs = StringFormat(
               "AI-RESCUE — score %d < min %d but P(win)=%.0f%% ≥ %.0f%% (gap %d ≤ %d)",
               score, minS, pr*100.0, InpAIRescueProb*100.0, minS-score, InpAIRescueMargin);
            JournalInfo("EntryGate", g4rs);
            PushEAEvent("Gate4-AIRescue", g4rs);
         }
      }
      if(!rescued)
      {
         string g4reason = StringFormat("BLOCKED — score %d < min %d [%s]", score, minS,
                           gBotMode==BOT_MODE_HFT?"HFT":gBotMode==BOT_MODE_SCALPING?"SCALP":"MOD");
         JournalInfo("EntryGate", g4reason);
         PushEAEvent("Gate4-Score", g4reason);
         return false;
      }
   }

   // Gate 5: News window — CheckNewsWindowActive() is void; read gNews.active state
   CheckNewsWindowActive();  // refreshes gNews.active (P5)
   if(gNews.active)
   {
      if(TimeLocal()-gLastNewsAlertAt > NEWS_ALERT_COOLDOWN_SEC)
      {
         TGAlert_NewsBlocking("Scheduled news window", InpNewsPreBufferMin, InpNewsPostBufferMin);
         gLastNewsAlertAt = TimeLocal();
      }
      PushEAEvent("Gate5-News","BLOCKED — news window active");
      return false;
   }

   // Gate 6: Implied news — state set by CheckImpliedNewsFilter() in P5 each tick
   if(gImpliedNewsActive)
   { JournalInfo("EntryGate","BLOCKED — implied news (spread spike)");
     PushEAEvent("Gate6-ImpNews","BLOCKED — implied news (spread/ATR elevated)"); return false; }

   // Gate 7: Blackout window
   if(IsInBlackoutWindow())
   { JournalInfo("EntryGate","BLOCKED — blackout window active");
     PushEAEvent("Gate7-Blackout","BLOCKED — manual blackout window"); return false; }

   // Gate 8: Spike active (already penalised in score but gate as hard block if too severe)
   if(gSpike.spikeActive)
   {
      double ratio = SafeDiv(gSpike.spikeRange, GetATR(IDX_M5,1));
      if(ratio > InpSpikeATRFactor * 3.0)
      {
         string g8r = StringFormat("BLOCKED — severe spike %.2fx ATR", ratio);
         JournalInfo("EntryGate", g8r);
         PushEAEvent("Gate8-Spike", g8r);
         return false;
      }
   }

   // Gate 9: Regime — scalp suppressed in HOSTILE
   if(gBotMode==BOT_MODE_SCALPING && RegimeSuppressScalper())
   { JournalInfo("EntryGate","BLOCKED — scalp suppressed (HOSTILE/QUIET regime)");
     PushEAEvent("Gate9-Regime","BLOCKED — scalp suppressed in HOSTILE/QUIET regime"); return false; }

   // Gate 10: Loss streak cooldown
   if(!LossCooldownOK_v2())
   { JournalInfo("EntryGate","BLOCKED — loss streak cooldown active");
     PushEAEvent("Gate10-Cooldown",StringFormat("BLOCKED — cooldown after %d loss streak",gConsecLosses)); return false; }

   // Gate 10b: HFT bidirectional cooldown
   // After an HFT entry, prevent immediate opposite-direction flip within cooldown window.
   // gRt_HFTBidirCoolMs = 0 means unlimited (Low-Risk/bidir-off uses 2000ms).
   // Non-HFT modes skip this gate entirely.
   if(gBotMode == BOT_MODE_HFT && gRt_HFTBidirCoolMs > 0 &&
      gHFTLastEntryBias != BIAS_NONE && gHFTLastEntryBias != bias &&
      gHFTLastEntryMs > 0)
   {
      ulong nowMs   = GetTickCount64();
      ulong elapsedMs = (nowMs >= gHFTLastEntryMs) ? (nowMs - gHFTLastEntryMs) : 0;
      if(elapsedMs < (ulong)gRt_HFTBidirCoolMs)
      {
         string g10b = StringFormat("BLOCKED — HFT bidir cooldown: %dms / %dms elapsed",
                                     gRt_HFTBidirCoolMs, (int)elapsedMs);
         JournalInfo("EntryGate", g10b);
         PushEAEvent("Gate10b-HFTBidir", g10b);
         return false;
      }
   }

   // Gate 11: Maximum open positions per mode
   int openCount=0;
   for(int i=0;i<100;i++) if(gRec[i].active) openCount++;
   if(openCount >= InpMaxOpenTrades)
   { JournalInfo("EntryGate",StringFormat("BLOCKED — max %d open trades reached",InpMaxOpenTrades));
     PushEAEvent("Gate11-MaxTrades",StringFormat("BLOCKED — %d/%d max trades",openCount,InpMaxOpenTrades)); return false; }

   // Gate 12: Portfolio ranking gate (only if watchlist enabled)
   if(InpUsePortfolioWatchlist)
   {
      int myRank = GetChartSymbolRank();
      if(myRank > InpPortfolioMaxTradableRanks)
      { JournalInfo("EntryGate",StringFormat("BLOCKED — rank %d > max %d", myRank, InpPortfolioMaxTradableRanks));
        PushEAEvent("Gate12-Portfolio",StringFormat("BLOCKED — rank %d > max %d",myRank,InpPortfolioMaxTradableRanks)); return false; }
      if(myRank <= 0)
      { JournalInfo("EntryGate","BLOCKED — symbol not in portfolio watchlist");
        PushEAEvent("Gate12-Portfolio","BLOCKED — symbol not in watchlist"); return false; }
   }

   // Gate 13: Real-time tick pressure (HFT only, CPressureEngine)
   // Requires 60%+ directional tick ratio on current M1 bar before entering.
   // Skipped if not enough samples yet (< PRESS_MIN_SAMPLE ticks on this bar).
   if(gBotMode == BOT_MODE_HFT && InpHFTPressureGate)
   {
      if(gPressEng.IsValid())   // at least PRESS_MIN_SAMPLE=5 ticks classified
      {
         double ratio    = gPressEng.GetRatio();   // buy-tick fraction [0.0–1.0]
         double minRatio = InpHFTPressureMin;       // default 0.60

         bool pressOK = (bias == BIAS_BULL && ratio >= minRatio) ||
                        (bias == BIAS_BEAR && ratio <= (1.0 - minRatio));

         if(!pressOK)
         {
            string g13r = StringFormat(
               "BLOCKED — tick pressure %.1f%% (need %s≥%.0f%%) buys=%.1f%% sells=%.1f%%",
               ratio * 100.0,
               bias == BIAS_BULL ? "buy" : "sell",
               minRatio * 100.0,
               ratio * 100.0, (1.0 - ratio) * 100.0);
            JournalInfo("EntryGate", g13r);
            PushEAEvent("Gate13-Pressure", g13r);
            return false;
         }
      }
      // If !IsValid() (< 5 ticks this bar) — skip gate, don't block early in session
   }

   // Gate 14: Multi-TF candle Buy/Sell Pressure gate (all modes, v6.5)
   // Uses the rolling candle-wise BSP composite (gBSP) — the per-TF volume
   // pressure the user asked for, computed by CalcCandleWindowBSP across the
   // mode's timeframe set. Blocks entries that fight measured volume flow.
   // gBSP.buyPct already holds the mode-correct composite (set in
   // RefreshBuySellPressure: HFT→M1/M3/M5+tick, SCALP→M5/M15/M1, MOD→H1/H4/M15).
   if(InpBSPGateEnable && g_BSPHandlesReady)
   {
      double biasPct = (bias == BIAS_BULL) ? gBSP.buyPct : gBSP.sellPct;

      if(biasPct < InpBSPGateMinPct)
      {
         string g14r = StringFormat(
            "BLOCKED — candle BSP %s=%.1f%% < min %.1f%% (buy=%.1f%% sell=%.1f%%)",
            bias == BIAS_BULL ? "buy" : "sell",
            biasPct, InpBSPGateMinPct, gBSP.buyPct, gBSP.sellPct);
         JournalInfo("EntryGate", g14r);
         PushEAEvent("Gate14-BSP", g14r);
         return false;
      }

      // Optional velocity veto (HFT only — only HFT computes a composite velocity)
      if(InpBSPGateVelocityVeto && gBotMode == BOT_MODE_HFT)
      {
         // Positive hftVelocity = buy pressure accelerating. A bull entry into
         // strongly decelerating (negative) flow — or a bear into accelerating
         // (positive) flow — is fought by the tape.
         bool velOpposes =
            (bias == BIAS_BULL && gBSP.hftVelocity <= -InpBSPGateVelVetoMin) ||
            (bias == BIAS_BEAR && gBSP.hftVelocity >=  InpBSPGateVelVetoMin);
         if(velOpposes)
         {
            string g14v = StringFormat(
               "BLOCKED — BSP velocity %.1f opposes %s bias (veto≥%.1f)",
               gBSP.hftVelocity, bias == BIAS_BULL ? "bull" : "bear", InpBSPGateVelVetoMin);
            JournalInfo("EntryGate", g14v);
            PushEAEvent("Gate14-BSPvel", g14v);
            return false;
         }
      }
   }

   // Gate 15: AI win-probability veto / advisory (v6.5)
   // The online logistic model (SKP_P8_AI.mqh) scores every passing setup with a
   // learned P(win). Modes:
   //   1 ADVISORY — log the probability, never change the decision.
   //   2 GATE     — hard block when P(win) < InpAIGateMinProb.
   //   3 BLEND    — permissive veto: only block clearly-bad passers
   //                (P(win) < InpAIVetoProb). Pairs with the Gate-4 rescue above
   //                so the model both saves good near-misses and culls bad passes.
   //   4 AI-LED    — handled authoritatively in Gate 4 (aiLedActive); skip here so
   //                the model isn't double-gated with a different threshold.
   if(InpAIMode != 0 && InpAIMode != 4 && gAIReady)
   {
      double pwin = AI_PredictWinProb(bias, score);   // also refreshes gLastAIProb

      if(InpAIMode == 1)   // ADVISORY — observe only
      {
         JournalInfo("EntryGate", StringFormat(
            "AI advisory — P(win)=%.0f%% (score %d, no veto)", pwin*100.0, score));
      }
      else
      {
         double aiThresh = (InpAIMode == 2) ? InpAIGateMinProb : InpAIVetoProb;
         if(pwin < aiThresh)
         {
            string g15r = StringFormat("BLOCKED — AI P(win)=%.0f%% < %.0f%% [%s]",
               pwin*100.0, aiThresh*100.0, InpAIMode==2 ? "GATE" : "BLEND-veto");
            JournalInfo("EntryGate", g15r);
            PushEAEvent("Gate15-AI", g15r);
            return false;
         }
      }
   }

   // All gates cleared — reset block count
   gBlockedTickCount = 0;
   return true;   // all gates cleared

   #undef GATE_BLOCK
}

//====================================================================
// 7.9  DAILY P&L RESET
//       Detects trading day change and resets gDailyClosedPnL,
//       gDailyStartBalance.  Called once per timer tick.
//====================================================================
void CheckDailyReset()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);

   // Build a "today" epoch at midnight
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(gTodayDate == 0)
   {
      // First call: initialise without firing
      gTodayDate         = today;
      gDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      return;
   }

   if(today != gTodayDate)
   {
      JournalInfo("DayReset", StringFormat("New trading day — resetting daily P&L. Yesterday: %.2f",
                                            gDailyClosedPnL));
      // Carry the daily PnL into a running weekly accumulator if you build one
      gDailyClosedPnL    = 0.0;
      gConsecLosses      = 0;       // daily streak reset (design choice)
      gTodayDate         = today;
      gDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      UINeedRedraw();
   }
}

//====================================================================
// 7.9b  INDICATOR HEALTH AUDIT  (Upgrade 6.2 Point 2)
//        Checks every indicator handle and its buffer values.
//        Pushes diagnostic events into gEAEventLog[] so the WebView
//        dashboard and CCanvas overlay can display what is happening.
//        Call from OnTimer, rate-limited to once per M5 bar.
//
//        Events pushed:
//          "IndHealth" / "DEAD: <TF> <Name>" — INVALID_HANDLE
//          "IndHealth" / "ZERO: <TF> <Name>" — buffer returned 0.0 exactly
//          "IndHealth" / "NaN:  <TF> <Name>" — buffer returned EMPTY_VALUE
//          "IndHealth" / "ALL OK"             — no issues found
//====================================================================
datetime gLastIndHealthCheck = 0;   // rate-limiter — one per M5 bar

void AuditIndicatorHealth()
{
   // Rate-limit: once per M5 bar at most
   datetime curBarTime = iTime(gSymbol, PERIOD_M5, 0);
   if(curBarTime == gLastIndHealthCheck) return;
   gLastIndHealthCheck = curBarTime;

   // Timeframe labels — must match TF_COUNT (9); uses P1's TFNames[9] array.
   // Fallback local copy so we don't depend on TFNames being in scope here.
   string tfLabels[9] = {"M1","M5","M15","H1","H4","D1","M3","M6","M10"};

   struct HndCheck { int hnd; string name; bool checkNeg; };

   int issueCount = 0;
   string issues = "";

   for(int tf = 0; tf < TF_COUNT; tf++)
   {
      // Build list of handles and their names for this TF
      HndCheck checks[7];
      checks[0].hnd = gTF[tf].hEMA9;  checks[0].name = "EMA9";  checks[0].checkNeg = false;
      checks[1].hnd = gTF[tf].hEMA34; checks[1].name = "EMA34"; checks[1].checkNeg = false;
      checks[2].hnd = gTF[tf].hRSI;   checks[2].name = "RSI";   checks[2].checkNeg = false;
      checks[3].hnd = gTF[tf].hATR;   checks[3].name = "ATR";   checks[3].checkNeg = true;
      checks[4].hnd = gTF[tf].hMACD;  checks[4].name = "MACD";  checks[4].checkNeg = false;
      checks[5].hnd = gTF[tf].hBB;    checks[5].name = "BB";    checks[5].checkNeg = false;
      checks[6].hnd = gTF[tf].hStoch; checks[6].name = "Stoch"; checks[6].checkNeg = false;

      for(int h = 0; h < 7; h++)
      {
         string label = tfLabels[tf] + "/" + checks[h].name;

         if(checks[h].hnd == INVALID_HANDLE)
         {
            string msg = "DEAD: " + label + " (INVALID_HANDLE)";
            PushEAEvent("IndHealth", msg);
            JournalWarn("IndHealth", msg);
            issueCount++;
            continue;
         }

         // Try reading 1 value from buffer 0 at shift=1 (last closed bar)
         double val = GetBufVal(checks[h].hnd, 0, 1);

         if(val == EMPTY_VALUE)
         {
            string msg = "NaN: " + label + " (no data — buffer empty)";
            PushEAEvent("IndHealth", msg);
            JournalWarn("IndHealth", msg);
            issueCount++;
         }
         else if(val == 0.0)
         {
            string msg = "ZERO: " + label + " (indicator returned 0 — not yet calculated?)";
            PushEAEvent("IndHealth", msg);
            JournalInfo("IndHealth", msg);
            issueCount++;
         }
         else if(checks[h].checkNeg && val < 0.0)
         {
            string msg = StringFormat("NEG: %s = %.5f (ATR should not be negative)", label, val);
            PushEAEvent("IndHealth", msg);
            JournalWarn("IndHealth", msg);
            issueCount++;
         }
      }

      // BSP check only for standard TFs that have BSP data (M1=0,M5=1,H1=3,H4=4)
      // Skip M15=2, D1=5, and HFT extended M3=6,M6=7,M10=8 — no BSP for those.
      double bspBuy = (tf==0)?gBSP.buyPctM1:(tf==1)?gBSP.buyPctM5:
                      (tf==3)?gBSP.buyPctH1:(tf==4)?gBSP.buyPctH4:0;
      if(bspBuy <= 0.0 && (tf == 0 || tf == 1 || tf == 3 || tf == 4))
      {
         string msg = "BSP-ZERO: " + tfLabels[tf] + " buy pressure = 0 (session data pending?)";
         PushEAEvent("IndHealth", msg);
         issueCount++;
      }
   }

   // Score component zero-check: if all 8 components are 0 something is wrong
   bool allCompZero = true;
   for(int c = 0; c < 8; c++) if(gScoreComp[c] != 0) { allCompZero = false; break; }
   if(allCompZero)
   {
      PushEAEvent("IndHealth", "WARN: ALL score components are 0 — EA is IDLE or indicators warming up");
      issueCount++;
   }

   // gLastScore = 0 but positions already exist is fine; if 0 + no trades = warn
   if(gLastScore == 0 && PositionsTotal() == 0 && issueCount == 0)
   {
      // Quiet info — not a hard error, just user awareness
      PushEAEvent("Scoring", StringFormat("Score=0 RawSigned=%d Bias=%s (waiting for signal)",
                  gLastRawScore,
                  gLastBias==BIAS_BULL?"BULL":gLastBias==BIAS_BEAR?"BEAR":"NONE"));
   }
}

//====================================================================
// 7.10  OnInit  — 10-STEP INITIALISATION SEQUENCE
//       Returns INIT_SUCCEEDED (0) or INIT_FAILED (negative).
//       Every step is logged.  Failures are non-fatal unless marked
//       CRITICAL — in that case OnInit returns INIT_FAILED.
//====================================================================
int OnInit()
{
   JournalInfo("OnInit", "═══ SK TRADE PREMIUM v6.0 — BOOT SEQUENCE ═══");
   gInitTime = TimeLocal();

   // ── STEP 1: Core trade object and symbol metadata ─────────────
   gTrade.SetExpertMagicNumber(InpMagicNumber);
   gTrade.SetDeviationInPoints(InpSlippagePoints);
   gTrade.SetTypeFilling(ORDER_FILLING_IOC);
   gTrade.SetAsyncMode(false);   // synchronous for reliable result codes

   gSymbol   = Symbol();
   gPoint    = SymbolInfoDouble(gSymbol, SYMBOL_POINT);
   gDigits   = (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS);
   gTickSize = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_SIZE);
   gTickValue= SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_VALUE);
   gLotStep  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);
   gMinLot   = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN);
   gMaxLot   = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MAX);
   gMinStopLevel = (double)SymbolInfoInteger(gSymbol, SYMBOL_TRADE_STOPS_LEVEL) * gPoint;

   if(gPoint < DBL_EPSILON || gTickValue < DBL_EPSILON)
   {
      JournalError("OnInit","CRITICAL — symbol metadata invalid (gPoint or gTickValue = 0)");
      return INIT_FAILED;
   }
   JournalInfo("OnInit",StringFormat("Step1 OK — %s  Pt=%.6f  Dig=%d  TickVal=%.4f",
                                      gSymbol, gPoint, gDigits, gTickValue));

   // ── STEP 2: Symbol profile (asset class auto-detect) ─────────
   LoadSymbolProfile();   // P5 — fills gProfile, sets pip multipliers
   JournalInfo("OnInit","Step2 OK — symbol profile loaded: "+g_AssetClass);

   // ── STEP 3: Patch engine init and built-in patches ────────────
   PatchEngine_Init();
   RegisterBuiltInPatches();
   ApplyPendingPatches();
   PrintPatchRegistry();
   JournalInfo("OnInit","Step3 OK — patch engine ready ("+IntegerToString(gPatchCount)+" patches)");

   // ── STEP 4: Indicator handle creation (CRITICAL) ─────────────
   if(!InitAllIndicatorHandles())
   {
      JournalError("OnInit","CRITICAL — indicator handle creation failed");
      return INIT_FAILED;
   }
   JournalInfo("OnInit","Step4 OK — "+IntegerToString(TF_COUNT*8)+" indicator handles ready (incl. EMA21)");

   // ── STEP 2b: Pip calibration (auto-detect pip size + value) ─────
   DetectAndSetPipValues();  // P1B_COMPAT Section X — fills gPipSize, gPipValue
   JournalInfo("OnInit",StringFormat("Step2b OK — pip size=%.5f  pip val=%.4f  %s",
                                      gPipSize, gPipValue, gPipDigitLabel));

   // ── STEP 2b-pre: Init runtime direction toggles from inputs ─────
   // v6.3d: gRtAllowBuy/gRtAllowSell are the runtime-mutable mirrors of InpAllowBuy/Sell.
   // They start equal to the input values and can be flipped by the dashboard BUY/SELL buttons.
   gRtAllowBuy  = InpAllowBuy;
   gRtAllowSell = InpAllowSell;

   // CRITICAL: gBotMode must be set HERE — before ApplyRiskProfile and ApplySubMode.
   // If set later (Step 7), both profile and sub-mode run with gBotMode at its default
   // (BOT_MODE_MODERATE), causing wrong parameter branches and misleading log labels.
   gBotMode = (ENUM_BOT_MODE_)InpMode;

   // ── STEP 2c: Apply initial risk profile ──────────────────────────
   gActiveRiskProfile = -1;   // force first-call apply
   ApplyRiskProfile(InpRiskProfile);   // P1B_COMPAT Section Y
   JournalInfo("OnInit","Step2c OK — risk profile: "+RiskProfileName(InpRiskProfile));

   // ── STEP 2d: Apply sub-mode strategy preset (overrides gRt_*) ────
   // Sub-mode runs AFTER risk profile so it takes final precedence.
   // MANUAL and AUTO_ADAPTIVE sub-modes delegate to their own logic.
   ApplySubMode();   // P1B_COMPAT Section Y3
   JournalInfo("OnInit", StringFormat(
      "Step2d OK — sub-mode: %s  ACTIVE_GATES: HFT_min=%d  Scalp_min=%d  Mod_min=%d  DD=%.1f%%  BiDir=%s",
      SubModeName(), gRt_HFTMinScore, gRt_ScalpMinScore, gRt_ModMinScore,
      gRt_DailyDDPct, gRt_HFTBidir ? "YES" : "NO"));

   // ── STEP 5: Volume momentum handles ───────────────────────────
   InitVolumeHandles();   // P5 — void return; logs own warnings internally
   JournalInfo("OnInit","Step5 OK — volume handles initialised (see P5 log for handle status)");

   // ── STEP 5b: Buy/Sell Pressure Engine handles ──────────────────
   InitBSPHandles();   // P5 Engine v5.0d
   JournalInfo("OnInit","Step5b OK — Buy/Sell Pressure Engine v5.0d initialised");

   // ── STEP 5c: Real-time tick pressure engine (SKP_PressureEngine) ─
   // Seeds last PRESS_HIST_DEPTH=30 bars of historical pressure, then
   // updates tick-by-tick in OnTick STEP 4b.
   if(!gPressEng.Init(gSymbol))
      JournalWarn("OnInit","Step5c WARN — PressureEngine Init failed (non-critical)");
   else
      JournalInfo("OnInit","Step5c OK — CPressureEngine seeded for " + gSymbol);

   // ── STEP 5d: Online win-probability model (SKP_P8_AI) ─────────
   // Seeds informative priors, then (live only) restores any persisted
   // weights. Learns from every closed trade via ProcessDealAdd hooks.
   AI_Init();

   // ── STEP 6: Portfolio watchlist handles ───────────────────────
   if(InpUsePortfolioWatchlist && StringLen(InpPortfolioWatchlist) > 0)
   {
      ParseWatchlistCSV();   // P5 — reads InpPortfolioWatchlist directly
      JournalInfo("OnInit","Step6 OK — portfolio "+IntegerToString(g_WatchCount)+" symbols loaded");
   }
   else
      JournalInfo("OnInit","Step6 SKIP — portfolio watchlist disabled");

   // ── STEP 7: Safety and state initialisation ───────────────────
   {
      // Clear all safety locks
      gSafety.lockEquityFloor     = false;
      gSafety.lockDailyLoss       = false;
      gSafety.lockGlobalDD        = false;
      gSafety.lockManualPause     = false;
      gSafety.lockMacroDivergence = false;
      gSafety.lockSpread          = false;
      gSafety.lockStaleData       = false;
      gSafety.lockSpike           = false;
      gSafety.lockNews            = false;
      gSafety.ddHighWaterMark     = AccountInfoDouble(ACCOUNT_BALANCE);

      // Clear record arrays
      for(int i=0;i<100;i++) gRec[i].active = false;
      for(int i=0;i<20; i++) gPlan[i].active= false;
      for(int i=0;i<64; i++) gRetry[i].active=false;

      // Initialise performance stats
      gPerf.totalTrades = 0; gPerf.winTrades  = 0; gPerf.lossTrades = 0;
      gPerf.totalProfit = 0; gPerf.totalLoss  = 0;
      gPerf.bestTrade   = 0; gPerf.worstTrade = 0;

      // Spike buffer
      ArrayInitialize(gSpike.tickPriceBuf, 0.0);
      gSpike.tickBufIdx   = 0;
      gSpike.spikeActive  = false;

      // Session counters
      gConsecLosses = 0; gConsecWins  = 0;
      gDailyClosedPnL = 0.0;
      gManualPause    = false;
      gBotMode        = (ENUM_BOT_MODE_)InpMode;  // initialise runtime mode from input
   }
   JournalInfo("OnInit","Step7 OK — safety vault cleared, state zeroed");

   // ── STEP 8: News window and blackout parsing ───────────────────
   ParseNewsWindowCSV();    // P5 — reads InpNewsScheduleCSV directly
   // Blackout windows are parsed on-demand inside IsInBlackoutWindow() — no pre-parse needed
   JournalInfo("OnInit","Step8 OK — "+IntegerToString(gNews.parsedCount)+" news events parsed, blackout windows on-demand");

   // ── STEP 9: Recover any open positions from before restart ────
   RecoverOpenPositions();
   JournalInfo("OnInit","Step9 OK — broker reconciliation complete");

   // ── STEP 10: Dashboard, Telegram, Timer ───────────────────────
   if(!UIInit())   // P6 — CCanvas basic overlay
      JournalWarn("OnInit","Step10 WARN — dashboard canvas failed (non-critical)");

   // Write WebView HTML dashboard file (once at boot)
   WriteWebViewHTML();   // P6 Engine 16 — writes to MQL5/Files/sk_dashboard.html
   // Write initial JSON data immediately
   gWebViewLastWrite = 0;  // force immediate write
   WriteWebViewJSON();      // P6 Engine 16 — writes sk_dashboard_data.js

   // Prime Telegram: send bot start notification
   if(InpUseTelegram)
      TGAlert_BotStart();   // P6 — queued, fires on first OnTimer call

   // Daily session initialisation
   MqlDateTime dt; TimeToStruct(TimeLocal(), dt);
   gTodayDate         = StringToTime(StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day));
   gDailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Portfolio next scan
   gPortNextScanAt = TimeLocal() + InpPortfolioScanIntervalSec;

   // Panic state clean
   gPanicArmed    = false;
   gPanicArmedAt  = 0;

   // Start 500ms millisecond timer for OnTimer async processing
   if(!EventSetMillisecondTimer(500))
      JournalWarn("OnInit","EventSetMillisecondTimer failed — retrying with 1s timer");
   else
      JournalInfo("OnInit","Step10 OK — 500ms async timer armed");

   // Force first dashboard render
   UINeedRedraw();

   JournalInfo("OnInit", StringFormat(
      "═══ BOOT COMPLETE  v%s  %s  Magic=%d  Balance=%.2f  Mode=%s ═══",
      GetVersionString(), gSymbol, InpMagicNumber,
      AccountInfoDouble(ACCOUNT_BALANCE), TGBotModeStr()));

   return INIT_SUCCEEDED;
}

//====================================================================
// 7.11  OnDeinit — FULL CLEANUP
//       Must release all resources; any leak here causes memory/handle
//       exhaustion across restarts or strategy tester runs.
//====================================================================
void OnDeinit(const int reason)
{
   string reasonStr;
   switch(reason)
   {
      case REASON_REMOVE:    reasonStr="REMOVE";    break;
      case REASON_RECOMPILE: reasonStr="RECOMPILE"; break;
      case REASON_CHARTCLOSE:reasonStr="CHARTCLOSE";break;
      case REASON_PARAMETERS:reasonStr="PARAMETERS";break;
      case REASON_ACCOUNT:   reasonStr="ACCOUNT";   break;
      case REASON_TEMPLATE:  reasonStr="TEMPLATE";  break;
      case REASON_INITFAILED:reasonStr="INITFAILED";break;
      case REASON_CLOSE:     reasonStr="CLOSE";     break;
      default:               reasonStr=IntegerToString(reason);
   }

   JournalInfo("OnDeinit","═══ SHUTDOWN — reason: "+reasonStr+" ═══");

   // Kill timer FIRST to prevent OnTimer firing during cleanup
   EventKillTimer();

   // Telegram: send stop alert then drain queue synchronously (last chance)
   if(InpUseTelegram && reason != REASON_INITFAILED)
   {
      TGAlert_BotStop(reasonStr);
      // Drain remaining queue — 30 attempts at 300ms each = up to 9 seconds max
      for(int attempt=0; attempt<30 && gTGQHead!=gTGQTail; attempt++)
      {
         int   idx      = gTGQHead;
         bool  ok       = TGSendRaw(gTGQueue[idx].message, gTGQueue[idx].chatId);
         gTGQueue[idx].active = false;
         gTGQHead = (gTGQHead+1) % 128;
         if(!ok) break;   // network gone — stop trying
         // Rate limit (blocking sleep acceptable in OnDeinit only)
         Sleep(TG_SEND_RATE_MS);
      }
      JournalInfo("OnDeinit",StringFormat("Telegram: %d sent, %d dropped session total",
                                           gTGTotalSent, gTGDropped));
   }

   // Dashboard cleanup
   UIDestroy();   // P6

   // Release all per-TF indicator handles
   ReleaseAllIndicatorHandles();

   // Release Buy/Sell Pressure Engine handles
   ReleaseBSPHandles();      // P5 Engine v5.0d

   // Release volume momentum handles
   ReleaseVolumeHandles();   // P5

   // Release portfolio watchlist handles
   if(InpUsePortfolioWatchlist)
      ReleaseWatchlistHandles();   // P5

   // Final patch registry print
   PrintPatchRegistry();

   // Final performance summary to journal
   JournalInfo("OnDeinit",StringFormat(
      "Session: %d trades | W=%d L=%d | DayPnL=%.2f | Best=%.2f | Worst=%.2f",
      gPerf.totalTrades, gPerf.winTrades, gPerf.lossTrades,
      gDailyClosedPnL, gPerf.bestTrade, gPerf.worstTrade));

   JournalInfo("OnDeinit","═══ SK TRADE PREMIUM v6.0 OFFLINE ═══");
}

//====================================================================
// 7.12  OnTick — 16-STEP HOT PATH
//       ► NO Sleep()
//       ► NO WebRequest()
//       ► NO chart object creation
//       ► NO indicator handle creation
//       ► TGEnqueue() is the ONLY Telegram call allowed here
//       ► Dashboard render deferred to OnTimer via dirty flag only
//
//       EXECUTION ORDER IS MANDATORY — do not reorder steps.
//====================================================================
void OnTick()
{
   // ── STEP 1: Minimum bars guard ───────────────────────────────────
   // Prevent signal calculation on broker startup before history is loaded
   if(Bars(gSymbol, PERIOD_M5)  < 100 ||
      Bars(gSymbol, PERIOD_H1)  < 50)
   { return; }

   // ── STEP 2: Valid tick guard ─────────────────────────────────────
   MqlTick tick;
   if(!SymbolInfoTick(gSymbol, tick)) return;
   if(tick.bid <= 0 || tick.ask <= 0) return;

   gTickCount++;

   // ── HFT: Tick velocity + order flow tracking (runs every tick) ──
   if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE || InpHFTTickVelocityMin > 0)
   {
      // Per-second tick rate
      datetime nowSec = (datetime)((ulong)TimeLocal());
      if(nowSec != gHFTTickBufSec)
      {
         // Commit previous second's count into ring buffer
         gHFTTickBuf[gHFTTickBufIdx] = gHFTTickThisSec;
         gHFTTickBufIdx = (gHFTTickBufIdx + 1) % 32;
         // Compute 8-second rolling average ticks/sec
         int filled = MathMin(32, (int)(nowSec - gHFTTickBufSec < 32 ? 8 : 32));
         double total = 0;
         for(int _ti=0; _ti<filled; _ti++)
            total += gHFTTickBuf[(gHFTTickBufIdx - 1 - _ti + 32) % 32];
         gHFTTickRate = (filled > 0) ? total / filled : 0;
         gHFTTickThisSec = 0;
         gHFTTickBufSec  = nowSec;
      }
      gHFTTickThisSec++;

      // Order flow classification: determine if this tick is a buy or sell aggressor.
      // tick.last returns 0 in MT5 strategy tester (only real-tick feeds populate it).
      // Use bid-direction-change as the universal proxy: rising bid = buy pressure.
      // Secondary fallback: if bid is unchanged, compare to midpoint.
      static double gPrevBidFlow = 0.0;
      double mid = (tick.bid + tick.ask) * 0.5;
      int flowDir;
      if(gPrevBidFlow > DBL_EPSILON)
         flowDir = (tick.bid > gPrevBidFlow + DBL_EPSILON) ? 1 :   // bid rose  → buy aggressor
                   (tick.bid < gPrevBidFlow - DBL_EPSILON) ? 0 :   // bid fell  → sell aggressor
                   (tick.bid >= mid)                       ? 1 : 0; // unchanged → midpoint side
      else
         flowDir = (tick.bid >= mid) ? 1 : 0;  // first tick: midpoint classification
      gPrevBidFlow = tick.bid;
      gHFTFlowBuf[gHFTFlowIdx] = flowDir;
      gHFTFlowIdx = (gHFTFlowIdx + 1) % 64;
      // Rolling 64-tick buy fraction
      int buyTicks = 0;
      for(int _fi=0; _fi<64; _fi++) buyTicks += gHFTFlowBuf[_fi];
      gHFTOrderFlowBull = (double)buyTicks / 64.0;

      // Reset hourly rate-limiter at each new clock-hour
      datetime thisHour = (datetime)(((ulong)TimeLocal() / 3600) * 3600);
      if(thisHour != gHFTHourBucket)
      {
         gHFTHourBucket    = thisHour;
         gHFTTradesThisHour = 0;
      }
   }

   // ── STEP 3: Tick buffer update (spike detection raw data) ────────
   // UpdateTickBuffer() is declared in P5 Engine v5.0a
   UpdateTickBuffer();

   // ── STEP 4: Bar data refresh (all 6 TFs, sets newBar flags) ─────
   RefreshBarData();

   // ── STEP 4b: Tick pressure engine update (every tick) ─────────────
   // CPressureEngine classifies each tick as buy or sell via bid-delta.
   // Handles bar-reset internally (archives closing bar, resets counters).
   gPressEng.OnNewTick();

   // ── STEP 5: Spike evaluation (tick-by-tick, uses circular buffer) ─
   EvaluateSpikeDetection();   // P5

   // Track spike alert deduplication
   if(gSpike.spikeActive && (TimeLocal()-gLastSpikeAlertAt) > SPIKE_ALERT_COOLDOWN_SEC)
   {
      TGAlert_SpikeDetected(gSpike.spikeRange, GetATR(IDX_M5,1));
      gLastSpikeAlertAt = TimeLocal();
   }

   // ── STEP 6: Stale data detection (inline — no function call) ────
   {
      static datetime lastTickTime = 0;
      if(lastTickTime > 0)
      {
         int staleGap = (int)(tick.time - lastTickTime);

         // Asset-class aware stale threshold — crypto/commodity feeds have
         // wider natural tick gaps especially on demo/thin market hours.
         // NOTE: Use StringFind (substring) because g_AssetClass is "CRYPTO_BTC",
         //       "CRYPTO_ETH", "METAL_GOLD", "ENERGY_OIL" etc. — never bare "CRYPTO".
         int staleThr = InpStaleDataMaxSec;
         if     (StringFind(g_AssetClass, "CRYPTO") >= 0)  staleThr = MathMax(staleThr, 120);
         else if(StringFind(g_AssetClass, "METAL")  >= 0)  staleThr = MathMax(staleThr, 90);
         else if(StringFind(g_AssetClass, "ENERGY") >= 0)  staleThr = MathMax(staleThr, 90);

         bool nowStale = (staleGap > staleThr);
         if(nowStale != gSafety.lockStaleData)
         {
            gSafety.lockStaleData = nowStale;
            if(nowStale)
               JournalWarn("OnTick",StringFormat("STALE DATA lock: gap=%ds > %ds (%s threshold)",
                                                   staleGap, staleThr, g_AssetClass));
         }
      }
      lastTickTime = tick.time;
   }

   // ── STEP 7: Spread lock (hot-path check, RefreshBrokerSanity
   //           runs the full check in OnTimer) ─────────────────────
   {
      double spreadPts = (tick.ask - tick.bid) / gPoint;
      double atrPts    = GetATR(IDX_M5, 1) / gPoint;
      // HFT mode uses tighter spread limit from risk profile (gRt_MaxSpreadATR)
      // Other modes use the input parameter InpSpreadATRFactor
      double spreadFactor = (gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
                            ? gRt_MaxSpreadATR : InpSpreadATRFactor;
      bool   spreadBad = (atrPts > DBL_EPSILON &&
                          spreadPts > atrPts * spreadFactor * RegimeSpreadMultiplier());
      if(spreadBad != gSafety.lockSpread)
      {
         gSafety.lockSpread = spreadBad;
         // Lock engage/release alerts are fired in RefreshBrokerSanity (OnTimer)
      }
   }

   // ── STEP 8: Manage existing open positions (ALWAYS — even if locked) ─
   // Position management continues regardless of entry locks.
   // TSL, partial closes, breakeven, exhaustion are all critical to protect capital.
   //
   // FIX (TSL/Partial-TP/BE): Previously this loop called P3 helper functions which
   // used ManagePartialCloseCheck(idx) → PartialCloseVolumeManaged(idx, ...) passing
   // the record INDEX (0-99) as a ulong ticket — PositionSelectByTicket(0..99) always
   // fails → TP1 never fired → TSL never armed → BE never set.
   //
   // Now replaced with P4's RunAllPositionManagement() which uses the correct
   // ticket-based PartialCloseVolumeManaged(ulong ticket, ...) throughout.
   // ManagePendingOrderAge (scalp limit-order TTL) is kept as it is not part of
   // RunAllPositionManagement's scope.
   {
      // P4 complete management: TP1(30%), TP2(40%), BE, Exhaustion, TSL, ReverseExit
      // All calls are ticket-based — no index/ticket confusion possible.
      RunAllPositionManagement();

      // Pending order TTL cancellation for scalp limit orders (gRec[]-tracked)
      for(int i = 0; i < 100; i++)
      {
         if(!gRec[i].active) continue;
         ManagePendingOrderAge(i);
      }
   }

   // ── STEP 9: Closed position reconciliation ───────────────────────
   CheckPositionsClosed();

   // ── STEP 10: Signal refresh gate (throttle to new bar only) ──────
   bool isNewH1Bar = gTF[IDX_H1].newBar;
   bool isNewM5Bar = gTF[IDX_M5].newBar;
   bool isNewM1Bar = gTF[IDX_M1].newBar;

   // Refresh gate: expensive indicator refreshes run on new bar.
   // HFT_PURE gate evaluation runs every tick (so pressure gate fires once 5+ ticks arrive).
   bool shouldRefreshSig = gSigRefreshNeeded
      || (gBotMode==BOT_MODE_MODERATE  && isNewH1Bar)
      || (gBotMode==BOT_MODE_SCALPING  && isNewM5Bar)
      || (gBotMode==BOT_MODE_HFT       && isNewM1Bar)
      || (gBotMode==BOT_MODE_HFT_PURE  && isNewM1Bar);  // heavy refreshes on new bar only
   bool shouldRunPureGates = (gBotMode==BOT_MODE_HFT_PURE);  // gate evaluation every tick

   // ── STEP 11: Entry signal evaluation (rate-gated) ────────────────
   if(shouldRefreshSig || shouldRunPureGates)
   {
      // Heavy indicator refreshes only on new bar (not every tick for HFT_PURE)
      if(shouldRefreshSig)
      {
         RefreshRegimeState();        // P5 Engine 11
         SyncRegimeCurrent();         // sync gRegime.current alias field
         RefreshVolumeMomentum();     // P5 Engine v5.0c
         RefreshBuySellPressure();    // P5 Engine v5.0d — buy/sell pressure composite
         if(InpRiskProfile == RISK_PROFILE_AUTO_SWITCH) ApplyRiskProfile((int)RISK_PROFILE_AUTO_SWITCH);
      }

      // Route each mode to its signal engine:
      //   HFT_PURE → gate-only (7.7c): returns 100/0, no scoring, runs every tick
      //   HFT      → scored engine (7.7b): returns raw score
      //   MODERATE / SCALPING → standard multi-TF scorer (7.7)
      ENUM_BIAS newBias;
      int newScore;
      if(gBotMode == BOT_MODE_HFT_PURE)
         newScore = ComputeHFTPureSignal(newBias);   // Section 7.7c — gate-only, no score
      else if(gBotMode == BOT_MODE_HFT)
         newScore = ComputeHFTEntrySignal(newBias);  // Section 7.7b — HFT scored engine
      else
         newScore = ComputeEntrySignal(newBias);     // Section 7.7  — MODERATE/SCALP

      // Regime change alert
      if(gRegime.regime != gLastAlertedRegime)
      {
         TGAlert_RegimeChange(gLastAlertedRegime, gRegime.regime);
         gLastAlertedRegime = gRegime.regime;
      }

      gSigRefreshNeeded = false;
      if(gBotMode==BOT_MODE_MODERATE) gLastSigBarTimeH1 = gTF[IDX_H1].barTime0;
      else                            gLastSigBarTimeM5 = gTF[IDX_M5].barTime0;

      // ── STEP 12: Safety vault full evaluation (P4 Engine 9) ────────
      // CheckSafetyLockAdvanced also handles equity floor, daily loss, global DD checks
      CheckSafetyLockAdvanced();

      // ── STEP 13: Entry attempt (only if all gates clear) ───────────
      // Skip CanAttemptEntry when bias=NONE — ComputeHFTPureSignal already
      // logged the gate block; calling CanAttemptEntry here would spam
      // "[EntryGate] BLOCKED — bias NONE" on every tick.
      if(newBias != BIAS_NONE && CanAttemptEntry(newBias, newScore))
      {
         // TryNewEntry() is the 20-step guard pipeline in P4 Engine 7.
         // It reads gLastScore, gLastBias, gRegimeState, gProfile etc.
         // and places the trade if all conditions pass.
         // We capture pre-entry position count to detect if a trade was opened,
         // then update HFT bidirectional state accordingly.
         int posBefore = PositionsTotal();
         gAIEntryScore = newScore;   // carry entry score to AI_OnTradeOpen (ENTRY_IN deal)
         TryNewEntry(newBias, newScore);
         // If HFT / HFT_PURE and a new position was opened, record direction + timestamp
         if((gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
            && PositionsTotal() > posBefore)
         {
            gHFTLastEntryBias = newBias;
            gHFTLastEntryMs   = GetTickCount64();
         }
      }

      // ── STEP 13b: Signal CSV — written AFTER gate evaluation ────────
      // v6.3c: Moved from inside ComputeHFTEntrySignal/ComputeEntrySignal.
      // Now gLastBlockGate/gLastBlockReason reflect the actual gate that blocked
      // (CanAttemptEntry or TryNewEntry gates 16a-16e) rather than the stale
      // "SubMode / Applied: HFT:MomentumFlash" PushEAEvent from ApplySubMode().
      WriteSignalCSV(gLastBias, gLastScore, gLastRawScore);
   }
   else
   {
      // Even without signal refresh, run safety checks (they're fast O(1) lookups)
      // Safety vault: only call equity/margin checks, not full signal re-eval
      CheckEquityFloor();    // P4 §9.2 — hard equity floor (account wipe guard)
      CheckDailyLossLimit(); // P3 §6.2 — daily loss using gRt_DailyDDPct per sub-mode
      CheckGlobalDrawdown(); // P3 §6.3 — v6.3g FIX: was NEVER called — global DD lock now active
   }

   // ── STEP 14: Process non-blocking retry queue ─────────────────────
   // Retry queue handles EmergencyClose failures, partial close retries, etc.
   // ProcessRetryQueue is defined in P4.  Must not call WebRequest.
   ProcessRetryQueue();

   // ── STEP 15: Mark dashboard dirty (never render here — OnTimer only) ─
   UINeedRedraw();

   // ── STEP 16: Panic arm expiry ─────────────────────────────────────
   if(gPanicArmed && (TimeLocal()-gPanicArmedAt) > 3)
   {
      gPanicArmed = false;   // auto-disarm after 3 seconds if not confirmed
      UINeedRedraw();
   }
}

//====================================================================
// 7.13  OnTimer — 9-STEP ASYNC PATH (fires every 500ms)
//       All blocking I/O, expensive computations, and Telegram sends
//       happen here.  OnTick stays sub-millisecond.
//====================================================================
void OnTimer()
{
   // ── STEP 1: Telegram queue drain ──────────────────────────────────
   // Rate-limited internally to TG_SEND_RATE_MS; drains up to 3 per call
   ProcessTelegramQueue();   // P6

   // ── STEP 2: Scheduled reports (hourly / daily / weekly) ───────────
   CheckScheduledReports();  // P6

   // ── STEP 3: Daily session reset ───────────────────────────────────
   CheckDailyReset();

   // ── STEP 4: Full broker sanity check ─────────────────────────────
   // Includes spread shock, tick velocity, bar gap, stop levels, blackout.
   // Rate-limited to BROKER_SANITY_INTERVAL_SEC so it doesn't thrash.
   {
      datetime now = TimeLocal();
      if(now - gLastBrokerSanityAt >= (datetime)BROKER_SANITY_INTERVAL_SEC)
      {
         bool wasDangerous = (gSafety.lockSpread || gSafety.lockStaleData);
         RefreshBrokerSanity();   // P5 Engine 10
         bool  isDangerous = (gSafety.lockSpread || gSafety.lockStaleData);

         // Send lock/release alerts on state transitions
         if(!wasDangerous && isDangerous)
         {
            string lockStr = gSafety.lockSpread ? "SPREAD" : "STALE_DATA";
            TGAlert_SafetyLock(lockStr, "Broker sanity check triggered");
         }
         if(wasDangerous && !isDangerous)
         {
            string lockStr = "BROKER_SANITY";
            TGAlert_SafetyRelease(lockStr);
         }

         HandleHostileScalpExposure();   // P5 — close profitable scalps in hostile market
         gLastBrokerSanityAt = now;

         // Indicator health audit runs at same cadence as broker sanity (every 2s)
         // but is internally rate-limited to once per M5 bar to avoid log flooding.
         AuditIndicatorHealth();   // Section 7.9b
      }
   }

   // ── STEP 5: Portfolio watchlist scan (interval-gated) ─────────────
   if(InpUsePortfolioWatchlist && g_WatchCount > 0)
   {
      if(TimeLocal() >= gPortNextScanAt)
      {
         ScanPortfolioWatchlist();   // P5 Engine 12 — bubble-sort ranking
         gPortLastScanTime = TimeLocal();
         gPortNextScanAt   = TimeLocal() + (datetime)InpPortfolioScanIntervalSec;
      }
   }

   // ── STEP 6: Implied news filter refresh ───────────────────────────
   {
      bool prevImplied = gImpliedNewsActive;
      CheckImpliedNewsFilter();   // P5 — void; sets gImpliedNewsActive global

      if(gImpliedNewsActive && !prevImplied)
         JournalWarn("OnTimer","Implied news filter: ACTIVE (spread/ATR ratio elevated)");
   }

   // ── STEP 7: Non-blocking retry queue (async portion) ──────────────
   // ProcessRetryQueue handles partial EmergencyClose attempts that failed.
   // The OnTick call handles fast retries; OnTimer handles delay-backed retries.
   ProcessRetryQueue();   // P4

   // ── STEP 8: Sample equity for sparkline (every EQUITY_SMPL_SEC) ─────
   SampleEquityHistory();   // P6 — writes gEquityHist ring buffer

   // ── STEP 8b: Dashboard render ─────────────────────────────────────
   // ProcessWebViewDash() = lightweight CCanvas HUD + JSON data writer (always runs)
   // RenderDashboardAdvanced() = full glassmorphism (only if InpUseGlassmorphUI = true)
   ProcessWebViewDash();        // P6 Engine 16 — basic HUD + WebView JSON
   if(InpUseGlassmorphUI)
      RenderDashboardAdvanced(); // P6 Engine 14 — full canvas if enabled

   // ── STEP 9: Panic arm visual feedback (blink via dirty flag) ──────
   if(gPanicArmed)
      UINeedRedraw();   // keep dashboard updating while panic is armed (blink effect)
}

//====================================================================
// 7.14  OnTradeTransaction — DEAL AND ORDER EVENT HANDLER
//       Processes broker-confirmed deal events immediately rather than
//       relying solely on CheckPositionsClosed() polling in OnTick.
//       This ensures reliable TP1/TP2 detection even on rapid price moves.
//====================================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   switch(trans.type)
   {
      // ── New deal confirmed by broker ──────────────────────────────
      case TRADE_TRANSACTION_DEAL_ADD:
         ProcessDealAdd(trans.deal, trans.position);
         break;

      // ── Pending order deleted (filled, cancelled, or expired) ─────
      case TRADE_TRANSACTION_ORDER_DELETE:
         ProcessOrderDelete(trans.order);
         break;

      // ── Position state changed (volume, price, SL, TP updated) ───
      case TRADE_TRANSACTION_POSITION:
         // Broker confirmed a SL/TP modification — log for audit trail
         JournalInfo("TradeTrans", StringFormat("POSITION updated: pos=%llu",
                                                 trans.position));
         UINeedRedraw();
         break;

      default: break;
   }
}

// ── Deal processing sub-function ─────────────────────────────────────
void ProcessDealAdd(ulong dealTkt, ulong positionId)
{
   if(dealTkt == 0) return;

   // Fetch from history
   if(!HistoryDealSelect(dealTkt)) return;

   long   magic = HistoryDealGetInteger(dealTkt, DEAL_MAGIC);
   if(magic != InpMagicNumber) return;   // not our deal

   string sym   = HistoryDealGetString(dealTkt, DEAL_SYMBOL);
   if(sym != gSymbol) return;

   ENUM_DEAL_ENTRY dEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTkt, DEAL_ENTRY);
   ENUM_DEAL_TYPE  dType  = (ENUM_DEAL_TYPE) HistoryDealGetInteger(dealTkt, DEAL_TYPE);
   double          dVol   = HistoryDealGetDouble(dealTkt, DEAL_VOLUME);
   double          dPrice = HistoryDealGetDouble(dealTkt, DEAL_PRICE);
   double          dProfit= HistoryDealGetDouble(dealTkt, DEAL_PROFIT)
                          + HistoryDealGetDouble(dealTkt, DEAL_COMMISSION)
                          + HistoryDealGetDouble(dealTkt, DEAL_SWAP);

   // ── Entry deal: new position opened ───────────────────────────────
   if(dEntry == DEAL_ENTRY_IN)
   {
      // Find matching gRec[] slot (should have been allocated by TryNewEntry)
      for(int i=0;i<100;i++)
      {
         if(!gRec[i].active) continue;
         if(gRec[i].ticket != positionId) continue;

         // Confirm entry price (may differ from request due to slippage)
         gRec[i].entryPrice   = dPrice;
         gRec[i].spreadAtEntry= (SymbolInfoDouble(sym, SYMBOL_ASK)
                                - SymbolInfoDouble(sym, SYMBOL_BID)) / gPoint;

         JournalInfo("TradeTrans", StringFormat("ENTRY confirmed TKT=%llu  Vol=%.2f  Price=%.5f",
                                                 positionId, dVol, dPrice));

         // AI: snapshot entry features for this ticket (label resolved at close).
         // Bias is taken from the deal type (authoritative for this fill); the
         // entry score was carried from the decision site via gAIEntryScore.
         ENUM_BIAS aiBias = (dType == DEAL_TYPE_BUY) ? BIAS_BULL : BIAS_BEAR;
         AI_OnTradeOpen(positionId, aiBias, gAIEntryScore);

         // Telegram entry alert (enqueue, not blocking)
         TGAlert_TradeEntry(i);
         UINeedRedraw();
         return;
      }
      // Slot not found: position may have been opened externally or on different symbol
      JournalWarn("TradeTrans", StringFormat("ENTRY TKT=%llu not in gRec[] — external?", positionId));
      return;
   }

   // ── Exit deal: partial or full position close ─────────────────────
   if(dEntry == DEAL_ENTRY_OUT || dEntry == DEAL_ENTRY_INOUT)
   {
      // AI: accumulate realised P&L from THIS exit deal (partial or full) so the
      // win/loss label at final close reflects the whole trade's net result.
      AI_AccumProfit(positionId, dProfit);

      // Find gRec[] slot for this position
      int slot = -1;
      for(int i=0;i<100;i++)
         if(gRec[i].active && gRec[i].ticket == positionId) { slot=i; break; }

      if(slot < 0)
      {
         // Slot not found — ticket race between PlaceTrade and OnTradeTransaction.
         // CheckPositionsClosed() will sync fully on the next tick. But we must
         // update the critical stat accumulators HERE to avoid daily-DD blind spot.
         bool stillOpen = PositionSelectByTicket(positionId);
         if(!stillOpen)
         {
            // Full close — update every stat that matters for DD / lot smoothing
            gDailyClosedPnL += dProfit;
            gPerf.totalTrades++;
            if(dProfit >= 0) { gPerf.winTrades++;  gConsecWins++;  gConsecLosses=0; gPerf.totalProfit+=dProfit; }
            else             { gPerf.lossTrades++; gConsecLosses++; gConsecWins=0;  gPerf.totalLoss  +=dProfit; }
            if(dProfit > gPerf.bestTrade)  gPerf.bestTrade  = dProfit;
            if(dProfit < gPerf.worstTrade) gPerf.worstTrade = dProfit;
            if(gBotMode == BOT_MODE_HFT)   gHFTLastExitTime = TimeLocal();
            AI_OnTradeClose(positionId);   // train on whole-trade label, free AI slot
            JournalWarn("TradeTrans",StringFormat(
               "EXIT TKT=%llu not in gRec[] (ticket race) — fallback stats: PnL=%.2f L=%d",
               positionId, dProfit, gConsecLosses));
         }
         else
         {
            JournalWarn("TradeTrans",StringFormat("EXIT TKT=%llu not in gRec[] — partial, position still open",positionId));
         }
         return;
      }

      // No local struct reference (MQL5 disallows local &ref) — use gRec[slot] directly

      // Determine if this is a partial or full close by checking remaining position
      bool positionStillOpen = PositionSelectByTicket(positionId);
      double remainingVol    = positionStillOpen ?
                               PositionGetDouble(POSITION_VOLUME) : 0.0;

      if(positionStillOpen && remainingVol > gLotStep * 0.5)
      {
         // Partial close — identify which TP level
         double closedPct = SafeDiv(dVol, gRec[slot].initialVolume);

         if(!gRec[slot].tp1Hit && MathAbs(closedPct - 0.30) < 0.05)
         {
            gRec[slot].tp1Hit = true;
            JournalInfo("TradeTrans",StringFormat("TP1 partial close TKT=%llu Vol=%.2f",positionId,dVol));
            TGAlert_TP1Hit(slot);
         }
         else if(gRec[slot].tp1Hit && !gRec[slot].tp2Hit && MathAbs(closedPct - 0.40) < 0.05)
         {
            gRec[slot].tp2Hit = true;
            JournalInfo("TradeTrans",StringFormat("TP2 partial close TKT=%llu Vol=%.2f",positionId,dVol));
            TGAlert_TP2Hit(slot);
         }
         else
         {
            JournalInfo("TradeTrans",StringFormat("Partial close TKT=%llu Vol=%.2f (%.0f%%)",
                                                   positionId, dVol, closedPct*100));
         }
         UINeedRedraw();
      }
      else
      {
         // Full close — update stats, fire alert, free slot
         gDailyClosedPnL   += dProfit;
         gPerf.totalTrades++;
         if(dProfit >= 0) { gPerf.winTrades++;  gConsecWins++;  gConsecLosses=0; gPerf.totalProfit+=dProfit; }
         else             { gPerf.lossTrades++; gConsecLosses++;gConsecWins=0;   gPerf.totalLoss  +=dProfit; }
         if(dProfit > gPerf.bestTrade)  gPerf.bestTrade  = dProfit;
         if(dProfit < gPerf.worstTrade) gPerf.worstTrade = dProfit;

         // Alert type: TP3 vs SL
         string comment = HistoryDealGetString(dealTkt, DEAL_COMMENT);
         bool   isSL    = (StringFind(comment,"sl")>=0 || StringFind(comment,"SL")>=0 ||
                           dProfit < 0);   // loss = likely SL
         if(isSL)
            TGAlert_StopLoss(slot, dProfit);
         else
            TGAlert_TP3Hit(slot, dProfit);

         JournalInfo("TradeTrans",StringFormat("FULL CLOSE TKT=%llu  PnL=%.2f  %s",
                                                positionId, dProfit, isSL?"SL":"TP3"));

         // HFT: stamp exit time for cooldown tracking
         if(gRec[slot].isScalpMode &&
            (gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE))
            gHFTLastExitTime = TimeLocal();

         // AI: trade fully closed — train on whole-trade win/loss, free AI slot
         AI_OnTradeClose(positionId);

         gRec[slot].active = false;
         gRec[slot].ticket = 0;
         UINeedRedraw();
      }
   }
}

// ── Pending order deletion sub-function ──────────────────────────────
void ProcessOrderDelete(ulong orderTkt)
{
   if(orderTkt == 0) return;

   // Scan gPlan[] for matching order ticket
   for(int i=0;i<20;i++)
   {
      if(!gPlan[i].active) continue;
      if(gPlan[i].orderTicket != orderTkt) continue;

      JournalInfo("TradeTrans",StringFormat("Pending order %llu deleted — freeing plan slot %d",
                                             orderTkt, i));
      gPlan[i].active = false;
      UINeedRedraw();
      return;
   }
   // Not in our plan array — may be external order, ignore silently
}

//====================================================================
// 7.15  OnChartEvent — DELEGATION TO DASHBOARD
//       Dashboard handles all interactive events (drag, buttons).
//       Add any custom chart interaction logic here if needed.
//====================================================================
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   // Delegate all events to the dashboard event handler (P6)
   OnDashChartEvent(id, lparam, dparam, sparam);
}

//====================================================================
// 7.16  ASSEMBLY INSTRUCTIONS AND VERIFICATION CHECKLIST
//====================================================================
/*
╔══════════════════════════════════════════════════════════════════════╗
║  SK TRADE PREMIUM v6.0 — FINAL ASSEMBLY GUIDE                       ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  STEP A — CREATE MERGED FILE                                         ║
║  Concatenate in ORDER (no gaps, no separator lines):                 ║
║    1. SK_TRADE_PREMIUM_BOT_P1.mq5   (inputs, structs, globals)       ║
║    2. SK_TRADE_PREMIUM_BOT_P2.mq5   (Engines 1-3: signal indicators) ║
║    3. SK_TRADE_PREMIUM_BOT_P3.mq5   (Engines 4-6: scoring/filters)   ║
║    4. SK_TRADE_PREMIUM_BOT_P4.mq5   (Engines 7-9: trade/mgmt/safety) ║
║    5. SK_TRADE_PREMIUM_BOT_P5.mq5   (Engines 10-12 + v5.0 engines)  ║
║    6. SK_TRADE_PREMIUM_BOT_P6.mq5   (Engines 13-15: TG/dash/patch)  ║
║    7. SK_TRADE_PREMIUM_BOT_P7.mq5   (THIS FILE — event handlers)     ║
║  Save as: SK_TRADE_PREMIUM_BOT.mq5                                   ║
║                                                                      ║
║  STEP B — FILE HEADER (add BEFORE P1 content):                       ║
║    #property copyright  "SK TRADE PREMIUM v6.0"                     ║
║    #property version    "6.00"                                       ║
║    #property strict                                                   ║
║    #include <Trade/Trade.mqh>                                        ║
║    #include <Canvas/Canvas.mqh>       // Engine 14 dashboard         ║
║                                                                      ║
║  STEP C — DUPLICATE SYMBOL RESOLUTION                                ║
║    If compiler reports duplicate symbol errors:                       ║
║    • RegimeToString() — keep only P6 version, remove P5 if any      ║
║    • gPatchReg[] / gPatchCount — keep only P6 declaration            ║
║    • gScoreComp[] / gLastScore — keep only P6 declaration            ║
║    • gImpliedNewsActive       — keep only P6 declaration             ║
║    • gPortLastScanTime        — keep only P6 declaration             ║
║                                                                      ║
║  STEP D — P1 STRUCT PATCHES (if not already present in P1):         ║
║    • TelegramQueue: add  int retryCount;   field                     ║
║    • TimeframeData: verify hMACD, hBB, hStoch handle fields exist    ║
║    • PlanRecord: verify orderTicket (ulong) field exists             ║
║    • SafetyState: verify all 9 lockXxx bool fields + ddHighWaterMark ║
║    • PerformanceStats: verify totalProfit, totalLoss, bestTrade,     ║
║      worstTrade, winTrades, lossTrades, totalTrades fields           ║
║                                                                      ║
║  STEP E — P4 INPUT NAME COMPATIBILITY                                ║
║    The #define shims in P5 remap P4 wrong names → P1 actuals.       ║
║    In the assembled file, P5's #defines MUST appear BEFORE P4.      ║
║    Assembly order above guarantees this (P5 before P4 is WRONG —    ║
║    actually P4 then P5 per order above is correct for shims to work. ║
║    Shims in P5 fix references already compiled from P4 in same unit.)║
║    MQL5 single-file compilation resolves in one pass — this is OK.  ║
║                                                                      ║
║  STEP F — P7 FUNCTION STUBS (if P2/P3 not yet written):             ║
║    The following functions are called from P7 and must exist in      ║
║    P2/P3/P4 or be stubbed:                                          ║
║    • RunAllPositionManagement()  — P4 §8.8 (replaces P3 loop)      ║
║    • ManagePendingOrderAge(int idx) — P3 §5.6 (limit-order TTL)    ║
║    • TryNewEntry(ENUM_BIAS bias, int score)                          ║
║    • CheckEquityFloor()                                              ║
║    • CheckDailyLossLimit()                                           ║
║    • ProcessRetryQueue()                                             ║
║    (All the above are implemented in P3/P4 Engine 7/8/9)            ║
║    NOTE (Fix 25): ManageBreakeven/TrailingStop/Exhaustion/           ║
║    PartialCloseCheck/ReverseExit are now called internally by        ║
║    RunAllPositionManagement → ManageTradeRecordAdvanced (P4).       ║
║                                                                      ║
║  STEP G — MT5 CONFIGURATION                                          ║
║    1. Allow WebRequest for: https://api.telegram.org                 ║
║       (Tools → Options → Expert Advisors → Allow WebRequest)        ║
║    2. Set CLAUDE_CODE_MAX_OUTPUT_TOKENS = 64000 if regenerating      ║
║    3. Compile with: Tools → Compile (F7)                             ║
║    4. Expected compile warnings: none (errors = assembly issue)      ║
║                                                                      ║
║  STEP H — VERIFICATION CHECKLIST                                     ║
║    □ File compiles without errors                                    ║
║    □ OnInit log shows all 10 steps OK                                ║
║    □ Dashboard renders on chart                                      ║
║    □ Telegram BotStart message received                               ║
║    □ Backtest: 1 trade opens, TP1 partial fires, BE sets             ║
║    □ Backtest: emergency close fires on DD limit                     ║
║    □ Portfolio scan ranks symbols in journal                         ║
║    □ Regime changes trigger alert                                    ║
╚══════════════════════════════════════════════════════════════════════╝
*/

//====================================================================
//  ┌────────────────────────────────────────────────────────────────┐
//  │   END OF PART 7  —  SK TRADE PREMIUM BOT v6.0 COMPLETE         │
//  │                                                                  │
//  │   Files produced this session:                                   │
//  │     P1 — Inputs / Structs / Globals / Journal / Math            │
//  │     P4 — Engines 7, 8, 9  (Trade / Mgmt / Safety Vault)        │
//  │     P5 — Engines 10-12, v5.0 (Broker Sanity / Regime /         │
//  │              Portfolio / Spike / News / Volume / Profile)        │
//  │     P6 — Engines 13-15  (Telegram / Dashboard / Patch)         │
//  │     P7 — Event Handlers (OnInit/Tick/Timer/Transaction/etc.)    │
//  │                                                                  │
//  │   Remaining:  P2 (Engines 1-3) and P3 (Engines 4-6)            │
//  │   to be written as the signal/indicator computation layer.       │
//  └────────────────────────────────────────────────────────────────┘
//====================================================================


#endif // SKP_P7_MAIN_MQH
