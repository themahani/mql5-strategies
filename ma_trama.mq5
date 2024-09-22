//+------------------------------------------------------------------+
//|                                                  MACD Sample.mq5 |
//|                             Copyright 2000-2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2024, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "5.50"
#property description "It is important to make sure that the expert works with a normal"
#property description "chart and the user did not make any mistakes setting input"
#property description "variables (Lots, TakeProfit, TrailingStop) in our case,"
#property description "we check TakeProfit on a chart of more than 2*trend_period bars"

#define MACD_MAGIC 1234502
//---
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
//---

input group "iMA Params"
input ENUM_TIMEFRAMES timeFrameMA = PERIOD_H1;
input int periodMA = 100;
input ENUM_MA_METHOD methodMA = MODE_SMA;
input ENUM_APPLIED_PRICE appliedPriceMA = PRICE_CLOSE;

input group "Money Management";
input double Lots = 0.1;
input double profitFactor = 2.0;
input ulong MAGIC = 3948302840;

input group "Trendline Breakout Params";
input int lenBack = 14;
input double atrMultiplier = 1.0;    // ATR multiplier

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

// SMA
int handleMA;
double dataMA[2];

// TRAMA
int length = 99;
double AMA = 0.0;

MqlRates rates[];
double highestArray[2];
double lowestArray[2];
double hh[99];
double ll[99];
int trends[99];

int numOfBars = 0;

// Trend line Breakout
double upper = 0.0;  // Upper trendline
double lower = 0.0;  // Lower trendline
double slope_ph = 0.0;  // Slope for swing high
double slope_pl = 0.0;  // Slope for swing low
double upos = 0.0;
double dnos = 0.0;
double ph = 0.0, pl = 0.0;

bool TradeSession()
{
    MqlDateTime tm = {};
    datetime current = TimeGMT(tm);
    int startMins = startHour * 60 + startMinute;
    int endMins = endHour * 60 + endMinute;

    int currentMins = tm.hour * 60 + tm.min;

    return (currentMins >= startMins && currentMins <= endMins);
}


double pivotHigh(MqlRates &rates[], int ind)
{
    for (int i = 1; i < lenBack; i++)
    {
        if (rates[ind].high <= rates[ind+i].high || rates[ind].high <= rates[ind-1].high)
        {
            return 0.0;
        }
    }
    
    return rates[ind].high;
}

double pivotLow(MqlRates &rates[], int ind)
{
    for (int i = 1; i < lenBack; i++)
    {
        if (rates[ind].low >= rates[ind+i].low || rates[ind].low >= rates[ind-1].low)
        {
            return 0.0;
        }
    }
    
    return rates[ind].low;
}

double calculateSlope()
{
    double atrValue = iATR(NULL, 0, lenBack);
    double slope = atrValue * atrMultiplier;
    return slope;
}

void UpdateTrendlines(int i)
{
    double slope = calculateSlope();  // Calculate slope
    ph = pivotHigh(rates, lenBack);
    if(ph)
    {
        slope_ph = slope;  // Update slope for the swing high
        upper = ph;  // Update upper trendline to the new swing high
    }
    else
    {
        // FIXME: Sometimes shows negative values.
        upper -= slope_ph;  // Extend the upper trendline downward
    }

    pl = pivotLow(rates, lenBack);
    if(pl)
    {
        slope_pl = slope;  // Update slope for the swing low
        lower = pl;  // Update lower trendline to the new swing low
    }
    else
    {
        lower += slope_pl;  // Extend the lower trendline upward
    }
}

// Function to create and update trendline objects
// void PlotTrendlines(const MqlRates &rates[], int i)
// {
//     string upper_line_name = "UpperTrendline_" + IntegerToString(i);
//     string lower_line_name = "LowerTrendline_" + IntegerToString(i);

//     // Plot upper trendline
//     if(!ObjectFind(0, upper_line_name))
//     {
//         ObjectCreate(upper_line_name, OBJ_TREND, 0, rates[i].time, upper, rates[i - 1].time, upper - slope_ph);
//         ObjectSetInteger(0, upper_line_name, OBJPROP_COLOR, 0, clrTeal);
//     }
//     else
//     {
//         ObjectMove(0, upper_line_name, 0, rates[i].time, upper);
//         ObjectMove(0, upper_line_name, 1, rates[i - 1].time, upper - slope_ph);
//     }

//     // Plot lower trendline
//     if(!ObjectFind(0, lower_line_name))
//     {
//         ObjectCreate(lower_line_name, OBJ_TREND, 0, rates[i].time, lower, rates[i - 1].time, lower + slope_pl);
//         ObjectSetInteger(0, lower_line_name, OBJPROP_COLOR, 0, clrRed);
//     }
//     else
//     {
//         ObjectMove(0, lower_line_name, 0, rates[i].time, lower);
//         ObjectMove(0, lower_line_name, 1, rates[i - 1].time, lower + slope_pl);
//     }
// }

bool trendlineBreakUp()
{
    double new_upos = ph ? 0 : rates[0].close > upper + slope_ph * lenBack ? 1 : upos;
    if (new_upos > upos)
    {
        upos = new_upos;
        Print("TrendLine Break Up");
        return true;
    }
    upos = new_upos;
    return false;
}

