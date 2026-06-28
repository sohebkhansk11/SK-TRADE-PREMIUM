#ifndef SKP_P1_GLOBALS_MQH
#define SKP_P1_GLOBALS_MQH

//+------------------------------------------------------------------+
//|  ╔══════════════════════════════════════════════════════════════╗ |
//|  ║   🤖 SK TRADE PREMIUM BOT  |  NASA-GRADE INSTITUTIONAL EA   ║ |
//|  ║   Version: 6.3.0  |  Platform: MetaTrader 5  |  MQL5        ║ |
//|  ║   Architecture: 13-Engine · 10-Part · Single-File           ║ |
//|  ║   Asset: Universal (XAUUSD Primary)                          ║ |
//|  ║   © SK Trade Premium | All Rights Reserved                   ║ |
//|  ╚══════════════════════════════════════════════════════════════╝ |
//|                                                                    |
//|  ENGINES:                                                          |
//|  E1  Indicator Data       E8  Position Management                  |
//|  E2  EMA Ribbon/Matrix    E9  Safety Vault (The Vault)             |
//|  E3  MTF Cascade Bias     E10 Broker Sanity + Blackout             |
//|  E4  Fibonacci + Pivot    E11 Regime Engine                        |
//|  E5  Pattern Recognition  E12 Portfolio Watchlist                  |
//|  E6  Bias & Signal        E13 Lot Control                          |
//|  E7  Trade Execution      +   Telegram · Dashboard · Journal       |
//|                                +   Spike · News · Volume (v5.0)    |
//+------------------------------------------------------------------+
#property copyright   "SK Trade Premium"
#property version     "6.30"
#property description "🤖 SK TRADE PREMIUM BOT v6.3 — NASA-Grade Institutional EA"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Canvas\Canvas.mqh>

// ─── Enumerations — MUST precede input declarations ────────────────────
// Real MQL5 enums give named dropdowns in the MT5 parameter dialog.
// The numeric values are preserved so all existing comparisons still compile.

enum ENUM_BOT_MODE
{
   BOT_MODE_MODERATE  = 0,   // MODERATE  —  Trend-Following  (3-TP Partial Close)
   BOT_MODE_SCALPING  = 1,   // SCALPING  —  Precision Confluence  (Limit Orders)
   BOT_MODE_HFT       = 2,   // HFT       —  High-Frequency  (Tick-Level Market Orders)
   BOT_MODE_HFT_PURE  = 3    // HFT PURE  —  Gate-only, zero scoring, fire on all-clear
};

enum ENUM_LOT_MODE
{
   LOT_MODE_AUTO   = 0,     // AUTO    —  Risk % of Equity
   LOT_MODE_MANUAL = 1      // MANUAL  —  Fixed Lot Size
};

// Legacy #define aliases kept for backward-compatibility with P4/P5 code
// that uses BOT_MODE_MODERATE etc. directly without the enum prefix.
#define ENUM_BOT_MODE_   ENUM_BOT_MODE   // shim alias (zero-cost)
#define ENUM_LOT_MODE_   ENUM_LOT_MODE   // shim alias (zero-cost)

// ─── Risk Profile dropdown — pre-calibrated parameter bundle ─────────
//     Applied automatically by ApplyRiskProfile() during OnInit.
//     AGGRESSIVE: max trade frequency, wider score tolerance, higher risk%
//     MED-RISK:   balanced default — recommended for most accounts
//     LOW-RISK:   conservative capital preservation mode
//     AUTO-SWITCH: regime-aware, shifts profile based on market state
//     MANUAL:     no override — all individual inputs used exactly as set
enum ENUM_RISK_PROFILE
{
   RISK_PROFILE_AGGRESSIVE   = 0,  // AGGRESSIVE  — Max frequency, wider tolerance
   RISK_PROFILE_MED_RISK     = 1,  // MED-RISK    — Balanced default (RECOMMENDED)
   RISK_PROFILE_LOW_RISK     = 2,  // LOW-RISK    — Conservative capital preservation
   RISK_PROFILE_AUTO_SWITCH  = 3,  // AUTO-SWITCH — Regime-aware dynamic selection
   RISK_PROFILE_MANUAL       = 4   // MANUAL      — No override, use all inputs as-is
};

// ─── Sub-mode dropdown — selects a named trading strategy preset ─────
//
// Each sub-mode is a COMPLETE parameter preset optimised for a specific
// real-world trading strategy. ALL gRt_* runtime settings (score thresholds,
// SL/TP multiples, filters, risk%, DD ceiling, cooldowns) are applied
// automatically by ApplySubMode() during OnInit.
//
// USAGE:
//  1. Select your BOT_MODE (HFT / SCALPING / MODERATE).
//  2. Select the sub-mode that fits your market conditions.
//  3. For MANUAL, all parameters come from the input fields below.
//
// ─── HFT sub-modes (BOT_MODE_HFT) ────────────────────────────────────
//   Momentum Flash    — Tick-burst momentum, ultra-fast, 60 trades/hr
//   OrderFlow Sniper  — BSP + order-flow imbalance, balanced HFT
//   Precision Scalp   — Quality-only HFT, 20 trades/hr, tight spread
//
// ─── Scalping sub-modes (BOT_MODE_SCALPING) ──────────────────────────
//   Breakout Surge    — Key-level breakout + ATR burst + volume
//   Pullback Precision— H1-trend + M5 EMA pullback snipe (default)
//   Reversal Sniper   — RSI extreme + pivot/fib mean-reversion
//
// ─── Moderate sub-modes (BOT_MODE_MODERATE) ──────────────────────────
//   Trend Rider       — H1/H4 aligned trend following, 3-TP partial close
//   Momentum Swing    — Strong momentum entry, wider TP target
//   Safe Accumulator  — Half-risk, ultra-selective, long swing hold
//
// ─── Universal ───────────────────────────────────────────────────────
//   Auto Adaptive     — Regime-aware: switches preset based on market state
//   Manual Settings   — Use input parameters exactly as entered (no override)
//
enum ENUM_SUBMODE
{
   // ── HFT sub-modes ──────────────────────────────────────────────────
   SUBMODE_HFT_MOMENTUM_FLASH   = 0,  // HFT: Momentum Flash   — tick-burst, 60/hr, 0.20ATR SL
   SUBMODE_HFT_ORDERFLOW_SNIPER = 1,  // HFT: OrderFlow Sniper — BSP+flow, 40/hr, 0.30ATR SL (DEFAULT HFT)
   SUBMODE_HFT_PRECISION_SCALP  = 2,  // HFT: Precision Scalp  — quality-only, 20/hr, 0.40ATR SL
   // ── Scalping sub-modes ─────────────────────────────────────────────
   SUBMODE_SCALP_BREAKOUT_SURGE = 3,  // Scalp: Breakout Surge    — level break + ATR burst + volume
   SUBMODE_SCALP_PULLBACK_PREC  = 4,  // Scalp: Pullback Precision — H1 trend + M5 EMA pullback (DEFAULT SCALP)
   SUBMODE_SCALP_REVERSAL_SNIPE = 5,  // Scalp: Reversal Sniper   — RSI extreme + pivot/fib reversion
   // ── Moderate sub-modes ─────────────────────────────────────────────
   SUBMODE_MOD_TREND_RIDER      = 6,  // Moderate: Trend Rider      — H1/H4 trend follow, 3-TP partial
   SUBMODE_MOD_MOMENTUM_SWING   = 7,  // Moderate: Momentum Swing   — strong momentum, wider TP (DEFAULT MOD)
   SUBMODE_MOD_SAFE_ACCUMULATOR = 8,  // Moderate: Safe Accumulator — half-risk, selective, swing hold
   // ── Universal ──────────────────────────────────────────────────────
   SUBMODE_AUTO_ADAPTIVE        = 9,  // Auto Adaptive — regime-aware: Hostile→Safe, Explosive→Momentum
   SUBMODE_MANUAL_SETTINGS      = 10  // Manual Settings — no override, all inputs used as-is
};

// ─── Drawdown limit dropdown ─────────────────────────────────────────
// Sets the per-session daily drawdown ceiling for the selected mode.
// Each mode has its own DD limit input below; this is a shared reference.
enum ENUM_DD_LIMIT
{
   DD_LIMIT_1PCT  = 0,  // Daily DD limit:  1.0%  (ultra-conservative)
   DD_LIMIT_2PCT  = 1,  // Daily DD limit:  2.0%  (conservative)
   DD_LIMIT_3PCT  = 2,  // Daily DD limit:  3.0%  (cautious)
   DD_LIMIT_4PCT  = 3,  // Daily DD limit:  4.0%  (standard) ← DEFAULT
   DD_LIMIT_5PCT  = 4,  // Daily DD limit:  5.0%  (active)
   DD_LIMIT_6PCT  = 5,  // Daily DD limit:  6.0%  (active-aggressive)
   DD_LIMIT_8PCT  = 6,  // Daily DD limit:  8.0%  (aggressive)
   DD_LIMIT_10PCT = 7,  // Daily DD limit: 10.0%  (high-risk)
   DD_LIMIT_15PCT = 8,  // Daily DD limit: 15.0%  (very high-risk)
   DD_LIMIT_20PCT = 9   // Daily DD limit: 20.0%  (extreme / tournament)
};

//════════════════════════════════════════════════════════════════════
//  ⚙️  PART 1 — ALL INPUT PARAMETERS
//════════════════════════════════════════════════════════════════════

//── GROUP: MASTER CONTROLS ──────────────────────────────────────────
input group             "═══ 🤖 MASTER CONTROLS ═══"
input bool              InpEnableBot                 = true;       // ✅ Master ON/OFF — false = immediate halt
input bool              InpAllowBuy                  = true;       // 🟢 Allow BUY (Long) entries
input bool              InpAllowSell                 = true;       // 🔴 Allow SELL (Short) entries
input ENUM_BOT_MODE      InpMode                     = BOT_MODE_MODERATE; // 🎯 Trading mode (dropdown)
input ENUM_SUBMODE       InpSubMode                  = SUBMODE_MOD_MOMENTUM_SWING; // 🎛️ Sub-mode strategy preset (see enum comments above)
input bool              InpOneExposurePerSymbol       = true;       // 🔒 Block new entry if symbol already has position
input bool              InpPauseByButtonAtStart       = false;      // ⏸️ Start in paused state
input long              InpMagic                     = 909090;     // 🔢 EA Magic Number

//── GROUP: RISK MATRIX & DRAWDOWN LIMITS ────────────────────────────
input group             "═══ 🛡️ RISK MATRIX & DRAWDOWN ═══"
input double            InpRiskPercent               = 1.00;       // 💰 Risk per trade (% of equity)
input double            InpEquityFloor               = 0.0;        // 🛡️ Equity floor in account currency USD (0=disabled)
input double            InpMaxDailyLossPercent        = 4.0;        // 💤 Daily loss limit % (overridden by mode DD below)
input ENUM_DD_LIMIT      InpDDLimitHFT               = DD_LIMIT_2PCT; // ⚡ HFT mode: daily DD limit (default 2%)
input ENUM_DD_LIMIT      InpDDLimitScalp             = DD_LIMIT_3PCT; // 📊 Scalping mode: daily DD limit (default 3%)
input ENUM_DD_LIMIT      InpDDLimitModerate          = DD_LIMIT_4PCT; // 🎯 Moderate mode: daily DD limit (default 4%)
input double            InpMaxGlobalDrawdownPercent   = 7.0;        // 🛡️ Floating DD limit % → block new entries
input int               InpConsecutiveLossForSmooth   = 2;          // 📉 Consec losses before smoothening activates
input double            InpSmootheningMultiplier      = 0.65;       // ✂️ Lot multiplier after consec losses
input int               InpMaxSlippagePoints          = 25;         // 📐 Max slippage points on market orders

