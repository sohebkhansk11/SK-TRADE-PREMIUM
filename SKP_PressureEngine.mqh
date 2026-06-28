//+------------------------------------------------------------------+
//|  SK_PressureEngine.mqh  —  Intraday Tick-by-Tick Pressure Engine |
//+------------------------------------------------------------------+
#ifndef SK_PRESSUREENGINE_MQH
#define SK_PRESSUREENGINE_MQH

// Standalone — no external dependencies (SK_Defines.mqh removed)
#define PRESS_HIST_DEPTH  30
#define PRESS_MIN_SAMPLE   5

//+------------------------------------------------------------------+
class CPressureEngine
{
private:
   long     m_buy_ticks;
   long     m_sell_ticks;
   long     m_total_ticks;
   double   m_last_bid;
   double   m_ratio;             // 0.0 – 1.0, cached
   datetime m_current_bar_time;
   string   m_symbol;
   bool     m_initialized;

   //--- Historical bar approximation storage (last N bars)
   double   m_hist_buy[PRESS_HIST_DEPTH];
   double   m_hist_sell[PRESS_HIST_DEPTH];
   int      m_hist_count;

   void     SeedHistoricalBars();
   void     PushHistory(double buy_vol, double sell_vol);

public:
   CPressureEngine();

   bool     Init(const string symbol);
   void     OnNewTick();
   void     OnNewBar();                       // called when bar changes
   void     SyncOnTFSwitch();                 // rebuilds history for new TF

   //--- Declarations only — out-of-class definitions below
   double   GetRatio()     const;
   long     GetBuyTicks()  const;
   long     GetSellTicks() const;
   long     GetTotal()     const;
   bool     IsValid()      const;

   //--- Composite historical pressure ratio over last N closed bars
   double   GetHistoricalRatio(int bars = PRESS_HIST_DEPTH) const;

   //--- Formatted pressure bar string for UI
   string   GetPressureBar(int width = 20) const;
};

//+------------------------------------------------------------------+
CPressureEngine::CPressureEngine()
   : m_buy_ticks(0), m_sell_ticks(0), m_total_ticks(0),
     m_last_bid(0.0), m_ratio(0.5), m_current_bar_time(0),
     m_symbol(""), m_initialized(false), m_hist_count(0)
{
   ArrayInitialize(m_hist_buy,  0.0);
   ArrayInitialize(m_hist_sell, 0.0);
}

//+------------------------------------------------------------------+
bool CPressureEngine::Init(const string symbol)
{
   m_symbol           = symbol;
   m_last_bid         = SymbolInfoDouble(symbol, SYMBOL_BID);
   m_current_bar_time = (datetime)SeriesInfoInteger(symbol, Period(), SERIES_LASTBAR_DATE);
   m_initialized      = true;
   SeedHistoricalBars();
   return true;
}

//+------------------------------------------------------------------+
void CPressureEngine::SeedHistoricalBars()
{
   MqlRates rates[];
   int n = CopyRates(m_symbol, Period(), 1, PRESS_HIST_DEPTH, rates);
   if(n <= 0) return;

   m_hist_count = 0;
   for(int i = n - 1; i >= 0; i--)
   {
      double range = rates[i].high - rates[i].low;
      double buy_v = 0.0, sell_v = 0.0;
      if(range > 0.0)
      {
         buy_v  = ((rates[i].close - rates[i].low) / range) * (double)rates[i].tick_volume;
         sell_v = (double)rates[i].tick_volume - buy_v;
      }
      else
      {
         buy_v  = (double)rates[i].tick_volume * 0.5;
         sell_v = buy_v;
      }
      PushHistory(buy_v, sell_v);
   }
}

//+------------------------------------------------------------------+
void CPressureEngine::PushHistory(double buy_vol, double sell_vol)
{
   //--- Shift array right by one, insert at [0]
   for(int i = PRESS_HIST_DEPTH - 1; i > 0; i--)
   {
      m_hist_buy[i]  = m_hist_buy[i-1];
      m_hist_sell[i] = m_hist_sell[i-1];
   }
   m_hist_buy[0]  = buy_vol;
   m_hist_sell[0] = sell_vol;
   if(m_hist_count < PRESS_HIST_DEPTH) m_hist_count++;
}

