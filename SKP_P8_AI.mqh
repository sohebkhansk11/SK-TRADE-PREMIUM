//+------------------------------------------------------------------+
//|  SKP_P8_AI.mqh  —  Online-Learning Win-Probability Model (v6.5)   |
//|                                                                  |
//|  Pure-MQL5 logistic-regression scorer. NO Python, NO DLL.        |
//|                                                                  |
//|  WHY: the static additive score is a hard cliff — a setup at     |
//|  score 67 is rejected while 68 trades, even when realised        |
//|  outcomes say the 67 was the better trade. This model learns     |
//|  P(win) directly from closed-trade results (stochastic gradient  |
//|  descent, updated on every close) and either rescues good        |
//|  near-miss setups or vetoes bad passing ones (see InpAIMode).    |
//|                                                                  |
//|  This module is included LAST so it can use the indicator        |
//|  getters (GetRSI/GetEMA/GetATR, P7) and gBSP (P5). Its inputs    |
//|  and gLastAIProb live in P1_Globals (declared before the gate    |
//|  chain that reads them). P7/P4 call the AI_* functions below;    |
//|  MQL5 resolves global functions across the whole program, so     |
//|  call-before-definition across includes is fine.                 |
//+------------------------------------------------------------------+
#ifndef SKP_P8_AI_MQH
#define SKP_P8_AI_MQH

#define AI_NFEAT    10     // number of features (weights = AI_NFEAT + 1 intercept)
#define AI_PENDING  64     // open-trade feature store size

//── Model state ──────────────────────────────────────────────────────
double gAIw[AI_NFEAT + 1];   // weights[0..N-1] + intercept at [AI_NFEAT]
int    gAITrainCount = 0;    // number of SGD updates applied

//── Per-open-trade feature snapshot (label resolved at close) ─────────
struct AIPend
{
   bool   used;
   ulong  ticket;
   double f[AI_NFEAT];
   double cumProfit;         // sum of all realised deal P&L for this position
};
AIPend gAIPend[AI_PENDING];

//── Small math helpers ───────────────────────────────────────────────
double AI_Clamp(double v, double lo, double hi)
{
   return (v < lo) ? lo : ((v > hi) ? hi : v);
}

double AI_Sigmoid(double z)
{
   if(z >  30.0) return 1.0;
   if(z < -30.0) return 0.0;
   return 1.0 / (1.0 + MathExp(-z));
}

//── Seed weights (informative priors) ────────────────────────────────
// The base strategy already wins ~90%, so the intercept is set high
// (sigmoid(1.5)=0.82). Favourable features push P(win) up toward 0.9+,
// hostile features pull it down. Online learning refines all of these.
void AI_SeedWeights()
{
   gAIw[0]  = 0.80;   // score strength
   gAIw[1]  = 0.90;   // multi-TF BSP directional edge
   gAIw[2]  = 0.35;   // BSP velocity in trade direction
   gAIw[3]  = 0.55;   // tick-flow in trade direction
   gAIw[4]  = 0.30;   // M5 RSI momentum in direction
   gAIw[5]  = 0.40;   // M5 EMA9/34 alignment in direction
   gAIw[6]  = 0.25;   // H1 RSI context in direction
   gAIw[7]  = 0.60;   // recent loss-streak regime (feature is negative when losing)
   gAIw[8]  = 0.30;   // spread cost (feature high = cheap spread)
   gAIw[9]  = 0.20;   // session (London/NY vs off-hours)
   gAIw[AI_NFEAT] = 1.50;  // intercept ≈ base win rate
}

