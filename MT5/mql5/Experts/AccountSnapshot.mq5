//+------------------------------------------------------------------+
//|                                                  AccountSnapshot.mq5 |
//|                        Copyright 2026, Ishan Parihar              |
//|                                       AD-12 MT5 Log Checker      |
//+------------------------------------------------------------------+
#property copyright "AD-12"
#property version   "4.02"
#property strict

// AccountSnapshot.mq5 v4 — comprehensive account state dump.
//
// Attach to ANY chart (recommend a dedicated XAUUSDc M1 chart). Writes to
// MQL5/Files/account_snapshot.json (FILE_COMMON).
//
// v4 changes:
//   - FIX: History now uses HistorySelect with explicit deal-type filter
//   - FIX: Added HistoryDealsTotal() debug logging
//   - Added peak_equity + drawdown tracking (static persistent)
//   - Added margin_utilization percentage
//   - Added symbol_exposure aggregation
//   - Added strategy_performance per magic
//   - Added pending_orders from OrdersTotal()
//   - Added position_risks per open position (risk_pct, rr_ratio, hold_bars)
//   - Added avg_trade_stats (avg_win, avg_loss, profit_factor, expectancy)
//   - Added equity_snapshots (last 24 hourly points for curve)
// v4.01 changes:
//   - FIX: peak_equity persisted to file, restored on init (survives EA restarts)
//   - FIX: Rolling stats now include avg_win/avg_loss per period
// v4.02 changes:
//   - FIX: peak_equity now reconstructs historical peak from deal history on init
//   - FIX: Drawdown now reflects all-time peak (since account inception), not just EA-attach-time

input int SNAPSHOT_INTERVAL = 60;     // seconds between snapshots
input int HISTORY_DEALS = 100;         // number of closed deals to include
input int HISTORY_DAYS = 90;           // days of history to select

const string SNAPSHOT_FILE = "account_snapshot.json";
const string PEAK_FILE = "peak_equity.dat";  // persistent high-water mark

// Starting balance for historical peak reconstruction
static double s_startingBalance = 0.0;

// Persistent peak equity for drawdown tracking
static double s_peakEquity = 0.0;

// Hourly equity snapshots for curve (24 points)
static double s_equityHours[24];
static int s_equityTimes_h[24];  // hour component
static int s_equityTimes_d[24];  // day component
static int s_equityTimes_m[24];  // month component
static int s_equityTimes_y[24];  // year component
static int s_equityIdx = 0;

int OnInit()
{
    // Restore peak equity from persistent file (survives EA restarts)
    s_peakEquity = 0.0;
    int peakHandle = FileOpen(PEAK_FILE, FILE_READ|FILE_TXT|FILE_COMMON);
    if(peakHandle != INVALID_HANDLE)
    {
        string val = FileReadString(peakHandle);
        FileClose(peakHandle);
        s_peakEquity = StringToDouble(val);
        Print("[AccountSnapshot] Restored peak_equity=", DoubleToString(s_peakEquity, 2));
    }

    // ALSO query full deal history to find ALL-TIME peak balance (before EA was attached)
    double historicalPeak = FindHistoricalPeakBalance();
    if(historicalPeak > s_peakEquity)
    {
        s_peakEquity = historicalPeak;
        Print("[AccountSnapshot] Using historical peak: ", DoubleToString(s_peakEquity, 2));
    }

    // Fallback: use current equity if no persisted/historical value
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(s_peakEquity <= 0.0)
        s_peakEquity = currentEquity;

    // Also ensure peak is at least as high as current equity
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance > s_peakEquity) s_peakEquity = balance;
    if(currentEquity > s_peakEquity) s_peakEquity = currentEquity;

    ArrayInitialize(s_equityHours, 0.0);
    ArrayInitialize(s_equityTimes_h, 0);
    ArrayInitialize(s_equityTimes_d, 0);
    ArrayInitialize(s_equityTimes_m, 0);
    ArrayInitialize(s_equityTimes_y, 0);

    EventSetTimer(SNAPSHOT_INTERVAL);
    WriteSnapshot();  // write immediately on attach
    Print("[AccountSnapshot] v4.02 attached, interval=", SNAPSHOT_INTERVAL,
          "s, history=", HISTORY_DEALS, ", window=", HISTORY_DAYS, "d",
          ", peak=", DoubleToString(s_peakEquity, 2));
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
    EventKillTimer();
}

