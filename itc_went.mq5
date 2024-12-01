//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2020, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+

#property  copyright "Copyright 2024, Ali Mahani"
#property link       "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Pivot High/Low";
input int pivotLen = 7; // Bars to look around for Pivots
input int pivotHistWeekly = 5;  // # of Pivots in W1 timeframe
input int pivotHistDaily = 5;   // # of Pivots in D1 timeframe

input group "Trade Management";
input ulong EA_MAGIC = 59205709;    // Magic ID for EA
input double riskPercent = 2.0;     // Risk as % of balance
input int slPoints = 150;           // SL in Points
input double profitFactor = 1.5;    // Profit factor
input int expBars = 12;             // # of Bars to expire limit order
input bool trailStop = true;        // Use Trailing SL ?
input int tslTriggerPoints = 50;        // TSL trigger in points
input int tslPoints = 50;               // TSL in points
input string tradeComment = "ICT WENT Series Bot";      // Trading Bot Comment

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};


// ------------ Global ----------


Pivot pivotsDaily[];
Pivot pivotsWeekly[];

// PivotFinder pf;

// ----------- Data -----------
int lenRates = 99;
MqlRates rates[];


// ----------- Trade ---------
CTrade trade;
CPositionInfo pos;
COrderInfo ord;


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
   {
    if(Period() != PERIOD_M15)
       {
        Alert("Current Timeframe should be M15");
        return INIT_FAILED;
       }

//    pf = new PivotFinder(50, PERIOD_M15, Symbol(), pivotLen);
    
    ArraySetAsSeries(pivotsDaily, true);
    ArraySetAsSeries(pivotsWeekly, true);
    ArraySetAsSeries(rates, true);
    ArrayResize(pivotsDaily, pivotHistDaily);
    ArrayResize(pivotsWeekly, pivotHistWeekly);
    ArrayResize(rates, lenRates);
    
    Pivot initialPivot = {SymbolInfoDouble(Symbol(), SYMBOL_ASK), 0, PIVOT_LOW};
    pivotsDaily[0] = initialPivot.copy();
    pivotsWeekly[0] = initialPivot.copy();

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
    if(trailStop)
        TrailStop(pos, trade, EA_MAGIC, tslTriggerPoints, tslPoints);

    if(!newBar())
        return;

//    pf.Update();

    CopyRates(_Symbol, PERIOD_CURRENT, 1, lenRates, rates);

    IsPivotHigh(PERIOD_D1, pivotsDaily);
    IsPivotLow(PERIOD_D1, pivotsDaily);
    IsPivotHigh(PERIOD_W1, pivotsWeekly);
    IsPivotLow(PERIOD_W1, pivotsWeekly);

    if(!TradeSession(startTime, endTime))
        return;

    if(OrdersTotal() != 0 || PositionsTotal() != 0)
        return;

    double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double support = FindNearestBelow(currentPrice);
    double resistance = FindNearestAbove(currentPrice);

   //  double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   //  double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double slDiff = slPoints * _Point;
    double shortSLPrice = resistance + slDiff;
    double shortTPPrice = resistance - slDiff * profitFactor;
    double longSLPrice = support - slDiff;
    double longTPPrice = support + slDiff * profitFactor;

    BuyLimit(trade, support, longSLPrice, longTPPrice);
    SellLimit(trade, resistance, shortSLPrice, shortTPPrice);
   }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double FindNearestAbove(double price)
   {
    double nearestPrice = price + 1000 * _Point;
    for(int i = 0; i < pivotHistDaily; i++)
       {
        if(price < pivotsDaily[i].value && MathAbs(nearestPrice - price) > MathAbs(pivotsDaily[i].value - price))
           {
            nearestPrice = pivotsDaily[i].value;
           }
       }
    for(int i = 0; i < pivotHistWeekly; i++)
       {
        if(price < pivotsWeekly[i].value && MathAbs(nearestPrice - price) > MathAbs(pivotsWeekly[i].value - price))
           {
            nearestPrice = pivotsDaily[i].value;
           }
       }
    return nearestPrice;
   }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double FindNearestBelow(double price)
   {
    double nearestPrice = price - 1000 * _Point;
    for(int i = 0; i < pivotHistDaily; i++)
       {
        if(price > pivotsDaily[i].value && MathAbs(nearestPrice - price) > MathAbs(pivotsDaily[i].value - price))
           {
            nearestPrice = pivotsDaily[i].value;
           }
       }
    for(int i = 0; i < pivotHistWeekly; i++)
       {
        if(price > pivotsWeekly[i].value && MathAbs(nearestPrice - price) > MathAbs(pivotsWeekly[i].value - price))
           {
            nearestPrice = pivotsDaily[i].value;
           }
       }
    return nearestPrice;
   }



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateSeriesPivot(Pivot &arr[], const Pivot &newValue)
   {
    int size = ArraySize(arr);
    for(int i = size - 1; i > 0; i--)
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
    if(ph)
       {
        datetime now = iTime(_Symbol, tf, pivotLen + 1);
        Pivot p = {ph, now, PIVOT_HIGH};
        if(pivots[0].type == PIVOT_HIGH)
           {
            if(p.value > pivots[0].value)
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
    if(pl)
       {
        datetime time = iTime(_Symbol, 0, pivotLen + 1);
        Pivot p = {pl, time, PIVOT_LOW};
        if(pivots[0].type == PIVOT_LOW)
           {
            if(p.value < pivots[0].value)
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
/*bool BuyLimitCondition(MqlRates &candles[])
   {
    datetime prevDay = iTime(Symbol(), PERIOD_D1, 1);
    double prevDailyHigh = iHigh(_Symbol, PERIOD_D1, 1);
    double prevDailyLow = iLow(_Symbol, PERIOD_D1, 1);

    bool pivotHigh = (pivots[0].type == PIVOT_HIGH && pivots[0].value > prevDailyHigh);
    bool pivotLow = (pivots[1].type == PIVOT_LOW && pivots[1].value < prevDailyHigh);

// bool priceInRange = true;
    if(pivotHigh && pivotLow)
       {
        return true;
       }
    return false;
   }
*/

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void BuyLimit(CTrade &trade, double entry, double slPrice, double tpPrice)
   {
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
// if (ask > entry + orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double lots = 0.01;
    double slDiff = MathAbs(entry - slPrice);

    if(riskPercent > 0)
        lots = calculateLots(slDiff, riskPercent);
    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);

    trade.BuyLimit(lots, entry, _Symbol, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expiration, tradeComment + " Buy");
   }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SellLimit(CTrade &trade, double entry, double slPrice, double tpPrice)
   {
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
// if (ask > entry + orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double lots = 0.01;
    double slDiff = MathAbs(entry - slPrice);

    if(riskPercent > 0)
        lots = calculateLots(slDiff, riskPercent);
    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);

    trade.SellLimit(lots, entry, _Symbol, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expiration, tradeComment + " Sell");
   }
//+------------------------------------------------------------------+
