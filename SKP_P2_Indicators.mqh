#ifndef SKP_P2_INDICATORS_MQH
#define SKP_P2_INDICATORS_MQH

//+------------------------------------------------------------------+
//| SK_TRADE_PREMIUM_BOT_P2.mq5                                      |
//|                                                                  |
//|  ENGINE 1 — MULTI-TIMEFRAME TREND STRENGTH MATRIX               |
//|  ENGINE 2 — RSI DIVERGENCE & OSCILLATOR CONFLUENCE              |
//|  ENGINE 3 — SESSION AWARENESS & CANDLESTICK PATTERN ENGINE      |
//|                                                                  |
//|  ASSEMBLY ORDER:  P1 → P2 → P3 → P4 → P5 → P6 → P7            |
//|  DO NOT COMPILE STANDALONE — requires P1 definitions            |
//|                                                                  |
//|  These engines produce supplemental signal modifiers consumed by  |
//|  ComputeEntrySignal() (P7) and TryNewEntry() (P3/P4).           |
//|  All public functions return additive score components (int)     |
//|  or filter booleans.  No orders are placed here.                |
//+------------------------------------------------------------------+

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 1 — MULTI-TIMEFRAME TREND STRENGTH MATRIX
//  Evaluates EMA9/EMA34 alignment on all 6 timeframes and produces
//  a weighted trend strength score and a consensus ENUM_BIAS.
//  Higher timeframes carry more weight (D1 > H4 > H1 > M15 > M5 > M1)
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 1.1  TF WEIGHT TABLE (must sum to 100)
//      IDX 0-5: standard system (moderate/scalp trend matrix)
//      IDX 6-8: HFT extended TFs — zero weight in trend matrix
//               (ComputeHFTEntrySignal uses these directly, not via matrix)
//--------------------------------------------------------------------
static const double TF_WEIGHT[TF_COUNT] = {
    4.0,   // IDX_M1   — noise filter; minor influence
   10.0,   // IDX_M5   — execution TF for scalp
   14.0,   // IDX_M15  — entry timing for moderate
   28.0,   // IDX_H1   — primary signal TF (highest single weight)
   26.0,   // IDX_H4   — higher-TF trend context
   18.0,   // IDX_D1   — macro direction
    0.0,   // IDX_M3   — HFT extended (no weight in standard trend matrix)
    0.0,   // IDX_M6   — HFT extended
    0.0    // IDX_M10  — HFT extended
};

//--------------------------------------------------------------------
// 1.2  SINGLE-TF EMA ALIGNMENT STATE (shift=1 = completed bar)
//      Returns: 1=bull, -1=bear, 0=neutral (< threshold separation)
//--------------------------------------------------------------------
int GetTFEMAState(int tfIdx)
{
   double e9  = GetEMA9 (tfIdx, 1);
   double e34 = GetEMA34(tfIdx, 1);
   if(e9 == EMPTY_VALUE || e34 == EMPTY_VALUE) return 0;

   double atr       = GetATR(tfIdx, 1);
   double threshold = (atr > DBL_EPSILON) ? atr * 0.03 : gPoint * 2;
   double diff      = e9 - e34;

   if(diff >  threshold) return  1;
   if(diff < -threshold) return -1;
   return 0;
}

//--------------------------------------------------------------------
// 1.3  TREND MATRIX STATE STRUCT
//--------------------------------------------------------------------
struct TrendMatrix
{
   int    state[9];        // per-TF state: +1/-1/0 (9 = TF_COUNT; idx 6-8 HFT only)
   double weightedScore;   // ∈ [−100, +100]
   int    bullCount;
   int    bearCount;
   int    neutralCount;
   bool   htfConfirm;      // H4 + D1 agree
   bool   allAligned;      // ≥4 non-neutral TFs same direction
   ENUM_BIAS bias;
};

TrendMatrix gTrendMx;
bool        gTrendMxReady = false;