//+------------------------------------------------------------------+
//| Find historical peak balance from full deal history              |
//+------------------------------------------------------------------+
double FindHistoricalPeakBalance()
{
    // Select ALL history from account inception
    datetime from = 0;
    datetime to = TimeCurrent();
    
    if(!HistorySelect(from, to))
    {
        Print("[AccountSnapshot] WARNING: HistorySelect(ALL) failed, err=", GetLastError());
        return 0.0;
    }
    
    int totalDeals = HistoryDealsTotal();
    if(totalDeals <= 0)
    {
        Print("[AccountSnapshot] No deals in full history");
        return 0.0;
    }
    
    double runningBalance = 0.0;
    double peakBalance = 0.0;
    int processedDeals = 0;
    
    // Iterate oldest-first (index 0 = oldest) to reconstruct balance timeline
    for(int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket == 0) continue;
        
        long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
        long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
        double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
        double comm = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
        
        // Balance operations (deposits, withdrawals, credits)
        if(dealType == DEAL_TYPE_BALANCE)
        {
            runningBalance += profit;  // profit field contains the balance change
        }
        // Closed trades: DEAL_ENTRY_OUT, DEAL_ENTRY_INOUT, DEAL_ENTRY_OUT_BY
        else if((dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL) &&
                (dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT || dealEntry == DEAL_ENTRY_OUT_BY))
        {
            runningBalance += profit + swap + comm;
        }
        
        if(runningBalance > peakBalance)
            peakBalance = runningBalance;
        
        processedDeals++;
    }
    
    Print("[AccountSnapshot] Historical peak balance: ", DoubleToString(peakBalance, 2),
          " (from ", processedDeals, "/", totalDeals, " deals)");
    
    return peakBalance;
}

void OnTimer()
{
    WriteSnapshot();
}

