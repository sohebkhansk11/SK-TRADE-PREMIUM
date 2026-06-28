#ifndef SKP_P1B_COMPAT_MQH
#define SKP_P1B_COMPAT_MQH

//+------------------------------------------------------------------+
//| SK_TRADE_PREMIUM_BOT_P1B_COMPAT.mq5                              |
//|                                                                   |
//| COMPATIBILITY BRIDGE LAYER — SK TRADE PREMIUM BOT v6.0           |
//|                                                                   |
//| This file is inserted BETWEEN P1 and P2 in the final assembly.   |
//| It resolves ALL cross-part naming mismatches and provides the     |
//| supplemental globals, structs, #defines, and wrapper functions   |
//| that the individual parts expected but P1 did not declare.        |
//|                                                                   |
//| DO NOT COMPILE STANDALONE.                                        |
//+------------------------------------------------------------------+

//====================================================================
// SECTION A — TF COUNT & INDEX SYSTEM
//   Base system: M1 M5 M15 H1 H4 D1 (IDX 0-5) — Moderate/Scalp + HFT
//   Extended HFT TFs: M3 M6 M10 (IDX 6-8) — HFT engine only
//   TF_COUNT 9 defined once here; P7 section 7.1 does NOT redefine it.
//====================================================================
#define TF_COUNT  9        // 9-TF system: M1 M5 M15 H1 H4 D1 + M3 M6 M10 (HFT extended)

//====================================================================
// SECTION A2 — P4 ADDITIONAL INPUT ALIASES
//   P4 uses InpPresetCSV (combined CSV); P1 has separate lists.
//   We provide an empty CSV; P4's SymbolPresetRiskMultiplier will
//   return 1.0 for all symbols, and P1B's SymbolPresetRiskMultiplierV2
//   (Section I) is the authoritative one used by P3.
//   InpMinLotCap / InpMaxLotCap → use mode-sensitive ActiveMinLot / ActiveMaxLot.
//   Since these must be scalar values for P4's ClampModeLot function,
//   we define them as mode-agnostic reasonable caps.
//====================================================================
#define InpPresetCSV       ""           // P4 legacy — replaced by per-mode lists in P1
#define InpMinLotCap       0.01         // P4: minimum lot cap fallback
#define InpMaxLotCap       5.00         // P4: maximum lot cap fallback

//====================================================================
// SECTION B — INPUT NAME ALIASES
//   P4/P5/P6/P7 were written using alternate input names.
//   These transparent macros bridge them to the P1 declarations.
//====================================================================
#define InpMagicNumber                InpMagic
#define InpSlippagePoints             InpMaxSlippagePoints
#define InpDailyLossPct               InpMaxDailyLossPercent
#define InpGlobalDDPct                InpMaxGlobalDrawdownPercent
#define InpTelegramBotToken           InpTelegramToken
#define InpMaxOpenTrades              10          // hard max concurrent positions
#define InpRSIExhaustionOB            70.0        // RSI OB level for exhaustion
#define InpRSIExhaustionOS            30.0        // RSI OS level for exhaustion

// InpEquityFloorPct: P3 uses a percentage comparison; P1's InpEquityFloor
// is an absolute amount.  We express the floor as 90% of balance as a
// conservative default.  For production: expose as an input in P1 and
// remove this line.
const double InpEquityFloorPct = 90.0;    // 90 % of balance = equity floor

//====================================================================
// SECTION C — MODE & PAUSE ALIASES
//   P2-P7 code uses gBotMode for the bot operating mode and
//   gManualPause for the manual-pause flag.
//   InpMode is an immutable input — safe to #define as an alias.
//   gBotPaused IS a global bool in P1.
//====================================================================
// gBotMode is declared as ENUM_BOT_MODE_ gBotMode in P1 globals (writable runtime variable)
// InpMode is the startup default; OnInit assigns gBotMode = InpMode at boot.
#define gManualPause   gBotPaused
#define InpDefaultMode InpMode    // P7 OnInit uses InpDefaultMode as alias for startup value

//====================================================================
// SECTION D — SAFETY VAULT STATE
//   P3 (Engines 4-6) operates on gSafety.lockXxx fields.
//   This struct and global instance are declared here.
//====================================================================
struct SafetyVaultState
{
   // Active lock flags — set by the vault engine, read by TryNewEntry
   bool   lockEquityFloor;     // P3 CheckEquityFloor
   bool   lockDailyLoss;       // P3 CheckDailyLossLimit
   bool   lockGlobalDD;        // P3 CheckGlobalDrawdown
   bool   lockSpread;          // P7 spread check
   bool   lockManualPause;     // manual pause button
   bool   lockMacroDivergence; // HTF macro divergence lock
   bool   lockStaleData;       // stale indicator data lock
   bool   lockSpike;           // spike detected lock
   bool   lockNews;            // news window lock
   // Numeric tracking
   double ddHighWaterMark;
   double globalDDPct;
   double globalDDHysteresisPct;
};

SafetyVaultState gSafety;

//====================================================================
// SECTION E — SUPPLEMENTAL GLOBALS
//   Variables referenced by multiple parts but not declared in P1.
//====================================================================

// Daily start balance — updated in CheckDailyReset (P7).
// Declared here so P3 CheckDailyLossLimit() can reference it.
// P7 section 7.1 duplicate removed during this session's edits.
double   gDailyStartBalance = 0.0;

// NOTE: The following globals are declared in P6 Engine 14 supplementals.
// DO NOT declare here to avoid duplicate-symbol compilation errors.
//   gDashNeedsRedraw  — P6 line ~825
//   gPanicArmed       — P6 line ~832
//   gPanicArmedAt     — P6 line ~833
//   gImpliedNewsActive — P6 line ~846
//   gScoreComp[7]     — P6 line ~847
//   gLastScore        — P6 line ~848
//   gPortLastScanTime — P6 line ~849
//   UINeedRedraw()    — P6 line ~891

//====================================================================
// SECTION F — JOURNAL WRAPPER FUNCTIONS
//   P1 provides JournalWrite(evt, a, b, c, d, e).
//   P2-P7 call JournalInfo/JournalWarn/JournalError with (tag, msg).
//====================================================================
void JournalInfo(string tag, string msg)
{
   Print("ℹ️ [", tag, "] ", msg);
   JournalWrite("INFO", tag, msg);
   PushDiag("[" + tag + "] " + msg);
}

void JournalWarn(string tag, string msg)
{
   Print("⚠️ [", tag, "] ", msg);
   JournalWrite("WARN", tag, msg);
   PushDiag("⚠️ [" + tag + "] " + msg);
}

void JournalError(string tag, string msg)
{
   Print("🚨 [", tag, "] ", msg);
   JournalWrite("ERROR", tag, msg);
   PushDiag("🚨 [" + tag + "] " + msg);
}

// Overloaded convenience variants for formatted messages
void JournalInfo (string tag, string fmt, int a)
   { JournalInfo (tag, StringFormat(fmt, a)); }
void JournalInfo (string tag, string fmt, int a, int b)
   { JournalInfo (tag, StringFormat(fmt, a, b)); }
void JournalInfo (string tag, string fmt, int a, int b, int c)
   { JournalInfo (tag, StringFormat(fmt, a, b, c)); }
void JournalInfo (string tag, string fmt, int a, int b, double c, double d)
   { JournalInfo (tag, StringFormat(fmt, a, b, c, d)); }
void JournalWarn (string tag, string fmt, double a, double b)
   { JournalWarn (tag, StringFormat(fmt, a, b)); }
void JournalWarn (string tag, string fmt, int a, ulong b, int c)
   { JournalWarn (tag, StringFormat(fmt, a, b, c)); }
void JournalError(string tag, string fmt, int a, ulong b)
   { JournalError(tag, StringFormat(fmt, a, b)); }
void JournalError(string tag, string fmt, int a, int b)
   { JournalError(tag, StringFormat(fmt, a, b)); }
void JournalError(string tag, string fmt, ulong a, double b, double c, double d, double e, int f)
   { JournalError(tag, StringFormat(fmt, a, b, c, d, e, f)); }

//====================================================================
// SECTION G — UI REDRAW SIGNAL
//   UINeedRedraw() is defined in P6 Engine 14 (line ~891).
//   It sets gDashNeedsRedraw = true.
//   Both gDashNeedsRedraw and UINeedRedraw() are declared in P6.
//   Do NOT redeclare here — MQL5 resolves both from P6 at link time.
//   This section is retained as a dependency documentation block.
//====================================================================

