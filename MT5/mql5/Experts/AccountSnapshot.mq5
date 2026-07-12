//+------------------------------------------------------------------+
//|                                                  AccountSnapshot.mq5 |
//|                        Copyright 2026, Ishan Parihar              |
//|                                       AD-12 MT5 Log Checker      |
//+------------------------------------------------------------------+
#property copyright "AD-12"
#property version   "1.00"
#property strict

// AccountSnapshot.mq5 — dumps live account state + open positions to a JSON
// file every SNAPSHOT_INTERVAL seconds. Read by mt5ctl/mt5_summary on the VPS.
//
// Attaches to ANY chart (recommend a dedicated XAUUSDc M1 chart). Writes to
// MQL5/Files/account_snapshot.json (FILE_COMMON so it's accessible from the
// Linux host via the Common volume — but we use MQL5/Files which is bind-mounted
// via the ea/Experts volume).
//
// Output JSON shape:
// {
//   "written_at": "2026-07-11T23:47:45",   // LOCAL time when this write happened (ISO 8601)
//   "ts": "2026-07-11T10:30:00",            // MT5 SERVER time of the account state
//   "balance": 102.45,
//   "equity": 103.12,
//   "margin": 12.34,
//   "free_margin": 90.78,
//   "margin_level": 835.5,
//   "profit": 0.67,
//   "leverage": 1000,
//   "currency": "USD",
//   "login": 184060850,
//   "server": "Exness-MT5Real25",
//   "positions": [
//     {"ticket": 12345, "symbol": "XAUUSDc", "type": "BUY", "lots": 0.03,
//      "open_price": 4113.28, "current_price": 4120.50, "sl": 4014.09,
//      "tp": 4410.41, "profit": 2.17, "magic": 992101, "open_time": "..."}
//   ]
// }

input int SNAPSHOT_INTERVAL = 60;  // seconds between snapshots

const string SNAPSHOT_FILE = "account_snapshot.json";

int OnInit()
{
   EventSetTimer(SNAPSHOT_INTERVAL);
   WriteSnapshot();  // write immediately on attach
   Print("[AccountSnapshot] attached, interval=", SNAPSHOT_INTERVAL, "s");
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
   // Write to MQL5/Files (container bind-mount: /opt/mt5/ea/Experts/Files)
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

   // Local time when this write happens (ISO 8601, local timezone)
   // This tells the reader when the snapshot was actually written,
   // independent of the MT5 server time of the account state.
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
   s += "  \"positions\": [";

   bool first = true;
   int total = PositionsTotal();
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
      long   magic    = PositionGetInteger(POSITION_MAGIC);
      datetime openT  = (datetime)PositionGetInteger(POSITION_TIME);

      if(!first) s += ",";
      first = false;

      s += "\n    {";
      s += "\"ticket\": "        + IntegerToString((int)ticket) + ",";
      s += "\"symbol\": \""      + sym + "\",";
      s += "\"type\": \""         + (type == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",";
      s += "\"lots\": "          + DoubleToString(lots, 2) + ",";
      s += "\"open_price\": "    + DoubleToString(openPx, 5) + ",";
      s += "\"current_price\": " + DoubleToString(curPx, 5) + ",";
      s += "\"sl\": "            + DoubleToString(sl, 5) + ",";
      s += "\"tp\": "            + DoubleToString(tp, 5) + ",";
      s += "\"profit\": "        + DoubleToString(pnl, 2) + ",";
      s += "\"magic\": "         + IntegerToString((int)magic) + ",";
      s += "\"open_time\": \""   + TimeToString(openT, TIME_DATE|TIME_SECONDS) + "\"";
      s += "}";
   }

   s += "\n  ]\n";
   s += "}\n";
   return s;
}
//+------------------------------------------------------------------+