void WriteSnapshot()
{
   // Persist peak equity to file (survives EA restarts)
   int peakHandle = FileOpen(PEAK_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(peakHandle != INVALID_HANDLE)
   {
      FileWriteString(peakHandle, DoubleToString(s_peakEquity, 2));
      FileClose(peakHandle);
   }

   string json = BuildSnapshotJson();
   int handle = FileOpen(SNAPSHOT_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_SHARE_READ, '\n');
   if(handle == INVALID_HANDLE)
   {
      Print("[AccountSnapshot] ERROR: cannot open ", SNAPSHOT_FILE, " err=", GetLastError());
      return;
   }
   FileWriteString(handle, json);
   FileClose(handle);
}

string BuildSnapshotJson()
{
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginLvl  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double profit     = AccountInfoDouble(ACCOUNT_PROFIT);
   int    leverage   = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   string currency   = AccountInfoString(ACCOUNT_CURRENCY);
   long   login      = AccountInfoInteger(ACCOUNT_LOGIN);
   string server     = AccountInfoString(ACCOUNT_SERVER);

   // Update peak equity for drawdown tracking
   if(equity > s_peakEquity) s_peakEquity = equity;
   double drawdownPct = s_peakEquity > 0 ? (s_peakEquity - equity) / s_peakEquity * 100.0 : 0.0;

   // Margin utilization
   double marginUtil = equity > 0 ? margin / equity * 100.0 : 0.0;

   // Hourly equity snapshot
   MqlDateTime dtNow;
   TimeLocal(dtNow);
   int currentHour = dtNow.hour;
   static int lastRecordedHour = -1;
   if(currentHour != lastRecordedHour)
   {
      s_equityHours[s_equityIdx] = equity;
      s_equityTimes_h[s_equityIdx] = dtNow.hour;
      s_equityTimes_d[s_equityIdx] = dtNow.day;
      s_equityTimes_m[s_equityIdx] = dtNow.mon;
      s_equityTimes_y[s_equityIdx] = dtNow.year;
      s_equityIdx = (s_equityIdx + 1) % 24;
      lastRecordedHour = currentHour;
   }

   // Local time when this write happens
   string writtenAt = StringFormat("%04d-%02d-%02dT%02d:%02d:%02d",
                                    dtNow.year, dtNow.mon, dtNow.day,
                                    dtNow.hour, dtNow.min, dtNow.sec);

   string s = "";
   s += "{\n";
   s += "  \"written_at\": \"" + writtenAt + "\",\n";
   s += "  \"ts\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",\n";
   s += "  \"balance\": "    + DoubleToString(balance, 2)    + ",\n";
   s += "  \"equity\": "     + DoubleToString(equity, 2)     + ",\n";
   s += "  \"margin\": "     + DoubleToString(margin, 2)     + ",\n";
   s += "  \"free_margin\": "+ DoubleToString(freeMargin, 2) + ",\n";
   s += "  \"margin_level\": "+ DoubleToString(marginLvl, 1) + ",\n";
   s += "  \"profit\": "     + DoubleToString(profit, 2)     + ",\n";
   s += "  \"leverage\": "   + IntegerToString(leverage)    + ",\n";
   s += "  \"currency\": \"" + currency + "\",\n";
   s += "  \"login\": "      + IntegerToString((int)login)  + ",\n";
   s += "  \"server\": \""   + server + "\",\n";
   s += "  \"peak_equity\": " + DoubleToString(s_peakEquity, 2) + ",\n";
   s += "  \"drawdown_pct\": " + DoubleToString(drawdownPct, 2) + ",\n";
   s += "  \"margin_utilization\": " + DoubleToString(marginUtil, 1) + ",\n";

   // ── Open positions ──
   s += "  \"positions\": [";
   bool first = true;
   int total = PositionsTotal();
   double totalOpenPnl = 0.0;
   double totalSwap = 0.0;
   double totalComm = 0.0;

   // Exposure aggregation
   // Using manual string concat since MQL5 doesn't have dict literals
   string symKeys = "";   // comma-separated unique symbols
   string symLots = "";   // parallel: lots per symbol
   string symPnl = "";    // parallel: pnl per symbol
   string symCount = "";  // parallel: count per symbol

   // Strategy aggregation
   string magKeys = "";
   string magPnl = "";
   string magCount = "";
   string magLots = "";

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string sym      = PositionGetString(POSITION_SYMBOL);
      int    type     = (int)PositionGetInteger(POSITION_TYPE);
      double lots     = PositionGetDouble(POSITION_VOLUME);
      double openPx   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPx    = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl       = PositionGetDouble(POSITION_SL);
      double tp       = PositionGetDouble(POSITION_TP);
      double pnl      = PositionGetDouble(POSITION_PROFIT);
      double swap     = PositionGetDouble(POSITION_SWAP);
      double comm     = PositionGetDouble(POSITION_COMMISSION);
      long   magic    = PositionGetInteger(POSITION_MAGIC);
      datetime openT  = (datetime)PositionGetInteger(POSITION_TIME);

      totalOpenPnl += pnl;
      totalSwap += swap;
      totalComm += comm;

      // Calculate unrealized PnL %
      double pnlPct = 0.0;
      if(openPx > 0.0)
         pnlPct = (pnl + swap + comm) / (lots * SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE) * openPx / leverage) * 100.0;

      // Position risk metrics
      double riskPct = 0.0;
      double rrRatio = 0.0;
      if(sl > 0 && equity > 0)
      {
         double slDist = MathAbs(curPx - sl);
         double contractSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize > 0 && tickValue > 0)
         {
            double riskMoney = slDist / tickSize * tickValue * lots;
            riskPct = riskMoney / equity * 100.0;
         }
      }
      if(sl > 0 && tp > 0 && MathAbs(curPx - sl) > 0)
      {
         rrRatio = MathAbs(tp - curPx) / MathAbs(curPx - sl);
      }

      // Hold duration (approximate bar count)
      int holdBars = (int)((TimeCurrent() - openT) / PeriodSeconds());

      // Aggregate by symbol
      int symIdx = StringFind(symKeys, sym);
      if(symIdx < 0)
      {
         if(symKeys != "") symKeys += ",";
         symKeys += sym;
         if(symLots != "") symLots += ",";
         symLots += DoubleToString(lots, 2);
         if(symPnl != "") symPnl += ",";
         symPnl += DoubleToString(pnl, 2);
         if(symCount != "") symCount += ",";
         symCount += "1";
      }
      else
      {
         // Find position of this symbol and update counts
         // Simple approach: rebuild each time is expensive, so we do it once at end
         // Actually, let's track via parallel arrays in a simpler way
      }

      // Aggregate by magic
      string magStr = IntegerToString((int)magic);
      int magIdx = StringFind(magKeys, magStr);
      if(magIdx < 0)
      {
         if(magKeys != "") magKeys += ",";
         magKeys += magStr;
         if(magLots != "") magLots += ",";
         magLots += DoubleToString(lots, 2);
         if(magPnl != "") magPnl += ",";
         magPnl += DoubleToString(pnl, 2);
         if(magCount != "") magCount += ",";
         magCount += "1";
      }

      // Position risk metrics
      double slDist = sl > 0 ? MathAbs(curPx - sl) : 0.0;
      double tpDist = tp > 0 ? MathAbs(tp - curPx) : 0.0;

      if(!first) s += ",";
      first = false;

      s += "\n    {";
      s += "\"ticket\": "         + IntegerToString((int)ticket) + ",";
      s += "\"symbol\": \""       + sym + "\",";
      s += "\"type\": \""          + (type == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",";
      s += "\"lots\": "           + DoubleToString(lots, 2) + ",";
      s += "\"open_price\": "     + DoubleToString(openPx, 5) + ",";
      s += "\"current_price\": "  + DoubleToString(curPx, 5) + ",";
      s += "\"sl\": "             + DoubleToString(sl, 5) + ",";
      s += "\"tp\": "             + DoubleToString(tp, 5) + ",";
      s += "\"profit\": "         + DoubleToString(pnl, 2) + ",";
      s += "\"swap\": "           + DoubleToString(swap, 2) + ",";
      s += "\"commission\": "     + DoubleToString(comm, 2) + ",";
      s += "\"pnl_pct\": "       + DoubleToString(pnlPct, 2) + ",";
      s += "\"magic\": "          + IntegerToString((int)magic) + ",";
      s += "\"open_time\": \""    + TimeToString(openT, TIME_DATE|TIME_SECONDS) + "\",";
      s += "\"hold_bars\": "     + IntegerToString(holdBars) + ",";
      s += "\"risk_pct\": "      + DoubleToString(riskPct, 2) + ",";
      s += "\"rr_ratio\": "      + DoubleToString(rrRatio, 2) + ",";
      s += "\"sl_dist\": "       + DoubleToString(slDist, 5) + ",";
      s += "\"tp_dist\": "       + DoubleToString(tpDist, 5);
      s += "}";
   }
   s += "\n  ],\n";

   // Position summary
   s += "  \"position_summary\": {\n";
   s += "    \"count\": " + IntegerToString(total) + ",\n";
   s += "    \"total_pnl\": " + DoubleToString(totalOpenPnl, 2) + ",\n";
   s += "    \"total_swap\": " + DoubleToString(totalSwap, 2) + ",\n";
   s += "    \"total_commission\": " + DoubleToString(totalComm, 2) + ",\n";
   s += "    \"total_net\": " + DoubleToString(totalOpenPnl + totalSwap + totalComm, 2) + "\n";
   s += "  },\n";

   // ── Symbol exposure ──
   // Rebuild aggregation properly using second pass
   s += "  \"symbol_exposure\": [";
   BuildSymbolExposure(s, total);
   s += "\n  ],\n";

   // ── Strategy performance ──
   s += "  \"strategy_performance\": [";
   BuildStrategyPerformance(s, total);
   s += "\n  ],\n";

   // ── Pending orders ──
   s += "  \"pending_orders\": [";
   BuildPendingOrders(s);
   s += "\n  ],\n";

   // ── Closed trade history ──
   double histPnl = 0.0, histSwap = 0.0, histComm = 0.0;
   int histWins = 0, histLosses = 0;
   double histAvgWin = 0.0, histAvgLoss = 0.0;
   int winCount = 0, lossCount = 0;
   s += "  \"history\": [";
   WriteClosedDeals(s, histPnl, histSwap, histComm, histWins, histLosses, histAvgWin, histAvgLoss, winCount, lossCount);

   // History summary
   int histTotal = histWins + histLosses;
   double profitFactor = histAvgLoss != 0 ? histAvgWin * winCount / (MathAbs(histAvgLoss) * lossCount) : 0.0;
   double expectancy = histTotal > 0 ? (histPnl + histSwap + histComm) / histTotal : 0.0;

   s += "  ],\n";
   s += "  \"history_summary\": {\n";
   s += "    \"count\": " + IntegerToString(histTotal) + ",\n";
   s += "    \"wins\": " + IntegerToString(histWins) + ",\n";
   s += "    \"losses\": " + IntegerToString(histLosses) + ",\n";
   s += "    \"win_rate\": " + DoubleToString(histTotal > 0 ? (double)histWins / histTotal * 100.0 : 0.0, 1) + ",\n";
   s += "    \"total_pnl\": " + DoubleToString(histPnl, 2) + ",\n";
   s += "    \"total_swap\": " + DoubleToString(histSwap, 2) + ",\n";
   s += "    \"total_commission\": " + DoubleToString(histComm, 2) + ",\n";
   s += "    \"total_net\": " + DoubleToString(histPnl + histSwap + histComm, 2) + ",\n";
   s += "    \"avg_win\": " + DoubleToString(histAvgWin, 2) + ",\n";
   s += "    \"avg_loss\": " + DoubleToString(histAvgLoss, 2) + ",\n";
   s += "    \"profit_factor\": " + DoubleToString(profitFactor, 2) + ",\n";
   s += "    \"expectancy\": " + DoubleToString(expectancy, 2) + "\n";
   s += "  },\n";

   // ── Rolling stats ──
   s += "  \"rolling\": {\n";
   WriteRollingStats(s);
   s += "\n  },\n";

   // ── Equity snapshots (last 24h hourly) ──
   s += "  \"equity_snapshots\": [";
   bool firstEq = true;
   for(int i = 0; i < 24; i++)
   {
      int idx = (s_equityIdx + i) % 24;
      if(s_equityHours[idx] <= 0.0) continue;
      if(!firstEq) s += ",";
      firstEq = false;
      string eqTime = StringFormat("%04d-%02d-%02d %02d:00",
                                    s_equityTimes_y[idx], s_equityTimes_m[idx],
                                    s_equityTimes_d[idx], s_equityTimes_h[idx]);
      s += "\n    {\"time\": \"" + eqTime + "\", \"equity\": " + DoubleToString(s_equityHours[idx], 2) + "}";
   }
   s += "\n  ]\n";
   s += "}\n";
   return s;
}

