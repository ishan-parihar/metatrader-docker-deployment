//+------------------------------------------------------------------+
//|                                                  AccountSnapshot.mq5 |
//|                        Copyright 2026, Ishan Parihar              |
//|                                       AD-12 MT5 Log Checker      |
//+------------------------------------------------------------------+
#property copyright "AD-12"
#property version   "3.00"
#property strict

// AccountSnapshot.mq5 v3 — comprehensive account state dump.
//
// Attach to ANY chart (recommend a dedicated XAUUSDc M1 chart). Writes to
// MQL5/Files/account_snapshot.json (FILE_COMMON).
//
// v3 changes:
//   - Extended history window from 30d to 90d
//   - Include DEAL_ENTRY_INOUT (partial closes) alongside DEAL_ENTRY_OUT
//   - Added close_time to history deals
//   - Added total_pnl / total_swap / total_comm summary fields
//   - Added daily_pnl / weekly_pnl / monthly_pnl rolling stats
//   - Added open_count / history_count for quick counts

input int SNAPSHOT_INTERVAL = 60;     // seconds between snapshots
input int HISTORY_DEALS = 100;         // number of closed deals to include
input int HISTORY_DAYS = 90;           // days of history to select

const string SNAPSHOT_FILE = "account_snapshot.json";

int OnInit()
{
   EventSetTimer(SNAPSHOT_INTERVAL);
   WriteSnapshot();  // write immediately on attach
   Print("[AccountSnapshot] v3.00 attached, interval=", SNAPSHOT_INTERVAL,
         "s, history=", HISTORY_DEALS, ", window=", HISTORY_DAYS, "d");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   WriteSnapshot();
}

void WriteSnapshot()
{
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

   // Local time when this write happens
   MqlDateTime dt;
   TimeLocal(dt);
   string writtenAt = StringFormat("%04d-%02d-%02dT%02d:%02d:%02d",
                                    dt.year, dt.mon, dt.day,
                                    dt.hour, dt.min, dt.sec);

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

   // Open positions
   s += "  \"positions\": [";
   bool first = true;
   int total = PositionsTotal();
   double totalOpenPnl = 0.0;
   double totalSwap = 0.0;
   double totalComm = 0.0;

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
      s += "\"open_time\": \""    + TimeToString(openT, TIME_DATE|TIME_SECONDS) + "\"";
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

   // Closed trade history
   double histPnl = 0.0, histSwap = 0.0, histComm = 0.0;
   int histWins = 0, histLosses = 0;
   s += "  \"history\": [";
   WriteClosedDeals(s, histPnl, histSwap, histComm, histWins, histLosses);

   // History summary
   int histTotal = histWins + histLosses;
   s += "  ],\n";
   s += "  \"history_summary\": {\n";
   s += "    \"count\": " + IntegerToString(histTotal) + ",\n";
   s += "    \"wins\": " + IntegerToString(histWins) + ",\n";
   s += "    \"losses\": " + IntegerToString(histLosses) + ",\n";
   s += "    \"win_rate\": " + DoubleToString(histTotal > 0 ? (double)histWins / histTotal * 100.0 : 0.0, 1) + ",\n";
   s += "    \"total_pnl\": " + DoubleToString(histPnl, 2) + ",\n";
   s += "    \"total_swap\": " + DoubleToString(histSwap, 2) + ",\n";
   s += "    \"total_commission\": " + DoubleToString(histComm, 2) + ",\n";
   s += "    \"total_net\": " + DoubleToString(histPnl + histSwap + histComm, 2) + "\n";
   s += "  },\n";

   // Daily/weekly/monthly rolling PnL
   s += "  \"rolling\": {\n";
   WriteRollingStats(s);
   s += "\n  }\n";
   s += "}\n";
   return s;
}

