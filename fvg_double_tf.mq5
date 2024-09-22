
//---
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
//---

input group "Data Analysis";
input ENUM_TIMEFRAMES periodHigher = PERIOD_H4;
// Body to Wick ratio to consider for FVG detection.
input double b2wRatio = 0.70;
// FVG top - bottom ratio to the body for FVG detection.
input double fvg2bRatio = 0.50;

// input int pivotLen = 10;
// input double ratio = 0.50;



input group "Trade Management";
input double Lots = 0.1;


// ---
int numBars = 0;
// ---
MqlRates rates[];
MqlRates ratesHigher[];
int lenBack = 99;


// Trade
CTrade trade;


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
    ENUM_FVG_TYPE type;
};

FVG fvgCurrent = {0.0, 0.0, 0., 0., FVG_NULL};
FVG fvgHigher = {0.0, 0.0, 0., 0., FVG_NULL};

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
        fvg.type = FVG_BULLISH;
        datetime start = TimeCurrent();
        datetime end = start + 3600;
        DrawBox("Bullish FVG", start, bottom, end, top, clrGreen);
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
        fvg.type = FVG_BEARISH;
        datetime start = TimeCurrent();
        datetime end = start + 3600;
        DrawBox("Bullish FVG", start, bottom, end, top, clrRed);
    }
    return false;
}

void updateFVG()
{
    bearishFVG(rates, fvgCurrent);
    bullishFVG(rates, fvgCurrent);
    bearishFVG(ratesHigher, fvgHigher);
    bullishFVG(ratesHigher, fvgHigher);
}

// Function to draw a green box on the chart
void DrawBox(string name, datetime time1, double price1, datetime time2, double price2, color clr)
{
    // Create the rectangle object
    if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2))
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

    Print("Box created successfully!");
}

// bool lookForBuy()

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
    if (fvgCurrent.type == FVG_BULLISH 
    && fvgHigher.type == FVG_BULLISH
    && currentInHigher())
    {
        double price = rates[0].close;
        if (price < fvgCurrent.top && price > fvgCurrent.low)
        {
            return true;
        }
    }
    
    return false;
}

bool SellCondition()
{
    if (fvgCurrent.type == FVG_BEARISH && fvgHigher.type == FVG_BEARISH && currentInHigher())
    {
        double price = rates[0].close;
        if (price < fvgCurrent.top && price > fvgCurrent.low)
        {
            return true;
        }
    }
    
    return false;
}

void Buy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = fvgHigher.low;
    double tp = fvgHigher.high;

    if(!trade.Buy(Lots, _Symbol, ask, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}

void Sell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = fvgHigher.high;
    double tp = fvgHigher.low;

    if(!trade.Buy(Lots, _Symbol, bid, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}


int OnInit(void)
{
    Print(Symbol(), PERIOD_CURRENT);
    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(ratesHigher, true);
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
    if (newBar())
    {
        CopyRates(Symbol(), PERIOD_CURRENT, 1, lenBack, rates);
        CopyRates(Symbol(), periodHigher, 1, lenBack, ratesHigher);
        // CopyBuffer(handleRSI, MAIN_LINE, 1, lenBack, bufferRSI);
        // CopyBuffer(handleMA, MAIN_LINE, 1, lenBack, bufferMA);
        updateFVG();
        // updatePivot();
        Comment(fvgCurrent.top, "\n", fvgCurrent.bottom, "\n", fvgCurrent.type, "\n", rates[0].close);

        if (PositionsTotal() == 0)
        {
            if (BuyCondition())
            {
                Buy();
            }
            else if (SellCondition())
            {
                Sell();
            }
        }
    }
}