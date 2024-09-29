
//---
#include "include/time.mqh"
#include "include/data_analysis.mqh"
#include "include/trading.mqh"
//---

input group "Data Analysis";
input double b2wRatio = 0.70;   // Body to Wick ratio to consider for FVG detection.
input double fvg2bRatio = 0.50; // FVG top - bottom ratio to the body for FVG detection.

input group "Visualization";
input int fvgLen = 100;     // No. of bars to extend the FVG block
input int boxExpBars = 500; // # of bars to keep the boxes (then they are deleted)

input group "Trade Management";
input double riskPercent = 2.0;               // Risk as a % of trading capital
input int slPoints = 200;                     // SL in Points (10 pts = 1 pip)
input double profitFactor = 2.0;              // Profit factor to calculate TP
input ulong EA_MAGIC = 583093450;             // EA Magic ID
input string tradeComment = "Scalping Robot"; // Trade Comment
input int expBars = 100;                      // # of bars to expire orders
input bool isTrailStop = true;                // Use Trailing SL ?
input int tslTriggerPoints = 50;              // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 50;                     // Trailing SL (10 points = 1 pip)

input group "Indicators";
input int periodRSI = 14;                          // RSI period
input ENUM_TIMEFRAMES timeframeHigher = PERIOD_H4; // Higher timeframe for EMA
input int periodMAHigher = 14;                     // EMA period for the higher timeframe

input group "Trade Session UTC";
input int startHour = 7;
input int startMinute = 0;
input int endHour = 21;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};

// ---
// int numBars = 0;
// int orderDistPoints = 0;  // ?
// ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;

// ---
MqlRates rates[];
int histBars = 99;

// --- Indicators
int handleRSI;
double bufferRSI[];
int handleEMA;
double bufferEMA[];

// FVGs
FVG fvgCurrent = {0.0, 0.0, 0., 0., FVG_NULL};
FVG fvgSeries[];

// Boxes
Box boxes[];

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
    for (int i = ArraySize(boxes) - 1; i >= 0; i--)
    {
        if (boxes[i].startTime < expTime)
            ObjectDelete(0, boxes[i].name);
    }
}

bool BuyCondition()
{
    if (fvgSeries[0].type == FVG_BULLISH && fvgSeries[1].type == FVG_BULLISH && fvgSeries[0].top > fvgSeries[1].top)
    {
        // if (iClose(_Symbol, timeframeHigher, 0) > bufferEMA[0])
        if (bufferRSI[0] > 70) // Not over bought
            return false;
        double close = rates[0].close;
        double low = rates[0].low;

        if ((close < fvgSeries[0].top && close > fvgSeries[0].bottom) || (low < fvgSeries[0].top && low > fvgSeries[0].bottom))
        {
            return true;
        }
    }

    return false;
}

bool PriceInFVG(FVG &fvg, double price)
{
    return (price < fvg.top && price > fvg.bottom);
}

bool PriceTouchDownFVG(FVG &fvg, MqlRates &candle)
{
    return (candle.close > fvg.top && candle.open > fvg.top && PriceInFVG(fvg, candle.low));
}

bool PriceTouchUpFVG(FVG &fvg, MqlRates &candle)
{
    return (candle.close < fvg.bottom && candle.open < fvg.bottom && PriceInFVG(fvg, candle.high));
}

bool BuyCond1(MqlRates &candle, int len)
{
    for (int i = 0; i < len; i++)
    {
        if (PriceTouchDownFVG(fvgSeries[i], candle) && fvgSeries[i].type == FVG_BULLISH)
            return true;
    }
    return false;
}

bool SellCond1(MqlRates &candle, int len)
{
    for (int i = 0; i < len; i++)
    {
        if (PriceTouchUpFVG(fvgSeries[i], candle) && fvgSeries[i].type == FVG_BEARISH)
            return true;
    }
    return false;
}