//── GROUP: INDICATOR TUNERS ─────────────────────────────────────────
input group             "═══ 📊 INDICATOR TUNERS ═══"
input int               InpEMAFast                   = 9;          // ⚡ Fast EMA — ignition trigger
input int               InpEMASlow                   = 34;         // 🌊 Slow EMA — momentum structure
input int               InpEMA50                     = 50;         // 📊 EMA50 — structural S/R
input int               InpEMA100                    = 100;        // 📊 EMA100 — structural baseline
input int               InpEMA200                    = 200;        // 📊 EMA200 — macro trend
input int               InpSMA21                     = 21;         // 📏 SMA21
input int               InpSMA50                     = 50;         // 📏 SMA50
input int               InpSMA100                    = 100;        // 📏 SMA100
input int               InpSMA200                    = 200;        // 📏 SMA200
input int               InpSMA800                    = 800;        // 🏦 SMA800 — INSTITUTIONAL BASELINE
input int               InpRSIPeriod                 = 14;         // 📈 RSI period
input int               InpRSICurveLookback          = 4;          // 🔄 RSI slope lookback bars
input bool              InpRSIUseCurveLogic          = true;       // ✅ Enable RSI 4-state quadrant
input bool              InpRSIExhaustionExit         = true;       // ⚠️ Enable RSI exhaustion partial exit
input int               InpRSIExhaustionBars         = 3;          // 🔢 Consecutive counter-trend bars = exhaustion
input int               InpADXPeriod                 = 14;         // 📉 ADX period
input int               InpATRPeriod                 = 14;         // 📐 ATR period

//── GROUP: MTF CASCADE CONFLUENCE ───────────────────────────────────
input group             "═══ 🌐 MTF CASCADE CONFLUENCE ═══"
input bool              InpUseM1                     = true;       // 🕐 Enable M1 TF (weight 0.5)
input bool              InpUseM5                     = true;       // 🕔 Enable M5 TF (weight 1.0) — PRIMARY
input bool              InpUseM10                    = true;       // 🕙 Enable M10 TF (weight 1.0)
input bool              InpUseM15                    = true;       // 🕞 Enable M15 TF (weight 1.0)
input bool              InpUseM30                    = true;       // 🕧 Enable M30 TF (weight 1.5)
input bool              InpUseH1                     = true;       // 🕐 Enable H1 TF (weight 2.0) — MACRO ANCHOR
input bool              InpUseH4                     = true;       // 🕓 Enable H4 TF (weight 3.0) — MACRO CONFIRM
input bool              InpRequireFibConfluence      = true;       // 📐 Require Fib golden zone hit
input bool              InpRequirePivotConfluence    = true;       // 🎯 Require pivot level proximity
input int               InpSwingLookbackBars         = 50;         // 🔭 Fractal swing lookback bars
input int               InpSignalCooldownSeconds     = 30;         // ⏱️ Min seconds between signal evaluations
input double            InpMinCascadeScore           = 0.40;       // 📊 Min MTF cascade score (0.0–1.0)
input int               InpCascadeHoldBars           = 3;          // 🔒 Anti-flicker: bias hold bars
input bool              InpHTFSingleMode             = false;      // 🔧 H1 alone if H4 disabled (req score≥0.60)
input double            InpFibConflTolerance         = 0.20;       // 📐 Fib zone ATR tolerance multiplier
input double            InpPivotConflTolerance       = 0.30;       // 🎯 Pivot proximity ATR tolerance

//── GROUP: EXECUTION — MODERATE MODE ────────────────────────────────
input group             "═══ 🎯 EXECUTION — MODERATE MODE ═══"
input double            InpModerateSLATR             = 1.50;       // 🛑 SL = 1.5 × ATR beyond fractal swing
input double            InpModerateTP1R              = 0.50;       // 🎯 TP1 R-multiple (0.5:1 RR)
input double            InpModerateTP2R              = 1.00;       // 🎯 TP2 R-multiple (1:1 RR)
input double            InpModerateTP3R              = 1.50;       // 🎯 TP3 R-multiple (1.5:1 RR) — BROKER HARD TP
input double            InpModerateTSLATR            = 1.20;       // 🔄 TSL trail step ATR multiplier
input double            InpTP1VolPct                 = 0.30;       // 📦 30% volume closed at TP1
input double            InpTP2VolPct                 = 0.40;       // 📦 40% volume closed at TP2
input double            InpTP3VolPct                 = 0.30;       // 📦 30% volume closed at TP3

//── GROUP: EXECUTION — SCALPING MODE ────────────────────────────────
input group             "═══ ⚡ EXECUTION — SCALPING MODE ═══"
input double            InpScalpSLATRMin             = 0.80;       // 🛑 Scalp SL min ATR multiplier
input double            InpScalpSLATRMax             = 1.00;       // 🛑 Scalp SL max ATR multiplier
input double            InpScalpTP1R                 = 0.50;       // 🎯 Scalp TP1 R-multiple
input double            InpScalpTSLATRFraction       = 0.75;       // 🔄 Scalp TSL fractional ATR step (v6.5: 0.35→0.75 — let post-BE runners breathe to TP2/TP3; raises avg win / RR)
input bool              InpScalpTSLOnTick            = true;       // ⚡ Scalp TSL update every tick
input double            InpPendingOffsetPoints       = 15.0;       // 📍 BuyLimit/SellLimit offset from price
input int               InpPendingExpiryMinutes      = 45;         // ⏰ Pending order auto-expiry minutes
input double            InpScalpFastBER              = 0.35;       // 🔒 Fast BE lock at R-multiple
input double            InpScalpBEArmR               = 0.0;        // 🔒 Delay ALL breakeven arming until profit ≥ this R (0 = arm at TP1 as before; raise to let runners reach TP2/TP3 → higher RR)
input double            InpScalpProfitLockR1         = 0.60;       // 🔒 Profit-lock step 1 R-level
input double            InpScalpProfitLockR2         = 0.90;       // 🔒 Profit-lock step 2 R-level
input double            InpScalpProfitLockR3         = 1.20;       // 🔒 Profit-lock step 3 R-level
input double            InpScalpProfitLockATR1       = 0.15;       // 📐 ATR buffer at step 1 (v6.5: 0.10→0.15 — lock floor sits above BE without choking the runner)
input double            InpScalpProfitLockATR2       = 0.30;       // 📐 ATR buffer at step 2 (v6.5: 0.20→0.30)
input double            InpScalpProfitLockATR3       = 0.55;       // 📐 ATR buffer at step 3 (v6.5: 0.35→0.55 — keep ~0.55R locked while leaving room to TP3)
input double            InpScalpBurstATRFactor       = 1.25;       // 💥 ATR burst: bar range > ATR × factor
input double            InpScalpSpreadCompressionFactor = 0.70;    // 📉 Spread compressed: spread < ATR × factor
input double            InpScalpMicroPullbackATR     = 0.20;       // 🔄 Micro-pullback: retrace < ATR × factor
input int               InpScalpCrossLookbackBars    = 3;          // 🔭 Fresh cross within last N bars
input int               InpScalpSignalPersistBars    = 2;          // ⏱️ Signal valid for N bars after cross
input int               InpScalpPendingMaxAgeSec     = 180;        // ⏰ Max age (sec) for scalp pending order
input int               InpScalpPostExitCooldownSec  = 45;         // ⏸️ Cooldown after scalp exit

//── GROUP: SCALPER ENTRY GUARDS ─────────────────────────────────────
input group             "═══ 🔒 SCALPER ENTRY GUARDS ═══"
input bool              InpScalpRequireATRBurst      = true;       // 💥 Require ATR burst confirmation
input bool              InpScalpRequireSpreadComp    = true;       // 📉 Require spread compression
input bool              InpScalpRequireFreshCross    = true;       // ⚡ Require fresh EMA cross (within lookback)
input bool              InpScalpRequireMicroPullback = true;       // 🔄 Require micro-pullback
input bool              InpScalpRequireDualLTF       = true;       // 🌐 M1 + M5 must both confirm direction
input bool              InpScalpIgnoreADXIfBurst     = true;       // 💥 Bypass ADX gate if burst confirmed
input bool              InpScalpUseProfitLockSteps   = true;       // 🔒 Enable 3-step profit-lock TSL
input bool              InpScalpLockBEFast           = true;       // 🔒 Enable fast breakeven lock
input bool              InpScalpUseDedicatedScore    = true;       // 📊 Scalper uses own score weights
input bool              InpScalpCancelAgedPending    = true;       // ♻️ Auto-cancel aged pending orders
input bool              InpScalpRequireVolumeMom     = false;      // 📊 Hard-require volume confirmation

//── GROUP: EXECUTION — HFT MODE ─────────────────────────────────────
input group             "═══ ⚡⚡ EXECUTION — HFT MODE ═══"
input double            InpHFTSLATRMult              = 0.30;       // 🛑 HFT SL = 0.3 × M1 ATR (ultra-tight)
input double            InpHFTTP1R                   = 0.40;       // 🎯 HFT TP1 R-multiple (0.4:1 — fast grab)
input double            InpHFTTP2R                   = 0.80;       // 🎯 HFT TP2 R-multiple (0.8:1)
input double            InpHFTFastBER                = 0.25;       // 🔒 HFT fast BE lock R-level (25% profit)
input double            InpHFTRiskPercent            = 0.25;       // 💰 HFT risk per trade % (very small)
input double            InpHFTManualLot              = 0.01;       // 📦 HFT fixed lot (manual mode)
input int               InpHFTPendingMaxAgeSec       = 25;         // ⏰ HFT pending order max age (sec)
input int               InpHFTPostExitCooldownSec    = 10;         // ⏸️ HFT cooldown after exit (sec)
input int               InpHFTMaxTradesPerHour       = 40;         // 🔢 Rate limiter — max entries / hour
input int               InpHFTMinScore               = 52;         // ⚡ HFT min score to enter (lower = more trades)
input double            InpHFTMaxSpreadFactor        = 0.06;       // 📡 HFT max spread = ATR × this factor
input double            InpHFTTickVelocityMin        = 1.0;        // 🚀 Min tick/sec velocity for HFT entry (0=disabled; was 4.0, too restrictive in quiet markets)
input double            InpHFTOrderFlowBiasMin       = 0.52;       // 📊 Min order flow imbalance ratio (0.52=52% directional; was 0.62 — 0.0=disabled)
input bool              InpHFTRequireDualM1M5        = true;       // 🌐 Require M1 + M5 both confirm
input bool              InpHFTUseMarketOrder         = true;       // 🚀 Use market orders (vs limit) in HFT mode
input bool              InpHFTUseProfitLock          = true;       // 🔒 Enable HFT 2-step profit lock TSL
input double            InpHFTProfitLockR1           = 0.30;       // 🔒 HFT profit lock step 1 (R-level)
input double            InpHFTProfitLockR2           = 0.60;       // 🔒 HFT profit lock step 2 (R-level)
input bool              InpHFTSuppressLowVolSession  = true;       // 🕐 Skip entries during low-volume sessions
input bool              InpHFTRequireSpreadComp      = true;       // 📉 Require tighter spread in HFT mode
input bool              InpHFTCancelAgedPending      = true;       // ♻️ Auto-cancel aged HFT pending orders
input bool              InpHFTRespectHTFFilter       = false;      // 🚫 HFT: apply D1/H4 counter-trend gate (OFF=HFT ignores D1/H4, ON=same gate as other modes)