//── Feature builder — DIRECTION-NORMALISED ───────────────────────────
// Every feature is expressed "in favour of the trade direction" so a
// single weight set generalises across longs and shorts.
void AI_BuildFeatures(ENUM_BIAS bias, int score, double &f[])
{
   if(ArraySize(f) < AI_NFEAT) ArrayResize(f, AI_NFEAT);

   double dir     = (bias == BIAS_BULL) ? 1.0 : -1.0;
   double biasPct = (bias == BIAS_BULL) ? gBSP.buyPct : gBSP.sellPct;

   double rsiM5 = GetRSI (IDX_M5, 1);
   double rsiH1 = GetRSI (IDX_H1, 1);
   double atrM5 = GetATR (IDX_M5, 1);
   double emaF  = GetEMA9 (IDX_M5, 1);
   double emaS  = GetEMA34(IDX_M5, 1);

   double atrPts    = (gPoint > 0.0) ? (atrM5 / gPoint) : 1.0;
   double spreadPts = (double)SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   double sess = (tm.hour >= 7 && tm.hour < 21) ? 0.5 : -0.5;  // active-session proxy

   f[0] = AI_Clamp((score - 60.0) / 30.0,                 -1.5, 1.5);
   f[1] = AI_Clamp((biasPct - 50.0) / 25.0,               -2.0, 2.0);
   f[2] = AI_Clamp(dir * gBSP.hftVelocity / 25.0,         -2.0, 2.0);
   f[3] = AI_Clamp(dir * (gBSP.tickFlowBull - 0.5) * 4.0, -2.0, 2.0);
   f[4] = AI_Clamp(dir * (rsiM5 - 50.0) / 25.0,           -2.0, 2.0);
   f[5] = (atrM5 > 0.0) ? AI_Clamp(dir * (emaF - emaS) / atrM5, -2.0, 2.0) : 0.0;
   f[6] = AI_Clamp(dir * (rsiH1 - 50.0) / 25.0,           -2.0, 2.0);
   f[7] = AI_Clamp(-(double)gConsecLosses / 3.0,          -2.0, 0.5);
   f[8] = AI_Clamp(1.0 - spreadPts / MathMax(0.10 * atrPts, 1.0), -2.0, 1.0);
   f[9] = sess;
}

//── Forward inference ────────────────────────────────────────────────
double AI_RawPredict(const double &f[])
{
   double z = gAIw[AI_NFEAT];               // intercept
   for(int i = 0; i < AI_NFEAT; i++) z += gAIw[i] * f[i];
   return AI_Sigmoid(z);
}

double AI_PredictWinProb(ENUM_BIAS bias, int score)
{
   double f[];
   AI_BuildFeatures(bias, score, f);
   double p = AI_RawPredict(f);
   gLastAIProb = p;                          // expose for dashboard / logs
   return p;
}

//── Size-from-edge — lot multiplier from the latest P(win) ───────────
// Reads gLastAIProb (refreshed by the Gate-15 evaluation that runs in the
// same tick immediately before the entry's lot is sized). Maps probability
// to a bounded multiplier around InpAISizePivotProb (where mult = 1.0):
//   above pivot → scale up toward InpAISizeMaxMult (stronger edge, bigger size)
//   below pivot → scale down toward InpAISizeMinMult (weaker edge, smaller size)
// Returns 1.0 (no change) when disabled or the model is off/not ready.
double AI_EdgeLotMult()
{
   if(!InpAISizeFromEdge || !gAIReady || InpAIMode == 0) return 1.0;

   double p     = gLastAIProb;
   double pivot = InpAISizePivotProb;
   double m;

   if(p >= pivot)
   {
      double span = MathMax(0.97 - pivot, 0.01);
      m = 1.0 + (p - pivot) / span * (InpAISizeMaxMult - 1.0);
   }
   else
   {
      double lo   = InpAIVetoProb;                 // floor of the usable range
      double span = MathMax(pivot - lo, 0.01);
      m = InpAISizeMinMult + (p - lo) / span * (1.0 - InpAISizeMinMult);
   }
   return AI_Clamp(m, InpAISizeMinMult, InpAISizeMaxMult);
}

//── SGD update (single sample, logistic loss) ────────────────────────
void AI_TrainStep(const double &f[], double label)
{
   double p   = AI_RawPredict(f);
   double err = label - p;                   // gradient of logistic loss
   double lr  = InpAILearnRate;

   for(int i = 0; i < AI_NFEAT; i++)
   {
      gAIw[i] += lr * (err * f[i] - InpAIL2Reg * gAIw[i]);
      gAIw[i]  = AI_Clamp(gAIw[i], -6.0, 6.0);
   }
   gAIw[AI_NFEAT] += lr * err;               // intercept — no regularisation
   gAIw[AI_NFEAT]  = AI_Clamp(gAIw[AI_NFEAT], -6.0, 6.0);
   gAITrainCount++;
}