//====================================================================
// SECTION H — 2-ARGUMENT NormalizeLotSafe OVERLOAD
//   P3/P4 call NormalizeLotSafe(rawLot, symbol).
//   P1 provides the 1-arg version using gSymbol globals.
//   This overload handles any symbol explicitly.
//====================================================================
double NormalizeLotSafe(double rawLot, string sym)
{
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0 || minL <= 0.0) return 0.0;
   double lot = MathFloor(rawLot / step) * step;
   lot = MathMax(minL, MathMin(maxL, lot));
   return NormalizeDouble(lot, 2);
}

//====================================================================
// SECTION I — SYMBOL PRESET RISK MULTIPLIER V2
//   P3 ResolveLotSize calls SymbolPresetRiskMultiplierV2().
//   Evaluates InpPresetScalpList / InpPresetModerateList CSV inputs.
//====================================================================
double SymbolPresetRiskMultiplierV2(string sym)
{
   if(!InpUseSymbolPresetMap) return 1.00;

   // Scalp preset list
   string sArr[]; int ns = StringSplit(InpPresetScalpList, ',', sArr);
   for(int i = 0; i < ns; i++)
   {
      StringTrimLeft(sArr[i]); StringTrimRight(sArr[i]);
      if(sArr[i] == sym) return InpPresetScalpRiskMult;
   }
   // Moderate preset list
   string mArr[]; int nm = StringSplit(InpPresetModerateList, ',', mArr);
   for(int i = 0; i < nm; i++)
   {
      StringTrimLeft(mArr[i]); StringTrimRight(mArr[i]);
      if(mArr[i] == sym) return InpPresetModerateRiskMult;
   }
   return 1.00;
}

//====================================================================
// SECTION J — LOSS COOLDOWN CHECK v2
//   LossCooldownOK_v2() is fully defined in P7 §7.7 (LossCooldownOK_v2).
//   It uses LossCooldownSeconds_v2() + TimeCurrent().
//   MQL5 single-file compilation resolves the call to P7's definition.
//====================================================================
// bool LossCooldownOK_v2() — defined in P7 §7.7

//====================================================================
// SECTION K — PORTFOLIO RANK LOOKUP
//   GetChartSymbolRank() is fully defined in P5 (GetChartSymbolRank).
//   MQL5 single-file compilation resolves the call to P5's definition.
//====================================================================
// int GetChartSymbolRank() — defined in P5

//====================================================================
// SECTION L — TELEGRAM ALERT FORWARD STUBS
//   P3 calls TGAlert_* functions that are fully defined in P6.
//   In a single MQL5 file, ALL functions are resolved at compile-time
//   regardless of declaration order — no stubs needed.
//   This comment documents the dependency for maintenance reference.
//
//   TGAlert_BreakevenSet  — P6 Engine 13
//   TGAlert_ExhaustionClose — P6 Engine 13
//   TGAlert_TP1Hit        — P6 Engine 13
//   TGAlert_TP2Hit        — P6 Engine 13
//   TGAlert_SafetyLock    — P6 Engine 13
//   TGAlert_SafetyRelease — P6 Engine 13
//   TGAlert_StopLoss      — P7 section 7.6 calls from CheckPositionsClosed
//   TGAlert_TP3Hit        — P7 section 7.6 calls from CheckPositionsClosed
//====================================================================

//====================================================================
// SECTION M — REGIME STATE ALIAS
//   P3 was written using gRegimeState.current.
//   It has been patched (Edit tool) to use gRegime.regime directly.
//   This alias is retained for safety in case any remaining reference
//   appears in later parts.
//====================================================================
#define gRegimeState   gRegime

// Keep gRegime.current in sync whenever gRegime.regime is assigned.
// P5 RefreshRegimeState sets gRegime.regime — the sync happens in OnTick
// step 4 (RefreshRegimeState) which then immediately propagates to current.
// A dedicated sync macro is not needed; gRegimeState.current resolves to
// gRegime.current which is the separately-tracked alias field added to
// RegimeState struct in P1B.

//====================================================================
// SECTION N — DAILY CLOSED P&L ALIAS
//   P3 CheckDailyLossLimit uses gDailyClosedPnL.
//   P1 globals declares gDailyClosedPnL at line ~962.  No alias needed.
//   This comment documents the dependency for verification.
//====================================================================

//====================================================================
// SECTION O — REGIME SYNC HELPER
//   After any assignment to gRegime.regime, sync the .current alias.
//   Called from P5 RefreshRegimeState via the bridge below.
//   (Single inline — zero overhead when inlined by MQL5 compiler)
//====================================================================
inline void SyncRegimeCurrent() { gRegime.current = gRegime.regime; }

//====================================================================
// SECTION P — SPIKE STATE SYNC HELPER
//   gSpike.spikeActive and gSpike.spikeRange are alias fields added
//   to SpikeState struct in P1 (by Edit in this session).
//   They must be kept in sync with spikeDetected / lastSpikeRange.
//   Call SyncSpikeAliases() after any spike state update.
//====================================================================
inline void SyncSpikeAliases()
{
   gSpike.spikeActive = gSpike.spikeDetected;
   gSpike.spikeRange  = gSpike.lastSpikeRange;
}

//====================================================================
// SECTION Q — CHECKNEWSWINDOWACTIVE / CHECKIMPLIEDNEWSFILTER STUBS
//   P3 TryNewEntry calls these; full definitions are in P5.
//   Forward declarations documented here; MQL5 resolves at link time.
//
//   CheckNewsWindowActive()  → P5 Engine v5.0b
//   CheckImpliedNewsFilter() → P5 Engine v5.0b
//   IsInBlackoutWindow()     → P5 Engine 10 (§10.1)
//   RegimeSuppressScalper()  → P5 Engine 11 (§11.2)
//   RegimeSpreadMultiplier() → P5 Engine 11 (§11.2)
//   PartialCloseVolumeManaged() → P4 Engine 8
//   PlaceTrade()             → P4 Engine 7
//   ModifySLTP()             → P4 Engine 8
//   EmergencyCloseAll()      → P4 Engine 9
//   CheckSafetyLockAdvanced() → P4 Engine 9
//   RegimeToString()         → P6 (with #ifndef guard)
//====================================================================

//====================================================================
// SECTION R — TELEGRAM QUEUE HEAD/TAIL ALIASES
//   P6 uses gTGQHead / gTGQTail; P1 declares gTGQueueHead / gTGQueueTail.
//====================================================================
#define gTGQHead   gTGQueueHead
#define gTGQTail   gTGQueueTail

//====================================================================
// SECTION S — TELEGRAM INPUT ALIAS
//   P6 uses InpTelegramChatId; P1 declares InpTelegramChatID.
//====================================================================
#define InpTelegramChatId   InpTelegramChatID

//====================================================================
// SECTION T — REGIME CURRENT SYNC
//   After each RefreshRegimeState() call, sync the .current alias field.
//   We override the function by wrapping it; since MQL5 doesn't support
//   true function wrapping, we instead define a post-call sync macro.
//   Usage: call SyncRegimeCurrent() immediately after RefreshRegimeState()
//   in P7 OnTick and OnTimer.
//====================================================================
// SyncRegimeCurrent() is already defined as inline in SECTION O above.

//====================================================================
// SECTION U — ENQUEUE OVERLOADS (P6 TGEnqueue 2-arg variant)
//   P6 defines TGEnqueue(msg, chatId=""). P3/P7 call TGEnqueue(type, msg).
//   Both overloads must coexist.  We define the type-based variant here
//   as a wrapper; P6's HTML variant is the authoritative sender.
//====================================================================
// NOTE: TGEnqueue is defined in P6 with signature:
//       void TGEnqueue(const string &htmlMsg, const string &chatId = "")
// Some P5 code may call TGEnqueue(MSG_EXIT, tgMsg, priority).
// We need a 3-arg overload for backward compat.

void TGEnqueue(ENUM_QUEUE_MSG msgType, const string htmlMsg, bool priority = false)
{
   // Delegate to P6's 1-arg TGEnqueue (defined later in assembly)
   // msgType and priority are intentionally discarded (P6 queue handles priority internally)
   TGEnqueue(htmlMsg);
}

