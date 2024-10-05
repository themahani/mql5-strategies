
#property copyright "Copyright 2024, Ali Mahani"
#property link      "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Indicator Parameters";
input int periodRSI = 14;               // RSI period
input double lowRSI = 30;               // RSI low threshold
input double highRSI = 70;              // RSI high threshold

input int periodBB = 30;                // BB period
input double stdBB = 2.0;                    // BB STD
input double minWidthBB = 0.0015;       // BB Minimum width

input int periodATR = 14;               // ATR period

input group "Trade Management";
input double slCoeff = 1.5;                   // SL weight from ATR
input double tpCoeff = 2;                     // TP weight from ATR
input double riskPercent = 1.0;               // Risk % balance per trade


// ------------ Indicators ----------
int handleRSI;
double bufferRSI[];

int handleBB;
double bufferLowerBB[];
double bufferUpperBB[];
double bufferBaseBB[];

int handleATR;
double bufferATR[];

// --------- Rates ----------
MqlRates rates[];


// -------- Trade ----------
CTrade trade;
CPositionInfo pos;
COrderInfo ord;


int OnInit()
{
    ArraySetAsSeries(bufferRSI, true);
    ArraySetAsSeries(bufferLowerBB, true);
    ArraySetAsSeries(bufferUpperBB, true);
    ArraySetAsSeries(bufferBaseBB, true);
    ArraySetAsSeries(bufferATR, true);
    ArraySetAsSeries(rates, true);

    handleRSI = iRSI(_Symbol, PERIOD_CURRENT, periodRSI, PRICE_CLOSE);
    handleBB = iBands(_Symbol, PERIOD_CURRENT, periodBB, 0, stdBB, PRICE_CLOSE);
    handleATR = iATR(_Symbol, PERIOD_CURRENT, periodATR);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{

}

void OnTick(void)
{
    if(!newBar())
        return;
    
    CopyBuffer(handleRSI, MAIN_LINE, 1, 20, bufferRSI);
    CopyBuffer(handleBB, BASE_LINE, 1, 20, bufferBaseBB);
    CopyBuffer(handleRSI, LOWER_BAND, 1, 20, bufferLowerBB);
    CopyBuffer(handleRSI, UPPER_BAND, 1, 20, bufferUpperBB);
    CopyBuffer(handleATR, MAIN_LINE, 1, 20, bufferATR);
    CopyRates(_Symbol, PERIOD_CURRENT, 1, 20, rates);

    if (PositionsTotal() == 0)
    {
        if (BuyCondition())
            Buy();
        if (SellCondition())
            Sell();
    }
}


double BBWidth(int i)
{
    return (bufferUpperBB[i] - bufferLowerBB[i]) / bufferBaseBB[i];
}

bool BuyCondition()
{
    bool prevCloseBB = (rates[1].close < bufferLowerBB[1]);
    bool prevLowRSI = (bufferRSI[1] < lowRSI);
    bool closeAboveHigh = (rates[0].close > rates[1].high);
    bool highVolatility = (BBWidth(0) > minWidthBB);

    if (prevCloseBB 
    // && prevLowRSI 
    && closeAboveHigh && highVolatility)
        return true;
    
    return false;
}

bool SellCondition()
{
    bool prevCloseBB = (rates[1].close > bufferUpperBB[1]);
    bool prevHighRSI = (bufferRSI[1] > highRSI);
    bool closeBelowLow = (rates[0].close < rates[1].low);
    bool highVolatility = (BBWidth(0) > minWidthBB);

    if (prevCloseBB 
    // && prevHighRSI 
    && closeBelowLow && highVolatility)
        return true;
    
    return false;
}

void Buy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double slDiff = slCoeff * bufferATR[0];
    double tp = ask + tpCoeff * bufferATR[0];
    double lots = calculateLots(slDiff, riskPercent);
    double sl = ask - slDiff;

    trade.Buy(lots, _Symbol, ask, sl, tp, "BB RSI Strategy -- Buy");
}

void Sell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slDiff = slCoeff * bufferATR[0];
    double tp = bid - tpCoeff * bufferATR[0];
    double lots = calculateLots(slDiff, riskPercent);
    double sl = bid + slDiff;

    trade.Sell(lots, _Symbol, bid, sl, tp, "BB RSI Strategy -- Sell");
}