TrendMatrix EvaluateTrendMatrix()
{
   TrendMatrix tm;
   ArrayInitialize(tm.state, 0);
   tm.weightedScore = 0;
   tm.bullCount = tm.bearCount = tm.neutralCount = 0;
   tm.htfConfirm = false; tm.allAligned = false;
   tm.bias = BIAS_NONE;

   double sumW = 0;
   for(int i = 0; i < TF_COUNT; i++)
   {
      tm.state[i]       = GetTFEMAState(i);
      tm.weightedScore += TF_WEIGHT[i] * (double)tm.state[i];
      sumW             += TF_WEIGHT[i];

      if(tm.state[i] ==  1) tm.bullCount++;
      else if(tm.state[i] == -1) tm.bearCount++;
      else tm.neutralCount++;
   }

   if(sumW > 0) tm.weightedScore = SafeDiv(tm.weightedScore * 100.0, sumW);

   // HTF confirmation: H4 and D1 non-neutral and same direction
   if(tm.state[IDX_H4]!=0 && tm.state[IDX_D1]!=0 && tm.state[IDX_H4]==tm.state[IDX_D1])
      tm.htfConfirm = true;

   // Full alignment: ≥4 TFs in same direction
   if(tm.bullCount >= 4) tm.allAligned = true;
   if(tm.bearCount >= 4) tm.allAligned = true;

   if(tm.weightedScore >=  20) tm.bias = BIAS_BULL;
   else if(tm.weightedScore <= -20) tm.bias = BIAS_BEAR;

   return tm;
}

void RefreshTrendMatrix()
{
   gTrendMx      = EvaluateTrendMatrix();
   gTrendMxReady = true;
}

//--------------------------------------------------------------------
// 1.4  TREND MATRIX SCORE CONTRIBUTION  → ∈ [−15, +15]
//--------------------------------------------------------------------
int TrendMatrixScoreBonus(ENUM_BIAS tradeBias)
{
   if(!gTrendMxReady) RefreshTrendMatrix();

   double ws    = gTrendMx.weightedScore;
   int    score = 0;

   if(tradeBias == BIAS_BULL)
   {
      if     (ws >=  60) score = 15;
      else if(ws >=  40) score = 10;
      else if(ws >=  20) score =  5;
      else if(ws >=   0) score =  0;
      else if(ws >= -20) score = -5;
      else               score = -12;
   }
   else if(tradeBias == BIAS_BEAR)
   {
      if     (ws <= -60) score = 15;
      else if(ws <= -40) score = 10;
      else if(ws <= -20) score =  5;
      else if(ws <=   0) score =  0;
      else if(ws <=  20) score = -5;
      else               score = -12;
   }

   // HTF confirmation premium/penalty
   if(gTrendMx.htfConfirm)
   {
      int htfDir = gTrendMx.state[IDX_H4];
      if(tradeBias==BIAS_BULL && htfDir== 1) score = MathMin(score+3, 15);
      if(tradeBias==BIAS_BEAR && htfDir==-1) score = MathMin(score+3, 15);
      if(tradeBias==BIAS_BULL && htfDir==-1) score = MathMax(score-5,-15);
      if(tradeBias==BIAS_BEAR && htfDir== 1) score = MathMax(score-5,-15);
   }

   if(gTrendMx.allAligned) score = MathMin(score+3, 15);

   return MathMax(-15, MathMin(15, score));
}

//--------------------------------------------------------------------
// 1.5  HIGHER-TF HARD GATE  (D1+H4 strongly against = block)
//--------------------------------------------------------------------
bool TrendMatrixPassesHTFGate(ENUM_BIAS tradeBias)
{
   if(!gTrendMxReady) RefreshTrendMatrix();
   int d1 = gTrendMx.state[IDX_D1];
   int h4 = gTrendMx.state[IDX_H4];

   if(tradeBias==BIAS_BULL && d1==-1 && h4==-1) return false;
   if(tradeBias==BIAS_BEAR && d1== 1 && h4== 1) return false;
   return true;
}

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 2 — RSI DIVERGENCE & OSCILLATOR CONFLUENCE DETECTOR
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 2.1  SWING POINT DETECTION  (closed bars only, shift ≥ 1)
//--------------------------------------------------------------------
int FindLastSwingHigh(int tfIdx, int lookback=15)
{
   double highs[]; ArraySetAsSeries(highs,true);
   if(CopyHigh(gSymbol,gTF[tfIdx].tf,1,lookback+2,highs)<lookback+2) return -1;
   for(int i=1;i<lookback;i++)
      if(highs[i]>highs[i-1] && highs[i]>highs[i+1]) return i;
   return -1;
}