// ─────────────────────────────────────────────────────────────────────
// SECTION V — P4 COMPATIBILITY DEFINES
//   P4 was written before P1 was finalized.  These #defines map P4's
//   compact names to the actual P1 inputs.  They MUST appear before P4
//   in the assembly (P4 comes after P1B in the order P1→P1B→P2→P3→P4).
//   P5 repeats a subset of these; that's harmless (same-value re-define).
// ─────────────────────────────────────────────────────────────────────
#define InpLotMode                   InpLotControlMode
#define InpManualLot                 ActiveManualLot()
#define InpRiskPercent               ActiveRiskPct()
#define InpApplyLossSmoothToAutoLots InpApplyLossSmoothToAuto
#define InpUseSymbolPresets          InpUseSymbolPresetMap
#define InpScoreMinModerate          InpModerateMinScore
#define InpScoreMinScalper           InpScalpMinScore
#define InpUsePortfolioEngine        InpUsePortfolioWatchlist
#define InpPortfolioMaxRankToTrade   InpPortfolioMaxTradableRanks
#define InpPortfolioScoreGapBlock    InpPortfolioMinScoreGap
#define InpMinATRForEntry            0           // ATR floor guard (0 = disabled)
// InpStaleDataMaxSec is now a real input in P1 (removed #define to avoid redeclaration conflict)
// Additional P4 aliases (P5 previously defined these; now centralised here)
#define InpUseReverseExit            InpCloseOnOppositeSignal
// News CSV alias: P7 OnInit calls ParseNewsWindowCSV() which references InpNewsScheduleCSV.
// P1 declares the equivalent as InpNewsWindowCSV — bridge it here.
#define InpNewsScheduleCSV           InpNewsWindowCSV
// P6 dashboard alert threshold (InpShowDashboard is now a real input in P1)
#define InpMaxConsecLosses           5           // loss streak alert threshold in Telegram

// ─────────────────────────────────────────────────────────────────────
// SECTION W — P4 ENGINE 2 HELPER FUNCTIONS
//   P4 calls these as if they were in P2 ("// defined in Engine 2").
//   They are simple wrappers around P1 globals / P2 indicator buffers.
//   All defined here so P4 can resolve them at compile time.
// ─────────────────────────────────────────────────────────────────────

//--- Detect price of swing low in recent bars on tfIdx
double DetectSwingLow(int tfIdx, int lookback)
{
   double buf[];
   if(CopyLow(gSymbol, gTF[tfIdx].tf, 1, lookback, buf) < lookback) return 0.0;
   double lowest = buf[0];
   for(int i = 1; i < lookback; i++)
      if(buf[i] < lowest) lowest = buf[i];
   return lowest;
}

//--- Detect price of swing high in recent bars on tfIdx
double DetectSwingHigh(int tfIdx, int lookback)
{
   double buf[];
   if(CopyHigh(gSymbol, gTF[tfIdx].tf, 1, lookback, buf) < lookback) return 0.0;
   double highest = buf[0];
   for(int i = 1; i < lookback; i++)
      if(buf[i] > highest) highest = buf[i];
   return highest;
}

//--- Signal cooldown: true if InpSignalCooldownSeconds have elapsed since last signal
bool SignalCooldownOK()
{
   if(InpSignalCooldownSeconds <= 0) return true;
   return (int)(TimeCurrent() - gLastSignalTime) >= InpSignalCooldownSeconds;
}

//--- ADX trend confirmation: true if ADX on tfIdx is above the mode-appropriate minimum
bool ADXTrendConfirmed(int tfIdx)
{
   if(gTF[tfIdx].hADX == INVALID_HANDLE) return true; // handle missing = don't block
   double adxBuf[];
   if(CopyBuffer(gTF[tfIdx].hADX, 0, 1, 1, adxBuf) < 1) return true;
   double threshold = (InpMode == BOT_MODE_SCALPING) ? InpADXMinScalp : InpADXMinModerate;
   return adxBuf[0] >= threshold;
}

//--- Session filter: true if current time is inside London or NY session
bool IsLondonNYSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   // London: 08:00-17:00 UTC  |  New York: 13:00-22:00 UTC
   return (h >= 8 && h < 17) || (h >= 13 && h < 22);
}

//--- RSI exhaustion: true if RSI crosses the OB/OS threshold on the given side
bool RSIExhaustionDetected(int tfIdx, ENUM_ORDER_TYPE side)
{
   if(gTF[tfIdx].hRSI == INVALID_HANDLE) return false;
   double rsiBuf[];
   if(CopyBuffer(gTF[tfIdx].hRSI, 0, 1, 2, rsiBuf) < 2) return false;
   double rsiNow  = rsiBuf[0];
   double rsiPrev = rsiBuf[1];
   if(side == ORDER_TYPE_BUY)
      return (rsiPrev < InpRSIExhaustionOB && rsiNow >= InpRSIExhaustionOB);
   else
      return (rsiPrev > InpRSIExhaustionOS && rsiNow <= InpRSIExhaustionOS);
}


//--- EMA cross detectors — used by P4 ManageReverseExit
//    CrossedDown(tfIdx): returns true if EMA_FAST crossed BELOW EMA_SLOW on last 2 closed bars
bool CrossedDown(int tfIdx)
{
   if(gTF[tfIdx].hEMAFast == INVALID_HANDLE || gTF[tfIdx].hEMASlow == INVALID_HANDLE) return false;
   double fast[]; double slow[];
   if(CopyBuffer(gTF[tfIdx].hEMAFast, 0, 1, 2, fast) < 2) return false;
   if(CopyBuffer(gTF[tfIdx].hEMASlow, 0, 1, 2, slow) < 2) return false;
   // Index 0 = most recent closed bar, index 1 = previous bar
   return (fast[1] >= slow[1]) && (fast[0] < slow[0]);
}
//    CrossedUp(tfIdx): returns true if EMA_FAST crossed ABOVE EMA_SLOW on last 2 closed bars
bool CrossedUp(int tfIdx)
{
   if(gTF[tfIdx].hEMAFast == INVALID_HANDLE || gTF[tfIdx].hEMASlow == INVALID_HANDLE) return false;
   double fast[]; double slow[];
   if(CopyBuffer(gTF[tfIdx].hEMAFast, 0, 1, 2, fast) < 2) return false;
   if(CopyBuffer(gTF[tfIdx].hEMASlow, 0, 1, 2, slow) < 2) return false;
   return (fast[1] <= slow[1]) && (fast[0] > slow[0]);
}

//--- ModifySLTP 3-param overload — P3 calls (int idx, double sl, double tp)
//    P4 defines the authoritative 5-param version; this bridge looks up the ticket.
bool ModifySLTP(int idx, double sl, double tp)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return false;
   return ModifySLTP(gRec[idx].ticket, sl, tp, "AUTO", false);
}

//--- PartialCloseVolumeManaged 3-param bridge — P3 passes (int idx, double vol, string reason)
//    P4 defines the authoritative ticket-based version; this bridge resolves the ticket.
//    Without this bridge MQL5 silently casts idx (0-99) to ulong ticket → PositionSelectByTicket(0..99)
//    always fails → TP1 never fires → TSL never arms → BE never sets.
bool PartialCloseVolumeManaged(int idx, double closeVol, string reason)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return false;
   return PartialCloseVolumeManaged(gRec[idx].ticket, closeVol, reason);
}

//--- PlaceTrade 6-param overload — P3 TryNewEntry calls this after pre-allocating gRec[slot].
//    Ticket recovery uses PositionSelect (position ticket) NOT ResultOrder (order ticket).
//    On hedging accounts these differ; using PositionSelect makes ProcessDealAdd match correctly.
bool PlaceTrade(int slot, ENUM_ORDER_TYPE oType, double lot, double price, double sl, double tp)
{
   if(slot < 0 || slot >= 100) return false;
   gTrade.SetExpertMagicNumber((ulong)InpMagic);
   gTrade.SetDeviationInPoints((ulong)InpMaxSlippagePoints);
   gTrade.SetTypeFilling(ORDER_FILLING_FOK);

   bool ok = false;
   if(oType == ORDER_TYPE_BUY)
      ok = gTrade.Buy (lot, gSymbol, 0.0, sl, tp, "SKP-P3-BUY");
   else
      ok = gTrade.Sell(lot, gSymbol, 0.0, sl, tp, "SKP-P3-SEL");

   if(ok)
   {
      // Primary: select by symbol — on netting accounts this IS the position opened.
      // Fallback: ResultOrder() which equals position ticket on most brokers.
      ulong resolved = 0;
      if(PositionSelect(gSymbol))
         resolved = (ulong)PositionGetInteger(POSITION_TICKET);
      if(resolved == 0)
         resolved = gTrade.ResultOrder();

      gRec[slot].ticket = resolved;
      gRec[slot].active = true;   // keep active regardless — CheckPositionsClosed recovers on miss

      if(resolved == 0)
         JournalWarn("P3PlaceTrade",StringFormat(
            "Slot[%d]: ticket not resolved immediately — SyncRecords will recover",slot));
      else
         JournalInfo("P3PlaceTrade",StringFormat(
            "Slot[%d] → TKT=%llu %s lot=%.2f SL=%.5f TP=%.5f",
            slot, resolved, oType==ORDER_TYPE_BUY?"BUY":"SELL", lot, sl, tp));
   }
   return ok;
}

