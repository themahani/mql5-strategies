
//---
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
//---

input group "Data Analysis";
input ENUM_TIMEFRAMES periodHigher = PERIOD_H4;
input double b2wRatio = 0.70;   // Body to Wick ratio to consider for FVG detection.
input double fvg2bRatio = 0.50; // FVG top - bottom ratio to the body for FVG detection.
input int fvgLen = 100;     // No. of bars to extend the FVG block
// input int pivotLen = 10;
// input double ratio = 0.50;
input int boxExpBars = 500;         // # of bars to keep the boxes (then they are deleted)


input group "Trade Management";
input double riskPercent = 2.0;         // Risk as a % of trading capital
input int slPoints = 200;               // SL in Points (10 pts = 1 pip)
input double profitFactor = 2.0;        // Profit factor to calculate TP
input ulong EA_MAGIC = 583093450;       // EA Magic ID
input string tradeComment = "Scalping Robot";   // Trade Comment
input int expBars = 100;                // # of bars to expire orders


// ---
int numBars = 0;
int orderDistPoints = 0;  // ?
ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;

// ---
MqlRates rates[];
MqlRates ratesHigher[];
int lenBack = 99;

// Trade
CTrade trade;
CPositionInfo pos;
COrderInfo ord;

enum ENUM_FVG_TYPE 
{
    FVG_BULLISH = 1,
    FVG_BEARISH = -1,
    FVG_NULL = 0
};

struct FVG
{
    double top;
    double bottom;
    double high;
    double low;
    datetime time;
    ENUM_FVG_TYPE type;
    FVG copy()
    {
        FVG copied;
        copied.top = top;
        copied.bottom = bottom;
        copied.high = high;
        copied.low = low;
        copied.time = time;
        copied.type = type;
        return copied;
    }
};

FVG fvgCurrent = {0.0, 0.0, 0., 0., FVG_NULL};
FVG fvgHigher = {0.0, 0.0, 0., 0., FVG_NULL};
FVG fvgSeries[99];

struct Box
{
    datetime startTime;
    datetime endTime;
    string name;
    Box copy()
    {
        Box copied;
        copied.startTime = startTime;
        copied.endTime = endTime;
        copied.name = name;
        return copied;
    }
};

Box boxes[99];

/*
Update the values and shift to left.
Since the data is set as timeseries, the newest bar is index zero,
so we use that for our new value and shift the previous data to the left.
*/
void updateSeriesFVG(FVG &arr[], FVG &newValue)
{
    int size = ArraySize(arr);
    for (int i = size-2; i >=0; i--)
    {
        arr[i+1] = arr[i];
    }
    arr[0] = newValue;
}

void initializeArrayFVG(FVG &arr[], int len)
{
    for (int i = 0; i < len; i++)
    {
        FVG element = {0., 0., 0., 0., 0, FVG_NULL};
        arr[i] = element;
    }
}

void updateSeriesBox(Box &arr[], Box &newValue)
{
    int size = ArraySize(arr);
    for (int i = size-2; i >=0; i--)
    {
        arr[i+1] = arr[i];
    }
    arr[0] = newValue;
}

void initializeArrayBox(Box &arr[], int len)
{
    for (int i = 0; i < len; i++)
    {
        Box element = {NULL, NULL, ""};
        arr[i] = element;
    }
}



bool isBullish(MqlRates &candle)
{
    if (candle.close > candle.open)
    {
        return true;
    }
    return false;
}

bool bigCandle(MqlRates &candle)
{
    double wick = MathAbs(candle.high - candle.low);
    double body = MathAbs(candle.open - candle.close);
    if (body / wick > b2wRatio)
    {
        return true;
    }
    return false;
}

bool bullishFVG(MqlRates &candles[], FVG &fvg)
{
    double top = candles[0].low;
    double bottom = candles[2].high;
    double fvgSize = top - bottom;
    double body = MathAbs(candles[1].close - candles[1].open);

    if (isBullish(candles[1]) && bigCandle(candles[1]) && fvgSize > body * fvg2bRatio)
    {
        fvg.top = top;
        fvg.bottom = bottom;
        fvg.high = candles[1].high;
        fvg.low = candles[1].low;
        fvg.time = candles[1].time;
        fvg.type = FVG_BULLISH;
        updateSeriesFVG(fvgSeries, fvg.copy());
        datetime start = TimeCurrent();
        datetime end = start + 3600;
        DrawBox(fvg, fvgLen);
        return true;
    }
    return false;
}


bool bearishFVG(MqlRates &candles[], FVG &fvg)
{
    double top = candles[2].low;
    double bottom = candles[0].high;
    double fvgSize = top - bottom;
    double body = MathAbs(candles[1].close - candles[1].open);

    if (!isBullish(candles[1]) && bigCandle(candles[1]) && fvgSize > body * fvg2bRatio)
    {
        fvg.top = top;
        fvg.bottom = bottom;
        fvg.high = candles[1].high;
        fvg.low = candles[1].low;
        fvg.time = candles[1].time;
        fvg.type = FVG_BEARISH;
        updateSeriesFVG(fvgSeries, fvg.copy());
        datetime start = TimeCurrent();
        datetime end = start + 3600;
        DrawBox(fvg, fvgLen);
    }
    return false;
}

