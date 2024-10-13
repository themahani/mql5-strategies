//+------------------------------------------------------------------+
//|                                                  MACD Sample.mq5 |
//|                             Copyright 2000-2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Ali Mahani"
#property link "ali.a.mahani@zoho.com"
#property version "5.50"


//---
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"


//---
input group "Trade Management"
input double riskPercent = 2.0; // Risk as a % of trading capital
input double profitFactor = 2.0;
input ulong EA_MAGIC = 3948302840; // EA Magic ID
input int slPoints = 200;        // Stop Loss in Points (10 points = 1 pip)
input double slATR = 1.0;        // Stop Loss modifier using ATR
input bool trailStop = true;        // Use trailing SL ?
input int tslTriggerPoints = 15; // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 10;        // Trailing SL (10 points = 1 pip)

input group "Trendline Breakout Params"
input int lenBack = 14;                 // # of bars to look around for pivots detection
input double atrMultiplier = 1.0;                               // ATR multiplier

input group "Indicator Params";
input int periodRSI = 20;               // RSI Period

input group "Trade Session UTC" input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

// TRAMA
int length = 99;
MqlRates rates[];


int numOfBars = 0;

// Trend line Breakout
double upper = 0.0;    // Upper trendline
double lower = 0.0;    // Lower trendline
double slope_ph = 0.0; // Slope for swing high
double slope_pl = 0.0; // Slope for swing low
double upos = 0.0;
double dnos = 0.0;
double ph = 0.0, pl = 0.0;

// Indicators
int handleATR;
double bufferATR[];

int handleTRAMA;
double bufferTRAMA[];

int handleRSI;
double bufferRSI[];



bool TradeSession()
{
    MqlDateTime tm = {};
    datetime current = TimeGMT(tm);
    int startMins = startHour * 60 + startMinute;
    int endMins = endHour * 60 + endMinute;

    int currentMins = tm.hour * 60 + tm.min;

    return (currentMins >= startMins && currentMins <= endMins);
}




CTrade trade;
CPositionInfo pos;
COrderInfo ord;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(void)
{
    Print(_Symbol);
    ChartSetInteger(0, CHART_SHOW_GRID, false);

    ArraySetAsSeries(rates, true);

    trade.SetExpertMagicNumber(EA_MAGIC);

    handleATR = iATR(NULL, 0, lenBack);
    ArraySetAsSeries(bufferATR, true);

    handleTRAMA = iCustom(_Symbol, PERIOD_CURRENT, "mql5-indicators/trama");
    ArraySetAsSeries(bufferTRAMA, true);

    handleRSI = iRSI(_Symbol, PERIOD_CURRENT, periodRSI, PRICE_CLOSE);
    ArraySetAsSeries(bufferRSI, true);

    return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert new tick handling function                                |
//+------------------------------------------------------------------+
void OnTick(void)
{
    if (trailStop)
        TrailStop();
    
    if (!newBar())
        return;

    CopyBuffer(handleATR, MAIN_LINE, 1, lenBack, bufferATR);
    CopyBuffer(handleTRAMA, MAIN_LINE, 1, lenBack, bufferTRAMA);
    CopyBuffer(handleRSI, MAIN_LINE, 1, lenBack, bufferRSI);
    getRates();

    UpdateTrendlines();

    Comment(upper, "\n", lower, "\n", ph, "\n", pl);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (PositionsTotal() == 0 && TradeSession())
    {
        if (trendlineBreakUp() && ask > bufferTRAMA[0] && bufferRSI[0] > 55)
        {
            Buy();
        }
        else if (trendlineBreakDown() && bid < bufferTRAMA[0] && bufferRSI[0] < 45)
        {
            Sell();
        }
    }
}
//+------------------------------------------------------------------+

double pivotHigh()
{
    double highest = 0;
    int count = 2 * lenBack + 1;
    int highestIndex = iHighest(NULL, 0, MODE_HIGH, count, 1);
    if (highestIndex == (lenBack + 1))
        highest = iHigh(NULL, 0, highestIndex);
    return highest;
}

double pivotLow()
{
    double lowest = 0;
    int count = 2 * lenBack + 1;
    int highestIndex = iLowest(NULL, 0, MODE_LOW, count, 1);
    if (highestIndex == (lenBack + 1))
        lowest = iLow(NULL, 0, highestIndex);
    return lowest;
}

bool DrawTrendline(double price, double slope, string name)
{
    int barsForward = 100;
    datetime startTime = iTime(_Symbol, PERIOD_CURRENT, 0) - (lenBack + 1) * PeriodSeconds();
    datetime endTime = startTime + barsForward * PeriodSeconds();
    double price2 = price + barsForward * slope;
    // Print("Slope: ", slope);
    if (!ObjectCreate(0, name, OBJ_TREND, 0, startTime, price, endTime, price2))
    {
        Alert("[Error] Failed to draw trendline.", GetLastError());
        return false;
    }
    color clr = clrRed; // Assuming slope is positive looking for break down
    if (slope < 0)
        clr = clrGreen; // If slope is negetive, looking for break up.
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);

    return true;
}

