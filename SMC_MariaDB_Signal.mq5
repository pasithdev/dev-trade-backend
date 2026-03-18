//+------------------------------------------------------------------+
//|                                          SMC_MariaDB_Signal.mq5  |
//|                   Signal-based EA with MariaDB connectivity       |
//|                   Reads signals from DB, opens/closes trades      |
//+------------------------------------------------------------------+
#property copyright "DevTrade"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include "Include\MQLMySQL.mqh"

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+
input string   DBHost           = "localhost";       // MariaDB Host
input uint     DBPort           = 3306;              // MariaDB Port
input string   DBUser           = "root";            // Database User
input string   DBPassword       = "pasith1234";      // Database Password
input string   DBName           = "devtrade";        // Database Name
input string   DBTable          = "signals";         // Signal Table Name
input string   TradeSymbol      = "XAUUSD";          // Symbol to trade
input double   FixedLot         = 0.01;              // Lot Size
input double   MaxLot           = 1.0;               // Max Lot Size
input int      MagicNumber      = 20260312;          // EA Magic Number
input int      PollIntervalSec  = 5;                 // DB Poll Interval (seconds)
input int      SLBufferPoints   = 50;                // Extra SL buffer (points)
input int      SwingBars        = 20;                // Bars to look back for SL calculation

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CTrade         trade;
bool           g_db_connected       = false;
int            g_lastSignalId       = 0;       // Currently active/tracked signal_id
bool           g_hasActiveOrder     = false;    // Is there an active order for this cycle?
int            g_activeOrderType    = -1;       // 0=BUY, 1=SELL
string         g_activeSignalAction = "";       // The action that opened the order
int            g_pendingSetup       = -1;       // -1=None, 0=BUY Pending, 1=SELL Pending
int            g_pendingSignalId    = 0;        // Signal ID that triggered the setup

// Signal data structure
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
   double         sl;
   double         fibo_0_5;
   double         fibo_61_8;
   double         fibo_poc;
   string         close_status;
   string         is_active;
  };

SignalData g_currentSignal;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Set magic number
   trade.SetExpertMagicNumber(MagicNumber);

   // Try initial DB connection
   g_db_connected = MySqlConnect(DBHost, DBPort, DBUser, DBPassword, DBName);
   if(!g_db_connected)
     {
      Print("⚠ Initial DB connection failed. Will retry on timer.");
     }

   // Start timer
   EventSetTimer(PollIntervalSec);
   Print("🚀 SMC MariaDB Signal EA initialized");
   Print("   Symbol: ", TradeSymbol, " | DB: ", DBHost, ":", DBPort, "/", DBName);
   Print("   Lot: ", FixedLot, " | Magic: ", MagicNumber, " | Poll: ", PollIntervalSec, "s");

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   MySqlDisconnect();
   g_db_connected = false;
   Print("🛑 SMC MariaDB Signal EA stopped. Reason: ", reason);
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
                  Print("❌ Failed to close position #", ticket, ": ", trade.ResultRetcodeDescription());
                  allClosed = false;
                 }
               else
                 {
                  Print("✅ Closed position #", ticket);
                 }
              }
           }
        }
     }
   return allClosed;
  }

//+------------------------------------------------------------------+
//| Read signal from MariaDB                                          |
//| SELECT * WHERE signal_id = MAX AND symbol = XAUUSD AND is_active=Y|
//+------------------------------------------------------------------+
bool ReadSignalFromDB(SignalData &signal)
  {
   // Build query: get the row with max signal_id for XAUUSD where is_active='Y'
   string query = "SELECT signal_id, symbol, pitch_fan, macd_hist1, macd_hist2, "
                  "macd1_sig_cross, macd2_sig_cross, fvg, ob, bb, rb, "
                  "sl, fibo_0_5, fibo_61_8, fibo_poc, close_status, is_active "
                  "FROM " + DBTable + " "
                  "WHERE symbol = '" + TradeSymbol + "' "
                  "AND is_active = 'Y' "
                  "ORDER BY signal_id DESC LIMIT 1";

   int cursor = MySqlCursorOpen(query);
   if(cursor == 0)
     {
      Print("❌ Failed to execute signal query");
      return false;
     }

   int rows = MySqlCursorRows(cursor);
   if(rows <= 0)
     {
      MySqlCursorClose(cursor);
      return false;
     }

   // Fetch the row
   int row = MySqlCursorFetchRow(cursor);
   if(row == 0)
     {
      MySqlCursorClose(cursor);
      return false;
     }

   // Read all fields (0-indexed matching SELECT order)
   signal.signal_id       = (int)StringToInteger(MySqlGetFieldValue(row, 0));
   signal.symbol          = MySqlGetFieldValue(row, 1);
   signal.pitch_fan       = MySqlGetFieldValue(row, 2);
   signal.macd_hist1      = MySqlGetFieldValue(row, 3);
   signal.macd_hist2      = MySqlGetFieldValue(row, 4);
   signal.macd1_sig_cross = MySqlGetFieldValue(row, 5);
   signal.macd2_sig_cross = MySqlGetFieldValue(row, 6);
   signal.fvg             = MySqlGetFieldValue(row, 7);
   signal.ob              = MySqlGetFieldValue(row, 8);
   signal.bb              = MySqlGetFieldValue(row, 9);
   signal.rb              = MySqlGetFieldValue(row, 10);
   signal.sl              = StringToDouble(MySqlGetFieldValue(row, 11));
   signal.fibo_0_5        = StringToDouble(MySqlGetFieldValue(row, 12));
   signal.fibo_61_8       = StringToDouble(MySqlGetFieldValue(row, 13));
   signal.fibo_poc        = StringToDouble(MySqlGetFieldValue(row, 14));
   signal.close_status    = MySqlGetFieldValue(row, 15);
   signal.is_active       = MySqlGetFieldValue(row, 16);

   MySqlCursorClose(cursor);
   return true;
  }