//+------------------------------------------------------------------+
//| Build symbol exposure aggregation                                  |
//+------------------------------------------------------------------+
void BuildSymbolExposure(string &s, int totalPos)
{
   // Collect unique symbols and aggregate
   string symbols[32];
   double lots[32];
   double pnl[32];
   int counts[32];
   int symCount = 0;

   for(int i = 0; i < totalPos && symCount < 32; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double l = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PROFIT);

      // Find existing
      int idx = -1;
      for(int j = 0; j < symCount; j++)
      {
         if(symbols[j] == sym) { idx = j; break; }
      }
      if(idx >= 0)
      {
         lots[idx] += l;
         pnl[idx] += p;
         counts[idx]++;
      }
      else
      {
         symbols[symCount] = sym;
         lots[symCount] = l;
         pnl[symCount] = p;
         counts[symCount] = 1;
         symCount++;
      }
   }

   bool first = true;
   for(int i = 0; i < symCount; i++)
   {
      if(!first) s += ",";
      first = false;
      s += "\n    {";
      s += "\"symbol\": \"" + symbols[i] + "\",";
      s += "\"lots\": " + DoubleToString(lots[i], 2) + ",";
      s += "\"pnl\": " + DoubleToString(pnl[i], 2) + ",";
      s += "\"count\": " + IntegerToString(counts[i]);
      s += "}";
   }
}

