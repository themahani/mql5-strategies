
#property  copyright "Copyright 2024, Ali Mahani"
#property link       "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Pivot High/Low";
input int pivotLen = 7; // Bars to look around for Pivots
input int historySize = 50;

input group "Trade Management";
input ulong EA_MAGIC = 59205709;    // Magic ID for EA
input double riskPercent = 2.0;     // Risk as % of balance
input int expBars = 50;             // # of Bars to expire limit order
input bool trailStop = true;        // Use Trailing SL ?
input int tslTriggerPoints = 50;        // TSL trigger in points
input int tslPoints = 50;               // TSL in points
input string tradeComment = "ICT OTE";      // Trading Bot Comment

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};


// ------------ Global ----------


Pivot pivots[];

PivotFinder pf;

// ----------- Data -----------
int lenRates = 99;
MqlRates rates[];


// ----------- Trade ---------
CTrade trade;
CPositionInfo pos;
COrderInfo ord;


int OnInit()
{
    if (Period() != PERIOD_M5)
    {
        Alert("Current Timeframe should be M5");
        return INIT_FAILED;
    }
    pf = new PivotFinder(historySize, PERIOD_CURRENT, _Symbol, pivotLen);
    ArraySetAsSeries(pivots, true);
    ArraySetAsSeries(rates, true);
    ArrayResize(pivots, historySize);
    ArrayResize(rates, lenRates);

    trade.SetExpertMagicNumber(EA_MAGIC);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{

}

void OnTick(void)
{
    if (trailStop)
        TrailStop(pos, trade, EA_MAGIC, tslTriggerPoints, tslPoints);

    if (!newBar())
        return;
    
    pf.Update();

    CopyRates(_Symbol, PERIOD_CURRENT, 1, lenRates, rates);

    IsPivotHigh();
    IsPivotLow();

    if (!TradeSession(startTime, endTime))
        return;

    if (OrdersTotal() != 0 || PositionsTotal() != 0)
        return;
    
    if (BuyLimitCondition(rates))
    {
        double sl = 0;

        double pl = (pivots[1].type == PIVOT_LOW ? pivots[1].value : 0);
        double ph = (pivots[0].type == PIVOT_HIGH ? pivots[0].value : 0);

        if (ph == 0 || pl == 0)
            return;
        
        double std = MathAbs(ph - pl);
        double support = ph - 0.62 * std;
        double resistance1 = ph + .5 * std;
        double resistance2 = ph + std;
        
        double entry = support;
        sl = pivots[1].value;
        BuyLimit(entry, sl, resistance1);
        // BuyLimit(entry, sl, resistance2);
    }
}


void UpdateSeriesPivot(Pivot &arr[], const Pivot &newValue)
{
    int size = ArraySize(arr);
    for (int i = size - 1; i > 0; i--)
    {
        arr[i] = arr[i-1];
    }
    arr[0] = newValue;
}

bool IsPivotHigh()
{
    double ph = PivotHigh(pivotLen);
    if (ph)
    {
        datetime now = iTime(_Symbol, 0, pivotLen + 1);
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

bool IsPivotLow()
{
    double pl = PivotLow(pivotLen);
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

bool BuyLimitCondition(MqlRates &candles[])
{
    datetime prevDay = iTime(Symbol(), PERIOD_D1, 1);
    double prevDailyHigh = iHigh(_Symbol, PERIOD_D1, 1);
    double prevDailyLow = iLow(_Symbol, PERIOD_D1, 1);

    bool pivotHigh = (pivots[0].type == PIVOT_HIGH && pivots[0].value > prevDailyHigh);
    bool pivotLow = (pivots[1].type == PIVOT_LOW && pivots[1].value < prevDailyHigh);

    // bool priceInRange = true;
    if (pivotHigh && pivotLow)
    {
        return true;
    }
    return false;
}

void BuyLimit(double entry, double slPrice, double tpPrice)
{
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    // if (ask > entry + orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double lots = 0.01;
    double slDiff = MathAbs(entry - slPrice);

    if (riskPercent > 0)    lots = calculateLots(slDiff, riskPercent);
    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);

    trade.BuyLimit(lots, entry, _Symbol, slPrice, tpPrice, ORDER_TIME_SPECIFIED, expiration, tradeComment);
}