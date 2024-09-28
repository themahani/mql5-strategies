/*
All the data analysis utilities in one place.
*/

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

/*
Update the values and shift to left.
Since the data is set as timeseries, the newest bar is index zero,
so we use that for our new value and shift the previous data to the left.

[in] FVG arr:   Series to update.
[in] FVG newValue:  New value to put at the start of the Series
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

/*
Check if the given candle is bullish

[in] MqlRates candle:   Candle to check
*/
bool isBullish(MqlRates &candle)
{
    if (candle.close > candle.open)
    {
        return true;
    }
    return false;
}


bool bigCandle(MqlRates &candle, double b2wRatio)
{
    double wick = MathAbs(candle.high - candle.low);
    double body = MathAbs(candle.open - candle.close);
    if (body / wick > b2wRatio)
    {
        return true;
    }
    return false;
}

/*
MqlRates candles [in]: The rates for at least the previous 3 candles.
*/
bool bullishFVG(MqlRates &candles[], FVG &fvg, double fvg2bRatio, double b2wRatio)
{

    double top = candles[0].low;
    double bottom = candles[2].high;
    double fvgSize = top - bottom;
    double body = MathAbs(candles[1].close - candles[1].open);

    if (isBullish(candles[1]) && bigCandle(candles[1], b2wRatio) && fvgSize > body * fvg2bRatio)
    {
        fvg.top = top;
        fvg.bottom = bottom;
        fvg.high = candles[1].high;
        fvg.low = candles[1].low;
        fvg.time = candles[1].time;
        fvg.type = FVG_BULLISH;
        return true;
    }
    return false;
}

bool bearishFVG(MqlRates &candles[], FVG &fvg, double fvg2bRatio, double b2wRatio)
{
    double top = candles[2].low;
    double bottom = candles[0].high;
    double fvgSize = top - bottom;
    double body = MathAbs(candles[1].close - candles[1].open);

    if (!isBullish(candles[1]) && bigCandle(candles[1], b2wRatio) && fvgSize > body * fvg2bRatio)
    {
        fvg.top = top;
        fvg.bottom = bottom;
        fvg.high = candles[1].high;
        fvg.low = candles[1].low;
        fvg.time = candles[1].time;
        fvg.type = FVG_BEARISH;
    }
    return false;
}

// Function to draw a green box on the chart
Box DrawBox(FVG &fvg, int nBars)
{
    double clr = clrGreen;
    if (fvg.type == FVG_BEARISH)    clr = clrRed;

    datetime time1 = fvg.time;
    datetime time2 = time1 + nBars * PeriodSeconds(Period());
    string name = TimeToString(time1);
    Box newBox = {time1, time2, name};

    // Create the rectangle object
    if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, fvg.bottom, time2, fvg.top))
    {
        Print("Error creating rectangle: ", GetLastError());
        newBox.name = NULL;
        return newBox;
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
    return newBox;
}