//+------------------------------------------------------------------+
//| Build strategy performance per magic                               |
//+------------------------------------------------------------------+
void BuildStrategyPerformance(string &s, int totalPos)
{
   long magics[32];
   double lots[32];
   double pnl[32];
   int counts[32];
   int magCount = 0;

   for(int i = 0; i < totalPos && magCount < 32; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      double l = PositionGetDouble(POSITION_VOLUME);
      double p = PositionGetDouble(POSITION_PROFIT);

      int idx = -1;
      for(int j = 0; j < magCount; j++)
      {
         if(magics[j] == magic) { idx = j; break; }
      }
      if(idx >= 0)
      {
         lots[idx] += l;
         pnl[idx] += p;
         counts[idx]++;
      }
      else
      {
         magics[magCount] = magic;
         lots[magCount] = l;
         pnl[magCount] = p;
         counts[magCount] = 1;
         magCount++;
      }
   }

   bool first = true;
   for(int i = 0; i < magCount; i++)
   {
      if(!first) s += ",";
      first = false;
      s += "\n    {";
      s += "\"magic\": " + IntegerToString((int)magics[i]) + ",";
      s += "\"lots\": " + DoubleToString(lots[i], 2) + ",";
      s += "\"pnl\": " + DoubleToString(pnl[i], 2) + ",";
      s += "\"count\": " + IntegerToString(counts[i]);
      s += "}";
   }
}