//── GROUP: SCORE WEIGHTS ─────────────────────────────────────────────
input group             "═══ ⚖️ SCORE WEIGHTS ═══"
input int               InpScalpMinScore             = 68;         // ⚡ Scalper min score to enter
input int               InpModerateMinScore          = 62;         // 🎯 Moderate min score to enter
input int               InpScoreStrongThreshold      = 78;         // 💪 Score ≥ 78 = STRONG label
input int               InpScoreExtremeThreshold     = 88;         // 🔥 Score ≥ 88 = EXTREME label
input int               InpWMacroAlign               = 14;         // ⚖️ H1+H4 EMA alignment weight
input int               InpWSMA800                   = 15;         // ⚖️ SMA800 baseline compliance weight
input int               InpWRSIQuadrant              = 12;         // ⚖️ RSI strong quadrant weight
input int               InpWRSIFlip                  = 8;          // ⚖️ RSI slope flip weight
input int               InpWPattern                  = 10;         // ⚖️ Pattern on confluence zone weight
input int               InpWFibConfluence            = 10;         // ⚖️ Fibonacci zone weight
input int               InpWPivotConfluence          = 7;          // ⚖️ Pivot level proximity weight
input int               InpWADX                      = 8;          // ⚖️ ADX trend gate pass weight
input int               InpWLTFTrigger               = 12;         // ⚖️ Fresh M5 EMA cross weight
input int               InpWATRBurst                 = 7;          // ⚖️ ATR burst confirmation weight
input int               InpWSpreadCompression        = 5;          // ⚖️ Spread compressed weight
input int               InpWSessionBoost             = 4;          // ⚖️ London/NY session boost weight
input int               InpWTrendStructure           = 8;          // ⚖️ EMA50>EMA100 trend structure weight
input int               InpWDualLTF                  = 6;          // ⚖️ Dual LTF confirm weight
input int               InpWMicroPullback            = 5;          // ⚖️ Micro-pullback weight
input int               InpWVolumeMomentum           = 8;          // ⚖️ Volume momentum weight (v5.0)
input int               InpLossStreakPenaltyStep      = 8;          // 📉 Points penalty per consecutive loss

//── GROUP: FILTERS ───────────────────────────────────────────────────
input group             "═══ 🔍 FILTERS ═══"
input bool              InpUseADXFilter              = true;       // 📉 ADX gatekeeper active
input double            InpADXMinModerate            = 25.0;       // 📉 ADX minimum — Moderate mode
input double            InpADXMinScalp               = 18.0;       // 📉 ADX minimum — Scalper (relaxed)
input bool              InpUseDynamicSpreadFilter    = true;       // 📡 Dynamic ATR-based spread filter
input double            InpSpreadATRFactor           = 0.10;       // 📡 MaxSpread = ATR × this factor
input bool              InpUseSessionFilter          = false;      // 🕐 Session time window filter
input int               InpSessionStartHour          = 7;          // 🕐 Session start hour
input int               InpSessionEndHour            = 22;         // 🕓 Session end hour
input bool              InpUseProfileSessions        = true;       // 🌍 Use asset-class auto sessions
input bool              InpUseEMAFilter              = true;       // 📊 Use EMA ribbon filter
input bool              InpUseSMAFilter              = true;       // 📊 Use SMA800 macro baseline filter
input bool              InpUseRSIFilter              = true;       // 📈 Use RSI quadrant filter
input bool              InpUseATRDynamic             = true;       // 📐 Use ATR for dynamic sizing
input bool              InpUseFibEngine              = true;       // 📐 Use Fibonacci engine
input bool              InpUsePivotEngine            = true;       // 🎯 Use Pivot engine
input bool              InpUseCandlePatterns         = true;       // 🕯️ Use candlestick patterns
input bool              InpUseChartPatterns          = true;       // 📈 Use chart structure patterns
input bool              InpCloseOnOppositeSignal     = true;       // 🔄 Close on opposing EMA cross

//── GROUP: BROKER SANITY & BLACKOUT ─────────────────────────────────
input group             "═══ 🔬 BROKER SANITY & BLACKOUT ═══"
input bool              InpUseBrokerSanityChecks     = true;       // 🔬 Enable all broker sanity checks
input bool              InpUseSpreadShockFilter      = true;       // ⚡ Spread shock filter
input double            InpSpreadShockFactor         = 2.5;        // ⚡ Spread shock: spread > ATR × factor
input bool              InpUseTickVelocityFilter     = true;       // 🚀 Tick velocity shock filter
input double            InpTickVelocityATRFactor     = 0.30;       // 🚀 Velocity shock threshold
input int               InpVelocitySampleTicks       = 10;         // 🔢 Velocity sample window (ticks)
input bool              InpUseGapShockFilter         = true;       // 📊 Bar gap shock filter
input double            InpGapATRFactor              = 0.50;       // 📊 Gap shock threshold
input bool              InpUseStopLevelCheck         = true;       // 🛑 Broker stop level check
input double            InpMaxStopLevelATRFactor     = 0.50;       // 🛑 Stop level hostile threshold
input bool              InpUseFreezeLevelCheck       = true;       // 🧊 Broker freeze level check
input bool              InpUseScalpHostileExit       = true;       // 🚨 Emergency close scalp on hostile
input bool              InpUseManualBlackout         = true;       // ⛔ Manual blackout windows
input string            InpBlackoutWindow1           = "0000-0000";// ⛔ Blackout 1 HH:MM-HH:MM
input string            InpBlackoutWindow2           = "0000-0000";// ⛔ Blackout 2 HH:MM-HH:MM
input string            InpBlackoutWindow3           = "0000-0000";// ⛔ Blackout 3 HH:MM-HH:MM
input bool              InpUseAdaptiveScorePenalty   = true;       // 📉 Loss-streak score penalty
input bool              InpUseLossStreakCooldown      = true;       // ⏸️ Loss-streak cooldown waits
input int               InpLossStreakCooldown1Sec     = 90;         // ⏸️ Cooldown after 1 loss (sec)
input int               InpLossStreakCooldown2Sec     = 180;        // ⏸️ Cooldown after 2 losses (sec)
input int               InpLossStreakCooldown3Sec     = 300;        // ⏸️ Cooldown after 3+ losses (sec)

//── GROUP: SPIKE DETECTION (v5.0) ───────────────────────────────────
input group             "═══ 🚨 SPIKE DETECTION ENGINE (v5.0) ═══"
input bool              InpUseSpikeDetection         = true;       // 🚨 Enable spike detection filter
input double            InpSpikeATRFactor            = 0.50;       // 🚨 Spike: tick range > ATR × factor
input int               InpSpikeWindowSec            = 3;          // 🕐 Rolling window seconds for spike
input bool              InpBlockEntryOnSpike         = true;       // 🚫 Block entries during spike
input bool              InpCloseScalpOnSpike         = true;       // 🚨 Emergency-close profitable scalp on spike

//── GROUP: NEWS FILTER (v5.0) ───────────────────────────────────────
input group             "═══ 📰 NEWS FILTER ENGINE (v5.0) ═══"
input bool              InpUseNewsFilter             = true;       // 📰 Enable news filter engine
input string            InpNewsWindowCSV             = "";         // 📅 Manual news: WEEKDAY,HH:MM,MIN;...
input int               InpNewsPreBufferMin          = 5;          // ⏰ Block N min BEFORE news window
input int               InpNewsPostBufferMin         = 5;          // ⏰ Block N min AFTER news window
input bool              InpUseImpliedNewsFilter      = true;       // 📡 Auto-detect news via spread/ATR
input double            InpNewsImpliedSpreadMult     = 2.50;       // 📡 Implied: spread > ATR × factor
input bool              InpNewsAllowManageOnly       = true;       // 🛡️ During news: manage only, no new entries
input bool              InpNewsTelegramAlert         = true;       // 📡 Alert when news window starts/ends

//── GROUP: VOLUME MOMENTUM (v5.0) ───────────────────────────────────
input group             "═══ 📊 VOLUME MOMENTUM ENGINE (v5.0) ═══"
input bool              InpUseVolumeMomentum         = true;       // 📊 Enable volume momentum scoring
input int               InpVolMomLookback            = 14;         // 📊 Average volume lookback (M5 bars)
input double            InpVolMomBullFactor          = 1.30;       // 📊 Bull: vol > avg × factor + up close
input double            InpVolMomBearFactor          = 1.30;       // 📊 Bear: vol > avg × factor + down close

//── GROUP: REGIME ENGINE ────────────────────────────────────────────
input group             "═══ 🌡️ REGIME ENGINE (Block 9) ═══"
input bool              InpUseRegimeEngine           = true;       // 🌡️ Enable market regime classification
input int               InpRegimeATRPeriod           = 14;         // 📐 ATR period for regime baseline
input int               InpRegimeLookbackBars        = 20;         // 📊 ATR average lookback bars
input double            InpQuietATRRatioMax          = 0.70;       // 💤 ATR ratio < this = QUIET regime
input double            InpExplosiveATRRatioMin      = 1.50;       // 💥 ATR ratio > this = EXPLOSIVE regime
input double            InpHostileSpreadFactor       = 3.0;        // ☠️ Spread × factor vs ATR = HOSTILE
input double            InpHostileVelocityFactor     = 0.50;       // ☠️ Velocity vs ATR = HOSTILE
input double            InpRegimeQuietLotMult        = 0.75;       // ✂️ Lot multiplier in QUIET
input double            InpRegimeExplosiveLotMult    = 0.60;       // ✂️ Lot multiplier in EXPLOSIVE
input double            InpRegimeHostileLotMult      = 0.35;       // ✂️ Lot multiplier in HOSTILE
input bool              InpUseRegimeScalpSuppress    = true;       // 🔇 Suppress scalper in QUIET/HOSTILE
input int               InpRegimeMaxModifyRetries    = 3;          // 🔄 Max modify recovery retries

//── GROUP: LOT CONTROL ──────────────────────────────────────────────
input group             "═══ 💰 LOT CONTROL ENGINE (Block 8) ═══"
input ENUM_LOT_MODE     InpLotControlMode            = LOT_MODE_AUTO; // 💰 Lot sizing mode (dropdown)
input double            InpModerateRiskPercent       = 1.0;        // 💰 Moderate mode risk %
input double            InpScalpRiskPercent          = 0.6;        // 💰 Scalper mode risk %
input double            InpModerateManualLot         = 0.10;       // 📦 Moderate fixed lot (manual mode)
input double            InpScalpManualLot            = 0.05;       // 📦 Scalper fixed lot (manual mode)
input double            InpModerateMinLot            = 0.01;       // 📏 Moderate min lot cap
input double            InpModerateMaxLot            = 5.00;       // 📏 Moderate max lot cap
input double            InpScalpMinLot               = 0.01;       // 📏 Scalper min lot cap
input double            InpScalpMaxLot               = 2.00;       // 📏 Scalper max lot cap
input bool              InpApplyLossSmoothToAuto     = true;       // ✂️ Apply smoothening to auto lots
input bool              InpApplyLossSmoothToManual   = false;      // ✂️ Apply smoothening to manual lots
input bool              InpApplyPortfolioMultToManual= false;      // 📊 Apply portfolio mult to manual lots

