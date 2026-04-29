//+------------------------------------------------------------------+
//|                                          SMC_API_Signal.mq5       |
//|                   Signal-based EA with REST API connectivity       |
//|                   Reads signals from API, opens/closes trades      |
//+------------------------------------------------------------------+
#property copyright "DevTrade"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input string   APIBaseUrl       = "http://127.0.0.1";   // API Base URL (e.g. http://192.168.1.100)
input uint     APIPort          = 80;                  // API Port
input int      APITimeout       = 5000;                // API Request Timeout (ms)
input string   APISymbol        = "GOLD";              // Symbol name for API query (DB symbol)
input double   FixedLot         = 0.01;                // Lot Size
input double   MaxLot           = 1.0;                 // Max Lot Size
input int      MagicNumber      = 20260312;            // EA Magic Number
input int      PollIntervalSec  = 5;                   // API Poll Interval (seconds)
input int      SLBufferPoints   = 50;                  // Extra SL buffer (points)
input int      SwingBars        = 20;                  // Bars to look back for SL calculation
input int      TargetProfitPoints = 1500;              // Min profit points to allow close (0=disabled)

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
int            g_lastSignalId       = 0;
bool           g_hasActiveOrder     = false;
int            g_activeOrderType    = -1;       // 0=BUY, 1=SELL
string         g_activeSignalAction = "";
int            g_pendingSetup       = -1;       // -1=None, 0=BUY Pending, 1=SELL Pending
int            g_pendingSignalId    = 0;
int            g_apiFailCount       = 0;

struct SignalData
  {
   int            signal_id;
   string         symbol;
   string         pitch_fan;
   string         macd_hist1;
   string         macd_hist2;
   string         macd1_sig_cross;
   string         macd2_sig_cross;
   string         fvg;
   string         ob;
   string         bb;
   string         rb;
   string         blue_mode;
   double         sl;
   double         fibo_0_5;
   double         fibo_61_8;
   double         fibo_poc;
   string         close_status;
   string         is_active;
   string         trade_action;
  };

SignalData g_currentSignal;

//+------------------------------------------------------------------+
//| Build full API URL with port                                      |
//+------------------------------------------------------------------+
string BuildUrl(string path)
  {
   if(APIPort == 80)
      return APIBaseUrl + path;
   return APIBaseUrl + ":" + IntegerToString(APIPort) + path;
  }

//+------------------------------------------------------------------+
//| Extract a JSON string value by key                                |
//+------------------------------------------------------------------+
string JsonGetString(const string &json, const string key)
  {
   string searchKey = "\"" + key + "\"";
   int keyPos = StringFind(json, searchKey);
   if(keyPos < 0)
      return "";

   int colonPos = StringFind(json, ":", keyPos + StringLen(searchKey));
   if(colonPos < 0)
      return "";

   int startSearch = colonPos + 1;

   // Skip whitespace
   while(startSearch < StringLen(json) && (StringGetCharacter(json, startSearch) == ' ' || StringGetCharacter(json, startSearch) == '\t'))
      startSearch++;

   if(startSearch >= StringLen(json))
      return "";

   ushort ch = StringGetCharacter(json, startSearch);

   // null value
   if(ch == 'n')
      return "";

   // Quoted string
   if(ch == '"')
     {
      int strStart = startSearch + 1;
      int strEnd = StringFind(json, "\"", strStart);
      if(strEnd < 0)
         return "";
      return StringSubstr(json, strStart, strEnd - strStart);
     }

   // Number or boolean (unquoted value) - read until comma, }, or whitespace
   int valStart = startSearch;
   int valEnd = valStart;
   while(valEnd < StringLen(json))
     {
      ushort c = StringGetCharacter(json, valEnd);
      if(c == ',' || c == '}' || c == ']' || c == ' ' || c == '\r' || c == '\n')
         break;
      valEnd++;
     }
   return StringSubstr(json, valStart, valEnd - valStart);
  }

//+------------------------------------------------------------------+
//| Extract a JSON double value by key                                |
//+------------------------------------------------------------------+
double JsonGetDouble(const string &json, const string key)
  {
   string val = JsonGetString(json, key);
   if(val == "" || val == "null")
      return 0.0;
   return StringToDouble(val);
  }

