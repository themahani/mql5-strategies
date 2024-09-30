
#property copyright "Copyright 2024, Ali Mahani"
#property link "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Smart Money Concepts";
input double maxSpread = 50; // Max. spread in Points - No Demand Bar (10 pts = 1 pip)
input double minWick = 40;   // Min. wick size in Points - No Demand Bar (10 pts = 1 pip)
input int periodEMA = 14;    // EMA period

input group "Trade Management";
input double riskPercent = 2.0; // Risk as a % of trading capital
input double profitFactor = 2.0;
input ulong EA_MAGIC = 3948302840; // EA Magic ID
// input int tpPoints = 200;               // Take Profit in Points (10 points = 1 pip)
input int slPoints = 200;        // Stop Loss in Points (10 points = 1 pip)
input int tslTriggerPoints = 15; // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 10;        // Trailing SL (10 points = 1 pip)
input int expBars = 100;         // # of bars after which the orders expire
input bool trailStop = true;     // Use Trailing SL?

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};

// ---------- Variables ----------
MqlRates rates[];
int histBars = 100;

// -------- Indicators --------
int handleEMA;
double bufferEMA[];

// ----------- Trade ---------
CTrade trade;
CPositionInfo pos;
COrderInfo ord;

int OnInit()
{
    trade.SetExpertMagicNumber(EA_MAGIC);
    // trade.SetDeviationInPoints()
    ArraySetAsSeries(rates, true);

    handleEMA = iMA(_Symbol, PERIOD_CURRENT, periodEMA, 0, MODE_SMA, PRICE_CLOSE);
    ArraySetAsSeries(bufferEMA, true);

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

    CopyRates(_Symbol, PERIOD_CURRENT, 1, histBars, rates);
    CopyBuffer(handleEMA, MAIN_LINE, 1, histBars, bufferEMA);
    NoDemandBarBearish(rates, maxSpread, minWick);
    // if (PositionsTotal() == 0 && TradeSession(startTime, endTime))
    // {
    //     if (NoDemandBarBearish(rates, maxSpread, minWick) && rates[0].close < bufferEMA[0])
    //     {
    //         Sell();
    //     }
    // }
}

void DrawArrow(const string arrowName, const datetime arrowTime, const double arrowPrice)
{

    if (!ObjectCreate(0, arrowName, OBJ_ARROW_DOWN, 0, arrowTime, arrowPrice))
        Print("Failed to Create Object Arrow Down.");
}

bool NoDemandBarBearish(MqlRates &price[], double spreadThreshold, double wickThreshold)
{
    double spread = MathAbs(price[0].open - price[0].close);
    double highWick = price[0].high - MathMax(price[0].close, price[0].open);

    ulong vol0 = price[0].tick_volume;
    ulong vol1 = price[1].tick_volume;
    ulong vol2 = price[2].tick_volume;
    if (spread < spreadThreshold * _Point && highWick > wickThreshold * _Point && vol0 < vol1 && vol0 < vol2)
    {
        Alert("No Demand Bar Found!");
        datetime now = iTime(_Symbol, PERIOD_CURRENT, 1);
        DrawArrow("NDB", now, price[0].high);
        return true;
    }
    return false;
}

void Sell()
{
    double entry = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double slDiff = slPoints * _Point;
    double sl = entry + slDiff;
    double tp = entry - slDiff * profitFactor;

    double lots = 0.01;
    if (riskPercent > 0)
        lots = calculateLots(slDiff, riskPercent);

    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);
    if (!trade.Sell(lots, _Symbol, entry, sl, tp))
    {
        Alert("Sell Failed! ", _LastError);
    }
}

void Buy()
{
    double entry = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double slDiff = slPoints * _Point;
    double sl = entry - slDiff;
    double tp = entry + slDiff * profitFactor;

    double lots = 0.01;
    if (riskPercent > 0)
        lots = calculateLots(slDiff, riskPercent);

    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);
    if (!trade.Buy(lots, _Symbol, entry, sl, tp))
    {
        Alert("Sell Failed! ", _LastError);
    }
}