//── GROUP: PORTFOLIO WATCHLIST ───────────────────────────────────────
input group             "═══ 📋 PORTFOLIO WATCHLIST (Block 7) ═══"
input bool              InpUsePortfolioWatchlist     = false;      // 📋 Enable multi-symbol scanning
input string            InpPortfolioWatchlist        = "";         // 📋 CSV symbols: "XAUUSD,EURUSD,GBPUSD"
input int               InpPortfolioScanIntervalSec  = 60;         // ⏱️ Rescan interval (seconds)
input int               InpPortfolioMaxTradableRanks = 3;          // 🏆 Max tradable rank slots
input bool              InpPortfolioBlockNonTop      = true;       // 🔒 Block chart if not top-ranked
input int               InpPortfolioMinScoreGap      = 10;         // 📊 Min score gap for rank priority
input bool              InpPortfolioReqSameBias      = true;       // 🎯 Must match top symbol bias
input int               InpPortfolioMinCandScore     = 50;         // 📊 Min score to be candidate
input bool              InpPortfolioSkipWithExposure = true;       // 🔒 Skip symbols with open positions
input bool              InpPortfolioUseRiskThrottle  = true;       // ✂️ Reduce lot by rank
input double            InpPortfolioRank1Mult        = 1.00;       // 💰 Rank 1 risk multiplier
input double            InpPortfolioRank2Mult        = 0.70;       // 💰 Rank 2 risk multiplier
input double            InpPortfolioRank3Mult        = 0.50;       // 💰 Rank 3 risk multiplier
input double            InpPortfolioExposureMult     = 0.60;       // 💰 Exposure risk multiplier

//── GROUP: SYMBOL PRESET ─────────────────────────────────────────────
input group             "═══ 🎯 SYMBOL PRESET ENGINE (Block 10) ═══"
input bool              InpUseSymbolPresetMap        = true;       // 🗺️ Enable symbol preset risk multipliers
input string            InpPresetScalpList           = "XAUUSD,US30,NAS100,GER40"; // ⚡ Scalp-optimised symbols
input string            InpPresetModerateList        = "EURUSD,GBPUSD,USDJPY,USDCHF"; // 🎯 Moderate symbols
input double            InpPresetScalpRiskMult       = 1.10;       // 💰 Scalp preset risk multiplier
input double            InpPresetModerateRiskMult    = 0.90;       // 💰 Moderate preset risk multiplier

//── GROUP: TELEGRAM ──────────────────────────────────────────────────
input group             "═══ 📡 TELEGRAM ENGINE ═══"
input bool              InpUseTelegram               = false;      // 📡 Master Telegram toggle
input string            InpTelegramToken             = "";         // 🔑 Bot API token from @BotFather
input string            InpTelegramChatID            = "";         // 💬 Target chat/channel ID
input bool              InpNotifyEntries             = true;       // 🟢 Alert on new trade entry
input bool              InpNotifyExits               = true;       // 🔴 Alert on trade exit
input bool              InpNotifySLHits              = true;       // 🛑 Alert on stop loss hit
input bool              InpNotifyTPHits              = true;       // 🎯 Alert on TP1/TP2/TP3 hit
input bool              InpNotifyDrawdown            = true;       // ⚠️ Alert on vault state change
input bool              InpNotifyHourlyPing          = false;      // ⏰ Hourly heartbeat ping
input bool              InpNotifyDailyReport         = true;       // 🌙 Daily P&L summary
input bool              InpNotifyWeeklyReport        = true;       // 📅 Weekly performance report
input bool              InpNotifyChartSnaps          = false;      // 📸 Attach chart screenshot PNG
input int               InpDailyReportHour           = 23;         // 🕓 Hour to fire daily/weekly reports
input bool              InpUseVerboseTGDiag          = false;      // 🔬 Verbose diagnostic Telegram messages
input bool              InpUseSafetyLockAlerts       = true;       // 🔒 Alert on every safety lock state

//── GROUP: GLASSMORPHISM UI ──────────────────────────────────────────
input group             "═══ 🎨 GLASSMORPHISM DASHBOARD ═══"
input bool              InpShowDashboard             = true;       // 🖥️ Enable dashboard overlay
input bool              InpUseGlassmorphUI           = true;       // 🎨 Enable full glassmorphism effects
input int               InpDashOpacity               = 220;        // 🔆 Dashboard opacity (0=transparent, 255=opaque)
input int               InpTimerSeconds              = 1;          // ⏱️ EventSetTimer interval (seconds)
input int               InpUIRefreshMs               = 500;        // 🔄 Dashboard refresh interval (ms)
input int               InpUIPanelX                  = 20;         // 📍 Panel X position (px from left)
input int               InpUIPanelY                  = 20;         // 📍 Panel Y position (px from top)
input int               InpUIPanelW                  = 320;        // 📐 Panel width (px)
//── Per-panel visibility controls (show/hide each section independently)
input bool              InpDashShowAccount           = true;       // 💰 Show Account panel
input bool              InpDashShowSafety            = true;       // 🔒 Show Safety Vault panel
input bool              InpDashShowTrades            = true;       // 📈 Show Active Trades panel
input bool              InpDashShowPerformance       = true;       // 📊 Show Performance Metrics panel
input bool              InpDashShowRegime            = true;       // 🌡️ Show Market Regime panel
input bool              InpDashShowScore             = true;       // ⚡ Show Signal Score panel
input bool              InpDashShowPortfolio         = true;       // 🌐 Show Portfolio Watchlist panel
input bool              InpDashShowFilters           = true;       // 🔍 Show Filters & Events panel
input bool              InpDashShowControls          = true;       // 🎮 Show Controls panel
//── Legacy color overrides (used by older display elements)
input color             InpUIColorBull               = clrLimeGreen;    // 🟢 Bull signal color
input color             InpUIColorBear               = clrTomato;       // 🔴 Bear signal color
input color             InpUIColorNeutral            = clrSilver;       // ⬜ Neutral state color
input color             InpUIColorAccent             = clrDeepSkyBlue;  // 🔵 Accent/info color

//── GROUP: TELEMETRY & JOURNAL ───────────────────────────────────────
input group             "═══ 📋 TELEMETRY & JOURNAL ═══"
input bool              InpUseExecTelemetry          = true;       // 📋 Enable execution telemetry ring buffer
input bool              InpUseRejectReasonDash       = true;       // ❌ Show last reject reason on dashboard
input int               InpTelemetryHistoryLimit     = 3;          // 📋 Last N telemetry rows on dashboard
input int               InpPendingPlanMaxAgeMin      = 60;         // ♻️ GC orphaned plans older than N min

//── GROUP: PIP SETTINGS ──────────────────────────────────────────────
input group             "═══ 📐 PIP CALIBRATION ═══"
input bool              InpPipAutoDetect             = true;       // 🔍 Auto-detect pip size from symbol digits (5/3-digit = 10x point)
input int               InpManualPipDigits           = 0;          // 🔧 Manual: 4=4-digit, 5=5-digit, 0=auto
input double            InpPipValueOverride          = 0.0;        // 💵 Override pip value in account currency (0=auto-calc)

//── GROUP: STALE DATA THRESHOLD ──────────────────────────────────────
input group             "═══ ⚠️ STALE DATA DETECTION ═══"
input int               InpStaleDataMaxSec           = 60;         // ⏱️ No-tick gap (sec) before STALE lock fires (0=disable)

//── GROUP: RISK PROFILES ──────────────────────────────────────────────
input group             "═══ 🎛️ RISK PROFILE PRESETS ═══"
// Profile applies a pre-calibrated parameter bundle on top of mode settings.
// AUTO_SWITCH analyses regime + consecutive losses and shifts profile dynamically.
// Use MANUAL to rely exclusively on the individual parameter values below.
input ENUM_RISK_PROFILE  InpRiskProfile               = RISK_PROFILE_MED_RISK; // 🎛️ Risk profile preset (named dropdown)

//── GROUP: WEBVIEW DASHBOARD ──────────────────────────────────────────
input group             "═══ 🌐 WEBVIEW LIVE DASHBOARD ═══"
input bool              InpWebViewDash               = true;       // 🌐 Write HTML+JSON live dashboard to MQL5\\Files folder
input int               InpWebViewRefreshMs          = 1000;       // 🔄 Dashboard JSON refresh interval (ms)

//── GROUP: HFT SCORING WEIGHTS ────────────────────────────────────────
// Weight multiplier per HFT signal component. 1.0=default. 0.0=disable. 2.0=double.
// Applied after internal cap; total raw score bounded to ±98.
input group             "═══ ⚡ HFT SCORING WEIGHTS ═══"
input double            InpHFTW_EMA     = 1.0;   // ⚡[0] M1 EMA9/34 + M15 alignment  (max ±18)
input double            InpHFTW_M5EMA   = 1.0;   // ⚡[1] M5 EMA9/34 alignment        (max ±10)
input double            InpHFTW_RSI     = 1.0;   // ⚡[2] M1 RSI momentum             (max ±12)
input double            InpHFTW_Pattern = 1.0;   // ⚡[3] M1 candle pattern            (max ±10)
input double            InpHFTW_BSP     = 1.0;   // ⚡[4] Buy/sell pressure rolling    (max ±20)
input double            InpHFTW_MACD    = 1.0;   // ⚡[5] M1 MACD micro-cross         (max  ±8)
input double            InpHFTW_Volume  = 1.0;   // ⚡[6] Volume momentum burst        (max  ±7)
input double            InpHFTW_ATR     = 1.0;   // ⚡[7] M1/M5 ATR sweet-spot        (max  ±5)
input double            InpHFTW_M3EMA   = 1.0;   // ⚡[8] M3 EMA bridge               (max  ±6)
input double            InpHFTW_M6RSI   = 1.0;   // ⚡[9] M6 RSI momentum             (max  ±6)
input double            InpHFTW_M10ATR  = 1.0;   // ⚡[10] M10 ATR bridge             (max  ±4)

//── GROUP: HFT EMA TOUCH ZONE ─────────────────────────────────────────
// Blocks entry when price approaches opposing EMA9/21/34 on M1/M3/M5.
// Rejection candle (pin bar or bounce) flips bias and allows counter-trade.
input group             "═══ 🔶 HFT EMA TOUCH ZONE ═══"
input bool              InpHFTBlockEMATouchOpposite  = true;   // 🔶 Block entry when approaching opposing EMA S/R zone
input bool              InpHFTAllowRejectionTrade    = true;   // 🔄 Allow counter-direction trade on rejection candle
input double            InpHFTEMATouchATR            = 0.30;   // 📏 Touch zone radius (X × M1 ATR; 0.30 = 30% of M1 ATR)
input double            InpHFTEMARejectionPips       = 3.0;    // 📐 Min bounce (broker points) from EMA to confirm rejection