//+------------------------------------------------------------------+
//| Build pending orders                                              |
//+------------------------------------------------------------------+
void BuildPendingOrders(string &s)
{
   int total = OrdersTotal();
   bool first = true;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(!OrderSelect(ticket)) continue;

      string sym     = OrderGetString(ORDER_SYMBOL);
      int    type    = (int)OrderGetInteger(ORDER_TYPE);
      double lots    = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double price   = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl      = OrderGetDouble(ORDER_SL);
      double tp      = OrderGetDouble(ORDER_TP);
      long   magic   = OrderGetInteger(ORDER_MAGIC);
      datetime oTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

      // Only show relevant order types (limit/stop)
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT &&
         type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_SELL_STOP)
         continue;

      string typeStr = "LIMIT";
      if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP) typeStr = "STOP";
      string side = "BUY";
      if(type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP) side = "SELL";

      if(!first) s += ",";
      first = false;

      s += "\n    {";
      s += "\"ticket\": " + IntegerToString((int)ticket) + ",";
      s += "\"symbol\": \"" + sym + "\",";
      s += "\"type\": \"" + side + " " + typeStr + "\",";
      s += "\"lots\": " + DoubleToString(lots, 2) + ",";
      s += "\"price\": " + DoubleToString(price, 5) + ",";
      s += "\"sl\": " + DoubleToString(sl, 5) + ",";
      s += "\"tp\": " + DoubleToString(tp, 5) + ",";
      s += "\"magic\": " + IntegerToString((int)magic) + ",";
      s += "\"time\": \"" + TimeToString(oTime, TIME_DATE|TIME_SECONDS) + "\"";
      s += "}";
   }
}

