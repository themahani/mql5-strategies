
//---
#include "include/time.mqh"
#include "include/data_analysis.mqh"
#include "include/trading.mqh"
//---

input group "Data Analysis";
input double b2wRatio = 0.70;   // Body to Wick ratio to consider for FVG detection.
input double fvg2bRatio = 0.50; // FVG top - bottom ratio to the body for FVG detection.

input group "Visualization"
input int fvgLen = 100;     // No. of bars to extend the FVG block
input int boxExpBars = 500;         // # of bars to keep the boxes (then they are deleted)


input group "Trade Management";
input double riskPercent = 2.0;         // Risk as a % of trading capital
input int slPoints = 200;               // SL in Points (10 pts = 1 pip)
input double profitFactor = 2.0;        // Profit factor to calculate TP
input ulong EA_MAGIC = 583093450;       // EA Magic ID
input string tradeComment = "Scalping Robot";   // Trade Comment
input int expBars = 100;                // # of bars to expire orders
input int tslTriggerPoints = 50;        // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 50;               // Trailing SL (10 points = 1 pip)

input group "Indicators"
input int periodRSI = 14;                           // RSI period
input ENUM_TIMEFRAMES timeframeHigher = PERIOD_H4;  // Higher timeframe for EMA
input int periodMAHigher = 14;                      // EMA period for the higher timeframe

input group "Trade Session UTC"
input int startHour = 7;
input int startMinute = 0;
input int endHour = 21;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};


// ---
int numBars = 0;
int orderDistPoints = 0;  // ?
ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;

// ---
MqlRates rates[];
MqlRates ratesHigher[];
int lenBack = 99;

// --- Indicators
int handleRSI;
double bufferRSI[];
int handleEMA;
double bufferEMA[];


// FVGs
FVG fvgCurrent = {0.0, 0.0, 0., 0., FVG_NULL};
FVG fvgSeries[99];

// Boxes
Box boxes[99];

// Trade
CTrade trade;
CPositionInfo pos;
COrderInfo ord;



void updateFVG()
{
    if (bearishFVG(rates, fvgCurrent, fvg2bRatio, b2wRatio))
    {
        updateSeriesFVG(fvgSeries, fvgCurrent.copy());
        updateSeriesBox(boxes, DrawBox(fvgCurrent.copy(), fvgLen));
    }

    else if (bullishFVG(rates, fvgCurrent, fvg2bRatio, b2wRatio))
    {
        updateSeriesFVG(fvgSeries, fvgCurrent.copy());
        updateSeriesBox(boxes, DrawBox(fvgCurrent.copy(), fvgLen));
    }
}

void updateBoxes()
{
    // The time before which the boxed should be deleted
    datetime expTime = iTime(_Symbol, PERIOD_CURRENT, 0) - boxExpBars * PeriodSeconds(PERIOD_CURRENT);
    for (int i = ArraySize(boxes)-1; i >= 0; i--)
    {
        if (boxes[i].startTime < expTime)   ObjectDelete(0, boxes[i].name);
    }
}

bool BuyCondition()
{
    if (fvgSeries[0].type == FVG_BULLISH 
    && fvgSeries[1].type == FVG_BULLISH
    && fvgSeries[0].top > fvgSeries[1].top)
    {
        // if (iClose(_Symbol, timeframeHigher, 0) > bufferEMA[0])
        if (bufferRSI[0] > 70)  // Not over bought
            return false;
        double close = rates[0].close;
        double low = rates[0].low;

        if ((close < fvgSeries[0].top && close > fvgSeries[0].bottom)
            || (low < fvgSeries[0].top && low > fvgSeries[0].bottom))
        {
            return true;
        }
    }
    
    return false;
}

bool SellCondition()
{
    if (fvgSeries[0].type == FVG_BEARISH 
    && fvgSeries[1].type == FVG_BEARISH
    && fvgSeries[0].bottom < fvgSeries[1].bottom)
    {
        // if (iClose(_Symbol, timeframeHigher, 0) < bufferEMA[0])
        if (bufferRSI[0] < 30)  // Not over sold
            return false;
        double close = rates[0].close;
        double high = rates[0].high;

        if ((close < fvgSeries[0].top && close > fvgSeries[0].bottom)
            || (high < fvgSeries[0].top && high > fvgSeries[0].bottom))
        {
            return true;
        }
    }
    
    return false;
}