//── GROUP: HFT PRESSURE GATE ──────────────────────────────────────────
// CPressureEngine tracks live tick direction; gate requires 60%+ directional.
input group             "═══ 🔵 HFT PRESSURE GATE ═══"
input bool              InpHFTPressureGate           = true;   // 🔵 Gate HFT entry on real-time tick pressure
input double            InpHFTPressureMin            = 0.60;   // 📊 Min directional ratio (0.60 = need 60%+ buy or sell ticks)

//── GROUP: BSP CANDLE-PRESSURE GATE (all modes, v6.5) ─────────────────
// Hard directional gate driven by the multi-TF candle-wise Buy/Sell Pressure
// engine (gBSP rolling composite — HFT:M1/M3/M5, SCALP:M5/M15/M1, MOD:H1/H4/M15).
// Blocks an entry when measured volume pressure is NET AGAINST the trade.
// Default 50.0 = "don't fight the tape" (only blocks when flow opposes); raise
// to 55–62 to demand positive confirmation. Velocity veto is optional.
input group             "═══ 📊 BSP CANDLE-PRESSURE GATE ═══"
input bool              InpBSPGateEnable             = true;   // 📊 Gate entry on multi-TF candle BSP (all modes)
input double            InpBSPGateMinPct             = 50.0;   // 📊 Min bias-side BSP % (50=block only opposing; 55-62=demand confirmation)
input bool              InpBSPGateVelocityVeto       = false;  // 📊 Also block when BSP velocity strongly opposes bias (HFT only)
input double            InpBSPGateVelVetoMin         = 8.0;    // 📊 Velocity opposing threshold (pts) for veto

//── GROUP: AI WIN-PROBABILITY MODEL (online learning, v6.5) ───────────
// Pure-MQL5 online logistic-regression scorer. Learns P(win) from realised
// trade outcomes (SGD, updated on every close) and augments the static score:
//   ADVISORY → logs P(win), never changes a decision (safe: learns only)
//   GATE     → blocks any entry with P(win) < InpAIGateMinProb
//   BLEND    → rescues near-miss scores the model likes AND vetoes
//              passing scores the model strongly dislikes (recommended)
// Set InpAIMode=0 to disable entirely (clean A/B baseline). Engine logic
// lives in SKP_P8_AI.mqh; these inputs sit here so the gate chain can read them.
input group             "═══ 🤖 AI WIN-PROBABILITY MODEL ═══"
input int               InpAIMode                    = 3;      // 🤖 0=OFF 1=ADVISORY 2=GATE 3=BLEND 4=AI-LED
input double            InpAIGateMinProb             = 0.50;   // 🤖 GATE: block entry if P(win) < this
input int               InpAIRescueMargin            = 8;      // 🤖 BLEND: rescue scores within N pts below min
input double            InpAIRescueProb              = 0.60;   // 🤖 BLEND: rescue only if P(win) ≥ this
input double            InpAIVetoProb                = 0.32;   // 🤖 BLEND: veto passing setup if P(win) < this
input double            InpAILearnRate               = 0.04;   // 🤖 SGD learning rate
input double            InpAIL2Reg                   = 0.0008; // 🤖 L2 weight regularisation
input bool              InpAIPersist                 = true;   // 🤖 Save/load weights across runs (common folder)
input string            InpAIWeightsFile             = "skp_ai_weights.csv"; // 🤖 Weights filename (FILE_COMMON)
// ── AI-LED (InpAIMode=4): the model REPLACES the score gate as the entry
//    decision-maker. Score engines still propose a DIRECTION, but entry is
//    decided by P(win) ≥ InpAIPrimaryProb — the score cliff is removed and the
//    score becomes just feature f[0]. Until the model has learned from
//    InpAIWarmupTrades closed trades, it falls back to the proven score gate so
//    it never trades on an untrained brain. This is the genuine "replace the score".
input double            InpAIPrimaryProb             = 0.55;   // 🤖 AI-LED: enter when P(win) ≥ this (score cliff removed)
input int               InpAIWarmupTrades            = 30;     // 🤖 AI-LED: use score gate until model has N closed-trade updates
// ── Size-from-edge: scale lot by the model's P(win) (the "size from edge" lever).
//    Default OFF so the baseline is unchanged; turn on to A/B Kelly-style sizing.
input bool              InpAISizeFromEdge            = false;  // 🤖 Scale lot by AI edge (P(win))
input double            InpAISizePivotProb           = 0.80;   // 🤖 P(win) that maps to 1.0× lot
input double            InpAISizeMinMult             = 0.50;   // 🤖 Lot multiplier floor (weak edge)
input double            InpAISizeMaxMult             = 1.60;   // 🤖 Lot multiplier ceiling (strong edge)

double           gLastAIProb        = 0.0;      // last computed P(win) (for dashboard/logs; set by P8 via gate)
bool             gAIReady           = false;    // AI engine initialised
int              gAIEntryScore      = 0;        // score carried from entry decision → AI_OnTradeOpen (ENTRY_IN)

//── GROUP: HFT SPREAD GATE (PURE MODE) ────────────────────────────────
// Fixed absolute spread cap — replaces ATR-ratio method which is too tight
// during low-volatility sessions (e.g. XAUUSD Asian session spread 39-47 pts).
input group             "═══ 📡 HFT PURE — SPREAD & VOLUME GATES ═══"
input double            InpHFTMaxSpreadPts            = 60.0;  // 📡 HFT Pure max spread (broker points; 60 = 0.60 XAUUSD)
input bool              InpHFTVolActivityGate         = true;  // 📊 Gate entry on volume activity ratio (quiet bar filter)
input double            InpHFTMinVolRatio             = 0.80;  // 📊 Min vol ratio vs 14-bar avg (0.80 = need ≥ 80% normal activity)

//════════════════════════════════════════════════════════════════════
//  🔢  PART 2 — ALL ENUMERATIONS
//════════════════════════════════════════════════════════════════════

// ENUM_BOT_MODE_ / ENUM_LOT_MODE_ defined in the shim at the top of the assembly
// (must appear before the first 'input' that uses them — see P1 shim block)

enum ENUM_BIAS
{
   BIAS_NONE =  0,   // ⬜ No Clear Bias
   BIAS_BULL =  1,   // 🟢 Confirmed Bullish
   BIAS_BEAR = -1    // 🔴 Confirmed Bearish
};

enum ENUM_RSI_CURVE
{
   RSICURVE_FLAT    = 0,   // ➡️ Flat / Insufficient slope
   RSICURVE_RISING  = 1,   // 📈 Rising slope (accelerating buying)
   RSICURVE_FALLING = -1   // 📉 Falling slope (accelerating selling)
};

enum ENUM_RSI_QUADRANT
{
   RSIQ_NEUTRAL          = 0,  // ⬜ Undefined / Transitioning
   RSIQ_STRONG_BULLISH   = 1,  // 🟢 RSI>50 + Rising  → VALIDATES LONGS
   RSIQ_WEAKENING_BULLISH= 2,  // 🟡 RSI>50 + Falling → BLOCKS LONGS
   RSIQ_STRONG_BEARISH   = 3,  // 🔴 RSI<50 + Falling → VALIDATES SHORTS
   RSIQ_WEAKENING_BEARISH= 4   // 🟠 RSI<50 + Rising  → BLOCKS SHORTS
};

enum ENUM_RSI_STATE
{
   RSI_STRONG_BULL = 0,
   RSI_WEAK_BULL   = 1,
   RSI_STRONG_BEAR = 2,
   RSI_WEAK_BEAR   = 3,
   RSI_NEUTRAL_S   = 4
};

enum ENUM_PATTERN_FLAG
{
   PATTERN_NONE        = 0,
   BULL_ENGULFING      = 1,   // 🟢 Bullish Engulfing
   BEAR_ENGULFING      = 2,   // 🔴 Bearish Engulfing
   BULL_PIN_BAR        = 3,   // 📌 Bullish Pin Bar (Hammer)
   BEAR_PIN_BAR        = 4,   // 📌 Bearish Pin Bar (Shooting Star)
   MORNING_STAR        = 5,   // 🌅 Morning Star (3-bar)
   EVENING_STAR        = 6,   // 🌇 Evening Star (3-bar)
   INSIDE_BREAK_BULL   = 7,   // 📦 Inside Bar Bull Breakout
   INSIDE_BREAK_BEAR   = 8,   // 📦 Inside Bar Bear Breakout
   BULL_FLAG           = 9,   // 🚩 Bull Flag
   BEAR_FLAG           = 10,  // 🚩 Bear Flag
   RISING_WEDGE        = 11,  // 📐 Rising Wedge (bearish)
   FALLING_WEDGE       = 12,  // 📐 Falling Wedge (bullish)
   DOUBLE_TOP          = 13,  // 🏔️ Double Top
   DOUBLE_BOTTOM       = 14   // 🏔️ Double Bottom
};

enum ENUM_CROSS
{
   CROSS_NONE = 0,   // ➡️ No cross
   CROSS_BULL = 1,   // 🟢 Bullish crossover
   CROSS_BEAR = -1   // 🔴 Bearish crossover
};

enum ENUM_QUEUE_MSG
{
   MSG_INFO     = 0,
   MSG_ENTRY    = 1,
   MSG_EXIT     = 2,
   MSG_TP1      = 3,
   MSG_TP2      = 4,
   MSG_TP3      = 5,
   MSG_SL       = 6,
   MSG_DRAWDOWN = 7,
   MSG_HOURLY   = 8,
   MSG_DAILY    = 9,
   MSG_WEEKLY   = 10,
   MSG_SPIKE    = 11,
   MSG_NEWS     = 12,
   MSG_LOCK     = 13,
   MSG_REJECT   = 14,
   MSG_PENDING  = 15
};

enum ENUM_SAFETY_LOCK
{
   LOCK_NONE             = 0,   // ✅ All clear
   LOCK_EQUITY_FLOOR     = 1,   // 🚨 Equity floor breached — HALT
   LOCK_DAILY_LOSS       = 2,   // 💤 Daily loss limit — Sleep Mode
   LOCK_GLOBAL_DD        = 3,   // 🛡️ Global DD — no new entries
   LOCK_SPREAD           = 4,   // 📡 Spread too wide
   LOCK_STALE_DATA       = 5,   // ⚠️ Stale indicator data
   LOCK_MACRO_DIVERGENCE = 6,   // ⛔ H1 vs SMA800 macro divergence
   LOCK_MANUAL_PAUSE     = 7,   // ⏸️ Manual pause via button
   LOCK_SPIKE            = 8,   // 🚨 Spike detected (v5.0)
   LOCK_NEWS             = 9    // 📰 News window active (v5.0)
};

enum ENUM_MARKET_REGIME
{
   REGIME_UNKNOWN   = 0,  // ❓ Not yet classified
   REGIME_QUIET     = 1,  // 💤 Low volatility
   REGIME_NORMAL    = 2,  // ✅ Standard conditions
   REGIME_EXPLOSIVE = 3,  // 💥 High volatility burst
   REGIME_HOSTILE   = 4   // ☠️ Hostile — max spread/velocity
};

