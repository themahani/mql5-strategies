
#property copyright "Copyright 2024, Ali Mahani"
#property link "ali.a.mahani@zoho.com"

// ----------- Include ---------
#include "include/data_analysis.mqh"
#include "include/time.mqh"
#include "include/trading.mqh"

// ----------- Inputs ----------
input group "Volume Profile Params";
input ENUM_TIMEFRAMES timeframeVP = PERIOD_CURRENT;    // Calculation Timeframe for VP
input int precisionVP = 100;                           // number of VP bars
input ENUM_APPLIED_VOLUME appliedVolume = VOLUME_REAL; // applied volume
input double ratioVP = 0.25;                           // ratio of maximum VP bar length to chart width
input color gc = clrSlateGray;                         // bars color
input color pocc = clrOrange;                          // POC color
input color svlc = clrGreen;                           // start vline color
input color evlc = clrGreen;                           // end vline color

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

struct VolumeProfile
{
    double price;
    double profile;
    VolumeProfile copy()
    {
        VolumeProfile element = {price, profile};
        return element;
    }
};

VolumeProfile volumeProfile[];

int OnInit()
{
    ArraySetAsSeries(pivots, true);
    ArrayResize(pivots, historySize);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, -1, -1);
}

void OnTick(void)
{
    if (!newBar())
        return;

    if (!IsPivotHigh() && !IsPivotLow())
        return;

    if (pivots[0].type == pivots[1].type)
        return;

    if (pivots[0].value == 0 || pivots[1].value == 0)
        return;
    
    iVolumeProfile(timeframeVP, pivots[1].time, pivots[0].time, ratioVP, precisionVP, appliedVolume, volumeProfile);
    int size = ArraySize(volumeProfile);
    Comment(volumeProfile[0].price, "\n", volumeProfile[size-1].price,
            "\n", pivots[0].value, "\n", pivots[1].value);

}

void DrawLines(VolumeProfile &vp[])
{
    int size = ArraySize(vp);
    ObjectsDeleteAll(0, "price", -1, OBJ_HLINE);
    for (int i = size - 1; i > 0; i--)
    {
        if (vp[i].price == 0 || vp[i].profile == 0)
            break;
        if (vp[i-1].profile < vp[i].profile / 2.0)
        {
            datetime now = iTime(_Symbol, 0, 1);
            if (!ObjectCreate(0, "price" + IntegerToString(i), OBJ_HLINE, 0, now, vp[i].price))
            {
                Print("Failed to Draw hline: ", GetLastError());
            }
        }
    }

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

void DrawLines(double &profile[])
{
    int size = ArraySize(profile);
}

void iVolumeProfile(ENUM_TIMEFRAMES tf, datetime time_begin, datetime time_finish,
                    double ratio, int precision, ENUM_APPLIED_VOLUME av, VolumeProfile &vp[],
                    bool visualize = true)
{

    //---Number of bars in the range based on the calculation timeframe (not the current timeframe visible in the chart).
    int bars = Bars(_Symbol, tf, time_begin, time_finish);
    if (time_begin >= time_finish)
        return;

    //---Copy high-low-volume data of the calculation timeframe.
    double high_array[];
    double low_array[];
    long volume[];
    ArrayResize(high_array, bars);
    ArrayResize(low_array, bars);
    ArrayResize(volume, bars);
    if (CopyHigh(_Symbol, tf, time_begin, time_finish, high_array) == -1 ||
        CopyLow(_Symbol, tf, time_begin, time_finish, low_array) == -1 ||
        CopyRealVolume(_Symbol, tf, time_begin, time_finish, volume) == -1)
        return;
    if (av == VOLUME_TICK || volume[0] == 0)
        if (CopyTickVolume(_Symbol, tf, time_begin, time_finish, volume) == -1)
            return;
    //---Find the max-min price in the range & the height of VP bars based on the number of bars (precision input)
    double max = high_array[ArrayMaximum(high_array, 0, WHOLE_ARRAY)]; // highest price in the range
    double min = low_array[ArrayMinimum(low_array, 0, WHOLE_ARRAY)];   // lowest price in the range
    double range = (max - min) / precision;                            // height of the VP bars

    //---Create an array to store the VP data
    double profile[];
    ArrayResize(profile, precision);
    ArrayResize(vp, precision);
    //---Calculate VP array
    //---Loop through all price bars in the range and cumulatively assign their volume to VPs.
    for (int i = 0; i < bars && !IsStopped(); i++)
    {
        int Floor = (int)MathFloor((low_array[i] - min) / range); // the first level of VP just below the low of the ith candle
        int Ceil = (int)MathFloor((high_array[i] - min) / range); // the first level ov VP just above the high of the ith candle
        double body = high_array[i] - low_array[i];               // the height of ith candle
        //---When the lower part of the candle falls between two levels of VPs, we have to consider just that part, not the entire level height
        double tail = min + (Floor + 1) * range - low_array[i];
        //---When the upper part of the candle falls between two levels of VPs, we have to consider just that part, not the entire level height
        double wick = high_array[i] - (min + (Ceil)*range);
        //---set the values of VPs to zero in the first step of the loop, because we are accumulating volumes to find VPs and they should be zero in the begining
        if (i == 0)
            for (int n = 0; n < precision; n++)
                profile[n] = 0.0;
        for (int n = 0; n < precision && !IsStopped(); n++)
        {
            if (n < Floor || n > Ceil) // when no part of the candle is in the nth level of VP, continue
                continue;
            if (Ceil - Floor == 0) // when all of the candle is in the nth level of VP, add whole volume of the candle to that level of VP
                profile[n] += (double)volume[i];
            else if (n == Floor) // when the lower part of the candle falls in the nth level of VP, but it doesn't cover the whole height of the nth level
                profile[n] += (tail / body) * volume[i];
            else if (n == Ceil) // when the upper part of the candle falls in the nth level of VP, but it doesn't cover the entire height of the nth level
                profile[n] += (wick / body) * volume[i];
            else
                profile[n] += (range / body) * volume[i]; // when a part of the candle covers the entire height of the nth level
        }
    }
    for (int i = 0; i < precision; i++)
    {
        double price = min + range * i;
        VolumeProfile element = {price, profile[i]};
        vp[i] = element.copy();
    }

    //--- Point of Control is the maximum VP found in the volume profile array
    double POC = profile[ArrayMaximum(profile, 0, WHOLE_ARRAY)];
    //---Define the maximum length of VP bars (which is for POC) by considering the width of the chart and ratio input
    int BL = (int)(ratio * ChartGetInteger(0, CHART_WIDTH_IN_PIXELS));
    //---Find an appropriate height for VP bars by considering the chart height and the number of VP bars
    int ch = int(ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS) * ((max - min) / (ChartGetDouble(0, CHART_PRICE_MAX) - ChartGetDouble(0, CHART_PRICE_MIN))) / precision);

    if (POC == 0.0)
        return;
    
    if (!visualize)
        return;
    //---delete all existing bars before drawing new ones
    ObjectsDeleteAll(0, "VP prfl ", -1, -1);

    //---Draw VP bars one by one from the lowest price in the range to the highest
    for (int n = 0; n < precision; n++)
    {
        //--- The length of each VP bar is calculated by its ratio to POC
        int xd = (int)((profile[n] / POC) * BL);
        int x_start = 0;
        int y_start = 0;
        //--- Finding the xy position for drawing VPs according to the end vline and min price in the range
        ChartTimePriceToXY(0, 0, time_finish, min + (n + 1) * range, x_start, y_start);
        //--- In case the end of VPs go beyond the visible chart
        if (x_start + xd >= ChartGetInteger(0, CHART_WIDTH_IN_PIXELS))
            xd = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) - x_start;
        //---Draw rectangle lable to display VP bars, using RectLabelCreate function
        RectLabelCreate("VP prfl " + IntegerToString(n), x_start, y_start, xd, ch, gc);
        //---Change the color of POC
        if (profile[n] == POC)
        {
            ObjectSetInteger(0, "VP prfl " + IntegerToString(n), OBJPROP_COLOR, pocc);
            ObjectSetInteger(0, "VP prfl " + IntegerToString(n), OBJPROP_BGCOLOR, pocc);
        }
    }
    //---
    ChartRedraw(0L);
}