//+------------------------------------------------------------------+
//| Update close_status in database                                   |
//+------------------------------------------------------------------+
bool UpdateCloseStatus(int signalId)
  {
   string query = "UPDATE " + DBTable + " SET close_status = 'closed', is_active = 'N' "
                  "WHERE signal_id = " + IntegerToString(signalId);

   if(!MySqlExecute(query))
     {
      Print("❌ Failed to update close_status for signal_id=", signalId);
      return false;
     }

   Print("✅ Updated close_status='closed' for signal_id=", signalId);
   return true;
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
   
   // Fallback to current BID if calculation fails
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
   
   // Fallback to current ASK if calculation fails
   if(highest == 0) return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return highest;
  }

//+------------------------------------------------------------------+
//| Check if close condition is met for BUY positions                 |
//+------------------------------------------------------------------+
bool ShouldCloseBuy(const SignalData &signal)
  {
   // Close BUY when ANY bearish signal appears across the fields
   if(signal.fvg == "FVG_BEAR" || signal.ob == "OB_BEAR" || signal.bb == "BB_BEAR" || signal.rb == "RB_BEAR")
     {
      Print("📉 Close BUY condition met -> fvg: ", signal.fvg, " | ob: ", signal.ob, " | bb: ", signal.bb, " | rb: ", signal.rb);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Check if close condition is met for SELL positions                |
//+------------------------------------------------------------------+
bool ShouldCloseSell(const SignalData &signal)
  {
   // Close SELL when ANY bullish signal appears across the fields
   if(signal.fvg == "FVG_BULL" || signal.ob == "OB_BULL" || signal.bb == "BB_BULL" || signal.rb == "RB_BULL")
     {
      Print("📈 Close SELL condition met -> fvg: ", signal.fvg, " | ob: ", signal.ob, " | bb: ", signal.bb, " | rb: ", signal.rb);
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
      Print("❌ Cannot get ASK price");
      return false;
     }

   // Validate and adjust SL
   if(slPrice > 0)
     {
      // Add buffer to SL
      slPrice = slPrice - SLBufferPoints * _Point;
      // Ensure SL is below current price for BUY
      if(slPrice >= ask)
        {
         Print("⚠ SL (", slPrice, ") >= ASK (", ask, "). Setting SL = 0 (no SL)");
         slPrice = 0;
        }
     }

   double lot = MathMin(FixedLot, MaxLot);
   lot = NormalizeDouble(lot, 2);

   string comment = "SMC_DB_" + IntegerToString(g_currentSignal.signal_id);

   Print("🟢 Opening BUY: ", _Symbol, " Lot=", lot, " SL=", slPrice);

   if(trade.Buy(lot, _Symbol, 0, slPrice, 0, comment))
     {
      Print("✅ BUY Order Placed! Ticket: ", trade.ResultOrder());
      Print("   Price: ", trade.ResultPrice(), " SL: ", slPrice);
      return true;
     }
   else
     {
      Print("❌ BUY Failed! Error: ", trade.ResultRetcodeDescription());
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
      Print("❌ Cannot get BID price");
      return false;
     }

   // Validate and adjust SL
   if(slPrice > 0)
     {
      // Add buffer to SL
      slPrice = slPrice + SLBufferPoints * _Point;
      // Ensure SL is above current price for SELL
      if(slPrice <= bid)
        {
         Print("⚠ SL (", slPrice, ") <= BID (", bid, "). Setting SL = 0 (no SL)");
         slPrice = 0;
        }
     }

   double lot = MathMin(FixedLot, MaxLot);
   lot = NormalizeDouble(lot, 2);

   string comment = "SMC_DB_" + IntegerToString(g_currentSignal.signal_id);

   Print("🔴 Opening SELL: ", _Symbol, " Lot=", lot, " SL=", slPrice);

   if(trade.Sell(lot, _Symbol, 0, slPrice, 0, comment))
     {
      Print("✅ SELL Order Placed! Ticket: ", trade.ResultOrder());
      Print("   Price: ", trade.ResultPrice(), " SL: ", slPrice);
      return true;
     }
   else
     {
      Print("❌ SELL Failed! Error: ", trade.ResultRetcodeDescription());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Main Timer function - polls DB and manages trades                 |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Ensure we are on the correct symbol (allowing for broker suffixes like XAUUSD.m)
   if(StringFind(_Symbol, TradeSymbol) < 0)
     {
      static bool warned = false;
      if(!warned)
        {
         Print("⚠ EA is on ", _Symbol, " but configured for ", TradeSymbol, ". Please attach to correct chart.");
         warned = true;
        }
      return;
     }

   //--- Step 1: Ensure DB connection
   if(!g_db_connected)
     {
      g_db_connected = MySqlConnect(DBHost, DBPort, DBUser, DBPassword, DBName);
      if(!g_db_connected)
        {
         Print("⚠ DB reconnection failed. Will retry...");
         return;
        }
     }

   //--- Step 2: Read latest signal from DB
   SignalData signal;
   if(!ReadSignalFromDB(signal))
     {
      // No active signal found - nothing to do
      return;
     }

   // Store current signal globally
   g_currentSignal = signal;

   //--- Step 3: Check if we have an active order to manage
   int openCount = CountOpenPositions();

   if(g_hasActiveOrder && openCount > 0)
     {
      //--- We have an active order - check close conditions
      bool shouldClose = false;

      if(g_activeOrderType == 0)  // BUY position
        {
         shouldClose = ShouldCloseBuy(signal);
        }
      else if(g_activeOrderType == 1)  // SELL position
        {
         shouldClose = ShouldCloseSell(signal);
        }

      if(shouldClose)
        {
         Print("🔄 Closing position for signal_id=", g_lastSignalId);

         // Close the position
         bool closed = ClosePositionsByType(g_activeOrderType);
         if(closed)
           {
            // Update close_status in database
            UpdateCloseStatus(g_lastSignalId);

            // Reset cycle - ready for next signal
            g_hasActiveOrder = false;
            g_activeOrderType = -1;
            g_lastSignalId = 0;
            g_activeSignalAction = "";

            Print("🔄 Cycle complete. Ready for next signal.");
           }
        }

      return;  // Don't open new orders while managing an existing one
     }

   //--- If we thought we had an order but it's gone (e.g., SL hit)
   if(g_hasActiveOrder && openCount == 0)
     {
      Print("⚠ Active order was closed externally (SL/TP hit). Resetting cycle.");
      // Update close_status in database
      UpdateCloseStatus(g_lastSignalId);
      g_hasActiveOrder = false;
      g_activeOrderType = -1;
      g_lastSignalId = 0;
      g_activeSignalAction = "";
     }

   //--- Step 4: No active order - check if we should open one
   
   //--- Priority 1: Check for PitchFan setup
   if(signal.pitch_fan == "above_blue_1R")
     {
      if(g_pendingSetup != 0)
        {
         Print("🎯 Priority 1 Met: BUY Setup Initialized (PitchFan: above_blue_1R). Waiting for MACD buy...");
         g_pendingSetup = 0;
         g_pendingSignalId = signal.signal_id;
        }
     }
   else if(signal.pitch_fan == "below_blue_1S")
     {
      if(g_pendingSetup != 1)
        {
         Print("🎯 Priority 1 Met: SELL Setup Initialized (PitchFan: below_blue_1S). Waiting for MACD sell...");
         g_pendingSetup = 1;
         g_pendingSignalId = signal.signal_id;
        }
     }

   // Optional: Log waiting status periodically if setup is pending
   if(g_pendingSetup != -1)
     {
      string setupStr = (g_pendingSetup == 0) ? "BUY" : "SELL";
      Print("⏳ Waiting for Priority 2 (macd_hist1) to confirm ", setupStr, " setup...");
     }

   //--- Priority 2: Check for MACD trigger
   if(g_pendingSetup == 0 && signal.macd_hist1 == "buy")
     {
      Print("🔥 Priority 2 Met: BUY Triggered (macd_hist1: buy)!");
      // Calculate dynamic SL via Swing Low
      double swingSL = GetSwingLow(SwingBars);
      
      if(OpenBuyOrder(swingSL))
        {
         g_hasActiveOrder = true;
         g_activeOrderType = 0;  // BUY
         g_lastSignalId = signal.signal_id;
         g_activeSignalAction = "buy";
         g_pendingSetup = -1;  // Reset setup state
        }
     }
   else if(g_pendingSetup == 1 && signal.macd_hist1 == "sell")
     {
      Print("🔥 Priority 2 Met: SELL Triggered (macd_hist1: sell)!");
      // Calculate dynamic SL via Swing High
      double swingSL = GetSwingHigh(SwingBars);
      
      if(OpenSellOrder(swingSL))
        {
         g_hasActiveOrder = true;
         g_activeOrderType = 1;  // SELL
         g_lastSignalId = signal.signal_id;
         g_activeSignalAction = "sell";
         g_pendingSetup = -1;  // Reset setup state
        }
     }
   else if(signal.signal_id != g_lastSignalId)
     {
      // No entry trigger met for this signal ID yet
      g_lastSignalId = signal.signal_id;
     }
  }

//+------------------------------------------------------------------+
//| Tick function (not used - logic is timer-based)                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   // All logic is handled in OnTimer()
   // OnTick is kept for potential future use
  }
//+------------------------------------------------------------------+
