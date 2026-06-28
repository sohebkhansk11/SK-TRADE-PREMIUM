//+------------------------------------------------------------------+
//|  SK_TRADE_PREMIUM_BOT.mq5  —  Modular Entry Point v6.4          |
//|                                                                  |
//|  ARCHITECTURE: 8-module #include system                         |
//|  Compile THIS FILE only. Edit the .mqh modules below.           |
//|  No manual file merging needed — recompile to pick up changes.  |
//|                                                                  |
//|  MODULE MAP:                                                     |
//|  SKP_P1_Globals.mqh     Inputs · globals · structs · enums      |
//|  SKP_P1B_Compat.mqh     ApplySubMode · ApplyRiskProfile · PlaceTrade|
//|  SKP_P2_Indicators.mqh  Indicator handles · MTF wrappers        |
//|  SKP_P3_Entry.mqh       TryNewEntry · CalculateEntryLevels      |
//|  SKP_P4_TradeExec.mqh   CalcSL · CalcTieredTP · E7/E8 engines   |
//|  SKP_P5_BSP.mqh         BSP engine v6.3g (rolling candle-wise)  |
//|  SKP_P6_UI.mqh          Dashboard · Telegram · Journal · Events |
//|  SKP_P7_Main.mqh        Signal engines · OnInit/OnTick/OnTimer  |
//|                                                                  |
//|  WORKFLOW:                                                       |
//|  1. Open MetaEditor                                              |
//|  2. Open SK_TRADE_PREMIUM_BOT.mq5 (this file)                   |
//|  3. Edit any SKP_P*.mqh for the engine you want to change        |
//|  4. Press F7 (compile this file) — all modules recompile        |
//|  5. The .ex5 in the same folder is ready to drag to chart       |
//|                                                                  |
//|  FIXES INCLUDED (v6.3g):                                        |
//|  Fix 1  P1B  ApplySubMode log accuracy (score48 not score52)    |
//|  Fix 2  P3   HFT SL spread floor (3× spread minimum)           |
//|  Fix 3  P3   TryNewEntry Gate4 dynamic loss escalation          |
//|  Fix 4  P3   CheckDailyLossLimit includes floating P&L          |
//|  Fix 5  P4   CalcSL HFT branch (ATR + spread floor)            |
//|  Fix 6  P4   CalcTieredTP HFT branch (gRt_HFT R-multiples)     |
//|  Fix 7  P4   RegisterTradeRecord isScalp=true for HFT           |
//|  Fix 8  P1   BuySellPressure struct — rolling BSP fields        |
//|  Fix 9  P5   BSP engine full rebuild (CalcCandleWindowBSP)      |
//|  Fix 10 P7   gHFTOrderFlowBull bid-direction fix (tester safe)  |
//|  Fix 11 P7   HFT component weights recalibrated (EMA/BSP split) |
//|  Fix 12 P7   ProcessDealAdd fallback stat tracking              |
//|  Fix 13 P1B  PlaceTrade ticket recovery (PositionSelect)        |
//|                                                                  |
//|  FIXES INCLUDED (v6.3h):                                        |
//|  Fix 14 P7   BIAS_NONE threshold: BiDir HFT lowered 20→8       |
//|  Fix 15 P7   M5 opposing penalty: 0 in BiDir mode (was -4)     |
//|  Fix 16 P7   M3 opposing penalty: 0 in BiDir mode (was -2)     |
//|  Fix 17 P6   WebView JSON/HTML: IsTesting() guard (no ERR=5002)|
//|  Fix 18 P6   WriteSignalCSV: IsOptimization() guard            |
//|  Fix 19 P7   OnInit Step2d log: shows actual gate values        |
//|  Fix 20 P1   BuySellPressure struct: per-TF rolling fields     |
//|  Fix 21 P5   RefreshBuySellPressure: store+log per-TF rolling  |
//|                                                                  |
//|  FIXES INCLUDED (v6.3i):                                        |
//|  Fix 22 P1B  PartialCloseVolumeManaged(int idx) bridge added    |
//|              Without it P3 passed record idx 0-99 as ulong tkt  |
//|              → PositionSelectByTicket always failed → TP1 never |
//|              fired → TSL never armed → BE never set.            |
//|  Fix 23 P4   RegisterTradeRecord: HFT forces scalpTSLOnTick=true|
//|              (InpScalpTSLOnTick defaults false → dead-path TSL) |
//|  Fix 24 P4   ManageTradeRecordAdvanced TSL dead-path removed:   |
//|              isScalpMode+scalpTSLOnTick=false now falls back to  |
//|              ManageTrailing() instead of silently doing nothing. |
//|  Fix 25 P7   OnTick Step 8: P3 management loop replaced with    |
//|              RunAllPositionManagement() (P4 ticket-based).      |
//|              ManagePendingOrderAge kept for limit-order TTL.    |
//|                                                                  |
//|  FEATURES ADDED (v6.4):                                         |
//|  F1   PressureEngine wired: SKP_PressureEngine.mqh tick-by-tick |
//|       buy/sell ratio; Gate 13 blocks entry if < 60% directional |
//|  F2   Dual-EMA bias: M1 EMA9/34 AND EMA9/21 both must agree.   |
//|       Mixed pair → candle tiebreak (3 M1 candles OR M3 OR M5). |
//|  F3   EMA Touch Zone gate: blocks entry when price approaches   |
//|       opposing EMA9/21/34 on M1/3M/5M (radius = X×ATR).       |
//|       Rejection candle detected → allow counter-direction trade.|
//|  F4   11 HFT scoring weight multipliers in inputs (below HTML  |
//|       dashboard group) — tune each component 0.0–3.0×.         |
//|  F5   EMA21 handle added to all 9 TF slots; GetEMA21() wrapper |
//+------------------------------------------------------------------+

// ── Module includes (order is mandatory — each module depends on prior) ──
// SKP_PressureEngine is FIRST — it is standalone (no P1 deps) and defines
// CPressureEngine which is instantiated as gPressEng in P1_Globals below.
#include "SKP_PressureEngine.mqh"  // Tick-by-tick pressure engine (standalone)
#include "SKP_P1_Globals.mqh"      // Step 1: types, inputs, globals
#include "SKP_P1B_Compat.mqh"      // Step 2: sub-mode / risk profile engine
#include "SKP_P2_Indicators.mqh"   // Step 3: indicator handle layer
#include "SKP_P3_Entry.mqh"        // Step 4: entry decision stack
#include "SKP_P4_TradeExec.mqh"    // Step 5: trade execution & management
#include "SKP_P5_BSP.mqh"          // Step 6: buy/sell pressure engine
#include "SKP_P6_UI.mqh"           // Step 7: dashboard, telegram, journal
#include "SKP_P7_Main.mqh"         // Step 8: signal engines + event handlers
#include "SKP_P8_AI.mqh"           // Step 9: online win-probability model (pure MQL5)