//+------------------------------------------------------------------+
//| Write closed deals with improved history access                    |
//+------------------------------------------------------------------+
void WriteClosedDeals(string &s, double &totalPnl, double &totalSwap,
                      double &totalComm, int &wins, int &losses,
                      double &avgWin, double &avgLoss, int &winCount, int &lossCount)
{
   int leverage = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);

   // Select history — try multiple strategies
   datetime from = TimeCurrent() - HISTORY_DAYS * 24 * 3600;
   datetime to   = TimeCurrent() + 10;  // small buffer

   bool selected = false;

   // Strategy 1: Direct HistorySelect with full range
   if(HistorySelect(from, to))
   {
      int totalDeals = HistoryDealsTotal();
      Print("[AccountSnapshot] HistorySelect OK: ", totalDeals, " deals in ", HISTORY_DAYS, "d window");
      if(totalDeals > 0) selected = true;
   }

   // Strategy 2: If no deals, try broader window (history might be outside range)
   if(!selected)
   {
      from = 0;  // all history
      if(HistorySelect(from, to))
      {
         int totalDeals = HistoryDealsTotal();
         Print("[AccountSnapshot] HistorySelect fallback (all): ", totalDeals, " deals");
         if(totalDeals > 0) selected = true;
      }
   }

   // Strategy 3: Try HistorySelect with just a very recent window
   if(!selected)
   {
      from = TimeCurrent() - 24 * 3600;  // last 24h only
      if(HistorySelect(from, to))
      {
         int totalDeals = HistoryDealsTotal();
         Print("[AccountSnapshot] HistorySelect fallback (24h): ", totalDeals, " deals");
         if(totalDeals > 0) selected = true;
      }
   }

   if(!selected)
   {
      Print("[AccountSnapshot] WARNING: No deals found in any history window. Deinit reason may be blocking access.");
      return;
   }

   int totalDeals = HistoryDealsTotal();

   // Collect closed deals — both DEAL_ENTRY_OUT and DEAL_ENTRY_INOUT (partial closes)
   bool first = true;
   int count = 0;
   double sumWin = 0.0, sumLoss = 0.0;

   for(int i = totalDeals - 1; i >= 0 && count < HISTORY_DEALS; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) continue;

      // Skip entry deals (DEAL_ENTRY_IN) — we only want exits
      // Also skip balance operations
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);

      string sym      = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long   type     = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      double lots     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      double dealPrice= HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double profit   = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap     = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double comm     = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      long   magic    = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      double net = profit + swap + comm;
      totalPnl += profit;
      totalSwap += swap;
      totalComm += comm;
      if(net >= 0)
      {
         wins++;
         winCount++;
         sumWin += net;
      }
      else
      {
         losses++;
         lossCount++;
         sumLoss += net;
      }

      // Calculate realized PnL %
      double openPx = dealPrice;  // for exit deals, price is close price
      double pnlPct = 0.0;
      if(openPx > 0.0)
         pnlPct = net / (lots * SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE) * openPx / leverage) * 100.0;

      if(!first) s += ",";
      first = false;

      s += "\n    {";
      s += "\"ticket\": "        + IntegerToString((int)dealTicket) + ",";
      s += "\"symbol\": \""      + sym + "\",";
      s += "\"type\": \""         + (type == DEAL_TYPE_BUY ? "BUY" : "SELL") + "\",";
      s += "\"lots\": "          + DoubleToString(lots, 2) + ",";
      s += "\"price\": "         + DoubleToString(dealPrice, 5) + ",";
      s += "\"profit\": "        + DoubleToString(profit, 2) + ",";
      s += "\"swap\": "          + DoubleToString(swap, 2) + ",";
      s += "\"commission\": "    + DoubleToString(comm, 2) + ",";
      s += "\"net\": "           + DoubleToString(net, 2) + ",";
      s += "\"pnl_pct\": "      + DoubleToString(pnlPct, 2) + ",";
      s += "\"magic\": "         + IntegerToString((int)magic) + ",";
      s += "\"position_id\": "   + IntegerToString((int)positionId) + ",";
      s += "\"time\": \""        + TimeToString(dealTime, TIME_DATE|TIME_SECONDS) + "\",";
      s += "\"entry\": "         + IntegerToString(dealEntry);
      s += "}";

      count++;
   }

   // Calculate averages
   avgWin = winCount > 0 ? sumWin / winCount : 0.0;
   avgLoss = lossCount > 0 ? sumLoss / lossCount : 0.0;

   Print("[AccountSnapshot] History: ", count, " deals (", wins, "W/", losses, "L)");
}

