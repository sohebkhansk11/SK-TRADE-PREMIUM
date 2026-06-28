#ifndef SKP_P6_UI_MQH
#define SKP_P6_UI_MQH

//+------------------------------------------------------------------+
//| SK_TRADE_PREMIUM_BOT_P6.mq5                                      |
//|                                                                  |
//|  ENGINE 13 — ASYNC TELEGRAM NOTIFICATION SYSTEM                  |
//|  ENGINE 14 — GLASSMORPHISM REAL-TIME DASHBOARD (CCanvas ARGB)    |
//|  ENGINE 15 — UPDATE / PATCH INJECTION ENGINE                     |
//|                                                                  |
//|  ASSEMBLY ORDER:  P1 → P2 → P3 → P4 → P5 → P6 → P7             |
//|                                                                  |
//|  REQUIRES in final assembled file header section (P1 area):      |
//|    #include <Canvas/Canvas.mqh>                                  |
//|                                                                  |
//|  DO NOT COMPILE STANDALONE — requires all prior part definitions |
//|                                                                  |
//|  P1 TelegramQueue struct MUST contain these fields:             |
//|    bool   active;   string message;  string chatId;             |
//|    datetime timestamp;  int retryCount;                         |
//|  Add retryCount to P1 struct if not present.                    |
//|                                                                  |
//|  NASA-Grade MQL5 EA — Production Tier Engineering               |
//|  SK TRADE PREMIUM Development Team — Version 6.0 Part 6         |
//+------------------------------------------------------------------+

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 13 — ASYNC TELEGRAM NOTIFICATION SYSTEM
//  128-slot ring-buffer queue | HTML parse mode | rate-limited send
//  15 alert templates | hourly/daily/weekly scheduled reports
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 13.1  TELEGRAM ENGINE CONSTANTS
//--------------------------------------------------------------------
#define TG_MAX_RETRIES          3          // max send attempts before drop
#define TG_RETRY_DELAY_SEC      30         // seconds before each retry attempt
#define TG_SEND_RATE_MS         300        // minimum ms between consecutive sends
#define TG_MAX_MSG_CHARS        4000       // Telegram hard limit 4096; buffer to 4000
#define TG_HTTP_TIMEOUT_MS      8000       // WebRequest timeout
#define TG_QUEUE_DEPTH_WARN     100        // warn journal if queue exceeds this
#define TG_BATCH_PER_TIMER      3          // max messages drained per OnTimer call

// Telegram emoji constants — Unicode characters sent via Telegram Bot API (UTF-8 over HTTP).
// MQL5 transmits these correctly through StringToCharArray + HTTP request.
// Verified: Telegram renders all Plane-0 and Plane-1 emoji from MQL5 string literals.
#define TGE_BULL    "📈"   // 📈  rising chart
#define TGE_BEAR    "📉"   // 📉  falling chart
#define TGE_WARN    "⚠️" // ⚠️  warning sign
#define TGE_LOCK    "🔒"   // 🔒  locked
#define TGE_UNLOCK  "🔓"   // 🔓  unlocked
#define TGE_ROCKET  "🚀"   // 🚀  rocket (bot start)
#define TGE_STOP    "🛑"   // 🛑  stop sign (bot offline)
#define TGE_FIRE    "🔥"   // 🔥  fire (hot / urgent)
#define TGE_CHECK   "✅"       // ✅  green check
#define TGE_CROSS   "❌"       // ❌  red cross
#define TGE_CLOCK   "⏰"       // ⏰  alarm clock (time)
#define TGE_CHART   "📊"   // 📊  bar chart
#define TGE_MONEY   "💰"   // 💰  money bag (P&L)
#define TGE_SKULL   "💀"   // 💀  skull (critical loss)
#define TGE_SHIELD  "🛡️" // 🛡️  shield (safety)
#define TGE_BOLT    "⚡"       // ⚡  lightning (HFT / spike)
#define TGE_NEWS    "📰"   // 📰  newspaper (news filter)
#define TGE_THERM   "🌡️" // 🌡️  thermometer (regime)
#define TGE_WRENCH  "🔧"   // 🔧  wrench (system / config)
#define TGE_PULSE   "💹"   // 💹  chart with yen (P&L pulse)
#define TGE_GREEN   "🟢"   // 🟢  green circle (profit / buy)
#define TGE_RED     "🔴"   // 🔴  red circle (loss / sell)
#define TGE_YELLOW  "🟡"   // 🟡  yellow circle (neutral)
#define TGE_STAR    "⭐"       // ⭐  star (strong signal)
#define TGE_SPIKE   "🚨"   // 🚨  siren (spike detected)
#define TGE_TROPHY  "🏆"   // 🏆  trophy (TP hit)
#define TGE_TARGET  "🎯"   // 🎯  target (entry)

//--------------------------------------------------------------------
// 13.2  TELEGRAM ENGINE SUPPLEMENTAL GLOBALS
//        (declare here if not already in P1; safe to remove duplicates
//         during assembly if P1 already declares them)
//--------------------------------------------------------------------
datetime  gTGLastHourlyRpt  = 0;    // epoch of last hourly report sent
datetime  gTGLastDailyRpt   = 0;    // epoch of last daily report sent
datetime  gTGLastWeeklyRpt  = 0;    // epoch of last weekly report sent
ulong     gTGLastSendMs     = 0;    // GetTickCount64() snapshot at last send
int       gTGTotalSent      = 0;    // lifetime sent messages this session
int       gTGDropped        = 0;    // messages dropped (queue full / retries)
bool      gTGConnOK         = false;// true if most recent send succeeded
string    gTGLastErrStr     = "";   // last error description for dashboard

// NOTE: gTGQHead, gTGQTail, gTGQueue[128] are declared in P1.
//       If P1 does not declare them, uncomment these two lines:
// int gTGQHead = 0;
// int gTGQTail = 0;

//--------------------------------------------------------------------
// 13.3  HTML ENCODING HELPERS
//        Telegram HTML parse mode requires escaping:  &  <  >
//        All other characters (including emojis) pass through raw.
//--------------------------------------------------------------------

// Escape raw content for embedding inside Telegram HTML tags
string TGHtmlEsc(const string raw)
{
   string s = raw;
   StringReplace(s, "&",  "&amp;");   // MUST be first
   StringReplace(s, "<",  "&lt;");
   StringReplace(s, ">",  "&gt;");
   return s;
}

// Bold, italic, code wrappers — content inside is HTML-escaped
string TGH(const string t)  { return "<b>"    + TGHtmlEsc(t) + "</b>";    }
string TGI(const string t)  { return "<i>"    + TGHtmlEsc(t) + "</i>";    }
string TGC(const string t)  { return "<code>" + TGHtmlEsc(t) + "</code>"; }

// Divider line — ASCII only (safe across all encodings and Telegram clients)
string TGLine() { return "----------------------"; }

// Bot-mode string helper
string TGBotModeStr()
{
   if(gBotMode == BOT_MODE_HFT)      return "HFT";
   if(gBotMode == BOT_MODE_SCALPING) return "SCALP";
   return "MODERATE";
}

//--------------------------------------------------------------------
// 13.4  JSON BODY ENCODER
//        Escapes a plain string for safe embedding inside a JSON
//        string value.  Must run before string is placed in the JSON
//        payload sent to Telegram.  HTML tags survive unmodified
//        because < > are not special in JSON.
//--------------------------------------------------------------------
string TGJsonEncode(const string raw)
{
   string s = raw;
   StringReplace(s, "\\", "\\\\");   // backslash first to avoid double-escape
   StringReplace(s, "\"", "\\\"");   // quote
   StringReplace(s, "\n", "\\n");    // newline
   StringReplace(s, "\r", "\\r");    // carriage return
   StringReplace(s, "\t", "\\t");    // tab
   return s;
}

// Truncate message to TG_MAX_MSG_CHARS (operates on raw/HTML string)
string TGTruncate(const string msg)
{
   if(StringLen(msg) <= TG_MAX_MSG_CHARS) return msg;
   return StringSubstr(msg, 0, TG_MAX_MSG_CHARS - 40)
          + "\n<i>... [message truncated]</i>";
}

//--------------------------------------------------------------------
// 13.5  RAW HTTP SENDER  (BLOCKING — only call from ProcessTelegramQueue)
//        Sends one pre-formatted HTML message via Telegram Bot API.
//        Returns true on HTTP 200, false on any error.
//
//        PREREQUISITE: api.telegram.org must be whitelisted in MT5:
//          Tools → Options → Expert Advisors → Allow WebRequest for URL
//--------------------------------------------------------------------
bool TGSendRaw(const string htmlMsg, const string chatId)
{
   if(!InpUseTelegram)                    return true;   // silently succeed when disabled
   if(StringLen(InpTelegramBotToken) < 8) return false;  // no valid token

   string url  = "https://api.telegram.org/bot" + InpTelegramBotToken + "/sendMessage";

   // Build JSON payload; message is JSON-encoded to handle quotes / newlines
   string safeMsg = TGJsonEncode(TGTruncate(htmlMsg));
   string json    = "{\"chat_id\":\""    + chatId   + "\","
                  + "\"text\":\""        + safeMsg  + "\","
                  + "\"parse_mode\":\"HTML\","
                  + "\"disable_web_page_preview\":true}";

   // Convert to UTF-8 byte array (remove null terminator that MQL5 appends)
   char   postData[];
   char   resultData[];
   string resultHeaders = "";

   StringToCharArray(json, postData, 0, StringLen(json), CP_UTF8);
   ArrayResize(postData, ArraySize(postData) - 1);

   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int httpCode = WebRequest("POST", url, headers, TG_HTTP_TIMEOUT_MS,
                              postData, resultData, resultHeaders);

   if(httpCode == 200)
   {
      gTGConnOK    = true;
      gTGTotalSent++;
      gTGLastErrStr = "";
      return true;
   }

   // Decode failure
   int  lastErr = GetLastError();
   if(httpCode == -1)
   {
      gTGLastErrStr = StringFormat("WebRequest ERR=%d", lastErr);
      if(lastErr == 4014)
         gTGLastErrStr += " [Add api.telegram.org to MT5 WebRequest whitelist]";
   }
   else
   {
      string resp = CharArrayToString(resultData, 0, WHOLE_ARRAY, CP_UTF8);
      gTGLastErrStr = StringFormat("HTTP %d — %.200s", httpCode, resp);
   }

   gTGConnOK = false;
   JournalError("TGSendRaw", gTGLastErrStr);
   return false;
}

//--------------------------------------------------------------------
// 13.6  ENQUEUE  (NON-BLOCKING — safe to call from anywhere incl. OnTick)
//        Writes one message into the ring buffer.  Caller passes raw
//        HTML-formatted message; it is stored and sent asynchronously
//        by ProcessTelegramQueue() called from OnTimer.
//--------------------------------------------------------------------
void TGEnqueue(const string htmlMsg, const string chatId = "")
{
   if(!InpUseTelegram) return;

   string target = (StringLen(chatId) > 0) ? chatId : InpTelegramChatId;
   if(StringLen(target) == 0) return;

   int nextTail = (gTGQTail + 1) % 128;

   // Queue full?  head == next-tail
   if(nextTail == gTGQHead)
   {
      gTGDropped++;
      if(gTGDropped <= 5 || gTGDropped % 100 == 0)
         JournalWarn("TGEnqueue",
                     StringFormat("Queue FULL — message #%d dropped. Preview: %.80s",
                                  gTGDropped, htmlMsg));
      return;
   }

   // Warn on deep queue (possible timer stall or send failure cascade)
   int depth = (gTGQTail - gTGQHead + 128) % 128;
   if(depth >= TG_QUEUE_DEPTH_WARN)
      JournalWarn("TGEnqueue", StringFormat("Queue depth %d — check WebRequest whitelist", depth));

   gTGQueue[gTGQTail].active      = true;
   gTGQueue[gTGQTail].message     = htmlMsg;   // store raw HTML, JSON-encode at send time
   gTGQueue[gTGQTail].chatId      = target;
   gTGQueue[gTGQTail].timestamp   = TimeLocal();
   gTGQueue[gTGQTail].retryCount  = 0;

   gTGQTail = nextTail;
}

//--------------------------------------------------------------------
// 13.7  PROCESS TELEGRAM QUEUE  (OnTimer only — never OnTick)
//        Rate-limited to TG_SEND_RATE_MS between individual sends.
//        Drains up to TG_BATCH_PER_TIMER messages per call.
//        Exponential back-off: retry slot waits (retryCount × TG_RETRY_DELAY_SEC)
//        before attempting again.  After TG_MAX_RETRIES failures, slot dropped.
//--------------------------------------------------------------------
void ProcessTelegramQueue()
{
   if(!InpUseTelegram)             return;
   if(gTGQHead == gTGQTail)        return;   // empty

   ulong nowMs    = GetTickCount64();
   int   drained  = 0;

   while(drained < TG_BATCH_PER_TIMER && gTGQHead != gTGQTail)
   {
      // Enforce inter-message rate limit
      if(drained > 0)
      {
         nowMs = GetTickCount64();
         if(nowMs - gTGLastSendMs < (ulong)TG_SEND_RATE_MS) break;
      }
      else
      {
         if(nowMs - gTGLastSendMs < (ulong)TG_SEND_RATE_MS) break;
      }

      int idx = gTGQHead;

      // Skip inactive slot (should not normally occur)
      if(!gTGQueue[idx].active)
      {
         gTGQHead = (gTGQHead + 1) % 128;
         drained++;
         continue;
      }

      // Retry back-off: do not retry too soon
      if(gTGQueue[idx].retryCount > 0)
      {
         int waitSec = gTGQueue[idx].retryCount * TG_RETRY_DELAY_SEC;
         if((int)(TimeLocal() - gTGQueue[idx].timestamp) < waitSec)
            break;   // this slot not ready; stop draining (FIFO order preserved)
      }

      bool ok = TGSendRaw(gTGQueue[idx].message, gTGQueue[idx].chatId);
      gTGLastSendMs = GetTickCount64();

      if(ok)
      {
         gTGQueue[idx].active = false;
         gTGQHead = (gTGQHead + 1) % 128;
         drained++;
      }
      else
      {
         gTGQueue[idx].retryCount++;
         if(gTGQueue[idx].retryCount > TG_MAX_RETRIES)
         {
            JournalError("TGQueue",
                         StringFormat("Dropped after %d retries: %.60s",
                                      TG_MAX_RETRIES, gTGQueue[idx].message));
            gTGQueue[idx].active = false;
            gTGQHead = (gTGQHead + 1) % 128;
            gTGDropped++;
            drained++;
         }
         else
         {
            gTGQueue[idx].timestamp = TimeLocal();  // reset back-off timer
            break;                                   // stop; retry this slot later
         }
      }
   }
}

//====================================================================
// 13.8  ALERT TEMPLATE LIBRARY (15 templates)
//        All functions build HTML-formatted strings and call TGEnqueue.
//        Content values are HTML-escaped via TGHtmlEsc().
//        Structural HTML tags (<b>,<i>,<code>) are written literally.
//====================================================================

//--- T01: Bot Started
void TGAlert_BotStart()
{
   string name    = TGHtmlEsc(AccountInfoString(ACCOUNT_NAME));
   string broker  = TGHtmlEsc(AccountInfoString(ACCOUNT_COMPANY));
   long   acctNo  = AccountInfoInteger(ACCOUNT_LOGIN);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   string msg = TGE_ROCKET " " + TGH("SK TRADE PREMIUM " + GetVersionString() + " — ONLINE") + "\n"
              + TGLine() + "\n"
              + TGE_CLOCK " Started: "  + TGC(TimeToString(TimeLocal(), TIME_DATE|TIME_MINUTES)) + "\n"
              + "Account: "  + TGC(IntegerToString(acctNo))  + " | " + name   + "\n"
              + "Broker:  "  + broker + "\n"
              + "Symbol:  "  + TGC(gSymbol) + "\n"
              + "Mode:    "  + TGH(TGBotModeStr()) + "\n"
              + "Balance: "  + TGC("$" + DoubleToString(balance, 2)) + "\n"
              + TGLine() + "\n"
              + TGE_SHIELD " Safety systems: ARMED\n"
              + TGE_CHECK  " All engines initialized\n"
              + TGLine();

   TGEnqueue(msg);
}

//--- TGReport_Boot: alias to TGAlert_BotStart (boot/startup notification)
//    Called by P7 OnInit; also aliased here for backward-compat function lookup.
void TGReport_Boot() { TGAlert_BotStart(); }

//--- T02: Bot Stopped
void TGAlert_BotStop(const string reason)
{
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double bidNow   = SymbolInfoDouble(gSymbol, SYMBOL_BID);   // v6.3e: price tracking
   int    openCnt  = 0;
   for(int i = 0; i < 100; i++) if(gRec[i].active) openCnt++;

   string msg = TGE_STOP " " + TGH("SK TRADE PREMIUM " + GetVersionString() + " — OFFLINE") + "\n"
              + TGLine() + "\n"
              + "Stopped: " + TGC(TimeToString(TimeLocal(), TIME_DATE|TIME_MINUTES)) + "\n"
              + "Reason:  " + TGH(TGHtmlEsc(reason)) + "\n"
              + TGLine() + "\n"
              + "Price:    " + TGC(DoubleToString(bidNow, gDigits)) + "\n"      // v6.3e
              + "Equity:   " + TGC("$" + DoubleToString(equity, 2)) + "\n"
              + "Day P&L:  " + TGC((gDailyClosedPnL>=0?"+":"") + DoubleToString(gDailyClosedPnL,2)) + "\n"
              + "Open Pos: " + TGC(IntegerToString(openCnt)) + "\n"
              + TGLine() + "\n"
              + TGE_WARN " Review open positions manually on MT5";

   TGEnqueue(msg);
}

//--- T03: New Trade Entry — enhanced with full levels + risk + emoji
void TGAlert_TradeEntry(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;

   bool   isBuy   = (gRec[idx].posType == ORDER_TYPE_BUY);
   string dirEmoji= isBuy ? TGE_BULL : TGE_BEAR;
   string dirTxt  = isBuy ? "BUY" : "SELL";
   string modeStr;
   if(gBotMode == BOT_MODE_HFT)      modeStr = TGE_BOLT " HFT";
   else if(gRec[idx].isScalpMode)    modeStr = TGE_FIRE " SCALP";
   else                               modeStr = TGE_CHART " MODERATE";

   double slDist   = SafeDiv(MathAbs(gRec[idx].entryPrice - gRec[idx].stopLoss),   gPoint);
   double tp1Dist  = SafeDiv(MathAbs(gRec[idx].tp1Price   - gRec[idx].entryPrice), gPoint);
   double tp3Dist  = SafeDiv(MathAbs(gRec[idx].tp3Price   - gRec[idx].entryPrice), gPoint);
   double riskUSD  = slDist * gTickValue * (gPipSize/gPoint) * gRec[idx].initialVolume;
   double rrTP3    = (slDist > DBL_EPSILON) ? SafeDiv(tp3Dist, slDist) : 0.0;

   string msg = TGE_TARGET " " + TGH("NEW TRADE ENTRY") + "\n"
              + TGLine() + "\n"
              + dirEmoji + " " + TGH(dirTxt) + "  " + TGC(gRec[idx].symbol)
              + "  #" + TGC(IntegerToString(gRec[idx].ticket)) + "\n"
              + modeStr + "  Score: " + TGC(IntegerToString(gLastScore)) + "/93\n"
              + TGLine() + "\n"
              + TGE_TARGET + " Entry:    " + TGH(DoubleToString(gRec[idx].entryPrice, gDigits)) + "\n"
              + TGE_RED    + " SL:       " + TGC(DoubleToString(gRec[idx].stopLoss,   gDigits))
                           + "  <i>(" + DoubleToString(slDist,1) + " pts)</i>\n"
              + TGE_GREEN  + " TP1:      " + TGC(DoubleToString(gRec[idx].tp1Price,   gDigits))
                           + "  <i>30% partial</i>\n"
              + TGE_GREEN  + " TP2:      " + TGC(DoubleToString(gRec[idx].tp2Price,   gDigits))
                           + "  <i>40% partial</i>\n"
              + TGE_TROPHY + " TP3:      " + TGC(DoubleToString(gRec[idx].tp3Price,   gDigits))
                           + "  <i>30% runner  R:R=" + DoubleToString(rrTP3,2) + "R</i>\n"
              + TGLine() + "\n"
              + TGE_MONEY  + " Vol:      " + TGC(DoubleToString(gRec[idx].initialVolume,2)) + " lots"
                           + "   Risk: " + TGC("$" + DoubleToString(riskUSD,2)) + "\n"
              + TGE_THERM  + " Regime:   " + TGC(RegimeToString(gRegime.regime))
                           + "  BSP: " + TGC(StringFormat(
                               (gBotMode==BOT_MODE_HFT)
                               ? "B%.0f%% S%.0f%% Tick:%.0f%%"
                               : "B%.0f%% S%.0f%%",
                               (gBotMode==BOT_MODE_HFT) ? gBSP.hftBuyPct  : gBSP.buyPct,
                               (gBotMode==BOT_MODE_HFT) ? gBSP.hftSellPct : gBSP.sellPct,
                               gBSP.tickFlowBull * 100.0)) + "\n"
              + TGE_WRENCH + " Reason:   " + TGI(TGHtmlEsc(gRec[idx].entryReason));

   TGEnqueue(msg);
}

//--- T04: TP1 Hit — 30% partial close — hit price + P&L shown
void TGAlert_TP1Hit(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;

   bool   isBuy    = (gRec[idx].posType == ORDER_TYPE_BUY);
   double hitPrice = gRec[idx].tp1Price;
   double pips     = SafeDiv(MathAbs(hitPrice - gRec[idx].entryPrice), gPoint);
   double closedV  = NormalizeLotSafe(gRec[idx].initialVolume * 0.30, gSymbol);
   double pnl      = pips * gTickValue * (gPipSize/gPoint) * closedV * (isBuy?1.0:-1.0);

   string msg = TGE_GREEN TGE_MONEY " " + TGH("TP1 HIT — 30% Banked") + "\n"
              + TGLine() + "\n"
              + (isBuy?TGE_BULL:TGE_BEAR) + " " + (isBuy?"BUY":"SELL")
              + "  " + TGC(gRec[idx].symbol)
              + "  #" + TGC(IntegerToString(gRec[idx].ticket)) + "\n"
              + TGLine() + "\n"
              + TGE_TARGET + " Entry:    " + TGC(DoubleToString(gRec[idx].entryPrice, gDigits)) + "\n"
              + TGE_TROPHY + " TP1 Hit:  " + TGH(DoubleToString(hitPrice, gDigits))
                           + "  <i>+" + DoubleToString(pips,1) + " pts</i>\n"
              + TGE_MONEY  + " P&L:      " + TGH("+" + DoubleToString(pnl,2) + " USD")
                           + "  <i>" + DoubleToString(closedV,2) + " lots closed</i>\n"
              + TGLine() + "\n"
              + TGE_SHIELD + " Breakeven: ACTIVATING  "
              + TGE_STAR   + " Runner: 70% still open";

   TGEnqueue(msg);
}

//--- T05: TP2 Hit — 40% partial close — hit price + P&L shown
void TGAlert_TP2Hit(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;

   bool   isBuy    = (gRec[idx].posType == ORDER_TYPE_BUY);
   double hitPrice = gRec[idx].tp2Price;
   double pips     = SafeDiv(MathAbs(hitPrice - gRec[idx].entryPrice), gPoint);
   double closedV  = NormalizeLotSafe(gRec[idx].initialVolume * 0.40, gSymbol);
   double pnl      = pips * gTickValue * (gPipSize/gPoint) * closedV * (isBuy?1.0:-1.0);

   string msg = TGE_GREEN TGE_GREEN TGE_MONEY " " + TGH("TP2 HIT — 40% Banked") + "\n"
              + TGLine() + "\n"
              + (isBuy?TGE_BULL:TGE_BEAR) + " " + (isBuy?"BUY":"SELL")
              + "  " + TGC(gRec[idx].symbol)
              + "  #" + TGC(IntegerToString(gRec[idx].ticket)) + "\n"
              + TGLine() + "\n"
              + TGE_TARGET + " Entry:    " + TGC(DoubleToString(gRec[idx].entryPrice, gDigits)) + "\n"
              + TGE_TROPHY + " TP2 Hit:  " + TGH(DoubleToString(hitPrice, gDigits))
                           + "  <i>+" + DoubleToString(pips,1) + " pts</i>\n"
              + TGE_MONEY  + " P&L:      " + TGH("+" + DoubleToString(pnl,2) + " USD")
                           + "  <i>" + DoubleToString(closedV,2) + " lots closed</i>\n"
              + TGLine() + "\n"
              + TGE_SHIELD + " TSL Active  " + TGE_STAR + " 30% runner: FREE PROFIT RIDE";

   TGEnqueue(msg);
}

//--- T06: TP3 Hit — FULL CLOSE — complete P&L summary
void TGAlert_TP3Hit(int idx, double closedPnL)
{
   string sym = gSymbol, dir = "—";
   bool   isBuy = true;
   ulong  tkt   = 0;
   double ep = 0, tp3p = 0, slp = 0;
   if(idx >= 0 && idx < 100)
   {
      sym   = gRec[idx].symbol;
      isBuy = (gRec[idx].posType == ORDER_TYPE_BUY);
      dir   = isBuy ? "BUY" : "SELL";
      tkt   = gRec[idx].ticket;
      ep    = gRec[idx].entryPrice;
      tp3p  = gRec[idx].tp3Price;
      slp   = gRec[idx].stopLoss;
   }

   double pips   = SafeDiv(MathAbs(tp3p - ep), gPoint);
   bool   isWin  = (closedPnL >= 0);
   string result = isWin ? TGE_TROPHY " FULL WIN" : TGE_CROSS " LOSS";
   string streakS= (gConsecWins > 0) ?
                   TGE_FIRE " " + IntegerToString(gConsecWins) + " WIN STREAK!" :
                   TGE_WARN " " + IntegerToString(gConsecLosses) + " loss streak";
   string dayClr = (gDailyClosedPnL >= 0) ? "+" : "";

   string msg = TGE_TROPHY TGE_TROPHY " " + TGH("TRADE FULLY CLOSED — TP3") + "\n"
              + TGLine() + "\n"
              + (isBuy?TGE_BULL:TGE_BEAR) + " " + dir
              + "  " + TGC(sym) + "  #" + TGC(IntegerToString(tkt)) + "\n"
              + TGLine() + "\n"
              + TGE_TARGET + " Entry:    " + TGC(DoubleToString(ep,   gDigits)) + "\n"
              + TGE_TROPHY + " TP3 Hit:  " + TGH(DoubleToString(tp3p, gDigits))
                           + "  <i>+" + DoubleToString(pips,1) + " pts</i>\n"
              + TGE_RED    + " SL was:   " + TGC(DoubleToString(slp,  gDigits)) + "\n"
              + TGLine() + "\n"
              + result + "\n"
              + TGE_PULSE  + " Trade P&L: " + TGH((isWin?"+":"") + DoubleToString(closedPnL,2) + " USD") + "\n"
              + TGE_CHART  + " Day Total: " + TGC(dayClr + DoubleToString(gDailyClosedPnL,2) + " USD") + "\n"
              + TGLine() + "\n"
              + streakS;

   TGEnqueue(msg);
}

//--- T07: Stop Loss Hit — hit price + full loss detail
void TGAlert_StopLoss(int idx, double closedPnL)
{
   string sym  = gSymbol, dir = "—";
   bool   isBuy= true;
   ulong  tkt  = 0;
   double ep   = 0, slp = 0;
   if(idx >= 0 && idx < 100)
   {
      sym   = gRec[idx].symbol;
      isBuy = (gRec[idx].posType == ORDER_TYPE_BUY);
      dir   = isBuy ? "BUY" : "SELL";
      tkt   = gRec[idx].ticket;
      ep    = gRec[idx].entryPrice;
      slp   = gRec[idx].stopLoss;
   }

   double pips    = SafeDiv(MathAbs(slp - ep), gPoint);
   string dayClr  = (gDailyClosedPnL >= 0) ? "+" : "";
   string streak  = (gConsecLosses >= 3) ?
                    TGE_SKULL + " " + IntegerToString(gConsecLosses) + " CONSECUTIVE LOSSES!" :
                    TGE_WARN  + " " + IntegerToString(gConsecLosses) + " loss(es) in a row";
   string limit   = (gConsecLosses >= InpMaxConsecLosses) ?
                    "\n" + TGE_LOCK + " MAX LOSS STREAK REACHED — SAFETY ARMED" : "";

   string msg = TGE_RED TGE_CROSS + " " + TGH("STOP LOSS HIT") + "\n"
              + TGLine() + "\n"
              + (isBuy?TGE_BULL:TGE_BEAR) + " " + dir
              + "  " + TGC(sym) + "  #" + TGC(IntegerToString(tkt)) + "\n"
              + TGLine() + "\n"
              + TGE_TARGET  + " Entry:    " + TGC(DoubleToString(ep,  gDigits)) + "\n"
              + TGE_RED     + " SL Hit:   " + TGH(DoubleToString(slp, gDigits))
                            + "  <i>-" + DoubleToString(pips,1) + " pts</i>\n"
              + TGE_PULSE   + " Loss:     " + TGH(DoubleToString(closedPnL,2) + " USD") + "\n"
              + TGE_CHART   + " Day P&L:  " + TGC(dayClr + DoubleToString(gDailyClosedPnL,2) + " USD") + "\n"
              + TGLine() + "\n"
              + streak + limit;

   TGEnqueue(msg);
}

//--- T08: Breakeven Activated
void TGAlert_BreakevenSet(int idx)
{
   if(idx < 0 || idx >= 100 || !gRec[idx].active) return;

   double ep = gRec[idx].entryPrice;
   string msg = TGE_SHIELD + " " + TGH("BREAKEVEN ACTIVATED") + "\n"
              + TGLine() + "\n"
              + TGC(gRec[idx].symbol)
              + "  #" + TGC(IntegerToString(gRec[idx].ticket)) + "\n"
              + TGE_TARGET + " Entry = SL: " + TGH(DoubleToString(ep, gDigits)) + "\n"
              + TGE_CHECK  + " Zero risk from this point forward\n"
              + TGE_STAR   + " Free ride to TP2 / TP3";

   TGEnqueue(msg);
}

//--- T09: TSL Hit (Trailing Stop closed trade)
void TGAlert_TSLHit(int idx, double hitPrice, double closedPnL)
{
   if(idx < 0 || idx >= 100) return;

   bool   isBuy = (gRec[idx].posType == ORDER_TYPE_BUY);
   double ep    = gRec[idx].entryPrice;
   double pips  = SafeDiv(MathAbs(hitPrice - ep), gPoint);
   string dayClr= (gDailyClosedPnL >= 0) ? "+" : "";
   bool   isWin = (closedPnL >= 0);

   string msg = TGE_SHIELD + " " + TGH("TRAILING STOP CLOSED") + "\n"
              + TGLine() + "\n"
              + (isBuy?TGE_BULL:TGE_BEAR) + " " + (isBuy?"BUY":"SELL")
              + "  " + TGC(gRec[idx].symbol)
              + "  #" + TGC(IntegerToString(gRec[idx].ticket)) + "\n"
              + TGLine() + "\n"
              + TGE_TARGET + " Entry:    " + TGC(DoubleToString(ep,       gDigits)) + "\n"
              + TGE_SHIELD + " TSL Hit:  " + TGH(DoubleToString(hitPrice, gDigits))
                           + "  <i>" + (pips>=0?"+":"") + DoubleToString(pips,1) + " pts</i>\n"
              + TGE_PULSE  + " P&L:      " + TGH((isWin?"+":"") + DoubleToString(closedPnL,2) + " USD") + "\n"
              + TGE_CHART  + " Day P&L:  " + TGC(dayClr + DoubleToString(gDailyClosedPnL,2) + " USD") + "\n"
              + TGLine() + "\n"
              + (isWin ? TGE_CHECK + " Profit locked by trailing stop" :
                         TGE_WARN  + " TSL triggered before breakeven");

   TGEnqueue(msg);
}

//--- T09b: RSI Exhaustion Partial Close  — v6.3c: adds current price + entry
void TGAlert_ExhaustionClose(int idx, double closedVol)
{
   if(idx < 0 || idx >= 100) return;

   bool   isBuy   = (gRec[idx].posType == ORDER_TYPE_BUY);
   string exDir   = isBuy ? "OVERBOUGHT" : "OVERSOLD";
   double bidNow  = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   double ep      = gRec[idx].entryPrice;
   double pnlPts  = isBuy ? (bidNow - ep) / gPoint : (ep - bidNow) / gPoint;
   double pnlUSD  = pnlPts * gTickValue * (gPipSize/gPoint) * closedVol;

   string msg = TGE_WARN + " " + TGH("RSI EXHAUSTION — PARTIAL EXIT") + "\n"
              + TGLine() + "\n"
              + (isBuy?TGE_BULL:TGE_BEAR) + " " + (isBuy?"BUY":"SELL")
              + "  " + TGC(gRec[idx].symbol)
              + "  #" + TGC(IntegerToString(gRec[idx].ticket)) + "\n"
              + TGLine() + "\n"
              + TGE_TARGET + " Entry:     " + TGC(DoubleToString(ep,     gDigits)) + "\n"
              + TGE_BOLT   + " Current:   " + TGH(DoubleToString(bidNow, gDigits))
                           + "  <i>(" + (pnlPts>=0?"+":"") + DoubleToString(pnlPts,1) + " pts)</i>\n"
              + TGE_RED    + " SL:        " + TGC(DoubleToString(gRec[idx].stopLoss, gDigits)) + "\n"
              + TGLine() + "\n"
              + TGE_THERM + " RSI State: " + TGH(exDir) + "\n"
              + TGE_MONEY + " Closed:    " + TGC(DoubleToString(closedVol,2))
                          + " lots (50%)  est P&L: " + TGC((pnlUSD>=0?"+":"") + DoubleToString(pnlUSD,2) + " USD") + "\n"
              + TGE_SHIELD + " Remaining 50% still open\n"
              + TGE_CHECK  + " Exhaustion latch: ACTIVE (one-time)";

   TGEnqueue(msg);
}

//--- T10: Safety Lock Engaged  — v6.3c: adds current price
void TGAlert_SafetyLock(const string lockName, const string reason)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPct   = SafeDiv(balance - equity, balance) * 100.0;
   double bidNow  = SymbolInfoDouble(gSymbol, SYMBOL_BID);

   string msg = TGE_LOCK " " + TGH("SAFETY LOCK ENGAGED") + "\n"
              + TGLine() + "\n"
              + "Lock Type: " + TGH(TGHtmlEsc(lockName)) + "\n"
              + "Reason:    " + TGI(TGHtmlEsc(reason)) + "\n"
              + TGLine() + "\n"
              + "Price:     " + TGC(DoubleToString(bidNow, gDigits)) + "\n"
              + "Equity:    " + TGC("$" + DoubleToString(equity, 2)) + "\n"
              + "Drawdown:  " + TGC(DoubleToString(ddPct, 2) + "%") + "\n"
              + "Day P&L:   " + TGC((gDailyClosedPnL>=0?"+":"") + DoubleToString(gDailyClosedPnL,2)) + "\n"
              + TGLine() + "\n"
              + TGE_WARN " NEW ENTRIES BLOCKED until lock releases";

   TGEnqueue(msg);
}

//--- T11: Safety Lock Released
void TGAlert_SafetyRelease(const string lockName)
{
   double bidNow = SymbolInfoDouble(gSymbol, SYMBOL_BID);   // v6.3e: price tracking
   string msg = TGE_UNLOCK " " + TGH("SAFETY LOCK RELEASED") + "\n"
              + TGLine() + "\n"
              + "Lock:   " + TGH(TGHtmlEsc(lockName)) + "\n"
              + "Status: " + TGH("TRADING RESUMED") + "\n"
              + "Price:  " + TGC(DoubleToString(bidNow, gDigits)) + "\n"   // v6.3e
              + "Time:   " + TGC(TimeToString(TimeLocal(), TIME_MINUTES)) + "\n"
              + TGE_CHECK " System monitoring active";

   TGEnqueue(msg);
}

//--- T12: Emergency Close All
void TGAlert_EmergencyClose(int closedCount, const string trigger)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPct   = SafeDiv(balance - equity, balance) * 100.0;
   double bidNow  = SymbolInfoDouble(gSymbol, SYMBOL_BID);    // v6.3e: price tracking

   string msg = TGE_SKULL " " + TGH("EMERGENCY CLOSE ALL TRIGGERED") + "\n"
              + TGLine() + "\n"
              + "TRIGGER:  " + TGH(TGHtmlEsc(trigger)) + "\n"
              + "Price:    " + TGC(DoubleToString(bidNow, gDigits)) + "\n"  // v6.3e
              + "Closed:   " + TGC(IntegerToString(closedCount)) + " positions\n"
              + "Equity:   " + TGC("$" + DoubleToString(equity, 2)) + "\n"
              + "DD:       " + TGC(DoubleToString(ddPct, 2) + "%") + "\n"
              + TGLine() + "\n"
              + TGE_WARN " IMMEDIATE MANUAL REVIEW REQUIRED\n"
              + TGE_WARN " Verify residual positions in MT5 terminal";

   TGEnqueue(msg);
}

//--- T13: Market Regime Change  — v6.3c: adds current price + ATR values
void TGAlert_RegimeChange(ENUM_MARKET_REGIME prevR, ENUM_MARKET_REGIME newR)
{
   if(prevR == newR) return;   // no-op on same regime
   string multStr  = DoubleToString(RegimeLotMultiplier(), 2);
   double bidNow   = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   double atrNow   = gRegimeState.atrNow;
   double atrAvg   = gRegimeState.atrAvg;

   string msg = TGE_THERM " " + TGH("MARKET REGIME CHANGE") + "\n"
              + TGLine() + "\n"
              + "Symbol:    " + TGC(gSymbol) + "\n"
              + "Price:     " + TGH(DoubleToString(bidNow,  gDigits)) + "\n"
              + "Previous:  " + TGC(RegimeToString(prevR)) + "\n"
              + "New:       " + TGH(RegimeToString(newR))  + "\n"
              + TGLine() + "\n"
              + "ATR Now:   " + TGC(DoubleToString(atrNow,  gDigits+2)) + "\n"
              + "ATR Avg:   " + TGC(DoubleToString(atrAvg,  gDigits+2)) + "\n"
              + "ATR Ratio: " + TGC(DoubleToString(gRegimeState.atrRatio, 3)) + "\n"
              + "Lot Mult:  " + TGC(multStr + "×") + "\n"
              + TGLine() + "\n"
              + (newR == REGIME_HOSTILE   ? TGE_WARN  " HOSTILE — scalp suppressed (HFT continues)\n"  : "")
              + (newR == REGIME_EXPLOSIVE ? TGE_FIRE  " EXPLOSIVE — lot reduced to " + multStr + "×\n" : "")
              + (newR == REGIME_QUIET     ? TGE_PULSE " QUIET — reduced lot, scalp suppressed\n"       : "")
              + (newR == REGIME_NORMAL    ? TGE_CHECK " NORMAL — full trading resumed\n"                : "");

   TGEnqueue(msg);
}

//--- T14: Price Spike Detected  — v6.3c: adds from/to price and current bid
void TGAlert_SpikeDetected(double spikeRangePts, double atrRefPts)
{
   double ratio   = SafeDiv(spikeRangePts, atrRefPts);
   double bidNow  = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   double askNow  = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
   // Reconstruct approximate spike from/to using spikeRange centred on current price
   double halfRange = (spikeRangePts * gPoint) / 2.0;
   double fromPx  = bidNow - halfRange;  // spike floor estimate
   double toPx    = bidNow + halfRange;  // spike ceiling estimate

   string msg = TGE_SPIKE " " + TGH("PRICE SPIKE DETECTED") + "\n"
              + TGLine() + "\n"
              + "Symbol:     " + TGC(gSymbol) + "\n"
              + "Spike From: " + TGC(DoubleToString(fromPx, gDigits)) + "\n"
              + "Spike To:   " + TGH(DoubleToString(toPx,   gDigits)) + "\n"
              + "Range:      " + TGC(DoubleToString(spikeRangePts, 1) + " pts"
                              + "  (" + DoubleToString(spikeRangePts * gPoint / gPipSize, 1) + " pips)") + "\n"
              + "ATR Ref:    " + TGC(DoubleToString(atrRefPts,     1) + " pts") + "\n"
              + "Ratio:      " + TGH(DoubleToString(ratio, 2) + "× ATR") + "\n"
              + "Current:    " + TGC("B" + DoubleToString(bidNow, gDigits)
                              + " / A" + DoubleToString(askNow, gDigits)) + "\n"
              + TGLine() + "\n"
              + TGE_WARN " Score penalized −30 pts | Entries guarded";

   TGEnqueue(msg);
}

//--- T15: News Window Blocking  — v6.3e: adds price at time of block
void TGAlert_NewsBlocking(const string detail, int minBefore, int minAfter)
{
   double bidNow = SymbolInfoDouble(gSymbol, SYMBOL_BID);   // v6.3e: price tracking
   string msg = TGE_NEWS " " + TGH("NEWS WINDOW — ENTRIES BLOCKED") + "\n"
              + TGLine() + "\n"
              + "Symbol:  " + TGC(gSymbol) + "\n"
              + "Price:   " + TGC(DoubleToString(bidNow, gDigits)) + "\n"  // v6.3e
              + "Event:   " + TGI(TGHtmlEsc(detail)) + "\n"
              + "Buffer:  " + TGC(IntegerToString(minBefore) + "m before / "
                                + IntegerToString(minAfter)  + "m after") + "\n"
              + TGLine() + "\n"
              + TGE_CLOCK " Trading resumes after window clears";

   TGEnqueue(msg);
}

//====================================================================
// 13.9  SCHEDULED REPORT ENGINE
//       Hourly  — every hour on the hour (±5 min hysteresis)
//       Daily   — at midnight (00:00–00:05) on new day
//       Weekly  — Monday 00:05–00:10 after daily report fires
//====================================================================

// Build shared performance summary block (HTML formatted)
string TGBuildPerfBlock()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginLvl  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double ddPct      = SafeDiv(balance - equity, balance) * 100.0;

   int    openCount  = 0;
   double floatPnL   = 0.0;
   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active) continue;
      openCount++;
      if(PositionSelectByTicket(gRec[i].ticket))
         floatPnL += PositionGetDouble(POSITION_PROFIT);
   }

   double winRate = (gPerf.totalTrades > 0) ?
                    SafeDiv((double)gPerf.winTrades, (double)gPerf.totalTrades) * 100.0 : 0;
   double pf      = (MathAbs(gPerf.totalLoss) > DBL_EPSILON) ?
                    SafeDiv(gPerf.totalProfit, MathAbs(gPerf.totalLoss)) : 0;

   string s;
   s  = TGLine() + "\n";
   s += TGE_MONEY " <b>Account</b>\n";
   s += "Balance:    " + TGC("$" + DoubleToString(balance,    2)) + "\n";
   s += "Equity:     " + TGC("$" + DoubleToString(equity,     2)) + "\n";
   s += "Free Mrg:   " + TGC("$" + DoubleToString(freeMargin, 2)) + "\n";
   s += "Mrg Level:  " + TGC(DoubleToString(marginLvl, 1) + "%") + "\n";
   s += "Drawdown:   " + TGC(DoubleToString(ddPct,      2) + "%") + "\n";
   s += TGLine() + "\n";
   s += TGE_CHART " <b>Performance</b>\n";
   s += "Trades:     " + TGC(IntegerToString(gPerf.totalTrades)) + "\n";
   s += "Win Rate:   " + TGC(DoubleToString(winRate, 1) + "%") + "\n";
   s += "W / L:      " + TGC(IntegerToString(gPerf.winTrades) + " / "
                            + IntegerToString(gPerf.lossTrades))  + "\n";
   s += "Prof Factor:" + TGC(DoubleToString(pf, 2)) + "\n";
   s += "Day P&L:    " + TGC((gDailyClosedPnL>=0?"+":"") + DoubleToString(gDailyClosedPnL,2)) + "\n";
   s += "Float P&L:  " + TGC((floatPnL>=0?"+":"")        + DoubleToString(floatPnL,        2)) + "\n";
   s += TGLine() + "\n";
   s += "Open Pos: "   + TGC(IntegerToString(openCount)) + "\n";
   s += "Mode:     "   + TGC(TGBotModeStr()) + "\n";
   s += "Regime:   "   + TGC(RegimeToString(gRegime.regime)) + "\n";

   bool anyLk = (gSafety.lockEquityFloor  || gSafety.lockDailyLoss  ||
                 gSafety.lockGlobalDD     || gSafety.lockManualPause ||
                 gSafety.lockMacroDivergence || gSafety.lockSpread   ||
                 gSafety.lockStaleData    || gSafety.lockSpike       ||
                 gSafety.lockNews);
   s += "Locks:    " + TGC(anyLk ? "LOCKED" : "CLEAR");
   return s;
}

void TGReport_Hourly()
{
   string msg = TGE_CLOCK " " + TGH("HOURLY STATUS REPORT") + "\n"
              + "Time: " + TGC(TimeToString(TimeLocal(), TIME_DATE|TIME_MINUTES)) + "\n"
              + TGBuildPerfBlock();
   TGEnqueue(msg);
   gTGLastHourlyRpt = TimeLocal();
}

void TGReport_Daily()
{
   string dayStr = (gDailyClosedPnL >= 0) ? TGE_CHECK " PROFITABLE" : TGE_CROSS " LOSS DAY";
   string msg = TGE_CHART " " + TGH("DAILY TRADING REPORT") + "\n"
              + "Date: " + TGC(TimeToString(TimeLocal(), TIME_DATE)) + "\n"
              + TGLine() + "\n"
              + "<b>Day Result: " + dayStr + "</b>\n"
              + TGBuildPerfBlock() + "\n"
              + TGLine() + "\n"
              + "Best Trade:  " + TGC("$" + DoubleToString(gPerf.bestTrade,  2)) + "\n"
              + "Worst Trade: " + TGC("$" + DoubleToString(gPerf.worstTrade, 2)) + "\n"
              + TGE_ROCKET " Ready for next session";
   TGEnqueue(msg);
   gTGLastDailyRpt = TimeLocal();
}

void TGReport_Weekly()
{
   string msg = TGE_CHART TGE_CHART " " + TGH("WEEKLY PERFORMANCE SUMMARY") + "\n"
              + "Week ending: " + TGC(TimeToString(TimeLocal(), TIME_DATE)) + "\n"
              + TGBuildPerfBlock() + "\n"
              + TGLine() + "\n"
              + TGE_SHIELD " SK Trade Premium " + GetVersionString() + " monitoring continuously\n"
              + "Alerts sent:  " + TGC(IntegerToString(gTGTotalSent))  + " this session\n"
              + "Msgs dropped: " + TGC(IntegerToString(gTGDropped));
   TGEnqueue(msg);
   gTGLastWeeklyRpt = TimeLocal();
}

// Master scheduler — call from OnTimer
void CheckScheduledReports()
{
   if(!InpUseTelegram) return;

   datetime now = TimeLocal();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // ── Hourly: fire within first 5 minutes of each hour ──────────
   if(gTGLastHourlyRpt == 0)
      gTGLastHourlyRpt = now;                        // seed on first call, don't fire
   else if(dt.min < 5 && now - gTGLastHourlyRpt > 3500)
      TGReport_Hourly();

   // ── Daily: fire 00:00–00:05, once per day ─────────────────────
   if(gTGLastDailyRpt == 0)
      gTGLastDailyRpt = now;
   else if(dt.hour == 0 && dt.min < 5 && now - gTGLastDailyRpt > 82800)
      TGReport_Daily();

   // ── Weekly: Monday 00:05–00:10, once per week ─────────────────
   if(gTGLastWeeklyRpt == 0)
      gTGLastWeeklyRpt = now;
   else if(dt.day_of_week == 1 && dt.hour == 0 && dt.min >= 5 && dt.min < 10
           && now - gTGLastWeeklyRpt > 604000)
      TGReport_Weekly();
}

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 14 — GLASSMORPHISM REAL-TIME DASHBOARD
//  CCanvas ARGB overlay | 10 panel sections | timer-driven render
//  Interactive: drag, minimize, pause, mode-switch, panic-close
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 14.1  ARGB COLOR PALETTE  — VOID BLACK + NEON CYAN GLASSMORPHISM
//       Concept A palette: pure void black bg + neon cyan #00DCFF accent
//       Format:  0xAA RR GG BB   (Alpha Red Green Blue)
//       Alpha:   0x00 = transparent, 0xFF = fully opaque
//       NOTE: alpha channel of BG colors is dynamically scaled by
//             InpDashOpacity at render time (see DashAlpha() macro).
//--------------------------------------------------------------------
#define ARGB_BG_MAIN         0xF005050C   // main canvas bg      — void black 94%
#define ARGB_BG_PANEL        0xD00A0A18   // sub-panel bg        — near-black blue 82%
#define ARGB_BG_HEADER       0xF8070710   // header band         — pure black 97%
#define ARGB_BG_SUBHDR       0xC0080818   // sub-header          — deep void 75%
#define ARGB_BORDER_NORM     0x3000DCFF   // panel border normal — neon cyan 19% (glow)
#define ARGB_BORDER_HL       0x8000DCFF   // panel border hilite — neon cyan 50%
#define ARGB_BORDER_DANGER   0xC0FF2040   // panel border danger — hot red 75%
#define ARGB_TEXT_PRI        0xFFECF4FF   // primary text        — near-white
#define ARGB_TEXT_SEC        0xFF7AAABB   // secondary text      — muted cyan-gray
#define ARGB_TEXT_DIM        0xFF3A5060   // dim/label text      — void slate
#define ARGB_GREEN_NEON      0xFF00E896   // bull indicator      — neon mint
#define ARGB_RED_NEON        0xFFFF3055   // bear indicator      — hot crimson
#define ARGB_AMBER_WARN      0xFFFFB020   // warning             — golden amber
#define ARGB_CYAN_INFO       0xFF00DCFF   // information         — NEON CYAN (hero accent)
#define ARGB_PURPLE_ACC      0xFF9060FF   // accent 1            — electric violet
#define ARGB_TEAL_ACC        0xFF00D4C8   // accent 2            — deep teal
#define ARGB_BTN_SAFE        0xC018A050   // action btn: safe    — dark green 75%
#define ARGB_BTN_DANGER      0xC0A02030   // action btn: danger  — dark red 75%
#define ARGB_BTN_NEUTRAL     0xC0181830   // action btn: neutral — void slate 75%
#define ARGB_BTN_ACTIVE      0xD000DCFF   // toggle btn: active  — neon cyan bg 82%
#define ARGB_BTN_INACTIVE    0xA0101018   // toggle btn: off     — near-black 62%
#define ARGB_GOLD            0xFFD4A020   // gold accent         — rich gold
#define ARGB_BG_LOCK_ON      0xA0380010   // locked pill bg      — deep red 62%
#define ARGB_BG_LOCK_OFF     0x20080818   // clear pill bg       — void faint 12%
#define ARGB_SPARK_UP        0xCC00C880   // sparkline bull      — mint 80%
#define ARGB_SPARK_DN        0xCCCC3050   // sparkline bear      — crimson 80%
#define ARGB_GLOBE_RING      0xFF00DCFF   // globe ring/meridian — neon cyan
#define ARGB_GLOBE_CORE      0xE005050C   // globe fill          — void black 88%

// ── Opacity-scaled alpha helper ─────────────────────────────────────
// Apply InpDashOpacity scaling to a full-opaque ARGB color's alpha channel.
// usage: DashA(0xFFRRGGBB) → same color with alpha scaled by InpDashOpacity
uint DashA(uint argb)
{
   uchar baseAlpha = (uchar)((argb >> 24) & 0xFF);
   uchar scaled    = (uchar)((uint)baseAlpha * (uint)MathMax(0,MathMin(255,InpDashOpacity)) / 255);
   return (argb & 0x00FFFFFF) | ((uint)scaled << 24);
}

//--------------------------------------------------------------------
// 14.2  DASHBOARD LAYOUT CONSTANTS
//--------------------------------------------------------------------
// ── HUD (professional overlay) dimensions — declared here so UIInit() can reference them
#define HUD_W    310          // basic HUD canvas width
#define HUD_H    490          // basic HUD canvas height

#define DASH_W               660         // canvas width — widened for readability
#define DASH_H_BASE          820         // base canvas height — Apex compact design (v6.3f)
#define DASH_PANEL_GAP       5           // vertical gap between panels (px)
#define DASH_HDR_H           90          // draggable header height (px)
#define DASH_OBJ_NAME        "SKP_CANVAS"
#define DASH_FONT_MONO       "Consolas"
#define DASH_FONT_TITLE      "Arial Bold"
#define DASH_FSM             9           // font size: small  (was 7 — too tiny to read)
#define DASH_FMD             11          // font size: medium (was 8)
#define DASH_FLG             13          // font size: large  (was 9)
#define DASH_FXL             16          // font size: XL     (was 12)
#define DASH_FXXL            20          // font size: XXL    (was 15)

//--------------------------------------------------------------------
// 14.3  DASHBOARD STATE GLOBALS
// NOTE: gCanvas and gCanvasReady are declared in P1 globals — do not re-declare here.
//--------------------------------------------------------------------
// CCanvas gCanvas and bool gCanvasReady — declared in P1, used here
int       gDashX          = 10;          // canvas X position on chart
int       gDashY          = 30;          // canvas Y position on chart
int       gDashActualH    = DASH_H_BASE; // current canvas height (adjusts dynamically)
bool      gDashMinimized  = false;       // true = header-only display
bool      gDashNeedsRedraw= true;        // dirty flag — set whenever state changes
bool      gDashDragging   = false;       // true while mouse drag is in progress
int       gDashDragOX     = 0;           // canvas-local X at drag start
int       gDashDragOY     = 0;           // canvas-local Y at drag start
int       gDashRenderCnt  = 0;           // total renders (for debug strip)

// ── Equity sparkline ring-buffer (40 samples × 30s = ~20 min window) ──
#define SPARK_LEN         40
double    gEquityHist[SPARK_LEN];        // equity samples
int       gEquityHistPos  = 0;           // next write index (ring buffer)
int       gEquityHistFull = 0;           // filled sample count (0..SPARK_LEN)
datetime  gEquityLastSmpl = 0;           // last sample epoch
#define   EQUITY_SMPL_SEC 30             // seconds between samples

// Panic button two-click arm state
bool      gPanicArmed     = false;
datetime  gPanicArmedAt   = 0;

// Button bounding boxes (canvas-local coords, set during render)
struct DBtnRgn { int x,y,w,h; bool vis; };
DBtnRgn   gBtnPause    = {0,0,0,0,false};
DBtnRgn   gBtnMode     = {0,0,0,0,false};
DBtnRgn   gBtnPanic    = {0,0,0,0,false};
DBtnRgn   gBtnMinimize = {0,0,0,0,false};
DBtnRgn   gBtnBuy      = {0,0,0,0,false};  // v6.3d: dashboard BUY direction toggle
DBtnRgn   gBtnSell     = {0,0,0,0,false};  // v6.3d: dashboard SELL direction toggle
// Apex-style tab navigation (v6.3g — 5 tabs)
// 0=OVERVIEW  1=INDICATORS  2=TRADES  3=CONFIG  4=STATS
int       gDashTab     = 0;
DBtnRgn   gTabRgn[5]   = {{0,0,0,0,false},{0,0,0,0,false},{0,0,0,0,false},{0,0,0,0,false},{0,0,0,0,false}};

//--------------------------------------------------------------------
// 14.4  SUPPLEMENTAL GLOBALS referenced by Dashboard/Telegram
//       (not in P1-P5; declare here and remove duplicates on assembly)
//--------------------------------------------------------------------
// gImpliedNewsActive declared in P1 globals — not re-declared here
int      gScoreComp[8]      = {0,0,0,0,0,0,0,0}; // EMA,RSI,MACD,BB,STOCH,VOL,REGIME,BSP
int      gLastScore         = 0;          // absolute score [0..93] used for gate check
int      gLastRawScore      = 0;          // signed raw (negative=bear, positive=bull) — diagnostic only
datetime gPortLastScanTime  = 0;          // set by ScanPortfolioWatchlist() in P5

//--------------------------------------------------------------------
// 14.5  CANVAS LIFECYCLE
//--------------------------------------------------------------------
bool UIInit()
{
   if(!InpShowDashboard) return true;     // disabled — no-op success

   UIDestroy();                           // remove any stale canvas

   // Use smaller canvas for the professional HUD (non-glassmorphism mode)
   int cW = InpUseGlassmorphUI ? DASH_W    : HUD_W;
   int cH = InpUseGlassmorphUI ? DASH_H_BASE : HUD_H;

   if(!gCanvas.CreateBitmapLabel(0, 0, DASH_OBJ_NAME,
                                  gDashX, gDashY, cW, cH,
                                  COLOR_FORMAT_ARGB_NORMALIZE))
   {
      JournalError("UIInit", StringFormat("CCanvas.CreateBitmapLabel ERR=%d", GetLastError()));
      return false;
   }

   ObjectSetInteger(0, DASH_OBJ_NAME, OBJPROP_ZORDER,    100);
   ObjectSetInteger(0, DASH_OBJ_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, DASH_OBJ_NAME, OBJPROP_HIDDEN,     false);

   gCanvasReady    = true;
   gDashNeedsRedraw= true;

   JournalInfo("UIInit", StringFormat("Dashboard canvas %dx%d at (%d,%d)",
                                       cW, cH, gDashX, gDashY));
   return true;
}

void UIDestroy()
{
   if(gCanvasReady)
   {
      gCanvas.Destroy();
      gCanvasReady = false;
   }
   if(ObjectFind(0, DASH_OBJ_NAME) >= 0)
      ObjectDelete(0, DASH_OBJ_NAME);
}

void UINeedRedraw() { gDashNeedsRedraw = true; }

// Move canvas to (gDashX, gDashY) without full pixel redraw
void UIReposition()
{
   if(!gCanvasReady) return;
   ObjectSetInteger(0, DASH_OBJ_NAME, OBJPROP_XDISTANCE, gDashX);
   ObjectSetInteger(0, DASH_OBJ_NAME, OBJPROP_YDISTANCE, gDashY);
   ChartRedraw(0);
}

//--------------------------------------------------------------------
// 14.6  CANVAS DRAWING PRIMITIVES
//       All accept ARGB uint (0xAARRGGBB).
//--------------------------------------------------------------------
void DFill(int x1,int y1,int x2,int y2, uint c)
{
   if(!gCanvasReady) return;
   gCanvas.FillRectangle(x1,y1,x2,y2,c);
}

void DBorder(int x1,int y1,int x2,int y2, uint c, int t=1)
{
   if(!gCanvasReady) return;
   for(int i=0;i<t;i++) gCanvas.Rectangle(x1+i,y1+i,x2-i,y2-i,c);
}

// Glassmorphism sub-panel: dark fill + border + top-glow highlight
void DPanel(int x,int y,int w,int h, bool danger=false, bool hilite=false)
{
   DFill(x,y,x+w,y+h, ARGB_BG_PANEL);
   uint bc = danger  ? ARGB_BORDER_DANGER :
             hilite  ? ARGB_BORDER_HL     : ARGB_BORDER_NORM;
   DBorder(x,y,x+w,y+h, bc, 1);
   // Top-edge glow line (glassmorphism highlight)
   gCanvas.Line(x+2, y,   x+w-2, y,   hilite ? 0x50C0D8FF : 0x28809ABB);
   gCanvas.Line(x,   y+2, x,     y+h-2, 0x1C608090);  // left edge shimmer
}

// Horizontal divider
void DHLine(int x1,int x2,int y, uint c)
{
   if(!gCanvasReady) return;
   gCanvas.Line(x1,y,x2,y,c);
}

// Text (left-aligned, top anchor)
void DText(int x,int y, const string s, uint c,
           int fs=DASH_FMD, const string fn=DASH_FONT_MONO)
{
   if(!gCanvasReady) return;
   gCanvas.FontSet(fn,fs,0);
   gCanvas.TextOut(x,y,s,c,TA_LEFT|TA_TOP);
}

// Text centered within [x, x+w]
void DTextC(int x,int y,int w, const string s, uint c,
            int fs=DASH_FMD, const string fn=DASH_FONT_MONO)
{
   if(!gCanvasReady) return;
   gCanvas.FontSet(fn,fs,0);
   int tw=0,th=0; gCanvas.TextSize(s,tw,th);
   gCanvas.TextOut(x+(w-tw)/2, y, s, c, TA_LEFT|TA_TOP);
}

// Text right-aligned within [x, x+w]
void DTextR(int x,int y,int w, const string s, uint c,
            int fs=DASH_FMD, const string fn=DASH_FONT_MONO)
{
   if(!gCanvasReady) return;
   gCanvas.FontSet(fn,fs,0);
   int tw=0,th=0; gCanvas.TextSize(s,tw,th);
   gCanvas.TextOut(x+w-tw, y, s, c, TA_LEFT|TA_TOP);
}

// Horizontal progress bar — pct clamped [0,1]
void DBar(int x,int y,int w,int h, double pct, uint fill, uint bg=0x40202830)
{
   pct = MathMax(0.0, MathMin(1.0, pct));
   DFill(x,y,x+w,y+h, bg);
   int fw=(int)MathRound(w*pct);
   if(fw>0) DFill(x,y,x+fw,y+h,fill);
   DBorder(x,y,x+w,y+h, 0x30608090, 1);
}

// Bi-directional vertical bar — pct in [-1,1]; green above mid, red below
void DVBar(int x,int y,int w,int h, double pct)
{
   pct = MathMax(-1.0, MathMin(1.0, pct));
   DFill(x,y,x+w,y+h, 0x40202830);
   int mid = y+h/2;
   if(pct>=0) { int fh=(int)(h/2.0*pct);    DFill(x,mid-fh,x+w,mid,   ARGB_GREEN_NEON); }
   else       { int fh=(int)(h/2.0*(-pct));  DFill(x,mid,   x+w,mid+fh,ARGB_RED_NEON);  }
   gCanvas.Line(x,mid,x+w,mid,0x50608090);
}

// Filled circle dot
void DDot(int cx,int cy,int r, uint c)
{
   if(!gCanvasReady) return;
   gCanvas.FillCircle(cx,cy,r,c);
}

// ── Globe widget ────────────────────────────────────────────────────
// Draws a stylized planet globe with latitude rings, meridian ellipses,
// and a live-pulsing orbital dot. Used in the header panel.
// cx/cy = center; r = radius; accent = ARGB ring color
void DrawGlobe(int cx, int cy, int r, uint accent)
{
   // Base sphere fill — void black with slight blue tint
   gCanvas.FillCircle(cx, cy, r, ARGB_GLOBE_CORE);
   // Inner gradient: slightly lighter core
   gCanvas.FillCircle(cx - r/5, cy - r/5, r/3, 0x180A0A28);

   // Outer ring (planet outline) — neon cyan
   gCanvas.Circle(cx, cy, r,     accent);
   gCanvas.Circle(cx, cy, r - 1, (accent & 0x50FFFFFF));   // inner softening ring

   // ── Latitude lines (3 rings above and below equator) ────────────
   int latSteps[3] = {r*2/5, r*7/10, r*9/10};
   for(int li = 0; li < 3; li++)
   {
      int yOff = latSteps[li];
      int rxL  = (int)(MathSqrt((double)(r*r - (double)(yOff*yOff))) * 0.95);
      int ryL  = MathMax(3, r / 9);
      if(rxL < 6) continue;
      uint latClr = (li==0) ? (accent & 0x50FFFFFF) : (accent & 0x28FFFFFF);
      // Above equator
      gCanvas.Ellipse(cx-rxL, cy-yOff-ryL, cx+rxL, cy-yOff+ryL, latClr);
      // Below equator
      gCanvas.Ellipse(cx-rxL, cy+yOff-ryL, cx+rxL, cy+yOff+ryL, latClr);
   }
   // Equator (full visibility)
   gCanvas.Ellipse(cx-r+1, cy-r/8, cx+r-1, cy+r/8, accent & 0x70FFFFFF);

   // ── Meridian ellipses (2 longitude arcs) ─────────────────────────
   int mW1 = r * 45 / 100;
   gCanvas.Ellipse(cx-mW1, cy-r+1, cx+mW1, cy+r-1, accent & 0x50FFFFFF);
   int mW2 = r * 15 / 100;
   gCanvas.Ellipse(cx-mW2, cy-r+1, cx+mW2, cy+r-1, accent & 0x28FFFFFF);

   // ── Live orbital dot (pulses along equatorial orbit) ─────────────
   const double PI_VAL = 3.14159265358979;
   int  dotAngleDeg = (int)(TimeLocal() % 360);     // 1° per second orbit
   double rad  = (double)dotAngleDeg * PI_VAL / 180.0;
   int   dx    = cx + (int)((double)(r-2) * MathCos(rad));
   int   dy    = cy + (int)((double)(r-2) * 0.25 * MathSin(rad));  // flattened to equatorial plane

   // Glow halo (3 concentric, outer → inner)
   gCanvas.FillCircle(dx, dy, 6, accent & 0x20FFFFFF);
   gCanvas.FillCircle(dx, dy, 4, accent & 0x50FFFFFF);
   gCanvas.FillCircle(dx, dy, 2, accent & 0xA0FFFFFF);
   gCanvas.FillCircle(dx, dy, 1, 0xFFFFFFFF);        // bright white core pixel

   // ── Clip: re-draw outer circle to clean up any dot overflow ──────
   gCanvas.Circle(cx, cy, r, accent & 0x80FFFFFF);
}

// Draw a glassmorphism button; returns bounding box for hit-testing
DBtnRgn DBtn(int x,int y,int w,int h, const string lbl,
             uint bg, uint tc=ARGB_TEXT_PRI, bool pressed=false)
{
   DBtnRgn b; b.x=x; b.y=y; b.w=w; b.h=h; b.vis=true;
   DFill(x,y,x+w,y+h, bg);
   DBorder(x,y,x+w,y+h, pressed ? 0xFF404060 : 0x80809AC8, 1);
   if(!pressed) gCanvas.Line(x+1,y+1,x+w-1,y+1, 0x28FFFFFF);  // top gloss
   DTextC(x,y+(h-(DASH_FMD*2))/2, w, lbl, tc, DASH_FMD);
   return b;
}

// Status row: bullet dot + label + right-aligned value
void DStatusRow(int x,int y,int w, const string lbl, const string val, bool ok,
                uint lc=ARGB_TEXT_DIM)
{
   DDot(x+4, y+6, 3, ok ? ARGB_GREEN_NEON : ARGB_RED_NEON);
   DText(x+12, y, lbl, lc, DASH_FSM);
   DTextR(x,y,w, val, ok ? ARGB_GREEN_NEON : ARGB_RED_NEON, DASH_FSM);
}

//--------------------------------------------------------------------
// 14.6b  EQUITY SPARKLINE SAMPLER  (call from OnTimer)
//         Writes AccountEquity into ring buffer every EQUITY_SMPL_SEC.
//--------------------------------------------------------------------
void SampleEquityHistory()
{
   datetime now = TimeLocal();
   if(now - gEquityLastSmpl < (datetime)EQUITY_SMPL_SEC) return;
   gEquityLastSmpl = now;
   gEquityHist[gEquityHistPos] = AccountInfoDouble(ACCOUNT_EQUITY);
   gEquityHistPos = (gEquityHistPos + 1) % SPARK_LEN;
   if(gEquityHistFull < SPARK_LEN) gEquityHistFull++;
}

//--------------------------------------------------------------------
// 14.6c  SPARKLINE RENDERER  — draws equity history within bounding box
//         hist: ring-buffer; pos: next-write index; n: filled count
//         bal: balance reference line
//--------------------------------------------------------------------
void DSparkline(int x, int y, int w, int h, double bal)
{
   DFill(x, y, x+w, y+h, 0x40101820);
   DBorder(x, y, x+w, y+h, 0x30405060, 1);

   int n = gEquityHistFull;
   if(n < 2)
   {
      DText(x+4, y+(h-DASH_FSM*2)/2, "Collecting...", ARGB_TEXT_DIM, 6);
      return;
   }
   // Start index of oldest sample in ring buffer
   int start = (gEquityHistFull < SPARK_LEN) ? 0 : gEquityHistPos;

   // Find min/max for y-scaling
   double mn = 1e15, mx = -1e15;
   for(int i=0; i<n; i++)
   {
      double v = gEquityHist[(start+i) % SPARK_LEN];
      if(v < mn) mn = v;
      if(v > mx) mx = v;
   }
   // Ensure balance line is always visible even if equity never moved
   mn = MathMin(mn, bal * 0.999);
   mx = MathMax(mx, bal * 1.001);
   double rng = mx - mn;
   if(rng < 1.0) rng = 1.0;

   // Draw balance reference line
   int balY = y + h - 2 - (int)((bal - mn) / rng * (double)(h - 4));
   balY = MathMax(y+1, MathMin(y+h-2, balY));
   for(int lx2=x+1; lx2<x+w-1; lx2+=4)
      gCanvas.PixelSet(lx2, balY, 0x50607080);  // dotted balance line

   // Draw sparkline polyline with color based on above/below balance
   int prevPx=-1, prevPy=-1;
   for(int i=0; i<n; i++)
   {
      double v  = gEquityHist[(start+i) % SPARK_LEN];
      int    px = x + 1 + (n>1 ? (int)((double)i / (n-1) * (double)(w-3)) : 0);
      int    py = y + h - 2 - (int)((v - mn) / rng * (double)(h - 4));
      py = MathMax(y+1, MathMin(y+h-2, py));
      if(prevPx >= 0)
         gCanvas.Line(prevPx, prevPy, px, py,
                      (v >= bal) ? ARGB_SPARK_UP : ARGB_SPARK_DN);
      prevPx = px;
      prevPy = py;
   }
   // Terminal dot (latest value)
   if(prevPx >= 0)
   {
      double lastV = gEquityHist[(start + n - 1) % SPARK_LEN];
      DDot(prevPx, prevPy, 3, lastV >= bal ? ARGB_GREEN_NEON : ARGB_RED_NEON);
   }
}

//--------------------------------------------------------------------
// 14.7  PANEL 1 — HEADER  (Void Black + Neon Cyan + Globe widget)
//       Globe (left) | Bot name + mode badge | Symbol | Regime | TG | Minimize
//--------------------------------------------------------------------
void PanelHeader(int x, int &cy, int w)
{
   int pH = 96;   // header height — globe + title + regime + time strip
   DFill(x, cy, x+w, cy+pH, DashA(ARGB_BG_HEADER));

   // ── Neon cyan top-edge glow (4-layer gradient) ───────────────────
   gCanvas.Line(x, cy,   x+w, cy,   DashA(0xFF00DCFF));   // neon cyan top line
   gCanvas.Line(x, cy+1, x+w, cy+1, DashA(0x7000DCFF));
   gCanvas.Line(x, cy+2, x+w, cy+2, DashA(0x3000DCFF));
   gCanvas.Line(x, cy+3, x+w, cy+3, DashA(0x1000DCFF));

   // Bottom separator — neon cyan faint
   gCanvas.Line(x, cy+pH-1, x+w, cy+pH-1, DashA(0x3000DCFF));

   // ── Globe widget (left side) ─────────────────────────────────────
   int globeR = 28;
   int globeX = x + 14 + globeR;
   int globeY = cy + pH/2;
   DrawGlobe(globeX, globeY, globeR, ARGB_GLOBE_RING);

   // ── Title block (right of globe) ─────────────────────────────────
   int titleX = globeX + globeR + 10;
   DText(titleX, cy+8, "SK TRADE PREMIUM", ARGB_TEXT_PRI, DASH_FXXL, DASH_FONT_TITLE);

   // Version badge
   string verStr = GetVersionString();
   gCanvas.FontSet(DASH_FONT_MONO, DASH_FSM, 0);
   int tw=0,th=0; gCanvas.TextSize(verStr,tw,th);
   int vbx = titleX + 210;
   DFill  (vbx,   cy+9,  vbx+tw+10, cy+9+th+4,  DashA(0xC0000020));
   DBorder(vbx,   cy+9,  vbx+tw+10, cy+9+th+4,  DashA(0x7000DCFF), 1);
   DText  (vbx+5, cy+11, verStr, ARGB_CYAN_INFO, DASH_FSM);

   // ── TG status + Minimize (top-right corner) ──────────────────────
   uint tgC = gTGConnOK ? ARGB_GREEN_NEON : ARGB_AMBER_WARN;
   DDot(x+w-14, cy+9, 4, tgC);
   DText(x+w-32, cy+7, "TG", ARGB_TEXT_DIM, DASH_FSM);
   gCanvas.Line(x+w-37, cy+5, x+w-37, cy+21, DashA(0x30607080));

   gBtnMinimize.x=x+w-54; gBtnMinimize.y=cy+5;
   gBtnMinimize.w=14;      gBtnMinimize.h=14; gBtnMinimize.vis=true;
   DFill  (gBtnMinimize.x, gBtnMinimize.y,
           gBtnMinimize.x+gBtnMinimize.w, gBtnMinimize.y+gBtnMinimize.h, DashA(0x60080818));
   DBorder(gBtnMinimize.x, gBtnMinimize.y,
           gBtnMinimize.x+gBtnMinimize.w, gBtnMinimize.y+gBtnMinimize.h, DashA(0x5000DCFF), 1);
   DTextC(gBtnMinimize.x, gBtnMinimize.y+2, 14, gDashMinimized ? "▲" : "▼", ARGB_CYAN_INFO, 6);

   // ── ROW 2: Mode badge | Symbol | Regime badge ────────────────────
   string mLbl;
   uint   mBg, mClr;
   if(gBotMode==BOT_MODE_HFT)
      { mLbl="  HFT MODE  "; mBg=0xE0004020; mClr=ARGB_CYAN_INFO; }
   else if(gBotMode==BOT_MODE_SCALPING)
      { mLbl="  SCALP  ";    mBg=0xE0702808; mClr=ARGB_AMBER_WARN; }
   else
      { mLbl="  MODERATE  "; mBg=0xE0080820; mClr=ARGB_PURPLE_ACC; }

   gCanvas.FontSet(DASH_FONT_MONO, DASH_FSM, 0);
   gCanvas.TextSize(mLbl, tw, th);
   int mbx = titleX;
   DFill  (mbx, cy+30, mbx+tw+2, cy+30+th+6, DashA(mBg));
   DBorder(mbx, cy+30, mbx+tw+2, cy+30+th+6, DashA(mClr & 0x50FFFFFF), 1);
   gCanvas.Line(mbx+1, cy+31, mbx+tw, cy+31, DashA(0x15FFFFFF));
   DText(mbx+1, cy+32, mLbl, mClr, DASH_FSM);

   // Symbol — centered in full width
   gCanvas.FontSet(DASH_FONT_TITLE, DASH_FLG, 0);
   int sw=0,sh=0; gCanvas.TextSize(gSymbol, sw, sh);
   DText(x + (w-sw)/2, cy+31, gSymbol, ARGB_TEXT_PRI, DASH_FLG, DASH_FONT_TITLE);

   // Regime badge (right-aligned row 2)
   ENUM_MARKET_REGIME reg = gRegime.regime;
   uint rC = (reg==REGIME_QUIET)?ARGB_CYAN_INFO : (reg==REGIME_NORMAL)?ARGB_GREEN_NEON :
             (reg==REGIME_EXPLOSIVE)?ARGB_AMBER_WARN : ARGB_RED_NEON;
   string rS = RegimeToString(reg);
   gCanvas.FontSet(DASH_FONT_MONO, DASH_FSM, 0);
   gCanvas.TextSize(rS, tw, th);
   int rbx = x+w-tw-22;
   DFill  (rbx, cy+29, rbx+tw+16, cy+29+th+8, DashA(rC & 0x18FFFFFF));
   DBorder(rbx, cy+29, rbx+tw+16, cy+29+th+8, DashA(rC & 0x80FFFFFF), 1);
   DTextC(rbx, cy+32, tw+16, rS, rC, DASH_FSM);
   DDot(x+w-5, cy+35, 4, rC);

   // ── ROW 3: Divider + time strip ─────────────────────────────────
   DHLine(x+8, x+w-8, cy+57, DashA(0x2800DCFF));

   datetime now   = TimeLocal();
   int      upSec = (int)(now - gInitTime);
   string   tStr  = TimeToString(now, TIME_MINUTES|TIME_SECONDS);
   string   upStr = StringFormat("▲%dh%02dm", upSec/3600, (upSec%3600)/60);
   DText(x+8,  cy+63, tStr,  ARGB_CYAN_INFO, DASH_FMD);
   DText(x+74, cy+64, upStr, ARGB_TEXT_DIM,  DASH_FSM);
   DTextR(x+4, cy+64, w-12, GetVersionString(), ARGB_TEXT_DIM, DASH_FSM);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.8  PANEL 2 — ACCOUNT STATUS
//--------------------------------------------------------------------
void PanelAccount(int x, int &cy, int w)
{
   int pH = 168;   // account + sparkline — enlarged for font scale
   DPanel(x, cy, w, pH);

   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ml   = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double mg   = AccountInfoDouble(ACCOUNT_MARGIN);
   double fp   = eq - bal;
   double dd   = SafeDiv(bal - eq, bal) * 100.0;
   uint   eqC  = (eq >= bal) ? ARGB_GREEN_NEON : ARGB_RED_NEON;
   uint   fpC  = (fp >= 0)   ? ARGB_GREEN_NEON : ARGB_RED_NEON;
   uint   dpC  = (gDailyClosedPnL >= 0) ? ARGB_GREEN_NEON : ARGB_RED_NEON;
   uint   ddC  = (dd < 5) ? ARGB_GREEN_NEON : (dd < 10) ? ARGB_AMBER_WARN : ARGB_RED_NEON;
   uint   mlC  = (mg==0||ml>200) ? ARGB_GREEN_NEON : (ml>100) ? ARGB_AMBER_WARN : ARGB_RED_NEON;

   // ── Header row ───────────────────────────────────────────────────
   DText(x+8, cy+6, "ACCOUNT", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);
   // Float P&L badge (right-aligned)
   string fpBadge = (fp>=0?"+":"")+DoubleToString(fp,2)+" USD";
   DFill  (x+w-116, cy+4, x+w-5, cy+20, fp>=0 ? 0x40004020 : 0x40300010);
   DBorder(x+w-116, cy+4, x+w-5, cy+20, fpC & 0x60FFFFFF, 1);
   DTextC(x+w-116, cy+5, 111, fpBadge, fpC, DASH_FSM);
   DHLine(x+4, x+w-4, cy+22, 0x30608090);

   // ── Row 1–3: 2-column layout, 20px per row (matches DASH_FMD=11) ─
   int lx=x+8, rx=x+w/2+6, ry1=cy+26, ry2=cy+48, ry3=cy+70;
   int lv=x+100, rv=x+w/2+106;

   DText(lx, ry1, "Balance",  ARGB_TEXT_DIM, DASH_FSM);
   DText(lv, ry1, "$"+DoubleToString(bal, 2), ARGB_TEXT_PRI, DASH_FMD);
   DText(rx, ry1, "Equity",   ARGB_TEXT_DIM, DASH_FSM);
   DText(rv, ry1, "$"+DoubleToString(eq,  2), eqC, DASH_FMD);

   DText(lx, ry2, "Free Mrg", ARGB_TEXT_DIM, DASH_FSM);
   DText(lv, ry2, "$"+DoubleToString(fm, 2), ARGB_TEXT_SEC, DASH_FMD);
   DText(rx, ry2, "Day P&L",  ARGB_TEXT_DIM, DASH_FSM);
   DText(rv, ry2, (gDailyClosedPnL>=0?"+":"")+DoubleToString(gDailyClosedPnL,2), dpC, DASH_FMD);

   string mlS = (mg==0) ? "N/A" : DoubleToString(ml,1)+"%";
   DText(lx, ry3, "Mrg Lvl",  ARGB_TEXT_DIM, DASH_FSM);
   DText(lv, ry3, mlS, mlC, DASH_FMD);
   DText(rx, ry3, "Drawdown", ARGB_TEXT_DIM, DASH_FSM);
   DText(rv, ry3, DoubleToString(dd,2)+"%", ddC, DASH_FMD);

   // ── Progress bars ────────────────────────────────────────────────
   int barX = x+8, barW = (w-24)/2;
   DText(barX, cy+90, "DD", ARGB_TEXT_DIM, DASH_FSM);
   DBar(barX+24, cy+92, barW-30, 9, MathMin(dd/20.0,1.0), ddC);
   DText(barX+barW-2, cy+90, DoubleToString(dd,1)+"%", ARGB_TEXT_DIM, DASH_FSM);
   int rbX = x + w/2 + 4;
   double eqN = (bal>0) ? MathMin(eq/bal, 1.10)/1.10 : 0.5;
   DText(rbX, cy+90, "EQ", ARGB_TEXT_DIM, DASH_FSM);
   DBar(rbX+24, cy+92, barW-30, 9, eqN, eqC);
   DText(rbX+barW-2, cy+90, DoubleToString(eqN*110.0,1)+"%", ARGB_TEXT_DIM, DASH_FSM);

   // ── Equity Sparkline ─────────────────────────────────────────────
   DHLine(x+4, x+w-4, cy+108, 0x30608090);
   DText(x+8, cy+113, "Equity Trend", ARGB_TEXT_DIM, DASH_FSM);
   DSparkline(x+108, cy+109, w-120, 34, bal);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.9  PANEL 3 — SAFETY VAULT STATUS
//--------------------------------------------------------------------
void PanelSafety(int x, int &cy, int w)
{
   bool anyLk = (gSafety.lockEquityFloor  || gSafety.lockDailyLoss     ||
                 gSafety.lockGlobalDD     || gSafety.lockManualPause    ||
                 gSafety.lockMacroDivergence || gSafety.lockSpread      ||
                 gSafety.lockStaleData    || gSafety.lockSpike          ||
                 gSafety.lockNews);

   int pH = 190;
   DPanel(x, cy, w, pH, anyLk, false);

   // ── Header ───────────────────────────────────────────────────────
   DText(x+6, cy+5, "SAFETY VAULT", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);

   // Master status badge
   string mStr = anyLk ? "! LOCKED" : "+ ALL CLEAR";
   uint   mClr = anyLk ? ARGB_RED_NEON : ARGB_GREEN_NEON;
   int    mbw  = anyLk ? 80 : 96;
   DFill  (x+w-mbw-6, cy+3, x+w-4, cy+19, anyLk ? 0xD0400010 : 0xD0004020);
   DBorder(x+w-mbw-6, cy+3, x+w-4, cy+19, mClr & 0x80FFFFFF, 1);
   DTextC(x+w-mbw-6, cy+4, mbw+2, mStr, mClr, DASH_FSM);
   DHLine(x+4, x+w-4, cy+22, 0x30608090);

   // ── 9 lock pills — 3 columns × 3 rows ───────────────────────────
   // Each pill gets a colored background when ACTIVE (much clearer visually)
   struct LDef { string n; bool v; };
   LDef lks[9] = {
      {"EQ FLOOR",  gSafety.lockEquityFloor},
      {"DAILY LOSS",gSafety.lockDailyLoss},
      {"GLOBAL DD", gSafety.lockGlobalDD},
      {"MANUAL",    gSafety.lockManualPause},
      {"MACRO DIV", gSafety.lockMacroDivergence},
      {"SPREAD",    gSafety.lockSpread},
      {"STALE DATA",gSafety.lockStaleData},
      {"SPIKE",     gSafety.lockSpike},
      {"NEWS",      gSafety.lockNews}
   };

   int pillW = (w-18) / 3;
   int pillH = 26;              // enlarged for DASH_FSM=9
   int startY = cy+26;

   for(int i=0; i<9; i++)
   {
      int col = i % 3, row = i / 3;
      int px  = x + 5 + col * (pillW + 4);
      int py  = startY + row * (pillH + 4);

      // Pill background — red fill when LOCKED, faint when CLEAR
      uint pillBg  = lks[i].v ? ARGB_BG_LOCK_ON : ARGB_BG_LOCK_OFF;
      uint pillBdr = lks[i].v ? (ARGB_RED_NEON & 0x70FFFFFF) : 0x20405060;
      uint dotClr  = lks[i].v ? ARGB_RED_NEON   : ARGB_GREEN_NEON;
      uint txtClr  = lks[i].v ? ARGB_AMBER_WARN : ARGB_TEXT_DIM;

      DFill  (px, py, px+pillW, py+pillH, pillBg);
      DBorder(px, py, px+pillW, py+pillH, pillBdr, 1);

      DDot(px+8,  py+13, 4, dotClr);
      DText(px+18, py+8, lks[i].n, txtClr, DASH_FSM);
   }

   // ── DD recovery bar + hysteresis ─────────────────────────────────
   DHLine(x+4, x+w-4, cy+pH-30, 0x30608090);
   double hystN = (gSafety.globalDDHysteresisPct > DBL_EPSILON) ?
                  MathMin(gSafety.globalDDPct / gSafety.globalDDHysteresisPct, 1.0) : 1.0;
   double recov = 1.0 - hystN;
   uint   recC  = recov > 0.8 ? ARGB_GREEN_NEON : recov > 0.4 ? ARGB_CYAN_INFO : ARGB_AMBER_WARN;
   DText(x+6, cy+pH-24, "DD Recovery:", ARGB_TEXT_DIM, DASH_FSM);
   DBar(x+106, cy+pH-22, w-120, 11, recov, recC);
   DTextR(x+4, cy+pH-23, w-8, DoubleToString(recov*100.0,1)+"%", recC, DASH_FSM);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.10  PANEL 4 — ACTIVE TRADES
//--------------------------------------------------------------------
void PanelTrades(int x, int &cy, int w)
{
   int cnt=0; int tidx[20];
   for(int i=0;i<100&&cnt<20;i++) if(gRec[i].active){tidx[cnt]=i;cnt++;}

   int vis   = MathMin(cnt, 6);
   int rowH  = 36;              // enlarged row for DASH_FMD=11
   int pH    = 36 + vis*rowH + (cnt>6 ? 16:0);
   if(pH < 58) pH = 58;
   DPanel(x, cy, w, pH);

   DText(x+6, cy+5, StringFormat("ACTIVE TRADES (%d)", cnt), ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);
   DHLine(x+4, x+w-4, cy+20, 0x30608090);

   if(cnt == 0)
   {
      DTextC(x, cy+30, w, "No open positions", ARGB_TEXT_DIM, DASH_FMD);
      cy += pH + DASH_PANEL_GAP;
      return;
   }

   // Column headers — scaled for w=660
   int hy=cy+23;
   DText(x+6,   hy, "TKT",    ARGB_TEXT_DIM,DASH_FSM);
   DText(x+72,  hy, "SYMBOL", ARGB_TEXT_DIM,DASH_FSM);
   DText(x+180, hy, "D  LOT", ARGB_TEXT_DIM,DASH_FSM);
   DText(x+268, hy, "P&L",    ARGB_TEXT_DIM,DASH_FSM);
   DText(x+348, hy, "SL-PTS", ARGB_TEXT_DIM,DASH_FSM);
   DText(x+440, hy, "FLAGS",  ARGB_TEXT_DIM,DASH_FSM);
   DHLine(x+4, x+w-4, hy+14, 0x20406080);

   int ry=hy+16;
   for(int ri=0;ri<vis;ri++)
   {
      int i=tidx[ri];
      // direct gRec[i] access — no struct refs in MQL5

      if(ri%2==1) DFill(x+2,ry-2,x+w-2,ry+rowH-2, 0x18304050);

      double pnl=0;
      if(PositionSelectByTicket(gRec[i].ticket)) pnl=PositionGetDouble(POSITION_PROFIT);
      double price=0;
      if(PositionSelectByTicket(gRec[i].ticket)) price=PositionGetDouble(POSITION_PRICE_CURRENT);
      double slPts=SafeDiv(MathAbs(price-gRec[i].stopLoss),gPoint);

      bool   buy = (gRec[i].posType==ORDER_TYPE_BUY);
      uint   dC  = buy ? ARGB_GREEN_NEON : ARGB_RED_NEON;
      uint   pC  = (pnl>=0) ? ARGB_GREEN_NEON : ARGB_RED_NEON;
      string pS  = (pnl>=0?"+":"")+DoubleToString(pnl,2);

      DText(x+6,   ry, IntegerToString(gRec[i].ticket),           ARGB_TEXT_SEC,DASH_FSM);
      DText(x+72,  ry, gRec[i].symbol,                            ARGB_TEXT_PRI,DASH_FMD);
      DText(x+180, ry, buy?"BUY":"SEL",                     dC,DASH_FMD);
      DText(x+222, ry, DoubleToString(gRec[i].initialVolume,2),   ARGB_TEXT_SEC,DASH_FSM);
      DText(x+268, ry, pS,                                  pC,DASH_FMD);
      DText(x+348, ry, DoubleToString(slPts,1)+"p",         ARGB_TEXT_DIM,DASH_FSM);

      // Status flags
      string fl=""; uint flC=ARGB_TEXT_DIM;
      if(gRec[i].breakEvenSet){fl+="BE ";  flC=ARGB_CYAN_INFO;}
      if(gRec[i].tp1Hit)      {fl+="T1 ";}
      if(gRec[i].tp2Hit)      {fl+="T2 ";}
      if(gRec[i].tslActive)   {fl+="TSL ";}
      if(gRec[i].exhaustionHit){fl+="EX ";}
      DText(x+440, ry, fl, flC, DASH_FSM);

      // Mode tag (SC=scalp, HF=HFT, MD=moderate)
      string mt = (gRec[i].isScalpMode && gBotMode==BOT_MODE_HFT) ? "HF" :
                  gRec[i].isScalpMode ? "SC" : "MD";
      uint   mc = (gBotMode==BOT_MODE_HFT&&gRec[i].isScalpMode) ? ARGB_CYAN_INFO :
                  gRec[i].isScalpMode ? ARGB_AMBER_WARN : ARGB_PURPLE_ACC;
      DText(x+w-28, ry, mt, mc, DASH_FSM);

      ry+=rowH;
   }

   if(cnt>6)
      DText(x+6, ry, StringFormat("...+%d more not shown",cnt-6), ARGB_TEXT_DIM, DASH_FSM);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.11  PANEL 5 — PERFORMANCE METRICS
//--------------------------------------------------------------------
void PanelPerformance(int x, int &cy, int w)
{
   int pH = 140;
   DPanel(x, cy, w, pH);
   DText(x+6, cy+5, "PERFORMANCE", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);
   DHLine(x+4, x+w-4, cy+20, 0x30608090);

   double wr  = (gPerf.totalTrades>0) ? SafeDiv((double)gPerf.winTrades,(double)gPerf.totalTrades)*100.0 : 0;
   double pf  = (MathAbs(gPerf.totalLoss)>DBL_EPSILON) ? SafeDiv(gPerf.totalProfit,MathAbs(gPerf.totalLoss)) : 0;
   double aw  = (gPerf.winTrades >0) ? SafeDiv(gPerf.totalProfit, (double)gPerf.winTrades)  : 0;
   double al  = (gPerf.lossTrades>0) ? SafeDiv(MathAbs(gPerf.totalLoss),(double)gPerf.lossTrades) : 0;

   uint wrC = (wr>=60) ? ARGB_GREEN_NEON : (wr>=45) ? ARGB_AMBER_WARN : ARGB_RED_NEON;
   uint pfC = (pf>=1.5) ? ARGB_GREEN_NEON : (pf>=1.0) ? ARGB_AMBER_WARN : ARGB_RED_NEON;

   int mid = x + w/2;
   int r1=cy+26, r2=cy+48, r3=cy+70, r4=cy+92;   // 22px row spacing for DASH_FMD=11

   // ── Left column ──────────────────────────────────────────────────
   DText(x+6, r1, "Trades:",  ARGB_TEXT_DIM, DASH_FSM);
   DText(x+86, r1, IntegerToString(gPerf.totalTrades), ARGB_TEXT_PRI, DASH_FMD);
   DText(x+6, r2, "W / L:",   ARGB_TEXT_DIM, DASH_FSM);
   DText(x+86, r2, IntegerToString(gPerf.winTrades)+"/"+IntegerToString(gPerf.lossTrades),
         ARGB_TEXT_PRI, DASH_FMD);
   DText(x+6, r3, "Win %:",   ARGB_TEXT_DIM, DASH_FSM);
   DText(x+86, r3, DoubleToString(wr,1)+"%", wrC, DASH_FMD);
   DText(x+6, r4, "Prof.F:",  ARGB_TEXT_DIM, DASH_FSM);
   DText(x+86, r4, (pf>0) ? DoubleToString(pf,2) : "—", pfC, DASH_FMD);

   // ── Right column ─────────────────────────────────────────────────
   DText(mid+6, r1, "Best:",   ARGB_TEXT_DIM, DASH_FSM);
   DText(mid+72, r1, "$"+DoubleToString(gPerf.bestTrade,  2), ARGB_GREEN_NEON, DASH_FMD);
   DText(mid+6, r2, "Worst:",  ARGB_TEXT_DIM, DASH_FSM);
   DText(mid+72, r2, "$"+DoubleToString(gPerf.worstTrade, 2), ARGB_RED_NEON,   DASH_FMD);
   DText(mid+6, r3, "Avg W:",  ARGB_TEXT_DIM, DASH_FSM);
   DText(mid+72, r3, "$"+DoubleToString(aw, 2), ARGB_GREEN_NEON, DASH_FMD);
   DText(mid+6, r4, "Avg L:",  ARGB_TEXT_DIM, DASH_FSM);
   DText(mid+72, r4, "$"+DoubleToString(al, 2), ARGB_RED_NEON,   DASH_FMD);

   // ── Dual metric bars ─────────────────────────────────────────────
   DHLine(x+4, x+w-4, cy+pH-32, 0x30608090);
   int bw = (w-26)/2, bh = 10;
   // Win-rate bar (left half)
   DText(x+6,   cy+pH-25, "Win%", ARGB_TEXT_DIM, DASH_FSM);
   DBar(x+42,   cy+pH-23, bw-50, bh, wr/100.0, wrC);
   DText(x+42+bw-50+3, cy+pH-24, DoubleToString(wr,0)+"%", wrC, DASH_FSM);
   // Profit factor bar (right half) — capped at 3.0x
   DText(mid+2, cy+pH-25, "PF",  ARGB_TEXT_DIM, DASH_FSM);
   DBar(mid+26, cy+pH-23, bw-34, bh, MathMin(pf/3.0,1.0), pfC);
   DText(mid+26+bw-34+3, cy+pH-24, DoubleToString(pf,2)+"x", pfC, DASH_FSM);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.12  PANEL 6 — MARKET REGIME
//--------------------------------------------------------------------
void PanelRegime(int x, int &cy, int w)
{
   ENUM_MARKET_REGIME reg = gRegime.regime;
   bool isDanger = (reg==REGIME_HOSTILE || reg==REGIME_EXPLOSIVE);
   int  pH = 104;
   DPanel(x, cy, w, pH, isDanger, false);

   // ── Header: label left, big regime badge right ───────────────────
   DText(x+6, cy+5, "MARKET REGIME", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);

   string rs = RegimeToString(reg);
   uint   rc = (reg==REGIME_QUIET)?ARGB_CYAN_INFO : (reg==REGIME_NORMAL)?ARGB_GREEN_NEON :
               (reg==REGIME_EXPLOSIVE)?ARGB_AMBER_WARN : ARGB_RED_NEON;

   // Large regime badge with stronger background fill
   uint bgFill = (reg==REGIME_HOSTILE)   ? 0xD0380010 :
                 (reg==REGIME_EXPLOSIVE) ? 0xD0402800 :
                 (reg==REGIME_QUIET)     ? 0xD0001840 : 0xD0003018;

   int rbw=112, rbh=22;
   DFill  (x+w-rbw-6, cy+3, x+w-4, cy+3+rbh, bgFill);
   DBorder(x+w-rbw-6, cy+3, x+w-4, cy+3+rbh, rc & 0x90FFFFFF, 1);
   // Top gloss
   gCanvas.Line(x+w-rbw-5, cy+4, x+w-5, cy+4, 0x18FFFFFF);
   DTextC(x+w-rbw-6, cy+5, rbw+2, rs, rc, DASH_FLG, DASH_FONT_TITLE);

   DHLine(x+4, x+w-4, cy+28, 0x30608090);

   // ── Metrics row — 4 pairs spaced for w=660 ──────────────────────
   int iy = cy+34;
   int c1=x+6,  c2=x+52,  c3=x+148, c4=x+196;
   int c5=x+298, c6=x+356, c7=x+454, c8=x+508;
   DText(c1,iy,"ATR:",  ARGB_TEXT_DIM,DASH_FSM); DText(c2,iy,DoubleToString(gRegime.atrNow/gPoint,1)+"p",ARGB_TEXT_PRI,DASH_FMD);
   DText(c3,iy,"Avg:",  ARGB_TEXT_DIM,DASH_FSM); DText(c4,iy,DoubleToString(gRegime.atrAvg/gPoint,1)+"p",ARGB_TEXT_SEC,DASH_FMD);
   DText(c5,iy,"Ratio:",ARGB_TEXT_DIM,DASH_FSM); DText(c6,iy,DoubleToString(gRegimeState.atrRatio,3),rc,DASH_FMD);
   DText(c7,iy,"LotX:", ARGB_TEXT_DIM,DASH_FSM); DText(c8,iy,DoubleToString(RegimeLotMultiplier(),2)+"x",rc,DASH_FMD);

   // ── ATR ratio bar with labeled zone markers ──────────────────────
   int bx=x+6, bw=w-14, by=cy+pH-20;
   DBar(bx, by, bw, 12, MathMin(gRegimeState.atrRatio/2.0, 1.0), rc);
   int qP=(int)(InpQuietATRRatioMax     / 2.0 * bw);
   int eP=(int)(InpExplosiveATRRatioMin / 2.0 * bw);
   // Zone boundary markers
   for(int yi=by; yi<=by+12; yi++)
   {
      gCanvas.PixelSet(bx+qP, yi, 0xC040A0FF);   // QUIET boundary — blue
      gCanvas.PixelSet(bx+eP, yi, 0xC0FF8020);   // EXPLOSIVE boundary — orange
   }

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.13  PANEL 7 — SIGNAL SCORE BREAKDOWN
//--------------------------------------------------------------------
void PanelSignalScore(int x, int &cy, int w)
{
   int pH = 124;
   DPanel(x, cy, w, pH);
   DText(x+6, cy+5, "SIGNAL SCORE", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);

   int  minS = (gBotMode==BOT_MODE_HFT)     ? InpHFTMinScore    :
               (gBotMode==BOT_MODE_SCALPING) ? InpScalpMinScore  : InpModerateMinScore;
   bool pass = (gLastScore >= minS);
   uint sC   = pass ? ARGB_GREEN_NEON : ARGB_RED_NEON;

   // Score badge: top-right
   DFill(x+w-102, cy+3, x+w-4, cy+21, pass ? 0x30004020 : 0x30400010);
   DBorder(x+w-102, cy+3, x+w-4, cy+21, sC & 0x80FFFFFF, 1);
   DTextC(x+w-102, cy+4, 98, IntegerToString(gLastScore)+"/100", sC, DASH_FMD);
   DText(x+w-100, cy+16, (pass?"PASS":"FAIL")+"  min:"+IntegerToString(minS), sC, DASH_FSM);

   DHLine(x+4, x+w-4, cy+24, 0x30608090);

   // 7 component bars: EMA RSI MACD BB STOCH VOL REGIME
   string cLbls[7] = {"EMA","RSI","MACD","BB","STCH","VOL","REG"};
   int    cMax[7]  = {20, 15, 15, 10, 10, 10, 5};

   int nBars = 7;
   int barW  = (w-20) / nBars;
   int barH  = 44;              // enlarged for readability
   int barX  = x+8;
   int barY  = cy+30;

   for(int ci=0; ci<nBars; ci++)
   {
      int    cv  = gScoreComp[ci];
      double pct = (cMax[ci]>0) ? MathMax(-1.0, MathMin(1.0, (double)cv/cMax[ci])) : 0;
      uint   bc  = (cv>0) ? ARGB_GREEN_NEON : (cv<0) ? ARGB_RED_NEON : ARGB_TEXT_DIM;
      DVBar(barX, barY, barW-2, barH, pct);
      DTextC(barX, barY+barH+3, barW-2, cLbls[ci], ARGB_TEXT_DIM, DASH_FSM);
      DTextC(barX, barY-14, barW-2, (cv>0?"+":"")+IntegerToString(cv), bc, DASH_FSM);
      barX += barW;
   }

   // Total score bar at bottom
   DBar(x+6, cy+pH-14, w-14, 10, MathMax(0.0,(double)gLastScore/100.0), sC);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.14  PANEL 8 — PORTFOLIO WATCHLIST
//--------------------------------------------------------------------
void PanelPortfolio(int x, int &cy, int w)
{
   if(!InpUsePortfolioWatchlist)
   {
      int pH=22; DPanel(x,cy,w,pH);
      DText(x+6, cy+5, "PORTFOLIO: disabled (InpUsePortfolioWatchlist=false)",
            ARGB_TEXT_DIM, DASH_FSM);
      cy += pH + DASH_PANEL_GAP; return;
   }

   int showN = MathMin(g_WatchCount, 5);
   int pH    = 40 + showN*24 + 20;   // 24px rows for DASH_FSM=9
   DPanel(x, cy, w, pH);

   string scanAge="—";
   if(gPortLastScanTime>0)
   {
      int sc=(int)(TimeLocal()-gPortLastScanTime);
      scanAge=(sc<60)?IntegerToString(sc)+"s":(sc<3600)?IntegerToString(sc/60)+"m":"stale";
   }

   DText(x+6, cy+5, StringFormat("PORTFOLIO  %d syms", g_WatchCount), ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);
   DTextR(x, cy+6, w-6, "scan:"+scanAge, ARGB_TEXT_DIM, DASH_FSM);
   DHLine(x+4, x+w-4, cy+20, 0x30608090);

   // Column headers — scaled to w=660
   int hy=cy+24;
   DText(x+6,   hy,"#",       ARGB_TEXT_DIM,DASH_FSM);
   DText(x+26,  hy,"SYMBOL",  ARGB_TEXT_DIM,DASH_FSM);
   DText(x+160, hy,"SCORE",   ARGB_TEXT_DIM,DASH_FSM);
   DText(x+280, hy,"BIAS",    ARGB_TEXT_DIM,DASH_FSM);
   DText(x+380, hy,"TRADE?",  ARGB_TEXT_DIM,DASH_FSM);

   int ry=hy+16;
   for(int pi=0;pi<showN;pi++)
   {
      // direct gPortCand[pi] access below — no struct refs in MQL5
      bool isMe  = (gPortCand[pi].symbol == gSymbol);
      bool trade = (gPortCand[pi].rank <= InpPortfolioMaxTradableRanks);

      if(pi%2==0) DFill(x+2,ry-2,x+w-2,ry+21,0x18304050);

      uint rC=(gPortCand[pi].rank==1)?ARGB_AMBER_WARN:(gPortCand[pi].rank==2)?ARGB_TEXT_SEC:
              (gPortCand[pi].rank==3)?0xFFA09060:ARGB_TEXT_DIM;
      DText(x+6,  ry, "#"+IntegerToString(gPortCand[pi].rank), rC, DASH_FSM);
      DText(x+26, ry, gPortCand[pi].symbol+(isMe?"<":""),
            isMe ? ARGB_CYAN_INFO : ARGB_TEXT_PRI, DASH_FMD);

      double sN=MathMin((double)gPortCand[pi].finalScore/85.0,1.0);
      uint   sC=(gPortCand[pi].finalScore>=60)?ARGB_GREEN_NEON:(gPortCand[pi].finalScore>=40)?ARGB_AMBER_WARN:ARGB_RED_NEON;
      DBar(x+160, ry+5, 58, 8, sN, sC);
      DText(x+224, ry, IntegerToString(gPortCand[pi].finalScore), sC, DASH_FSM);

      uint   bC=(gPortCand[pi].bias==BIAS_BULL)?ARGB_GREEN_NEON:(gPortCand[pi].bias==BIAS_BEAR)?ARGB_RED_NEON:ARGB_TEXT_DIM;
      string bS=(gPortCand[pi].bias==BIAS_BULL)?"^BULL":(gPortCand[pi].bias==BIAS_BEAR)?"vBEAR":"-FLAT";
      DText(x+280, ry, bS, bC, DASH_FMD);
      DText(x+380, ry, trade?"YES":"no", trade?ARGB_GREEN_NEON:ARGB_TEXT_DIM, DASH_FMD);

      ry+=24;
   }

   DHLine(x+4, x+w-4, ry, 0x30608090);
   int myR=GetChartSymbolRank();
   DText(x+6, ry+4, gSymbol+" rank: "+(myR>0?"#"+IntegerToString(myR):"not ranked"),
         ARGB_TEXT_DIM, DASH_FSM);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.15  PANEL 9 — FILTERS: NEWS / SPIKE / VOLUME MOMENTUM
//--------------------------------------------------------------------
void PanelNewsSpike(int x, int &cy, int w)
{
   bool anyAlert = gSpike.spikeActive || gNews.active || gImpliedNewsActive;
   int  pH = 102;              // enlarged for DASH_FSM=9
   DPanel(x, cy, w, pH, anyAlert, false);

   DText(x+6, cy+5, "FILTERS & EVENTS", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);
   DHLine(x+4, x+w-4, cy+20, 0x30608090);

   int c1=x+6, c2=x+w/3, c3=x+2*w/3;
   int ry=cy+26;

   // Spike
   bool spk=gSpike.spikeActive;
   DText(c1,ry,"SPIKE",ARGB_TEXT_DIM,DASH_FMD,DASH_FONT_TITLE);
   DDot(c1+54,ry+8, 6, spk?ARGB_RED_NEON:ARGB_GREEN_NEON);
   DText(c1,ry+17,spk?"ACTIVE":"clear",spk?ARGB_RED_NEON:ARGB_GREEN_NEON,DASH_FSM);
   if(spk && gSpike.spikeRange>0)
      DText(c1,ry+31,DoubleToString(gSpike.spikeRange/gPoint,1)+"p",ARGB_AMBER_WARN,DASH_FSM);

   // News
   bool nws=gNews.active;
   DText(c2,ry,"NEWS",ARGB_TEXT_DIM,DASH_FMD,DASH_FONT_TITLE);
   DDot(c2+44,ry+8, 6, nws?ARGB_AMBER_WARN:ARGB_GREEN_NEON);
   DText(c2,ry+17,nws?"BLOCKED":"clear",nws?ARGB_AMBER_WARN:ARGB_GREEN_NEON,DASH_FSM);
   if(nws) { int mLeft=(int)MathMax(0.0,(gNews.windowEnd - TimeCurrent())/60.0);
             DText(c2,ry+31,IntegerToString(mLeft)+"m left",ARGB_TEXT_DIM,DASH_FSM); }

   // Volume momentum
   bool vmB=gVolMom.bullConfirmed, vmS=gVolMom.bearConfirmed;
   uint vmC=vmB?ARGB_GREEN_NEON:vmS?ARGB_RED_NEON:ARGB_TEXT_DIM;
   DText(c3,ry,"VOL MOM",ARGB_TEXT_DIM,DASH_FMD,DASH_FONT_TITLE);
   DDot(c3+70,ry+8, 6, vmC);
   DText(c3,ry+17,vmB?"BULL":vmS?"BEAR":"NEUT",vmC,DASH_FSM);
   DText(c3,ry+31,"x"+DoubleToString(gVolMom.ratio,2),ARGB_TEXT_DIM,DASH_FSM);

   // Bottom strip: implied news + blackout
   DHLine(x+4, x+w-4, cy+pH-24, 0x30608090);
   bool blk=IsInBlackoutWindow();
   DText(x+6,   cy+pH-17,"Implied News:",ARGB_TEXT_DIM,DASH_FSM);
   DText(x+106, cy+pH-17,gImpliedNewsActive?"ACTIVE":"clear",
         gImpliedNewsActive?ARGB_AMBER_WARN:ARGB_GREEN_NEON,DASH_FMD);
   DText(x+w/2, cy+pH-17,"Blackout:",ARGB_TEXT_DIM,DASH_FSM);
   DText(x+w/2+72,cy+pH-17,blk?"YES":"no",blk?ARGB_RED_NEON:ARGB_GREEN_NEON,DASH_FMD);

   cy += pH + DASH_PANEL_GAP;
}

//--------------------------------------------------------------------
// 14.16  PANEL 10 — CONTROL BUTTONS  (Full v6 toggle grid)
//         Row A: PAUSE/RESUME | MODE SWITCH (2 wide action buttons)
//         Row B: BUY ON/OFF | SELL ON/OFF | ONE-SYMBOL (direction)
//         Row C: 12 engine toggles (4 × 3 grid)
//         Row D: 4 notification toggles
//         Row E: EMERGENCY CLOSE ALL (full-width panic, 2-click)
//--------------------------------------------------------------------
void PanelControls(int x, int &cy, int w)
{
   if(!InpDashShowControls) { cy += DASH_PANEL_GAP; return; }

   bool paused = gSafety.lockManualPause;
   int  gap    = 5;
   int  pH     = 290 + (paused ? 16 : 0);   // full v6 grid height — enlarged for DASH_FSM=9
   DPanel(x, cy, w, pH);

   DText(x+6, cy+5, "CONTROLS", ARGB_TEXT_DIM, DASH_FSM, DASH_FONT_TITLE);

   // PAUSED banner strip
   if(paused)
   {
      DFill(x+80, cy+2, x+w-4, cy+15, 0xD0380010);
      DBorder(x+80, cy+2, x+w-4, cy+15, 0xA0FF3050, 1);
      DTextC(x+80, cy+3, w-84, "⏸  BOT PAUSED — ENTRIES BLOCKED", 0xFFFF6070, DASH_FSM);
   }

   DHLine(x+4, x+w-4, cy+17, DashA(0x2000DCFF));

   int curY = cy + 22;
   int btnH = 28;              // larger button height for DASH_FSM=9
   int halfW = (w - gap*3) / 2;

   // ── ROW A: PAUSE | MODE SWITCH ───────────────────────────────────
   string pauseLbl = paused ? "▶ RESUME TRADING" : "⏸ PAUSE BOT";
   uint   pauseBg  = paused ? ARGB_BTN_SAFE : ARGB_BTN_NEUTRAL;
   uint   pauseTC  = paused ? ARGB_GREEN_NEON : ARGB_TEXT_PRI;
   gBtnPause = DBtn(x+gap, curY, halfW, btnH, pauseLbl, DashA(pauseBg), pauseTC);

   string modeLbl;
   if(gBotMode==BOT_MODE_HFT)      modeLbl = "⇌ → SCALP";
   else if(gBotMode==BOT_MODE_SCALPING) modeLbl = "⇌ → MOD";
   else                             modeLbl = "⇌ → SCALP";
   gBtnMode = DBtn(x+gap*2+halfW, curY, halfW, btnH, modeLbl, DashA(ARGB_BTN_NEUTRAL));

   curY += btnH + gap;

   // ── ROW B: Direction & exposure toggles ─────────────────────────
   // v6.3d: use gRtAllowBuy/Sell (runtime globals) so dashboard buttons are INTERACTIVE.
   // Previously used InpAllowBuy/Sell (frozen inputs) — buttons were display-only.
   int   thirdW = (w - gap*4) / 3;
   bool  buyOn  = gRtAllowBuy;
   bool  sellOn = gRtAllowSell;
   bool  oneExp = InpOneExposurePerSymbol;

   uint buyBg  = buyOn  ? DashA(0xD0003A1A) : DashA(ARGB_BTN_INACTIVE);
   uint sellBg = sellOn ? DashA(0xD03A0010) : DashA(ARGB_BTN_INACTIVE);
   uint oneBg  = oneExp ? DashA(0xC0001830) : DashA(ARGB_BTN_INACTIVE);

   gBtnBuy  = DBtn(x+gap,            curY, thirdW, btnH, buyOn  ?"BUY: ON":"BUY: OFF",   buyBg,  buyOn  ?ARGB_GREEN_NEON:ARGB_TEXT_DIM);
   gBtnSell = DBtn(x+gap*2+thirdW,   curY, thirdW, btnH, sellOn ?"SELL: ON":"SELL: OFF",  sellBg, sellOn ?ARGB_RED_NEON  :ARGB_TEXT_DIM);
   DBtn(x+gap*3+thirdW*2, curY, thirdW, btnH, oneExp ?"1/SYM" :"MULTI",    oneBg,  oneExp ?ARGB_CYAN_INFO :ARGB_TEXT_DIM);

   curY += btnH + gap + 2;

   // ── ROW C: 12 engine/filter toggles — 4 columns × 3 rows ─────────
   DHLine(x+4, x+w-4, curY-2, DashA(0x1800DCFF));
   DText(x+6, curY, "ENGINES", ARGB_TEXT_DIM, 6, DASH_FONT_TITLE);
   curY += 10;

   struct EngTgl { string n; bool v; };
   EngTgl etgls[12] = {
      {"NEWS",      InpUseNewsFilter},
      {"SPIKE",     InpUseSpikeDetection},
      {"VOL MOM",   InpUseVolumeMomentum},
      {"ADX",       InpUseADXFilter},
      {"REGIME",    InpUseRegimeEngine},
      {"SESSION",   InpUseSessionFilter},
      {"EMA",       InpUseEMAFilter},
      {"CANDLES",   InpUseCandlePatterns},
      {"PIVOT",     InpUsePivotEngine},
      {"FIB",       InpUseFibEngine},
      {"CHART PAT", InpUseChartPatterns},
      {"BROKER CHK",InpUseBrokerSanityChecks}
   };

   int colsE = 4;
   int eW    = (w - gap*(colsE+1)) / colsE;
   int eH    = 24;             // enlarged toggle pill height

   for(int ei=0; ei<12; ei++)
   {
      int col = ei % colsE;
      int row = ei / colsE;
      int ex  = x + gap + col*(eW + gap);
      int ey  = curY + row*(eH + 3);
      bool on = etgls[ei].v;
      uint bg = on ? DashA(0xB8000C1E) : DashA(ARGB_BTN_INACTIVE);
      uint tc = on ? ARGB_CYAN_INFO    : ARGB_TEXT_DIM;
      DFill  (ex, ey, ex+eW, ey+eH, bg);
      DBorder(ex, ey, ex+eW, ey+eH, on ? DashA(0x5000DCFF) : DashA(0x20304050), 1);
      DDot(ex+8, ey+12, 4, on ? ARGB_GREEN_NEON : 0xFF203030);
      DText(ex+16, ey+7, etgls[ei].n, tc, DASH_FSM);
   }

   curY += 3*(eH+3) + gap + 2;

   // ── ROW D: 4 notification toggles ────────────────────────────────
   DHLine(x+4, x+w-4, curY-2, DashA(0x1800DCFF));
   DText(x+6, curY, "NOTIFY", ARGB_TEXT_DIM, 6, DASH_FONT_TITLE);
   curY += 10;

   struct NtfTgl { string n; bool v; };
   NtfTgl ntgls[4] = {
      {"TELEGRAM",  InpUseTelegram},
      {"ENTRIES",   InpNotifyEntries},
      {"EXITS",     InpNotifyExits},
      {"HOURLY",    InpNotifyHourlyPing}
   };

   int nW = (w - gap*5) / 4;
   int nH = 24;                // enlarged notify pill height
   for(int ni=0; ni<4; ni++)
   {
      int nx  = x + gap + ni*(nW + gap);
      bool on = ntgls[ni].v;
      uint bg = on ? DashA(0xB8001020) : DashA(ARGB_BTN_INACTIVE);
      uint tc = on ? ARGB_CYAN_INFO    : ARGB_TEXT_DIM;
      DFill  (nx, curY, nx+nW, curY+nH, bg);
      DBorder(nx, curY, nx+nW, curY+nH, on ? DashA(0x5000DCFF) : DashA(0x20304050), 1);
      DDot(nx+8, curY+12, 4, on ? ARGB_CYAN_INFO : 0xFF203030);
      DText(nx+16, curY+7, ntgls[ni].n, tc, DASH_FSM);
   }

   curY += nH + gap + 2;

   // ── ROW E: PANIC CLOSE ALL (full width, 2-click arm) ─────────────
   DHLine(x+4, x+w-4, curY-1, DashA(0x2000DCFF));
   curY += 3;
   if(gPanicArmed)
   {
      int elapsed = (int)(TimeLocal() - gPanicArmedAt);
      int remain  = MathMax(0, 3 - elapsed);
      string pnkLbl = StringFormat("☠ CONFIRM CLOSE ALL — %ds", remain);
      gBtnPanic = DBtn(x+gap, curY, w-gap*2, btnH, pnkLbl,
                       DashA(0xF0FF1020), 0xFFFFFFFF, true);
   }
   else
   {
      gBtnPanic = DBtn(x+gap, curY, w-gap*2, btnH,
                       "⚠ EMERGENCY CLOSE ALL",
                       DashA(ARGB_BTN_DANGER), 0xFFFF9090);
   }

   cy += pH + DASH_PANEL_GAP;
}

//====================================================================
// 14.17-APEX  APEX ALGORITHMS-STYLE DASHBOARD  (v6.3f)
//   Deep navy background, blue accent, 4-tab navigation,
//   donut charts, equity curve, compact professional layout.
//   Colors: bg=#0D1117  card=#1C2333  accent=#3B82F6
//====================================================================
#define AP_BG           0xFF0D1117
#define AP_CARD         0xFF1C2333
#define AP_CARD2        0xFF0F172A
#define AP_HDR          0xFF111827
#define AP_BLUE         0xFF3B82F6
#define AP_BLUE_DIM     0x403B82F6
#define AP_BLUE_MUTED   0xFF1E3A5F
#define AP_BLUE_BRIGHT  0xFF93C5FD
#define AP_TEXT         0xFFE2E8F0
#define AP_TEXT2        0xFF94A3B8
#define AP_TEXT3        0xFF475569
#define AP_GREEN        0xFF22C55E
#define AP_GREEN_BG     0x2022C55E
#define AP_RED          0xFFEF4444
#define AP_RED_BG       0x20EF4444
#define AP_YELLOW       0xFFEAB308
#define AP_YELLOW_BG    0x20EAB308
#define AP_SEP          0x28607090
// Layout
#define AP_HDR_H        44
#define AP_TAB_H        30
#define AP_CCARD_H      74
#define AP_CTOP         (AP_HDR_H + AP_TAB_H)  // first content y = 74

//--------------------------------------------------------------------
// APEX: Pixel-perfect donut gauge — pct [0,1] clockwise from top
//--------------------------------------------------------------------
void DrawApexDonut(int cx, int cy, int r_out, int r_in,
                   double pct, uint col_fill, uint col_bg)
{
   pct = MathMax(0.0, MathMin(1.0, pct));
   double fill_ang = pct * M_PI * 2.0;
   for(int px = cx-r_out-1; px <= cx+r_out+1; px++)
   for(int py = cy-r_out-1; py <= cy+r_out+1; py++)
   {
      double dx = (double)(px-cx), dy = (double)(py-cy);
      double r  = MathSqrt(dx*dx + dy*dy);
      if(r < (double)r_in || r > (double)r_out) continue;
      double a = MathArctan2(dx, -dy);  // -dy: screen-y is downward; 0=top clockwise
      if(a < 0.0) a += M_PI * 2.0;
      gCanvas.PixelSet(px, py, a <= fill_ang ? col_fill : col_bg);
   }
}

//--------------------------------------------------------------------
// APEX: Card — filled rect with 1px border
//--------------------------------------------------------------------
void DrawApexCard(int x, int y, int w, int h,
                  uint bg=AP_CARD, uint border=0x20607090)
{
   DFill(x, y, x+w, y+h, bg);
   DBorder(x, y, x+w, y+h, border, 1);
}

//--------------------------------------------------------------------
// APEX: Stat card — title / big value / sub-label / optional left bar
//--------------------------------------------------------------------
void DrawApexStatCard(int x, int y, int w, int h,
                      const string title, const string value,
                      const string sub,   uint val_col=AP_TEXT)
{
   DrawApexCard(x, y, w, h, AP_CARD, AP_BLUE_DIM);
   DFill(x, y, x+3, y+h, AP_BLUE);                          // left accent bar
   DText(x+7, y+6,  title, AP_TEXT3, DASH_FSM,  DASH_FONT_TITLE);
   gCanvas.FontSet(DASH_FONT_TITLE, DASH_FXL, FW_BOLD);
   gCanvas.TextOut(x+7, y+20, value, val_col, TA_LEFT|TA_TOP);
   DText(x+7, y+h-15, sub, AP_TEXT3, DASH_FSM-1);
}

//--------------------------------------------------------------------
// APEX: Tab bar — writes click regions into gTabRgn[]
//--------------------------------------------------------------------
void DrawApexTabBar(int y)
{
   // v6.3g: 5 tabs — OVERVIEW | INDICATORS | TRADES | CONFIG | STATS
   static const string TABS[5] = {"OVERVIEW","INDICATORS","TRADES","CONFIG","STATS"};
   DFill(0, y, DASH_W, y+AP_TAB_H, AP_HDR);
   int tw = DASH_W / 5;
   for(int i = 0; i < 5; i++)
   {
      int tx = i * tw;
      bool active = (i == gDashTab);
      uint bg = active ? 0xFF1A2A4A : AP_HDR;
      uint tc = active ? AP_BLUE_BRIGHT : AP_TEXT3;
      if(active) DFill(tx, y, tx+tw, y+AP_TAB_H, bg);
      gCanvas.FontSet(DASH_FONT_TITLE, DASH_FSM, active ? FW_BOLD : FW_NORMAL);
      int sw=0,sh=0; gCanvas.TextSize(TABS[i],sw,sh);
      gCanvas.TextOut(tx+(tw-sw)/2, y+(AP_TAB_H-sh)/2, TABS[i], tc, TA_LEFT|TA_TOP);
      if(active) DFill(tx+4, y+AP_TAB_H-3, tx+tw-4, y+AP_TAB_H, AP_BLUE);
      // Separator between tabs
      if(i < 4) gCanvas.Line(tx+tw, y+4, tx+tw, y+AP_TAB_H-4, AP_SEP);
      gTabRgn[i].x=tx; gTabRgn[i].y=y; gTabRgn[i].w=tw; gTabRgn[i].h=AP_TAB_H; gTabRgn[i].vis=true;
   }
   gCanvas.Line(0, y+AP_TAB_H-1, DASH_W, y+AP_TAB_H-1, AP_SEP);
}

//--------------------------------------------------------------------
// APEX: Equity curve from gEquityHist ring buffer
//--------------------------------------------------------------------
void DrawApexEquityCurve(int x, int y, int w, int h)
{
   DrawApexCard(x, y, w, h, AP_CARD2, 0x10607090);
   int N = (gEquityHistFull >= SPARK_LEN) ? SPARK_LEN : gEquityHistFull;
   if(N < 2) { DText(x+6, y+h/2-5, "Building curve...", AP_TEXT3, DASH_FSM-1); return; }
   double eMin=gEquityHist[0], eMax=gEquityHist[0];
   for(int i=0; i<N; i++) { if(gEquityHist[i]<eMin) eMin=gEquityHist[i]; if(gEquityHist[i]>eMax) eMax=gEquityHist[i]; }
   double range = eMax - eMin; if(range < 0.01) range = 1.0;
   double zero = AccountInfoDouble(ACCOUNT_BALANCE);
   int pad=5, lx=-1, ly=-1;
   for(int i=0; i<N; i++)
   {
      int idx = (gEquityHistFull >= SPARK_LEN) ? (gEquityHistPos + i) % SPARK_LEN : i;
      double eq = gEquityHist[idx];
      int px2 = x+pad+(int)((double)(w-pad*2)*i/(N-1));
      int py2 = y+h-pad-(int)((double)(h-pad*2)*(eq-eMin)/range);
      if(lx >= 0) gCanvas.Line(lx,ly,px2,py2, eq>=zero ? AP_GREEN : AP_RED);
      lx=px2; ly=py2;
   }
   DText(x+pad+1, y+pad,   DoubleToString(eMax,0), AP_TEXT3, 6);
   DText(x+pad+1, y+h-pad-8, DoubleToString(eMin,0), AP_TEXT3, 6);
}

//--------------------------------------------------------------------
// APEX Tab 0: Overview — the main live-trading view
//--------------------------------------------------------------------
void RenderTabOverview()
{
   int PAD=8;
   int y = AP_CTOP;

   // Account data
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dp      = gDailyClosedPnL;
   double floatPL = equity - balance;
   // v6.3g: Use gRt_DailyDDPct (set by ApplySubMode per mode) as per-mode daily DD limit.
   // Also track global drawdown from gSafety high-water mark.
   double ddLim   = (gRt_DailyDDPct > 0.0) ? gRt_DailyDDPct : InpMaxDailyLossPercent;
   double ddUsed  = (balance > 0) ? MathAbs(MathMin(0.0, dp))/balance*100.0 : 0;
   double globalDD = gSafety.globalDDPct;

   // ── 4 Stat cards row ──────────────────────────────────────────
   int cw = (DASH_W - PAD*2 - 9) / 4;
   int cy0 = y + PAD;
   DrawApexStatCard(PAD,       cy0, cw, AP_CCARD_H, "BALANCE",
      "$"+DoubleToString(balance,2), "Account Balance", AP_TEXT);
   uint eqC = (equity >= balance) ? AP_GREEN : AP_RED;
   DrawApexStatCard(PAD+cw+3, cy0, cw, AP_CCARD_H, "EQUITY",
      "$"+DoubleToString(equity,2),
      (floatPL>=0?"+":"")+DoubleToString(floatPL,2)+" float", eqC);
   uint dpC = dp >= 0 ? AP_GREEN : AP_RED;
   DrawApexStatCard(PAD+cw*2+6, cy0, cw, AP_CCARD_H, "DAILY P&&L",
      (dp>=0?"+$":"$")+DoubleToString(MathAbs(dp),2),
      DoubleToString(dp/MathMax(balance,1)*100,2)+"% balance", dpC);
   uint ddC = ddUsed < ddLim*0.5 ? AP_GREEN : ddUsed < ddLim*0.8 ? AP_YELLOW : AP_RED;
   // Show global DD (from high-water mark) vs daily DD
   string ddStr = "D:"+DoubleToString(ddUsed,1)+"% G:"+DoubleToString(globalDD,1)+"%";
   DrawApexStatCard(PAD+cw*3+9, cy0, cw, AP_CCARD_H, "DRAWDOWN",
      ddStr,
      "DLim:"+DoubleToString(ddLim,1)+"% GLim:"+DoubleToString(InpMaxGlobalDrawdownPercent,1)+"%", ddC);
   y += PAD + AP_CCARD_H + 6;

   gCanvas.Line(PAD, y, DASH_W-PAD, y, AP_BLUE_DIM);
   y += 5;

   // ── Score gauge (left) | Win Rate donut (right) ───────────────
   int midW = (DASH_W - PAD*3) / 2;
   int midH = 152;

   // LEFT: Score Arc
   DrawApexCard(PAD, y, midW, midH, AP_CARD, 0x18607090);
   {
      int gx = PAD + 68; int gy = y + midH/2;
      int sc = gLastScore;
      uint sc_col = sc >= 62 ? AP_GREEN : sc >= 40 ? AP_YELLOW : AP_RED;
      DrawApexDonut(gx, gy, 52, 40, (double)sc/93.0, sc_col, 0xFF1E293B);
      // Center value
      gCanvas.FontSet(DASH_FONT_TITLE, 18, FW_BOLD);
      string scStr=IntegerToString(sc); int sw=0,sh=0;
      gCanvas.TextSize(scStr,sw,sh);
      gCanvas.TextOut(gx-sw/2, gy-sh/2, scStr, AP_TEXT, TA_LEFT|TA_TOP);
      gCanvas.FontSet(DASH_FONT_TITLE, DASH_FSM, FW_BOLD);
      string scLbl = sc>=62?"STRONG":sc>=40?"MODERATE":"WEAK";
      gCanvas.TextSize(scLbl,sw,sh);
      gCanvas.TextOut(gx-sw/2, gy+sh/2+3, scLbl, sc_col, TA_LEFT|TA_TOP);
      // Right side info
      int rx = PAD + 132; int ry = y + 10;
      string bias = (gLastBias==BIAS_BULL)?"▲ BULL":(gLastBias==BIAS_BEAR)?"▼ BEAR":"— NEUTRAL";
      uint bc = (gLastBias==BIAS_BULL)?AP_GREEN:(gLastBias==BIAS_BEAR)?AP_RED:AP_TEXT3;
      DFill(rx, ry, rx+midW-134, ry+22, AP_CARD2); DBorder(rx, ry, rx+midW-134, ry+22, bc, 1);
      DTextC(rx, ry+5, midW-134, bias, bc, DASH_FSM, DASH_FONT_TITLE);
      ry += 28;
      string modeTag = (gBotMode==BOT_MODE_HFT)?"HFT":(gBotMode==BOT_MODE_SCALPING)?"SCALP":"MOD";
      DText(rx, ry,    "Mode",    AP_TEXT3, DASH_FSM); DText(rx+50, ry,    modeTag+" / "+SubModeName(), AP_TEXT2, DASH_FSM); ry+=16;
      DText(rx, ry,    "Session", AP_TEXT3, DASH_FSM); DText(rx+50, ry,    GetSessionName(), AP_TEXT2, DASH_FSM); ry+=16;
      DText(rx, ry,    "Regime",  AP_TEXT3, DASH_FSM); DText(rx+50, ry,    RegimeToString(gRegime.regime), AP_TEXT2, DASH_FSM); ry+=16;
      DText(rx, ry,    "Score",   AP_TEXT3, DASH_FSM); DText(rx+50, ry,    IntegerToString(sc)+"/93", sc_col, DASH_FSM); ry+=16;
      double spread = (SymbolInfoDouble(gSymbol,SYMBOL_ASK)-SymbolInfoDouble(gSymbol,SYMBOL_BID))/gPoint;
      DText(rx, ry,    "Spread",  AP_TEXT3, DASH_FSM); DText(rx+50, ry,    DoubleToString(spread,1)+" pts", AP_TEXT2, DASH_FSM);
      DText(PAD+6, y+midH-14, "Signal Score /93", AP_TEXT3, DASH_FSM-1);
   }

   // RIGHT: Win Rate Donut
   DrawApexCard(PAD*2+midW, y, midW, midH, AP_CARD, 0x18607090);
   {
      int dx = PAD*2+midW+68; int dy = y+midH/2;
      double wr = (gPerf.totalTrades>0) ? (gPerf.winTrades*100.0/gPerf.totalTrades) : 0;
      uint wr_col = wr>=60?AP_GREEN:wr>=45?AP_YELLOW:AP_RED;
      DrawApexDonut(dx, dy, 52, 40, wr/100.0, wr_col, 0xFF1E293B);
      gCanvas.FontSet(DASH_FONT_TITLE, 16, FW_BOLD);
      string wrStr = DoubleToString(wr,1)+"%"; int sw=0,sh=0;
      gCanvas.TextSize(wrStr,sw,sh);
      gCanvas.TextOut(dx-sw/2, dy-sh/2, wrStr, AP_TEXT, TA_LEFT|TA_TOP);
      gCanvas.FontSet(DASH_FONT_TITLE, DASH_FSM, FW_BOLD); string wl="WIN RATE";
      gCanvas.TextSize(wl,sw,sh); gCanvas.TextOut(dx-sw/2, dy+sh/2+3, wl, wr_col, TA_LEFT|TA_TOP);
      // Stats column
      int rx = PAD*2+midW+132; int ry = y+10;
      // MQL5: no anonymous-struct arrays, no brace-init — use parallel arrays
      string wlbl[4]; wlbl[0]="WINS"; wlbl[1]="LOSSES"; wlbl[2]="TOTAL"; wlbl[3]="WIN %";
      string wval[4]; wval[0]=IntegerToString(gPerf.winTrades);
                      wval[1]=IntegerToString(gPerf.lossTrades);
                      wval[2]=IntegerToString(gPerf.totalTrades);
                      wval[3]=DoubleToString(wr,1)+"%";
      uint   wcol[4]; wcol[0]=AP_GREEN; wcol[1]=AP_RED; wcol[2]=AP_TEXT2; wcol[3]=wr_col;
      for(int r=0; r<4; r++)
      {
         DrawApexCard(rx, ry, midW-134, 22, AP_CARD2, 0x10607090);
         DText(rx+4, ry+6, wlbl[r], AP_TEXT3, DASH_FSM-1);
         DTextR(rx, ry+6, midW-134-4, wval[r], wcol[r], DASH_FSM, DASH_FONT_TITLE);
         ry += 24;
      }
      // Streak badge
      string stk = (gConsecWins>0)?"+"+IntegerToString(gConsecWins)+"W":(gConsecLosses>0)?"-"+IntegerToString(gConsecLosses)+"L":"—";
      uint sk = (gConsecWins>0)?AP_GREEN:(gConsecLosses>0)?AP_RED:AP_TEXT3;
      DrawApexCard(rx, ry, midW-134, 22, AP_CARD2, 0x10607090);
      DText(rx+4, ry+6, "STREAK", AP_TEXT3, DASH_FSM-1); DTextR(rx, ry+6, midW-134-4, stk, sk, DASH_FSM, DASH_FONT_TITLE);
      DText(PAD*2+midW+6, y+midH-14, "Win Rate  /100%", AP_TEXT3, DASH_FSM-1);
   }
   y += midH + 6;

   // ── BSP pressure bar ─────────────────────────────────────────
   DrawApexCard(PAD, y, DASH_W-PAD*2, 38, AP_CARD2, 0x10607090);
   {
      double buyP;
      string pressLabel;
      if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
      {
         buyP       = gPressEng.GetRatio() * 100.0;   // actual ratio always (0.5 at bar-reset, updates each tick)
         pressLabel = gPressEng.IsValid() ? "LIVE-TICK" : "WARM-UP";
      }
      else
      {
         buyP       = gBSP.buyPct;
         pressLabel = gBSP.label;
      }
      DText(PAD+6, y+4, "PRESSURE — Live Tick  ["+pressLabel+"]", AP_TEXT3, DASH_FSM-1, DASH_FONT_TITLE);
      int bw=DASH_W-PAD*2-16, bx=PAD+8, by=y+18, bh=12;
      DFill(bx, by, bx+bw, by+bh, 0xFF1E3A5F);
      int fw=(int)(bw*buyP/100.0);
      if(fw>0) DFill(bx, by, bx+fw, by+bh, AP_GREEN);
      if(fw<bw) DFill(bx+fw, by, bx+bw, by+bh, AP_RED);
      DText(bx+2, by+1, "B "+DoubleToString(buyP,0)+"%", 0xFFFFFFFF, DASH_FSM-1);
      DTextR(bx, by+1, bw-2, "S "+DoubleToString(100-buyP,0)+"%", 0xFFFFFFFF, DASH_FSM-1);
   }
   y += 44;

   // ── Open Trades ───────────────────────────────────────────────
   int tc=0; for(int i=0;i<100;i++) if(gRec[i].active) tc++;
   DrawApexCard(PAD, y, DASH_W-PAD*2, 22, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+22, AP_BLUE);
   DText(PAD+7, y+6, "OPEN TRADES", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   DTextR(PAD, y+6, DASH_W-PAD*2-6, IntegerToString(tc)+" position"+(tc!=1?"s":""), AP_TEXT2, DASH_FSM);
   y += 24;
   if(tc == 0)
   {
      DrawApexCard(PAD, y, DASH_W-PAD*2, 26, AP_CARD2, 0x08607090);
      DTextC(PAD, y+7, DASH_W-PAD*2, "No open positions", AP_TEXT3, DASH_FSM);
      y += 28;
   }
   else
   {
      int trShown=0;
      for(int i=0; i<100 && trShown<6; i++)
      {
         if(!gRec[i].active) continue;
         bool buy = (gRec[i].posType==ORDER_TYPE_BUY);
         double cp = buy?SymbolInfoDouble(gSymbol,SYMBOL_BID):SymbolInfoDouble(gSymbol,SYMBOL_ASK);
         double epnl = (cp-gRec[i].entryPrice)*(buy?1:-1)*gRec[i].initialVolume*gTickValue/MathMax(gTickSize,gPoint);
         DrawApexCard(PAD, y, DASH_W-PAD*2, 28, AP_CARD, 0x08607090);
         DFill(PAD, y, PAD+3, y+28, buy?AP_GREEN:AP_RED);
         uint dc=buy?AP_GREEN:AP_RED;
         DText(PAD+7,  y+8, buy?"▲ BUY":"▼ SELL",                           dc,       DASH_FSM, DASH_FONT_TITLE);
         DText(PAD+80, y+8, "@ "+DoubleToString(gRec[i].entryPrice,gDigits), AP_TEXT2, DASH_FSM);
         DText(PAD+210,y+8, "SL "+DoubleToString(gRec[i].stopLoss,gDigits),  AP_TEXT3, DASH_FSM);
         DText(PAD+340,y+8, DoubleToString(gRec[i].initialVolume,2)+" lot",  AP_TEXT2, DASH_FSM);
         uint pc=epnl>=0?AP_GREEN:AP_RED;
         DTextR(PAD, y+8, DASH_W-PAD*2-6, (epnl>=0?"+$":"$")+DoubleToString(MathAbs(epnl),2), pc, DASH_FSM, DASH_FONT_TITLE);
         y += 30; trShown++;
      }
      if(tc>6) { DTextC(PAD,y,DASH_W-PAD*2,"...+"+IntegerToString(tc-6)+" more",AP_TEXT3,DASH_FSM); y+=16; }
   }

   // ── Score components strip ───────────────────────────────────
   static const string CN[8]={"EMA","M5","RSI","PAT","BSP","MACD","VOL","ATR"};
   static const int    CM[8]={25,  15,  12,  10,  10,  8,   7,   5};
   DrawApexCard(PAD, y, DASH_W-PAD*2, 22, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+22, AP_BLUE);
   DText(PAD+7, y+6, "SIGNAL COMPONENTS", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   y += 24;
   int cbw=(DASH_W-PAD*2-7)/8;
   for(int c=0;c<8;c++)
   {
      int bx=PAD+c*(cbw+1);
      DrawApexCard(bx, y, cbw, 36, AP_CARD2, 0x08607090);
      int val=gScoreComp[c];
      uint vc=val>0?AP_GREEN:val<0?AP_RED:AP_TEXT3;
      DTextC(bx, y+2, cbw, CN[c], AP_TEXT3, DASH_FSM-1);
      gCanvas.FontSet(DASH_FONT_TITLE, DASH_FMD, FW_BOLD);
      string vs=(val>=0?"+":"")+IntegerToString(val); int sw=0,sh=0;
      gCanvas.TextSize(vs,sw,sh); gCanvas.TextOut(bx+(cbw-sw)/2, y+14, vs, vc, TA_LEFT|TA_TOP);
      int bby=y+32; int bww=(int)(cbw*0.7*MathMin(MathAbs((double)val)/MathMax((double)CM[c],1.0),1.0));
      DFill(bx+1, bby, bx+cbw-1, bby+3, AP_CARD);
      if(val>0 && bww>0) DFill(bx+cbw/2, bby, bx+cbw/2+bww, bby+3, AP_GREEN);
      if(val<0 && bww>0) DFill(bx+cbw/2-bww, bby, bx+cbw/2, bby+3, AP_RED);
   }
   y += 38;

   // ── Safety status row ─────────────────────────────────────────
   DrawApexCard(PAD, y, DASH_W-PAD*2, 22, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+22, AP_BLUE);
   DText(PAD+7, y+6, "SAFETY", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   y += 24;
   int pw=(DASH_W-PAD*2-7)/8;
   // MQL5: struct array brace-init not supported — assign element by element
   struct SfPill { string l; bool ok; bool warn; };
   SfPill sfp[8];
   sfp[0].l="SPREAD";    sfp[0].ok=!gBroker.spreadShock;                  sfp[0].warn=false;
   sfp[1].l="NEWS";      sfp[1].ok=!gNews.active;                         sfp[1].warn=gNews.active;
   sfp[2].l="SPIKE";     sfp[2].ok=!gSpike.spikeActive;                   sfp[2].warn=gSpike.spikeActive;
   sfp[3].l="DAILY DD";  sfp[3].ok=(ddUsed<ddLim);                        sfp[3].warn=(ddUsed>=ddLim*0.80);
   sfp[4].l="COOLDOWN";  sfp[4].ok=(gConsecLosses<(int)InpMaxConsecLosses); sfp[4].warn=false;
   sfp[5].l="PAUSED";    sfp[5].ok=!gBotPaused;                           sfp[5].warn=false;
   sfp[6].l="BUY";       sfp[6].ok=gRtAllowBuy;                           sfp[6].warn=!gRtAllowBuy;
   sfp[7].l="SELL";      sfp[7].ok=gRtAllowSell;                          sfp[7].warn=!gRtAllowSell;
   for(int p=0;p<8;p++)
   {
      int px2=PAD+p*(pw+1);
      uint bg=sfp[p].ok?AP_GREEN_BG:sfp[p].warn?AP_YELLOW_BG:AP_RED_BG;
      uint tc2=sfp[p].ok?AP_GREEN:sfp[p].warn?AP_YELLOW:AP_RED;
      DFill(px2, y, px2+pw, y+26, bg|0xC0000000); DBorder(px2, y, px2+pw, y+26, tc2, 1);
      DTextC(px2, y+3, pw, sfp[p].l, tc2, DASH_FSM-1, DASH_FONT_TITLE);
      DTextC(px2, y+14, pw, sfp[p].ok?"OK":"!", tc2, DASH_FSM, DASH_FONT_TITLE);
   }
   y += 30;

   // ── Controls ─────────────────────────────────────────────────
   string mTag=(gBotMode==BOT_MODE_HFT)?"HFT":(gBotMode==BOT_MODE_SCALPING)?"SCALP":"MOD";
   gBtnPause   = DBtn(PAD,       y, 96, 34, gBotPaused?"▶ RESUME":"⏸ PAUSE",
                      gBotPaused?AP_BLUE_MUTED:AP_CARD, gBotPaused?AP_BLUE_BRIGHT:AP_TEXT2);
   gBtnMode    = DBtn(PAD+100,   y,106, 34, "⟳ MODE: "+mTag, AP_CARD, AP_TEXT2);
   gBtnBuy     = DBtn(PAD+210,   y, 82, 34, gRtAllowBuy?"▲ BUY ON":"▲ BUY OFF",
                      gRtAllowBuy?(AP_GREEN_BG|0xD0000000):AP_CARD, gRtAllowBuy?AP_GREEN:AP_TEXT3);
   gBtnSell    = DBtn(PAD+296,   y, 82, 34, gRtAllowSell?"▼ SELL ON":"▼ SELL OFF",
                      gRtAllowSell?(AP_RED_BG|0xD0000000):AP_CARD, gRtAllowSell?AP_RED:AP_TEXT3);
   gBtnPanic   = DBtn(PAD+382,   y,200, 34, "⚠ EMERGENCY CLOSE ALL", 0xC0300010, AP_RED);
   gBtnMinimize= DBtn(DASH_W-PAD-44, y, 44, 34, "—", AP_CARD, AP_TEXT3);
}

//--------------------------------------------------------------------
// APEX Tab 1: Indicators — actual indicator values + score weights
// v6.3g: Replaces Calendar tab.  Shows all 7 score components with live
//        indicator readings and score contribution bars.  Also shows
//        EMA multi-TF alignment, Fib levels, Pivot levels, Patterns.
//--------------------------------------------------------------------
void RenderTabIndicators()
{
   int PAD = 8;
   int y   = AP_CTOP + PAD;

   // ── Header ───────────────────────────────────────────────────────
   DrawApexCard(PAD, y, DASH_W-PAD*2, 28, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+28, AP_BLUE);
   DText(PAD+7, y+7, "SIGNAL COMPONENTS — LIVE VALUES & SCORE WEIGHTS", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   string scBias = (gLastBias==BIAS_BULL)?"▲ BULL":(gLastBias==BIAS_BEAR)?"▼ BEAR":"— NEUTRAL";
   uint   scCol  = (gLastBias==BIAS_BULL)?AP_GREEN:(gLastBias==BIAS_BEAR)?AP_RED:AP_TEXT3;
   DTextR(PAD, y+7, DASH_W-PAD*2-6, IntegerToString(gLastScore)+"/93  "+scBias, scCol, DASH_FSM, DASH_FONT_TITLE);
   y += 34;

   // Live indicator reads (OnTimer context — safe to use CopyBuffer helpers)
   double h1e9    = GetEMA9(IDX_H1,1);   double h1e34   = GetEMA34(IDX_H1,1);
   double m5e9    = GetEMA9(IDX_M5,1);   double m5e34   = GetEMA34(IDX_M5,1);
   double rsiH1   = GetRSI(IDX_H1,1);    double rsiM5   = GetRSI(IDX_M5,1);
   double macdM   = GetMACDMain(IDX_H1,1); double macdS  = GetMACDSig(IDX_H1,1);
   double bbU     = GetBBUpper(IDX_H1,1); double bbL    = GetBBLower(IDX_H1,1);
   double bbMid2  = GetBBMid(IDX_H1,1);
   double stK     = GetStochK(IDX_H1,1); double stD    = GetStochD(IDX_H1,1);
   double atrH1   = GetATR(IDX_H1,1);
   double curBid  = SymbolInfoDouble(gSymbol, SYMBOL_BID);

   // Component labels, max weights (matches actual 7-component scorer in P7 §7.7)
   static const string CLBL[7] = {"EMA CROSS","RSI","MACD","BOLLINGER","STOCHASTIC","VOLUME MOM","REGIME"};
   static const int    CMAX[7] = {20, 15, 15, 10, 10, 10, 5};

   // Build human-readable value strings for each component
   string cval[7];
   if(h1e9 != EMPTY_VALUE && h1e34 != EMPTY_VALUE)
   {
      string h1dir = (h1e9 > h1e34) ? "9>34 ▲" : "9<34 ▼";
      string m5dir = (m5e9 != EMPTY_VALUE && m5e34 != EMPTY_VALUE) ? ((m5e9>m5e34)?"M5▲":"M5▼") : "M5:?";
      cval[0] = "H1: "+h1dir+"  "+m5dir
               +"  sep:"+DoubleToString(MathAbs(h1e9-h1e34)/gPoint,0)+"pt";
   }
   else cval[0] = "H1 EMA: waiting...";

   cval[1] = (rsiH1 != EMPTY_VALUE)
             ? "H1: "+DoubleToString(rsiH1,1)+"  M5: "+DoubleToString(rsiM5,1)
               +(rsiH1 > 70?" [OB]":rsiH1 < 30?" [OS]":rsiH1 > 50?" [Bull zone]":" [Bear zone]")
             : "RSI: waiting...";

   cval[2] = (macdM != EMPTY_VALUE)
             ? "Main: "+DoubleToString(macdM/gPoint,1)+"pt  Sig: "+DoubleToString(macdS/gPoint,1)+"pt"
               +"  Hist: "+DoubleToString((macdM-macdS)/gPoint,1)+"pt"
               +(macdM > macdS ? "  ↑ABVSIG" : "  ↓BLWSIG")
             : "MACD: waiting...";

   if(bbU != EMPTY_VALUE && bbL != EMPTY_VALUE)
   {
      double bbRng = bbU - bbL;
      string pos   = (curBid > bbU)    ? "ABOVE UPPER" :
                     (curBid < bbL)    ? "BELOW LOWER" :
                     (curBid > bbMid2) ? "UPPER HALF"  : "LOWER HALF";
      double pct   = SafeDiv(curBid - bbL, bbRng) * 100.0;
      cval[3] = "U:"+DoubleToString(bbU,gDigits)+" L:"+DoubleToString(bbL,gDigits)
               +"  Pos:"+pos+"("+DoubleToString(pct,0)+"%)";
   }
   else cval[3] = "BB: waiting...";

   cval[4] = (stK != EMPTY_VALUE)
             ? "K:"+DoubleToString(stK,1)+"  D:"+DoubleToString(stD,1)
               +(stK > stD?" K>D▲":" K<D▼")
               +(stK > 80?" [OB]":stK < 20?" [OS]":"")
             : "Stoch: waiting...";

   cval[5] = (atrH1 != EMPTY_VALUE && atrH1 > 0)
             ? "ATR H1: "+DoubleToString(atrH1/gPoint,0)+"pts  Vol-Mom: "+IntegerToString(gScoreComp[5])
               +(gScoreComp[5] > 0?" BULL":"")+(gScoreComp[5] < 0?" BEAR":"")
             : "ATR: waiting...";

   cval[6] = RegimeToString(gRegime.regime)
            +"  ATR H1: "+((atrH1 != EMPTY_VALUE) ? DoubleToString(atrH1/gPoint,0)+"pts" : "---");

   // ── 7 Component cards: 4+3 layout ───────────────────────────────
   int cH = 68;
   int cw4 = (DASH_W - PAD*2 - 9)  / 4;
   int cw3 = (DASH_W - PAD*2 - 6)  / 3;

   // Row 1: comps 0-3
   for(int c = 0; c < 4; c++)
   {
      int bx  = PAD + c*(cw4+3);
      int val = gScoreComp[c];
      int mxv = CMAX[c];
      uint vc = (val > 0) ? AP_GREEN : (val < 0) ? AP_RED : AP_TEXT3;
      DrawApexCard(bx, y, cw4, cH, AP_CARD2, 0x10607090);
      DFill(bx, y, bx+3, y+cH, vc);
      // Title row: name + max weight
      DText(bx+5, y+3, CLBL[c], AP_TEXT3, DASH_FSM-1, DASH_FONT_TITLE);
      DTextR(bx, y+3, cw4-4, "±"+IntegerToString(mxv), AP_TEXT3, DASH_FSM-1);
      // Value string
      gCanvas.FontSet(DASH_FONT_MONO, DASH_FSM-1, FW_NORMAL);
      // Clip the value string to fit card width
      string vs2 = cval[c]; if(StringLen(vs2) > 28) vs2 = StringSubstr(vs2,0,27)+"…";
      int tsw=0,tsh=0; gCanvas.TextSize(vs2,tsw,tsh);
      gCanvas.TextOut(bx+5, y+16, vs2, AP_TEXT2, TA_LEFT|TA_TOP);
      // Score value
      gCanvas.FontSet(DASH_FONT_TITLE, DASH_FMD+1, FW_BOLD);
      string sv = (val>=0?"+":"")+IntegerToString(val); int sw=0,sh=0;
      gCanvas.TextSize(sv,sw,sh);
      gCanvas.TextOut(bx+(cw4-sw)/2, y+36, sv, vc, TA_LEFT|TA_TOP);
      // Score bar
      int bby=y+54; int bww=(int)((cw4-8)*0.8*MathMin(MathAbs((double)val)/MathMax((double)mxv,1.0),1.0));
      DFill(bx+4, bby, bx+cw4-4, bby+4, AP_CARD);
      if(val>0 && bww>0) DFill(bx+cw4/2, bby, bx+cw4/2+bww, bby+4, AP_GREEN);
      if(val<0 && bww>0) DFill(bx+cw4/2-bww, bby, bx+cw4/2, bby+4, AP_RED);
   }
   y += cH + 4;

   // Row 2: comps 4-6
   for(int c = 4; c < 7; c++)
   {
      int bx  = PAD + (c-4)*(cw3+3);
      int val = gScoreComp[c];
      int mxv = CMAX[c];
      uint vc = (val > 0) ? AP_GREEN : (val < 0) ? AP_RED : AP_TEXT3;
      DrawApexCard(bx, y, cw3, cH, AP_CARD2, 0x10607090);
      DFill(bx, y, bx+3, y+cH, vc);
      DText(bx+5, y+3, CLBL[c], AP_TEXT3, DASH_FSM-1, DASH_FONT_TITLE);
      DTextR(bx, y+3, cw3-4, "±"+IntegerToString(mxv), AP_TEXT3, DASH_FSM-1);
      gCanvas.FontSet(DASH_FONT_MONO, DASH_FSM-1, FW_NORMAL);
      string vs2 = cval[c]; if(StringLen(vs2) > 36) vs2 = StringSubstr(vs2,0,35)+"…";
      gCanvas.TextOut(bx+5, y+16, vs2, AP_TEXT2, TA_LEFT|TA_TOP);
      gCanvas.FontSet(DASH_FONT_TITLE, DASH_FMD+1, FW_BOLD);
      string sv = (val>=0?"+":"")+IntegerToString(val); int sw=0,sh=0;
      gCanvas.TextSize(sv,sw,sh);
      gCanvas.TextOut(bx+(cw3-sw)/2, y+36, sv, vc, TA_LEFT|TA_TOP);
      int bby=y+54; int bww=(int)((cw3-8)*0.8*MathMin(MathAbs((double)val)/MathMax((double)mxv,1.0),1.0));
      DFill(bx+4, bby, bx+cw3-4, bby+4, AP_CARD);
      if(val>0 && bww>0) DFill(bx+cw3/2, bby, bx+cw3/2+bww, bby+4, AP_GREEN);
      if(val<0 && bww>0) DFill(bx+cw3/2-bww, bby, bx+cw3/2, bby+4, AP_RED);
   }
   y += cH + 6;

   // ── EMA Multi-TF alignment ────────────────────────────────────
   DrawApexCard(PAD, y, DASH_W-PAD*2, 22, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+22, AP_BLUE);
   DText(PAD+7, y+6, "EMA 9/34 — MULTI-TIMEFRAME ALIGNMENT", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   y += 24;
   {
      static const int    EMA_TFS[6]  = {IDX_M1, IDX_M5, IDX_M15, IDX_H1, IDX_H4, IDX_D1};
      static const string EMA_TFLBL[6]= {"M1","M5","M15","H1","H4","D1"};
      int ew = (DASH_W-PAD*2-10) / 6;
      for(int i = 0; i < 6; i++)
      {
         int ex = PAD + i*(ew+2);
         double e9  = GetEMA9 (EMA_TFS[i], 1);
         double e34 = GetEMA34(EMA_TFS[i], 1);
         bool   abv = (e9 != EMPTY_VALUE && e34 != EMPTY_VALUE && e9 > e34);
         uint   ec  = (e9==EMPTY_VALUE) ? AP_TEXT3 : abv ? AP_GREEN : AP_RED;
         DrawApexCard(ex, y, ew, 42, AP_CARD2, 0x10607090);
         DFill(ex, y, ex+3, y+42, ec);
         DTextC(ex, y+2,  ew, EMA_TFLBL[i],                       AP_TEXT3, DASH_FSM-1, DASH_FONT_TITLE);
         DTextC(ex, y+14, ew, (e9==EMPTY_VALUE)?"---":abv?"▲ BULL":"▼ BEAR", ec,      DASH_FSM);
         string sep = (e9!=EMPTY_VALUE && e34!=EMPTY_VALUE)
                      ? DoubleToString(MathAbs(e9-e34)/gPoint,0)+"pt" : "---";
         DTextC(ex, y+28, ew, sep, AP_TEXT3, DASH_FSM-1);
      }
      y += 48;
   }

   // ── Fib, Pivot & Pattern alignment ────────────────────────────
   DrawApexCard(PAD, y, DASH_W-PAD*2, 22, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+22, AP_BLUE);
   DText(PAD+7, y+6, "FIB / PIVOT / PATTERN  CONFLUENCE", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   y += 24;

   DrawApexCard(PAD, y, DASH_W-PAD*2, 50, AP_CARD2, 0x10607090);
   {
      // Row 1: alignment flags
      DText(PAD+6, y+4, "Fib:", AP_TEXT3, DASH_FSM);
      DText(PAD+32, y+4, gSignal.fibAligned?"ALIGNED ✓":"not aligned",
            gSignal.fibAligned?AP_GREEN:AP_TEXT3, DASH_FSM);
      DText(PAD+130, y+4, "Pivot:", AP_TEXT3, DASH_FSM);
      DText(PAD+164, y+4, gSignal.pivotAligned?"ALIGNED ✓":"not aligned",
            gSignal.pivotAligned?AP_GREEN:AP_TEXT3, DASH_FSM);
      DText(PAD+270, y+4, "Pattern:", AP_TEXT3, DASH_FSM);
      string patLbl = (gPattern.pattern != PATTERN_NONE)
                      ? gPattern.name + (gPattern.bullish?" ▲":" ▼") : "None";
      uint   patCol = (gPattern.pattern != PATTERN_NONE)
                      ? (gPattern.bullish ? AP_GREEN : AP_RED) : AP_TEXT3;
      DText(PAD+316, y+4, patLbl, patCol, DASH_FSM, DASH_FONT_TITLE);

      // Row 2: Fib levels
      string fibStr = gFibMap.valid
                      ? "H:"+DoubleToString(gFibMap.swingHigh,gDigits)
                        +" L:"+DoubleToString(gFibMap.swingLow,gDigits)
                        +"  0.382="+DoubleToString(gFibMap.r382,gDigits)
                        +"  0.500="+DoubleToString(gFibMap.r500,gDigits)
                        +"  0.618="+DoubleToString(gFibMap.r618,gDigits)
                      : "Fib: insufficient swing data";
      DText(PAD+6, y+18, fibStr, gFibMap.valid?AP_TEXT2:AP_TEXT3, DASH_FSM-1);

      // Row 3: Pivot levels
      string pvStr = gPivotD.ready
                     ? "D-Pvt: P="+DoubleToString(gPivotD.pivot,gDigits)
                       +"  R1="+DoubleToString(gPivotD.r1,gDigits)
                       +"  R2="+DoubleToString(gPivotD.r2,gDigits)
                       +"  S1="+DoubleToString(gPivotD.s1,gDigits)
                       +"  S2="+DoubleToString(gPivotD.s2,gDigits)
                     : "Pivot: not ready";
      DText(PAD+6, y+32, pvStr, gPivotD.ready?AP_TEXT2:AP_TEXT3, DASH_FSM-1);
   }
   y += 56;

   // ── S/R Zones (from pivot R1/R2/S1/S2 proximity) ─────────────
   DrawApexCard(PAD, y, DASH_W-PAD*2, 22, AP_CARD, AP_BLUE_DIM);
   DFill(PAD, y, PAD+3, y+22, AP_BLUE);
   DText(PAD+7, y+6, "SUPPORT / RESISTANCE ZONES", AP_BLUE_BRIGHT, DASH_FSM, DASH_FONT_TITLE);
   y += 24;
   if(gPivotD.ready && curBid > 0)
   {
      int zw = (DASH_W-PAD*2-10) / 6;
      string zlbl[6]; double zval[6]; bool     zabv[6];
      zlbl[0]="S2";  zval[0]=gPivotD.s2;  zabv[0]=(curBid>gPivotD.s2);
      zlbl[1]="S1";  zval[1]=gPivotD.s1;  zabv[1]=(curBid>gPivotD.s1);
      zlbl[2]="PP";  zval[2]=gPivotD.pivot;zabv[2]=(curBid>gPivotD.pivot);
      zlbl[3]="R1";  zval[3]=gPivotD.r1;  zabv[3]=(curBid>gPivotD.r1);
      zlbl[4]="R2";  zval[4]=gPivotD.r2;  zabv[4]=(curBid>gPivotD.r2);
      zlbl[5]="R3";  zval[5]=gPivotD.r3;  zabv[5]=(curBid>gPivotD.r3);
      for(int i=0; i<6; i++)
      {
         int zx = PAD + i*(zw+2);
         uint zc = zabv[i] ? AP_GREEN : AP_RED;
         DrawApexCard(zx, y, zw, 34, AP_CARD2, 0x10607090);
         DFill(zx, y, zx+3, y+34, zc);
         DTextC(zx, y+2,  zw, zlbl[i], AP_TEXT3, DASH_FSM-1, DASH_FONT_TITLE);
         DTextC(zx, y+14, zw, DoubleToString(zval[i],gDigits), AP_TEXT2, DASH_FSM-1);
         DTextC(zx, y+24, zw, zabv[i]?"↑ above":"↓ below", zc, DASH_FSM-2);
      }
      y += 40;
   }
   else
   {
      DrawApexCard(PAD, y, DASH_W-PAD*2, 24, AP_CARD2, 0x08607090);
      DTextC(PAD, y+6, DASH_W-PAD*2, "Pivot zones: not ready — waiting for daily bar close", AP_TEXT3, DASH_FSM-1);
      y += 28;
   }
}

//--------------------------------------------------------------------
// APEX Tab 2: Trades — detailed active position table
//--------------------------------------------------------------------
void RenderTabTrades()
{
   int PAD=8; int y=AP_CTOP+PAD;
   DrawApexCard(PAD,y,DASH_W-PAD*2,22,AP_CARD,AP_BLUE_DIM);
   DFill(PAD,y,PAD+3,y+22,AP_BLUE);
   DText(PAD+7,y+6,"ACTIVE POSITIONS",AP_BLUE_BRIGHT,DASH_FSM,DASH_FONT_TITLE);
   y+=24;
   int tc=0; for(int i=0;i<100;i++) if(gRec[i].active) tc++;
   if(tc==0)
   { DrawApexCard(PAD,y,DASH_W-PAD*2,50,AP_CARD2,0x08607090);
     DTextC(PAD,y+16,DASH_W-PAD*2,"No open positions",AP_TEXT3,DASH_FMD);
     return; }
   // Column headers
   int cx[]={PAD+4,PAD+28,PAD+118,PAD+218,PAD+308,PAD+388,PAD+455,PAD+510,PAD+568,PAD+618};
   static const string hdr[]={"#","DIR","ENTRY","CURRENT","SL","TP1","LOT","R","$PNL","M"};
   for(int c=0;c<10;c++) DText(cx[c],y,hdr[c],AP_TEXT3,DASH_FSM-1);
   y+=14; DHLine(PAD,DASH_W-PAD,y,AP_BLUE_DIM); y+=3;
   int idx=0;
   for(int i=0;i<100;i++)
   {
      if(!gRec[i].active) continue;
      bool buy=(gRec[i].posType==ORDER_TYPE_BUY);
      double cp=buy?SymbolInfoDouble(gSymbol,SYMBOL_BID):SymbolInfoDouble(gSymbol,SYMBOL_ASK);
      double pnl=PositionSelectByTicket(gRec[i].ticket)?PositionGetDouble(POSITION_PROFIT):0;
      double R=(gRec[i].riskDistance>0)
               ?(buy?(cp-gRec[i].entryPrice):(gRec[i].entryPrice-cp))/gRec[i].riskDistance:0;
      DrawApexCard(PAD,y,DASH_W-PAD*2,30,AP_CARD,0x08607090);
      DFill(PAD,y,PAD+3,y+30,buy?AP_GREEN:AP_RED);
      DText(cx[0],y+9,IntegerToString(idx+1),AP_TEXT2,DASH_FSM);
      DText(cx[1],y+9,buy?"▲B":"▼S",buy?AP_GREEN:AP_RED,DASH_FSM,DASH_FONT_TITLE);
      DText(cx[2],y+9,DoubleToString(gRec[i].entryPrice,gDigits),AP_TEXT2,DASH_FSM);
      DText(cx[3],y+9,DoubleToString(cp,gDigits),AP_TEXT2,DASH_FSM);
      DText(cx[4],y+9,DoubleToString(gRec[i].stopLoss,gDigits),AP_TEXT3,DASH_FSM);
      DText(cx[5],y+9,DoubleToString(gRec[i].tp1Price,gDigits),AP_TEXT3,DASH_FSM);
      DText(cx[6],y+9,DoubleToString(gRec[i].initialVolume,2),AP_TEXT2,DASH_FSM);
      uint rc=R>0?AP_GREEN:R<0?AP_RED:AP_TEXT3;
      DText(cx[7],y+9,(R>=0?"+":"")+DoubleToString(R,2)+"R",rc,DASH_FSM);
      uint pc=pnl>=0?AP_GREEN:AP_RED;
      DText(cx[8],y+9,(pnl>=0?"+$":"$")+DoubleToString(MathAbs(pnl),2),pc,DASH_FSM);
      DText(cx[9],y+9,gRec[i].isScalpMode?"S":"M",AP_TEXT3,DASH_FSM);
      y+=32; idx++;
   }
}

//--------------------------------------------------------------------
// APEX Tab 3: Stats — performance summary + drawdown donut + curve
//--------------------------------------------------------------------
void RenderTabStats()
{
   int PAD=8; int y=AP_CTOP+PAD;
   DrawApexCard(PAD,y,DASH_W-PAD*2,22,AP_CARD,AP_BLUE_DIM);
   DFill(PAD,y,PAD+3,y+22,AP_BLUE);
   DText(PAD+7,y+6,"PERFORMANCE SUMMARY",AP_BLUE_BRIGHT,DASH_FSM,DASH_FONT_TITLE);
   y+=24;
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double dp=gDailyClosedPnL;
   double ddLim=InpMaxDailyLossPercent;
   double ddUsed=(balance>0)?MathAbs(dp)/balance*100.0:0;
   double wr=(gPerf.totalTrades>0)?(gPerf.winTrades*100.0/gPerf.totalTrades):0;
   // MQL5: no anonymous-struct arrays — use parallel arrays with element assignment
   string stl[12]; string stv[12]; uint stc[12];
   stl[0]="Total Trades"; stv[0]=IntegerToString(gPerf.totalTrades);         stc[0]=AP_TEXT;
   stl[1]="Win Trades";   stv[1]=IntegerToString(gPerf.winTrades);           stc[1]=AP_GREEN;
   stl[2]="Loss Trades";  stv[2]=IntegerToString(gPerf.lossTrades);          stc[2]=AP_RED;
   stl[3]="Win Rate";     stv[3]=DoubleToString(wr,1)+"%";                   stc[3]=(wr>=60?AP_GREEN:wr>=45?AP_YELLOW:AP_RED);
   stl[4]="Daily P&L";    stv[4]=(dp>=0?"+$":"$")+DoubleToString(MathAbs(dp),2); stc[4]=(dp>=0?AP_GREEN:AP_RED);
   stl[5]="DD Used";      stv[5]=DoubleToString(ddUsed,2)+"%";               stc[5]=(ddUsed<3?AP_GREEN:ddUsed<5?AP_YELLOW:AP_RED);
   stl[6]="Consec Wins";  stv[6]=IntegerToString(gConsecWins);               stc[6]=AP_GREEN;
   stl[7]="Consec Loss";  stv[7]=IntegerToString(gConsecLosses);             stc[7]=AP_RED;
   stl[8]="Score";        stv[8]=IntegerToString(gLastScore)+"/93";          stc[8]=AP_TEXT2;
   stl[9]="HFT Rate";     stv[9]=DoubleToString(gHFTTickRate,1)+"/s";        stc[9]=AP_TEXT2;
   stl[10]="TG Sent";     stv[10]=IntegerToString(gTGTotalSent);             stc[10]=AP_TEXT2;
   stl[11]="TG Dropped";  stv[11]=IntegerToString(gTGDropped);               stc[11]=AP_TEXT2;
   int sw2=(DASH_W-PAD*3)/2, rowH=24;
   for(int r=0;r<12;r++)
   {
      int col=r/6, row=r%6;
      int rx=PAD+col*(sw2+PAD), ry=y+row*rowH;
      DrawApexCard(rx,ry,sw2,rowH-2,AP_CARD,0x08607090);
      DText(rx+PAD,ry+6,stl[r],AP_TEXT3,DASH_FSM);
      DTextR(rx,ry+6,sw2-PAD,stv[r],stc[r],DASH_FSM,DASH_FONT_TITLE);
   }
   y+=6*rowH+6;
   // Drawdown donut + equity curve side by side
   DrawApexCard(PAD,y,DASH_W-PAD*2,148,AP_CARD,0x18607090);
   // Drawdown donut (left)
   int dcx=PAD+76,dcy=y+74;
   DrawApexDonut(dcx,dcy,58,44,MathMin(ddUsed/MathMax(ddLim,0.1),1.0),
                 ddUsed<3?AP_GREEN:ddUsed<5?AP_YELLOW:AP_RED,0xFF1E293B);
   gCanvas.FontSet(DASH_FONT_TITLE,14,FW_BOLD);
   string ddS=DoubleToString(ddUsed,1)+"%"; int sw=0,sh=0; gCanvas.TextSize(ddS,sw,sh);
   gCanvas.TextOut(dcx-sw/2,dcy-sh/2,ddS,AP_TEXT,TA_LEFT|TA_TOP);
   gCanvas.FontSet(DASH_FONT_TITLE,DASH_FSM,FW_NORMAL); string dl="DRAWDOWN";
   gCanvas.TextSize(dl,sw,sh); gCanvas.TextOut(dcx-sw/2,dcy+sh/2+4,dl,AP_TEXT3,TA_LEFT|TA_TOP);
   DText(PAD+6,y+138,"DD Limit: "+DoubleToString(ddLim,1)+"%",AP_TEXT3,DASH_FSM-1);
   // Equity curve (right)
   DrawApexEquityCurve(PAD+152,y+6,DASH_W-PAD*2-160,134);
   DText(PAD+160,y+8,"EQUITY CURVE ("+IntegerToString(SPARK_LEN*EQUITY_SMPL_SEC/60)+"min window)",AP_TEXT3,DASH_FSM-1,DASH_FONT_TITLE);
}

//--------------------------------------------------------------------
// APEX Tab 3: Config — all parameter groups (Task 3+4)
// v6.3g: Mode/Risk, HFT parameters, Safety, Filters, TSL/TP
//--------------------------------------------------------------------
void RenderTabConfig()
{
   int PAD = 8;
   int y   = AP_CTOP + PAD;

   // Helper lambda-like macro: draw a two-column key-value row
   // (MQL5 has no lambdas, so we inline the draw calls)
   int rH  = 18;   // row height
   int kW  = 160;  // key column width
   int vW  = DASH_W - PAD*2 - kW - 4;

   // ── Section header helper (reused 6× below) ────────────────────
   #define CFGSEC(lbl) { DrawApexCard(PAD,y,DASH_W-PAD*2,22,AP_CARD,AP_BLUE_DIM); \
                          DFill(PAD,y,PAD+3,y+22,AP_BLUE); \
                          DText(PAD+7,y+6,lbl,AP_BLUE_BRIGHT,DASH_FSM,DASH_FONT_TITLE); \
                          y+=24; }
   #define CFGROW(k,v,vc) { DrawApexCard(PAD,y,DASH_W-PAD*2,rH,AP_CARD2,0x08607090); \
                              DText(PAD+6,y+4,k,AP_TEXT3,DASH_FSM-1); \
                              DTextR(PAD,y+4,DASH_W-PAD*2-6,v,(vc),DASH_FSM,DASH_FONT_TITLE); \
                              y+=rH+1; }

   // ── 1. MODE & RISK PROFILE ──────────────────────────────────────
   CFGSEC("MODE & RISK PROFILE")
   string modeStr = (gBotMode==BOT_MODE_HFT)?"HFT — High Frequency":
                    (gBotMode==BOT_MODE_SCALPING)?"SCALPING — Limit Orders":"MODERATE — Swing";
   CFGROW("Active Mode",      modeStr,           AP_BLUE_BRIGHT)
   CFGROW("Sub-Mode",         SubModeName(),     AP_TEXT2)
   CFGROW("Risk Profile",     RiskProfileName(gActiveRiskProfile), AP_TEXT2)
   CFGROW("Active Risk %",    DoubleToString(gRt_RiskPct,2)+"%  (gRt_RiskPct — effective after profile scaling)", AP_TEXT2)
   CFGROW("Daily DD Limit",   DoubleToString(gRt_DailyDDPct,1)+"%  ("+SubModeName()+" sub-mode limit)", AP_YELLOW)
   CFGROW("Global DD Limit",  DoubleToString(InpMaxGlobalDrawdownPercent,1)+"%  (equity high-water mark)", AP_YELLOW)
   CFGROW("Equity Floor",     "$"+DoubleToString(InpEquityFloor,2), AP_TEXT2)
   y += 4;

   // ── 2. HFT ENGINE PARAMETERS ────────────────────────────────────
   CFGSEC("HFT ENGINE PARAMETERS")
   uint hftOk = (gBotMode==BOT_MODE_HFT) ? AP_TEXT2 : AP_TEXT3;
   CFGROW("HFT Min Score",          IntegerToString(gRt_HFTMinScore)+"  (gRt_HFTMinScore — profile-adjusted)", hftOk)
   CFGROW("HFT SL ATR Mult",        DoubleToString(gRt_HFTSLatrMult,2)+"×  (tight — e.g. 0.30×M1 ATR)",       hftOk)
   CFGROW("HFT TP1 R / TP2 R",      DoubleToString(gRt_HFTTPr1,2)+"R  /  "+DoubleToString(gRt_HFTTPr2,2)+"R", hftOk)
   CFGROW("HFT Fast BE Lock",        DoubleToString(InpHFTFastBER,2)+"R  ("+DoubleToString(InpHFTFastBER*100,0)+"% profit → BE)", hftOk)
   CFGROW("HFT Risk %",             DoubleToString(InpHFTRiskPercent,2)+"%  (InpHFTRiskPercent input)", hftOk)
   CFGROW("HFT Profit Lock R1/R2",  DoubleToString(InpHFTProfitLockR1,2)+"R / "+DoubleToString(InpHFTProfitLockR2,2)+"R  Lock:"+(InpHFTUseProfitLock?"ON":"OFF"), hftOk)
   CFGROW("HFT Max Trades/Hr",       IntegerToString(InpHFTMaxTradesPerHour)+"  rate limiter", hftOk)
   CFGROW("HFT Cooldown (sec)",      IntegerToString(InpHFTPostExitCooldownSec)+"s  post-exit cooldown", hftOk)
   CFGROW("HFT Pending Max Age",     IntegerToString(InpHFTPendingMaxAgeSec)+"s  (auto-cancel aged HFT orders)", hftOk)
   CFGROW("HFT HTF Gate",            InpHFTRespectHTFFilter?"ON — applies D1/H4 trend gate":"OFF — HFT ignores D1/H4 trend gate", hftOk)
   CFGROW("HFT Bidir / Cooldown",    (gRt_HFTBidir?"Bidirectional ON":"Bidirectional OFF")+"  "+IntegerToString(gRt_HFTBidirCoolMs)+"ms cooldown", hftOk)
   y += 4;

   // ── 3. SCALP MODE PARAMETERS ────────────────────────────────────
   CFGSEC("SCALP MODE PARAMETERS")
   uint scOk = (gBotMode==BOT_MODE_SCALPING) ? AP_TEXT2 : AP_TEXT3;
   CFGROW("Scalp Min Score",         IntegerToString(gRt_ScalpMinScore)+"  (profile-adjusted)", scOk)
   CFGROW("Scalp SL ATR Min/Max",    DoubleToString(gRt_ScalpSLatrMin,2)+"×  /  "+DoubleToString(gRt_ScalpSLatrMax,2)+"×  ATR", scOk)
   CFGROW("Scalp TP1 R",             DoubleToString(gRt_ScalpTP1R,2)+"R  (virtual partial close trigger)", scOk)
   CFGROW("Scalp Profit Lock",       "R1:"+DoubleToString(InpScalpProfitLockR1,2)+" R2:"+DoubleToString(InpScalpProfitLockR2,2)+" R3:"+DoubleToString(InpScalpProfitLockR3,2)+"  Steps:"+(InpScalpUseProfitLockSteps?"ON":"OFF"), scOk)
   CFGROW("Scalp TSL ATR Frac",      DoubleToString(InpScalpTSLATRFraction,2)+"× ATR  (tick trail step)", scOk)
   y += 4;

   // ── 4. SAFETY & DRAWDOWN ────────────────────────────────────────
   // NOTE: All CFGROW args pre-computed into locals — MQL5 preprocessor terminates
   //       macro args at newline, so multi-line macro calls fail to compile.
   CFGSEC("SAFETY & DRAWDOWN STATUS")
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bl = AccountInfoDouble(ACCOUNT_BALANCE);
   string sEqFloor  = "$"+DoubleToString(eq,2)+" vs floor $"+DoubleToString(InpEquityFloor,2)+"  Lock:"+(gSafety.lockEquityFloor?"ACTIVE":"OK");
   string sDDDay    = DoubleToString(gSafety.globalDDPct<0?0:MathAbs(gDailyClosedPnL)/MathMax(bl,1)*100,1)+"% used / "+DoubleToString(gRt_DailyDDPct,1)+"% limit  Lock:"+(gSafety.lockDailyLoss?"ACTIVE":"OK");
   string sDDGlob   = DoubleToString(gSafety.globalDDPct,2)+"% (HWM $"+DoubleToString(gSafety.ddHighWaterMark,2)+")  Lock:"+(gSafety.lockGlobalDD?"ACTIVE":"OK");
   string sConsec   = IntegerToString(gConsecLosses)+" / "+IntegerToString(InpMaxConsecLosses)+"  Smooth:"+(InpApplyLossSmoothToAuto?"ON":"OFF");
   CFGROW("Equity Floor Status", sEqFloor,  gSafety.lockEquityFloor?AP_RED:AP_GREEN)
   CFGROW("Daily DD Status",     sDDDay,    gSafety.lockDailyLoss?AP_RED:AP_GREEN)
   CFGROW("Global DD Status",    sDDGlob,   gSafety.lockGlobalDD?AP_RED:AP_GREEN)
   CFGROW("Consec Loss Guard",   sConsec,   AP_TEXT2)
   y += 4;

   // ── 5. FILTERS ──────────────────────────────────────────────────
   CFGSEC("ACTIVE FILTERS")
   #define FROW(k,on)  CFGROW(k, (on)?"ON  ✓":"OFF", (on)?AP_GREEN:AP_TEXT3)
   FROW("News Filter",       gRt_UseNewsFilter)
   FROW("Spike Detection",   gRt_UseSpikeFilter)
   FROW("Volume Momentum",   gRt_UseVolMom)
   FROW("Candle Patterns",   gRt_UsePatterns)
   FROW("Fib Engine",        gRt_UseFib)
   FROW("Pivot Engine",      gRt_UsePivot)
   FROW("ADX Filter",        gRt_UseAdxFilter)
   CFGROW("ADX Min (Mode)",  (gBotMode==BOT_MODE_HFT?IntegerToString(gRt_ADXminHFT):
                               gBotMode==BOT_MODE_SCALPING?IntegerToString(gRt_ADXminScalp):
                               IntegerToString(gRt_ADXminMod))+"  (profile-adjusted)", AP_TEXT2)
   y += 4;

   // ── 6. TSL & PARTIAL TP ─────────────────────────────────────────
   CFGSEC("TSL & PARTIAL TP (Task 5)")
   // Note: Scalp TP2/TP3 are hardcoded 1.00R/1.50R (not configurable separately).
   //       HFT TP2 is gRt_HFTTPr2. Moderate uses gRt_ModTP1R/2R/3R.
   CFGROW("TP1 Partial (30%)",   (gBotMode==BOT_MODE_HFT?DoubleToString(gRt_HFTTPr1,2):
                                   gBotMode==BOT_MODE_SCALPING?DoubleToString(gRt_ScalpTP1R,2):
                                   DoubleToString(gRt_ModTP1R,2))+"R  → closes 30% volume", AP_TEXT2)
   CFGROW("TP2 Partial (40%)",   (gBotMode==BOT_MODE_HFT?DoubleToString(gRt_HFTTPr2,2):
                                   gBotMode==BOT_MODE_SCALPING?"1.00":
                                   DoubleToString(gRt_ModTP2R,2))+"R  → closes 40% volume", AP_TEXT2)
   CFGROW("TP3 Broker Hard",     (gBotMode==BOT_MODE_HFT?"HFT: no broker TP3":
                                   gBotMode==BOT_MODE_SCALPING?"1.50R  (hardcoded)":
                                   DoubleToString(gRt_ModTP3R,2)+"R (InpModerateTP3R)")+"  → broker hard TP", AP_TEXT2)
   CFGROW("TSL Mode (HFT/Scalp)","Tick-by-tick (scalpTSLOnTick=true) — fires every tick after TP1 hit", AP_TEXT2)
   CFGROW("TSL Mode (Moderate)", "Bar-close trailing — ManageTrailing() on each tick", AP_TEXT2)
   CFGROW("HFT Profit Lock ON?", InpHFTUseProfitLock?"YES — uses InpHFTProfitLockR1/R2":"NO — disabled", InpHFTUseProfitLock?AP_GREEN:AP_TEXT3)
   CFGROW("Scalp Profit Lock ON?",InpScalpUseProfitLockSteps?"YES — 3-step SCALP_LOCK_R1/2/3":"NO — disabled", InpScalpUseProfitLockSteps?AP_GREEN:AP_TEXT3)

   #undef CFGSEC
   #undef CFGROW
   #undef FROW
}

//--------------------------------------------------------------------
// 14.17  MASTER RENDER FUNCTION  (OnTimer ONLY — never OnTick)
//         Apex Algorithms-style redesign (v6.3g)
//         Deep navy background, blue accent, 5-tab navigation.
//--------------------------------------------------------------------
void RenderDashboardAdvanced()
{
   if(!InpShowDashboard || !gCanvasReady || !gDashNeedsRedraw) return;
   gDashNeedsRedraw = false;

   // Dynamic height — compact Apex design rows are ~32px
   int tc=0; for(int i=0;i<100;i++) if(gRec[i].active) tc++;
   int neededH = DASH_H_BASE + MathMax(0, tc-6)*32;
   if(neededH != gDashActualH)
   {
      gDashActualH = neededH;
      if(!gCanvas.Resize(DASH_W, gDashActualH))
         gDashActualH = DASH_H_BASE;
   }

   // Apex deep navy background (flat, no gradient)
   gCanvas.Erase(AP_BG);

   if(gDashMinimized)
   {
      // Minimized: header bar only
      DFill(0, 0, DASH_W, AP_HDR_H, AP_HDR);
      gCanvas.Line(0, AP_HDR_H-2, DASH_W, AP_HDR_H-2, AP_BLUE);
      DText(10, 14, "SK TRADE PREMIUM  " + GetVersionString(), AP_TEXT, DASH_FMD, DASH_FONT_TITLE);
      gBtnMinimize = DBtn(DASH_W-54, 6, 44, 30, "□", AP_CARD, AP_TEXT2);
      gCanvas.Update(true);
      return;
   }

   // ── Header ───────────────────────────────────────────────────────
   DFill(0, 0, DASH_W, AP_HDR_H, AP_HDR);
   gCanvas.Line(0, AP_HDR_H-2, DASH_W, AP_HDR_H-2, AP_BLUE);
   DText(10, 8,  "SK TRADE PREMIUM",  AP_TEXT,  DASH_FMD, DASH_FONT_TITLE);
   DText(10, 24, GetVersionString()+"  "+gSymbol, AP_TEXT2, DASH_FSM);
   string mTag = (gBotMode==BOT_MODE_HFT)?"HFT":(gBotMode==BOT_MODE_SCALPING)?"SCALP":"MOD";
   DTextR(0, 8,  DASH_W-10, mTag, AP_BLUE_BRIGHT, DASH_FMD, DASH_FONT_TITLE);
   DTextR(0, 24, DASH_W-10, TimeToString(TimeLocal(), TIME_SECONDS), AP_TEXT3, DASH_FSM);

   // ── Tab bar ──────────────────────────────────────────────────────
   DrawApexTabBar(AP_HDR_H);

   // ── Tab content routing — 5 tabs (v6.3g) ────────────────────────
   switch(gDashTab)
   {
      case 0: RenderTabOverview();    break;   // Live trading + score + safety
      case 1: RenderTabIndicators();  break;   // Indicator values + score weights
      case 2: RenderTabTrades();      break;   // Active position detail
      case 3: RenderTabConfig();      break;   // All parameters (Task 3+4)
      case 4: RenderTabStats();       break;   // Performance + equity curve
      default: RenderTabOverview();   break;
   }

   // ── Debug strip ──────────────────────────────────────────────────
   DText(4, gDashActualH-14,
         StringFormat("Renders:%d  TG:%d/%d  %s",
                      ++gDashRenderCnt, gTGTotalSent, gTGDropped,
                      TimeToString(TimeLocal(), TIME_SECONDS)),
         AP_TEXT3, 6);

   // ── Flush to screen ──────────────────────────────────────────────
   gCanvas.Update(true);
}

//--------------------------------------------------------------------
// 14.18  DASHBOARD CHART EVENT HANDLER
//         Forward all OnChartEvent params to this function.
//         Handles: header drag | minimize | pause | mode | panic
//--------------------------------------------------------------------
void OnDashChartEvent(const int id, const long &lparam,
                      const double &dparam, const string sparam)
{
   if(!InpShowDashboard || !gCanvasReady) return;

   // Convert chart coords → canvas-local coords
   int mx = (int)lparam;
   int my = (int)dparam;
   int lx = mx - gDashX;
   int ly = my - gDashY;

   // ── MOUSE MOVE: drag handling ───────────────────────────────────
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      // sparam encodes button state: "1"=left, "2"=right, "4"=middle, etc.
      bool leftDown = (StringFind(sparam, "1") >= 0);

      if(leftDown && !gDashDragging)
      {
         // Start drag only if click is in header band
         if(lx >= 0 && lx < DASH_W && ly >= 0 && ly < DASH_HDR_H)
         {
            gDashDragging = true;
            gDashDragOX   = lx;
            gDashDragOY   = ly;
         }
      }
      else if(leftDown && gDashDragging)
      {
         // Clamp new position to chart bounds
         int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         int newX   = MathMax(0, MathMin(mx - gDashDragOX, chartW - DASH_W));
         int newY   = MathMax(0, MathMin(my - gDashDragOY, chartH - 60));
         if(newX != gDashX || newY != gDashY)
         {
            gDashX = newX;
            gDashY = newY;
            UIReposition();
         }
      }
      else if(!leftDown)
         gDashDragging = false;

      return;
   }

   // ── CHART CLICK: button hit detection ──────────────────────────
   if(id == CHARTEVENT_CLICK)
   {
      // Reject clicks outside canvas bounds
      if(lx < 0 || lx >= DASH_W || ly < 0 || ly >= gDashActualH) return;

      // Tab navigation (v6.3g — 5 tabs) — check before buttons so tab bar takes priority
      for(int t=0; t<5; t++)
      {
         if(gTabRgn[t].vis
            && lx >= gTabRgn[t].x && lx <= gTabRgn[t].x + gTabRgn[t].w
            && ly >= gTabRgn[t].y && ly <= gTabRgn[t].y + gTabRgn[t].h)
         {
            if(gDashTab != t) { gDashTab = t; UINeedRedraw(); }
            return;
         }
      }

      // Minimize toggle
      if(gBtnMinimize.vis && lx>=gBtnMinimize.x && lx<=gBtnMinimize.x+gBtnMinimize.w
                          && ly>=gBtnMinimize.y && ly<=gBtnMinimize.y+gBtnMinimize.h)
      {
         gDashMinimized = !gDashMinimized;
         if(!gDashMinimized) gCanvas.Resize(DASH_W, gDashActualH);
         else                gCanvas.Resize(DASH_W, 60);
         UINeedRedraw();
         return;
      }

      // Pause / Resume toggle
      if(gBtnPause.vis && lx>=gBtnPause.x && lx<=gBtnPause.x+gBtnPause.w
                       && ly>=gBtnPause.y && ly<=gBtnPause.y+gBtnPause.h)
      {
         gSafety.lockManualPause = !gSafety.lockManualPause;
         gManualPause            =  gSafety.lockManualPause;
         if(gManualPause)
         {
            JournalWarn("Dashboard","MANUAL PAUSE engaged via dashboard");
            TGAlert_SafetyLock("MANUAL_PAUSE","Dashboard pause button");
         }
         else
         {
            JournalInfo("Dashboard","MANUAL PAUSE released via dashboard");
            TGAlert_SafetyRelease("MANUAL_PAUSE");
         }
         UINeedRedraw();
         return;
      }

      // Mode switch — cycles: MODERATE → SCALPING → HFT → MODERATE
      if(gBtnMode.vis && lx>=gBtnMode.x && lx<=gBtnMode.x+gBtnMode.w
                      && ly>=gBtnMode.y && ly<=gBtnMode.y+gBtnMode.h)
      {
         if(gBotMode == BOT_MODE_MODERATE)        gBotMode = BOT_MODE_SCALPING;
         else if(gBotMode == BOT_MODE_SCALPING)   gBotMode = BOT_MODE_HFT;
         else                                     gBotMode = BOT_MODE_MODERATE;
         string ms = (gBotMode==BOT_MODE_HFT)     ? "HFT"      :
                     (gBotMode==BOT_MODE_SCALPING) ? "SCALPING" : "MODERATE";
         JournalInfo("Dashboard","Mode → "+ms);
         TGEnqueue(TGE_WRENCH " Bot mode switched to <b>"+ms+"</b> via dashboard");
         UINeedRedraw();
         return;
      }

      // BUY direction toggle (v6.3d: toggles gRtAllowBuy runtime global)
      if(gBtnBuy.vis && lx>=gBtnBuy.x && lx<=gBtnBuy.x+gBtnBuy.w
                     && ly>=gBtnBuy.y && ly<=gBtnBuy.y+gBtnBuy.h)
      {
         gRtAllowBuy = !gRtAllowBuy;
         string bs = gRtAllowBuy ? "ENABLED" : "DISABLED";
         JournalInfo("Dashboard","BUY direction → "+bs);
         TGEnqueue(TGE_WRENCH " BUY direction <b>"+bs+"</b> via dashboard");
         PushEAEvent("DirToggle","BUY direction "+bs);
         UINeedRedraw();
         return;
      }

      // SELL direction toggle (v6.3d: toggles gRtAllowSell runtime global)
      if(gBtnSell.vis && lx>=gBtnSell.x && lx<=gBtnSell.x+gBtnSell.w
                      && ly>=gBtnSell.y && ly<=gBtnSell.y+gBtnSell.h)
      {
         gRtAllowSell = !gRtAllowSell;
         string ss = gRtAllowSell ? "ENABLED" : "DISABLED";
         JournalInfo("Dashboard","SELL direction → "+ss);
         TGEnqueue(TGE_WRENCH " SELL direction <b>"+ss+"</b> via dashboard");
         PushEAEvent("DirToggle","SELL direction "+ss);
         UINeedRedraw();
         return;
      }

      // Panic Close (two-click: arm then fire within 3 seconds)
      if(gBtnPanic.vis && lx>=gBtnPanic.x && lx<=gBtnPanic.x+gBtnPanic.w
                       && ly>=gBtnPanic.y && ly<=gBtnPanic.y+gBtnPanic.h)
      {
         if(!gPanicArmed || (TimeLocal()-gPanicArmedAt) > 3)
         {
            gPanicArmed   = true;
            gPanicArmedAt = TimeLocal();
            JournalWarn("Dashboard","PANIC CLOSE armed — confirm within 3s");
            TGEnqueue(TGE_WARN " <b>PANIC CLOSE armed</b> — click again within 3s to confirm");
         }
         else
         {
            int cnt=0; for(int i=0;i<100;i++) if(gRec[i].active) cnt++;
            gPanicArmed = false;
            EmergencyCloseAll("DashboardPanicButton");
            TGAlert_EmergencyClose(cnt,"Dashboard PANIC button — user initiated");
            JournalError("Dashboard","EMERGENCY CLOSE ALL fired via PANIC button");
         }
         UINeedRedraw();
         return;
      }
   }
}

//====================================================================
// ═══════════════════════════════════════════════════════════════════
//  ENGINE 15 — UPDATE / PATCH INJECTION SYSTEM
//  Registry of named behavioral patches injected into the EA at
//  runtime without full recompile.  Patches gate conditional code
//  blocks via IsPatchApplied().  Audit trail logged on startup.
// ═══════════════════════════════════════════════════════════════════
//====================================================================

//--------------------------------------------------------------------
// 15.1  PATCH RECORD STRUCTURE
//--------------------------------------------------------------------
struct PatchRecord
{
   int      patchId;         // unique sequential ID (never reused)
   string   patchName;       // identifier string (used in IsPatchApplied calls)
   string   patchVersion;    // semver string, e.g. "6.0.1"
   string   description;     // plain-text description of what the patch changes
   bool     applied;         // true once ApplyPendingPatches() has run
   datetime appliedAt;       // timestamp when applied this session
};

PatchRecord gPatchReg[32];   // registry array
int         gPatchCount = 0; // number of registered entries

//--------------------------------------------------------------------
// 15.2  VERSION STRING  (Upgrade 6.3 — clean version, no patch suffix)
//--------------------------------------------------------------------
string gCurrentVersion = "6.3.0";

string GetVersionString()
{
   // Return clean version — patch count suffix removed (was "+Np" in v6.0/6.1)
   return "v" + gCurrentVersion;
}

//--------------------------------------------------------------------
// 15.3  REGISTRY OPERATIONS
//--------------------------------------------------------------------
void PatchEngine_Init()
{
   gPatchCount = 0;
   for(int i=0;i<32;i++)
   {
      gPatchReg[i].patchId     = 0;
      gPatchReg[i].patchName   = "";
      gPatchReg[i].patchVersion= "";
      gPatchReg[i].description = "";
      gPatchReg[i].applied     = false;
      gPatchReg[i].appliedAt   = 0;
   }
   JournalInfo("PatchEngine", "Registry cleared — v" + gCurrentVersion);
}

// Register a new patch.  Returns false if patchId already exists or registry full.
bool InjectPatch(int patchId, const string name, const string ver, const string desc)
{
   for(int i=0;i<gPatchCount;i++)
      if(gPatchReg[i].patchId == patchId)
      {
         JournalWarn("InjectPatch", StringFormat("#%d '%s' already registered", patchId, name));
         return false;
      }

   if(gPatchCount >= 32)
   {
      JournalError("InjectPatch","Registry full (max 32)");
      return false;
   }

   int n = gPatchCount++;
   gPatchReg[n].patchId     = patchId;
   gPatchReg[n].patchName   = name;
   gPatchReg[n].patchVersion= ver;
   gPatchReg[n].description = desc;
   gPatchReg[n].applied     = false;
   gPatchReg[n].appliedAt   = 0;

   JournalInfo("InjectPatch", StringFormat("#%03d '%-20s' v%s — %s",
                                            patchId, name, ver, desc));
   return true;
}

// Mark all pending patches as applied.  Call once from OnInit after all
// InjectPatch() calls.  Sends one Telegram summary if any were applied.
void ApplyPendingPatches()
{
   int cnt = 0;
   for(int i=0;i<gPatchCount;i++)
   {
      if(!gPatchReg[i].applied)
      {
         gPatchReg[i].applied   = true;
         gPatchReg[i].appliedAt = TimeLocal();
         cnt++;
         JournalInfo("PatchEngine", StringFormat("Applied #%03d '%s' v%s",
                                                  gPatchReg[i].patchId,
                                                  gPatchReg[i].patchName,
                                                  gPatchReg[i].patchVersion));
      }
   }

   // Patch count is included in TGAlert_BotStart (called in OnInit Step 10) to
   // guarantee the ONLINE boot message always arrives first in Telegram (FIFO queue).
   // No separate TG notification here — patch details are in the MT5 Experts journal.
}

// Query: has patch been applied?  Use this in conditional behavior gates.
bool IsPatchApplied(int patchId)
{
   for(int i=0;i<gPatchCount;i++)
      if(gPatchReg[i].patchId==patchId && gPatchReg[i].applied)
         return true;
   return false;
}

// Alternate query by name
bool IsPatchAppliedByName(const string name)
{
   for(int i=0;i<gPatchCount;i++)
      if(gPatchReg[i].patchName==name && gPatchReg[i].applied)
         return true;
   return false;
}

// Count of applied patches
int GetAppliedPatchCount()
{
   int n=0;
   for(int i=0;i<gPatchCount;i++) if(gPatchReg[i].applied) n++;
   return n;
}

// Print full registry to Experts log
void PrintPatchRegistry()
{
   JournalInfo("PatchEngine", StringFormat("══ PATCH REGISTRY v%s  [%d entries] ══",
                                            gCurrentVersion, gPatchCount));
   for(int i=0;i<gPatchCount;i++)
      JournalInfo("PatchEngine",
                  StringFormat("  [%02d] #%03d  %-22s  v%-8s  %s  %s",
                               i+1, gPatchReg[i].patchId,
                               gPatchReg[i].patchName,
                               gPatchReg[i].patchVersion,
                               gPatchReg[i].applied ? "APPLIED" : "PENDING",
                               gPatchReg[i].description));
}

//--------------------------------------------------------------------
// 15.4  BUILT-IN PATCH REGISTRY  (call from OnInit before ApplyPendingPatches)
//        Documents all known P4/P5 compatibility fixes and enhancements
//        shipped with v6.0.  Future out-of-band patches use patchId 10+.
//--------------------------------------------------------------------
void RegisterBuiltInPatches()
{
   InjectPatch(1, "P4_INPUT_COMPAT",    "6.0.1",
               "Remaps P4 wrong input names to P1 actuals via #define shims in P5");

   InjectPatch(2, "PARTIAL_CLOSE_IOC",  "6.0.2",
               "Direct MqlTradeRequest + ORDER_FILLING_IOC for partial close (max compat)");

   InjectPatch(3, "BLACKOUT_HHMM",      "6.0.3",
               "ParseBlackoutWindow parses single HHMM-HHMM string per InpBlackoutWindow1/2/3");

   InjectPatch(4, "PRESET_SPLITLIST",   "6.0.4",
               "SymbolPresetRiskMultiplierV2 uses InpPresetScalpList+InpPresetModerateList");

   InjectPatch(5, "COOLDOWN_INPUTS",    "6.0.5",
               "LossCooldownSeconds_v2 reads InpLossStreakCooldown1/2/3Sec inputs");

   InjectPatch(6, "SAFETYLOCK_HYSTER",  "6.0.6",
               "Global DD lock uses 50% hysteresis release (gSafety.globalDDHysteresisPct)");

   InjectPatch(7, "SCALP_TSL_TIER3",   "6.0.7",
               "Scalp TSL three-tier profit lock R1=0.60 R2=0.90 R3=1.20 from inputs");

   InjectPatch(8, "HTML_TELEGRAM",      "6.0.8",
               "Telegram uses HTML parse_mode instead of MarkdownV2 for simpler escaping");

   InjectPatch(9, "PORTFOLIO_PERSIST",  "6.0.9",
               "Portfolio indicator handles created once in ParseWatchlistCSV (not per scan)");
}

//====================================================================
// ╔═══════════════════════════════════════════════════════════════╗
// ║   Supplemental helper: RegimeToString()                       ║
// ║   (define here if not already present in P2/P3/P5)            ║
// ║   If duplicate symbol error on assembly, remove this block.  ║
// ╚═══════════════════════════════════════════════════════════════╝
//====================================================================
#ifndef REGIME_TO_STRING_DEFINED
#define REGIME_TO_STRING_DEFINED
string RegimeToString(ENUM_MARKET_REGIME r)
{
   switch(r)
   {
      case REGIME_QUIET:     return "QUIET";
      case REGIME_NORMAL:    return "NORMAL";
      case REGIME_EXPLOSIVE: return "EXPLOSIVE";
      case REGIME_HOSTILE:   return "HOSTILE";
      default:               return "UNKNOWN";
   }
}
#endif

//====================================================================
//  ENGINE 16 — WEBVIEW2 LIVE DASHBOARD (HTML + JSON Writer)
//
//  Architecture:
//    1. WriteWebViewHTML()   — writes sk_dashboard.html ONCE at boot
//       (self-contained HTML/CSS/JS — auto-loads JSON every 1s)
//    2. WriteWebViewJSON()   — writes sk_dashboard_data.js every OnTimer
//       (JS variable: window.SK_DATA = {...}  — loaded via <script> tag injection)
//    3. UIRenderBasicCCanvas() — lightweight CCanvas overlay on chart
//       (shows Mode, Score, Signal, Spread, BSP, Events bar, Pause button)
//
//  The HTML file auto-refreshes data via dynamic <script> injection
//  (works on file:// protocol — no CORS, no server needed).
//  User opens: MQL5/Files/sk_dashboard.html in any browser.
//====================================================================

// Dashboard HTML+JSON file paths (relative to MQL5\Files\)
#define WEBVIEW_HTML_FILE   "sk_dashboard.html"
#define WEBVIEW_JSON_FILE   "sk_dashboard_data.js"

// Write timestamp for rate-limiting JSON writes
datetime gWebViewLastWrite = 0;

//--------------------------------------------------------------------
// 16.1  JSON DATA WRITER
//       Writes the current EA state as a JS variable file.
//       Called from OnTimer every InpWebViewRefreshMs interval.
//--------------------------------------------------------------------
void WriteWebViewJSON()
{
   if(!InpWebViewDash) return;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;   // filesystem write restricted in tester (ERR=5002)

   datetime now = TimeLocal();
   // v6.3f FIX: was (int)(now-gWebViewLastWrite)*1000 — on first call gWebViewLastWrite=0
   // so elapsed = ~1.7e9, cast to int then *1000 overflows int32 → negative → always < refreshMs
   // → early return every tick → file NEVER written.  Use long arithmetic, no overflow.
   if(gWebViewLastWrite > 0 && (long)(now - gWebViewLastWrite) * 1000L < (long)InpWebViewRefreshMs) return;
   gWebViewLastWrite = now;

   // ── Build JSON string ─────────────────────────────────────────
   MqlDateTime dt; TimeToStruct(now, dt);
   string ts = StringFormat("%04d-%02d-%02d %02d:%02d:%02d",
                             dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double margin   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double spread   = (SymbolInfoDouble(gSymbol, SYMBOL_ASK) -
                      SymbolInfoDouble(gSymbol, SYMBOL_BID)) / gPoint;

   // Count active positions
   int openTrades  = 0;
   double floatPnL = 0.0;
   for(int i = 0; i < 100; i++)
   {
      if(!gRec[i].active) continue;
      openTrades++;
      if(PositionSelectByTicket(gRec[i].ticket))
         floatPnL += PositionGetDouble(POSITION_PROFIT);
   }

   // Safety lock flags — individual + aggregate
   bool lkSpread    = gSafety.lockSpread;
   bool lkEquity    = gSafety.lockEquityFloor;
   bool lkDailyLoss = gSafety.lockDailyLoss || gSafety.lockGlobalDD;
   bool lkCooldown  = (gConsecLosses >= InpMaxConsecLosses);
   bool lkBroker    = !gTGConnOK;
   bool lkStale     = gSafety.lockStaleData;
   bool anyLocked   = (lkSpread || lkEquity || lkDailyLoss || lkCooldown ||
                       lkBroker || lkStale  ||
                       gSafety.lockSpike || gSafety.lockNews ||
                       gSafety.lockManualPause);

   // Extra status flags
   bool   volMomOk  = (gLastBias == BIAS_BULL) ? gVolMom.bullConfirmed
                                               : gVolMom.bearConfirmed;
   double ddUsedPct = (AccountInfoDouble(ACCOUNT_BALANCE) > 0)
                      ? (MathAbs(gDailyClosedPnL) /
                         AccountInfoDouble(ACCOUNT_BALANCE) * 100.0) : 0.0;

   // Mode label
   string modeStr = (gBotMode == BOT_MODE_HFT) ? "HFT" :
                    (gBotMode == BOT_MODE_SCALPING) ? "SCALPING" : "MODERATE";

   // Score label
   string scoreLabel;
   int sc = gLastScore;
   if(sc >= 88)     scoreLabel = "EXTREME";
   else if(sc >= 78) scoreLabel = "STRONG";
   else if(sc >= 68) scoreLabel = "PASS";
   else if(sc >= 62) scoreLabel = "PASS-MOD";
   else if(sc >= 52) scoreLabel = "PASS-HFT";
   else              scoreLabel = "FAIL";

   string biasStr = (gLastBias == BIAS_BULL) ? "BUY" :
                    (gLastBias == BIAS_BEAR) ? "SELL" : "NEUTRAL";

   string regimeStr = RegimeToString(gRegime.regime);

   // Build event log JSON array
   string evtArr = "[";
   for(int i = 0; i < 8; i++)
   {
      if(gEAEventLog[i] == "") break;
      evtArr += "\"" + gEAEventLog[i] + "\"";
      if(i < 7 && gEAEventLog[i+1] != "") evtArr += ",";
   }
   evtArr += "]";

   // Score components
   string scArr = StringFormat("[%d,%d,%d,%d,%d,%d,%d,%d]",
                                gScoreComp[0], gScoreComp[1], gScoreComp[2], gScoreComp[3],
                                gScoreComp[4], gScoreComp[5], gScoreComp[6], gScoreComp[7]);

   // ── Build trade slot JSON objects ──────────────────────────────────
   string tradeSlots = "";
   int slotIdx = 0;
   for(int i = 0; i < 100 && slotIdx < 20; i++)
   {
      if(!gRec[i].active) continue;
      if(!PositionSelectByTicket(gRec[i].ticket)) continue;
      string tType = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double tPnl  = PositionGetDouble(POSITION_PROFIT);
      double tLot  = PositionGetDouble(POSITION_VOLUME);
      string tSym  = PositionGetString(POSITION_SYMBOL);
      tradeSlots += StringFormat(
         ",\"trade_%d\":{\"type\":\"%s\",\"sym\":\"%s\",\"lot\":%.2f,\"pnl\":%.2f}",
         slotIdx, tType, tSym, tLot, tPnl);
      slotIdx++;
   }

   string verStr    = GetVersionString();        // v6.3e: version field in JSON
   string sessName  = GetSessionName();          // v6.3e: trading session label
   int    upSec2    = (int)(TimeLocal() - gInitTime); // v6.3e: EA uptime seconds

   // ── Split JSON into 3 StringFormat calls (MQL5 limit ≤64 total args) ────
   // Part A: identity + score + account (20 format specs)
   string jsonA = StringFormat(
      "window.SK_DATA = {\n"
      "  \"ts\":\"%s\",\n"
      "  \"symbol\":\"%s\",\n"
      "  \"mode\":\"%s\",\n"
      "  \"riskProfile\":\"%s\",\n"
      "  \"subMode\":\"%s\",\n"
      "  \"version\":\"%s\",\n"
      "  \"session\":\"%s\",\n"
      "  \"uptimeSec\":%d,\n"
      "  \"score\":%d,\n"
      "  \"scoreLabel\":\"%s\",\n"
      "  \"scoreComponents\":%s,\n"
      "  \"bias\":\"%s\",\n"
      "  \"regime\":\"%s\",\n"
      "  \"equity\":%.2f,\n"
      "  \"balance\":%.2f,\n"
      "  \"freeMargin\":%.2f,\n"
      "  \"floatPnL\":%.2f,\n"
      "  \"dailyPnL\":%.2f,\n"
      "  \"dd\":%.2f,\n"
      "  \"ddLimit\":%.1f,\n"
      "  \"digits\":%d,\n",
      ts, gSymbol, modeStr, RiskProfileName(gActiveRiskProfile), SubModeName(),
      verStr, sessName, upSec2,
      gLastScore, scoreLabel, scArr, biasStr, regimeStr,
      equity, balance, margin, floatPnL, gDailyClosedPnL,
      ddUsedPct, (double)InpMaxDailyLossPercent,
      gDigits
   );
   // Part B: BSP + lock flags (22 format specs)
   string jsonB = StringFormat(
      "  \"openTrades\":%d,\n"
      "  \"spread\":%.1f,\n"
      "  \"consecLosses\":%d,\n"
      "  \"consecWins\":%d,\n"
      "  \"bspBuy\":%.1f,\n"
      "  \"bspSell\":%.1f,\n"
      "  \"bspLabel\":\"%s\",\n"
      "  \"bspM1\":%.1f,\n"
      "  \"bspM3\":%.1f,\n"
      "  \"bspM5\":%.1f,\n"
      "  \"bspM6\":%.1f,\n"
      "  \"bspH1\":%.1f,\n"
      "  \"bspH4\":%.1f,\n"
      "  \"hftBspBuy\":%.1f,\n"
      "  \"hftBspSell\":%.1f,\n"
      "  \"tickFlowBull\":%.2f,\n"
      "  \"spikeActive\":%s,\n"
      "  \"newsActive\":%s,\n"
      "  \"paused\":%s,\n"
      "  \"anyLocked\":%s,\n"
      "  \"lockSpread\":%s,\n"
      "  \"lockEquity\":%s,\n",
      openTrades, spread, gConsecLosses, gConsecWins,
      gBSP.buyPct, gBSP.sellPct, gBSP.label,
      gBSP.buyPctM1, gBSP.buyPctM3, gBSP.buyPctM5, gBSP.buyPctM6,
      gBSP.buyPctH1, gBSP.buyPctH4,
      gBSP.hftBuyPct, gBSP.hftSellPct, gBSP.tickFlowBull,
      gSpike.spikeActive ? "true" : "false",
      gNews.active ? "true" : "false",
      gBotPaused    ? "true" : "false",
      anyLocked     ? "true" : "false",
      lkSpread      ? "true" : "false",
      lkEquity      ? "true" : "false"
   );
   // Part C: remaining locks + perf + trades (22 format specs + tradeSlots)
   string jsonC = StringFormat(
      "  \"lockDailyLoss\":%s,\n"
      "  \"lockCooldown\":%s,\n"
      "  \"lockBroker\":%s,\n"
      "  \"lockStale\":%s,\n"
      "  \"lockReason\":\"%s\",\n"
      "  \"lastBlockGate\":\"%s\",\n"
      "  \"lastBlockReason\":\"%s\",\n"
      "  \"tgSent\":%d,\n"
      "  \"tgDropped\":%d,\n"
      "  \"usePivot\":%s,\n"
      "  \"volMomOk\":%s,\n"
      "  \"pipSize\":%.5f,\n"
      "  \"pipValue\":%.4f,\n"
      "  \"pipLabel\":\"%s\",\n"
      "  \"hftTickRate\":%.1f,\n"
      "  \"hftFlowBull\":%.2f,\n"
      "  \"events\":%s,\n"
      "  \"totalTrades\":%d,\n"
      "  \"winTrades\":%d,\n"
      "  \"lossTrades\":%d,\n"
      "  \"winRate\":%.1f%s\n",
      lkDailyLoss  ? "true" : "false",
      lkCooldown   ? "true" : "false",
      lkBroker     ? "true" : "false",
      lkStale      ? "true" : "false",
      anyLocked ? gLastBlockReason : "NONE",
      gLastBlockGate, gLastBlockReason,
      gTGTotalSent, gTGDropped,
      gRt_UsePivot ? "true" : "false",
      volMomOk     ? "true" : "false",
      gPipSize, gPipValue, gPipDigitLabel,
      gHFTTickRate, gHFTOrderFlowBull,
      evtArr,
      gPerf.totalTrades, gPerf.winTrades, gPerf.lossTrades,
      gPerf.totalTrades > 0 ? (gPerf.winTrades * 100.0 / gPerf.totalTrades) : 0.0,
      tradeSlots
   );

   // ── Part D: Indicator values — built via direct concat (no StringFormat args) ──
   // v6.3f: EMA9/34, RSI, ATR per TF; MACD+BB for H1. Empty value returns 0.
   // MQL5: (fn)(args) treated as cast — use fn(args) directly
   #define IND_V(fn, tf, sh) (fn((tf),(sh))==EMPTY_VALUE ? 0.0 : fn((tf),(sh)))
   double bid_now = SymbolInfoDouble(gSymbol, SYMBOL_BID);

   double m1e9   = IND_V(GetEMA9,  IDX_M1,  1);
   double m1e34  = IND_V(GetEMA34, IDX_M1,  1);
   double m1rsi  = IND_V(GetRSI,   IDX_M1,  1);
   double m1atr  = IND_V(GetATR,   IDX_M1,  1);

   double m5e9   = IND_V(GetEMA9,  IDX_M5,  1);
   double m5e34  = IND_V(GetEMA34, IDX_M5,  1);
   double m5rsi  = IND_V(GetRSI,   IDX_M5,  1);
   double m5atr  = IND_V(GetATR,   IDX_M5,  1);

   double m15e9  = IND_V(GetEMA9,  IDX_M15, 1);
   double m15e34 = IND_V(GetEMA34, IDX_M15, 1);

   double h1e9   = IND_V(GetEMA9,     IDX_H1, 1);
   double h1e34  = IND_V(GetEMA34,    IDX_H1, 1);
   double h1rsi  = IND_V(GetRSI,      IDX_H1, 1);
   double h1macd = IND_V(GetMACDMain, IDX_H1, 1);
   double h1bbm  = IND_V(GetBBMid,    IDX_H1, 1);
   double h1bbu  = IND_V(GetBBUpper,  IDX_H1, 1);
   double h1bbl  = IND_V(GetBBLower,  IDX_H1, 1);
   double h1atr  = IND_V(GetATR,      IDX_H1, 1);
   #undef IND_V

   string jsonInd =
      "  ,\"ind\":{\n"
      "    \"bid\":"    + DoubleToString(bid_now, gDigits) + ",\n"
      "    \"m1\":{"
         "\"ema9\":"    + DoubleToString(m1e9,  gDigits) +
         ",\"ema34\":"  + DoubleToString(m1e34, gDigits) +
         ",\"rsi\":"    + DoubleToString(m1rsi, 2) +
         ",\"atr\":"    + DoubleToString(m1atr, gDigits) + "},\n"
      "    \"m5\":{"
         "\"ema9\":"    + DoubleToString(m5e9,  gDigits) +
         ",\"ema34\":"  + DoubleToString(m5e34, gDigits) +
         ",\"rsi\":"    + DoubleToString(m5rsi, 2) +
         ",\"atr\":"    + DoubleToString(m5atr, gDigits) + "},\n"
      "    \"m15\":{"
         "\"ema9\":"    + DoubleToString(m15e9,  gDigits) +
         ",\"ema34\":"  + DoubleToString(m15e34, gDigits) + "},\n"
      "    \"h1\":{"
         "\"ema9\":"    + DoubleToString(h1e9,   gDigits) +
         ",\"ema34\":"  + DoubleToString(h1e34,  gDigits) +
         ",\"rsi\":"    + DoubleToString(h1rsi,  2) +
         ",\"macd\":"   + DoubleToString(h1macd, gDigits+1) +
         ",\"bbmid\":"  + DoubleToString(h1bbm,  gDigits) +
         ",\"bbupper\":" + DoubleToString(h1bbu, gDigits) +
         ",\"bblower\":" + DoubleToString(h1bbl, gDigits) +
         ",\"atr\":"    + DoubleToString(h1atr,  gDigits) + "}\n"
      "  }\n";   // Note: NO closing "};\n" here — jsonExt adds final properties + closing

   // ── Part E: EMA touch / S&R / Pivot / Fib / Pattern (Task 6) ─────
   // H4 and D1 EMA values (extended TF coverage for HTML dashboard)
   #define IV2(fn,tf,sh) (fn((tf),(sh))==EMPTY_VALUE ? 0.0 : fn((tf),(sh)))
   double h4e9   = IV2(GetEMA9,  IDX_H4, 1);
   double h4e34  = IV2(GetEMA34, IDX_H4, 1);
   double h4rsi  = IV2(GetRSI,   IDX_H4, 1);
   double d1e9   = IV2(GetEMA9,  IDX_D1, 1);
   double d1e34  = IV2(GetEMA34, IDX_D1, 1);
   double h1macsig = IV2(GetMACDSig, IDX_H1, 1);
   double h1stk  = IV2(GetStochK,IDX_H1, 1);
   double h1std  = IV2(GetStochD,IDX_H1, 1);
   #undef IV2

   // EMA touch status per TF (true = price within 1×ATR of EMA34)
   double curP   = SymbolInfoDouble(gSymbol, SYMBOL_BID);
   string emaTouchM5  = (m5e34 > 0 && MathAbs(curP - m5e34) <= m5atr) ? "true" : "false";
   string emaTouchH1  = (h1e34 > 0 && MathAbs(curP - h1e34) <= h1atr) ? "true" : "false";

   // Build pivot JSON
   string pvJson = "\"ready\":false";
   if(gPivotD.ready)
      pvJson = StringFormat("\"ready\":true,\"p\":%.5f,\"r1\":%.5f,\"r2\":%.5f,\"r3\":%.5f,\"s1\":%.5f,\"s2\":%.5f,\"s3\":%.5f",
                            gPivotD.pivot,gPivotD.r1,gPivotD.r2,gPivotD.r3,gPivotD.s1,gPivotD.s2,gPivotD.s3);

   // Build fib JSON
   string fibJson = "\"valid\":false";
   if(gFibMap.valid)
      fibJson = StringFormat("\"valid\":true,\"high\":%.5f,\"low\":%.5f,\"bias\":%d,\"r236\":%.5f,\"r382\":%.5f,\"r500\":%.5f,\"r618\":%.5f,\"r786\":%.5f,\"ext1272\":%.5f,\"ext1618\":%.5f",
                             gFibMap.swingHigh,gFibMap.swingLow,(int)gFibMap.swingBias,
                             gFibMap.r236,gFibMap.r382,gFibMap.r500,gFibMap.r618,gFibMap.r786,
                             gFibMap.ext1272,gFibMap.ext1618);

   // Build pattern JSON
   string patJson = StringFormat("\"pattern\":%d,\"name\":\"%s\",\"bullish\":%s,\"conf\":%.2f",
                                 (int)gPattern.pattern, gPattern.name,
                                 gPattern.bullish?"true":"false", gPattern.confidence);

   string jsonExt =
      "  ,\"ema\":{\n"
      "    \"m1_bull\":"  + (m1e9  > m1e34  ? "true" : "false") + ","
      "\"m5_bull\":"      + (m5e9  > m5e34  ? "true" : "false") + ","
      "\"m15_bull\":"     + (m15e9 > m15e34 ? "true" : "false") + ","
      "\"h1_bull\":"      + (h1e9  > h1e34  ? "true" : "false") + ","
      "\"h4_bull\":"      + (h4e9  > h4e34  ? "true" : "false") + ","
      "\"d1_bull\":"      + (d1e9  > d1e34  ? "true" : "false") + ",\n"
      "    \"h4_e9\":"    + DoubleToString(h4e9,  gDigits) + ","
      "\"h4_e34\":"       + DoubleToString(h4e34, gDigits) + ","
      "\"h4_rsi\":"       + DoubleToString(h4rsi, 2) + ","
      "\"d1_e9\":"        + DoubleToString(d1e9,  gDigits) + ","
      "\"d1_e34\":"       + DoubleToString(d1e34, gDigits) + ",\n"
      "    \"touch_m5\":" + emaTouchM5 + ","
      "\"touch_h1\":"     + emaTouchH1 + ",\n"
      "    \"h1_macsig\":" + DoubleToString(h1macsig, gDigits+1) + ","
      "\"h1_stk\":"        + DoubleToString(h1stk, 2) + ","
      "\"h1_std\":"        + DoubleToString(h1std, 2)
      + "\n  },\n"
      "  \"pivot\":{" + pvJson + "},\n"
      "  \"fib\":{"   + fibJson + "},\n"
      "  \"pattern\":{" + patJson + "}\n"
      "};\n";   // Close window.SK_DATA = { ... };

   string json = jsonA + jsonB + jsonC + jsonInd + jsonExt;

   // v6.3f FIX: FILE_TXT alone writes UTF-16 LE + BOM — browsers cannot execute that as JS.
   //   FILE_ANSI = single-byte ASCII, no BOM, correct for JSON/JS files loaded via <script>.
   // v6.3g FIX: Added FILE_SHARE_READ — browser script-loader holds a concurrent read lock
   //   while polling the file every ~1s.  Opening WITHOUT FILE_SHARE_READ fails with ERR_5002
   //   (sharing violation) whenever the browser and MT5 collide on the same file handle.
   //   FILE_SHARE_READ allows MT5 to write while the browser has it open for reading.
   //   The 5ms Sleep before retry yields the scheduler so the OS can flush the browser lock.
   int fh = FileOpen(WEBVIEW_JSON_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(fh == INVALID_HANDLE)
   {
      Sleep(5);   // yield scheduler — let browser release its poll read lock
      fh = FileOpen(WEBVIEW_JSON_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
      if(fh == INVALID_HANDLE)
      {
         JournalWarn("WebView","JSON write failed ERR="+IntegerToString(GetLastError())
                     +"  path="+TerminalInfoString(TERMINAL_DATA_PATH)+"\\MQL5\\Files\\"+WEBVIEW_JSON_FILE);
         return;
      }
   }
   FileWriteString(fh, json);
   FileClose(fh);
}

//--------------------------------------------------------------------
//--------------------------------------------------------------------
// 16.2  HTML DASHBOARD WRITER  v6.2 — Matches dashboard_concepts.html
//       Rich void-black design with cyan accent, score ring, safety pills,
//       trade list, score breakdown, filter toggles, DD footer.
//       Writes sk_dashboard.html ONCE at boot; polls sk_dashboard_data.js
//       every 1 second via dynamic script injection (works on file://).
//--------------------------------------------------------------------
void WriteWebViewHTML()
{
   if(!InpWebViewDash) return;
   if(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)) return;   // filesystem write restricted in tester (ERR=5002)

   // ── Build HTML as multi-line string ─────────────────────────────
   string h = "";

   // HEAD
   h += "<!DOCTYPE html>\n<html lang='en'>\n<head>\n";
   h += "<meta charset='UTF-8'>\n";
   h += "<meta name='viewport' content='width=device-width,initial-scale=1'>\n";
   h += "<title>SK Trade Premium " + GetVersionString() + " — Live Dashboard</title>\n";

   // FONTS
   h += "<link rel='preconnect' href='https://fonts.googleapis.com'>\n";
   h += "<link href='https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700"
        "&family=JetBrains+Mono:wght@400;500;600;700&display=swap' rel='stylesheet'>\n";

   // CSS ──────────────────────────────────────────────────────────────
   h += "<style>\n";
   h += "*{margin:0;padding:0;box-sizing:border-box;}\n";
   h += "body{background:#020208;font-family:'Inter',sans-serif;display:flex;flex-direction:column;"
        "align-items:center;padding:20px 12px 60px;gap:0;min-height:100vh;}\n";
   h += ".dash{width:520px;max-width:100%;background:#05050c;border-radius:14px;"
        "border:1px solid rgba(0,220,255,0.12);overflow:hidden;"
        "box-shadow:0 0 60px rgba(0,220,255,0.05),0 30px 80px rgba(0,0,0,0.95);"
        "font-family:'JetBrains Mono',monospace;}\n";
   h += ".sep{height:1px;background:rgba(255,255,255,0.05);}\n";

   // HEADER
   h += ".p-hdr{background:linear-gradient(135deg,rgba(0,220,255,0.08),rgba(0,80,160,0.04));"
        "padding:11px 14px 9px;display:flex;align-items:center;gap:12px;"
        "border-bottom:1px solid rgba(0,220,255,0.1);}\n";
   h += ".hdr-accent{width:3px;height:36px;border-radius:2px;"
        "background:linear-gradient(180deg,#00dcff,rgba(0,220,255,0.2));flex-shrink:0;}\n";
   h += ".hdr-text{flex:1;}\n";
   h += ".h-name{color:#00dcff;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;}\n";
   h += ".h-sub{color:rgba(0,220,255,0.4);font-size:9px;letter-spacing:1px;margin-top:2px;}\n";
   h += ".h-chip{padding:4px 11px;border-radius:4px;font-size:9px;font-weight:700;letter-spacing:1.5px;"
        "background:rgba(0,220,255,0.1);border:1px solid rgba(0,220,255,0.25);color:#00dcff;}\n";
   h += ".h-chip.hft{background:rgba(255,100,0,0.12);border-color:rgba(255,100,0,0.3);color:#ff8040;}\n";
   h += ".h-chip.scalp{background:rgba(0,220,255,0.1);border-color:rgba(0,220,255,0.25);color:#00dcff;}\n";
   h += ".h-chip.mod{background:rgba(120,60,255,0.12);border-color:rgba(120,60,255,0.3);color:#c080ff;}\n";
   h += ".h-strip{background:rgba(0,0,0,0.3);border-bottom:1px solid rgba(255,255,255,0.04);"
        "padding:5px 14px;display:flex;align-items:center;justify-content:space-between;}\n";
   h += ".hs-l{color:rgba(255,255,255,0.3);font-size:9px;letter-spacing:0.5px;}\n";
   h += ".hs-r{color:rgba(255,255,255,0.25);font-size:9px;}\n";
   h += ".hs-r span{color:rgba(0,220,255,0.6);}\n";

   // GLOBE + TIME (from dashboard_concepts.html — v6.3e)
   h += ".p-globe{background:rgba(0,0,20,0.4);border-bottom:1px solid rgba(0,220,255,0.07);"
        "padding:6px 0 5px;display:flex;flex-direction:column;align-items:center;gap:3px;}\n";
   h += ".globe-wrap{position:relative;width:52px;height:52px;}\n";
   h += ".globe{width:52px;height:52px;border-radius:50%;"
        "background:radial-gradient(circle at 38% 32%,#0a2060 0%,#040e30 50%,#020818 100%);"
        "border:1.5px solid rgba(0,120,255,0.35);"
        "box-shadow:0 0 18px rgba(0,100,255,0.2),inset 0 0 16px rgba(0,0,80,0.6);"
        "position:relative;overflow:hidden;display:flex;align-items:center;justify-content:center;}\n";
   h += ".g-ring{position:absolute;width:100%;height:1px;background:rgba(80,140,255,0.12);}\n";
   h += ".g-ring:nth-child(1){top:30%;transform:scaleX(0.85);}\n";
   h += ".g-ring:nth-child(2){top:50%;}\n";
   h += ".g-ring:nth-child(3){top:70%;transform:scaleX(0.85);}\n";
   h += ".g-mer{position:absolute;width:1px;height:100%;background:rgba(80,140,255,0.1);}\n";
   h += ".g-mer:nth-child(4){left:30%;transform:scaleY(0.9) rotate(15deg);}\n";
   h += ".g-mer:nth-child(5){left:70%;transform:scaleY(0.9) rotate(-15deg);}\n";
   h += ".g-dot{width:6px;height:6px;border-radius:50%;background:#00dcff;"
        "box-shadow:0 0 8px #00dcff;z-index:1;}\n";
   h += ".g-time{color:#00dcff;font-size:11px;font-weight:700;letter-spacing:1px;"
        "text-shadow:0 0 8px rgba(0,220,255,0.5);}\n";
   h += ".g-date{color:rgba(255,255,255,0.25);font-size:8px;letter-spacing:0.8px;}\n";

   h += "#warn-banner{display:none;background:rgba(255,160,0,0.08);"
        "border:1px solid rgba(255,160,0,0.2);padding:6px 14px;"
        "color:#ffa000;font-size:10px;text-align:center;letter-spacing:1px;"
        "animation:blinkwarn 1.2s infinite alternate;}\n";
   h += "@keyframes blinkwarn{from{opacity:.6}to{opacity:1}}\n";

   // ACCOUNT CARDS
   h += ".p-acct{padding:10px 12px 8px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".cards-row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:7px;margin-bottom:8px;}\n";
   h += ".card{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06);"
        "border-radius:9px;padding:8px 10px;position:relative;overflow:hidden;}\n";
   h += ".card::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;}\n";
   h += ".card.equity::before{background:linear-gradient(90deg,#00dcff,rgba(0,220,255,0.3));}\n";
   h += ".card.pnl::before{background:linear-gradient(90deg,#00ff88,rgba(0,255,136,0.3));}\n";
   h += ".card.dd::before{background:linear-gradient(90deg,#ff6030,rgba(255,96,48,0.3));}\n";
   h += ".c-lbl{color:rgba(255,255,255,0.25);font-size:8px;letter-spacing:1.5px;text-transform:uppercase;}\n";
   h += ".c-val{color:#fff;font-size:15px;font-weight:700;margin-top:3px;line-height:1;}\n";
   h += ".c-val.cy{color:#00dcff;text-shadow:0 0 8px rgba(0,220,255,0.3);}\n";
   h += ".c-val.gr{color:#00ff88;}\n";
   h += ".c-val.rd{color:#ff4060;}\n";
   h += ".c-val.am{color:#ff8060;}\n";
   h += ".c-sub{color:rgba(255,255,255,0.18);font-size:8px;margin-top:3px;}\n";

   // SPARKLINE
   h += ".sparkline{height:38px;background:rgba(0,220,255,0.02);border-radius:6px;"
        "border:1px solid rgba(0,220,255,0.06);position:relative;overflow:hidden;}\n";
   h += ".spark-lbl{position:absolute;top:4px;left:8px;color:rgba(255,255,255,0.15);"
        "font-size:7px;letter-spacing:1px;text-transform:uppercase;z-index:1;}\n";
   h += ".sparkline svg{width:100%;height:100%;display:block;}\n";

   // SECTION HEADER
   h += ".sec-hdr{color:rgba(255,255,255,0.2);font-size:7px;letter-spacing:2px;"
        "text-transform:uppercase;margin-bottom:6px;display:flex;align-items:center;gap:6px;}\n";
   h += ".sec-hdr::after{content:'';flex:1;height:1px;background:rgba(255,255,255,0.06);}\n";

   // SAFETY PILLS
   h += ".p-safety{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".locks{display:flex;flex-wrap:wrap;gap:4px;}\n";
   h += ".pill{display:flex;align-items:center;gap:4px;padding:3px 8px 3px 5px;"
        "border-radius:20px;font-size:8px;font-weight:600;}\n";
   h += ".dot{width:6px;height:6px;border-radius:50%;flex-shrink:0;}\n";
   h += ".p-ok{background:rgba(0,255,136,0.07);border:1px solid rgba(0,255,136,0.18);"
        "color:rgba(0,255,136,0.8);}\n";
   h += ".p-ok .dot{background:#00ff88;box-shadow:0 0 5px rgba(0,255,136,0.7);}\n";
   h += ".p-warn{background:rgba(255,160,0,0.07);border:1px solid rgba(255,160,0,0.2);"
        "color:rgba(255,160,0,0.9);}\n";
   h += ".p-warn .dot{background:#ffa000;box-shadow:0 0 5px rgba(255,160,0,0.7);}\n";
   h += ".p-lock{background:rgba(255,64,96,0.08);border:1px solid rgba(255,64,96,0.22);"
        "color:rgba(255,80,100,0.9);}\n";
   h += ".p-lock .dot{background:#ff4060;box-shadow:0 0 5px rgba(255,64,96,0.7);}\n";

   // TRADES
   h += ".p-trades{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".trade-row{display:flex;align-items:center;gap:6px;"
        "background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.05);"
        "border-radius:6px;padding:5px 8px;margin-bottom:4px;font-size:10px;}\n";
   h += ".tb{padding:2px 7px;border-radius:3px;font-size:8px;font-weight:700;letter-spacing:1px;}\n";
   h += ".tb-buy{background:rgba(0,255,136,0.12);color:#00ff88;border:1px solid rgba(0,255,136,0.2);}\n";
   h += ".tb-sell{background:rgba(255,64,96,0.12);color:#ff4060;border:1px solid rgba(255,64,96,0.2);}\n";
   h += ".t-sym{color:rgba(255,255,255,0.7);font-weight:700;flex:1;}\n";
   h += ".t-pnl{font-weight:700;}\n";
   h += ".t-pnl.pos{color:#00ff88;} .t-pnl.neg{color:#ff4060;}\n";
   h += ".t-lot{color:rgba(255,255,255,0.3);font-size:8px;}\n";

   // PERFORMANCE
   h += ".p-perf{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".pm-grid{display:flex;gap:10px;margin-bottom:8px;flex-wrap:wrap;}\n";
   h += ".pm{text-align:center;min-width:50px;}\n";
   h += ".pm-v{font-size:14px;font-weight:700;color:#fff;}\n";
   h += ".pm-v.cy{color:#00dcff;} .pm-v.gr{color:#00ff88;} .pm-v.rd{color:#ff4060;} .pm-v.am{color:#ffa000;}\n";
   h += ".pm-l{color:rgba(255,255,255,0.2);font-size:7px;letter-spacing:1px;text-transform:uppercase;margin-top:1px;}\n";
   h += ".pr{display:flex;align-items:center;gap:8px;margin-bottom:5px;}\n";
   h += ".pr-lbl{color:rgba(255,255,255,0.25);font-size:8px;letter-spacing:1px;width:60px;text-transform:uppercase;}\n";
   h += ".pr-trk{flex:1;height:4px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;}\n";
   h += ".pr-fill{height:100%;border-radius:2px;transition:width 0.5s;}\n";
   h += ".f-win{background:linear-gradient(90deg,#00ff88,rgba(0,255,136,0.4));}\n";
   h += ".f-dd{background:linear-gradient(90deg,#ffa000,rgba(255,160,0,0.4));}\n";
   h += ".pr-val{color:rgba(255,255,255,0.6);font-size:9px;font-weight:700;width:46px;text-align:right;}\n";

   // REGIME + SCORE RING
   h += ".p-regime{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);"
        "display:grid;grid-template-columns:1fr 1fr;gap:8px;}\n";
   h += ".regime-box{background:rgba(0,255,136,0.04);border:1px solid rgba(0,255,136,0.15);"
        "border-radius:8px;padding:8px 10px;}\n";
   h += ".regime-box.hostile{background:rgba(255,64,64,0.04);border-color:rgba(255,64,64,0.2);}\n";
   h += ".regime-box.quiet{background:rgba(100,100,100,0.04);border-color:rgba(150,150,150,0.15);}\n";
   h += ".rname{font-size:16px;font-weight:800;letter-spacing:2px;color:#00ff88;}\n";
   h += ".rname.hostile{color:#ff4060;} .rname.quiet{color:#8080a0;} .rname.trend{color:#00dcff;}\n";
   h += ".rsub{color:rgba(0,255,136,0.4);font-size:8px;margin-top:3px;}\n";
   h += ".score-box{background:rgba(0,220,255,0.04);border:1px solid rgba(0,220,255,0.15);"
        "border-radius:8px;padding:8px 10px;display:flex;align-items:center;gap:10px;}\n";
   h += ".sring{position:relative;width:52px;height:52px;flex-shrink:0;}\n";
   h += ".sring svg{width:100%;height:100%;transform:rotate(-90deg);}\n";
   h += ".sctr{position:absolute;inset:0;display:flex;flex-direction:column;"
        "align-items:center;justify-content:center;}\n";
   h += ".snum{color:#00dcff;font-size:18px;font-weight:800;line-height:1;}\n";
   h += ".slbl{color:rgba(0,220,255,0.4);font-size:7px;letter-spacing:1px;text-transform:uppercase;}\n";
   h += ".sbias{padding:3px 8px;border-radius:3px;font-size:9px;font-weight:700;letter-spacing:1px;display:inline-block;}\n";
   h += ".sbias.bull{background:rgba(0,255,136,0.1);color:#00ff88;border:1px solid rgba(0,255,136,0.2);}\n";
   h += ".sbias.bear{background:rgba(255,64,96,0.1);color:#ff4060;border:1px solid rgba(255,64,96,0.2);}\n";
   h += ".sbias.none{background:rgba(255,255,255,0.04);color:rgba(255,255,255,0.3);"
        "border:1px solid rgba(255,255,255,0.08);}\n";
   h += ".tf-row{display:flex;gap:3px;margin-top:5px;}\n";
   h += ".tf-pip{flex:1;height:14px;border-radius:2px;display:flex;align-items:center;"
        "justify-content:center;font-size:7px;font-weight:700;}\n";
   h += ".tf-pip.u{background:rgba(0,255,136,0.12);color:#00ff88;border:1px solid rgba(0,255,136,0.2);}\n";
   h += ".tf-pip.d{background:rgba(255,64,96,0.12);color:#ff4060;border:1px solid rgba(255,64,96,0.2);}\n";
   h += ".tf-pip.n{background:rgba(255,255,255,0.04);color:rgba(255,255,255,0.25);"
        "border:1px solid rgba(255,255,255,0.07);}\n";
   h += ".tf-names{display:flex;gap:3px;margin-top:2px;}\n";
   h += ".tf-nl{flex:1;text-align:center;color:rgba(255,255,255,0.2);font-size:6px;}\n";

   // SCORE BREAKDOWN
   h += ".p-score{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".sb-row{display:flex;align-items:center;gap:8px;margin-bottom:3px;}\n";
   h += ".sb-name{color:rgba(255,255,255,0.35);font-size:8px;width:130px;}\n";
   h += ".sb-trk{flex:1;height:3px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;}\n";
   h += ".sb-fill{height:100%;border-radius:2px;background:linear-gradient(90deg,#00dcff,rgba(0,220,255,0.4));transition:width 0.5s;}\n";
   h += ".sb-fill.neg{background:linear-gradient(90deg,#ff4060,rgba(255,64,96,0.4));}\n";
   h += ".sb-val{color:rgba(0,220,255,0.8);font-size:8px;font-weight:700;width:28px;text-align:right;}\n";
   h += ".sb-val.neg{color:rgba(255,64,96,0.8);}\n";

   // INDICATOR VALUES PANEL (v6.3f)
   h += ".p-ind{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".ind-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:5px;}\n";
   h += ".ind-block{background:rgba(0,220,255,0.03);border:1px solid rgba(0,220,255,0.07);"
        "border-radius:6px;padding:5px 7px;}\n";
   h += ".ind-tf{color:rgba(0,220,255,0.5);font-size:7px;font-weight:700;letter-spacing:1px;"
        "margin-bottom:3px;}\n";
   h += ".ind-row{display:flex;justify-content:space-between;align-items:center;"
        "margin-bottom:2px;}\n";
   h += ".ind-lbl{color:rgba(255,255,255,0.3);font-size:8px;}\n";
   h += ".ind-val{color:#00dcff;font-size:8px;font-weight:700;font-family:monospace;}\n";
   h += ".ind-mkt{display:flex;justify-content:space-between;align-items:center;"
        "margin-bottom:5px;padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.04);}\n";
   h += ".ind-mkt-price{color:#fff;font-size:12px;font-weight:700;font-family:monospace;}\n";
   h += ".ind-mkt-label{color:rgba(255,255,255,0.25);font-size:8px;}\n";
   h += ".ind-above{color:rgba(0,255,136,0.8);} .ind-below{color:rgba(255,64,96,0.7);}\n";

   // EMA / PIVOT / FIB / PATTERN ZONES PANEL (v6.3g — Task 6)
   h += ".p-zones{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".z-hdr{font:600 8px 'Inter',sans-serif;letter-spacing:0.08em;color:rgba(0,220,255,0.5);"
        "text-transform:uppercase;margin-bottom:4px;}\n";
   h += ".z-cols{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:6px;}\n";
   h += ".ema-bar{display:flex;gap:3px;}\n";
   h += ".ema-tf{display:flex;flex-direction:column;align-items:center;flex:1;padding:3px 1px;"
        "border-radius:3px;font-size:7px;font-family:monospace;}\n";
   h += ".ema-tf.bull{background:rgba(0,255,136,0.12);color:#00ff88;}\n";
   h += ".ema-tf.bear{background:rgba(255,64,96,0.12);color:#ff4060;}\n";
   h += ".ema-tf.neut{background:rgba(255,255,255,0.03);color:rgba(255,255,255,0.25);}\n";
   h += ".ema-tf-arr{font-size:9px;line-height:1;}\n";
   h += ".touch-row{display:flex;gap:5px;margin-top:3px;}\n";
   h += ".tpill{padding:2px 6px;border-radius:9px;font-size:7px;font-weight:700;}\n";
   h += ".ton{background:rgba(0,220,255,0.15);color:#00dcff;}\n";
   h += ".toff{background:rgba(255,255,255,0.03);color:rgba(255,255,255,0.22);}\n";
   h += ".pat-card{display:flex;align-items:center;gap:6px;padding:5px 6px;"
        "background:rgba(255,255,255,0.03);border-radius:4px;}\n";
   h += ".pat-name{font:700 9px monospace;flex:1;}\n";
   h += ".pat-bull{color:#00ff88;} .pat-bear{color:#ff4060;} .pat-none{color:rgba(255,255,255,0.25);}\n";
   h += ".conf-bar{height:4px;border-radius:2px;background:rgba(255,255,255,0.06);"
        "width:50px;overflow:hidden;flex-shrink:0;}\n";
   h += ".conf-fill{height:100%;background:linear-gradient(90deg,#00dcff,rgba(0,220,255,0.4));}\n";
   h += ".piv-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:2px;}\n";
   h += ".pc{padding:3px 2px;border-radius:2px;font:8px monospace;text-align:center;}\n";
   h += ".pc-r{background:rgba(0,255,136,0.06);color:#7dff9e;}\n";
   h += ".pc-p{background:rgba(0,220,255,0.10);color:#00dcff;font-weight:700;}\n";
   h += ".pc-s{background:rgba(255,64,96,0.06);color:#ff8080;}\n";
   h += ".pc-hi{outline:1px solid rgba(0,220,255,0.4);}\n";
   h += ".fib-list{display:grid;grid-template-columns:repeat(3,1fr) repeat(2,1fr);gap:2px;}\n";
   h += ".fr{padding:2px 4px;border-radius:2px;display:flex;justify-content:space-between;"
        "font:8px monospace;}\n";
   h += ".fr-ret{color:rgba(255,255,255,0.45);}\n";
   h += ".fr-ext{color:rgba(255,200,0,0.65);background:rgba(255,200,0,0.05);}\n";
   h += ".fr-near{background:rgba(0,220,255,0.10);color:#00dcff;outline:1px solid rgba(0,220,255,0.3);}\n";

   // FILTERS
   h += ".p-filters{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".flt-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:4px;margin-bottom:4px;}\n";
   h += ".ftog{padding:5px 4px;border-radius:6px;text-align:center;font-size:8px;"
        "font-weight:600;display:flex;flex-direction:column;align-items:center;gap:2px;}\n";
   h += ".fton{background:rgba(0,220,255,0.07);border:1px solid rgba(0,220,255,0.18);"
        "color:rgba(0,220,255,0.85);}\n";
   h += ".ftoff{background:rgba(255,255,255,0.02);border:1px solid rgba(255,255,255,0.06);"
        "color:rgba(255,255,255,0.2);}\n";
   h += ".ft-ic{font-size:11px;}\n";
   h += ".ft-st{font-size:7px;}\n";
   h += ".fton .ft-st{color:rgba(0,255,136,0.7);} .ftoff .ft-st{color:rgba(255,64,96,0.5);}\n";
   h += ".news-inline{display:flex;gap:8px;align-items:center;margin-bottom:6px;flex-wrap:wrap;}\n";
   h += ".nchip{padding:4px 10px;border-radius:4px;font-size:9px;font-weight:700;}\n";
   h += ".nc-ok{background:rgba(0,255,136,0.07);border:1px solid rgba(0,255,136,0.15);"
        "color:rgba(0,255,136,0.7);}\n";
   h += ".nc-warn{background:rgba(255,160,0,0.1);border:1px solid rgba(255,160,0,0.25);color:#ffa000;}\n";
   h += ".nc-lock{background:rgba(255,64,96,0.1);border:1px solid rgba(255,64,96,0.25);color:#ff4060;}\n";

   // EVENTS LOG
   h += ".p-events{padding:8px 12px;border-bottom:1px solid rgba(255,255,255,0.05);}\n";
   h += ".ev-row{font-size:9px;padding:3px 0;border-bottom:1px solid rgba(255,255,255,0.04);"
        "color:rgba(255,255,255,0.4);line-height:1.5;}\n";
   h += ".ev-block{color:#ffa000;} .ev-trade{color:#00ff88;} .ev-lock{color:#ff4060;}\n";
   h += ".ev-info{color:rgba(0,220,255,0.6);}\n";

   // FOOTER
   h += ".p-footer{padding:6px 12px 8px;border-top:1px solid rgba(255,255,255,0.04);"
        "background:rgba(0,0,0,0.3);}\n";
   h += ".dd-row{display:flex;align-items:center;gap:8px;margin-bottom:4px;}\n";
   h += ".dd-lbl{color:rgba(255,255,255,0.2);font-size:7px;letter-spacing:1.5px;text-transform:uppercase;}\n";
   h += ".dd-trk{flex:1;height:3px;background:rgba(255,255,255,0.06);border-radius:2px;overflow:hidden;}\n";
   h += ".dd-fill{height:100%;border-radius:2px;transition:width 0.5s;}\n";
   h += ".dd-low{background:linear-gradient(90deg,#00ff88,#00dcff);}\n";
   h += ".dd-mid{background:linear-gradient(90deg,#ffa000,#ff6030);}\n";
   h += ".dd-high{background:linear-gradient(90deg,#ff4060,#ff2040);}\n";
   h += ".dd-val{color:rgba(0,220,255,0.6);font-size:8px;font-weight:700;}\n";
   h += ".meta-strip{display:flex;justify-content:space-between;}\n";
   h += ".meta-item{color:rgba(255,255,255,0.12);font-size:7px;}\n";

   // STATUS: no data / offline
   h += "#no-data{display:none;padding:20px;text-align:center;"
        "color:rgba(255,160,0,0.6);font-size:11px;}\n";
   h += "</style>\n";

   // BODY HTML ────────────────────────────────────────────────────────
   h += "</head>\n<body>\n";
   h += "<div class='dash'>\n";

   // ── Panel 1: Header ──────────────────────────────────────────────
   h += "<div class='p-hdr'>\n";
   h += "  <div class='hdr-accent'></div>\n";
   h += "  <div class='hdr-text'>\n";
   h += "    <div class='h-name'>SK Trade Premium</div>\n";
   h += "    <div class='h-sub' id='h-sub'>" + GetVersionString() + " &middot; Loading...</div>\n";
   h += "  </div>\n";
   h += "  <div id='mode-chip' class='h-chip'>---</div>\n";
   h += "</div>\n";
   h += "<div class='h-strip'>\n";
   h += "  <span class='hs-l'>&#x1F550; <span id='htime' style='color:rgba(0,220,255,0.7)'>--:--:--</span>"
        " &nbsp;|&nbsp; <span id='huptime'>-</span></span>\n";
   h += "  <span class='hs-r'>TG: <span id='htg'>-</span> &nbsp;|&nbsp; R: <span id='hrend'>-</span></span>\n";
   h += "</div>\n";
   h += "<div id='warn-banner'>&#x23F8; BOT PAUSED &mdash; TRADING SUSPENDED</div>\n";

   // ── Globe + Time panel (v6.3e: from dashboard_concepts.html) ─────
   h += "<div class='p-globe'>\n";
   h += "  <div class='globe-wrap'>\n";
   h += "    <div class='globe'>\n";
   h += "      <div class='g-ring'></div>\n";
   h += "      <div class='g-ring'></div>\n";
   h += "      <div class='g-ring'></div>\n";
   h += "      <div class='g-mer'></div>\n";
   h += "      <div class='g-mer'></div>\n";
   h += "      <div class='g-dot'></div>\n";
   h += "    </div>\n";
   h += "  </div>\n";
   h += "  <div class='g-time' id='g-time'>--:--:-- UTC</div>\n";
   h += "  <div class='g-date' id='g-date'>--- &middot; ---</div>\n";
   h += "</div>\n";

   // ── Panel 2: Account cards ────────────────────────────────────────
   h += "<div class='p-acct'>\n";
   h += "  <div class='cards-row'>\n";
   h += "    <div class='card equity'><div class='c-lbl'>Equity</div>"
        "<div class='c-val cy' id='eq'>---</div><div class='c-sub' id='bal'>Bal ---</div></div>\n";
   h += "    <div class='card pnl'><div class='c-lbl'>Daily P&amp;L</div>"
        "<div class='c-val' id='dpnl'>---</div><div class='c-sub' id='dpnlp'>---</div></div>\n";
   h += "    <div class='card dd'><div class='c-lbl'>DD Used</div>"
        "<div class='c-val am' id='ddpct'>---</div><div class='c-sub' id='ddlim'>Limit ---</div></div>\n";
   h += "  </div>\n";
   h += "  <div class='sparkline'><div class='spark-lbl'>Equity curve</div>"
        "<svg id='spark-svg' viewBox='0 0 496 38' preserveAspectRatio='none'>"
        "<defs><linearGradient id='sg' x1='0' y1='0' x2='0' y2='1'>"
        "<stop offset='0%' stop-color='#00dcff' stop-opacity='0.25'/>"
        "<stop offset='100%' stop-color='#00dcff' stop-opacity='0'/></linearGradient></defs>"
        "<path id='spark-area' fill='url(#sg)'/>"
        "<path id='spark-line' fill='none' stroke='#00dcff' stroke-width='1.5' opacity='0.8'/>"
        "<circle id='spark-dot' r='2.5' fill='#00dcff' opacity='0.9'/>"
        "</svg></div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 3: Safety vault ─────────────────────────────────────────
   h += "<div class='p-safety'>\n";
   h += "  <div class='sec-hdr'>Safety Vault</div>\n";
   h += "  <div class='locks' id='locks'>Loading...</div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 4: Active trades ────────────────────────────────────────
   h += "<div class='p-trades'>\n";
   h += "  <div class='sec-hdr'>Active Trades (<span id='n-trades'>0</span>)</div>\n";
   h += "  <div id='trade-list'><div style='color:rgba(255,255,255,0.2);font-size:9px;'>No open positions</div></div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 5: Performance ──────────────────────────────────────────
   h += "<div class='p-perf'>\n";
   h += "  <div class='sec-hdr'>Performance</div>\n";
   h += "  <div class='pm-grid'>\n";
   h += "    <div class='pm'><div class='pm-v gr' id='pm-w'>-</div><div class='pm-l'>Wins</div></div>\n";
   h += "    <div class='pm'><div class='pm-v rd' id='pm-l'>-</div><div class='pm-l'>Losses</div></div>\n";
   h += "    <div class='pm'><div class='pm-v cy' id='pm-wr'>-</div><div class='pm-l'>Win Rate</div></div>\n";
   h += "    <div class='pm'><div class='pm-v cy' id='pm-streak'>-</div><div class='pm-l'>Streak</div></div>\n";
   h += "    <div class='pm'><div class='pm-v am' id='pm-dd'>-</div><div class='pm-l'>Max DD</div></div>\n";
   h += "    <div class='pm'><div class='pm-v gr' id='pm-dpnl'>-</div><div class='pm-l'>Day P&amp;L</div></div>\n";
   h += "  </div>\n";
   h += "  <div class='pr'><div class='pr-lbl'>Win Rate</div>"
        "<div class='pr-trk'><div class='pr-fill f-win' id='bar-wr' style='width:0%'></div></div>"
        "<div class='pr-val' id='pv-wr' style='color:#00ff88'>0%</div></div>\n";
   h += "  <div class='pr'><div class='pr-lbl'>Daily DD</div>"
        "<div class='pr-trk'><div class='pr-fill f-dd' id='bar-dd' style='width:0%'></div></div>"
        "<div class='pr-val' id='pv-dd' style='color:#ffa000'>0%</div></div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 6: Regime + Score ring ──────────────────────────────────
   h += "<div class='p-regime'>\n";
   h += "  <div class='regime-box' id='regime-box'>\n";
   h += "    <div class='sec-hdr' style='margin-bottom:5px;'>Regime</div>\n";
   h += "    <div class='rname' id='rname'>---</div>\n";
   h += "    <div class='rsub' id='rsub'>---</div>\n";
   h += "  </div>\n";
   h += "  <div class='score-box'>\n";
   h += "    <div class='sring'>\n";
   h += "      <svg viewBox='0 0 52 52'>\n";
   h += "        <circle cx='26' cy='26' r='20' fill='none' stroke='rgba(0,220,255,0.1)' stroke-width='5'/>\n";
   h += "        <circle id='score-arc' cx='26' cy='26' r='20' fill='none' stroke='#00dcff'"
        " stroke-width='5' stroke-dasharray='0 126' stroke-linecap='round' opacity='0.9'/>\n";
   h += "      </svg>\n";
   h += "      <div class='sctr'><div class='snum' id='score-num'>0</div>"
        "<div class='slbl' id='score-lbl'>SCORE</div></div>\n";
   h += "    </div>\n";
   h += "    <div style='flex:1'>\n";
   h += "      <div class='sbias none' id='bias-badge'>NONE</div>\n";
   h += "      <div class='tf-row' id='tf-row'>\n";
   h += "        <div class='tf-pip n'>M1</div><div class='tf-pip n'>M5</div>"
        "<div class='tf-pip n'>M15</div><div class='tf-pip n'>H1</div>"
        "<div class='tf-pip n'>H4</div><div class='tf-pip n'>D1</div>\n";
   h += "      </div>\n";
   h += "      <div class='tf-names'>\n";
   h += "        <div class='tf-nl'>M1</div><div class='tf-nl'>M5</div><div class='tf-nl'>M15</div>\n";
   h += "        <div class='tf-nl'>H1</div><div class='tf-nl'>H4</div><div class='tf-nl'>D1</div>\n";
   h += "      </div>\n";
   h += "    </div>\n";
   h += "  </div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 7: Score breakdown ───────────────────────────────────────
   h += "<div class='p-score'>\n";
   h += "  <div class='sec-hdr'>Signal Score Breakdown</div>\n";
   h += "  <div id='score-breakdown'>\n";
   h += "    <div class='sb-row'><div class='sb-name'>EMA Cross</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc0' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv0'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>RSI</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc1' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv1'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>MACD</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc2' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv2'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>Bollinger / Pattern</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc3' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv3'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>Stoch / BSP</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc4' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv4'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>Volume Mom / MACD2</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc5' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv5'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>Regime Adj</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc6' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv6'>0</div></div>\n";
   h += "    <div class='sb-row'><div class='sb-name'>Buy/Sell Pressure</div>"
        "<div class='sb-trk'><div class='sb-fill' id='sc7' style='width:0%'></div></div>"
        "<div class='sb-val' id='sv7'>0</div></div>\n";
   h += "  </div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 7b: Indicator values (v6.3f) ────────────────────────────
   h += "<div class='p-ind'>\n";
   h += "  <div class='sec-hdr'>Live Indicator Values</div>\n";
   h += "  <div class='ind-mkt'>\n";
   h += "    <div class='ind-mkt-label'>Market Price</div>\n";
   h += "    <div class='ind-mkt-price' id='ind-bid'>--</div>\n";
   h += "  </div>\n";
   h += "  <div class='ind-grid'>\n";
   // M1 block
   h += "    <div class='ind-block'>\n";
   h += "      <div class='ind-tf'>M1</div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 9</span>"
        "<span class='ind-val' id='i-m1-e9'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 34</span>"
        "<span class='ind-val' id='i-m1-e34'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>RSI</span>"
        "<span class='ind-val' id='i-m1-rsi'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>ATR</span>"
        "<span class='ind-val' id='i-m1-atr'>--</span></div>\n";
   h += "    </div>\n";
   // M5 block
   h += "    <div class='ind-block'>\n";
   h += "      <div class='ind-tf'>M5</div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 9</span>"
        "<span class='ind-val' id='i-m5-e9'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 34</span>"
        "<span class='ind-val' id='i-m5-e34'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>RSI</span>"
        "<span class='ind-val' id='i-m5-rsi'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>ATR</span>"
        "<span class='ind-val' id='i-m5-atr'>--</span></div>\n";
   h += "    </div>\n";
   // M15 block
   h += "    <div class='ind-block'>\n";
   h += "      <div class='ind-tf'>M15</div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 9</span>"
        "<span class='ind-val' id='i-m15-e9'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 34</span>"
        "<span class='ind-val' id='i-m15-e34'>--</span></div>\n";
   h += "    </div>\n";
   // H1 block
   h += "    <div class='ind-block'>\n";
   h += "      <div class='ind-tf'>H1</div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 9</span>"
        "<span class='ind-val' id='i-h1-e9'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>EMA 34</span>"
        "<span class='ind-val' id='i-h1-e34'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>RSI</span>"
        "<span class='ind-val' id='i-h1-rsi'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>MACD</span>"
        "<span class='ind-val' id='i-h1-macd'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>BB Mid</span>"
        "<span class='ind-val' id='i-h1-bbm'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>BB Upper</span>"
        "<span class='ind-val' id='i-h1-bbu'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>BB Lower</span>"
        "<span class='ind-val' id='i-h1-bbl'>--</span></div>\n";
   h += "      <div class='ind-row'><span class='ind-lbl'>ATR</span>"
        "<span class='ind-val' id='i-h1-atr'>--</span></div>\n";
   h += "    </div>\n";
   h += "  </div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 7c: EMA alignment / Pivot S/R / Fib zones / Pattern (v6.3g Task 6) ─
   h += "<div class='p-zones'>\n";
   h += "  <div class='z-cols'>\n";
   // Left: EMA multi-TF alignment
   h += "    <div>\n";
   h += "      <div class='z-hdr'>&#x26A1; EMA Multi-TF</div>\n";
   h += "      <div class='ema-bar' id='ema-tfbar'>\n";
   h += "        <div class='ema-tf neut'><span>M1</span><span class='ema-tf-arr'>&#x2014;</span></div>\n";
   h += "        <div class='ema-tf neut'><span>M5</span><span class='ema-tf-arr'>&#x2014;</span></div>\n";
   h += "        <div class='ema-tf neut'><span>M15</span><span class='ema-tf-arr'>&#x2014;</span></div>\n";
   h += "        <div class='ema-tf neut'><span>H1</span><span class='ema-tf-arr'>&#x2014;</span></div>\n";
   h += "        <div class='ema-tf neut'><span>H4</span><span class='ema-tf-arr'>&#x2014;</span></div>\n";
   h += "        <div class='ema-tf neut'><span>D1</span><span class='ema-tf-arr'>&#x2014;</span></div>\n";
   h += "      </div>\n";
   h += "      <div class='touch-row' id='ema-touches'>\n";
   h += "        <span class='tpill toff'>M5 Touch</span>\n";
   h += "        <span class='tpill toff'>H1 Touch</span>\n";
   h += "      </div>\n";
   h += "    </div>\n";
   // Right: Pattern Detection
   h += "    <div>\n";
   h += "      <div class='z-hdr'>&#x1F3AF; Pattern</div>\n";
   h += "      <div class='pat-card'>\n";
   h += "        <span class='pat-name pat-none' id='pat-name'>No Pattern</span>\n";
   h += "        <div class='conf-bar'><div class='conf-fill' id='pat-conf' style='width:0%'></div></div>\n";
   h += "      </div>\n";
   h += "      <div id='pat-dir' style='font:8px monospace;color:rgba(255,255,255,0.3);margin-top:3px;'>---</div>\n";
   h += "    </div>\n";
   h += "  </div>\n";
   // Pivot Points S/R
   h += "  <div style='margin-bottom:5px;'>\n";
   h += "    <div class='z-hdr'>&#x1F4CC; Pivot S/R (Daily)</div>\n";
   h += "    <div class='piv-grid' id='piv-grid'>\n";
   h += "      <div class='pc pc-r'>R3<br>---</div><div class='pc pc-r'>R2<br>---</div>\n";
   h += "      <div class='pc pc-r'>R1<br>---</div><div class='pc pc-p'>PP<br>---</div>\n";
   h += "      <div class='pc pc-s'>S1<br>---</div><div class='pc pc-s'>S2<br>---</div>\n";
   h += "      <div class='pc pc-s'>S3<br>---</div><div></div>\n";
   h += "    </div>\n";
   h += "  </div>\n";
   // Fibonacci Zones
   h += "  <div>\n";
   h += "    <div class='z-hdr' id='fib-hdr'>&#x1F4C9; Fibonacci Zones</div>\n";
   h += "    <div id='fib-list' style='display:grid;grid-template-columns:1fr 1fr 1fr;gap:2px;'>\n";
   h += "      <div class='fr fr-ret'><span>23.6%</span><span>---</span></div>\n";
   h += "      <div class='fr fr-ret'><span>38.2%</span><span>---</span></div>\n";
   h += "      <div class='fr fr-ret'><span>50.0%</span><span>---</span></div>\n";
   h += "      <div class='fr fr-ret'><span>61.8%</span><span>---</span></div>\n";
   h += "      <div class='fr fr-ret'><span>78.6%</span><span>---</span></div>\n";
   h += "      <div class='fr fr-ext'><span>127.2%</span><span>---</span></div>\n";
   h += "    </div>\n";
   h += "  </div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 8: Filters status ────────────────────────────────────────
   h += "<div class='p-filters'>\n";
   h += "  <div class='sec-hdr'>Filters Status</div>\n";
   h += "  <div class='news-inline' id='news-chips'></div>\n";
   h += "  <div class='flt-grid' id='flt-grid'></div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Panel 9: EA Events ────────────────────────────────────────────
   h += "<div class='p-events'>\n";
   h += "  <div class='sec-hdr'>EA Events &amp; Block Reasons</div>\n";
   h += "  <div id='ev-list'><div class='ev-row'>Waiting for data...</div></div>\n";
   h += "</div><div class='sep'></div>\n";

   // ── Footer: DD bar + meta ─────────────────────────────────────────
   h += "<div class='p-footer'>\n";
   h += "  <div class='dd-row'>\n";
   h += "    <div class='dd-lbl'>Daily DD Used</div>\n";
   h += "    <div class='dd-trk'><div id='dd-fill' class='dd-fill dd-low' style='width:0%'></div></div>\n";
   h += "    <div class='dd-val' id='dd-val'>0 / 0%</div>\n";
   h += "  </div>\n";
   h += "  <div class='meta-strip'>\n";
   h += "    <div class='meta-item' id='meta-rend'>Renders: -</div>\n";
   h += "    <div class='meta-item' id='meta-tg'>TG: -</div>\n";
   h += "    <div class='meta-item'>SK Trade Premium " + GetVersionString() + "</div>\n";
   h += "  </div>\n";
   h += "</div>\n";

   h += "</div>\n"; // .dash

   // ── STATUS: no data warning ───────────────────────────────────────
   h += "<div id='no-data' style='display:block;padding:20px;text-align:center;"
        "color:rgba(255,160,0,0.7);font-size:12px;font-family:monospace;margin-top:12px;'>"
        "&#x26A0; Data file not found &mdash; EA is writing sk_dashboard_data.js to:<br>"
        "<span style='color:rgba(0,220,255,0.6);font-size:10px;'>"
        "MetaQuotes\\Terminal\\...\\MQL5\\Files\\sk_dashboard_data.js</span><br>"
        "<span style='font-size:10px;color:rgba(255,255,255,0.2);'>Refreshing every second...</span>"
        "</div>\n";

   // ── JAVASCRIPT ────────────────────────────────────────────────────
   h += "<script>\n";

   // Equity history for sparkline
   h += "let eqHist=[];\n";
   h += "let renders=0;\n";

   // Update sparkline from equity history
   h += "function updateSpark(){\n";
   h += "  if(eqHist.length<2)return;\n";
   h += "  var mn=Math.min.apply(null,eqHist),mx=Math.max.apply(null,eqHist);\n";
   h += "  var r=mx-mn||1,W=496,H=38;\n";
   h += "  var pts=eqHist.map(function(v,i){var x=i/(eqHist.length-1)*W;"
        "var y=H-(v-mn)/r*(H-6)-3;return x+','+y;});\n";
   h += "  var line=pts.join(' L');\n";
   h += "  var last=pts[pts.length-1].split(',');\n";
   h += "  document.getElementById('spark-line').setAttribute('d','M'+line);\n";
   h += "  document.getElementById('spark-area').setAttribute('d','M'+line+' L'+W+','+H+' L0,'+H+' Z');\n";
   h += "  document.getElementById('spark-dot').setAttribute('cx',last[0]);\n";
   h += "  document.getElementById('spark-dot').setAttribute('cy',last[1]);\n";
   h += "}\n";

   // comp bar helper
   h += "function setComp(idx,val){\n";
   h += "  var mx=[25,15,15,10,10,10,5,8];\n";
   h += "  var pct=Math.abs(val)/mx[idx]*100;\n";
   h += "  var el=document.getElementById('sc'+idx);\n";
   h += "  var ev=document.getElementById('sv'+idx);\n";
   h += "  if(!el||!ev)return;\n";
   h += "  el.style.width=Math.min(pct,100)+'%';\n";
   h += "  if(val<0){el.className='sb-fill neg';ev.className='sb-val neg';}\n";
   h += "  else{el.className='sb-fill';ev.className='sb-val';}\n";
   h += "  ev.textContent=(val>=0?'+':'')+val;\n";
   h += "}\n";

   // lock pill helper
   h += "function pill(label,ok,warn){\n";
   h += "  var cls=warn?'pill p-warn':ok?'pill p-ok':'pill p-lock';\n";
   h += "  return '<div class=\"'+cls+'\"><div class=\"dot\"></div>'+label+'</div>';\n";
   h += "}\n";

   // indicator value display helper (v6.3f)
   // Formats numeric indicator values with adaptive precision:
   // price-level (EMA, BB): use symbol digits; ratio (RSI): 1dp; tiny (ATR/MACD): adaptive
   h += "function setInd(id,val,digs){\n";
   h += "  var el=document.getElementById(id); if(!el)return;\n";
   h += "  if(!val||val===0){el.textContent='--';el.className='ind-val';return;}\n";
   h += "  var d2=digs||2;\n";
   h += "  el.textContent=(+val).toFixed(d2);\n";
   h += "  el.className='ind-val';\n";
   h += "}\n";
   h += "function setIndEMA(id,val,bid,digs){\n";
   h += "  var el=document.getElementById(id); if(!el)return;\n";
   h += "  if(!val||val===0){el.textContent='--';el.className='ind-val';return;}\n";
   h += "  el.textContent=(+val).toFixed(digs||2);\n";
   h += "  if(bid>0) el.className='ind-val '+(val>bid?'ind-above':'ind-below');\n";
   h += "  else el.className='ind-val';\n";
   h += "}\n";

   // filter toggle helper
   h += "function ftog(icon,label,on){\n";
   h += "  return '<div class=\"ftog '+(on?'fton':'ftoff')+'\">"
        "<span class=\"ft-ic\">'+icon+'</span>'+label+"
        "'<span class=\"ft-st\">'+(on?'&#x25CF; ON':'&#x25CB; OFF')+'</span></div>';\n";
   h += "}\n";

   // main update function
   h += "function applyData(d){\n";
   h += "  document.getElementById('no-data').style.display='none';\n";

   // Header
   h += "  document.getElementById('htime').textContent=d.ts?d.ts.substr(11,8):'--:--:--';\n";
   h += "  if(d.uptimeSec){var us=d.uptimeSec;"
        "document.getElementById('huptime').textContent="
        "'\\u25B2 '+Math.floor(us/3600)+'h '+Math.floor((us%3600)/60)+'m';}\n";
   h += "  document.getElementById('hrend').textContent=d.renders||renders;\n";
   h += "  var mtg=d.tgSent!==undefined?(d.tgSent+' sent / '+(d.tgDropped||0)+' dropped'):'-';\n";
   h += "  document.getElementById('htg').textContent=mtg;\n";
   h += "  var chip=document.getElementById('mode-chip');\n";
   h += "  var m=d.mode||'---';\n";
   h += "  chip.textContent=(m=='HFT'?'\\u26A1 ':'')+m;\n";
   h += "  chip.className='h-chip '+(m=='HFT'?'hft':m=='SCALPING'?'scalp':'mod');\n";
   h += "  document.getElementById('h-sub').textContent=(d.version||'v6.x')+' \\xB7 '+d.symbol+' \\xB7 '+(d.riskProfile||'-');\n";
   h += "  document.getElementById('warn-banner').style.display=d.paused?'block':'none';\n";
   // Globe + time update (v6.3e)
   h += "  if(d.ts){document.getElementById('g-time').textContent=d.ts.substr(11,8)+' UTC';}\n";
   h += "  var gSess=d.session||'';\n";
   h += "  var gDate=d.ts?d.ts.substr(0,10):'---';\n";
   h += "  document.getElementById('g-date').textContent=gDate+' \\xB7 '+(gSess?gSess+' SESSION':'---');\n";

   // Account
   h += "  var eq=parseFloat(d.equity)||0,bal=parseFloat(d.balance)||0;\n";
   h += "  document.getElementById('eq').textContent='$'+eq.toFixed(2);\n";
   h += "  document.getElementById('bal').textContent='Bal $'+bal.toFixed(2);\n";
   h += "  var dp=parseFloat(d.dailyPnL)||0;\n";
   h += "  var dpEl=document.getElementById('dpnl');\n";
   h += "  dpEl.textContent=(dp>=0?'+$':'$')+Math.abs(dp).toFixed(2);\n";
   h += "  dpEl.className='c-val '+(dp>=0?'gr':'rd');\n";
   h += "  var dpPct=bal>0?(dp/bal*100):0;\n";
   h += "  document.getElementById('dpnlp').textContent=(dpPct>=0?'+':'')+dpPct.toFixed(2)+'% today';\n";
   h += "  var ddUsed=bal>0?(Math.abs(dp)/bal*100):0;\n";
   h += "  var ddLim=parseFloat(d.ddLimit)||5.0;\n";
   h += "  document.getElementById('ddpct').textContent=ddUsed.toFixed(2)+'%';\n";
   h += "  document.getElementById('ddlim').textContent='Limit '+ddLim.toFixed(1)+'%';\n";

   // Sparkline
   h += "  if(eq>0){eqHist.push(eq);if(eqHist.length>60)eqHist.shift();updateSpark();}\n";

   // Safety pills
   h += "  var lk=document.getElementById('locks');\n";
   h += "  lk.innerHTML=\n";
   h += "    pill('Spread',!d.lockSpread,false)+\n";
   h += "    pill('News',!d.newsActive,d.newsActive)+\n";
   h += "    pill('Equity',!d.lockEquity,false)+\n";
   h += "    pill('Spike',!d.spikeActive,d.spikeActive)+\n";
   h += "    pill('Stale Data',!d.lockStale,false)+\n";
   h += "    pill('Daily DD',!d.lockDailyLoss,d.lockDailyLoss)+\n";
   h += "    pill('Loss Streak',!d.lockCooldown,d.lockCooldown)+\n";
   h += "    pill('Broker',!d.lockBroker,false);\n";

   // Trades
   h += "  var ot=parseInt(d.openTrades)||0;\n";
   h += "  document.getElementById('n-trades').textContent=ot;\n";
   h += "  var tl=document.getElementById('trade-list');\n";
   h += "  if(ot===0){tl.innerHTML='<div style=\"color:rgba(255,255,255,0.2);font-size:9px;\">No open positions</div>';}\n";
   h += "  else{var tr='';for(var i=0;i<ot;i++){"
        "var sd=d['trade_'+i];if(!sd)continue;"
        "var isBuy=sd.type==='BUY';"
        "var pnlC=parseFloat(sd.pnl)>=0?'pos':'neg';"
        "tr+='<div class=\"trade-row\">"
        "<span class=\"tb '+(isBuy?'tb-buy':'tb-sell')+'\">'+(isBuy?'BUY':'SELL')+'</span>"
        "<span class=\"t-sym\">'+sd.sym+'</span>"
        "<span class=\"t-lot\">'+sd.lot+'</span>"
        "<span class=\"t-pnl '+pnlC+'\">$'+parseFloat(sd.pnl).toFixed(2)+'</span>"
        "</div>';}tl.innerHTML=tr||'<div style=\"color:rgba(255,255,255,0.2);font-size:9px;\">Data loading</div>';}\n";

   // Performance
   h += "  document.getElementById('pm-w').textContent=d.winTrades||0;\n";
   h += "  document.getElementById('pm-l').textContent=d.lossTrades||0;\n";
   h += "  var wr=parseFloat(d.winRate)||0;\n";
   h += "  document.getElementById('pm-wr').textContent=wr.toFixed(1)+'%';\n";
   h += "  var cw=parseInt(d.consecWins)||0,cl=parseInt(d.consecLosses)||0;\n";
   h += "  var stk=cw>0?cw+'W':cl>0?cl+'L':'-';\n";
   h += "  document.getElementById('pm-streak').textContent=stk;\n";
   h += "  var dpu=parseFloat(d.dailyPnL)||0;\n";
   h += "  document.getElementById('pm-dpnl').textContent=(dpu>=0?'+$':'$')+Math.abs(dpu).toFixed(2);\n";
   h += "  document.getElementById('pm-dd').textContent=ddUsed.toFixed(2)+'%';\n";
   h += "  document.getElementById('bar-wr').style.width=Math.min(wr,100)+'%';\n";
   h += "  document.getElementById('pv-wr').textContent=wr.toFixed(1)+'%';\n";
   h += "  var ddFrac=Math.min(ddUsed/ddLim*100,100);\n";
   h += "  document.getElementById('bar-dd').style.width=ddFrac+'%';\n";
   h += "  document.getElementById('pv-dd').textContent=ddUsed.toFixed(2)+'%';\n";

   // Regime + Score
   h += "  var reg=d.regime||'NORMAL';\n";
   h += "  document.getElementById('rname').textContent=reg;\n";
   h += "  document.getElementById('rname').className='rname'+(reg==='HOSTILE'?' hostile':reg==='QUIET'?' quiet':reg==='TRENDING'?' trend':'');\n";
   h += "  var regbox=document.getElementById('regime-box');\n";
   h += "  regbox.className='regime-box'+(reg==='HOSTILE'?' hostile':reg==='QUIET'?' quiet':'');\n";
   h += "  var spd=parseFloat(d.spread)||0;\n";
   h += "  document.getElementById('rsub').textContent='Spread: '+spd.toFixed(1)+'pts | Bias: '+(d.bias||'-');\n";

   h += "  var sc=parseInt(d.score)||0;\n";
   h += "  document.getElementById('score-num').textContent=sc;\n";
   h += "  document.getElementById('score-lbl').textContent=d.scoreLabel||'SCORE';\n";
   h += "  var arc=document.getElementById('score-arc');\n";
   h += "  var pct=Math.min(sc/93,1);\n";
   h += "  arc.setAttribute('stroke-dasharray',(pct*125.7).toFixed(1)+' 125.7');\n";
   h += "  arc.setAttribute('stroke',sc>=62?'#00ff88':sc>=40?'#ffa000':'#ff4060');\n";
   h += "  var bb=document.getElementById('bias-badge');\n";
   h += "  var bias=d.bias||'NEUTRAL';\n";
   h += "  bb.textContent=(bias==='BUY'?'\\u25B2 BULL':bias==='SELL'?'\\u25BC BEAR':'\\u2014 NEUTRAL');\n";
   h += "  bb.className='sbias '+(bias==='BUY'?'bull':bias==='SELL'?'bear':'none');\n";

   // TF pips from score components
   h += "  var comps=d.scoreComponents||[];\n";
   h += "  var tfs=['M1','M5','M15','H1','H4','D1'];\n";
   h += "  var tfRow=document.getElementById('tf-row');\n";
   h += "  var tfBias=[comps[0]>2,comps[1]>2,comps[2]>2,comps[3]>1,comps[4]>1,comps[7]>2];\n";
   h += "  var tfBear=[comps[0]<-2,comps[1]<-2,comps[2]<-2,comps[3]<-1,comps[4]<-1,comps[7]<-2];\n";
   h += "  tfRow.innerHTML=tfs.map(function(t,i){"
        "var cls=tfBias[i]?'u':tfBear[i]?'d':'n';"
        "return '<div class=\"tf-pip '+cls+'\">'+(tfBias[i]?'\\u25B2':tfBear[i]?'\\u25BC':'\\u2014')+'</div>';"
        "}).join('');\n";

   // Score components
   h += "  if(comps.length>=8){for(var i=0;i<8;i++)setComp(i,comps[i]||0);}\n";

   // Filters
   h += "  var ni=document.getElementById('news-chips');\n";
   h += "  ni.innerHTML=\n";
   h += "    '<div class=\"nchip '+(d.newsActive?'nc-warn':'nc-ok')+'\">"
        "&#x1F4F0; News: '+(d.newsActive?'ACTIVE':'CLEAR')+'</div>'+\n";
   h += "    '<div class=\"nchip '+(d.spikeActive?'nc-warn':'nc-ok')+'\">"
        "&#x1F6A8; Spike: '+(d.spikeActive?'ACTIVE':'CLEAR')+'</div>'+\n";
   h += "    '<div class=\"nchip nc-ok\">Spread: '+spd.toFixed(1)+' pts</div>';\n";

   h += "  var fg=document.getElementById('flt-grid');\n";
   h += "  fg.innerHTML=\n";
   h += "    ftog('&#x1F4F0;','NEWS',!d.newsActive)+\n";
   h += "    ftog('&#x1F6A8;','SPIKE',!d.spikeActive)+\n";
   h += "    ftog('&#x1F4CA;','VOL MOM',d.volMomOk!==false)+\n";
   h += "    ftog('&#x1F4C8;','EMA',true)+\n";
   h += "    ftog('&#x1F321;','REGIME',true)+\n";
   h += "    ftog('&#x1F3AF;','PIVOT',d.usePivot!==false)+\n";
   h += "    ftog('&#x1F4B9;','BSP',true)+\n";
   h += "    ftog('&#x1F527;','HFT ENG',d.mode==='HFT');\n";

   // Events
   h += "  var evts=d.events||[];\n";
   h += "  var evl=document.getElementById('ev-list');\n";
   h += "  if(evts.length===0){evl.innerHTML='<div class=\"ev-row\">No events yet</div>';}\n";
   h += "  else{evl.innerHTML=evts.slice(0,8).map(function(e){"
        "var cls=e.indexOf('BLOCK')>=0?'ev-block':e.indexOf('TRADE')>=0?'ev-trade':"
        "e.indexOf('LOCK')>=0?'ev-lock':'ev-info';"
        "return '<div class=\"ev-row '+cls+'\">'+e+'</div>';"
        "}).join('');}\n";

   // Indicator values (v6.3f)
   h += "  if(d.ind){\n";
   h += "    var dg=parseInt(d.digits)||2;\n";
   h += "    var ibid=parseFloat(d.ind.bid)||0;\n";
   h += "    var bidEl=document.getElementById('ind-bid');\n";
   h += "    if(bidEl)bidEl.textContent=ibid>0?ibid.toFixed(dg):'--';\n";
   h += "    if(d.ind.m1){\n";
   h += "      setIndEMA('i-m1-e9',d.ind.m1.ema9,ibid,dg);\n";
   h += "      setIndEMA('i-m1-e34',d.ind.m1.ema34,ibid,dg);\n";
   h += "      setInd('i-m1-rsi',d.ind.m1.rsi,1);\n";
   h += "      setInd('i-m1-atr',d.ind.m1.atr,dg);\n";
   h += "    }\n";
   h += "    if(d.ind.m5){\n";
   h += "      setIndEMA('i-m5-e9',d.ind.m5.ema9,ibid,dg);\n";
   h += "      setIndEMA('i-m5-e34',d.ind.m5.ema34,ibid,dg);\n";
   h += "      setInd('i-m5-rsi',d.ind.m5.rsi,1);\n";
   h += "      setInd('i-m5-atr',d.ind.m5.atr,dg);\n";
   h += "    }\n";
   h += "    if(d.ind.m15){\n";
   h += "      setIndEMA('i-m15-e9',d.ind.m15.ema9,ibid,dg);\n";
   h += "      setIndEMA('i-m15-e34',d.ind.m15.ema34,ibid,dg);\n";
   h += "    }\n";
   h += "    if(d.ind.h1){\n";
   h += "      setIndEMA('i-h1-e9',d.ind.h1.ema9,ibid,dg);\n";
   h += "      setIndEMA('i-h1-e34',d.ind.h1.ema34,ibid,dg);\n";
   h += "      setInd('i-h1-rsi',d.ind.h1.rsi,1);\n";
   h += "      setInd('i-h1-macd',d.ind.h1.macd,dg+1);\n";
   h += "      setIndEMA('i-h1-bbm',d.ind.h1.bbmid,ibid,dg);\n";
   h += "      setIndEMA('i-h1-bbu',d.ind.h1.bbupper,ibid,dg);\n";
   h += "      setIndEMA('i-h1-bbl',d.ind.h1.bblower,ibid,dg);\n";
   h += "      setInd('i-h1-atr',d.ind.h1.atr,dg);\n";
   h += "    }\n";
   h += "  }\n";

   // EMA multi-TF alignment (v6.3g)
   h += "  if(d.ema){\n";
   h += "    var etfs=['M1','M5','M15','H1','H4','D1'];\n";
   h += "    var ebulls=[d.ema.m1_bull,d.ema.m5_bull,d.ema.m15_bull,d.ema.h1_bull,d.ema.h4_bull,d.ema.d1_bull];\n";
   h += "    var ebar=document.getElementById('ema-tfbar');\n";
   h += "    if(ebar)ebar.innerHTML=etfs.map(function(t,i){\n";
   h += "      var b=ebulls[i];\n";
   h += "      var cls=(b===true)?'bull':(b===false)?'bear':'neut';\n";
   h += "      var arr=(b===true)?'&#x25B2;':(b===false)?'&#x25BC;':'&#x2014;';\n";
   h += "      return '<div class=\"ema-tf '+cls+'\"><span>'+t+'</span><span class=\"ema-tf-arr\">'+arr+'</span></div>';\n";
   h += "    }).join('');\n";
   h += "    var etr=document.getElementById('ema-touches');\n";
   h += "    if(etr){etr.innerHTML=\n";
   h += "      '<span class=\"tpill '+(d.ema.touch_m5?'ton':'toff')+'\">M5 Touch</span>'+\n";
   h += "      '<span class=\"tpill '+(d.ema.touch_h1?'ton':'toff')+'\">H1 Touch</span>'+\n";
   h += "      (d.ema.h4_rsi?'<span style=\"font:8px monospace;color:rgba(255,255,255,0.3);margin-left:4px;\">H4 RSI '+(+d.ema.h4_rsi).toFixed(1)+'</span>':'');}\n";
   h += "  }\n";

   // Pivot Points S/R (v6.3g)
   h += "  var pg=document.getElementById('piv-grid');\n";
   h += "  if(pg){\n";
   h += "    if(d.pivot&&d.pivot.ready){\n";
   h += "      var pv=d.pivot;\n";
   h += "      var cbid=parseFloat((d.ind&&d.ind.bid)||0);\n";
   h += "      function pcell(lbl,val,cls){\n";
   h += "        var hi=cbid>0&&Math.abs(val-cbid)<Math.abs(pv.r1-pv.s1)*0.08?'pc-hi':'';\n";
   h += "        return '<div class=\"pc '+cls+' '+hi+'\">'+lbl+'<br>'+(+val).toFixed(5)+'</div>';\n";
   h += "      }\n";
   h += "      pg.innerHTML=\n";
   h += "        pcell('R3',pv.r3,'pc-r')+pcell('R2',pv.r2,'pc-r')+\n";
   h += "        pcell('R1',pv.r1,'pc-r')+pcell('PP',pv.p,'pc-p')+\n";
   h += "        pcell('S1',pv.s1,'pc-s')+pcell('S2',pv.s2,'pc-s')+\n";
   h += "        pcell('S3',pv.s3,'pc-s')+'<div></div>';\n";
   h += "    }else{\n";
   h += "      pg.innerHTML='<div class=\"pc pc-p\" style=\"grid-column:1/5\">Awaiting D1 close...</div>';\n";
   h += "    }\n";
   h += "  }\n";

   // Fibonacci Zones (v6.3g)
   h += "  var fl=document.getElementById('fib-list');\n";
   h += "  var fh2=document.getElementById('fib-hdr');\n";
   h += "  if(fl){\n";
   h += "    if(d.fib&&d.fib.valid){\n";
   h += "      var fib=d.fib;\n";
   h += "      var fbid=parseFloat((d.ind&&d.ind.bid)||0);\n";
   h += "      var bstr=fib.bias>0?'&#x25B2; BULL':'&#x25BC; BEAR';\n";
   h += "      var bcls=fib.bias>0?'pat-bull':'pat-bear';\n";
   h += "      if(fh2)fh2.innerHTML='&#x1F4C9; Fib <span class=\"'+bcls+'\">'+bstr+'</span>';\n";
   h += "      var flvls=[[23.6,fib.r236,false],[38.2,fib.r382,false],[50.0,fib.r500,false],"
              "[61.8,fib.r618,false],[78.6,fib.r786,false],[127.2,fib.ext1272,true],[161.8,fib.ext1618,true]];\n";
   h += "      var ni2=-1,nd2=1e9;\n";
   h += "      if(fbid>0){flvls.forEach(function(l,i){var dd=Math.abs(l[1]-fbid);if(dd<nd2){nd2=dd;ni2=i;}});}\n";
   h += "      fl.innerHTML=flvls.map(function(l,i){\n";
   h += "        var cls=i===ni2?'fr fr-near':l[2]?'fr fr-ext':'fr fr-ret';\n";
   h += "        return '<div class=\"'+cls+'\"><span>'+l[0].toFixed(1)+'%</span><span>'+(+l[1]).toFixed(5)+'</span></div>';\n";
   h += "      }).join('');\n";
   h += "    }else{\n";
   h += "      if(fh2)fh2.innerHTML='&#x1F4C9; Fibonacci Zones';\n";
   h += "      fl.innerHTML='<div class=\"fr fr-ret\" style=\"grid-column:1/4\">Insufficient swing data</div>';\n";
   h += "    }\n";
   h += "  }\n";

   // Pattern Detection (v6.3g)
   h += "  if(d.pattern){\n";
   h += "    var pnel=document.getElementById('pat-name');\n";
   h += "    var pcel=document.getElementById('pat-conf');\n";
   h += "    var pdel=document.getElementById('pat-dir');\n";
   h += "    var hasPat=d.pattern.pattern>0;\n";
   h += "    if(pnel){\n";
   h += "      pnel.textContent=hasPat?(d.pattern.name||'Pattern'):'No Pattern';\n";
   h += "      pnel.className='pat-name '+(hasPat?(d.pattern.bullish?'pat-bull':'pat-bear'):'pat-none');\n";
   h += "    }\n";
   h += "    if(pcel)pcel.style.width=((+(d.pattern.conf||0))*100).toFixed(0)+'%';\n";
   h += "    if(pdel&&hasPat){\n";
   h += "      var confPct=((+(d.pattern.conf||0))*100).toFixed(0);\n";
   h += "      var dcls2=d.pattern.bullish?'pat-bull':'pat-bear';\n";
   h += "      pdel.innerHTML='<span class=\"'+dcls2+'\">'+(d.pattern.bullish?'&#x25B2; BULL':'&#x25BC; BEAR')+'</span>"
              " <span style=\"color:rgba(255,255,255,0.3)\">Conf: '+confPct+'%</span>';\n";
   h += "    }else if(pdel)pdel.innerHTML='---';\n";
   h += "  }\n";

   // DD footer
   h += "  var ddF=document.getElementById('dd-fill');\n";
   h += "  ddF.style.width=Math.min(ddFrac,100)+'%';\n";
   h += "  ddF.className='dd-fill '+(ddFrac<40?'dd-low':ddFrac<80?'dd-mid':'dd-high');\n";
   h += "  document.getElementById('dd-val').textContent=ddUsed.toFixed(2)+' / '+ddLim.toFixed(1)+'%';\n";
   h += "  document.getElementById('meta-rend').textContent='Renders: '+renders;\n";
   h += "  var tgs=d.tgSent!==undefined?d.tgSent+' sent / '+(d.tgDropped||0)+' dropped':'-';\n";
   h += "  document.getElementById('meta-tg').textContent='TG: '+tgs;\n";
   h += "  renders++;\n";
   h += "}\n";

   // Data loader via dynamic <script> tag injection.
   // XHR was replaced because Chromium 92+ blocks XHR on file:// (CORS policy);
   // <script src="./same-dir-file"> IS permitted on file:// in all modern browsers.
   // Strategy: remove old tag, reset window.SK_DATA, inject new tag with cache-bust
   // query string; onload checks if SK_DATA populated; onerror shows no-data banner.
   // JSON writer now uses window.SK_DATA = {...} (not const) to allow re-injection.
   h += "var lastTs='';\n";
   h += "var _loaderSeq=0;\n";
   h += "var noDataEl=document.getElementById('no-data');\n";
   h += "function loadData(){\n";
   h += "  var seq=++_loaderSeq;\n";
   h += "  var old=document.getElementById('sk-data-script');\n";
   h += "  if(old)old.parentNode.removeChild(old);\n";
   h += "  window.SK_DATA=undefined;\n";
   h += "  var s=document.createElement('script');\n";
   h += "  s.id='sk-data-script';\n";
   h += "  s.src='sk_dashboard_data.js?t='+Date.now();\n";
   h += "  s.onload=function(){\n";
   h += "    if(seq!==_loaderSeq)return;\n";
   h += "    if(typeof window.SK_DATA==='object'&&window.SK_DATA!==null){\n";
   h += "      if(window.SK_DATA.ts!==lastTs){\n";
   h += "        lastTs=window.SK_DATA.ts;\n";
   h += "        try{applyData(window.SK_DATA);}catch(e){console.warn('SK apply:',e);}\n";
   h += "      }\n";
   h += "      if(noDataEl)noDataEl.style.display='none';\n";
   h += "    }else{\n";
   h += "      if(noDataEl)noDataEl.style.display='block';\n";
   h += "    }\n";
   h += "    setTimeout(loadData,1000);\n";
   h += "  };\n";
   h += "  s.onerror=function(){\n";
   h += "    if(noDataEl)noDataEl.style.display='block';\n";
   h += "    setTimeout(loadData,2000);\n";
   h += "  };\n";
   h += "  document.head.appendChild(s);\n";
   h += "}\n";
   h += "loadData();\n";
   h += "</script>\n";

   h += "</body>\n</html>\n";

   // ── Write to MQL5\Files (ANSI = no BOM, UTF-8 compatible, browser-safe) ──
   int fh = FileOpen(WEBVIEW_HTML_FILE, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
   {
      JournalWarn("WebView","HTML write failed ERR="+IntegerToString(GetLastError()));
      return;
   }
   FileWriteString(fh, h);
   FileClose(fh);

   string dataPath = TerminalInfoString(TERMINAL_DATA_PATH);
   JournalInfo("WebView","Dashboard written -> open: "+dataPath+"\\MQL5\\Files\\"+WEBVIEW_HTML_FILE);
}


//--------------------------------------------------------------------
// 16.3  SIGNAL DEBUG CSV LOGGER
//       Writes sk_signal_log.csv to MQL5\Files every signal compute.
//       Lets user trace exactly which component is blocking trades.
//--------------------------------------------------------------------
void WriteSignalCSV(ENUM_BIAS bias, int absScore, int rawSigned)
{
   if(MQLInfoInteger(MQL_OPTIMIZATION)) return;   // optimisation runs thousands of passes — CSV would be gigabytes
   static bool headerWritten = false;
   string path = "sk_signal_log.csv";

   // Header on first write
   if(!headerWritten)
   {
      int fhH = FileOpen(path, FILE_WRITE | FILE_TXT);
      if(fhH != INVALID_HANDLE)
      {
         FileWriteString(fhH,
            "Time,Mode,Bias,Score,RawSigned,"
            "EMA,RSI,MACD,BB,STOCH,VolMom,Regime,BSP,"
            "BSP_M1,BSP_M5,BSP_M15,BSP_H1,BSP_H4,BSP_CurBar,"
            "Spread,RegimeName,Profile,BlockGate,BlockReason\r\n");
         FileClose(fhH);
         headerWritten = true;
      }
   }

   string modeStr  = (gBotMode==BOT_MODE_HFT)?"HFT":(gBotMode==BOT_MODE_SCALPING)?"SCALP":"MOD";
   string biasStr  = (bias==BIAS_BULL)?"BUY":(bias==BIAS_BEAR)?"SELL":"NONE";
   double spread   = (SymbolInfoDouble(gSymbol,SYMBOL_ASK)-SymbolInfoDouble(gSymbol,SYMBOL_BID))/gPoint;

   string row = StringFormat(
      "%s,%s,%s,%d,%d,"
      "%d,%d,%d,%d,%d,%d,%d,%d,"
      "%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,"
      "%.1f,%s,%s,%s,%s\r\n",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS),
      modeStr, biasStr, absScore, rawSigned,
      gScoreComp[0], gScoreComp[1], gScoreComp[2], gScoreComp[3],
      gScoreComp[4], gScoreComp[5], gScoreComp[6], gScoreComp[7],
      gBSP.buyPctM1, gBSP.buyPctM5, gBSP.buyPctM15,
      gBSP.buyPctH1, gBSP.buyPctH4, gBSP.curBarBuyPct,
      spread,
      RegimeToString(gRegime.regime),
      RiskProfileName(gActiveRiskProfile),
      gLastBlockGate, gLastBlockReason
   );

   int fh = FileOpen(path, FILE_READ | FILE_WRITE | FILE_TXT);
   if(fh != INVALID_HANDLE)
   {
      FileSeek(fh, 0, SEEK_END);
      FileWriteString(fh, row);
      FileClose(fh);
   }
}

//--------------------------------------------------------------------
// 16.4  PROFESSIONAL CCANVAS HUD  (complete redesign v2.0)
//       High-quality chart overlay with:
//         • Color-coded score bar with visual fill
//         • Per-component breakdown (8 bars)
//         • BSP per-TF gauge with colored bars
//         • Events log with colored badges
//         • Clean section dividers and professional typography
//--------------------------------------------------------------------
// HUD_W / HUD_H declared at top of file (line ~834) — not redefined here
#define HUD_X0     0
#define HUD_Y0     0

// ── Drawing helpers (all pixel-coords relative to canvas) ───────────
void _HFill(int x1, int y, int x2, uint c) { gCanvas.FillRectangle(x1, y, x2, y+1, c); }
void _Rect(int x1, int y1, int x2, int y2, uint fillC)
   { gCanvas.FillRectangle(x1, y1, x2, y2, fillC); }
void _BorderRect(int x1, int y1, int x2, int y2, uint borderC)
{
   gCanvas.FillRectangle(x1, y1, x2, y1+1, borderC);
   gCanvas.FillRectangle(x1, y2, x2, y2+1, borderC);
   gCanvas.FillRectangle(x1, y1, x1+1, y2, borderC);
   gCanvas.FillRectangle(x2, y1, x2+1, y2, borderC);
}

// Draw a horizontal progress bar [0.0..1.0] with colored fill + grey track
void _BarH(int x, int y, int w, int h, double pct, uint fillC)
{
   pct = MathMax(0.0, MathMin(1.0, pct));
   uint trackC = ColorToARGB(C'28,38,58', 255);
   gCanvas.FillRectangle(x, y, x+w, y+h, trackC);
   if(pct > 0.0)
      gCanvas.FillRectangle(x, y, x+(int)(w*pct), y+h, fillC);
}

// Centered text in a box
void _TxtC(int x, int y, int w, string s, uint c)
   { gCanvas.TextOut(x + w/2, y, s, c, TA_CENTER); }

void RenderBasicCCanvas()
{
   if(!InpShowDashboard || !gCanvasReady) return;
   if(!gDashNeedsRedraw) return;
   gDashNeedsRedraw = false;

   // ── ARGB palette ────────────────────────────────────────────────
   uint BG       = 0xFF060611;          // near-black navy
   uint BG2      = 0xFF0A0F1E;          // slightly lighter card bg
   uint BG3      = 0xFF0D1428;          // section bg
   uint HDR      = 0xFF07091A;          // header strip
   uint CYAN     = 0xFF00DCFF;
   uint CYAN2    = 0x8000DCFF;          // dim cyan
   uint CYAN3    = 0x3000DCFF;          // very dim cyan
   uint DIV      = 0x28607090;          // divider
   uint WHITE    = 0xFFFFFFFF;
   uint GREY     = 0xFF7090B0;
   uint DIM      = 0xFF3A4E68;
   uint GREEN    = 0xFF00E878;
   uint GREEN2   = 0x5000E878;
   uint RED      = 0xFFFF3C55;
   uint RED2     = 0x50FF3C55;
   uint AMBER    = 0xFFFFAA20;
   uint AMBER2   = 0x50FFAA20;
   uint PURPLE   = 0xFFAA60FF;
   uint ORANGE   = 0xFFFF7030;
   uint ORANGE2  = 0x50FF7030;
   uint BLUE     = 0xFF2898FF;
   uint TEAL     = 0xFF00C8A8;

   int W = HUD_W;       // 310
   gCanvas.Erase(BG);

   // ═══════════════════════════════════════════════════════════════
   // HEADER  (0..32)
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, 0, W, 32, HDR);
   // Left accent bar (3px wide cyan gradient)
   _Rect(0, 0, 3, 32, CYAN);
   _Rect(3, 0, 4, 32, CYAN2);

   gCanvas.FontSet("Arial Bold", 8, 0);
   gCanvas.TextOut(9, 9, "SK TRADE PREMIUM", CYAN, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(9, 21, GetVersionString(), CYAN2, TA_LEFT|TA_TOP);

   // Mode badge
   string modStr = (gBotMode==BOT_MODE_HFT)   ? "HFT"   :
                   (gBotMode==BOT_MODE_SCALPING)? "SCALP" : "MOD";
   uint   modBg  = (gBotMode==BOT_MODE_HFT)   ? ORANGE2 :
                   (gBotMode==BOT_MODE_SCALPING)? CYAN3   : 0x50AA60FF;
   uint   modFg  = (gBotMode==BOT_MODE_HFT)   ? ORANGE :
                   (gBotMode==BOT_MODE_SCALPING)? CYAN   : PURPLE;
   _Rect(W-60, 6, W-4, 26, modBg);
   _BorderRect(W-60, 6, W-4, 26, modFg & 0x80FFFFFF);
   gCanvas.FontSet("Arial Bold", 8, 0);
   _TxtC(W-60, 13, 56, modStr, modFg);

   // Profile label (right of version)
   gCanvas.FontSet("Arial", 9, 0);
   // Show sub-mode name in header subtitle row
   string subLbl = SubModeName();
   if(StringLen(subLbl) > 16) subLbl = StringSubstr(subLbl,0,14)+"~";
   gCanvas.TextOut(78, 21, subLbl, GREY, TA_LEFT|TA_TOP);

   // Symbol label
   gCanvas.TextOut(9, 0, "", 0, TA_LEFT);  // noop to reset
   gCanvas.FontSet("Arial Bold", 9, 0);
   int symW=0,symH=0; gCanvas.TextSize(gSymbol,symW,symH);
   gCanvas.TextOut(W/2-symW/2, 2, gSymbol, GREY, TA_LEFT|TA_TOP);

   // Cyan accent divider
   _HFill(0, 32, W, CYAN3);
   _HFill(0, 33, W, 0x1500DCFF);

   // ═══════════════════════════════════════════════════════════════
   // SIGNAL SCORE  (34..96)
   // ═══════════════════════════════════════════════════════════════
   int y = 34;
   _Rect(0, y, W, y+62, BG3);
   // Left accent dot
   _Rect(0, y, 3, y+62, CYAN2);

   // Score threshold
   int minS = (gBotMode==BOT_MODE_HFT)    ? gRt_HFTMinScore  :
              (gBotMode==BOT_MODE_SCALPING)? gRt_ScalpMinScore : gRt_ModMinScore;
   bool pass = (gLastScore >= minS);

   // Score quality
   string scoreQual;
   uint   scoreQC;
   int    sc = gLastScore;
   if(sc >= 88) { scoreQual="EXTREME"; scoreQC=GREEN;  }
   else if(sc >= 78) { scoreQual="STRONG";  scoreQC=GREEN;  }
   else if(sc >= 68) { scoreQual="PASS";    scoreQC=TEAL;   }
   else if(pass)     { scoreQual="PASS";    scoreQC=TEAL;   }
   else              { scoreQual="FAIL";    scoreQC=RED;    }

   // Bias badge
   string biasLbl = (gLastBias==BIAS_BULL)?"  BUY  ":
                    (gLastBias==BIAS_BEAR)?"  SELL ":"  ---  ";
   uint   biasBg  = (gLastBias==BIAS_BULL) ? GREEN2 :
                    (gLastBias==BIAS_BEAR) ? RED2   : 0x28607090;
   uint   biasFg  = (gLastBias==BIAS_BULL) ? GREEN :
                    (gLastBias==BIAS_BEAR) ? RED   : GREY;
   _Rect(4, y+4, 56, y+22, biasBg);
   _BorderRect(4, y+4, 56, y+22, biasFg & 0x80FFFFFF);
   gCanvas.FontSet("Arial Bold", 8, 0);
   _TxtC(4, y+10, 52, biasLbl, biasFg);

   // Large score number
   string scoreTxt = IntegerToString(sc);
   gCanvas.FontSet("Arial Bold", 16, 0);
   int stw=0,sth=0; gCanvas.TextSize(scoreTxt,stw,sth);
   gCanvas.TextOut(W/2-stw/2, y+3, scoreTxt, scoreQC, TA_LEFT|TA_TOP);

   // Score quality label
   gCanvas.FontSet("Arial Bold", 9, 0);
   int qw=0,qh=0; gCanvas.TextSize(scoreQual,qw,qh);
   gCanvas.TextOut(W/2-qw/2, y+22, scoreQual, scoreQC, TA_LEFT|TA_TOP);

   // Min score info
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(W-58, y+10, "MIN:"+IntegerToString(minS), GREY, TA_LEFT|TA_TOP);

   // Score progress bar (thick, prominent)
   int barX=4, barY=y+33, barW=W-8, barH=14;
   uint trackC = 0xFF0D1428;
   gCanvas.FillRectangle(barX, barY, barX+barW, barY+barH, trackC);
   // Threshold zone (min score)
   int threshX = barX + (int)((double)minS/100.0 * barW);
   _Rect(threshX-1, barY, threshX+1, barY+barH, 0x60FFFFFF);
   // Fill up to score
   double pct = MathMax(0.0, MathMin(1.0, (double)sc / 100.0));
   int fillW = (int)(barW * pct);
   if(fillW > 0)
   {
      gCanvas.FillRectangle(barX, barY, barX+fillW, barY+barH, pass?0x5000E878:0x50FF3C55);
      gCanvas.FillRectangle(barX, barY, barX+fillW, barY+2, pass?GREEN:RED);  // bright top edge
   }
   // Tick marks at 25, 50, 75
   for(int tk=25; tk<=75; tk+=25)
   {
      int tkX = barX + (int)((double)tk/100.0*barW);
      gCanvas.Line(tkX, barY+barH-3, tkX, barY+barH, DIV);
   }
   // Text in bar: "xx / min:yy"
   gCanvas.FontSet("Arial", 9, 0);
   string barTxt = IntegerToString(sc)+"%   threshold:"+IntegerToString(minS)+"%";
   gCanvas.TextOut(barX+5, barY+3, barTxt, pass?GREEN:RED, TA_LEFT|TA_TOP);

   // Regime label (right end of score section)
   string regStr = RegimeToString(gRegime.regime);
   uint   regC   = (gRegime.regime==REGIME_HOSTILE)  ? RED   :
                   (gRegime.regime==REGIME_EXPLOSIVE) ? AMBER : TEAL;
   gCanvas.FontSet("Arial Bold", 9, 0);
   gCanvas.TextOut(W-58, y+25, regStr, regC, TA_LEFT|TA_TOP);

   y += 62;
   _HFill(0, y, W, CYAN3);
   y += 1;

   // ═══════════════════════════════════════════════════════════════
   // ACCOUNT  TILES  (y..y+44)
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+44, BG);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double dpnl= gDailyClosedPnL;
   double ddPct= (bal > 0) ? MathAbs(dpnl)/bal*100.0 : 0.0;

   int tW = W/3;
   // Tile: Equity
   _Rect(0,   y,   tW,   y+44, BG2);
   _Rect(0,   y,   tW,   y+3,  CYAN);           // top accent
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(4, y+5,  "EQUITY",   DIM, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial Bold", 9, 0);
   string eqStr = StringFormat("$%.0f", eq);
   gCanvas.TextOut(4, y+16, eqStr, CYAN, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial", 9, 0);
   string balStr= StringFormat("Bal $%.0f", bal);
   gCanvas.TextOut(4, y+31, balStr, DIM, TA_LEFT|TA_TOP);

   // Tile: Daily P&L
   _Rect(tW+1,  y,   2*tW, y+44, BG2);
   uint pnlAccC = (dpnl >= 0) ? GREEN : RED;
   uint pnlAccT = (dpnl >= 0) ? GREEN : RED;
   _Rect(tW+1,  y,   2*tW, y+3,  pnlAccC);
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(tW+4, y+5,  "DAILY P&L", DIM, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial Bold", 9, 0);
   string pnlStr = (dpnl>=0?"+$":"-$") + StringFormat("%.2f",MathAbs(dpnl));
   gCanvas.TextOut(tW+4, y+16, pnlStr, pnlAccT, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial", 9, 0);
   int cw=gConsecWins, cl=gConsecLosses;
   string strkStr = (cw>0) ? IntegerToString(cw)+"W streak" :
                    (cl>0) ? IntegerToString(cl)+"L streak" : "no streak";
   gCanvas.TextOut(tW+4, y+31, strkStr, pnlAccC & 0xA0FFFFFF, TA_LEFT|TA_TOP);

   // Tile: Drawdown
   _Rect(2*tW+1, y,   W, y+44, BG2);
   uint ddC  = (ddPct > 3.0) ? RED : (ddPct > 1.5) ? AMBER : TEAL;
   _Rect(2*tW+1, y,   W, y+3, ddC);
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(2*tW+4, y+5,  "DRAWDOWN", DIM, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial Bold", 9, 0);
   string ddStr = StringFormat("%.2f%%", ddPct);
   gCanvas.TextOut(2*tW+4, y+16, ddStr, ddC, TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial", 9, 0);
   string ddLimStr = StringFormat("Lim %.1f%%", (double)InpMaxDailyLossPercent);
   gCanvas.TextOut(2*tW+4, y+31, ddLimStr, DIM, TA_LEFT|TA_TOP);

   y += 44;
   _HFill(0, y, W, DIV);
   y += 1;

   // ═══════════════════════════════════════════════════════════════
   // SAFETY VAULT  (y..y+65)
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+65, BG);
   _Rect(0, y, 3, y+65, RED & 0x60FFFFFF);  // dim red accent

   // Overall status bar
   bool anyLk = (gSafety.lockEquityFloor||gSafety.lockDailyLoss||
                 gSafety.lockGlobalDD||gSafety.lockSpike||gSafety.lockNews||
                 gSafety.lockSpread||gSafety.lockManualPause||gSafety.lockStaleData||
                 gConsecLosses >= InpMaxConsecLosses);
   uint statBg, statFg;
   string statStr;
   if(gBotPaused)     { statBg=0x40604000; statFg=AMBER; statStr="PAUSED"; }
   else if(anyLk)     { statBg=0x40500A0A; statFg=RED;   statStr="LOCKED: "+gLastBlockGate; }
   else               { statBg=0x20003A1A; statFg=GREEN; statStr="ALL GATES CLEAR"; }
   _Rect(4, y+2, W-4, y+15, statBg);
   gCanvas.FontSet("Arial Bold", 9, 0);
   _TxtC(4, y+5, W-8, statStr, statFg);

   // Lock grid: 4 rows x 2 cols
   struct LockRow { string lbl; bool locked; };
   LockRow locks[8];
   locks[0].lbl="SPREAD";    locks[0].locked=gSafety.lockSpread;
   locks[1].lbl="EQUITY FLR";locks[1].locked=gSafety.lockEquityFloor;
   locks[2].lbl="DAILY DD";  locks[2].locked=(gSafety.lockDailyLoss||gSafety.lockGlobalDD);
   locks[3].lbl="NEWS";      locks[3].locked=gNews.active;
   locks[4].lbl="SPIKE";     locks[4].locked=gSpike.spikeActive;
   locks[5].lbl="STALE DATA";locks[5].locked=gSafety.lockStaleData;
   locks[6].lbl="LOSS STREAK";locks[6].locked=(gConsecLosses>=InpMaxConsecLosses);
   locks[7].lbl="MANUAL";   locks[7].locked=gSafety.lockManualPause;

   gCanvas.FontSet("Arial", 9, 0);
   int lkColW = W/2;
   for(int li=0; li<8; li++)
   {
      int col  = li % 2;
      int row  = li / 2;
      int lkX  = 5 + col * lkColW;
      int lkY  = y + 17 + row * 11;
      uint dotC = locks[li].locked ? RED : GREEN;
      uint txtC = locks[li].locked ? RED : DIM;
      gCanvas.FillCircle(lkX+3, lkY+4, 3, dotC);
      gCanvas.TextOut(lkX+9, lkY, locks[li].lbl, txtC, TA_LEFT|TA_TOP);
   }

   y += 65;
   _HFill(0, y, W, DIV);
   y += 1;

   // ═══════════════════════════════════════════════════════════════
   // BSP — Buyer/Seller Pressure split bar  (y..y+28)
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+28, BG3);
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(6, y+2, "PRESSURE", DIM, TA_LEFT|TA_TOP);
   // HFT/HFT_PURE → live tick pressure; other modes → rolling BSP
   double bsp_live_ratio;
   string bsp_press_label;
   if(gBotMode == BOT_MODE_HFT || gBotMode == BOT_MODE_HFT_PURE)
   {
      bsp_live_ratio  = gPressEng.GetRatio() * 100.0;   // actual ratio always (0.5 at bar-reset, updates each tick)
      bsp_press_label = gPressEng.IsValid() ? "LIVE" : "WARM";
   }
   else
   {
      bsp_live_ratio  = gBSP.buyPct;
      bsp_press_label = gBSP.label;
   }
   double bsp_buy  = MathMin(100.0, MathMax(0.0, bsp_live_ratio));
   double bsp_sell = MathMin(100.0, MathMax(0.0, 100.0 - bsp_live_ratio));
   int bspX=4, bspY=y+12, bspW=W-8, bspH=10;
   _Rect(bspX, bspY, bspX+bspW, bspY+bspH, 0xFF0A0F1E);
   int buyFW = (int)(bspW * bsp_buy / 100.0);
   if(buyFW > 0) gCanvas.FillRectangle(bspX, bspY, bspX+buyFW, bspY+bspH, GREEN2);
   // Sell from right
   int sellFW = (int)(bspW * bsp_sell / 100.0);
   if(sellFW > 0) gCanvas.FillRectangle(bspX+bspW-sellFW, bspY,
                                          bspX+bspW, bspY+bspH, RED2);
   // Center line
   gCanvas.Line(bspX+bspW/2, bspY, bspX+bspW/2, bspY+bspH, DIV);
   // Labels
   gCanvas.TextOut(bspX+2,     bspY+1, StringFormat("B%.0f%%",bsp_buy),  GREEN & 0xD0FFFFFF, TA_LEFT|TA_TOP);
   gCanvas.TextOut(bspX+bspW-28, bspY+1, StringFormat("S%.0f%%",bsp_sell), RED & 0xD0FFFFFF, TA_LEFT|TA_TOP);
   // Pressure label
   gCanvas.TextOut(W-60, y+2, bsp_press_label, GREY, TA_LEFT|TA_TOP);

   y += 28;
   _HFill(0, y, W, DIV);
   y += 1;

   // ═══════════════════════════════════════════════════════════════
   // SCORE COMPONENTS  (y..y+78)
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+78, BG);
   _Rect(0, y, 3, y+78, CYAN3);
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(6, y+1, "SCORE COMPONENTS", DIM, TA_LEFT|TA_TOP);

   // Component labels (abbreviated)
   string compLbls[8] = {"TREND","EMA5","RSI","CNDL","BSP","MACD","VOLM","ATR"};
   int maxComp[8] = {25, 15, 12, 10, 8, 8, 7, 5};   // max points per component
   int compBarX = 4, compBarStart = 60;
   int compBarMaxW = W - compBarStart - 8;
   gCanvas.FontSet("Arial", 8, 0);
   for(int ci=0; ci<8; ci++)
   {
      int cy2 = y + 11 + ci*8;
      int cv  = MathAbs(gScoreComp[ci]);
      double cpct = (maxComp[ci] > 0) ? (double)cv / maxComp[ci] : 0.0;
      uint cFill = (gScoreComp[ci] > 0) ? GREEN2 : (gScoreComp[ci] < 0) ? RED2 : DIM;
      uint cTxt  = (gScoreComp[ci] > 0) ? GREEN  : (gScoreComp[ci] < 0) ? RED  : DIM;
      gCanvas.TextOut(compBarX+1, cy2, compLbls[ci], cTxt, TA_LEFT|TA_TOP);
      // Bar track
      gCanvas.FillRectangle(compBarStart, cy2, compBarStart+compBarMaxW, cy2+6, 0xFF0D1428);
      // Bar fill
      int cBarW = (int)(compBarMaxW * MathMin(1.0, cpct));
      if(cBarW > 0)
         gCanvas.FillRectangle(compBarStart, cy2, compBarStart+cBarW, cy2+6, cFill);
      // Value text
      gCanvas.TextOut(compBarStart+compBarMaxW+2, cy2, IntegerToString(gScoreComp[ci]),
                      cTxt, TA_LEFT|TA_TOP);
   }

   y += 78;
   _HFill(0, y, W, DIV);
   y += 1;

   // ═══════════════════════════════════════════════════════════════
   // OPEN TRADES  (y..y+14+n*11)  max 4 trades shown
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+12, HDR);
   gCanvas.FontSet("Arial", 9, 0);
   int nTrades = 0;
   for(int ti=0; ti<100; ti++) if(gRec[ti].active) nTrades++;
   gCanvas.TextOut(6, y+2, "TRADES", DIM, TA_LEFT|TA_TOP);
   gCanvas.TextOut(W-28, y+2, IntegerToString(nTrades)+" open", GREY, TA_LEFT|TA_TOP);
   y += 13;
   _HFill(0, y, W, DIV); y++;

   if(nTrades == 0)
   {
      _Rect(0, y, W, y+11, BG);
      gCanvas.FontSet("Arial", 9, 0);
      gCanvas.TextOut(6, y+2, "No open positions", DIM, TA_LEFT|TA_TOP);
      y += 11;
   }
   else
   {
      int shown = 0;
      for(int ti=0; ti<100 && shown<4; ti++)
      {
         if(!gRec[ti].active) continue;
         if(!PositionSelectByTicket(gRec[ti].ticket)) continue;
         string tType = (PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?"BUY":"SELL";
         double tPnl  = PositionGetDouble(POSITION_PROFIT);
         double tLot  = PositionGetDouble(POSITION_VOLUME);
         uint rowBg   = (shown%2==0) ? BG3 : BG2;
         uint tBadge  = (tType=="BUY") ? GREEN2 : RED2;
         uint tBadgeF = (tType=="BUY") ? GREEN  : RED;
         uint tPnlC   = (tPnl >= 0)   ? GREEN  : RED;
         _Rect(0, y, W, y+11, rowBg);
         // Type badge
         _Rect(3, y+1, 30, y+10, tBadge);
         gCanvas.FontSet("Arial Bold", 8, 0);
         _TxtC(3, y+3, 27, tType, tBadgeF);
         // Symbol
         gCanvas.FontSet("Arial", 9, 0);
         gCanvas.TextOut(34, y+2, gSymbol, GREY, TA_LEFT|TA_TOP);
         // Lot
         gCanvas.TextOut(W/2-20, y+2, StringFormat("%.2fL",tLot), GREY, TA_LEFT|TA_TOP);
         // PnL
         string pnlS = (tPnl>=0 ? "+$" : "-$") + StringFormat("%.2f",MathAbs(tPnl));
         int pnlTW=0,pnlTH=0; gCanvas.FontSet("Arial Bold",7,0);
         gCanvas.TextSize(pnlS,pnlTW,pnlTH);
         gCanvas.TextOut(W-pnlTW-4, y+2, pnlS, tPnlC, TA_LEFT|TA_TOP);
         y += 11;
         shown++;
      }
   }
   _HFill(0, y, W, DIV); y++;

   // ═══════════════════════════════════════════════════════════════
   // EA EVENTS  (y..y+12+n*11)  last 4
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+12, HDR);
   _Rect(0, y, 3, y+12, AMBER & 0x60FFFFFF);
   gCanvas.FontSet("Arial", 9, 0);
   gCanvas.TextOut(6, y+2, "EA EVENTS", DIM, TA_LEFT|TA_TOP);
   y += 13;
   _HFill(0, y, W, DIV); y++;

   int evShown = 0;
   for(int ei=0; ei<16 && evShown<4; ei++)
   {
      if(gEAEventLog[ei] == "") break;
      string ev = gEAEventLog[ei];
      bool isBlk = (StringFind(ev,"BLOCK")>=0 || StringFind(ev,"Gate")>=0);
      bool isErr = (StringFind(ev,"ERROR")>=0 || StringFind(ev,"FAIL")>=0);
      uint evBg  = isBlk ? 0x30604000 : isErr ? 0x305A0A0A : 0x20003A1A;
      uint evFg  = isBlk ? AMBER : isErr ? RED : TEAL;
      _Rect(0, y, W, y+11, evBg);
      gCanvas.FontSet("Arial", 8, 0);
      if(StringLen(ev) > 52) ev = StringSubstr(ev,0,50)+"..";
      gCanvas.TextOut(5, y+2, ev, evFg, TA_LEFT|TA_TOP);
      y += 11;
      evShown++;
   }
   if(evShown == 0)
   {
      _Rect(0, y, W, y+11, BG);
      gCanvas.FontSet("Arial", 9, 0);
      gCanvas.TextOut(6, y+2, "EA running normally", DIM, TA_LEFT|TA_TOP);
      y += 11;
   }
   _HFill(0, y, W, DIV); y++;

   // ═══════════════════════════════════════════════════════════════
   // PERFORMANCE FOOTER  (y..y+26)
   // ═══════════════════════════════════════════════════════════════
   _Rect(0, y, W, y+26, BG3);
   int pW = (W-8)/3;
   double wr = (gPerf.totalTrades > 0) ?
               (gPerf.winTrades * 100.0 / gPerf.totalTrades) : 0.0;
   gCanvas.FontSet("Arial", 8, 0);
   gCanvas.TextOut(6,       y+2,  "W/L/RATE",          DIM,  TA_LEFT|TA_TOP);
   gCanvas.TextOut(6,       y+12, IntegerToString(gPerf.winTrades)+" W", GREEN, TA_LEFT|TA_TOP);
   gCanvas.TextOut(6+pW,    y+12, IntegerToString(gPerf.lossTrades)+" L", RED,   TA_LEFT|TA_TOP);
   gCanvas.FontSet("Arial Bold", 9, 0);
   uint wrC = (wr >= 60)?GREEN:(wr>=45)?AMBER:RED;
   gCanvas.TextOut(6+2*pW,  y+10, StringFormat("%.1f%%",wr), wrC, TA_LEFT|TA_TOP);
   // WinRate bar
   int wrBarX=4, wrBarY=y+21, wrBarW=W-8;
   gCanvas.FillRectangle(wrBarX, wrBarY, wrBarX+wrBarW, wrBarY+3, 0xFF0D1428);
   int wrFW = (int)(wrBarW * MathMin(1.0, wr/100.0));
   if(wrFW > 0) gCanvas.FillRectangle(wrBarX, wrBarY, wrBarX+wrFW, wrBarY+3, wrC & 0xA0FFFFFF);
   // Spread info
   double sprd = (SymbolInfoDouble(gSymbol,SYMBOL_ASK)-SymbolInfoDouble(gSymbol,SYMBOL_BID))/gPoint;
   gCanvas.FontSet("Arial", 8, 0);
   uint sprdC = gSafety.lockSpread ? RED : GREY;
   gCanvas.TextOut(W-50, y+2, StringFormat("Sprd:%.1f",sprd), sprdC, TA_LEFT|TA_TOP);
   gCanvas.TextOut(W-50, y+12, gPipDigitLabel, DIM, TA_LEFT|TA_TOP);

   y += 26;

   // ═══════════════════════════════════════════════════════════════
   // STATUS FOOTER  (always last 16px)
   // ═══════════════════════════════════════════════════════════════
   uint sfBg = anyLk  ? 0x50500A0A :
               gBotPaused ? 0x50504000 : 0x40003020;
   uint sfFg = anyLk  ? RED : gBotPaused ? AMBER : GREEN;
   _Rect(0, y, W, y+16, sfBg);
   _HFill(0, y, W, sfFg & 0x40FFFFFF);
   gCanvas.FontSet("Arial Bold", 9, 0);
   string sfTxt = anyLk   ? "LOCKED — "+gLastBlockGate :
                  gBotPaused ? "PAUSED — resume via dashboard" :
                               "ACTIVE — all systems operational";
   _TxtC(0, y+3, W, sfTxt, sfFg);

   gCanvas.Update();
}

//--------------------------------------------------------------------
// 16.4  WebView timer integration (called from OnTimer step 8b)
//--------------------------------------------------------------------
void ProcessWebViewDash()
{
   WriteWebViewJSON();       // update JSON data file
   // v6.3d FIX: Only render basic HUD when glassmorphism is DISABLED.
   // When InpUseGlassmorphUI=true, RenderDashboardAdvanced() (called from OnTimer right after)
   // handles all canvas output. Previously BOTH renderers ran — RenderBasicCCanvas consumed
   // gDashNeedsRedraw first, then RenderDashboardAdvanced() saw flag=false and returned without
   // drawing → advanced 660px dashboard never appeared on screen despite being "enabled".
   if(!InpUseGlassmorphUI)
      RenderBasicCCanvas();     // basic HUD only when glassmorphism OFF
}

//====================================================================
//  ┌─────────────────────────────────────────────────────────────┐
//  │   END OF PART 6                                              │
//  │                                                              │
//  │   Engines completed this file:                               │
//  │     Engine 13 — Async Telegram (128-slot ring, 15 templates) │
//  │     Engine 14 — Glassmorphism Dashboard (10 panels CCanvas)  │
//  │     Engine 15 — Update/Patch Injection (9 built-in patches)  │
//  │     Engine 16 — WebView2 HTML+JSON Live Dashboard            │
//  │                                                              │
//  │   Next → Part 7: OnInit | OnTick | OnTimer |                 │
//  │                  OnTradeTransaction | OnDeinit | OnChartEvent │
//  └─────────────────────────────────────────────────────────────┘
//====================================================================


#endif // SKP_P6_UI_MQH
