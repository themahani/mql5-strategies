
#property copyright "Copyright 2024, Ali Mahani"
#property link "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"
// #include <Indicators/mql5-indicators>

// ----------- Inputs ----------
input group "Nadaraya Watson Parameters";
input int numBarsNW = 200;       // Count of bars to look back
input double bandwidthNW = 10;   // Bandwidth -- Standard Deviation of the Gaussian
input double multiplierNW = 2.0; // Multiplier for the envelope -- value * stddev

input group "Trade Management";
input double riskPercent = 2.0; // Risk as a % of trading capital
input double profitFactor = 2.0;
input ulong EA_MAGIC = 59204508; // EA Magic ID
input int slPoints = 200;        // Stop Loss in Points (10 points = 1 pip)
input bool trailStop = true;     // Use Trailing SL?
input int tslTriggerPoints = 15; // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 10;        // Trailing SL (10 points = 1 pip)
input int expBars = 100;         // # of bars after which the orders expire

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};

// ------------ NW indicator ----------
int handleNW;
double bufferUpperNW[];
double bufferLowerNW[];
double bufferMainNW[];

// ---------- Globals ----------
CTrade trade;
CPositionInfo pos;
COrderInfo ord;

int OnInit()
{
    handleNW = iCustom(_Symbol, PERIOD_CURRENT, "mql5-indicators/codebase/NadarayaWatson",
                       numBarsNW, bandwidthNW, multiplierNW);
    ArraySetAsSeries(bufferUpperNW, true);
    ArraySetAsSeries(bufferLowerNW, true);
    ArraySetAsSeries(bufferMainNW, true);

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

    if (PositionsTotal() != 0 || !TradeSession(startTime, endTime))
        return;

    CopyBuffer(handleNW, 0, 1, 20, bufferUpperNW);
    CopyBuffer(handleNW, 1, 1, 20, bufferLowerNW);
    CopyBuffer(handleNW, 2, 1, 20, bufferMainNW);

    if (BuyCondition())
        Buy();

    if (SellCondition())
        Sell();
}

bool BuyCondition()
{
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    long volume = iVolume(_Symbol, PERIOD_CURRENT, 1);
    long prevVolume = iVolume(_Symbol, PERIOD_CURRENT, 2);
    if (close < bufferLowerNW[0]              // Close below the Lower envelope
        && prevVolume < volume                // close with higher volume
        && bufferMainNW[0] > bufferMainNW[1]) // NW in an uptrend
        return true;

    return false;
}

bool SellCondition()
{
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    long volume = iVolume(_Symbol, PERIOD_CURRENT, 1);
    long prevVolume = iVolume(_Symbol, PERIOD_CURRENT, 2);
    if (close > bufferUpperNW[0]              // Close above the Upper envelope
        && prevVolume < volume                // close with higher volume
        && bufferMainNW[0] < bufferMainNW[1]) // NW in a downtrend
        return true;

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
        Alert("Buy Failed! ", _LastError);
    }
}