bool trendlineBreakDown()
{
    double new_dnos = pl ? 0 : rates[0].close < lower - slope_pl * lenBack ? 1 : dnos;
    if (new_dnos > dnos)
    {
        dnos = new_dnos;
        Print("TrendLine Break Down");
        return true;
    }
    dnos = new_dnos;
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

double Highest(MqlRates &rates[])
{
    int size = ArraySize(rates);
    double highestValue = 0.;
    for (int i = size - 1; i >= 0; i--)
    {
        if (rates[i].high > highestValue)
            highestValue = rates[i].high;
    }
    // Push the new data point to array
    highestArray[0] = highestArray[1];
    highestArray[1] = highestValue;
    return highestValue;
}

double Lowest(MqlRates &rates[])
{
    int size = ArraySize(rates);
    double lowestValue = 999999.9;
    for (int i = size - 1; i >= 0; i--)
    {
        if (rates[i].low > lowestValue)
            lowestValue = rates[i].low;
    }
    // Push the new data point to array
    lowestArray[0] = lowestArray[1];
    lowestArray[1] = lowestValue;
    return lowestValue;
}

double Change(double &array[])
{
    return array[1] - array[0];
}

double Sign(double num)
{
    return num > 0.0 ? 1.0 : num < 0.0 ? -1.0
                                       : 0.0;
}

double MeanDouble(double &arr[])
{
    double mean = 0.0;
    int size = ArraySize(arr);
    for (int i = 0; i < size; i++)
    {
        mean += arr[i];
    }
    return mean / size;
}

double MeanInt(int &arr[])
{
    double mean = 0.0;
    int size = ArraySize(arr);
    for (int i = 0; i < size; i++)
    {
        mean += arr[i];
    }
    return mean / size;
}


/*
// Update the values and shift to left.
// Since the data is set as timeseries, the newest bar is index zero,
// so we use that for our new value and shift the previous data to the left.
*/
void updateSeries(double &arr[], double newValue)
{
    int size = ArraySize(arr);
    for (int i = size-2; i >=0; i--)
    {
        arr[i+1] = arr[i];
    }
    arr[0] = newValue;
}

void calculateAMA()
{
    Highest(rates);
    Lowest(rates);
    updateSeries(hh, MathMax(Sign(Change(highestArray)), 0.0));
    updateSeries(ll, MathMax(Sign(Change(lowestArray) * -1.0), 0.0));
    // FIXME: Might only need to use updateSeries on the last value... I'll think about it later.
    for (int i = 0; i < length; i++)
    {
        // TODO: Might need to expand this. Don't know exactly how MQL5 works is double conditionals.
        trends[i] = (hh[i] || ll[i] ? 1 : 0);
    }
    
    double mean = MeanInt(trends);
    double tc = MathPow(mean, 2);   // Trade Coefficient
    double src = rates[0].close;
    AMA = AMA == 0.0 ? src : AMA;
    // if (AMA == 0.0) AMA = src;
    AMA = (AMA + tc * (src - AMA));
}

double TRAMA = 0.;
double _hh, _ll, _tc, prev_TRAMA;

void calcTRAMA()
{
    // Calculate hh and ll based on highs and lows over 'length' period
    double highestHigh = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, length, length));
    double lowestLow = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, length, length));

    // Calculate changes in highest and lowest values
    _hh = MathMax(Sign(highestHigh - rates[0].high), 0);
    _ll = MathMax(Sign(lowestLow - rates[0].low) * -1, 0);

    // Trend Coefficient (tc)
    double sum_hl = 0.0;
    for (int j = 0; j < length; j++)
    {
        sum_hl += _hh || _ll ? 1.0 : 0.0;
    }
    _tc = MathPow(sum_hl / length, 2);

    // Adaptive Moving Average calculation
    prev_TRAMA = prev_TRAMA > 0 ? prev_TRAMA : rates[0].close;       // Initial condition for first AMA
    TRAMA = prev_TRAMA + _tc * (rates[0].close - prev_TRAMA); // AMA recursive formula
}

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(void)
{
    // handleMA = iMA(_Symbol, _Period, periodMA, 0, methodMA, appliedPriceMA);
    Print(_Symbol);

    // TRAMA
    ArraySetAsSeries(rates, true);
    initializeArray(hh, length);
    initializeArray(ll, length);
    ArraySetAsSeries(hh, true);
    ArraySetAsSeries(ll, true);

    trade.SetExpertMagicNumber(MAGIC);

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
    if(newBar())
    {
        // if(!CopyBuffer(handleMA, MAIN_LINE, 1, 2, dataMA))
        // {
        //     Print("Failed to Copy iMA buffer! Error: ", GetLastError());
        // }
        getRates();
        calculateAMA();
        // calcTRAMA();
        
        UpdateTrendlines(lenBack);

        Comment(AMA, "\n", upper, "\n", lower, "\n", ph, "\n", pl);

        if (PositionsTotal() == 0 && TradeSession())
        {
            if (trendlineBreakUp() && rates[0].close > AMA)
            {
                Buy(3);
            }
            else if (trendlineBreakDown() && rates[0].close < AMA)
            {
                Sell(3);
            }
        }
    }
}
//+------------------------------------------------------------------+

bool newBar()
{
    int bars = Bars(Symbol(), Period());
    if (bars != numOfBars)
    {
        numOfBars = bars;
        return true;
    }
    return false;
}

void Buy(int numBars)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = rates[0].close;
    for (int i = 0; i < numBars; i++)
    {
        sl = MathMin(sl, rates[i].close);
    }
    // sl = MathMin(sl, AMA);
    double diff = MathAbs(ask - sl);
    sl -= diff * 1.2;
    double tp = ask + profitFactor * diff;

    if(!trade.Buy(Lots, _Symbol, ask, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}

void Sell(int numBars)
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = rates[0].close;
    for (int i = 0; i < numBars; i++)
    {
        sl = MathMax(sl, rates[i].close);
    }
    // sl = MathMax(sl, AMA);
    double diff = MathAbs(bid - sl);
    sl += diff * 1.2;
    double tp = bid - profitFactor * diff;

    if(!trade.Sell(Lots, _Symbol, bid, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}