//+------------------------------------------------------------------+
//| Extract a JSON int value by key                                   |
//+------------------------------------------------------------------+
int JsonGetInt(const string &json, const string key)
  {
   string val = JsonGetString(json, key);
   if(val == "" || val == "null")
      return 0;
   return (int)StringToInteger(val);
  }

//+------------------------------------------------------------------+
//| HTTP GET request                                                  |
//+------------------------------------------------------------------+
bool HttpGet(string url, string &responseBody, int &httpCode)
  {
   char postData[];
   char result[];
   string resultHeaders;

   ResetLastError();
   httpCode = WebRequest("GET", url, "Content-Type: application/json\r\n", APITimeout, postData, result, resultHeaders);

   if(httpCode == -1)
     {
      int err = GetLastError();
      Print("HTTP GET failed. Error: ", err,
            ". Make sure URL is added in Tools > Options > Expert Advisors > Allow WebRequest for listed URL: ", APIBaseUrl);
      return false;
     }

   responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
  }

//+------------------------------------------------------------------+
//| HTTP POST request with JSON body                                  |
//+------------------------------------------------------------------+
bool HttpPost(string url, string jsonBody, string &responseBody, int &httpCode)
  {
   char postData[];
   char result[];
   string resultHeaders;

   StringToCharArray(jsonBody, postData, 0, StringLen(jsonBody), CP_UTF8);

   ResetLastError();
   httpCode = WebRequest("POST", url, "Content-Type: application/json\r\n", APITimeout, postData, result, resultHeaders);

   if(httpCode == -1)
     {
      int err = GetLastError();
      Print("HTTP POST failed. Error: ", err,
            ". Make sure URL is added in Tools > Options > Expert Advisors > Allow WebRequest for listed URL: ", APIBaseUrl);
      return false;
     }

   responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);

   EventSetTimer(PollIntervalSec);

   Print("SMC API Signal EA initialized (v2.0)");
   Print("   Chart Symbol: ", _Symbol, " | API Symbol: ", APISymbol, " | API: ", BuildUrl(""));
   Print("   Lot: ", FixedLot, " | Magic: ", MagicNumber, " | Poll: ", PollIntervalSec, "s");
   Print("   IMPORTANT: Add '", APIBaseUrl, "' to Tools > Options > Expert Advisors > Allow WebRequest");

   // Test API connectivity
   string responseBody;
   int httpCode;
   string testUrl = BuildUrl("/api/trade/latest-signal?symbol=" + APISymbol);
   if(HttpGet(testUrl, responseBody, httpCode))
     {
      Print("API connectivity OK. HTTP ", httpCode);
     }
   else
     {
      Print("WARNING: API connectivity test failed. Will retry on timer.");
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("SMC API Signal EA stopped. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Count open positions for this symbol + magic                      |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            count++;
           }
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Close all positions of specified type (0=BUY, 1=SELL)             |
//+------------------------------------------------------------------+
bool ClosePositionsByType(int posType)
  {
   bool allClosed = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            int type = (int)PositionGetInteger(POSITION_TYPE);
            if(type == posType)
              {
               if(!trade.PositionClose(ticket))
                 {
                  Print("Failed to close position #", ticket, ": ", trade.ResultRetcodeDescription());
                  allClosed = false;
                 }
               else
                 {
                  Print("Closed position #", ticket);
                 }
              }
           }
        }
     }
   return allClosed;
  }