// ─────────────────────────────────────────────────────────────────────
// SECTION X — PIP AUTO-DETECTION
//   Called from OnInit after symbol metadata is loaded.
//   Fills gPipSize, gPipValue, gPipsPerPoint from broker's digit count.
// ─────────────────────────────────────────────────────────────────────
void DetectAndSetPipValues()
{
   // Determine pip digit multiplier
   bool is5Digit = (gDigits == 5 || gDigits == 3);  // 5-digit FX or 3-digit JPY

   if(InpPipAutoDetect)
   {
      gPipsPerPoint    = is5Digit ? 10.0 : 1.0;
      gPipDigitLabel   = is5Digit ? "5-DIGIT" : "4-DIGIT";
   }
   else
   {
      // Manual override via InpManualPipDigits
      bool manualIs5 = (InpManualPipDigits == 5 || InpManualPipDigits == 3);
      gPipsPerPoint  = manualIs5 ? 10.0 : 1.0;
      gPipDigitLabel = manualIs5 ? "MANUAL-5D" : "MANUAL-4D";
   }

   gPipSize = gPoint * gPipsPerPoint;

   // pip value = how much 1 pip of move on 1 lot earns in account currency
   if(InpPipValueOverride > 0.0)
   {
      gPipValue    = InpPipValueOverride;
      gPipDigitLabel = "OVERRIDE";
   }
   else
   {
      // Standard formula: pipValue = (pipSize / tickSize) * tickValue
      if(gTickSize > DBL_EPSILON)
         gPipValue = (gPipSize / gTickSize) * gTickValue;
      else
         gPipValue = gTickValue * gPipsPerPoint;
   }

   JournalInfo("PipDetect", StringFormat(
      "Pip calibration: digits=%d  pipSize=%.5f  pipValue=%.4f  mode=%s",
      gDigits, gPipSize, gPipValue, gPipDigitLabel));
}

// ─────────────────────────────────────────────────────────────────────
// SECTION Y — RISK PROFILE PRESETS v2.0 (Full Parameter Bundles)
//   InpRiskProfile: 0=Aggressive 1=MedRisk 2=LowRisk 3=AutoSwitch 4=Manual
//
//   Runtime shadow globals are written here so the code can use overridden
//   values without touching read-only MQL5 input parameters.
//   P7 CanAttemptEntry and scoring code read the gRt_* globals (not inputs).
// ─────────────────────────────────────────────────────────────────────

// ── Runtime shadow globals — written by ApplyRiskProfile ─────────────
// Score thresholds
int    gRt_HFTMinScore    = 52;     // HFT minimum entry score
int    gRt_ScalpMinScore  = 68;     // Scalp minimum entry score
int    gRt_ModMinScore    = 62;     // Moderate minimum entry score
// Risk sizing
double gRt_RiskPct        = 1.00;   // risk % of equity per trade
double gRt_LotMultiplier  = 1.00;   // applied on top of risk-based lot
// SL / TP multiples
double gRt_HFTSLatrMult   = 0.30;   // HFT SL = ATR × this
double gRt_HFTTPr1        = 0.40;   // HFT TP1 R-multiple
double gRt_HFTTPr2        = 0.80;   // HFT TP2 R-multiple
double gRt_ScalpSLatrMin  = 0.80;   // Scalp SL min ATR mult
double gRt_ScalpSLatrMax  = 1.00;   // Scalp SL max ATR mult
double gRt_ScalpTP1R      = 0.50;   // Scalp TP1 R-multiple
double gRt_ModSLatrMult   = 1.50;   // Moderate SL ATR multiplier
double gRt_ModTP1R        = 0.50;   // Moderate TP1 R
double gRt_ModTP2R        = 1.00;   // Moderate TP2 R
double gRt_ModTP3R        = 1.50;   // Moderate TP3 R
// ADX filters
int    gRt_ADXminHFT      = 15;     // min ADX for HFT entry
int    gRt_ADXminScalp    = 18;     // min ADX for Scalp entry
int    gRt_ADXminMod      = 22;     // min ADX for Moderate entry
// Feature toggles (can be disabled by low-risk presets)
bool   gRt_UseNewsFilter  = true;
bool   gRt_UseSpikeFilter = true;
bool   gRt_UseVolMom      = true;
bool   gRt_UsePatterns    = true;
bool   gRt_UseFib         = true;
bool   gRt_UsePivot       = true;
bool   gRt_UseAdxFilter   = true;
// HFT bidirectional
bool   gRt_HFTBidir       = true;   // allow BUY after SELL (no cooldown between directions)
int    gRt_HFTBidirCoolMs = 500;    // minimum ms between opposite-direction entries
// Max spread
double gRt_MaxSpreadATR   = 0.06;   // spread > ATR × this blocks entry (HFT)
// Loss smoothing
int    gRt_ConsecLossSmooth = 2;    // apply lot reduction after this many losses
double gRt_SmoothMult      = 0.65;  // lot multiplier on loss streak

// Daily DD ceiling — set by ApplySubMode, read by CheckDailyLossLimit
double gRt_DailyDDPct   = 4.0;   // overrides InpMaxDailyLossPercent per sub-mode
// Active sub-mode tracker (set in OnInit, readable by dashboard)
int    gActiveSubMode   = (int)SUBMODE_MOD_MOMENTUM_SWING;

// ── Applied profile tracker ───────────────────────────────────────────
int  gActiveRiskProfile = -1;

// Risk profile names — used in dashboard and Telegram alerts
string RiskProfileName(int p)
{
   switch(p)
   {
      case 0: return "AGGRESSIVE";
      case 1: return "MED-RISK";
      case 2: return "LOW-RISK";
      case 3: return "AUTO-SWITCH";
      case 4: return "MANUAL";
      default: return "UNKNOWN";
   }
}