int FindLastSwingLow(int tfIdx, int lookback=15)
{
   double lows[]; ArraySetAsSeries(lows,true);
   if(CopyLow(gSymbol,gTF[tfIdx].tf,1,lookback+2,lows)<lookback+2) return -1;
   for(int i=1;i<lookback;i++)
      if(lows[i]<lows[i-1] && lows[i]<lows[i+1]) return i;
   return -1;
}

//--------------------------------------------------------------------
// 2.2  RSI DIVERGENCE DETECTOR
//      Returns:  1=bullish div, -1=bearish div, 0=none
//--------------------------------------------------------------------
int DetectRSIDivergence(int tfIdx)
{
   int lkb = 20;
   double highs[],lows[],rsi[];
   ArraySetAsSeries(highs,true); ArraySetAsSeries(lows,true); ArraySetAsSeries(rsi,true);

   if(CopyHigh  (gSymbol,gTF[tfIdx].tf,1,lkb+2,highs)<lkb+2) return 0;
   if(CopyLow   (gSymbol,gTF[tfIdx].tf,1,lkb+2,lows) <lkb+2) return 0;
   if(CopyBuffer(gTF[tfIdx].hRSI,0,    1,lkb+2,rsi)  <lkb+2) return 0;

   // Find two swing highs for bearish divergence
   int sh1=-1, sh2=-1;
   for(int i=1; i<lkb && (sh1<0||sh2<0); i++)
      if(highs[i]>highs[i-1] && highs[i]>highs[i+1])
      { if(sh1<0) sh1=i; else if(sh2<0) {sh2=i; break;} }

   if(sh1>0 && sh2>0 && highs[sh1]>highs[sh2] && rsi[sh1]<rsi[sh2])
      return -1;   // bearish divergence

   // Find two swing lows for bullish divergence
   int sl1=-1, sl2=-1;
   for(int i=1; i<lkb && (sl1<0||sl2<0); i++)
      if(lows[i]<lows[i-1] && lows[i]<lows[i+1])
      { if(sl1<0) sl1=i; else if(sl2<0) {sl2=i; break;} }

   if(sl1>0 && sl2>0 && lows[sl1]<lows[sl2] && rsi[sl1]>rsi[sl2])
      return 1;    // bullish divergence

   return 0;
}

//--------------------------------------------------------------------
// 2.3  MACD HISTOGRAM MOMENTUM  (expanding = strong directional move)
//      Returns: 1=expanding bull, -1=expanding bear, 0=flat/contracting
//--------------------------------------------------------------------
int MACDHistogramMomentum(int tfIdx)
{
   double m0=GetMACDMain(tfIdx,1)-GetMACDSig(tfIdx,1);
   double m1=GetMACDMain(tfIdx,2)-GetMACDSig(tfIdx,2);
   double m2=GetMACDMain(tfIdx,3)-GetMACDSig(tfIdx,3);
   if(m0==EMPTY_VALUE||m1==EMPTY_VALUE||m2==EMPTY_VALUE) return 0;

   if(MathAbs(m0)>MathAbs(m1) && MathAbs(m1)>MathAbs(m2))
      return (m0>0) ? 1 : -1;
   return 0;
}

//--------------------------------------------------------------------
// 2.4  STOCHASTIC CROSS AGE  (bars since last cross in trade direction)
//--------------------------------------------------------------------
int StochCrossAge(int tfIdx, ENUM_BIAS bias, int lookback=8)
{
   double k[],d[];
   ArraySetAsSeries(k,true); ArraySetAsSeries(d,true);
   if(CopyBuffer(gTF[tfIdx].hStoch,0,1,lookback+1,k)<lookback+1) return -1;
   if(CopyBuffer(gTF[tfIdx].hStoch,1,1,lookback+1,d)<lookback+1) return -1;

   for(int i=0;i<lookback;i++)
   {
      bool xBull = (k[i]>d[i] && k[i+1]<=d[i+1]);
      bool xBear = (k[i]<d[i] && k[i+1]>=d[i+1]);
      if(bias==BIAS_BULL && xBull) return i;
      if(bias==BIAS_BEAR && xBear) return i;
   }
   return -1;
}