//+------------------------------------------------------------------+
//| Write rolling stats                                               |
//+------------------------------------------------------------------+
void WriteRollingStats(string &s)
{
   datetime now = TimeCurrent();

   // Daily PnL
   double dayPnl = 0.0, weekPnl = 0.0, monthPnl = 0.0;
   int dayWins = 0, dayLosses = 0, weekWins = 0, weekLosses = 0, monthWins = 0, monthLosses = 0;
   double daySumWin = 0.0, daySumLoss = 0.0;
   double weekSumWin = 0.0, weekSumLoss = 0.0;
   double monthSumWin = 0.0, monthSumLoss = 0.0;

   datetime dayFrom = now - 1 * 24 * 3600;
   datetime weekFrom = now - 7 * 24 * 3600;
   datetime monthFrom = now - 30 * 24 * 3600;

   if(HistorySelect(dayFrom, now + 1))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double sw = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double net = p + sw + c;
         dayPnl += net;
         if(net >= 0) { dayWins++; daySumWin += net; }
         else { dayLosses++; daySumLoss += net; }
      }
   }

   if(HistorySelect(weekFrom, now + 1))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double sw = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double net = p + sw + c;
         weekPnl += net;
         if(net >= 0) { weekWins++; weekSumWin += net; }
         else { weekLosses++; weekSumLoss += net; }
      }
   }

   if(HistorySelect(monthFrom, now + 1))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         double p = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         double sw = HistoryDealGetDouble(ticket, DEAL_SWAP);
         double c = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         double net = p + sw + c;
         monthPnl += net;
         if(net >= 0) { monthWins++; monthSumWin += net; }
         else { monthLosses++; monthSumLoss += net; }
      }
   }

   int dayTotal = dayWins + dayLosses;
   int weekTotal = weekWins + weekLosses;
   int monthTotal = monthWins + monthLosses;
   double dayAvgWin = dayWins > 0 ? daySumWin / dayWins : 0.0;
   double dayAvgLoss = dayLosses > 0 ? daySumLoss / dayLosses : 0.0;
   double weekAvgWin = weekWins > 0 ? weekSumWin / weekWins : 0.0;
   double weekAvgLoss = weekLosses > 0 ? weekSumLoss / weekLosses : 0.0;
   double monthAvgWin = monthWins > 0 ? monthSumWin / monthWins : 0.0;
   double monthAvgLoss = monthLosses > 0 ? monthSumLoss / monthLosses : 0.0;

   s += "    \"daily\": {\n";
   s += "      \"pnl\": " + DoubleToString(dayPnl, 2) + ",\n";
   s += "      \"trades\": " + IntegerToString(dayTotal) + ",\n";
   s += "      \"wins\": " + IntegerToString(dayWins) + ",\n";
   s += "      \"losses\": " + IntegerToString(dayLosses) + ",\n";
   s += "      \"win_rate\": " + DoubleToString(dayTotal > 0 ? (double)dayWins / dayTotal * 100.0 : 0.0, 1) + ",\n";
   s += "      \"avg_win\": " + DoubleToString(dayAvgWin, 2) + ",\n";
   s += "      \"avg_loss\": " + DoubleToString(dayAvgLoss, 2) + "\n";
   s += "    },\n";

   s += "    \"weekly\": {\n";
   s += "      \"pnl\": " + DoubleToString(weekPnl, 2) + ",\n";
   s += "      \"trades\": " + IntegerToString(weekTotal) + ",\n";
   s += "      \"wins\": " + IntegerToString(weekWins) + ",\n";
   s += "      \"losses\": " + IntegerToString(weekLosses) + ",\n";
   s += "      \"win_rate\": " + DoubleToString(weekTotal > 0 ? (double)weekWins / weekTotal * 100.0 : 0.0, 1) + ",\n";
   s += "      \"avg_win\": " + DoubleToString(weekAvgWin, 2) + ",\n";
   s += "      \"avg_loss\": " + DoubleToString(weekAvgLoss, 2) + "\n";
   s += "    },\n";

   s += "    \"monthly\": {\n";
   s += "      \"pnl\": " + DoubleToString(monthPnl, 2) + ",\n";
   s += "      \"trades\": " + IntegerToString(monthTotal) + ",\n";
   s += "      \"wins\": " + IntegerToString(monthWins) + ",\n";
   s += "      \"losses\": " + IntegerToString(monthLosses) + ",\n";
   s += "      \"win_rate\": " + DoubleToString(monthTotal > 0 ? (double)monthWins / monthTotal * 100.0 : 0.0, 1) + ",\n";
   s += "      \"avg_win\": " + DoubleToString(monthAvgWin, 2) + ",\n";
   s += "      \"avg_loss\": " + DoubleToString(monthAvgLoss, 2) + "\n";
   s += "    }";
}
//+------------------------------------------------------------------+