// ─────────────────────────────────────────────────────────────────────
// ApplyRiskProfile()
//   Full parameter bundles per Mode × Profile. Writes to gRt_* shadow
//   globals. The actual trading code reads these — not the inputs.
// ─────────────────────────────────────────────────────────────────────
void ApplyRiskProfile(int profile)
{
   if(gActiveRiskProfile == profile) return;
   gActiveRiskProfile = profile;

   // ── AUTO-SWITCH: select sub-profile from market state ─────────────
   if(profile == 3)
   {
      int autoP = 1;  // default: MED-RISK
      // Hostile market or 3+ losses → conservative
      if(gRegime.regime == REGIME_HOSTILE || gConsecLosses >= 3)     autoP = 2;
      // Explosive with clean slate → aggressive
      else if(gRegime.regime == REGIME_EXPLOSIVE && gConsecLosses==0) autoP = 0;
      // 1-2 losses → keep MED-RISK but lower lot
      else if(gConsecLosses >= 1) { autoP = 1; gRt_LotMultiplier = 0.75; }
      JournalInfo("RiskProfile", StringFormat("AUTO-SWITCH → %s (regime=%s losses=%d)",
                  RiskProfileName(autoP), RegimeToString(gRegime.regime), gConsecLosses));
      gActiveRiskProfile = -1;  // allow recursive set
      ApplyRiskProfile(autoP);
      gActiveRiskProfile = 3;   // restore parent marker
      return;
   }

   // ── MANUAL: read inputs as-is, initialize gRt_* from inputs ───────
   if(profile == 4)
   {
      gRt_HFTMinScore    = InpHFTMinScore;
      gRt_ScalpMinScore  = InpScalpMinScore;
      gRt_ModMinScore    = InpModerateMinScore;
      gRt_RiskPct        = InpRiskPercent;
      gRt_LotMultiplier  = 1.00;
      gRt_HFTSLatrMult   = InpHFTSLATRMult;
      gRt_HFTTPr1        = InpHFTTP1R;
      gRt_HFTTPr2        = InpHFTTP2R;
      gRt_ScalpSLatrMin  = InpScalpSLATRMin;
      gRt_ScalpSLatrMax  = InpScalpSLATRMax;
      gRt_ScalpTP1R      = InpScalpTP1R;
      gRt_UseNewsFilter  = InpUseNewsFilter;
      gRt_UseSpikeFilter = InpUseSpikeDetection;
      gRt_UseVolMom      = InpUseVolumeMomentum;
      gRt_UsePatterns    = InpUseCandlePatterns;
      gRt_UseFib         = InpUseFibEngine;
      JournalInfo("RiskProfile","MANUAL — all gRt_* initialized from input parameters");
      return;
   }

   // ── Initialize all gRt_* from inputs first (safe baseline) ─────────
   gRt_HFTMinScore   = InpHFTMinScore;
   gRt_ScalpMinScore = InpScalpMinScore;
   gRt_ModMinScore   = InpModerateMinScore;
   gRt_RiskPct       = InpRiskPercent;
   gRt_LotMultiplier = 1.00;
   gRt_UseNewsFilter = InpUseNewsFilter;
   gRt_UseSpikeFilter= InpUseSpikeDetection;
   gRt_UseVolMom     = InpUseVolumeMomentum;
   gRt_UsePatterns   = InpUseCandlePatterns;
   gRt_UseFib        = InpUseFibEngine;
   gRt_UsePivot      = InpUsePivotEngine;

   // ══════════════════════════════════════════════════════════════
   // MODERATE MODE PRESETS
   // ══════════════════════════════════════════════════════════════
   if(gBotMode == BOT_MODE_MODERATE)
   {
      switch(profile)
      {
         case 0:  // ── AGGRESSIVE ─────────────────────────────────
            gRt_RiskPct       = MathMin(InpRiskPercent * 1.50, 3.0); // +50% risk, max 3%
            gRt_ModMinScore   = 55;      // lower bar = more entries
            gRt_ModSLatrMult  = 1.80;    // wider SL for trend breathing room
            gRt_ModTP1R       = 0.50;
            gRt_ModTP2R       = 1.20;    // extended TP2
            gRt_ModTP3R       = 2.00;    // aggressive TP3
            gRt_ADXminMod     = 20;      // slightly lower ADX requirement
            gRt_UseNewsFilter = true;    // keep news filter active (safety)
            gRt_UseSpikeFilter= true;
            gRt_UseVolMom     = true;
            gRt_UsePatterns   = true;
            gRt_UseFib        = true;
            gRt_SmoothMult    = 0.80;    // gentler smoothing on losses
            gRt_ConsecLossSmooth = 3;    // tolerate more losses before reducing
            JournalInfo("RiskProfile","MODERATE/AGGRESSIVE — Risk+50% Score55 SL1.8ATR TP3=2.0R");
            break;

         case 1:  // ── MED-RISK (default balanced) ─────────────────
            gRt_RiskPct       = InpRiskPercent;
            gRt_ModMinScore   = 62;
            gRt_ModSLatrMult  = 1.50;
            gRt_ModTP1R       = 0.50;
            gRt_ModTP2R       = 1.00;
            gRt_ModTP3R       = 1.50;
            gRt_ADXminMod     = 22;
            gRt_UseNewsFilter = true;
            gRt_UseSpikeFilter= true;
            gRt_UseVolMom     = true;
            gRt_UsePatterns   = true;
            gRt_UseFib        = true;
            gRt_ConsecLossSmooth = 2;
            gRt_SmoothMult    = 0.65;
            JournalInfo("RiskProfile","MODERATE/MED-RISK — default balanced settings");
            break;

         case 2:  // ── LOW-RISK (conservative) ──────────────────────
            gRt_RiskPct       = InpRiskPercent * 0.50; // half risk
            gRt_ModMinScore   = 72;      // higher bar = quality over quantity
            gRt_ModSLatrMult  = 1.20;    // tighter SL
            gRt_ModTP1R       = 0.50;
            gRt_ModTP2R       = 0.80;
            gRt_ModTP3R       = 1.20;
            gRt_ADXminMod     = 28;      // strong trend required
            gRt_UseNewsFilter = true;
            gRt_UseSpikeFilter= true;
            gRt_UseVolMom     = true;    // all filters ON for conservative
            gRt_UsePatterns   = true;
            gRt_UseFib        = true;
            gRt_UsePivot      = true;
            gRt_ConsecLossSmooth = 1;    // reduce lots after 1 loss
            gRt_SmoothMult    = 0.50;
            JournalInfo("RiskProfile","MODERATE/LOW-RISK — Risk50% Score72 tight SL all-filters-ON");
            break;
      }
   }

   // ══════════════════════════════════════════════════════════════
   // SCALPER MODE PRESETS
   // ══════════════════════════════════════════════════════════════
   else if(gBotMode == BOT_MODE_SCALPING)
   {
      switch(profile)
      {
         case 0:  // ── AGGRESSIVE ─────────────────────────────────
            gRt_RiskPct        = MathMin(InpRiskPercent * 1.30, 2.5);
            gRt_ScalpMinScore  = 60;
            gRt_ScalpSLatrMin  = 0.70;
            gRt_ScalpSLatrMax  = 0.90;
            gRt_ScalpTP1R      = 0.60;   // bigger TP1
            gRt_ADXminScalp    = 16;
            gRt_UseNewsFilter  = true;
            gRt_UseSpikeFilter = true;
            gRt_UseVolMom      = true;
            gRt_UsePatterns    = true;
            gRt_UseFib         = false;  // skip fib for speed
            gRt_SmoothMult     = 0.80;
            gRt_ConsecLossSmooth=3;
            JournalInfo("RiskProfile","SCALP/AGGRESSIVE — Risk+30% Score60 NoFib FastEntries");
            break;

         case 1:  // ── MED-RISK ─────────────────────────────────────
            gRt_RiskPct        = InpRiskPercent * 0.80; // slightly reduced for scalp
            gRt_ScalpMinScore  = 68;
            gRt_ScalpSLatrMin  = 0.80;
            gRt_ScalpSLatrMax  = 1.00;
            gRt_ScalpTP1R      = 0.50;
            gRt_ADXminScalp    = 18;
            gRt_UseNewsFilter  = true;
            gRt_UseSpikeFilter = true;
            gRt_UseVolMom      = true;
            gRt_UsePatterns    = true;
            gRt_UseFib         = true;
            gRt_SmoothMult     = 0.65;
            gRt_ConsecLossSmooth=2;
            JournalInfo("RiskProfile","SCALP/MED-RISK — balanced scalp settings");
            break;

         case 2:  // ── LOW-RISK ──────────────────────────────────────
            gRt_RiskPct        = InpRiskPercent * 0.40;
            gRt_ScalpMinScore  = 76;     // very selective
            gRt_ScalpSLatrMin  = 0.90;
            gRt_ScalpSLatrMax  = 1.10;
            gRt_ScalpTP1R      = 0.40;   // quick take-profit
            gRt_ADXminScalp    = 22;
            gRt_UseNewsFilter  = true;
            gRt_UseSpikeFilter = true;
            gRt_UseVolMom      = true;
            gRt_UsePatterns    = true;
            gRt_UseFib         = true;
            gRt_UsePivot       = true;
            gRt_SmoothMult     = 0.50;
            gRt_ConsecLossSmooth=1;
            JournalInfo("RiskProfile","SCALP/LOW-RISK — Risk40% Score76 max-filters quality-only");
            break;
      }
   }

   // ══════════════════════════════════════════════════════════════
   // HFT MODE PRESETS
   //   HFT uses small TFs only (M1/M5/M15). TP/SL in M1 ATR.
   //   Bidirectional: can flip direction on same bar.
   // ══════════════════════════════════════════════════════════════
   else // BOT_MODE_HFT
   {
      switch(profile)
      {
         case 0:  // ── AGGRESSIVE (max trade rate) ──────────────────
            gRt_RiskPct        = MathMin(InpRiskPercent * 1.20, 2.0);
            gRt_HFTMinScore    = 42;     // very permissive
            gRt_HFTSLatrMult   = 0.25;   // ultra-tight SL
            gRt_HFTTPr1        = 0.35;   // fast TP grab
            gRt_HFTTPr2        = 0.70;
            gRt_ADXminHFT      = 12;     // almost no ADX filter
            gRt_MaxSpreadATR   = 0.08;   // allow wider spread
            gRt_UseNewsFilter  = true;   // always keep news filter
            gRt_UseSpikeFilter = true;
            gRt_UseVolMom      = false;  // skip vol-mom for speed
            gRt_UsePatterns    = true;   // M1 patterns important
            gRt_UseFib         = false;  // not relevant at M1
            gRt_UsePivot       = false;
            gRt_HFTBidir       = true;
            gRt_HFTBidirCoolMs = 200;    // 200ms cooldown between flips
            gRt_SmoothMult     = 0.85;
            gRt_ConsecLossSmooth=4;
            JournalInfo("RiskProfile","HFT/AGGRESSIVE — Score42 SL0.25ATR MaxRate Bidir200ms");
            break;

         case 1:  // ── MED-RISK (balanced HFT) ──────────────────────
            gRt_RiskPct        = InpRiskPercent * 0.60; // HFT inherently smaller per-trade
            // HFT 11-component engine scores reach 48-62 on quality setups (max 98).
            // MODERATE/SCALP 8-component engine reaches 52-70 on quality setups (max 93).
            // Score distributions differ — HFT needs 48 to match equivalent signal quality.
            gRt_HFTMinScore    = (gBotMode == BOT_MODE_HFT) ? 48 : 52;
            gRt_HFTSLatrMult   = 0.30;
            gRt_HFTTPr1        = 0.40;
            gRt_HFTTPr2        = 0.80;
            gRt_ADXminHFT      = 15;
            gRt_MaxSpreadATR   = 0.06;
            gRt_UseNewsFilter  = true;
            gRt_UseSpikeFilter = true;
            gRt_UseVolMom      = true;
            gRt_UsePatterns    = true;
            gRt_UseFib         = false;
            gRt_UsePivot       = false;
            gRt_HFTBidir       = true;
            gRt_HFTBidirCoolMs = 500;
            gRt_SmoothMult     = 0.70;
            gRt_ConsecLossSmooth=3;
            JournalInfo("RiskProfile", StringFormat("%s/MED-RISK — Score%d SL0.30ATR balanced",
               gBotMode==BOT_MODE_HFT?"HFT":gBotMode==BOT_MODE_SCALPING?"SCALP":"MOD",
               gRt_HFTMinScore));
            break;

         case 2:  // ── LOW-RISK (conservative HFT) ──────────────────
            gRt_RiskPct        = InpRiskPercent * 0.35;
            gRt_HFTMinScore    = 62;     // strict for HFT
            gRt_HFTSLatrMult   = 0.40;   // slightly wider SL = more room
            gRt_HFTTPr1        = 0.50;
            gRt_HFTTPr2        = 1.00;
            gRt_ADXminHFT      = 20;
            gRt_MaxSpreadATR   = 0.04;   // very tight spread limit
            gRt_UseNewsFilter  = true;
            gRt_UseSpikeFilter = true;
            gRt_UseVolMom      = true;
            gRt_UsePatterns    = true;
            gRt_UseFib         = false;
            gRt_UsePivot       = false;
            gRt_HFTBidir       = false;  // no bidirectional — one direction at a time
            gRt_HFTBidirCoolMs = 2000;
            gRt_SmoothMult     = 0.50;
            gRt_ConsecLossSmooth=2;
            JournalInfo("RiskProfile","HFT/LOW-RISK — Score62 SL0.40ATR strict no-bidir");
            break;
      }
   }

   // ── Notify via Telegram if enabled ────────────────────────────────
   // NOTE: InpRiskProfile is now ENUM_RISK_PROFILE — (int)InpRiskProfile passes correctly
   string pLog = StringFormat("Profile: %s/%s | Risk:%.1f%% | MinScore:%d | Lot×%.2f",
      (gBotMode==BOT_MODE_HFT?"HFT":gBotMode==BOT_MODE_SCALPING?"SCALP":"MOD"),
      RiskProfileName(profile), gRt_RiskPct,
      (gBotMode==BOT_MODE_HFT?gRt_HFTMinScore:gBotMode==BOT_MODE_SCALPING?gRt_ScalpMinScore:gRt_ModMinScore),
      gRt_LotMultiplier);
   PushEAEvent("ProfileApply", pLog);
}

