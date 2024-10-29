
#property  copyright "Ali Mahani"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Date Analysis";
input int lenBack = 5;      // Bars to look around for Pivot Detection
input double w2bRatio = 2.0;       // Minimum ratio of wick to body for RB detection
input int minWickPoints = 50;       // Minimum size of wick in Points (10 pts = 1 pip)

input group "Trade Management";
input double riskPercent = 2.0; // Risk as a % of trading capital
input double profitFactor = 2.0;
input ulong EA_MAGIC = 3948302840; // EA Magic ID
// input int tpPoints = 200;               // Take Profit in Points (10 points = 1 pip)
input int slPoints = 200;        // Stop Loss in Points (10 points = 1 pip)
input int tslTriggerPoints = 15; // Points in profit before trailing SL is activated (10 points = 1 pip)
input int tslPoints = 10;        // Trailing SL (10 points = 1 pip)
input int expBars = 100;         // # of bars after which the orders expire
input bool trailStop = true;     // Use Trailing SL?

input group "Trade Session UTC";
input int startHour = 0;
input int startMinute = 0;
input int endHour = 6;
input int endMinute = 0;

Time startTime = {startHour, startMinute, 0};
Time endTime = {endHour, endMinute, 0};



enum ENUM_BLOCK_TYPE
{
    BLOCK_TYPE_BULLISH = 1,
    BLOCK_TYPE_BEARISH = -1,
    BLOCK_TYPE_NULL = 0
};

struct RejectionBlock
{
    double top;
    double bottom;
    ENUM_BLOCK_TYPE type;
    datetime time;
    void Reset()
    {
        top = 0;
        bottom = 0;
        type = 0;
        time = 0;
    }
};

// ----------- Global Variables --------
RejectionBlock rbBull = {0, 0, 0, 0};
RejectionBlock rbBear = {0, 0, 0, 0};

double ph = 0;
double pl = 0;
datetime phTime = 0;
datetime plTime = 0;

CTrade trade;
CPositionInfo pos;
COrderInfo ord;


int OnInit()
{
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
    if(!newBar()) return;

    
    UpdatePivots();
    FindRejectionBlock(rbBull, rbBear, w2bRatio);

    Comment(ph, "\n", pl);

    if (PositionsTotal() == 0 && TradeSession(startTime, endTime))
    {
        if (BuyCondition() && BuysTotal() == 0)
        {
            double entry = rbBull.top;
            BuyLimit(trade, entry, slPoints, profitFactor, riskPercent, expBars);
            rbBull.Reset();
        }
        if (SellCondition() && SellsTotal() == 0)
        {
            double entry = rbBear.bottom;
            SellLimit(trade, entry, slPoints, profitFactor, riskPercent, expBars);
            rbBear.Reset();
        }
    }

}

bool FindRejectionBlock(RejectionBlock &rejectBull, RejectionBlock &rejectBear, double ratio)
{
    double close = iClose(_Symbol, PERIOD_CURRENT, 1);
    double open = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double low = iLow(_Symbol, PERIOD_CURRENT, 1);

    bool candleBull = (close > open);
    double top = MathMax(close, open);
    double bottom = MathMin(close, open);

    double body = MathAbs(close - open);
    double lowWick = MathAbs(low - bottom);
    double highWick = MathAbs(high - top);
    double minSize = minWickPoints * _Point;

    if (lowWick > body * ratio && lowWick > minSize && highWick < body * ratio && highWick < minSize)
    {
        rejectBull.type = BLOCK_TYPE_BULLISH;
        rejectBull.bottom = low;
        rejectBull.top = bottom;
        rejectBull.time = iTime(_Symbol, PERIOD_CURRENT, 1);
        Alert("Found bullish rejection Block!");
        return true;
    }
    else if (lowWick < body * ratio && lowWick < minSize && highWick > body * ratio && highWick > minSize)
    {
        rejectBear.type = BLOCK_TYPE_BEARISH;
        rejectBear.top = high;
        rejectBear.bottom = top;
        rejectBear.time = iTime(_Symbol, PERIOD_CURRENT, 1);
        Alert("Found bearish rejection Block!");
        return true;
    }
    return false;
}

void UpdatePivots()
{
    double pLow = PivotLow(lenBack);
    if (pLow != 0)
    {
        pl = pLow;
        plTime = iTime(NULL, 0, lenBack);
    }

    double pHigh = PivotHigh(lenBack);
    if (pHigh != 0)
    {
        ph = pHigh;
        phTime = iTime(NULL, 0, lenBack);
    }
}

bool BuyCondition()
{
    if (ph != 0 && ph > rbBull.top && phTime > rbBull.time) return true;
    return false;
}

bool SellCondition()
{
    if (pl != 0 && pl < rbBear.bottom && plTime > rbBear.time) return true;
    return false;
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
    return sells;
}