//--------------------------------------------------------------------
// 2.5  DIVERGENCE SCORE BONUS  → ∈ [−12, +12]
//--------------------------------------------------------------------
int DivergenceScoreBonus(ENUM_BIAS tradeBias)
{
   int divH1 = DetectRSIDivergence(IDX_H1);
   int divM5 = DetectRSIDivergence(IDX_M5);
   int score = 0;

   if(tradeBias==BIAS_BULL && divH1== 1) score +=  8;
   if(tradeBias==BIAS_BEAR && divH1==-1) score +=  8;
   if(tradeBias==BIAS_BULL && divH1==-1) score -=  8;
   if(tradeBias==BIAS_BEAR && divH1== 1) score -=  8;
   if(tradeBias==BIAS_BULL && divM5== 1) score +=  4;
   if(tradeBias==BIAS_BEAR && divM5==-1) score +=  4;
   if(tradeBias==BIAS_BULL && divM5==-1) score -=  4;
   if(tradeBias==BIAS_BEAR && divM5== 1) score -=  4;

   int macdMom = MACDHistogramMomentum(IDX_H1);
   if(tradeBias==BIAS_BULL && macdMom== 1) score += 3;
   if(tradeBias==BIAS_BEAR && macdMom==-1) score += 3;
   if(tradeBias==BIAS_BULL && macdMom==-1) score -= 3;
   if(tradeBias==BIAS_BEAR && macdMom== 1) score -= 3;

   int crossAge = StochCrossAge(IDX_H1, tradeBias, 8);
   if(crossAge == 0)      score += 4;
   else if(crossAge == 1) score += 3;
   else if(crossAge == 2) score += 1;

   return MathMax(-12, MathMin(12, score));
}

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 3 — SESSION AWARENESS & CANDLESTICK PATTERN ENGINE
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 3.1  SESSION CONSTANTS AND DETECTION
//--------------------------------------------------------------------
#define SESSION_ASIAN   0
#define SESSION_LONDON  1
#define SESSION_NY      2
#define SESSION_OVERLAP 3
#define SESSION_PACIFIC 4
#define SESSION_NONE    5

#ifndef InpServerUTCOffset
  #define InpServerUTCOffset 0
#endif

static const string SESS_NAME[6] = {"ASIAN","LONDON","NEW YORK","LON/NY OVERLAP","PACIFIC","CLOSED"};

int GetCurrentSessionId()
{
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   int h = dt.hour - InpServerUTCOffset;
   if(h < 0) h += 24;
   if(h >= 24) h -= 24;

   if(h >= 12 && h < 16) return SESSION_OVERLAP;
   if(h >= 12 && h < 21) return SESSION_NY;
   if(h >=  7 && h < 16) return SESSION_LONDON;
   if(h >= 22 || h < 8)  return SESSION_ASIAN;
   if(h >= 20 && h < 22) return SESSION_PACIFIC;
   return SESSION_NONE;
}

string GetSessionName()    { return SESS_NAME[GetCurrentSessionId()]; }
bool   IsHighLiquidity()   { return GetCurrentSessionId()==SESSION_OVERLAP; }
bool   IsLowLiquidity()    { int s=GetCurrentSessionId(); return(s==SESSION_ASIAN||s==SESSION_PACIFIC||s==SESSION_NONE); }
bool   IsLondonOpen()      { int s=GetCurrentSessionId(); return(s==SESSION_LONDON||s==SESSION_OVERLAP); }
bool   IsNYOpen()          { int s=GetCurrentSessionId(); return(s==SESSION_NY||s==SESSION_OVERLAP); }

//--------------------------------------------------------------------
// 3.2  SESSION SCORE MODIFIER → ∈ [−5, +4]
//--------------------------------------------------------------------
int SessionScoreModifier(ENUM_BIAS bias)
{
   switch(GetCurrentSessionId())
   {
      case SESSION_OVERLAP: return  4;
      case SESSION_LONDON:  return  2;
      case SESSION_NY:      return  2;
      case SESSION_ASIAN:   return -2;
      case SESSION_PACIFIC: return -3;
      case SESSION_NONE:    return -5;
      default:              return  0;
   }
}

bool SessionPassesEntryGate()
{
   int s = GetCurrentSessionId();
   if(gBotMode==BOT_MODE_SCALPING) return (s!=SESSION_NONE && s!=SESSION_PACIFIC);
   return (s != SESSION_NONE);
}