void WriteClosedDeals(string &s, double &totalPnl, double &totalSwap,
                      double &totalComm, int &wins, int &losses)
{
   int leverage = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);

   // Extended window: 90 days
   datetime from = TimeCurrent() - HISTORY_DAYS * 24 * 3600;
   datetime to   = TimeCurrent() + 1;
   if(!HistorySelect(from, to))
   {
      Print("[AccountSnapshot] WARNING: HistorySelect failed, err=", GetLastError());
      return;
   }

   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;

   // Collect closed deals — both DEAL_ENTRY_OUT and DEAL_ENTRY_INOUT (partial closes)
   bool first = true;
   int count = 0;

   for(int i = totalDeals - 1; i >= 0 && count < HISTORY_DEALS; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) continue;

      string sym      = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      long   type     = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      double lots     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      double openPx   = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double closePx  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double profit   = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap     = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double comm     = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      long   magic    = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      datetime openT  = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      datetime closeT = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      long positionId = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      // Get close time from the position's closing deal
      // For DEAL_ENTRY_OUT, the deal time IS the close time
      closeT = openT;

      double net = profit + swap + comm;
      totalPnl += profit;
      totalSwap += swap;
      totalComm += comm;
      if(net >= 0) wins++; else losses++;

      // Calculate realized PnL %
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
      s += "\"open_price\": "    + DoubleToString(openPx, 5) + ",";
      s += "\"close_price\": "   + DoubleToString(closePx, 5) + ",";
      s += "\"profit\": "        + DoubleToString(profit, 2) + ",";
      s += "\"swap\": "          + DoubleToString(swap, 2) + ",";
      s += "\"commission\": "    + DoubleToString(comm, 2) + ",";
      s += "\"net\": "           + DoubleToString(net, 2) + ",";
      s += "\"pnl_pct\": "      + DoubleToString(pnlPct, 2) + ",";
      s += "\"magic\": "         + IntegerToString((int)magic) + ",";
      s += "\"position_id\": "   + IntegerToString((int)positionId) + ",";
      s += "\"open_time\": \""   + TimeToString(openT, TIME_DATE|TIME_SECONDS) + "\",";
      s += "\"close_time\": \""  + TimeToString(closeT, TIME_DATE|TIME_SECONDS) + "\"";
      s += "}";

      count++;
   }
}

void WriteRollingStats(string &s)
{
   datetime now = TimeCurrent();

   // Daily PnL
   double dayPnl = 0.0, weekPnl = 0.0, monthPnl = 0.0;
   int dayWins = 0, dayLosses = 0, weekWins = 0, weekLosses = 0, monthWins = 0, monthLosses = 0;

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
         dayPnl += p + sw + c;
         if(p + sw + c >= 0) dayWins++; else dayLosses++;
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
         weekPnl += p + sw + c;
         if(p + sw + c >= 0) weekWins++; else weekLosses++;
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
         monthPnl += p + sw + c;
         if(p + sw + c >= 0) monthWins++; else monthLosses++;
      }
   }

   int dayTotal = dayWins + dayLosses;
   int weekTotal = weekWins + weekLosses;
   int monthTotal = monthWins + monthLosses;

   s += "    \"daily\": {\n";
   s += "      \"pnl\": " + DoubleToString(dayPnl, 2) + ",\n";
   s += "      \"trades\": " + IntegerToString(dayTotal) + ",\n";
   s += "      \"wins\": " + IntegerToString(dayWins) + ",\n";
   s += "      \"losses\": " + IntegerToString(dayLosses) + ",\n";
   s += "      \"win_rate\": " + DoubleToString(dayTotal > 0 ? (double)dayWins / dayTotal * 100.0 : 0.0, 1) + "\n";
   s += "    },\n";

   s += "    \"weekly\": {\n";
   s += "      \"pnl\": " + DoubleToString(weekPnl, 2) + ",\n";
   s += "      \"trades\": " + IntegerToString(weekTotal) + ",\n";
   s += "      \"wins\": " + IntegerToString(weekWins) + ",\n";
   s += "      \"losses\": " + IntegerToString(weekLosses) + ",\n";
   s += "      \"win_rate\": " + DoubleToString(weekTotal > 0 ? (double)weekWins / weekTotal * 100.0 : 0.0, 1) + "\n";
   s += "    },\n";

   s += "    \"monthly\": {\n";
   s += "      \"pnl\": " + DoubleToString(monthPnl, 2) + ",\n";
   s += "      \"trades\": " + IntegerToString(monthTotal) + ",\n";
   s += "      \"wins\": " + IntegerToString(monthWins) + ",\n";
   s += "      \"losses\": " + IntegerToString(monthLosses) + ",\n";
   s += "      \"win_rate\": " + DoubleToString(monthTotal > 0 ? (double)monthWins / monthTotal * 100.0 : 0.0, 1) + "\n";
   s += "    }";
}
//+------------------------------------------------------------------+