enum ENUM_EXEC_RECOVERY
{
   RECOVERY_NONE            = 0,
   RECOVERY_REPRICE_PENDING = 1,
   RECOVERY_FALLBACK_MARKET = 2,
   RECOVERY_DROP_SIGNAL     = 3
};

//════════════════════════════════════════════════════════════════════
//  📦  PART 3 — ALL DATA STRUCTURES
//════════════════════════════════════════════════════════════════════

// ── TFState: Per-Timeframe Indicator Cache ───────────────────────
struct TFState
{
   ENUM_TIMEFRAMES  tf;
   string           tfName;
   bool             enabled;
   bool             ready;
   // EMA Handles
   int              hEMAFast;
   int              hEMASlow;
   int              hEMA50;
   int              hEMA100;
   int              hEMA200;
   // SMA Handles
   int              hSMA21;
   int              hSMA50;
   int              hSMA100;
   int              hSMA200;
   int              hSMA800;
   // Oscillator Handles
   int              hRSI;
   int              hADX;
   int              hATR;
   // Market Snapshot
   datetime         barTime;
   double           close0;
   double           high0;
   double           low0;
   double           bid;
   double           ask;
   double           spreadPoints;
   // EMA Values (current + prior for cross detection)
   double           emaFast0;
   double           emaFast1;
   double           emaSlow0;
   double           emaSlow1;
   double           ema50;
   double           ema100;
   double           ema200;
   // SMA Values
   double           sma21;
   double           sma50;
   double           sma100;
   double           sma200;
   double           sma800;
   // RSI (4 bars for slope)
   double           rsi0;
   double           rsi1;
   double           rsi2;
   double           rsi3;
   double           rsiSlope;
   ENUM_RSI_CURVE   rsiCurve;
   ENUM_RSI_QUADRANT rsiQuadrant;
   // ADX / ATR
   double           adx0;
   double           atr0;
   // ── P7-compatible extended handles ────────────────────────────
   int              hEMA9;        // EMA-9 handle  (= hEMAFast when InpEMAFast==9)
   int              hEMA34;       // EMA-34 handle (= hEMASlow when InpEMASlow==34)
   int              hEMA21;       // EMA-21 handle — second bias pair for HFT dual-EMA system
   int              hMACD;        // MACD 12/26/9 handle
   int              hBB;          // Bollinger Bands 20/2.0 handle
   int              hStoch;       // Stochastic 5/3/3 handle
   // ── Bar-change tracking ───────────────────────────────────────
   bool             newBar;       // true on the first tick of a new bar
   datetime         barTime0;     // current bar open time  (replaces barTime)
   datetime         barTime1;     // previous bar open time
   double           open0;        // current bar open price
   double           open1;        // previous bar open price
   double           high1;        // previous bar high price
   double           low1;         // previous bar low price
   double           close1;       // previous bar close price
};

// ── FibMap: Full Fibonacci Level Store ──────────────────────────
struct FibMap
{
   bool             valid;
   double           swingHigh;
   double           swingLow;
   datetime         highTime;
   datetime         lowTime;
   int              highBarIdx;
   int              lowBarIdx;
   // Retracements
   double           r236;
   double           r382;
   double           r500;
   double           r618;    // Golden Floor
   double           r786;    // Golden Ceiling
   // Extensions
   double           ext1000;
   double           ext1272; // TP Extension
   double           ext1618; // Golden Target
   ENUM_BIAS        swingBias;
};

// ── PivotState: Floor/Ceiling Levels ────────────────────────────
struct PivotState
{
   double   pivot;
   double   r1, r2, r3;
   double   s1, s2, s3;
   bool     ready;
};

// ── CandleProps: Normalized Bar for Pattern Engine ───────────────
struct CandleProps
{
   double   open;
   double   high;
   double   low;
   double   close;
   double   body;
   double   upperShadow;
   double   lowerShadow;
   double   range;
   bool     isBull;
   bool     isBear;
   bool     isDoji;
};

// ── PatternState: Active Pattern Result ─────────────────────────
struct PatternState
{
   ENUM_PATTERN_FLAG  pattern;
   string             name;
   bool               bullish;
   bool               bearish;
   double             confidence; // 0.0–1.0
};

// ── TieredTP: TP + TSL Config per Trade ─────────────────────────
struct TieredTP
{
   double   tp1;
   double   tp2;
   double   tp3;
   double   tp1VolPct;
   double   tp2VolPct;
   double   tp3VolPct;
   double   tslStep;
   bool     isScalpMode;
   bool     scalpOnTick;
   bool     softTP;
   double   softTPPrice;
};

// ── TradeRecord: Open Position Tracker ──────────────────────────
struct TradeRecord
{
   bool               active;
   ulong              ticket;
   string             symbol;
   ENUM_ORDER_TYPE    posType;
   double             initialVolume;
   double             entryPrice;
   double             stopLoss;
   double             initialSL;
   double             hardTP3;
   double             tp1Price;
   double             tp2Price;
   double             tp3Price;
   double             riskDistance;
   double             tslStep;
   // State Latches
   bool               tp1Hit;
   bool               tp2Hit;
   bool               breakEvenSet;
   bool               tslActive;
   bool               exhaustionHit;   // 🔒 ONE-TIME LATCH — prevents infinite loop
   int                exhaustionCount; // Counter: consecutive RSI counter-trend bars
   // Scalp-specific
   bool               isScalpMode;
   bool               scalpTSLOnTick;
   bool               softTPMode;
   double             softTPPrice;
   double             bestPrice;       // High watermark for TSL
   // Metadata
   datetime           createdAt;
   datetime           lastManageAt;
   double             spreadAtEntry;
   double             atrAtEntry;
   string             entryReason;
};

// ── PendingPlan: Pending Order Intent Binding ────────────────────
struct PendingPlan
{
   bool         active;
   ulong        orderTicket;
   string       symbol;
   ENUM_BIAS    bias;
   int          mode;
   double       lot;
   double       entry;
   double       sl;
   double       tp1;
   double       tp2;
   double       tp3;
   double       riskDistance;
   datetime     createdAt;
};

// ── SignalState: Current Bar Signal Output ───────────────────────
struct SignalState
{
   ENUM_BIAS    bias;
   int          bullScore;
   int          bearScore;
   string       blockReason;
   string       liveReason;
   bool         macroDivergent;
   bool         spreadBlocked;
   bool         adxBlocked;
   bool         staleBlocked;
   bool         sessionBlocked;
   bool         spikeBlocked;
   bool         newsBlocked;
   bool         fibAligned;
   bool         pivotAligned;
   bool         patternAligned;
   bool         triggerReady;
   double       entryPrice;
   double       stopLoss;
   double       tp1;
   double       tp2;
   double       tp3;
   double       riskDistance;
   double       confluencePrice;
};

// ── CascadeResult: MTF Weighted Scoring Output ──────────────────
struct CascadeResult
{
   ENUM_BIAS    bias;
   double       score;       // 0.0–1.0 normalized
   double       bullWeight;
   double       bearWeight;
   int          bullCount;
   int          bearCount;
   int          noneCount;
};

// ── ScoreSnapshot: Entry Scoring Debug State ─────────────────────
struct ScoreSnapshot
{
   int      bull;
   int      bear;
   int      minRequired;
   bool     burstOK;
   bool     spreadCompressed;
   bool     microPullbackOK;
   bool     freshBullCross;
   bool     freshBearCross;
   bool     dualLTFBull;
   bool     dualLTFBear;
   bool     scorePassBull;
   bool     scorePassBear;
   string   bullReason;
   string   bearReason;
   string   decision;
};

// ── BrokerSanityState: Hostile Market Conditions ─────────────────
struct BrokerSanityState
{
   bool     spreadShock;
   bool     tickVelocityShock;
   bool     gapShock;
   bool     stopLevelHostile;
   bool     freezeLevelHostile;
   bool     pendingDistanceBad;
   bool     blackoutActive;
   bool     hostileNow;
   bool     spikeDetected;   // v5.0
   bool     newsActive;      // v5.0
   double   spreadNow;
   double   spreadCap;
   double   lastGap;
   double   velocityPts;
   string   reason;
};

// ── SpikeState: v5.0 Spike Detection State ───────────────────────
struct SpikeState
{
   bool     spikeDetected;
   bool     spikeActive;       // alias: same as spikeDetected (P3/P4 compat)
   double   tickPriceBuf[64];
   datetime tickTimeBuf[64];
   int      tickBufIdx;
   int      tickBufCount;
   double   lastSpikeRange;
   double   spikeRange;        // alias: same as lastSpikeRange (P3/P4 compat)
   datetime spikeStartTime;
   datetime spikeClearTime;
   string   reason;
};

// ── NewsFilterState: v5.0 News Filter State ──────────────────────
struct NewsFilterState
{
   bool     active;
   bool     impliedBySpread;
   string   windowLabel;
   datetime windowEnd;
   int      parsedCount;
   int      weekday[10];
   int      startHour[10];
   int      startMin[10];
   int      durationMin[10];
};

// ── VolMomState: v5.0 Volume Momentum ───────────────────────────
struct VolMomState
{
   bool     bullConfirmed;
   bool     bearConfirmed;
   long     currentVol;
   double   avgVol;
   double   ratio;
   string   label;
};

// ── RegimeState: Market Regime Engine State ──────────────────────
struct RegimeState
{
   ENUM_MARKET_REGIME  regime;
   ENUM_MARKET_REGIME  current;     // alias for `regime` (P3/P6 compatibility)
   double              atrNow;
   double              atrAvg;
   double              atrRatio;
   double              spreadNow;
   double              spreadCap;
   double              velocityPts;
   string              label;
   bool                suppressScalp;
};

// ── RetryAction: Non-Blocking Retry Queue ───────────────────────
struct RetryAction
{
   bool     used;
   int      kind;          // 1=modify 2=close-partial 3=panic-close 4=delete-order
   ulong    ticket;
   double   price1;        // SL for modify / volume for partial close
   double   price2;        // TP for modify
   double   retryPrice;    // alias for price1 (P3 compatibility name)
   double   retryPrice2;   // alias for price2 (P3 compatibility name)
   double   volume;
   int      attempts;
   datetime nextTry;
   datetime createdAt;     // P3 uses createdAt for delay tracking
   string   note;
   bool     active;        // P3 uses active instead of used
};

// ── ModifyRecoveryTask: Queued Modify Retry ──────────────────────
struct ModifyRecoveryTask
{
   bool     active;
   ulong    ticket;
   double   sl;
   double   tp;
   int      tries;
   datetime nextTry;
   string   why;
};

// ── PerfStats: Session Performance Accumulator ───────────────────
struct PerfStats
{
   int      totalTrades;
   int      winTrades;
   int      lossTrades;
   int      tp1Hits;
   int      tp2Hits;
   int      tp3Hits;
   int      slHits;
   double   grossProfit;
   double   grossLoss;
   double   netProfit;
   double   avgWin;
   double   avgLoss;
   double   rrSum;
   int      rrCount;
   int      safetyEvents;
   int      blockedMacro;
   int      blockedSpread;
   int      blockedADX;
   int      blockedSession;
   // Mode-split
   int      modeTrades[2];
   int      modeWins[2];
   int      modeLosses[2];
   double   modeNet[2];
   // Extended performance fields (P7 section 7.6 compatibility)
   double   totalProfit;   // sum of all winning trade profits
   double   totalLoss;     // sum of all losing trade losses (negative)
   double   bestTrade;     // single best trade PnL
   double   worstTrade;    // single worst trade PnL (most negative)
};