//--------------------------------------------------------------------
// 3.3  CANDLESTICK PATTERN DETECTOR
//--------------------------------------------------------------------
enum ENUM_CANDLE_PATTERN
{
   CPAT_NONE=0, CPAT_BULL_ENGULF=1, CPAT_BEAR_ENGULF=2,
   CPAT_BULL_PIN=3,  CPAT_BEAR_PIN=4,
   CPAT_BULL_INSIDE=5, CPAT_BEAR_INSIDE=6,
   CPAT_DOJI=7, CPAT_MARUBOZU_B=8, CPAT_MARUBOZU_S=9
};

ENUM_CANDLE_PATTERN DetectBarPattern(int tfIdx, int shift=1)
{
   double oA[],hA[],lA[],cA[];   // dynamic — required for ArraySetAsSeries
   ArraySetAsSeries(oA,true); ArraySetAsSeries(hA,true);
   ArraySetAsSeries(lA,true); ArraySetAsSeries(cA,true);

   if(CopyOpen (gSymbol,gTF[tfIdx].tf,shift,2,oA)<2) return CPAT_NONE;
   if(CopyHigh (gSymbol,gTF[tfIdx].tf,shift,2,hA)<2) return CPAT_NONE;
   if(CopyLow  (gSymbol,gTF[tfIdx].tf,shift,2,lA)<2) return CPAT_NONE;
   if(CopyClose(gSymbol,gTF[tfIdx].tf,shift,2,cA)<2) return CPAT_NONE;

   double o1=oA[0],h1=hA[0],l1=lA[0],c1=cA[0];
   double o2=oA[1],h2=hA[1],l2=lA[1],c2=cA[1];
   double atr   = GetATR(tfIdx, shift);
   if(atr < DBL_EPSILON) return CPAT_NONE;

   double body1  = MathAbs(c1-o1);
   double body2  = MathAbs(c2-o2);
   double range1 = h1-l1;

   // Marubozu: body ≥ 80% of range
   if(range1 > atr*0.30 && body1 >= range1*0.80)
      return (c1>o1) ? CPAT_MARUBOZU_B : CPAT_MARUBOZU_S;

   // Engulfing: bar1 body engulfs bar2 body
   if(body1 > atr*0.30 && body2 > atr*0.10)
   {
      double mx1=MathMax(o1,c1),mn1=MathMin(o1,c1);
      double mx2=MathMax(o2,c2),mn2=MathMin(o2,c2);
      if(mx1>mx2 && mn1<mn2)
      {
         if(c1>o1 && c2<o2) return CPAT_BULL_ENGULF;
         if(c1<o1 && c2>o2) return CPAT_BEAR_ENGULF;
      }
   }

   // Pin bar: small body + long tail
   if(body1 <= range1*0.30 && range1 > atr*0.40)
   {
      double lwk = MathMin(o1,c1)-l1;
      double uwk = h1-MathMax(o1,c1);
      if(lwk >= range1*0.60 && uwk <= range1*0.20) return CPAT_BULL_PIN;
      if(uwk >= range1*0.60 && lwk <= range1*0.20) return CPAT_BEAR_PIN;
   }

   // Inside bar
   if(h1 < h2 && l1 > l2)
      return (c2>o2) ? CPAT_BULL_INSIDE : CPAT_BEAR_INSIDE;

   // Doji
   if(range1 > atr*0.20 && body1 < range1*0.10) return CPAT_DOJI;

   return CPAT_NONE;
}

