
#property  copyright "Copyright 2024, Ali Mahani"
#property link       "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Pivot High/Low";
input int pivotLen = 7; // Bars to look around for Pivots




// ------------ Global ----------
enum ENUM_PIVOT_TYPE
{
    PIVOT_HIGH = 1,
    PIVOT_LOW = -1,
    PIVOT_NULL = 0
};

struct Pivot
{
    double value;
    datetime time;
    ENUM_PIVOT_TYPE type;
    Pivot copy()
    {
        Pivot element = {value, time, type};
        return element;
    }
};

Pivot pivots[];
int historySize = 50;



// ----------- Data -----------
MqlRates rates[];


int OnInit()
{
    if (Period() != PERIOD_M5)
    {
        Alert("Current Timeframe should be M5");
        return INIT_FAILED;
    }

    ArraySetAsSeries(pivots, true);
    ArrayResize(pivots, historySize);


    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{

}

void OnTick(void)
{
    if (!newBar())
        return;

    IsPivotHigh();
    IsPivotLow();

}


void UpdateSeriesPivot(Pivot &arr[], const Pivot &newValue)
{
    int size = ArraySize(arr);
    for (int i = size - 1; i > 0; i--)
    {
        arr[i] = arr[i-1];
    }
    arr[0] = newValue;
}

bool IsPivotHigh()
{
    double ph = PivotHigh(pivotLen);
    if (ph)
    {
        datetime now = iTime(_Symbol, 0, pivotLen + 1);
        Pivot p = {ph, now, PIVOT_HIGH};
        if (pivots[0].type == PIVOT_HIGH)
        {
            pivots[0] = p.copy();            
        }
        else
        {
            UpdateSeriesPivot(pivots, p.copy());
        }
        return true;
    }
    return false;
}

bool IsPivotLow()
{
    double pl = PivotLow(pivotLen);
    if (pl)
    {
        datetime time = iTime(_Symbol, 0, pivotLen + 1);
        Pivot p = {pl, time, PIVOT_LOW};
        if (pivots[0].type == PIVOT_LOW)
        {
            pivots[0] = p.copy();
        }
        else
        {
            UpdateSeriesPivot(pivots, p.copy());
        }
        return true;
    }
    return false;
}