// ── PortfolioCandidate: Portfolio Scan Result ────────────────────
struct PortfolioCandidate
{
   bool     valid;
   string   symbol;
   ENUM_BIAS bias;
   int      bullScore;
   int      bearScore;
   int      finalScore;
   int      rank;
   bool     tradable;
   bool     spreadOK;
   bool     burstOK;
   bool     macroOK;
   bool     triggerOK;
   bool     rsiOK;
   bool     sessionOK;
   bool     hasExposure;
   string   reason;
};

// ── SafetyEventRow: Safety Log Entry ────────────────────────────
struct SafetyEventRow
{
   bool     used;
   datetime ts;
   string   code;
   string   detail;
};

// ── ExecTelemetryRow: Execution Action Log ───────────────────────
struct ExecTelemetryRow
{
   datetime ts;
   string   symbol;
   string   stage;
   string   side;
   bool     success;
   int      retcode;
   string   retlabel;
   string   detail;
};

// ── QueueMessage: Telegram Async Queue Item ──────────────────────
struct QueueMessage
{
   bool           used;           // P1 name
   bool           active;         // P6 alias for 'used'
   ENUM_QUEUE_MSG type;
   string         text;           // P1 name
   string         message;        // P6 alias for 'text'
   string         chatId;         // P6 target chat (absent in P1 single-chat model)
   int            retry;          // P1 name
   int            retryCount;     // P6 alias for 'retry'
   datetime       createdAt;      // P1 name
   datetime       timestamp;      // P6 alias for 'createdAt'
   bool           isPriority;
};

// ── SymbolProfileRuntime: Asset Class Profile ────────────────────
struct SymbolProfileRuntime
{
   string   assetClass;
   double   spreadFactor;
   double   pendingOffsetPoints;
   double   maxSlippage;
   double   scalpATRMin;
   double   scalpATRMax;
   double   moderateSLATR;
   int      sessionStartHour;
   int      sessionEndHour;
   double   slDistMultiplier;  // SL distance scale factor (default 1.0, preset-adjusted)
};

//════════════════════════════════════════════════════════════════════
//  🌐  PART 4 — GLOBAL STATE VARIABLES
//════════════════════════════════════════════════════════════════════

// ── Timeframe Index Map  (9-TF system: M1 M5 M15 H1 H4 D1 + M3 M6 M10) ─
// TF_COUNT defined in P1B_COMPAT as 9.  Indices 0-5 = standard system used
// by all modes; indices 6-8 = HFT extended TFs (M3/M6/M10) — used only
// by ComputeHFTEntrySignal.  Zero weight in trend matrix (P2 TF_WEIGHT).
const ENUM_TIMEFRAMES TFList[9] = {PERIOD_M1, PERIOD_M5,  PERIOD_M15,
                                    PERIOD_H1,  PERIOD_H4,  PERIOD_D1,
                                    PERIOD_M3,  PERIOD_M6,  PERIOD_M10};
const string          TFNames[9]= {"M1","M5","M15","H1","H4","D1","M3","M6","M10"};
const double          TFWeights[9]={4.0,10.0,14.0,28.0,26.0,18.0,0.0,0.0,0.0};
#define IDX_M1   0
#define IDX_M5   1
#define IDX_M15  2
#define IDX_H1   3
#define IDX_H4   4
#define IDX_D1   5
#define IDX_M3   6   // HFT extended
#define IDX_M6   7   // HFT extended
#define IDX_M10  8   // HFT extended

// ── Core State Arrays ────────────────────────────────────────────
TFState          gTF[9];   // [9] = TF_COUNT: slots 0-5 standard, 6-8 HFT extended
TradeRecord      gRec[100];
PendingPlan      gPlan[20];
RetryAction      gRetry[64];
ModifyRecoveryTask gModRecover[32];
QueueMessage     gTGQueue[128];
SafetyEventRow   gSafetyLog[64];
ExecTelemetryRow gExecTelemetry[64];
PortfolioCandidate gPortCand[32];

// ── Live Signal & Pattern ────────────────────────────────────────
SignalState      gSignal;
PatternState     gPattern;
FibMap           gFibMap;
PivotState       gPivotD;      // Daily pivot
PivotState       gPivotW;      // Weekly pivot
PivotState       gPivotMN;     // Monthly pivot
ScoreSnapshot    gScoreSnap;
CascadeResult    gCascadeRes;
RegimeState      gRegime;
BrokerSanityState gBroker;
SpikeState       gSpike;
NewsFilterState  gNews;
VolMomState      gVolMom;
SymbolProfileRuntime gProfile;
PerfStats        gPerf;

// ── MTF Cascade State ────────────────────────────────────────────
ENUM_BIAS        gTFAlignState[7];
ENUM_RSI_STATE   gRSIState[7];
double           gCascadeScore       = 0.0;
ENUM_BIAS        gCascadeLockedBias  = BIAS_NONE;
int              gCascadeHoldCounter = 0;
double           gMaxCascadeWeight   = 0.0;

// ── Safety & Vault ───────────────────────────────────────────────
ENUM_SAFETY_LOCK gSafetyLock        = LOCK_NONE;
bool             gBotPaused         = false;
bool             gEmergencyHalt     = false;
double           gStartEquity       = 0.0;
double           gDayStartEquity    = 0.0;
double           gPeakEquity        = 0.0;
double           gDailyClosedPnL    = 0.0;
int              gConsecLosses      = 0;
int              gConsecWins        = 0;
int              gHighSpreadCount   = 0;
bool             gSpreadPaused      = false;
datetime         gLastDailyReset    = 0;
datetime         gLastWeeklyReset   = 0;
datetime         gLastCooldownStart = 0;

// ── Bot runtime state ────────────────────────────────────────────
ENUM_BOT_MODE    gBotMode           = BOT_MODE_MODERATE; // runtime mode (updated from InpMode in OnInit)
datetime         gInitTime          = 0;   // EA start timestamp (set in OnInit)
bool             gImpliedNewsActive = false; // set by CheckImpliedNewsFilter() each tick

// ── Runtime direction toggles (dashboard-interactive shadows of InpAllowBuy/Sell) ─
// v6.3d: Separate runtime globals allow dashboard BUY/SELL buttons to actually work.
// InpAllow* are compile-time inputs (read-only); gRt* can be flipped at runtime.
// Initialized from InpAllow* in OnInit → P1B_COMPAT bootstrap section.
bool             gRtAllowBuy        = true;  // mirrors InpAllowBuy; toggled by dashboard
bool             gRtAllowSell       = true;  // mirrors InpAllowSell; toggled by dashboard

// ── HFT Mode globals ─────────────────────────────────────────────
int              gHFTTradesThisHour = 0;   // HFT rate limiter: entries in current clock-hour
datetime         gHFTHourBucket     = 0;   // the clock-hour of gHFTTradesThisHour
double           gHFTTickRate       = 0.0; // rolling ticks/sec (updated every tick in P7)
int              gHFTTickBuf[32];          // ring-buffer of per-second tick counts (32s window)
int              gHFTTickBufIdx     = 0;   // next write slot in ring buffer
datetime         gHFTTickBufSec     = 0;   // current second being tallied
int              gHFTTickThisSec    = 0;   // ticks accumulated in current second
datetime         gHFTLastExitTime   = 0;   // last HFT exit timestamp (for cooldown)
double           gHFTOrderFlowBull  = 0.0; // rolling buy-tick fraction [0..1]
int              gHFTFlowBuf[64];          // 0=sell-tick, 1=buy-tick ring buffer
int              gHFTFlowIdx        = 0;   // next write slot in order flow buffer

// ── Pressure Engine (SKP_PressureEngine.mqh) ─────────────────────
// gPressEng tracks tick-by-tick buy/sell balance for the current M1 bar.
// Included before P1_Globals in SK_TRADE_PREMIUM_BOT.mq5 so class is defined here.
CPressureEngine  gPressEng;               // real-time tick pressure engine
bool             gHFTIsRejectionTrade = false; // true when EMA-zone flip fired on current signal

// ── Entry & Signal Timing ────────────────────────────────────────
datetime         gLastSignalTime    = 0;
datetime         gLastEntryTime     = 0;
datetime         gLastScalpExitTime = 0;
datetime         gLastFibBarTime    = 0;
datetime         gLastPivotBarTime  = 0;
bool             gNewM5Bar          = false;
bool             gNewH1Bar          = false;

// ── Telegram ─────────────────────────────────────────────────────
int              gTGQueueHead       = 0;
int              gTGQueueTail       = 0;
datetime         gTGLastSendTime    = 0;
int              gTGSendCount       = 0;
int              gTGFailCount       = 0;
datetime         gLastHourlyReport  = 0;
datetime         gLastDailyReport   = 0;
datetime         gLastWeeklyReport  = 0;

// ── Portfolio ────────────────────────────────────────────────────
int              gPortTopRank       = 0;
ENUM_BIAS        gPortTopBias       = BIAS_NONE;
datetime         gLastPortScan      = 0;

// ── Dashboard ────────────────────────────────────────────────────
CCanvas          gCanvas;
bool             gCanvasReady       = false;
int              gPanelX            = 20;
int              gPanelY            = 20;
datetime         gLastUIRender      = 0;
bool             gMouseDragging     = false;
int              gDragOffX          = 0;
int              gDragOffY          = 0;
string           gLastRejectLabel   = "";
string           gDiagFeed[8];
int              gDiagFeedIdx       = 0;

// ── Safety & Telemetry Log ────────────────────────────────────────
int              gSafetyLogIdx      = 0;
int              gExecTelemIdx      = 0;

// ── Performance mode tracking ────────────────────────────────────
double           gModerateNetPL     = 0.0;
double           gScalpNetPL        = 0.0;

// ── Telegram TG Trade Stats ──────────────────────────────────────
int              gTGTotalTrades     = 0;
int              gTGWinTrades       = 0;
int              gTGLossTrades      = 0;
double           gTGGrossPnL        = 0.0;
double           gTGWeeklyPnL       = 0.0;
double           gTGMaxWin          = 0.0;
double           gTGMaxLoss         = 0.0;

// ── Broker object & symbol info ──────────────────────────────────
CTrade           gTrade;
CSymbolInfo      gSymInfo;
string           gSymbol;
double           gPoint;
int              gDigits;
double           gTickSize;
double           gTickValue;
double           gLotStep;
double           gMinLot;
double           gMaxLot;
double           gMinStopLevel;
int              gJournalHandle     = INVALID_HANDLE;
string           gJournalFile       = "";

// ── Pip calibration (auto-detected in OnInit) ────────────────────
double           gPipSize           = 0.0001; // 1 pip in price units (auto-set)
double           gPipValue          = 1.0;    // value of 1 pip in account currency
double           gPipsPerPoint      = 1.0;    // multiplier: 10 for 5-digit, 1 for 4-digit
string           gPipDigitLabel     = "AUTO"; // "4-DIGIT" / "5-DIGIT" / "OVERRIDE"