//--------------------------------------------------------------------
// 3.4  PATTERN SCORE BONUS → ∈ [−10, +10]
//--------------------------------------------------------------------
int PatternScoreBonus(ENUM_BIAS tradeBias)
{
   ENUM_CANDLE_PATTERN pH1 = DetectBarPattern(IDX_H1,1);
   ENUM_CANDLE_PATTERN pM5 = DetectBarPattern(IDX_M5,1);
   int score = 0;

   // H1 patterns (higher weight)
   if(pH1==CPAT_BULL_ENGULF) score += (tradeBias==BIAS_BULL) ?  8 : -6;
   if(pH1==CPAT_BEAR_ENGULF) score += (tradeBias==BIAS_BEAR) ?  8 : -6;
   if(pH1==CPAT_BULL_PIN)    score += (tradeBias==BIAS_BULL) ?  6 : -4;
   if(pH1==CPAT_BEAR_PIN)    score += (tradeBias==BIAS_BEAR) ?  6 : -4;
   if(pH1==CPAT_MARUBOZU_B)  score += (tradeBias==BIAS_BULL) ?  5 : -3;
   if(pH1==CPAT_MARUBOZU_S)  score += (tradeBias==BIAS_BEAR) ?  5 : -3;
   if(pH1==CPAT_BULL_INSIDE) score += (tradeBias==BIAS_BULL) ?  3 :  0;
   if(pH1==CPAT_BEAR_INSIDE) score += (tradeBias==BIAS_BEAR) ?  3 :  0;
   if(pH1==CPAT_DOJI)        score -= 2;

   // M5 patterns (lower weight)
   if(pM5==CPAT_BULL_ENGULF) score += (tradeBias==BIAS_BULL) ?  4 : -3;
   if(pM5==CPAT_BEAR_ENGULF) score += (tradeBias==BIAS_BEAR) ?  4 : -3;
   if(pM5==CPAT_BULL_PIN)    score += (tradeBias==BIAS_BULL) ?  3 : -2;
   if(pM5==CPAT_BEAR_PIN)    score += (tradeBias==BIAS_BEAR) ?  3 : -2;
   if(pM5==CPAT_MARUBOZU_B)  score += (tradeBias==BIAS_BULL) ?  2 : -1;
   if(pM5==CPAT_MARUBOZU_S)  score += (tradeBias==BIAS_BEAR) ?  2 : -1;

   return MathMax(-10, MathMin(10, score));
}

//--------------------------------------------------------------------
// 3.5  COMBINED ENGINE 2+3 SCORE BONUS → ∈ [−15, +15]
//--------------------------------------------------------------------
int Engine23ScoreBonus(ENUM_BIAS tradeBias)
{
   int total = 0;
   total += DivergenceScoreBonus(tradeBias);
   total += PatternScoreBonus(tradeBias);
   total += SessionScoreModifier(tradeBias);
   total += TrendMatrixScoreBonus(tradeBias);
   return MathMax(-15, MathMin(15, total));
}

//--------------------------------------------------------------------
// 3.6  COMBINED ENGINE FILTER GATE  (all hard filters)
//--------------------------------------------------------------------
bool EngineFiltersPass(ENUM_BIAS tradeBias)
{
   // v6.3f: In HFT mode the D1/H4 gate is BYPASSED by default (InpHFTRespectHTFFilter=false).
   // HFT trades on M1-M15 tick-scale; D1/H4 counter-trend is irrelevant and kills flow.
   // Set InpHFTRespectHTFFilter=true in the EA inputs to re-enable this gate for HFT.
   bool applyHTFGate = !((gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE) && !InpHFTRespectHTFFilter);
   if(applyHTFGate && !TrendMatrixPassesHTFGate(tradeBias))
   { JournalInfo("E2Flt","BLOCK — HTF D1/H4 counter-trend"); return false; }

   if(!SessionPassesEntryGate())
   { JournalInfo("E2Flt","BLOCK — session low-liquidity gate"); return false; }
   return true;
}

//--------------------------------------------------------------------
// 3.7  ENGINE 1-3 CACHE REFRESH  (call from RefreshBarData extension)
//--------------------------------------------------------------------
int  gLastDivH1     = 0;
int  gLastDivM5     = 0;
int  gLastSessionId = SESSION_NONE;

void RefreshEngine23Cache()
{
   if(gTF[IDX_H1].newBar) { gLastDivH1=DetectRSIDivergence(IDX_H1); RefreshTrendMatrix(); }
   if(gTF[IDX_M5].newBar)   gLastDivM5=DetectRSIDivergence(IDX_M5);
   gLastSessionId = GetCurrentSessionId();
}

//====================================================================
//  ┌────────────────────────────────────────────────────────────────┐
//  │   END OF PART 2                                                 │
//  │   Next → Part 3: Engines 4-6                                   │
//  │   (Lot Resolution | SL/TP Calc | Management Sub-functions |    │
//  │    Safety Sub-functions | Retry Queue | TryNewEntry)           │
//  └────────────────────────────────────────────────────────────────┘
//====================================================================


#endif // SKP_P2_INDICATORS_MQH
