
//---
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>
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

input group "Indicators"
input int maPeriodLow = 21;                 // Lower Moving Average Period
input int maPeriodHigh = 50;                // Higher Moving Average Period
input ENUM_MA_METHOD maMode = MODE_SMA;     // The Moving Average Method
input int periodRSI = 14;                   // Period for RSI
input double lowRSI = 25.0;                 // Low RSI indicating over sold
input double highRSI = 75.0;                 // High RSI indicating over bought


// ----------------------------
int nBars = 5;
int expBars = 100;  // # of bars after which the orders expire
int orderDistPoints = 100;  // ?

// Trade
CTrade trade;
CPositionInfo pos;
COrderInfo ord;

// Indicators
int handleMALow;
double bufferMALow[];
int handleMAHigh;
double bufferMAHigh[];
int handleRSI;
double bufferRSI[];


int OnInit(void)
{
    // Chart Properties
    ChartSetInteger(0, CHART_SHOW_GRID, false);

    handleMALow = iMA(Symbol(), timeframe, maPeriodLow, 0, maMode, PRICE_CLOSE);
    ArraySetAsSeries(bufferMALow, true);
    handleMAHigh = iMA(Symbol(), timeframe, maPeriodHigh, 0, maMode, PRICE_CLOSE);
    ArraySetAsSeries(bufferMAHigh, true);
    handleRSI = iRSI(Symbol(), timeframe, periodRSI, PRICE_CLOSE);
    ArraySetAsSeries(bufferRSI, true);

    trade.SetExpertMagicNumber(EA_MAGIC);


    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    CloseAllOrders();
}


void OnTick(void)
{

    TrailStop();

    if (!newBar())  return;

    CopyBuffer(handleMALow, MAIN_LINE, 1, expBars, bufferMALow);
    CopyBuffer(handleMAHigh, MAIN_LINE, 1, expBars, bufferMAHigh);
    CopyBuffer(handleRSI, MAIN_LINE, 1, expBars, bufferRSI);
    
    MqlDateTime time;
    TimeToStruct(TimeGMT(), time);
    int hourNow = time.hour;
    if (hourNow < startTime)
    {
        CloseAllOrders();
        return;
    }
    if (hourNow >= endTime && endTime != Inactive)
    {
        CloseAllOrders();
        return;
    }
    
    if (BuysTotal() == 0 
    && BuyCondition()
    )
    {
        double high = pivotHigh();
        if (high > 0)
        {
            Buy(high);
        }
    }
    if (SellsTotal() == 0
     && SellCondition()
     )
    {
        double low = pivotLow();
        if (low > 0)
        {
            Sell(low);
        }
    }
}


double pivotHigh()
{
    for (int i = 0; i < 200; i++)
    {
        double hh = 0;
        double high = iHigh(_Symbol, timeframe, i);
        if (i > nBars && iHighest(_Symbol, timeframe, MODE_HIGH, 2*nBars+1, i-nBars) == i)
        {
            if (high > hh)
            {
                return high;
            }
        }
        hh = MathMax(hh, high);
    }
    return -1;
}


double pivotLow()
{
    for (int i = 0; i < 200; i++)
    {
        double ll = DBL_MAX;
        double low = iLow(_Symbol, timeframe, i);
        if (i > nBars && iLowest(_Symbol, timeframe, MODE_LOW, 2*nBars+1, i-nBars) == i)
        {
            if (low < ll)
            {
                return low;
            }
        }
        ll = MathMin(ll, low);
    }
    return -1;
}

bool newBar()
{
    static datetime previousTime = 0;
    datetime newTime = iTime(_Symbol, timeframe, 0);

    if (previousTime != newTime)
    {
        previousTime = newTime;
        return true;
    }
    return false;
}




// -------- Trade Functions -------------

bool BuyCondition()
{
    // return bufferMALow[0] > bufferMAHigh[0];
    return bufferRSI[0] < highRSI; 
}

bool SellCondition()
{
    // return bufferMALow[0] < bufferMAHigh[0];
    return bufferRSI[0] > lowRSI;
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

void Buy(double entry)
{
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    if (ask > entry - orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double tp = entry + tpPoints * _Point;
    double sl = entry - slPoints * _Point;

    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(entry - sl);

    datetime expiration = iTime(_Symbol, timeframe, 0) + expBars * PeriodSeconds(timeframe);

    trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, tradeComment);
}

void Sell(double entry)
{
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    if (bid < entry + orderDistPoints * Point())   return;  // Don't send order if entry is less than orderDistPoints away.

    double tp = entry - tpPoints * _Point;
    double sl = entry + slPoints * _Point;

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