double calculateSlope()
{
    double slope = bufferATR[0] / lenBack * atrMultiplier;
    return slope;
}

void UpdateTrendlines()
{
    double slope = calculateSlope(); // Calculate slope
    ph = pivotHigh();
    if (ph)
    {
        slope_ph = -slope; // Update slope for the swing high
        upper = ph;        // Update upper trendline to the new swing high
        DrawTrendline(ph, slope_ph, "upper");
    }

    pl = pivotLow();
    if (pl)
    {
        slope_pl = slope; // Update slope for the swing low
        lower = pl;       // Update lower trendline to the new swing low
        DrawTrendline(pl, slope_pl, "lower");
    }
}

bool trendlineBreakUp()
{
    double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, 2);
    double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);

    datetime prevTime = iTime(_Symbol, PERIOD_CURRENT, 2);
    datetime time = iTime(_Symbol, PERIOD_CURRENT, 1);

    double prevValue = ObjectGetValueByTime(0, "upper", prevTime, 0);
    double value = ObjectGetValueByTime(0, "upper", time, 0);

    long prevVolume = iVolume(_Symbol, PERIOD_CURRENT, 2);
    long volume = iVolume(_Symbol, PERIOD_CURRENT, 1);
    bool highVolume = (volume > prevVolume);

    if (prevValue == 0 || value == 0)
    {
        Alert("Got zero value");
        return false;
    }
    if (prevClose < prevValue && close > value && highVolume)
    {
        Print("Trend Break Up");
        return true;
    }
    return false;
}

bool trendlineBreakDown()
{
    double prevOpen = iOpen(_Symbol, PERIOD_CURRENT, 2);
    double prevClose = iClose(_Symbol, PERIOD_CURRENT, 2);
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);

    datetime prevTime = iTime(_Symbol, PERIOD_CURRENT, 2);
    datetime time = iTime(_Symbol, PERIOD_CURRENT, 1);

    double prevValue = ObjectGetValueByTime(0, "lower", prevTime, 0);
    double value = ObjectGetValueByTime(0, "lower", time, 0);

    long prevVolume = iVolume(_Symbol, PERIOD_CURRENT, 2);
    long volume = iVolume(_Symbol, PERIOD_CURRENT, 1);
    bool highVolume = (volume > prevVolume);
    if (prevValue == 0 || value == 0)
    {
        Alert("Got zero value");
        return false;
    }
    if (prevClose > prevValue && close < value && highVolume)
    {
        Print("Trend Break Down");
        return true;
    }
    return false;
}

void initializeArray(double &arr[], int len)
{
    for (int i = 0; i < len; i++)
    {
        arr[i] = 0.0;
    }
}

void getRates()
{
    if (!CopyRates(_Symbol, PERIOD_CURRENT, 1, length, rates))
        Print("Couldn't fetch data. Error: ", GetLastError());
}

void Buy()
{
    datetime now = iTime(_Symbol, PERIOD_CURRENT, 0);
    // datetime limitTime = now + barsLimitOrder * PeriodSeconds();
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    // datetime expiration = now + expBars * PeriodSeconds();
    // double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    // double diff = slPoints * _Point;
    // double diff = slATR * bufferATR[0];
    // double sl = entry - diff;
    double sl = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, 5, 0));
    double diff = MathAbs(entry - sl);
    double tp = entry + profitFactor * diff;
    double lots = calculateLots(diff, riskPercent);

    if (!trade.Buy(lots, _Symbol, entry, sl, tp))
    {
        Print("Failed to Buy! Error: ", GetLastError());
    }
}

void Sell()
{
    datetime now = iTime(_Symbol, PERIOD_CURRENT, 0);
    // datetime limitTime = now + barsLimitOrder * PeriodSeconds();
    double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    // datetime expiration = now + expBars * PeriodSeconds();
    // double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    // double diff = slPoints * _Point;
    // double diff = slATR * bufferATR[0];
    // double sl = entry + diff;
    double sl = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_LOW, 5, 0));
    double diff = MathAbs(entry - sl);
    double tp = entry - profitFactor * diff;
    double lots = calculateLots(diff, riskPercent);

    if (!trade.Sell(lots, _Symbol, entry, sl, tp))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}