// void Buy()
// {
//     double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
//     double slDiff = slPoints * _Point;
//     double sl = ask - slDiff;
//     double tp = ask + slDiff * profitFactor;

//     if(!trade.Buy(Lots, _Symbol, ask, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
//     {
//         Print("Failed to Buy! Error: ", GetLastError());
//     }
// }

// void Sell()
// {
//     double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
//     double slDiff = slPoints * _Point;
//     double sl = bid + slDiff;
//     double tp = bid - slDiff * profitFactor;

//     if(!trade.Buy(Lots, _Symbol, bid, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
//     {
//         Print("Failed to Sell! Error: ", GetLastError());
//     }
// }

void CloseAllOrders()
{
    for (int i = OrdersTotal()-1; i >= 0; i--)
    {
        ord.SelectByIndex(i);
        ulong ticket = ord.Ticket();
        if (ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC)
        {
            trade.OrderDelete(ticket);
        }
    }
}

int BuysTotal()
{
    int buys = 0;
    for (int i = PositionsTotal()-1; i >= 0; i--)
    {
        pos.SelectByIndex(i);
        if (pos.PositionType() == POSITION_TYPE_BUY && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC) buys++;
    }
    for (int i = OrdersTotal()-1; i >= 0; i--)
    {
        ord.SelectByIndex(i);
        if (ord.OrderType() == ORDER_TYPE_BUY_LIMIT && ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC) buys++;
    }
    Alert("Buys total is ", buys);
    return buys;
}

int SellsTotal()
{
    int sells = 0;
    for (int i = PositionsTotal()-1; i >= 0; i--)
    {
        pos.SelectByIndex(i);
        if (pos.PositionType() == POSITION_TYPE_SELL && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC) sells++;
    }
    for (int i = OrdersTotal()-1; i >= 0; i--)
    {
        ord.SelectByIndex(i);
        if (ord.OrderType() == ORDER_TYPE_SELL_LIMIT && ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC) sells++;
    }
    Alert("Sells total is ", sells);
    return sells;
}


int OnInit(void)
{
    Print(Symbol(), PERIOD_CURRENT);
    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(ratesHigher, true);

    initializeArrayFVG(fvgSeries, lenBack);
    ArraySetAsSeries(fvgSeries, true);

    initializeArrayBox(boxes, lenBack);
    ArraySetAsSeries(boxes, true);

    trade.SetExpertMagicNumber(EA_MAGIC);

    handleRSI = iRSI(Symbol(), Period(), periodRSI, PRICE_CLOSE);
    ArraySetAsSeries(bufferRSI, true);
    handleEMA = iMA(Symbol(), timeframeHigher, periodMAHigher, 0, MODE_EMA, PRICE_CLOSE);
    ArraySetAsSeries(bufferEMA, true);


    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    
}


void OnTick(void)
{

    TrailStop(pos, trade, EA_MAGIC, tslTriggerPoints, tslPoints);
    if (!newBar())  return;

    CopyRates(Symbol(), PERIOD_CURRENT, 1, lenBack, rates);
    CopyBuffer(handleRSI, MAIN_LINE, 1, 10, bufferRSI);
    CopyBuffer(handleEMA, MAIN_LINE, 1, lenBack, bufferEMA);
    // CopyBuffer(handleRSI, MAIN_LINE, 1, lenBack, bufferRSI);

    updateFVG();
    updateBoxes();
    // updatePivot();
    Comment(fvgSeries[0].top, "\n", fvgSeries[0].bottom, "\n", fvgSeries[0].type, "\n",
    rates[0].close);

    if (PositionsTotal() == 0 && TradeSession(startTime, endTime))
    {
        if (BuyCondition() && BuysTotal() == 0)
        {
            double entry = fvgSeries[0].top;
            BuyLimit(trade, entry, slPoints, profitFactor, riskPercent, expBars);
        }
        else if (SellCondition() && SellsTotal() == 0)
        {
            double entry = fvgSeries[0].bottom;
            SellLimit(trade, entry, slPoints, profitFactor, riskPercent, expBars);
        }
    }
}

