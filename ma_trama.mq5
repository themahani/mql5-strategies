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
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>
//---

input group "iMA Params" input ENUM_TIMEFRAMES timeFrameMA = PERIOD_H1;
input int periodMA = 100;
input ENUM_MA_METHOD methodMA = MODE_SMA;
input ENUM_APPLIED_PRICE appliedPriceMA = PRICE_CLOSE;

input group "Trade Management"
    // input double Lots = 0.1;
    input double riskPercent = 2.0; // Risk as a % of trading capital
input double profitFactor = 2.0;
input ulong EA_MAGIC = 3948302840; // EA Magic ID
// input int tpPoints = 200;               // Take Profit in Points (10 points = 1 pip)
input int slPoints = 200;        // Stop Loss in Points (10 points = 1 pip)
input int tslTriggerPoints = 15; // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 10;        // Trailing SL (10 points = 1 pip)
input int barsLimitOrder = 4;    // Bars to look forward to for limit order
input int expBars = 100;         // # of bars after which the orders expire

input group "Trendline Breakout Params" input int lenBack = 14; // # of bars to look around for pivots detection
input double atrMultiplier = 1.0;                               // ATR multiplier

input group "Trade Session UTC" input int startHour = 0;
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
double upper = 0.0;    // Upper trendline
double lower = 0.0;    // Lower trendline
double slope_ph = 0.0; // Slope for swing high
double slope_pl = 0.0; // Slope for swing low
double upos = 0.0;
double dnos = 0.0;
double ph = 0.0, pl = 0.0;

// iATR
int handleATR;
double bufferATR[];

bool TradeSession()
{
    MqlDateTime tm = {};
    datetime current = TimeGMT(tm);
    int startMins = startHour * 60 + startMinute;
    int endMins = endHour * 60 + endMinute;

    int currentMins = tm.hour * 60 + tm.min;

    return (currentMins >= startMins && currentMins <= endMins);
}

double pivotHigh()
{
    double highest = 0;
    int count = 2 * lenBack + 1;
    int highestIndex = iHighest(NULL, 0, MODE_HIGH, count, 0);
    if (highestIndex == (lenBack + 1))
        highest = iHigh(NULL, 0, highestIndex);
    return highest;
}

double pivotLow()
{
    double lowest = 0;
    int count = 2 * lenBack + 1;
    int highestIndex = iLowest(NULL, 0, MODE_LOW, count, 0);
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
    double slope = bufferATR[0] / 10.0 * atrMultiplier;
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

    if (prevValue == 0 || value == 0)
    {
        Alert("Got zero value");
        return false;
    }
    if (prevClose < prevValue && close > value)
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

    if (prevValue == 0 || value == 0)
    {
        Alert("Got zero value");
        return false;
    }
    if (prevClose > prevValue && close < value)
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

double Highest(MqlRates &rates[])
{
    int size = ArraySize(rates);
    double highestValue = 0.;
    highestValue = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, size, 1));
    // for (int i = size - 1; i >= 0; i--)
    // {
    //     if (rates[i].high > highestValue)
    //         highestValue = rates[i].high;
    // }
    // Push the new data point to array
    highestArray[0] = highestArray[1];
    highestArray[1] = highestValue;
    return highestValue;
}

double Lowest(MqlRates &rates[])
{
    int size = ArraySize(rates);
    double lowestValue = DBL_MAX;
    lowestValue = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, size, 1));
    // for (int i = size - 1; i >= 0; i--)
    // {
    //     if (rates[i].low > lowestValue)
    //         lowestValue = rates[i].low;
    // }
    // Push the new data point to array
    lowestArray[0] = lowestArray[1];
    lowestArray[1] = lowestValue;
    return lowestValue;
}

double Change(double &array[])
{
    return array[0] - array[1];
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
    for (int i = size - 2; i >= 0; i--)
    {
        arr[i + 1] = arr[i];
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
    double tc = MathPow(mean, 2); // Trade Coefficient
    double src = rates[0].close;
    AMA = (AMA == 0.0 ? src : AMA);
    // if (AMA == 0.0) AMA = src;
    AMA = (AMA + tc * (src - AMA));
}

double TRAMA = 0.;
double _hh, _ll, _tc, prev_TRAMA;

void calcTRAMA()
{
    // Calculate hh and ll based on highs and lows over 'length' period
    double highestHigh = iHigh(NULL, 0, iHighest(NULL, 0, MODE_HIGH, length, 1));
    double lowestLow = iLow(NULL, 0, iLowest(NULL, 0, MODE_LOW, length, 1));

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
    prev_TRAMA = prev_TRAMA > 0 ? prev_TRAMA : rates[0].close; // Initial condition for first AMA
    TRAMA = prev_TRAMA + _tc * (rates[0].close - prev_TRAMA);  // AMA recursive formula
}

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

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

    trade.SetExpertMagicNumber(EA_MAGIC);

    handleATR = iATR(NULL, 0, lenBack);
    ArraySetAsSeries(bufferATR, true);

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
    // TrailStop();
    if (!newBar())
        return;

    CopyBuffer(handleATR, MAIN_LINE, 0, lenBack, bufferATR);
    getRates();
    calculateAMA();
    calcTRAMA();
    UpdateTrendlines();

    Comment(AMA, "\n", TRAMA, "\n", lower, "\n", ph, "\n", pl);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (PositionsTotal() == 0 && TradeSession())
    {
        if (trendlineBreakUp() && ask > AMA)
        {
            Buy();
        }
        else if (trendlineBreakDown() && bid < AMA)
        {
            Sell();
        }
    }
}
//+------------------------------------------------------------------+

bool newBar()
{
    static datetime previousTime = 0;
    datetime newTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    if (previousTime != newTime)
    {
        previousTime = newTime;
        return true;
    }
    return false;
}

void Buy()
{
    datetime now = iTime(_Symbol, PERIOD_CURRENT, 0);
    datetime limitTime = now + barsLimitOrder * PeriodSeconds();
    double entry = ObjectGetValueByTime(0, "upper", limitTime);
    datetime expiration = now + expBars * PeriodSeconds();
    // double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double diff = slPoints * _Point;
    double sl = entry - diff;
    double tp = entry + profitFactor * diff;
    double lots = calculateLots(diff);

    if (!trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, "Buy Limit!"))
    {
        Print("Failed to Buy! Error: ", GetLastError());
    }
}

void Sell()
{
    datetime now = iTime(_Symbol, PERIOD_CURRENT, 0);
    datetime limitTime = now + barsLimitOrder * PeriodSeconds();
    double entry = ObjectGetValueByTime(0, "upper", limitTime);
    datetime expiration = now + expBars * PeriodSeconds();
    // double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double diff = slPoints * _Point;
    double sl = entry + diff;
    double tp = entry - profitFactor * diff;
    double lots = calculateLots(diff);

    if (!trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, "Sell Limit!"))
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

double calculateLots(double slDiff)
{
    double risk = AccountInfoDouble(ACCOUNT_BALANCE) * riskPercent / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double volumeLimit = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_LIMIT);

    double moneyPerLotstep = slDiff / tickSize * tickValue * lotstep;
    double lots = MathFloor(risk * moneyPerLotstep) * lotstep;
    if (volumeLimit != 0)
        lots = MathMin(lots, volumeLimit);
    if (maxVolume != 0)
        lots = MathMin(lots, maxVolume);
    if (minVolume != 0)
        lots = MathMax(lots, minVolume);
    lots = NormalizeDouble(lots, 2);

    return lots;
}