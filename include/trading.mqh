
#include <Trade/AccountInfo.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/Trade.mqh>

double calculateLots(double slPoints, double riskPercent)
{
    double risk = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * riskPercent / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double volumeLimit = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_LIMIT);


    double moneyPerLotstep = (slPoints / tickSize) * tickValue * lotstep;
    double lots = MathFloor(risk * moneyPerLotstep) * lotstep;
    // if (volumeLimit != 0)   lots = MathMin(lots, volumeLimit);
    if (maxVolume != 0)     lots = MathMin(lots, maxVolume);
    if (minVolume != 0)     lots = MathMax(lots, minVolume);
    // lots = NormalizeDouble(lots, 2);

    return lots;
}

void BuyLimit(CTrade &trade, double entry, int slPoints, double profitFactor, double riskPercent, int expBars)
{
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

    double slDiff = slPoints * _Point;
    double sl = entry - slDiff;
    double tp = entry + slDiff * profitFactor;

    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(slDiff, riskPercent);

    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);
    trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
}

void SellLimit(CTrade &trade, double entry, int slPoints, double profitFactor, double riskPercent, int expBars)
{
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    double slDiff = slPoints * _Point;
    double sl = entry + slDiff;
    double tp = entry - slDiff * profitFactor;

    double lots = 0.01;
    if (riskPercent > 0)    lots = calculateLots(slDiff, riskPercent);

    datetime expiration = iTime(_Symbol, PERIOD_CURRENT, 0) + expBars * PeriodSeconds(PERIOD_CURRENT);
    trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration);
}

void TrailStop(CPositionInfo &pos, CTrade &trade, const ulong EA_MAGIC, int tslTriggerPoints, int tslPoints)
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