//── Persistence (live only — skipped in tester for clean backtests) ──
void AI_Save()
{
   if(!InpAIPersist) return;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;

   int h = FileOpen(InpAIWeightsFile, FILE_WRITE | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) return;
   FileWrite(h, "SKP_AI_V1", gAITrainCount,
             gAIw[0], gAIw[1], gAIw[2], gAIw[3], gAIw[4], gAIw[5],
             gAIw[6], gAIw[7], gAIw[8], gAIw[9], gAIw[10]);
   FileClose(h);
}

bool AI_Load()
{
   if(!InpAIPersist) return false;
   if(!FileIsExist(InpAIWeightsFile, FILE_COMMON)) return false;

   int h = FileOpen(InpAIWeightsFile, FILE_READ | FILE_CSV | FILE_COMMON | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) return false;

   string tag = FileReadString(h);
   if(tag != "SKP_AI_V1") { FileClose(h); return false; }
   gAITrainCount = (int)StringToInteger(FileReadString(h));
   for(int i = 0; i <= AI_NFEAT; i++)
   {
      if(FileIsEnding(h)) break;
      gAIw[i] = StringToDouble(FileReadString(h));
   }
   FileClose(h);
   return true;
}

//── Lifecycle ────────────────────────────────────────────────────────
void AI_Init()
{
   AI_SeedWeights();
   for(int i = 0; i < AI_PENDING; i++) { gAIPend[i].used = false; gAIPend[i].cumProfit = 0.0; }
   gAITrainCount = 0;

   bool loaded = false;
   if(!MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
      loaded = AI_Load();    // live: restore the trained model; tester: fresh seed

   gAIReady = true;

   string modeStr = (InpAIMode == 0) ? "OFF" :
                    (InpAIMode == 1) ? "ADVISORY" :
                    (InpAIMode == 2) ? "GATE" :
                    (InpAIMode == 4) ? "AI-LED" : "BLEND";
   JournalInfo("AI", StringFormat("Win-prob model ready — mode=%s source=%s trainN=%d",
               modeStr, loaded ? "loaded" : "seed", gAITrainCount));
}

//── Trade-lifecycle hooks (called from ProcessDealAdd in P7) ─────────
int AI_FindPend(ulong ticket)
{
   for(int i = 0; i < AI_PENDING; i++)
      if(gAIPend[i].used && gAIPend[i].ticket == ticket) return i;
   return -1;
}

void AI_OnTradeOpen(ulong ticket, ENUM_BIAS bias, int score)
{
   if(InpAIMode == 0) return;
   if(bias == BIAS_NONE) return;

   int idx = AI_FindPend(ticket);
   if(idx < 0)
      for(int i = 0; i < AI_PENDING; i++) if(!gAIPend[i].used) { idx = i; break; }
   if(idx < 0) return;       // store full — skip (no training for this trade)

   double f[];
   AI_BuildFeatures(bias, score, f);

   gAIPend[idx].used      = true;
   gAIPend[idx].ticket    = ticket;
   gAIPend[idx].cumProfit = 0.0;
   for(int k = 0; k < AI_NFEAT; k++) gAIPend[idx].f[k] = f[k];
}

// Accumulate realised P&L across partial + final exit deals.
void AI_AccumProfit(ulong ticket, double profit)
{
   int idx = AI_FindPend(ticket);
   if(idx >= 0) gAIPend[idx].cumProfit += profit;
}

// Final close: label = (whole-trade net P&L > 0), train, free slot.
void AI_OnTradeClose(ulong ticket)
{
   if(InpAIMode == 0) return;
   int idx = AI_FindPend(ticket);
   if(idx < 0) return;

   double label = (gAIPend[idx].cumProfit > 0.0) ? 1.0 : 0.0;
   double f[];
   ArrayResize(f, AI_NFEAT);
   for(int k = 0; k < AI_NFEAT; k++) f[k] = gAIPend[idx].f[k];

   double pBefore = AI_RawPredict(f);
   AI_TrainStep(f, label);

   JournalInfo("AI", StringFormat("LEARN tkt=%llu label=%.0f predicted=%.0f%% netPnL=%.2f n=%d",
               ticket, label, pBefore * 100.0, gAIPend[idx].cumProfit, gAITrainCount));

   gAIPend[idx].used = false;
   if((gAITrainCount % 10) == 0) AI_Save();   // periodic persist (live only)
}

#endif // SKP_P8_AI_MQH
