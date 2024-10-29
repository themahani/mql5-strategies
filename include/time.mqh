
struct Time
{
    int hour;
    int min;
    int sec;
    void getTime(MqlDateTime &moment)
    {
        hour = moment.hour;
        min = moment.min;
        sec = moment.sec;
    }
};

bool TradeSession(Time &start, Time &end)
{
    MqlDateTime tm = {};
    datetime current = TimeGMT(tm);
    
    int startSec = start.hour * 3600 + start.min * 60 + start.sec;
    int endSec = end.hour * 3600 + end.min * 60 + end.sec;
    int currentSec = tm.hour * 3600 + tm.min * 60 + tm.sec;

    if (startSec > endSec)
    {
        return (currentSec >= startSec || currentSec <= endSec);
    }
    else
        return (currentSec >= startSec && currentSec <= endSec);
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