//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

#property copyright "Copyright 2024, Ali Mahani"
#property link "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Pivot High/Low";
input int pivotLen = 7;   // Bars to look around for Pivots
input int pivotHist = 20; // # of Pivots
// input int pivotHistDaily = 5;  // # of Pivots in D1 timeframe

input group "Trade Management";
input ulong EA_MAGIC = 59205709;             // Magic ID for EA
input double riskPercent = 2.0;              // Risk as % of balance
input int slPoints = 150;                    // SL in Points
input double profitFactor = 1.5;             // Profit factor
input int expBars = 12;                      // # of Bars to expire limit order
input bool trailStop = true;                 // Use Trailing SL ?
input int tslTriggerPoints = 50;             // TSL trigger in points
input int tslPoints = 50;                    // TSL in points
input string tradeComment = "ICT CHoCH Bot"; // Trading Bot Comment

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};

// ----------- Trade ---------
CTrade trade;
CPositionInfo pos;
COrderInfo ord;

// -----------
Pivot pivots[];

enum ENUM_TREND
{
   TREND_UP = 1,
   TREND_DOWN = -1,
   TREND_NULL = 0
};

ENUM_TREND trend = TREND_DOWN;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(pivots, pivotHist);
   ArraySetAsSeries(pivots, true);
   Pivot initialPivot = {iClose(_Symbol, PERIOD_CURRENT, 0), 0, PIVOT_LOW};

   pivots[0] = initialPivot.copy();

   trade.SetExpertMagicNumber(EA_MAGIC);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick(void)
{
   if (trailStop)
      TrailStop(pos, trade, EA_MAGIC, tslTriggerPoints, tslPoints);

   if (!newBar())
      return;

   IsPivotHigh(PERIOD_CURRENT, pivots);
   IsPivotLow(PERIOD_CURRENT, pivots);
   UpdateTrend();
}

// -------------------------------------------------------------------

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateSeriesPivot(Pivot &arr[], const Pivot &newValue)
{
   int size = ArraySize(arr);
   for (int i = size - 1; i > 0; i--)
   {
      arr[i] = arr[i - 1];
   }
   arr[0] = newValue;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPivotHigh(ENUM_TIMEFRAMES tf, Pivot &pivots[])
{
   double ph = PivotHigh(pivotLen, tf);
   if (ph)
   {
      datetime now = iTime(_Symbol, tf, pivotLen + 1);
      Pivot p = {ph, now, PIVOT_HIGH};
      if (pivots[0].type == PIVOT_HIGH)
      {
         if (p.value > pivots[0].value)
            pivots[0] = p.copy();
      }
      else
      {
         UpdateSeriesPivot(pivots, p.copy());
      }
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsPivotLow(ENUM_TIMEFRAMES tf, Pivot &pivots[])
{
   double pl = PivotLow(pivotLen, tf);
   if (pl)
   {
      datetime time = iTime(_Symbol, 0, pivotLen + 1);
      Pivot p = {pl, time, PIVOT_LOW};
      if (pivots[0].type == PIVOT_LOW)
      {
         if (p.value < pivots[0].value)
            pivots[0] = p.copy();
      }
      else
      {
         UpdateSeriesPivot(pivots, p.copy());
      }
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateTrend()
{
   if (trend == TREND_DOWN)
   {
      if (pivots[0].type == PIVOT_HIGH && pivots[0].value > pivots[2].value)
      {
         Alert("Break of Structure in Downtrend!");
         ObjectCreate(0, "BoCH", OBJ_ARROWED_LINE, 0,
                      pivots[2].time, pivots[2].value, pivots[0].time, pivots[2].value);
      }
   }
   else if (trend == TREND_UP)
   {
      if (pivots[0].type == PIVOT_LOW && pivots[0].value < pivots[2].value)
      {
         Alert("Break of Structure in Uptrend!");
         ObjectCreate(0, "BoCH", OBJ_ARROWED_LINE, 0,
                      pivots[2].time, pivots[2].value, pivots[0].time, pivots[2].value);
      }
   }
   if (pivots[0].type == PIVOT_HIGH && pivots[0].value > pivots[2].value && pivots[1].value > pivots[3].value)
      trend = TREND_UP;
   else if (pivots[0].type == PIVOT_LOW && pivots[0].value < pivots[2].value && pivots[1].value < pivots[3].value)
      trend = TREND_DOWN;
}
//+------------------------------------------------------------------+
