#property copyright "Ali Mahani"
#property link      "https://x.com/themahani"
#property version   "1.0"


#include <Trade/Trade.mqh>

CTrade trade;
CPositionInfo pos;


// -------- ENUMs ---------
enum TradingStyle { StyleBreakUp = 1, StyleBreakDown = -1 };
enum LotType {LotFixed = 0, LotAsRiskPercent = 1};
enum TPType {TPFixed = 0, TPByProfitFactor = 1};
enum ENUM_TREND_BREAK {TREND_BREAK_NONE, TREND_BREAK_UP, TREND_BREAK_DOWN};

// ---------
int openBuys = 0;
int openSells = 0;
bool lineValid = true;


input group "Trading Style"
input string lineName = "Trendline";            // Name of the line
input TradingStyle tradeChoice = StyleBreakDown;    // Trade the break up or down?
input int lineValidPoints = 500;                    // Points diff to invalidate line
input color invalidColor = clrRed;                // Color of invalid line
input ENUM_LINE_STYLE invalidLineStyle = STYLE_DASHDOT;  // Style of invalid line

input group "Trade Management"
input LotType lotTypeChoice = LotFixed;             // Type of trade lot calculation
input double fixedLot = 0.01;                       // If chose LotFixed, enter lot size
input double riskPercent = 1.0;                     // If chose Lot as risk, enter risk %
input int slPoints = 300;                           // SL in points (10 pts = 1 pip)
input TPType tpTypeChoice = TPFixed;                // TP calculation method
input double tpPoints = 300;                        // If fixed TP, enter TP in points
input double rrRatio = 2;                           // TP as Risk Reward Ratio
input ulong EA_MAGIC = 39502903;                    // EA Magic ID


int OnInit(void)
{
    trade.SetExpertMagicNumber(EA_MAGIC);
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    ChartSetInteger(0, CHART_SHOW_VOLUMES, true);
    CreateLine();


    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{

}


void OnTick(void)
{
    int index = 0;
    OpenPositions();


    if(!newBar())   return;

    double lots = fixedLot, entry = 0, sl = 0, tp = 0;

    ENUM_TREND_BREAK brk = GetBreak(index);
    switch (brk)
    {
    case TREND_BREAK_NONE:
        break;
    case TREND_BREAK_UP:
    {
        if (tradeChoice != StyleBreakUp)    return;
        if (openBuys > 0)   return;
        entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        sl = GetSL(entry, brk);
        if (sl != 0 && lotTypeChoice == LotAsRiskPercent)
        {
            lots = calculateLots(MathAbs(entry - sl));
        }
        else if (sl == 0 && lotTypeChoice == LotAsRiskPercent)
        {
            Alert("SL is zero! Reverting to fixed lot size. Choosing Min Volume.");
            lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        }
        tp = GetTP(entry, MathAbs(entry - sl), brk);
        trade.Buy(lots, _Symbol, entry, sl, tp, "Trendline Break Up");
        break;
    }
    
    case TREND_BREAK_DOWN:
    {
        if (tradeChoice != StyleBreakDown)    return;
        if (openSells > 0)   return;
        entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        sl = GetSL(entry, brk);
        if (sl != 0 && lotTypeChoice == LotAsRiskPercent)
        {
            lots = calculateLots(MathAbs(entry - sl));
        }
        else if (sl == 0 && lotTypeChoice == LotAsRiskPercent)
        {
            Alert("SL is zero! Reverting to fixed lot size. Choosing Min Volume.");
            lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        }
        tp = GetTP(entry, MathAbs(entry - sl), brk);
        trade.Sell(lots, _Symbol, entry, sl, tp, "Trendline Break Down");
        break;
    }
    }

   
}



ENUM_TREND_BREAK GetBreak(int index)
{
    if(ObjectFind(0, lineName) < 0) return TREND_BREAK_NONE;

    double prevOpen =  iOpen(_Symbol, PERIOD_CURRENT, index+1);
    double prevClose =  iClose(_Symbol, PERIOD_CURRENT, index+1);
    double close =  iClose(_Symbol, PERIOD_CURRENT, index);

    datetime prevTime = iTime(_Symbol, PERIOD_CURRENT, index+1);
    datetime time = iTime(_Symbol, PERIOD_CURRENT, index);

    double prevValue = ObjectGetValueByTime(0, lineName, prevTime);
    double value = ObjectGetValueByTime(0, lineName, time);

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // Condition to make the lines invalid
    if (tradeChoice == StyleBreakUp && ask < value - lineValidPoints * _Point && lineValid) lineValid = false;  
    if (tradeChoice == StyleBreakDown && bid > value + lineValidPoints * _Point && lineValid) lineValid = false;  

    if (!lineValid)
    {
        ObjectSetInteger(0, lineName, OBJPROP_COLOR, invalidColor);
        ObjectSetInteger(0, lineName, OBJPROP_STYLE, invalidLineStyle);
    }


    if (prevValue == 0 || value == 0)   return TREND_BREAK_NONE;
    
    if ((prevOpen < prevValue && prevClose < prevValue)
        && close > value && lineValid)  return TREND_BREAK_UP;
    
    if ((prevOpen > prevValue && prevClose > prevValue)
        && close < value && lineValid)  return TREND_BREAK_DOWN;
    
    return TREND_BREAK_NONE;
}

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

void OpenPositions()
{
    openBuys = 0;
    openSells = 0;
    for (int i = PositionsTotal()-1; i >= 0; i--)
    {
        if (pos.Symbol() == _Symbol && pos.Magic() == EA_MAGIC)
        {
            if (pos.PositionType() == POSITION_TYPE_BUY) openBuys++;
            if (pos.PositionType() == POSITION_TYPE_SELL) openSells++;
        }
    }
}

double GetSL(double entry, ENUM_TREND_BREAK brk)
{
    double sl = 0;

    if(slPoints <= 0)   return sl;
    if (brk == TREND_BREAK_UP)  sl = entry - slPoints * _Point;
    if (brk == TREND_BREAK_DOWN)  sl = entry + slPoints * _Point;

    return sl;
}

double GetTP(double entry, double slDiff, ENUM_TREND_BREAK brk)
{
    double tp = 0;

    if (tpPoints == 0 && tpTypeChoice == TPFixed)   return tp;
    
    if (brk == TREND_BREAK_UP)
    {
        switch (tpTypeChoice)
        {
        case TPFixed:
            tp = entry + tpPoints * _Point;
        case TPByProfitFactor:
            tp = entry + slDiff * rrRatio;
        }
    }

    if (brk == TREND_BREAK_DOWN)
    {
        switch (tpTypeChoice)
        {
        case TPFixed:
            tp = entry - tpPoints * _Point;
        case TPByProfitFactor:
            tp = entry - slDiff * rrRatio;
        }
    }

    return tp;
}

void CreateLine()
{
    datetime lineStart = iTime(_Symbol, PERIOD_CURRENT, 10);
    datetime lineEnd = iTime(_Symbol, PERIOD_CURRENT, 10) + 5000 * PeriodSeconds(PERIOD_CURRENT);
    ObjectCreate(0, lineName, OBJ_TREND, 0, lineStart, SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 500 * _Point,
                    lineEnd,SymbolInfoDouble(_Symbol, SYMBOL_ASK) + 500);
}