// ─────────────────────────────────────────────────────────────────────
// SECTION Y2 — DD LIMIT HELPER
//   Converts ENUM_DD_LIMIT to a percentage value.
// ─────────────────────────────────────────────────────────────────────
double DDLimitToPercent(ENUM_DD_LIMIT v)
{
   switch((int)v)
   {
      case 0:  return  1.0;
      case 1:  return  2.0;
      case 2:  return  3.0;
      case 3:  return  4.0;
      case 4:  return  5.0;
      case 5:  return  6.0;
      case 6:  return  8.0;
      case 7:  return 10.0;
      case 8:  return 15.0;
      case 9:  return 20.0;
      default: return  4.0;
   }
}

// ─────────────────────────────────────────────────────────────────────
// SECTION Y3 — SUB-MODE STRATEGY PRESETS
//
//   ApplySubMode() is the authoritative parameter engine.
//   It is called from OnInit AFTER ApplyRiskProfile().
//   It completely overrides all gRt_* shadow globals to match the
//   chosen strategy preset — score thresholds, SL/TP multiples,
//   ADX/filter requirements, risk%, DD ceiling, HFT cooldowns.
//
//   Parameter sources:
//     - Sub-mode presets below: best worldwide strategy combinations
//     - SUBMODE_AUTO_ADAPTIVE: delegates back to ApplyRiskProfile(3)
//     - SUBMODE_MANUAL_SETTINGS: reads all Inp* directly (no override)
//
//   IMPORTANT: Only gRt_* are modified. Input parameters are untouched.
// ─────────────────────────────────────────────────────────────────────
void ApplySubMode()
{
   gActiveSubMode = (int)InpSubMode;

   // ── MANUAL: copy all inputs verbatim ─────────────────────────────
   if(InpSubMode == SUBMODE_MANUAL_SETTINGS)
   {
      gRt_HFTMinScore    = InpHFTMinScore;
      gRt_ScalpMinScore  = InpScalpMinScore;
      gRt_ModMinScore    = InpModerateMinScore;
      gRt_RiskPct        = InpRiskPercent;
      gRt_LotMultiplier  = 1.00;
      gRt_HFTSLatrMult   = InpHFTSLATRMult;
      gRt_HFTTPr1        = InpHFTTP1R;
      gRt_HFTTPr2        = InpHFTTP2R;
      gRt_ScalpSLatrMin  = InpScalpSLATRMin;
      gRt_ScalpSLatrMax  = InpScalpSLATRMax;
      gRt_ScalpTP1R      = InpScalpTP1R;
      gRt_ModSLatrMult   = InpModerateSLATR;
      gRt_ModTP1R        = InpModerateTP1R;
      gRt_ModTP2R        = InpModerateTP2R;
      gRt_ModTP3R        = InpModerateTP3R;
      gRt_UseNewsFilter  = InpUseNewsFilter;
      gRt_UseSpikeFilter = InpUseSpikeDetection;
      gRt_UseVolMom      = InpUseVolumeMomentum;
      gRt_UsePatterns    = InpUseCandlePatterns;
      gRt_UseFib         = InpUseFibEngine;
      gRt_UsePivot       = InpUsePivotEngine;
      gRt_DailyDDPct     = InpMaxDailyLossPercent;
      JournalInfo("SubMode","MANUAL — all gRt_* loaded from input parameters");
      return;
   }

   // ── AUTO ADAPTIVE: delegate to regime-aware risk profile ─────────
   if(InpSubMode == SUBMODE_AUTO_ADAPTIVE)
   {
      gActiveRiskProfile = -1;  // force re-apply
      ApplyRiskProfile(3);      // 3 = AUTO-SWITCH
      // DD follows mode default
      gRt_DailyDDPct = (gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
                       ? DDLimitToPercent(InpDDLimitHFT) :
                       (gBotMode == BOT_MODE_SCALPING)
                       ? DDLimitToPercent(InpDDLimitScalp) :
                         DDLimitToPercent(InpDDLimitModerate);
      JournalInfo("SubMode","AUTO ADAPTIVE — regime-responsive, DD="+DoubleToString(gRt_DailyDDPct,1)+"%");
      return;
   }

   // ══════════════════════════════════════════════════════════════════
   // HFT SUB-MODES
   // All use M1/M5/M15 only. Bidir entries allowed. Market orders.
   // ══════════════════════════════════════════════════════════════════

   if(InpSubMode == SUBMODE_HFT_MOMENTUM_FLASH)
   {
      // ─── HFT: Momentum Flash ────────────────────────────────────────
      // Strategy: Capture tick-velocity momentum bursts during London/NY
      //           session opens. Ultra-short TP, maximum trade frequency.
      //           Best for: EURUSD, GBPUSD, USDJPY in active sessions.
      // ─────────────────────────────────────────────────────────────────
      gRt_HFTMinScore    = 45;          // accept momentum above 45% confidence
      gRt_HFTSLatrMult   = 0.20;        // 0.20× M1 ATR stop — ultra-tight, 2-4 pips
      gRt_HFTTPr1        = 0.35;        // TP1 at 0.35R — fast profit grab
      gRt_HFTTPr2        = 0.70;        // TP2 at 0.70R if momentum holds
      gRt_HFTBidir       = true;        // flip direction with market flow
      gRt_HFTBidirCoolMs = 150;         // 150ms minimum between direction flips
      gRt_MaxSpreadATR   = 0.04;        // spread must be < 4% ATR (very tight)
      gRt_ADXminHFT      = 10;          // minimal trend filter — any movement counts
      gRt_RiskPct        = 0.20;        // 0.20% per trade — ultra-small (60/hr × 0.20% = manageable)
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 5;         // allow 5 losses before reducing (high-freq expected)
      gRt_SmoothMult     = 0.80;        // gentle lot reduction on streak
      gRt_UseNewsFilter  = true;        // always block during hard news spikes
      gRt_UseSpikeFilter = true;        // spike = invalid tick data, always block
      gRt_UseVolMom      = false;       // vol momentum too slow for tick trades
      gRt_UsePatterns    = true;        // M1 candle body/wick patterns still valid
      gRt_UseFib         = false;       // fib levels irrelevant at 1-min scale
      gRt_UsePivot       = false;       // pivot levels not used (pure momentum)
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = 1.5;        // tight DD: 60 trades/hr can compound losses fast
      JournalInfo("SubMode","HFT:MomentumFlash — score45 SL0.20ATR TP0.35R/0.70R 60/hr DD1.5%");
   }
   else if(InpSubMode == SUBMODE_HFT_ORDERFLOW_SNIPER)
   {
      // ─── HFT: OrderFlow Sniper ───────────────────────────────────────
      // Strategy: Read BSP imbalance + order-flow direction bias.
      //           Enter only when flow clearly one-directional (≥62%).
      //           Balanced frequency — quality over pure speed.
      //           Best for: Any liquid major pair, any active session.
      // ─────────────────────────────────────────────────────────────────
      // v6.3c: Lowered from 52→48 — 11-component HFT engine (M3/M6/M10
      //        extended TFs) adds up to +18 pts; 52 was too tight given
      //        the score distribution in live CSV analysis (scores 49-51
      //        were being blocked at the gate before the new TFs loaded).
      gRt_HFTMinScore    = 48;          // balanced quality threshold
      gRt_HFTSLatrMult   = 0.30;        // 0.30× M1 ATR — 3-6 pips typical
      gRt_HFTTPr1        = 0.40;        // 0.40R grab then trail
      gRt_HFTTPr2        = 0.80;        // 0.80R full exit
      gRt_HFTBidir       = true;        // bidirectional allowed
      gRt_HFTBidirCoolMs = 500;         // 500ms between direction switches
      gRt_MaxSpreadATR   = 0.06;        // moderate spread tolerance
      gRt_ADXminHFT      = 15;          // light trend confirmation
      gRt_RiskPct        = 0.25;        // 0.25% — 40 trades/hr × 0.25% sustainable
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 4;
      gRt_SmoothMult     = 0.75;
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;        // volume confirmation improves flow reads
      gRt_UsePatterns    = true;
      gRt_UseFib         = false;
      gRt_UsePivot       = false;
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = DDLimitToPercent(InpDDLimitHFT);
      JournalInfo("SubMode","HFT:OrderFlowSniper — score48 SL0.30ATR TP0.40R/0.80R 40/hr DD"+DoubleToString(gRt_DailyDDPct,1)+"%");
   }
   else if(InpSubMode == SUBMODE_HFT_PRECISION_SCALP)
   {
      // ─── HFT: Precision Scalp ────────────────────────────────────────
      // Strategy: Quality-first HFT. Requires strong multi-indicator
      //           confluence even at tick level. Lower frequency but
      //           higher win-rate target. Best for conservative accounts.
      // ─────────────────────────────────────────────────────────────────
      gRt_HFTMinScore    = 62;          // high bar — only strong signals
      gRt_HFTSLatrMult   = 0.40;        // 0.40× ATR SL — more room to breathe
      gRt_HFTTPr1        = 0.50;        // 0.50R solid R:R
      gRt_HFTTPr2        = 1.00;        // 1.0R extended target when momentum strong
      gRt_HFTBidir       = true;
      gRt_HFTBidirCoolMs = 2000;        // 2s cooldown — no frantic flipping
      gRt_MaxSpreadATR   = 0.04;        // tight spread — only liquid conditions
      gRt_ADXminHFT      = 20;          // clear momentum required
      gRt_RiskPct        = 0.15;        // smallest risk — quality compensates
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 2;
      gRt_SmoothMult     = 0.60;
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;
      gRt_UsePatterns    = true;
      gRt_UseFib         = false;       // M1 too fast for fib, skip
      gRt_UsePivot       = true;        // pivot proximity adds quality filter
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = 1.5;         // very conservative DD for precision mode
      JournalInfo("SubMode","HFT:PrecisionScalp — score62 SL0.40ATR TP0.50R/1.0R 20/hr DD1.5%");
   }

   // ══════════════════════════════════════════════════════════════════
   // SCALPING SUB-MODES
   // M1-M30 range. Mix of market and pending limit orders.
   // ══════════════════════════════════════════════════════════════════

   else if(InpSubMode == SUBMODE_SCALP_BREAKOUT_SURGE)
   {
      // ─── Scalp: Breakout Surge ───────────────────────────────────────
      // Strategy: Identify key structural levels (pivot/EMA), wait for
      //           confirmed break with ATR burst + increasing volume.
      //           Enter M1 close beyond level; aggressive TP capture.
      //           Best for: News releases, London/NY overlap sessions,
      //                     pairs with clear price structure.
      // ─────────────────────────────────────────────────────────────────
      gRt_ScalpMinScore  = 64;          // moderate bar — burst confirmation does the heavy lifting
      gRt_ScalpSLatrMin  = 0.80;        // SL just below broken level
      gRt_ScalpSLatrMax  = 0.90;
      gRt_ScalpTP1R      = 0.60;        // aggressive TP1 — capture momentum fast
      gRt_ADXminScalp    = 20;          // need some directional strength for breakout
      gRt_HFTMinScore    = 52;          // not used in scalp mode but set sensibly
      gRt_ModMinScore    = 62;
      gRt_RiskPct        = InpRiskPercent * 1.00;
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 3;
      gRt_SmoothMult     = 0.75;
      gRt_UseNewsFilter  = true;        // breakouts near news = valid, spike = not
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;        // REQUIRED — volume surge validates breakout
      gRt_UsePatterns    = true;        // engulfing/momentum candle validates break
      gRt_UseFib         = false;       // breakouts don't need fib — price LEAVES fib
      gRt_UsePivot       = true;        // pivot IS the level we break
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = 3.0;         // active but not reckless
      JournalInfo("SubMode","Scalp:BreakoutSurge — score64 SL0.80ATR TP0.60R VolReq DD3.0%");
   }
   else if(InpSubMode == SUBMODE_SCALP_PULLBACK_PREC)
   {
      // ─── Scalp: Pullback Precision ───────────────────────────────────
      // Strategy: Confirm H1 trend direction. Identify M5 EMA34/50
      //           pullback zone. Enter on M1 reversal candle at EMA.
      //           Classic institution-grade pullback scalp.
      //           Best for: Trending days, any major pair.
      // ─────────────────────────────────────────────────────────────────
      gRt_ScalpMinScore  = 68;          // standard — full confluence required
      gRt_ScalpSLatrMin  = 0.85;        // SL below EMA support
      gRt_ScalpSLatrMax  = 1.00;
      gRt_ScalpTP1R      = 0.50;        // 1:2 RR target
      gRt_ADXminScalp    = 18;          // moderate trend (not too ranging)
      gRt_HFTMinScore    = 52;
      gRt_ModMinScore    = 62;
      gRt_RiskPct        = InpRiskPercent * 0.85; // slightly reduced for scalp
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 2;
      gRt_SmoothMult     = 0.65;
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;
      gRt_UsePatterns    = true;        // reversal candle at EMA is key signal
      gRt_UseFib         = true;        // golden zone pullback highly valid here
      gRt_UsePivot       = true;        // pivot proximity adds confluence
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = DDLimitToPercent(InpDDLimitScalp);
      JournalInfo("SubMode","Scalp:PullbackPrecision — score68 SL0.85ATR TP0.50R Fib+Pivot DD"+DoubleToString(gRt_DailyDDPct,1)+"%");
   }
   else if(InpSubMode == SUBMODE_SCALP_REVERSAL_SNIPE)
   {
      // ─── Scalp: Reversal Sniper ──────────────────────────────────────
      // Strategy: Wait for RSI extremes (OB/OS) at pivot or fib support.
      //           BSP must show reversal bias. Mean-reversion quick grab.
      //           Low ADX preferred (ranging markets). Counter-trend.
      //           Best for: Ranging/choppy sessions, Asia session,
      //                     USDJPY, EURGBP, range-bound pairs.
      // ─────────────────────────────────────────────────────────────────
      gRt_ScalpMinScore  = 60;          // lower bar — RSI extreme IS the main signal
      gRt_ScalpSLatrMin  = 0.70;        // tight SL — enter at extreme, abort fast if wrong
      gRt_ScalpSLatrMax  = 0.85;
      gRt_ScalpTP1R      = 0.40;        // quick grab at mean reversion point
      gRt_ADXminScalp    = 10;          // LOW ADX preferred — ranging market is correct
      gRt_HFTMinScore    = 52;
      gRt_ModMinScore    = 62;
      gRt_RiskPct        = InpRiskPercent * 0.70; // reduced — counter-trend = higher failure
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 2;
      gRt_SmoothMult     = 0.55;        // aggressive reduction on streak
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = false;       // ranging markets have LOW volume — not useful
      gRt_UsePatterns    = true;        // hammer/doji at extreme = key confirmation
      gRt_UseFib         = true;        // fib retracement levels critical for MR
      gRt_UsePivot       = true;        // pivot S/R = target mean levels
      gRt_UseAdxFilter   = false;       // ADX would reject most MR entries — disable gate
      gRt_DailyDDPct     = 2.5;         // conservative — counter-trend has higher risk
      JournalInfo("SubMode","Scalp:ReversalSniper — score60 SL0.70ATR TP0.40R RSI+Pivot noADX DD2.5%");
   }

   // ══════════════════════════════════════════════════════════════════
   // MODERATE SUB-MODES
   // H1-D1 macro confluence. Partial-close 3-TP system.
   // ══════════════════════════════════════════════════════════════════

   else if(InpSubMode == SUBMODE_MOD_TREND_RIDER)
   {
      // ─── Moderate: Trend Rider ───────────────────────────────────────
      // Strategy: Classic trend following. H1 + H4 EMA aligned.
      //           Enter on M30/H1 pullback to EMA34/50 with SMA800
      //           structural alignment. Wide SL for trend breathing.
      //           3-TP partial close: lock at 0.5R, extend to 2.0R.
      //           Best for: Trending pairs, major fundamental moves.
      // ─────────────────────────────────────────────────────────────────
      gRt_ModMinScore    = 62;          // full confluence — all macro layers required
      gRt_ModSLatrMult   = 1.60;        // 1.6× ATR SL — trend needs room to breathe
      gRt_ModTP1R        = 0.50;        // lock 30% at 0.5R
      gRt_ModTP2R        = 1.20;        // move 40% at 1.2R — solid RR
      gRt_ModTP3R        = 2.00;        // let 30% run to 2.0R on strong trend
      gRt_ADXminMod      = 22;          // clear trend required
      gRt_ScalpMinScore  = 68;
      gRt_HFTMinScore    = 52;
      gRt_RiskPct        = InpRiskPercent * 1.00;
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 2;
      gRt_SmoothMult     = 0.70;
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;        // volume confirms trend health
      gRt_UsePatterns    = true;        // pullback candle signals
      gRt_UseFib         = true;        // fib retracement entry zones
      gRt_UsePivot       = true;        // macro pivot alignment
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = DDLimitToPercent(InpDDLimitModerate);
      JournalInfo("SubMode","Mod:TrendRider — score62 SL1.60ATR TP0.5/1.2/2.0R DD"+DoubleToString(gRt_DailyDDPct,1)+"%");
   }
   else if(InpSubMode == SUBMODE_MOD_MOMENTUM_SWING)
   {
      // ─── Moderate: Momentum Swing ────────────────────────────────────
      // Strategy: Combines momentum (ADX+EMA burst) with swing structure
      //           (H4 level + fib zone). Enter on strong directional move
      //           with full indicator stack aligned. Balance between
      //           frequency and quality. The recommended default.
      //           Best for: Any major pair, trending + volatile sessions.
      // ─────────────────────────────────────────────────────────────────
      gRt_ModMinScore    = 68;          // above default — momentum needs solid backing
      gRt_ModSLatrMult   = 1.50;        // standard 1.5× ATR stop
      gRt_ModTP1R        = 0.50;        // 0.5R partial (30%)
      gRt_ModTP2R        = 1.00;        // 1.0R partial (40%)
      gRt_ModTP3R        = 1.80;        // 1.8R final (30%) — momentum target
      gRt_ADXminMod      = 25;          // strong trend required for momentum
      gRt_ScalpMinScore  = 68;
      gRt_HFTMinScore    = 52;
      gRt_RiskPct        = InpRiskPercent * 0.90; // slightly conservative
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 2;
      gRt_SmoothMult     = 0.65;
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;        // volume surge validates momentum
      gRt_UsePatterns    = true;        // momentum candle confirms
      gRt_UseFib         = true;        // fib confluence adds precision
      gRt_UsePivot       = true;        // pivot level as target or barrier
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = DDLimitToPercent(InpDDLimitModerate);
      JournalInfo("SubMode","Mod:MomentumSwing — score68 SL1.50ATR TP0.5/1.0/1.8R DD"+DoubleToString(gRt_DailyDDPct,1)+"%");
   }
   else if(InpSubMode == SUBMODE_MOD_SAFE_ACCUMULATOR)
   {
      // ─── Moderate: Safe Accumulator ──────────────────────────────────
      // Strategy: Ultra-selective swing trade. Requires all indicators
      //           aligned across H1+H4+D1. Half-risk per position.
      //           Wide TP targets — hold for larger moves.
      //           Best for: Strong macro trends, prop firm challenges,
      //                     drawdown recovery mode.
      // ─────────────────────────────────────────────────────────────────
      gRt_ModMinScore    = 78;          // only STRONG+ signals qualify
      gRt_ModSLatrMult   = 1.20;        // tighter SL — entry precision compensates
      gRt_ModTP1R        = 0.80;        // 0.8R lock (30%) — good immediate reward
      gRt_ModTP2R        = 1.50;        // 1.5R partial (40%)
      gRt_ModTP3R        = 2.50;        // 2.5R swing target (30%) — let it run
      gRt_ADXminMod      = 28;          // only strong established trends
      gRt_ScalpMinScore  = 76;          // if scalp triggers, same high bar
      gRt_HFTMinScore    = 62;
      gRt_RiskPct        = InpRiskPercent * 0.50; // half risk — preservation first
      gRt_LotMultiplier  = 1.00;
      gRt_ConsecLossSmooth = 1;          // reduce after first loss
      gRt_SmoothMult     = 0.50;        // aggressive reduction on loss streak
      gRt_UseNewsFilter  = true;
      gRt_UseSpikeFilter = true;
      gRt_UseVolMom      = true;        // all filters maxed for max quality
      gRt_UsePatterns    = true;
      gRt_UseFib         = true;
      gRt_UsePivot       = true;
      gRt_UseAdxFilter   = true;
      gRt_DailyDDPct     = 2.5;         // conservative — half-risk means 2.5% sufficient
      JournalInfo("SubMode","Mod:SafeAccumulator — score78 SL1.20ATR TP0.8/1.5/2.5R HalfRisk DD2.5%");
   }

   PushEAEvent("SubMode", "Applied: " + SubModeName());
}

// Returns the active sub-mode name for dashboard display
string SubModeName()
{
   switch(gActiveSubMode)
   {
      case  0: return "HFT:MomentumFlash";
      case  1: return "HFT:OrderFlowSniper";
      case  2: return "HFT:PrecisionScalp";
      case  3: return "Scalp:BreakoutSurge";
      case  4: return "Scalp:PullbackPrecision";
      case  5: return "Scalp:ReversalSniper";
      case  6: return "Mod:TrendRider";
      case  7: return "Mod:MomentumSwing";
      case  8: return "Mod:SafeAccumulator";
      case  9: return "AutoAdaptive";
      case 10: return "ManualSettings";
      default: return "Unknown";
   }
}

// ─────────────────────────────────────────────────────────────────────
// SECTION Z — EA EVENT LOG HELPER
//   Push a message to the rolling 16-slot event log displayed in the
//   WebView dashboard events bar and CCanvas overlay.
// ─────────────────────────────────────────────────────────────────────
void PushEAEvent(string gate, string reason)
{
   string ts = TimeToString(TimeLocal(), TIME_SECONDS);
   // Shift log down (index 0 = newest)
   for(int i = 14; i >= 0; i--)
      gEAEventLog[i+1] = gEAEventLog[i];
   gEAEventLog[0] = ts + "  [" + gate + "]  " + reason;

   // Track last block for dashboard highlight
   gLastBlockReason = reason;
   gLastBlockGate   = gate;
   gLastBlockTime   = TimeLocal();
   gBlockedTickCount++;
}

// ─── END OF COMPATIBILITY BRIDGE ───────────────────────────────────


#endif // SKP_P1B_COMPAT_MQH
