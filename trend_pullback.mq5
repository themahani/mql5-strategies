//---
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\Trade.mqh>
//---


input group "Trading Inputs"
input double riskPercent = 2.0;         // Risk as a % of trading capital
input int tpPoints = 200;               // Take Profit in Points (10 points = 1 pip)
input int slPoints = 200;               // Stop Loss in Points (10 points = 1 pip)
input int tslTriggerPoints = 15;        // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 10;               // Trailing SL (10 points = 1 pip)
input ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;    // Timeframe to run
input ulong EA_MAGIC = 295047604;       // EA MAGIC ID
input string tradeComment = "Scalping Robot";   // Trade Comment

enum SessionHour {Inactive = 0, _0100 = 1, _0200=2, _0300=3, _0400=4, _0500=5, _0600=6, _0700=7, _0800=8, _0900=9, _1000=10, _1100=11, _1200=12, _1300=13, _1400=14, _1500=15, _1600=16, _1700=17, _1800=18, _1900=19, _2000=20, _2100=21, _2200=22, _2300=23,};
input SessionHour startTime = Inactive;     // Start Time
input SessionHour endTime = Inactive;       // 

input group "Data Analysis"
input ENUM_TIMEFRAMES periodHigher = PERIOD_H4;
input int pivotLen = 10;
input double ratio = 0.50;


// ---
int numBars = 0;
// ---
MqlRates rates[];
MqlRates ratesHigher[];
double ph[10];
double pl[10];

int pivotHistory = 10;
int histBars = 99;

int handleRSI;
double bufferRSI[];

int handleMA;
double bufferMA[];

// Trade
CTrade trade;
CPositionInfo pos;
COrderInfo ord;


void initializeArray(double &arr[], int len)
{
    for (int i = 0; i < len; i++)
    {
        arr[i] = 0.0;
    }
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

void updatePivot()
{
    double pivotH = pivotHigh(rates, pivotLen);
    if (pivotH)
    {
        updateSeries(ph, pivotH);
    }
    
    double pivotL = pivotLow(rates, pivotLen);
    if (pivotL)
    {
        updateSeries(pl, pivotL);
    }
}

double pivotHigh(MqlRates &rates[], int ind)
{
    for (int i = 1; i < pivotLen; i++)
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
    for (int i = 1; i < pivotLen; i++)
    {
        if (rates[ind].low >= rates[ind+i].low || rates[ind].low >= rates[ind-1].low)
        {
            return 0.0;
        }
    }
    
    return rates[ind].low;
}


bool isUpTrend()
{
    if (ph[1] < ph[0] && pl[1] < pl[0])
    {
        return true;
    }
    return false;
}

bool isDownTrend()
{
    if (ph[1] < ph[0] && pl[1] < pl[0])
    {
        return true;
    }
    return false;
}

bool isBullish(MqlRates &rates[])
{
    if (rates[0].close > rates[0].open)
    {
            return true;
    }
    return false;
    
}

/*
Return 1 for uptrend, -1 for downtrend and 0 otherwise.
*/
int trendHigher()
{
    if (ratesHigher[0].close > bufferMA[0] && ratesHigher[1].close > bufferMA[1])
    {
        return 1;
    }
    else if (ratesHigher[0].close < bufferMA[0] && ratesHigher[1].close < bufferMA[1])
    {
        return -1;
    }
    else return false;
}

bool BuyCondition()
{
    double price = rates[0].close;
    double diff = MathAbs(ph[0] - pl[0]);
    double threshold = pl[0] + ratio * diff;
    if (isUpTrend() && price < threshold 
    // && bufferRSI[0] > 50 
    && isBullish(ratesHigher) && trendHigher() == 1)
    {
        return true;
    }
    return false;
}

bool SellCondition()
{
    double price = rates[0].close;
    double diff = MathAbs(ph[0] - pl[0]);
    double threshold = ph[0] - ratio * diff;
    if (isDownTrend() && price > threshold 
    // && bufferRSI[0] < 50 
    && !isBullish(ratesHigher) && trendHigher() == -1)
    {
        return true;
    }
    return false;
}

int OnInit(void)
{
    Print(Symbol(), PERIOD_CURRENT);
    ArraySetAsSeries(rates, true);
    ArraySetAsSeries(ratesHigher, true);
    ArraySetAsSeries(ph, true);
    ArraySetAsSeries(pl, true);

    handleRSI = iRSI(Symbol(), Period(), 14, PRICE_CLOSE);
    ArraySetAsSeries(bufferRSI, true);
    handleMA = iMA(Symbol(), periodHigher, 50, 0, MODE_SMA, PRICE_CLOSE);
    ArraySetAsSeries(bufferMA, true);


    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    
}

void OnTick(void)
{
    TrailStop();
    
    if (!newBar()) return;

    CopyRates(Symbol(), PERIOD_CURRENT, 1, histBars, rates);
    CopyRates(Symbol(), periodHigher, 1, histBars, ratesHigher);
    CopyBuffer(handleRSI, MAIN_LINE, 1, histBars, bufferRSI);
    CopyBuffer(handleMA, MAIN_LINE, 1, histBars, bufferMA);

    updatePivot();
    Comment(ph[0], "\n", pl[0], "\n", ph[1], "\n", pl[1]);

    MqlDateTime time;
    TimeToStruct(TimeGMT(), time);
    int hourNow = time.hour;
    if (hourNow < startTime)    return;
    if (hourNow >= endTime && endTime != Inactive)  return;
    
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


void Buy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl = pl[0];
    double tp = ph[0];
    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(MathAbs(ask - sl));
    if(!trade.Buy(lots, _Symbol, ask, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
}

void Sell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = ph[0];
    double tp = pl[0];
    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(MathAbs(bid - sl));

    if(!trade.Sell(lots, _Symbol, bid, sl, tp, StringFormat("SL=%d, TP=%d", sl, tp)))
    {
        Print("Failed to Sell! Error: ", GetLastError());
    }
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

void TrailStop()
{
    double sl = 0;
    double tp = 0;

    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    for (int i = PositionsTotal()-1; i >= 0; i--)
    {
        // Select Position
        if (!pos.SelectByIndex(i))  continue;
        ulong ticket = pos.Ticket();

        if (pos.PositionType() == POSITION_TYPE_BUY && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC)
        {
            if (MathAbs(bid - pos.PriceOpen()) > tslPoints * _Point) // If TSL is triggered
            {
                tp = pos.TakeProfit();
                sl = bid - (tslPoints * _Point);
                if (sl > pos.StopLoss() && sl != 0) trade.PositionModify(ticket, sl, tp);
            }
        }
        else if (pos.PositionType() == POSITION_TYPE_SELL && pos.Symbol() == Symbol() && pos.Magic() == EA_MAGIC)
        {
            if (MathAbs(ask - pos.PriceOpen()) > tslPoints * _Point) // If TSL is triggered
            {
                tp = pos.TakeProfit();
                sl = ask + (tslPoints * _Point);
                if (sl < pos.StopLoss() && sl != 0) trade.PositionModify(ticket, sl, tp);
            }
        }
    }    
}