void updateFVG()
{
    bearishFVG(rates, fvgCurrent);
    bullishFVG(rates, fvgCurrent);
    // bearishFVG(ratesHigher, fvgHigher);
    // bullishFVG(ratesHigher, fvgHigher);
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


// Function to draw a green box on the chart
void DrawBox(FVG &fvg, int nBars)
{
    double clr = clrGreen;
    if (fvg.type == FVG_BEARISH)    clr = clrRed;

    // datetime time1 = TimeCurrent() - 2 * PeriodSeconds(Period());
    datetime time1 = fvg.time;
    datetime time2 = time1 + nBars * PeriodSeconds(Period());
    string name = TimeToString(time1);
    Box newBox = {time1, time2, name};

    // Create the rectangle object
    if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, fvg.bottom, time2, fvg.top))
    {
        Print("Error creating rectangle: ", GetLastError());
        return;
    }

    // Set the rectangle properties
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);           // Outline color
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);         // Outline style
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);                   // Outline width
    ObjectSetInteger(0, name, OBJPROP_BACK, true);                 // Draw in the background

    // Set the fill color and transparency (clrGreen with transparency)
    ObjectSetInteger(0, name, OBJPROP_FILL, true);                 // Enable filling
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);            // Color of the box outline
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);         // Solid style for border
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);                   // Border width
    
    // Set a semi-transparent green shade
    // int transparentGreen = clr & 0x7F00FF00;                  // Green with transparency
    // ObjectSetInteger(0, name, OBJPROP_COLOR, transparentGreen);    // Set transparent color
    updateSeriesBox(boxes, newBox);
}


bool currentInHigher()
{
    if (fvgCurrent.top < fvgHigher.top && fvgCurrent.bottom > fvgHigher.bottom)
    {
        return true;
    }
    
    return false;
}


bool newBar()
{
    int newNumBars = Bars(Symbol(), Period());
    if (newNumBars != numBars)
    {
        numBars = newNumBars;
        return true;
    }
    return false;
}

bool BuyCondition()
{
    if (fvgSeries[0].type == FVG_BULLISH 
    && fvgSeries[1].type == FVG_BULLISH
    && fvgSeries[0].top > fvgSeries[1].top)
    {
        double price = rates[0].close;
        if (price < fvgSeries[0].top && price > fvgSeries[0].bottom)
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
        double price = rates[0].close;
        if (price < fvgSeries[0].top && price > fvgSeries[0].bottom)
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
    if (volumeLimit != 0)   lots = MathMin(lots, volumeLimit);
    if (maxVolume != 0)     lots = MathMin(lots, maxVolume);
    if (minVolume != 0)     lots = MathMax(lots, minVolume);
    lots = NormalizeDouble(lots, 2);

    return lots;
}

void Buy(double entry)
{
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    if (ask > entry - orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double slDiff = slPoints * _Point;
    double sl = entry - slDiff;
    double tp = entry + slDiff * profitFactor;

    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(slDiff);

    datetime expiration = iTime(_Symbol, timeframe, 0) + expBars * PeriodSeconds(timeframe);

    trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, tradeComment);
}

void Sell(double entry)
{
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    if (bid < entry + orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double slDiff = slPoints * _Point;
    double sl = entry + slDiff;
    double tp = entry - slDiff * profitFactor;

    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(sl - entry);

    datetime expiration = iTime(_Symbol, timeframe, 0) + expBars * PeriodSeconds(timeframe);

    trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, tradeComment);
}

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
        if (ord.OrderType() == ORDER_TYPE_BUY_STOP && ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC) buys++;
    }
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
        if (ord.OrderType() == ORDER_TYPE_SELL_STOP && ord.Symbol() == Symbol() && ord.Magic() == EA_MAGIC) sells++;
    }
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

    // ArraySetAsSeries(ph, true);
    // ArraySetAsSeries(pl, true);

    // handleRSI = iRSI(Symbol(), Period(), 14, PRICE_CLOSE);
    // ArraySetAsSeries(bufferRSI, true);
    // handleMA = iMA(Symbol(), periodHigher, 50, 0, MODE_SMA, PRICE_CLOSE);
    // ArraySetAsSeries(bufferMA, true);


    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    
}


void OnTick(void)
{

    if (!newBar())  return;
    
    CopyRates(Symbol(), PERIOD_CURRENT, 1, lenBack, rates);
    CopyRates(Symbol(), periodHigher, 1, lenBack, ratesHigher);
    // CopyBuffer(handleRSI, MAIN_LINE, 1, lenBack, bufferRSI);
    // CopyBuffer(handleMA, MAIN_LINE, 1, lenBack, bufferMA);
    updateFVG();
    updateBoxes();
    // updatePivot();
    Comment(fvgSeries[0].top, "\n", fvgSeries[0].bottom, "\n", fvgSeries[0].type, "\n");

    if (PositionsTotal() == 0)
    {
        if (BuyCondition() && BuysTotal() == 0)
        {
            double entry = fvgSeries[0].top;
            Buy(entry);
        }
        else if (SellCondition() && SellsTotal() == 0)
        {
            double entry = fvgSeries[0].bottom;
            Sell(entry);
        }
    }

}