bool RectLabelCreate(const string name = "RectLabel",                   // label name
                     const int x = 0,                                   // X coordinate
                     const int y = 0,                                   // Y coordinate
                     const int width = 50,                              // width
                     const int height = 1,                              // height
                     const color clr = clrRed,                          // flat border color (Flat)
                     const color back_clr = clrNONE,                    // background color
                     const ENUM_BORDER_TYPE border = BORDER_FLAT,       // border type
                     const ENUM_BASE_CORNER corner = CORNER_LEFT_UPPER, // chart corner for anchoring
                     const ENUM_LINE_STYLE style = STYLE_SOLID,         // flat border style
                     const int line_width = 1,                          // flat border width
                     const long chart_ID = 0,                           // chart's ID
                     const int sub_window = 0,                          // subwindow index
                     const bool back = true,                            // in the background
                     const bool selection = false,                      // highlight to move
                     const bool hidden = true,                          // hidden in the object list
                     const long z_order = 0)                            // priority for mouse click
{
    //--- reset the error value
    ResetLastError();
    //--- create a rectangle label
    if (!ObjectCreate(chart_ID, name, OBJ_RECTANGLE_LABEL, sub_window, 0, 0))
    {
        Print(__FUNCTION__,
              ": failed to create a rectangle label! Error code = ", GetLastError());
        return (false);
    }
    //--- set label coordinates
    ObjectSetInteger(chart_ID, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(chart_ID, name, OBJPROP_YDISTANCE, y);
    //--- set label size
    ObjectSetInteger(chart_ID, name, OBJPROP_XSIZE, width);
    ObjectSetInteger(chart_ID, name, OBJPROP_YSIZE, height);
    //--- set background color
    ObjectSetInteger(chart_ID, name, OBJPROP_BGCOLOR, back_clr);
    //--- set border type
    ObjectSetInteger(chart_ID, name, OBJPROP_BORDER_TYPE, border);
    //--- set the chart's corner, relative to which point coordinates are defined
    ObjectSetInteger(chart_ID, name, OBJPROP_CORNER, corner);
    //--- set flat border color (in Flat mode)
    ObjectSetInteger(chart_ID, name, OBJPROP_COLOR, clr);
    //--- set flat border line style
    ObjectSetInteger(chart_ID, name, OBJPROP_STYLE, style);
    //--- set flat border width
    ObjectSetInteger(chart_ID, name, OBJPROP_WIDTH, line_width);
    //--- display in the foreground (false) or background (true)
    ObjectSetInteger(chart_ID, name, OBJPROP_BACK, back);
    //--- enable (true) or disable (false) the mode of moving the label by mouse
    ObjectSetInteger(chart_ID, name, OBJPROP_SELECTABLE, selection);
    ObjectSetInteger(chart_ID, name, OBJPROP_SELECTED, selection);
    //--- hide (true) or display (false) graphical object name in the object list
    ObjectSetInteger(chart_ID, name, OBJPROP_HIDDEN, hidden);
    //--- set the priority for receiving the event of a mouse click in the chart
    ObjectSetInteger(chart_ID, name, OBJPROP_ZORDER, z_order);
    //--- successful execution
    return (true);
}