//+------------------------------------------------------------------+
//| Read signal from API: GET /api/trade/latest-signal?symbol=XXX     |
//+------------------------------------------------------------------+
bool ReadSignalFromAPI(SignalData &signal)
  {
   string url = BuildUrl("/api/trade/latest-signal?symbol=" + APISymbol);
   string responseBody;
   int httpCode;

   if(!HttpGet(url, responseBody, httpCode))
     {
      g_apiFailCount++;
      if(g_apiFailCount % 10 == 1)
         Print("API call failed (count: ", g_apiFailCount, ")");
      return false;
     }

   // HTTP 204 = no active signal
   if(httpCode == 204 || StringLen(responseBody) == 0)
      return false;

   if(httpCode != 200)
     {
      Print("API returned HTTP ", httpCode, ": ", responseBody);
      return false;
     }

   // Reset fail counter on success
   g_apiFailCount = 0;

   // Parse JSON response
   signal.signal_id       = JsonGetInt(responseBody, "signalId");
   signal.symbol          = JsonGetString(responseBody, "symbol");
   signal.pitch_fan       = JsonGetString(responseBody, "pitchFan");
   signal.macd_hist1      = JsonGetString(responseBody, "macdHist1");
   signal.macd_hist2      = JsonGetString(responseBody, "macdHist2");
   signal.macd1_sig_cross = JsonGetString(responseBody, "macd1SigCross");
   signal.macd2_sig_cross = JsonGetString(responseBody, "macd2SigCross");
   signal.fvg             = JsonGetString(responseBody, "fvg");
   signal.ob              = JsonGetString(responseBody, "ob");
   signal.bb              = JsonGetString(responseBody, "bb");
   signal.rb              = JsonGetString(responseBody, "rb");
   signal.blue_mode       = JsonGetString(responseBody, "blueMode");
   signal.sl              = JsonGetDouble(responseBody, "sl");
   signal.fibo_0_5        = JsonGetDouble(responseBody, "fibo0_5");
   signal.fibo_61_8       = JsonGetDouble(responseBody, "fibo61_8");
   signal.fibo_poc        = JsonGetDouble(responseBody, "fiboPoc");
   signal.close_status    = JsonGetString(responseBody, "closeStatus");
   signal.is_active       = JsonGetString(responseBody, "isActive");
   signal.trade_action    = JsonGetString(responseBody, "tradeAction");

   if(signal.signal_id == 0)
     {
      Print("WARNING: Parsed signal_id is 0. Raw response: ", StringSubstr(responseBody, 0, 200));
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Update close_status via API: POST /api/trade/update-status        |
//+------------------------------------------------------------------+
bool UpdateCloseStatus(int signalId, string status="closed")
  {
   string url = BuildUrl("/api/trade/update-status");
   string jsonBody = "{\"signalId\":" + IntegerToString(signalId) + ",\"status\":\"" + status + "\"}";
   string responseBody;
   int httpCode;

   if(!HttpPost(url, jsonBody, responseBody, httpCode))
     {
      Print("Failed to update close_status for signal_id=", signalId);
      return false;
     }

   if(httpCode != 200)
     {
      Print("Update status API returned HTTP ", httpCode, ": ", responseBody);
      return false;
     }

   Print("Updated close_status='", status, "' for signal_id=", signalId, " via API");
   return true;
  }

//+------------------------------------------------------------------+
//| Reset a single ICT signal via API (fvg/ob/bb/rb)                 |
//| POST /api/trade/{endpoint} with action='' to clear it            |
//+------------------------------------------------------------------+
bool ResetSignalViaAPI(string endpoint, string indicator)
  {
   string url = BuildUrl("/api/trade/" + endpoint);
   string jsonBody = "{\"symbol\":\"" + APISymbol + "\",\"indicator\":\"" + indicator + "\",\"action\":\"\"}";
   string responseBody;
   int httpCode;

   if(!HttpPost(url, jsonBody, responseBody, httpCode))
     {
      Print("Failed to reset ", endpoint, " signal via API");
      return false;
     }

   if(httpCode != 200)
     {
      Print("Reset ", endpoint, " API returned HTTP ", httpCode, ": ", responseBody);
      return false;
     }

   Print("Reset ", endpoint, " signal (action='') for ", APISymbol);
   return true;
  }

//+------------------------------------------------------------------+
//| Reset all close-triggering signals so EA waits for new ones       |
//+------------------------------------------------------------------+
void ResetCloseSignals(const SignalData &signal, int posType)
  {
   if(posType == 0) // BUY position - reset bearish signals
     {
      if(signal.fvg == "FVG_BEAR") ResetSignalViaAPI("fvg", "fvg");
      if(signal.ob == "OB_BEAR")   ResetSignalViaAPI("ob", "ob");
      if(signal.bb == "BB_BEAR")   ResetSignalViaAPI("bb", "bb");
      if(signal.rb == "RB_BEAR")   ResetSignalViaAPI("rb", "rb");
     }
   else // SELL position - reset bullish signals
     {
      if(signal.fvg == "FVG_BULL") ResetSignalViaAPI("fvg", "fvg");
      if(signal.ob == "OB_BULL")   ResetSignalViaAPI("ob", "ob");
      if(signal.bb == "BB_BULL")   ResetSignalViaAPI("bb", "bb");
      if(signal.rb == "RB_BULL")   ResetSignalViaAPI("rb", "rb");
     }
  }

//+------------------------------------------------------------------+
//| Reset MACD entry signals via API after order is opened            |
//+------------------------------------------------------------------+
bool ResetMacdViaAPI(string endpoint)
  {
   string url = BuildUrl("/api/trade/" + endpoint);
   string jsonBody = "{\"symbol\":\"" + APISymbol + "\",\"action\":\"\"}";
   string responseBody;
   int httpCode;

   if(!HttpPost(url, jsonBody, responseBody, httpCode))
     {
      Print("Failed to reset ", endpoint, " via API");
      return false;
     }

   if(httpCode != 200)
     {
      Print("Reset ", endpoint, " API returned HTTP ", httpCode, ": ", responseBody);
      return false;
     }

   Print("Reset ", endpoint, " (action='') for ", APISymbol);
   return true;
  }

//+------------------------------------------------------------------+
//| Reset all entry signals after order is opened to prevent re-use   |
//+------------------------------------------------------------------+
void ResetEntrySignals()
  {
   ResetMacdViaAPI("macd_hist1");
   ResetMacdViaAPI("macd_hist2");
  }

//+------------------------------------------------------------------+
//| Get Lowest Low over the last N bars (excluding current bar)      |
//+------------------------------------------------------------------+
double GetSwingLow(int bars)
  {
   double lowest = 999999;
   double lowArr[];
   ArraySetAsSeries(lowArr, true);
   if(CopyLow(_Symbol, 0, 1, bars, lowArr) > 0)
     {
      int minIdx = ArrayMinimum(lowArr);
      if(minIdx >= 0) lowest = lowArr[minIdx];
     }

   if(lowest == 999999) return SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return lowest;
  }

//+------------------------------------------------------------------+
//| Get Highest High over the last N bars (excluding current bar)    |
//+------------------------------------------------------------------+
double GetSwingHigh(int bars)
  {
   double highest = 0;
   double highArr[];
   ArraySetAsSeries(highArr, true);
   if(CopyHigh(_Symbol, 0, 1, bars, highArr) > 0)
     {
      int maxIdx = ArrayMaximum(highArr);
      if(maxIdx >= 0) highest = highArr[maxIdx];
     }

   if(highest == 0) return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return highest;
  }

//+------------------------------------------------------------------+
//| Get profit in points for our active position                      |
//| BUY:  (current_bid - open_price) / _Point                        |
//| SELL: (open_price - current_ask) / _Point                        |
//+------------------------------------------------------------------+
double GetPositionProfitPoints(int posType)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (int)PositionGetInteger(POSITION_TYPE) == posType)
           {
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            if(posType == 0) // BUY
               return (SymbolInfoDouble(_Symbol, SYMBOL_BID) - openPrice) / _Point;
            else             // SELL
               return (openPrice - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / _Point;
           }
        }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Check if close condition is met for BUY positions                 |
//+------------------------------------------------------------------+
bool ShouldCloseBuy(const SignalData &signal)
  {
   if(signal.fvg == "FVG_BEAR" || signal.ob == "OB_BEAR" || signal.bb == "BB_BEAR" || signal.rb == "RB_BEAR")
     {
      Print("Close BUY condition met -> fvg: ", signal.fvg, " | ob: ", signal.ob, " | bb: ", signal.bb, " | rb: ", signal.rb);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check if close condition is met for SELL positions                |
//+------------------------------------------------------------------+
bool ShouldCloseSell(const SignalData &signal)
  {
   if(signal.fvg == "FVG_BULL" || signal.ob == "OB_BULL" || signal.bb == "BB_BULL" || signal.rb == "RB_BULL")
     {
      Print("Close SELL condition met -> fvg: ", signal.fvg, " | ob: ", signal.ob, " | bb: ", signal.bb, " | rb: ", signal.rb);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Open a BUY order                                                  |
//+------------------------------------------------------------------+
bool OpenBuyOrder(double slPrice)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask == 0)
     {
      Print("Cannot get ASK price");
      return false;
     }

   if(slPrice > 0)
     {
      slPrice = slPrice - SLBufferPoints * _Point;
      if(slPrice >= ask)
        {
         Print("SL (", slPrice, ") >= ASK (", ask, "). Setting SL = 0 (no SL)");
         slPrice = 0;
        }
     }

   double lot = MathMin(FixedLot, MaxLot);
   lot = NormalizeDouble(lot, 2);

   string comment = "SMC_API_" + IntegerToString(g_currentSignal.signal_id);

   Print("Opening BUY: ", _Symbol, " Lot=", lot, " SL=", slPrice);

   if(trade.Buy(lot, _Symbol, 0, slPrice, 0, comment))
     {
      Print("BUY Order Placed! Ticket: ", trade.ResultOrder());
      Print("   Price: ", trade.ResultPrice(), " SL: ", slPrice);
      return true;
     }
   else
     {
      Print("BUY Failed! Error: ", trade.ResultRetcodeDescription());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Open a SELL order                                                 |
//+------------------------------------------------------------------+
bool OpenSellOrder(double slPrice)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid == 0)
     {
      Print("Cannot get BID price");
      return false;
     }

   if(slPrice > 0)
     {
      slPrice = slPrice + SLBufferPoints * _Point;
      if(slPrice <= bid)
        {
         Print("SL (", slPrice, ") <= BID (", bid, "). Setting SL = 0 (no SL)");
         slPrice = 0;
        }
     }

   double lot = MathMin(FixedLot, MaxLot);
   lot = NormalizeDouble(lot, 2);

   string comment = "SMC_API_" + IntegerToString(g_currentSignal.signal_id);

   Print("Opening SELL: ", _Symbol, " Lot=", lot, " SL=", slPrice);

   if(trade.Sell(lot, _Symbol, 0, slPrice, 0, comment))
     {
      Print("SELL Order Placed! Ticket: ", trade.ResultOrder());
      Print("   Price: ", trade.ResultPrice(), " SL: ", slPrice);
      return true;
     }
   else
     {
      Print("SELL Failed! Error: ", trade.ResultRetcodeDescription());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Main Timer function - polls API and manages trades                |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //--- Step 1: Read latest signal from API (uses APISymbol, orders use chart _Symbol)
   SignalData signal;
   if(!ReadSignalFromAPI(signal))
      return;

   g_currentSignal = signal;

   //--- Step 2: Check if we have an active order to manage
   int openCount = CountOpenPositions();

   if(g_hasActiveOrder && openCount > 0)
     {
      bool shouldClose = false;

      if(g_activeOrderType == 0)
         shouldClose = ShouldCloseBuy(signal);
      else if(g_activeOrderType == 1)
         shouldClose = ShouldCloseSell(signal);

      if(shouldClose)
        {
         double profitPts = GetPositionProfitPoints(g_activeOrderType);
         string typeStr = (g_activeOrderType == 0) ? "BUY" : "SELL";

         if(TargetProfitPoints > 0 && profitPts < TargetProfitPoints)
           {
            Print("Close signal for ", typeStr, " but profit ", NormalizeDouble(profitPts, 1),
                  " pts < target ", TargetProfitPoints, " pts. Resetting signals, waiting for new close signal.");
            ResetCloseSignals(signal, g_activeOrderType);
           }
         else
           {
            Print("Closing ", typeStr, " position for signal_id=", g_lastSignalId,
                  " | Profit: ", NormalizeDouble(profitPts, 1), " pts");

            bool closed = ClosePositionsByType(g_activeOrderType);
            if(closed)
              {
               UpdateCloseStatus(g_lastSignalId);

               g_hasActiveOrder = false;
               g_activeOrderType = -1;
               g_lastSignalId = 0;
               g_activeSignalAction = "";

               Print("Cycle complete. Ready for next signal.");
              }
           }
        }

      return;
     }

   //--- If we thought we had an order but it's gone (e.g., SL hit)
   if(g_hasActiveOrder && openCount == 0)
     {
      Print("Active order was closed externally (SL/TP hit). Resetting cycle.");
      UpdateCloseStatus(g_lastSignalId);
      g_hasActiveOrder = false;
      g_activeOrderType = -1;
      g_lastSignalId = 0;
      g_activeSignalAction = "";
     }

   //--- Step 3: No active order - check if we should open one

   if(signal.trade_action != "enabled")
     {
      if(g_pendingSetup != -1)
        {
         Print("Trade action is '", signal.trade_action, "'. Cancelling pending setup.");
         g_pendingSetup = -1;
         g_pendingSignalId = 0;
        }
      return;
     }

   //--- Priority 1: Check for Blue Mode setup
   if(signal.blue_mode == "liq_bear")
     {
      if(g_pendingSetup != 0)
        {
         Print("Priority 1 Met: BUY Setup Initialized (Blue Mode: liq_bear). Waiting for MACD buy...");
         g_pendingSetup = 0;
         g_pendingSignalId = signal.signal_id;
        }
     }
   else if(signal.blue_mode == "liq_bull")
     {
      if(g_pendingSetup != 1)
        {
         Print("Priority 1 Met: SELL Setup Initialized (Blue Mode: liq_bull). Waiting for MACD sell...");
         g_pendingSetup = 1;
         g_pendingSignalId = signal.signal_id;
        }
     }
   else
     {
      if(g_pendingSetup != -1)
        {
         Print("Blue Mode changed to '", signal.blue_mode, "'. Cancelling pending ",
               (g_pendingSetup == 0) ? "BUY" : "SELL", " setup.");
         g_pendingSetup = -1;
         g_pendingSignalId = 0;
        }
     }

   if(g_pendingSetup != -1)
     {
      string setupStr = (g_pendingSetup == 0) ? "BUY" : "SELL";
      Print("Waiting for Priority 2 (macd_hist1/macd_hist2) to confirm ", setupStr, " setup...");
     }

   //--- Priority 2: Check for MACD trigger (either macd_hist1 OR macd_hist2)
   if(g_pendingSetup == 0 && (signal.macd_hist1 == "buy" || signal.macd_hist2 == "buy"))
     {
      Print("Priority 2 Met: BUY Triggered (macd_hist1: ", signal.macd_hist1, ", macd_hist2: ", signal.macd_hist2, ")!");
      double swingSL = GetSwingLow(SwingBars);

      if(OpenBuyOrder(swingSL))
        {
         g_hasActiveOrder = true;
         g_activeOrderType = 0;
         g_lastSignalId = signal.signal_id;
         g_activeSignalAction = "buy";
         g_pendingSetup = -1;
         UpdateCloseStatus(signal.signal_id, "open");
         ResetEntrySignals();
        }
     }
   else if(g_pendingSetup == 1 && (signal.macd_hist1 == "sell" || signal.macd_hist2 == "sell"))
     {
      Print("Priority 2 Met: SELL Triggered (macd_hist1: ", signal.macd_hist1, ", macd_hist2: ", signal.macd_hist2, ")!");
      double swingSL = GetSwingHigh(SwingBars);

      if(OpenSellOrder(swingSL))
        {
         g_hasActiveOrder = true;
         g_activeOrderType = 1;
         g_lastSignalId = signal.signal_id;
         g_activeSignalAction = "sell";
         g_pendingSetup = -1;
         UpdateCloseStatus(signal.signal_id, "open");
         ResetEntrySignals();
        }
     }
   else if(signal.signal_id != g_lastSignalId)
     {
      g_lastSignalId = signal.signal_id;
     }
  }

//+------------------------------------------------------------------+
//| Tick function (not used - logic is timer-based)                   |
//+------------------------------------------------------------------+
void OnTick()
  {
  }
//+------------------------------------------------------------------+