bool SellCondition()
{
    if (fvgSeries[0].type == FVG_BEARISH && fvgSeries[1].type == FVG_BEARISH && fvgSeries[0].bottom < fvgSeries[1].bottom)
    {
        // if (iClose(_Symbol, timeframeHigher, 0) < bufferEMA[0])
        if (bufferRSI[0] < 30) // Not over sold
            return false;
        double close = rates[0].close;
        double high = rates[0].high;

        if ((close < fvgSeries[0].top && close > fvgSeries[0].bottom) || (high < fvgSeries[0].top && high > fvgSeries[0].bottom))
        {
            return true;
        }
    }

    return false;
}

void Buy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double slDiff = slPoints * _Point;
    double sl = ask - slDiff;
    double tp = ask + slDiff * profitFactor;
    double lots = calculateLots(slDiff, riskPercent);

    if(!trade.Buy(lots, _Symbol, ask, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Buy! Error: ", GetLastError());
    }
}

void Sell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slDiff = slPoints * _Point;
    double sl = bid + slDiff;
    double tp = bid - slDiff * profitFactor;
    double lots = calculateLots(slDiff, riskPercent);

    if(!trade.Sell(lots, _Symbol, bid, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}

void CloseAllOrders()
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
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
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        pos.SelectByIndex(i);
        if (pos.PositionType() == POSITION_TYPE_BUY && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC)
            buys++;
    }
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ord.SelectByIndex(i);
        if (ord.OrderType() == ORDER_TYPE_BUY_LIMIT && ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC)
            buys++;
    }
    // Alert("Buys total is ", buys);
    return buys;
}

int SellsTotal()
{
    int sells = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        pos.SelectByIndex(i);
        if (pos.PositionType() == POSITION_TYPE_SELL && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC)
            sells++;
    }
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ord.SelectByIndex(i);
        if (ord.OrderType() == ORDER_TYPE_SELL_LIMIT && ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC)
            sells++;
    }
    // Alert("Sells total is ", sells);
    return sells;
}

int OnInit(void)
{
    Print(Symbol(), PERIOD_CURRENT);
    ArraySetAsSeries(rates, true);

    ArrayResize(fvgSeries, histBars);
    initializeArrayFVG(fvgSeries, histBars);
    ArraySetAsSeries(fvgSeries, true);

    ArrayResize(boxes, histBars);
    initializeArrayBox(boxes, histBars);
    ArraySetAsSeries(boxes, true);

    trade.SetExpertMagicNumber(EA_MAGIC);

    handleRSI = iRSI(Symbol(), Period(), periodRSI, PRICE_CLOSE);
    ArraySetAsSeries(bufferRSI, true);
    handleEMA = iMA(Symbol(), timeframeHigher, periodMAHigher, 0, MODE_SMA, PRICE_CLOSE);
    ArraySetAsSeries(bufferEMA, true);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick(void)
{
    if (isTrailStop)
        TrailStop(pos, trade, EA_MAGIC, tslTriggerPoints, tslPoints);

    if (!newBar())
        return;

    CopyRates(Symbol(), PERIOD_CURRENT, 1, histBars, rates);
    CopyBuffer(handleRSI, MAIN_LINE, 1, 10, bufferRSI);
    CopyBuffer(handleEMA, MAIN_LINE, 1, histBars, bufferEMA);

    updateFVG();
    updateBoxes();

    Comment(fvgSeries[0].top, "\n", fvgSeries[0].bottom, "\n", fvgSeries[0].type, "\n",
            rates[0].close);

    if (PositionsTotal() == 0 && TradeSession(startTime, endTime))
    {
        if (BuyCond1(rates[0], 1) && BuysTotal() == 0)
        {
            Buy();
            // double entry = fvgSeries[0].top;
            // BuyLimit(trade, entry, slPoints, profitFactor, riskPercent, expBars);
        }
        else if (SellCond1(rates[0], 1) && SellsTotal() == 0)
        {
            Sell();
            // double entry = fvgSeries[0].bottom;
            // SellLimit(trade, entry, slPoints, profitFactor, riskPercent, expBars);
        }
    }
}