//+------------------------------------------------------------------+
void CPressureEngine::OnNewTick()
{
   if(!m_initialized) return;

   double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

   //--- Bar-reset detection
   datetime bar_now = (datetime)SeriesInfoInteger(m_symbol, Period(), SERIES_LASTBAR_DATE);
   if(bar_now != m_current_bar_time)
   {
      //--- Archive closing bar to history using the formula
      double range = SymbolInfoDouble(m_symbol, SYMBOL_LAST) - 0.0; // use live data
      MqlRates r[];
      if(CopyRates(m_symbol, Period(), 1, 1, r) > 0)
      {
         double rng = r[0].high - r[0].low;
         double bv  = (rng > 0.0) ? ((r[0].close - r[0].low) / rng) * (double)r[0].tick_volume : (double)r[0].tick_volume * 0.5;
         PushHistory(bv, (double)r[0].tick_volume - bv);
      }
      //--- Reset live counters
      m_buy_ticks        = 0;
      m_sell_ticks       = 0;
      m_total_ticks      = 0;
      m_current_bar_time = bar_now;
   }

   //--- Delta-based tick classification
   double delta = bid - m_last_bid;
   if(delta > 0.0)
      m_buy_ticks++;
   else if(delta < 0.0)
      m_sell_ticks++;
   else
   {
      double mid = bid + (ask - bid) * 0.5;
      if(bid >= mid) m_buy_ticks++; else m_sell_ticks++;
   }

   m_last_bid    = bid;
   m_total_ticks = m_buy_ticks + m_sell_ticks;

   if(m_total_ticks > 0)
      m_ratio = (double)m_buy_ticks / (double)m_total_ticks;
   else
      m_ratio = 0.5;
}

//+------------------------------------------------------------------+
void CPressureEngine::SyncOnTFSwitch()
{
   //--- Called when user switches TF; rebuild historical bars for new Period()
   m_buy_ticks        = 0;
   m_sell_ticks       = 0;
   m_total_ticks      = 0;
   m_hist_count       = 0;
   m_ratio            = 0.5;
   m_current_bar_time = (datetime)SeriesInfoInteger(m_symbol, Period(), SERIES_LASTBAR_DATE);
   ArrayInitialize(m_hist_buy,  0.0);
   ArrayInitialize(m_hist_sell, 0.0);
   SeedHistoricalBars();
}

//+------------------------------------------------------------------+
double CPressureEngine::GetHistoricalRatio(int bars) const
{
   int n    = MathMin(bars, m_hist_count);
   if(n <= 0) return 0.5;
   double tb = 0.0, ts = 0.0;
   for(int i = 0; i < n; i++) { tb += m_hist_buy[i]; ts += m_hist_sell[i]; }
   double tot = tb + ts;
   return (tot > 0.0) ? tb / tot : 0.5;
}

//+------------------------------------------------------------------+
string CPressureEngine::GetPressureBar(int width) const
{
   if(width < 4) width = 4;
   int filled = (int)MathRound(m_ratio * (double)width);
   filled = MathMax(0, MathMin(filled, width));
   string bar = "";
   for(int i = 0; i < filled;         i++) bar += "|";
   for(int i = filled; i < width;     i++) bar += ".";
   return bar;
}

//+------------------------------------------------------------------+
//  Out-of-class getter definitions
//+------------------------------------------------------------------+
double CPressureEngine::GetRatio()     const { return m_ratio; }
long   CPressureEngine::GetBuyTicks()  const { return m_buy_ticks; }
long   CPressureEngine::GetSellTicks() const { return m_sell_ticks; }
long   CPressureEngine::GetTotal()     const { return m_total_ticks; }
bool   CPressureEngine::IsValid()      const { return m_total_ticks >= PRESS_MIN_SAMPLE; }

//+------------------------------------------------------------------+
void CPressureEngine::OnNewBar()
{
   //--- Reset live counters on new bar (also handled inside OnNewTick bar-reset detection)
   m_buy_ticks        = 0;
   m_sell_ticks       = 0;
   m_total_ticks      = 0;
   m_ratio            = 0.5;
}

#endif // SK_PRESSUREENGINE_MQH