void TrailStop()
{
    double sl = 0;
    double tp = 0;

    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        // Select Position
        if (!pos.SelectByIndex(i))
            continue;
        ulong ticket = pos.Ticket();

        if (pos.PositionType() == POSITION_TYPE_BUY && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC)
        {
            if (MathAbs(bid - pos.PriceOpen()) > tslPoints * _Point) // If TSL is triggered
            {
                tp = pos.TakeProfit();
                sl = bid - (tslPoints * _Point);
                if (sl > pos.StopLoss() && sl != 0)
                    trade.PositionModify(ticket, sl, tp);
            }
        }
        else if (pos.PositionType() == POSITION_TYPE_SELL && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC)
        {
            if (MathAbs(ask - pos.PriceOpen()) > tslPoints * _Point) // If TSL is triggered
            {
                tp = pos.TakeProfit();
                sl = ask + (tslPoints * _Point);
                if (sl < pos.StopLoss() && sl != 0)
                    trade.PositionModify(ticket, sl, tp);
            }
        }
    }
}


// double Highest(MqlRates &candles[])
// {
//     int size = ArraySize(candles);
//     double highestValue = 0.;
//     highestValue = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, size, 1));
//     highestArray[0] = highestArray[1];
//     highestArray[1] = highestValue;
//     return highestValue;
// }

// double Lowest(MqlRates &candles[])
// {
//     int size = ArraySize(candles);
//     double lowestValue = DBL_MAX;
//     lowestValue = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, size, 1));
//     lowestArray[0] = lowestArray[1];
//     lowestArray[1] = lowestValue;
//     return lowestValue;
// }

// double Change(double &array[])
// {
//     return array[0] - array[1];
// }

// double Sign(double num)
// {
//     return num > 0.0 ? 1.0 : num < 0.0 ? -1.0
//                                        : 0.0;
// }

// double MeanDouble(double &arr[])
// {
//     double mean = 0.0;
//     int size = ArraySize(arr);
//     for (int i = 0; i < size; i++)
//     {
//         mean += arr[i];
//     }
//     return mean / size;
// }

// double MeanInt(int &arr[])
// {
//     double mean = 0.0;
//     int size = ArraySize(arr);
//     for (int i = 0; i < size; i++)
//     {
//         mean += arr[i];
//     }
//     return mean / size;
// }

/*
// Update the values and shift to left.
// Since the data is set as timeseries, the newest bar is index zero,
// so we use that for our new value and shift the previous data to the left.
*/
void updateSeries(double &arr[], double newValue)
{
    int size = ArraySize(arr);
    for (int i = size - 2; i >= 0; i--)
    {
        arr[i + 1] = arr[i];
    }
    arr[0] = newValue;
}

// void calculateAMA()
// {
//     Highest(rates);
//     Lowest(rates);
//     updateSeries(hh, MathMax(Sign(Change(highestArray)), 0.0));
//     updateSeries(ll, MathMax(Sign(Change(lowestArray) * -1.0), 0.0));
//     // FIXME: Might only need to use updateSeries on the last value... I'll think about it later.
//     for (int i = 0; i < length; i++)
//     {
//         // TODO: Might need to expand this. Don't know exactly how MQL5 works is double conditionals.
//         trends[i] = (hh[i] || ll[i] ? 1 : 0);
//     }

//     double mean = MeanInt(trends);
//     double tc = MathPow(mean, 2); // Trade Coefficient
//     double src = rates[0].close;
//     AMA = (AMA == 0.0 ? src : AMA);
//     // if (AMA == 0.0) AMA = src;
//     AMA = (AMA + tc * (src - AMA));
// }

// double TRAMA = 0.;
// double _hh, _ll, _tc, prev_TRAMA;

// void calcTRAMA()
// {
//     // Calculate hh and ll based on highs and lows over 'length' period
//     double highestHigh = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, length, 1));
//     double lowestLow = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, length, 1));

//     // Calculate changes in highest and lowest values
//     _hh = MathMax(Sign(highestHigh - rates[0].high), 0);
//     _ll = MathMax(Sign(lowestLow - rates[0].low) * -1, 0);

//     // Trend Coefficient (tc)
//     double sum_hl = 0.0;
//     for (int j = 0; j < length; j++)
//     {
//         sum_hl += _hh || _ll ? 1.0 : 0.0;
//     }
//     _tc = MathPow(sum_hl / length, 2);

//     // Adaptive Moving Average calculation
//     prev_TRAMA = prev_TRAMA > 0 ? prev_TRAMA : rates[0].close; // Initial condition for first AMA
//     TRAMA = prev_TRAMA + _tc * (rates[0].close - prev_TRAMA);  // AMA recursive formula
// }