// ── Buy/Sell Pressure State (Engine v5.1 — HFT Extended) ────────
struct BuySellPressure
{
   // ── Composite (multi-TF weighted) ───────────────────────────────────
   double   buyPct;           // Composite buy  pressure 0.0–100.0
   double   sellPct;          // Composite sell pressure 0.0–100.0
   double   hftBuyPct;        // HFT composite (M1/M3/M5/M6 + tick flow)
   double   hftSellPct;       // HFT composite sell
   // ── Per-timeframe session pressures ─────────────────────────────────
   double   buyPctM1;         // M1  session buy %
   double   sellPctM1;        // M1  session sell %
   double   buyPctM3;         // M3  session buy % (HFT extended — v6.3b)
   double   sellPctM3;        // M3  session sell %
   double   buyPctM5;         // M5  session buy %
   double   sellPctM5;        // M5  session sell %
   double   buyPctM6;         // M6  session buy % (HFT extended — v6.3b)
   double   sellPctM6;        // M6  session sell %
   double   buyPctM10;        // M10 session buy % (HFT extended — v6.3f)
   double   sellPctM10;       // M10 session sell %
   double   buyPctM15;        // M15 session buy %
   double   sellPctM15;       // M15 session sell %
   double   buyPctH1;         // H1  session buy %
   double   sellPctH1;        // H1  session sell %
   double   buyPctH4;         // H4  session buy %
   double   sellPctH4;        // H4  session sell %
   // ── Tick-level order flow (HFT precision, from 64-tick rolling buf) ─
   double   tickFlowBull;     // 0.0–1.0: fraction of last 64 ticks that were buy
   double   tickFlowBear;     // = 1.0 - tickFlowBull
   // ── Current partial bar ─────────────────────────────────────────────
   double   curBarBuyPct;     // current open bar buy  % (real-time)
   double   curBarSellPct;    // current open bar sell % (real-time)
   // ── Session bar counts per TF ────────────────────────────────────────
   int      sessionBarsM5;    // M5  bars counted since session open
   int      sessionBarsH1;    // H1  bars counted since session open
   int      sessionBarsH4;    // H4  bars counted since session open
   // ── Raw forces (diagnostic) ─────────────────────────────────────────
   double   totalBuyForce;    // composite raw buy force sum
   double   totalSellForce;   // composite raw sell force sum
   // ── Mode-specific rolling-window BSP (v6.3g — candle-wise, exp-decay) ─
   // HFT: M1[20 bars, w=0.88] × 40% + M3[15 bars, w=0.90] × 25% + M5[12 bars, w=0.92] × 20% + tick × 15%
   double   hftRollingBuyPct;   // HFT rolling composite buy  % (0–100)
   double   hftRollingSellPct;  // HFT rolling composite sell % (0–100)
   double   hftVelocity;        // HFT pressure momentum: positive = accelerating bullish
   // Per-TF rolling buy % (stored so dashboard & logs can show divergence from session BSP)
   double   hftRollingM1BuyPct;  // M1 rolling 20-bar buy% (decay=0.88)
   double   hftRollingM3BuyPct;  // M3 rolling 15-bar buy% (decay=0.90)
   double   hftRollingM5BuyPct;  // M5 rolling 12-bar buy% (decay=0.92)
   // SCALP: M5[30 bars, w=0.90] × 45% + M15[20 bars, w=0.92] × 35% + M1[15 bars, w=0.85] × 20%
   double   scalpRollingBuyPct;
   double   scalpRollingSellPct;
   // MODERATE: H1[20 bars, w=0.92] × 45% + H4[10 bars, w=0.95] × 35% + M15[20 bars, w=0.90] × 20%
   double   modRollingBuyPct;
   double   modRollingSellPct;
   // ── Labels & flags ──────────────────────────────────────────────────
   string   label;            // "BUY DOMINANT" / "SELL DOMINANT" / "NEUTRAL"
   bool     bullDominant;     // buyPct >= 60
   bool     bearDominant;     // sellPct >= 60
};
BuySellPressure  gBSP;           // global buy/sell pressure state

// ── Entry block reason tracking (for dashboard events bar) ───────
string           gLastBlockReason   = "";     // most recent gate block reason
string           gLastBlockGate     = "";     // gate name (e.g. "Gate4-Score")
datetime         gLastBlockTime     = 0;      // when block was set
int              gBlockedTickCount  = 0;      // consecutive ticks blocked
string           gEAEventLog[16];             // rolling event log (newest at [0])
int              gEAEventLogIdx     = 0;      // next write position

//════════════════════════════════════════════════════════════════════
//  🔧  PART 4b — HELPER MATH / SAFE DIVISION
//════════════════════════════════════════════════════════════════════

//--- Zero-divide safe division: returns 0.0 if denominator == 0
double SafeDiv(double a, double b)
{
   if(b == 0.0) return 0.0;
   return a / b;
}

//--- Normalize price to symbol digits
double NormalizePrice(double price)
{
   return NormalizeDouble(price, gDigits);
}

//--- Normalize lot: zero-divide safe, step-aligned, clamped
double NormalizeLotSafeEx(double rawLot, double minL, double maxL, double step)
{
   if(step <= 0.0 || minL <= 0.0) return 0.0;
   double lot = MathFloor(rawLot / step) * step;
   lot = MathMax(minL, MathMin(maxL, lot));
   return NormalizeDouble(lot, 2);
}

//--- Quick lot normalize using symbol info
double NormalizeLotSafe(double rawLot)
{
   return NormalizeLotSafeEx(rawLot, gMinLot, gMaxLot, gLotStep);
}

//--- Get current spread in points
double GetSpreadPoints()
{
   return (SymbolInfoDouble(gSymbol, SYMBOL_ASK) - SymbolInfoDouble(gSymbol, SYMBOL_BID)) / gPoint;
}

//--- Clamp value between min and max
double Clamp(double v, double lo, double hi)
{
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
}

//--- Check if current time is in a trading session
bool IsInSession(int startHour, int endHour)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return (now.hour >= startHour && now.hour < endHour);
}

//--- Retcode to human-readable string
string RetcodeStr(int code)
{
   switch(code)
   {
      case TRADE_RETCODE_DONE:          return "DONE";
      case TRADE_RETCODE_PLACED:        return "PLACED";
      case TRADE_RETCODE_REQUOTE:       return "REQUOTE";
      case TRADE_RETCODE_REJECT:        return "REJECT";
      case TRADE_RETCODE_TIMEOUT:       return "TIMEOUT";
      case TRADE_RETCODE_NO_MONEY:      return "NOMONEY";
      case TRADE_RETCODE_PRICE_CHANGED: return "PRICECHANGED";
      case TRADE_RETCODE_INVALID_STOPS: return "INVALIDSTOPS";
      case TRADE_RETCODE_FROZEN:        return "FROZEN";
      case TRADE_RETCODE_CONNECTION:    return "CONNECTION";
      default:                          return "ERR_"+IntegerToString(code);
   }
}

//--- Push diagnostic feed message (rotating 8-slot ring)
void PushDiag(string msg)
{
   gDiagFeed[gDiagFeedIdx % 8] = TimeToString(TimeCurrent(), TIME_SECONDS) + " " + msg;
   gDiagFeedIdx++;
}

//════════════════════════════════════════════════════════════════════
//  📋  PART 4c — JOURNAL ENGINE
//════════════════════════════════════════════════════════════════════

void JournalInit()
{
   long loginID = AccountInfoInteger(ACCOUNT_LOGIN);
   gJournalFile = "SKPJournal_" + IntegerToString(loginID) + "_" + gSymbol + ".csv";
   gJournalHandle = FileOpen(gJournalFile, FILE_WRITE|FILE_READ|FILE_CSV|FILE_SHARE_READ|FILE_COMMON, ',');
   if(gJournalHandle == INVALID_HANDLE)
   {
      Print("⚠️ Journal: Failed to open ", gJournalFile);
      return;
   }
   // Write header if file is new (size == 0)
   ulong sz = FileSize(gJournalHandle);
   if(sz == 0)
   {
      FileWrite(gJournalHandle, "Timestamp","Symbol","Event","FieldA","FieldB","FieldC","FieldD","FieldE");
   }
   FileSeek(gJournalHandle, 0, SEEK_END);
}

void JournalWrite(string evt, string a="", string b="", string c="", string d="", string e="")
{
   if(gJournalHandle == INVALID_HANDLE) return;
   FileWrite(gJournalHandle, TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             gSymbol, evt, a, b, c, d, e);
   FileFlush(gJournalHandle);
}

void JournalClose()
{
   if(gJournalHandle != INVALID_HANDLE)
   {
      FileClose(gJournalHandle);
      gJournalHandle = INVALID_HANDLE;
   }
}

//--- Safety Event Log
void RegisterSafetyEvent(string code, string detail)
{
   int idx = gSafetyLogIdx % 64;
   gSafetyLog[idx].used   = true;
   gSafetyLog[idx].ts     = TimeCurrent();
   gSafetyLog[idx].code   = code;
   gSafetyLog[idx].detail = detail;
   gSafetyLogIdx++;
   gPerf.safetyEvents++;
   JournalWrite("SAFETY", code, detail);
   PushDiag("🔒 SAFETY: " + code + " — " + detail);
}

//--- Build safety digest string (for Telegram reports)
string BuildSafetyDigest(int maxRows = 5)
{
   string out = "";
   int total = MathMin(gSafetyLogIdx, 64);
   int start = MathMax(0, total - maxRows);
   for(int i = start; i < total; i++)
   {
      int idx = i % 64;
      if(!gSafetyLog[idx].used) continue;
      out += TimeToString(gSafetyLog[idx].ts, TIME_SECONDS)
           + " " + gSafetyLog[idx].code
           + " " + gSafetyLog[idx].detail + "\n";
   }
   return out;
}

//--- Execution Telemetry push
void PushExecTelemetry(string stage, string side, bool success, int retcode, string detail)
{
   if(!InpUseExecTelemetry) return;
   int idx = gExecTelemIdx % 64;
   gExecTelemetry[idx].ts       = TimeCurrent();
   gExecTelemetry[idx].symbol   = gSymbol;
   gExecTelemetry[idx].stage    = stage;
   gExecTelemetry[idx].side     = side;
   gExecTelemetry[idx].success  = success;
   gExecTelemetry[idx].retcode  = retcode;
   gExecTelemetry[idx].retlabel = RetcodeStr(retcode);
   gExecTelemetry[idx].detail   = detail;
   gExecTelemIdx++;
   if(!success) gLastRejectLabel = stage + ":" + RetcodeStr(retcode);
}

//--- Build last N telemetry rows for dashboard
string BuildLastExecTelemetry()
{
   string out = "";
   int lim = MathMin(InpTelemetryHistoryLimit, MathMin(gExecTelemIdx, 64));
   for(int i = 0; i < lim; i++)
   {
      int idx = (gExecTelemIdx - 1 - i + 64) % 64;
      string sym = (gExecTelemetry[idx].success) ? "✅" : "❌";
      out += sym + " " + gExecTelemetry[idx].stage
           + " " + gExecTelemetry[idx].side
           + " " + gExecTelemetry[idx].retlabel + "\n";
   }
   return out;
}


#endif // SKP_P1_GLOBALS_MQH
