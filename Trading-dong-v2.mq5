//+------------------------------------------------------------------+
//|                                                   Trading-dong.mq5|
//|                               Pivot, S1, R1, Previous Day High/Low|
//|                                                    SnD Integration|
//+------------------------------------------------------------------+
#property copyright "RHN-RTA-WAM"
#property version   "1.2"

#include <Trade\Trade.mqh>

CTrade trade;
CPositionInfo pos;
COrderInfo ord;


input group "=== Common Trading Inputs ==="
input ENUM_TIMEFRAMES      Timeframe = PERIOD_CURRENT;         // Timeframe
input int                  BackLimit = 1000;                   // Back Limit
input int                  MagicNumber = 2345; //Magic Number
input int                  ATRPeriod = 7; // ATR period for volatility calculation

input group "=== Money Management Inputs"
enum LOT_MODE_ENUM{
   LOT_MODE_FIXED, //fixed lots
   LOT_MODE_MONEY, //lots based on money
   LOT_MODE_PCT_ACCOUNT //lots based on % of account
   
};
input LOT_MODE_ENUM        InpLotMode = LOT_MODE_FIXED; // lot mode
input double               InpLots = 0.01; // lots / money / percent
input int                  Slpoints = 400; //Stoploss (10 points = 1 pips, 0 = off)
input bool                 InpStopLossTrailing = false; //Trailing stop loss?
input bool                 UseSwingHighLowSL = false;  // Use swing high/low as stop-loss
input int                  SwingLookbackPeriod = 10;     // Number of bars to look back for swing highs/lows

input group "=== Supply and Demand Inputs ==="
input bool                 EnableSnD = true;  // Enable Supply and Demand Zones 
input string               zone_settings = "--- Zone Settings ---";
input bool                 zone_show_weak = false;             // Show Weak Zones
input bool                 zone_show_untested = true;          // Show Untested Zones
input bool                 zone_show_turncoat = false;         // Show Broken Zones
input double               zone_fuzzfactor = 0.6;              // Zone ATR Factor
input bool                 zone_merge = true;                  // Zone Merge
input bool                 zone_extend = true;                 // Zone Extend
input double               fractal_fast_factor = 2.5;          // Fractal Fast Factor
input double               fractal_slow_factor = 4.5;          // Fractal slow Factor

input string               drawing_settings = "--- Drawing Settings ---";
input string               string_prefix = "SRRR";             // Change prefix to add multiple indicators to chart
input bool                 zone_solid = true;                  // Fill zone with color
input int                  zone_linewidth = 1;                 // Zone border width
input ENUM_LINE_STYLE      zone_style = STYLE_SOLID;           // Zone border style
input bool                 zone_show_info = true;              // Show info labels
input int                  zone_label_shift = 10;              // Info label shift
input string               sup_name = "Dem";                   // Demand Name
input string               res_name = "Sup";                   // Supply Name
input string               test_name = "Retests";              // Retest Name
input int                  Text_size = 8;                      // Text Size
input string               Text_font = "Courier New";          // Text Font
input color                Text_color = clrBlack;              // Text Color
input color color_support_weak     = clrDarkSlateGray;         // Color for weak support zone
input color color_support_untested = clrSeaGreen;              // Color for untested support zone
input color color_support_verified = clrGreen;                 // Color for verified support zone
input color color_support_proven   = clrLimeGreen;             // Color for proven support zone
input color color_support_turncoat = clrOliveDrab;             // Color for turncoat(broken) support zone
input color color_resist_weak      = clrIndigo;                // Color for weak resistance zone
input color color_resist_untested  = clrOrchid;                // Color for untested resistance zone
input color color_resist_verified  = clrCrimson;               // Color for verified resistance zone
input color color_resist_proven    = clrRed;                   // Color for proven resistance zone
input color color_resist_turncoat  = clrDarkOrange;            // Color for broken resistance zone

input group "=== Pivot Inputs ==="
input color PivotColor = clrBlue;                              // Color for Pivot
input color SupportColor = clrGreen;                           // Color for Support
input color ResistanceColor = clrRed;                          // Color for Resistance
input color HighLowColor = clrBlack;                           // Color for Previous High/Low

ENUM_TIMEFRAMES timeframe;
double FastDnPts[],FastUpPts[];
double SlowDnPts[],SlowUpPts[];

double zone_hi[1000],zone_lo[1000];
int    zone_start[1000],zone_hits[1000],zone_type[1000],zone_strength[1000],zone_count=0;
bool   zone_turn[1000];

#define ZONE_SUPPORT 1
#define ZONE_RESIST  2

#define ZONE_WEAK      0
#define ZONE_TURNCOAT  1
#define ZONE_UNTESTED  2
#define ZONE_VERIFIED  3
#define ZONE_PROVEN    4

#define UP_POINT 1
#define DN_POINT -1

int time_offset = 0;

double ner_lo_zone_P1[];
double ner_lo_zone_P2[];
double ner_hi_zone_P1[];
double ner_hi_zone_P2[];
double ner_hi_zone_strength[];
double ner_lo_zone_strength[];
double ner_price_inside_zone[];
double Close[];   // Array for close prices
double High[];    // Array for high prices
double Low[];     // Array for low prices
int iATR_handle;
double ATR[];
int cnt = 0;
bool try_again = false;
string prefix;

string lastBullishEngulfingObj = "";
string lastBearishEngulfingObj = "";

double pivot, s1, r1, prevHigh, prevLow;
datetime openPositionDate;
bool newBarDetected = false;  // Flag to track new bar detection
datetime lastTradeTime = 0;  // Stores the time of the last trade
int cooldownPeriodSeconds = 1800;  // Cooldown period in seconds (e.g., 1800 seconds = 30 minutes)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  prefix = string_prefix + "#";
   if (Timeframe == PERIOD_CURRENT)
      timeframe = Period();
   else
      timeframe = Timeframe;
      
   // Refresh data for the new timeframe
   RefreshTimeframeData();
   
   iATR_handle = iATR(NULL, timeframe, ATRPeriod);

   if (!CheckInputs())
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(MagicNumber);

   // Set arrays as series and resize once during initialization
   ArraySetAsSeries(SlowDnPts, true);
   ArraySetAsSeries(SlowUpPts, true);
   ArraySetAsSeries(FastDnPts, true);
   ArraySetAsSeries(FastUpPts, true);
   ArraySetAsSeries(ner_hi_zone_P1, true);
   ArraySetAsSeries(ner_hi_zone_P2, true);
   ArraySetAsSeries(ner_lo_zone_P1, true);
   ArraySetAsSeries(ner_lo_zone_P2, true);
   ArraySetAsSeries(ner_hi_zone_strength, true);
   ArraySetAsSeries(ner_lo_zone_strength, true);
   ArraySetAsSeries(ner_price_inside_zone, true);
   
   // Delete all zones if SnD is disabled
   if (!EnableSnD) 
   {
      DeleteZones();  // Remove any existing SnD objects
   }
   
   // Set a timer to run heavy calculations periodically (every 10 seconds)
   EventSetTimer(10);

   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
   EventKillTimer();  // Kill the timer to stop periodic processing
   DeleteZones();
   DeletePivotLevels();
   ChartRedraw();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar only, avoid heavy calculations here
    if (NewBar())
    {
        newBarDetected = true;  // Flag to run calculations in OnTimer
    }

    // Check for engulfing patterns and manage trades
    int engulfingSignal = getEngulfing(); // 1 for Bullish Engulfing, -1 for Bearish Engulfing, 0 for no signal
    //int DominantBreakSignal = getDominantBreak();

    if (engulfingSignal == 1) // Bullish Engulfing detected
    {
        OpenBuyOrder();
    }
    else if (engulfingSignal == -1) // Bearish Engulfing detected
    {
        OpenSellOrder();
    }

    // Update stop loss for open positions if needed
    UpdateStopLoss();

    // Check if it's the end of the day to close open positions
    CheckClosePositionByDay();
}

//+------------------------------------------------------------------+
//| Timer function (Heavy Calculations)                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   if (newBarDetected)
    {
        // Perform heavy calculations here
        FastFractals();
        SlowFractals();

        if (EnableSnD)  // Check if SnD is enabled
        {
            DeleteZones();
            FindZones();
            DrawZones();
        }
        else
        {
            DeleteZones();  // Remove any existing SnD objects
        }

        DrawPivotLevels();
        showLabels();

        newBarDetected = false;  // Reset flag after processing
    }
}

//+------------------------------------------------------------------+
//| Check for new bar formation                                      |
//+------------------------------------------------------------------+
bool NewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(Symbol(), timeframe, 0);
   
   if (currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
}
 
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void FindZones()
{
    if (!EnableSnD)  // Check if SnD is enabled
        return;
    int i, j, shift, bustcount = 0, testcount = 0;
    double hival, loval;
    bool turned = false, hasturned = false;
    double temp_hi[1000], temp_lo[1000];
    int temp_start[1000], temp_hits[1000], temp_strength[1000], temp_count = 0;
    bool temp_turn[1000], temp_merge[1000];
    int merge1[1000], merge2[1000], merge_count = 0;

    // Determine the number of bars to use for calculations
    int max_bars = MathMin(Bars(Symbol(), timeframe) - 1, BackLimit);
    shift = MathMin(max_bars, ArraySize(FastUpPts) - 1);

    // Resize arrays only once
    ArrayResize(Close, shift + 1);
    ArrayResize(High, shift + 1);
    ArrayResize(Low, shift + 1);
    ArrayResize(ATR, shift + 1);

    // Retrieve price data for processing
    for (i = 0; i <= shift; i++) {
        Close[i] = iClose(Symbol(), timeframe, i);
        High[i] = iHigh(Symbol(), timeframe, i);
        Low[i] = iLow(Symbol(), timeframe, i);
    }

    // Get ATR values in a single call
    if (CopyBuffer(iATR_handle, 0, 0, shift + 1, ATR) == -1)
    {
        try_again = true;
        return;
    }
    else
    {
        try_again = false;
    }

    // Iterate through the bars and find zones
    for (int ii = shift; ii > cnt + 5; ii--)
    {
        double atr = ATR[ii];
        double fu = atr / 2 * zone_fuzzfactor;
        bool isWeak;
        bool touchOk = false;
        bool isBust = false;

        // Use cached High, Low, and Close prices
        double highPrice = High[ii];
        double lowPrice = Low[ii];
        double closePrice = Close[ii];

        // Identify potential resistance zones
        if (FastUpPts[ii] > 0.001)
        {
            isWeak = SlowUpPts[ii] <= 0.001;
            hival = highPrice;
            if (zone_extend) hival += fu;
            loval = MathMax(MathMin(closePrice, highPrice - fu), highPrice - fu * 2);
            turned = false;
            hasturned = false;
            bustcount = 0;
            testcount = 0;

            for (i = ii - 1; i >= cnt; i--)
            {
                double high_i = High[i];
                double low_i = Low[i];
                double close_i = Close[i];

                if ((turned == false && FastUpPts[i] >= loval && FastUpPts[i] <= hival) ||
                    (turned == true && FastDnPts[i] <= hival && FastDnPts[i] >= loval))
                {
                    touchOk = true;
                    for (j = i + 1; j < i + 11; j++)
                    {
                        if ((turned == false && FastUpPts[j] >= loval && FastUpPts[j] <= hival) ||
                            (turned == true && FastDnPts[j] <= hival && FastDnPts[j] >= loval))
                        {
                            touchOk = false;
                            break;
                        }
                    }
                    if (touchOk)
                    {
                        bustcount = 0;
                        testcount++;
                    }
                }

                if ((turned == false && high_i > hival) || (turned == true && low_i < loval))
                {
                    bustcount++;
                    if (bustcount > 1 || isWeak)
                    {
                        isBust = true;
                        break;
                    }
                    turned = !turned;
                    hasturned = true;
                    testcount = 0;
                }
            }
            if (!isBust)
            {
                temp_hi[temp_count] = hival;
                temp_lo[temp_count] = loval;
                temp_turn[temp_count] = hasturned;
                temp_hits[temp_count] = testcount;
                temp_start[temp_count] = ii;
                temp_merge[temp_count] = false;

                if (testcount > 3) temp_strength[temp_count] = ZONE_PROVEN;
                else if (testcount > 0) temp_strength[temp_count] = ZONE_VERIFIED;
                else if (hasturned) temp_strength[temp_count] = ZONE_TURNCOAT;
                else if (!isWeak) temp_strength[temp_count] = ZONE_UNTESTED;
                else temp_strength[temp_count] = ZONE_WEAK;

                temp_count++;
            }
        }
        // Identify potential support zones
        else if (FastDnPts[ii] > 0.001)
        {
            isWeak = SlowDnPts[ii] <= 0.001;
            loval = lowPrice;
            if (zone_extend) loval -= fu;
            hival = MathMin(MathMax(closePrice, lowPrice + fu), lowPrice + fu * 2);
            turned = false;
            hasturned = false;
            bustcount = 0;
            testcount = 0;
            isBust = false;

            for (i = ii - 1; i >= cnt; i--)
            {
                double high_i = High[i];
                double low_i = Low[i];
                double close_i = Close[i];

                if ((turned == true && FastUpPts[i] >= loval && FastUpPts[i] <= hival) ||
                    (turned == false && FastDnPts[i] <= hival && FastDnPts[i] >= loval))
                {
                    touchOk = true;
                    for (j = i + 1; j < i + 11; j++)
                    {
                        if ((turned == true && FastUpPts[j] >= loval && FastUpPts[j] <= hival) ||
                            (turned == false && FastDnPts[j] <= hival && FastDnPts[j] >= loval))
                        {
                            touchOk = false;
                            break;
                        }
                    }
                    if (touchOk)
                    {
                        bustcount = 0;
                        testcount++;
                    }
                }

                if ((turned == true && high_i > hival) || (turned == false && low_i < loval))
                {
                    bustcount++;
                    if (bustcount > 1 || isWeak)
                    {
                        isBust = true;
                        break;
                    }
                    turned = !turned;
                    hasturned = true;
                    testcount = 0;
                }
            }
            if (!isBust)
            {
                temp_hi[temp_count] = hival;
                temp_lo[temp_count] = loval;
                temp_turn[temp_count] = hasturned;
                temp_hits[temp_count] = testcount;
                temp_start[temp_count] = ii;
                temp_merge[temp_count] = false;

                if (testcount > 3) temp_strength[temp_count] = ZONE_PROVEN;
                else if (testcount > 0) temp_strength[temp_count] = ZONE_VERIFIED;
                else if (hasturned) temp_strength[temp_count] = ZONE_TURNCOAT;
                else if (!isWeak) temp_strength[temp_count] = ZONE_UNTESTED;
                else temp_strength[temp_count] = ZONE_WEAK;

                temp_count++;
            }
        }
    }

    // Look for overlapping zones and merge them if necessary
    if (zone_merge)
    {
        merge_count = 1;
        int iterations = 0;
        while (merge_count > 0 && iterations < 3)
        {
            merge_count = 0;
            iterations++;
            for (i = 0; i < temp_count; i++) temp_merge[i] = false;
            for (i = 0; i < temp_count - 1; i++)
            {
                if (temp_hits[i] == -1 || temp_merge[i]) continue;
                for (j = i + 1; j < temp_count; j++)
                {
                    if (temp_hits[j] == -1 || temp_merge[j]) continue;
                    if ((temp_hi[i] >= temp_lo[j] && temp_hi[i] <= temp_hi[j]) ||
                        (temp_lo[i] <= temp_hi[j] && temp_lo[i] >= temp_lo[j]) ||
                        (temp_hi[j] >= temp_lo[i] && temp_hi[j] <= temp_hi[i]) ||
                        (temp_lo[j] <= temp_hi[i] && temp_lo[j] >= temp_lo[i]))
                    {
                        merge1[merge_count] = i;
                        merge2[merge_count] = j;
                        temp_merge[i] = true;
                        temp_merge[j] = true;
                        merge_count++;
                    }
                }
            }
            for (i = 0; i < merge_count; i++)
            {
                int target = merge1[i];
                int source = merge2[i];
                temp_hi[target] = MathMax(temp_hi[target], temp_hi[source]);
                temp_lo[target] = MathMin(temp_lo[target], temp_lo[source]);
                temp_hits[target] += temp_hits[source];
                temp_start[target] = MathMax(temp_start[target], temp_start[source]);
                temp_strength[target] = MathMax(temp_strength[target], temp_strength[source]);

                if (temp_hits[target] > 3) temp_strength[target] = ZONE_PROVEN;
                if (temp_hits[target] == 0 && !temp_turn[target])
                {
                    temp_hits[target] = 1;
                    if (temp_strength[target] < ZONE_VERIFIED)
                        temp_strength[target] = ZONE_VERIFIED;
                }
                temp_turn[target] = temp_turn[target] && temp_turn[source];
                temp_hits[source] = -1;
            }
        }
    }

    // Copy the zones into the official arrays
    zone_count = 0;
    for (i = 0; i < temp_count; i++)
    {
        if (temp_hits[i] >= 0 && zone_count < 1000)
        {
            zone_hi[zone_count] = temp_hi[i];
            zone_lo[zone_count] = temp_lo[i];
            zone_hits[zone_count] = temp_hits[i];
            zone_turn[zone_count] = temp_turn[i];
            zone_start[zone_count] = temp_start[i];
            zone_strength[zone_count] = temp_strength[i];

            if (zone_hi[zone_count] < Close[cnt])
                zone_type[zone_count] = ZONE_SUPPORT;
            else if (zone_lo[zone_count] > Close[cnt])
                zone_type[zone_count] = ZONE_RESIST;
            else
            {
                for (j = cnt + 1; j < shift; j++)
                {
                    if (Close[j] < zone_lo[zone_count])
                    {
                        zone_type[zone_count] = ZONE_RESIST;
                        break;
                    }
                    else if (Close[j] > zone_hi[zone_count])
                    {
                        zone_type[zone_count] = ZONE_SUPPORT;
                        break;
                    }
                }
                if (j == shift)
                    zone_type[zone_count] = ZONE_SUPPORT;
            }
            zone_count++;
        }
    }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DrawZones()
{
   double lower_nerest_zone_P1 = 0;
   double lower_nerest_zone_P2 = 0;
   double higher_nerest_zone_P1 = 99999;
   double higher_nerest_zone_P2 = 99999;
   double higher_zone_type = 0;
   double higher_zone_strength = 0;
   double lower_zone_type = 0;
   double lower_zone_strength = 0;
   
   if (!EnableSnD)  // Check if SnD is enabled
        return;
   for (int i = 0; i < zone_count; i++)
   {
      // Skip zones based on strength settings
      if (zone_strength[i] == ZONE_WEAK && zone_show_weak == false)
         continue;
      if (zone_strength[i] == ZONE_UNTESTED && zone_show_untested == false)
         continue;
      if (zone_strength[i] == ZONE_TURNCOAT && zone_show_turncoat == false)
         continue;

      // Create a name for the object (Support or Resistance Zone)
      string s;
      if (zone_type[i] == ZONE_SUPPORT)
         s = prefix + "S" + string(i) + " Strength=";
      else
         s = prefix + "R" + string(i) + " Strength=";

      // Add zone strength information
      if (zone_strength[i] == ZONE_PROVEN)
         s += "Proven, Test Count=" + string(zone_hits[i]);
      else if (zone_strength[i] == ZONE_VERIFIED)
         s += "Verified, Test Count=" + string(zone_hits[i]);
      else if (zone_strength[i] == ZONE_UNTESTED)
         s += "Untested";
      else if (zone_strength[i] == ZONE_TURNCOAT)
         s += "Turncoat";
      else
         s += "Weak";

      // Define the start and current time for the zone rectangle
      datetime start_time = iTime(Symbol(), timeframe, zone_start[i]);
      datetime current_time = iTime(Symbol(), 0, 0);

      // Create a rectangle object to represent the zone on the chart
      if (!ObjectCreate(0, s, OBJ_RECTANGLE, 0, start_time, zone_hi[i], current_time, zone_lo[i]))
      {
         Print("Error creating rectangle: ", s);
         continue;
      }

      // Set the properties of the rectangle (color, width, style, fill)
      ObjectSetInteger(0, s, OBJPROP_BACK, true);
      ObjectSetInteger(0, s, OBJPROP_FILL, zone_solid);
      ObjectSetInteger(0, s, OBJPROP_WIDTH, zone_linewidth);
      ObjectSetInteger(0, s, OBJPROP_STYLE, zone_style);

      // Set the color based on the zone type and strength
      if (zone_type[i] == ZONE_SUPPORT)
      {
         if (zone_strength[i] == ZONE_TURNCOAT)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_turncoat);
         else if (zone_strength[i] == ZONE_PROVEN)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_proven);
         else if (zone_strength[i] == ZONE_VERIFIED)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_verified);
         else if (zone_strength[i] == ZONE_UNTESTED)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_untested);
         else
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_support_weak);
      }
      else
      {
         if (zone_strength[i] == ZONE_TURNCOAT)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_turncoat);
         else if (zone_strength[i] == ZONE_PROVEN)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_proven);
         else if (zone_strength[i] == ZONE_VERIFIED)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_verified);
         else if (zone_strength[i] == ZONE_UNTESTED)
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_untested);
         else
            ObjectSetInteger(0, s, OBJPROP_COLOR, color_resist_weak);
      }

      // Detect the nearest zones based on the current price
      double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      if (zone_lo[i] > lower_nerest_zone_P2 && price > zone_lo[i])
      {
         lower_nerest_zone_P1 = zone_hi[i];
         lower_nerest_zone_P2 = zone_lo[i];
         higher_zone_type = zone_type[i];
         lower_zone_strength = zone_strength[i];
      }
      if (zone_hi[i] < higher_nerest_zone_P1 && price < zone_hi[i])
      {
         higher_nerest_zone_P1 = zone_hi[i];
         higher_nerest_zone_P2 = zone_lo[i];
         lower_zone_type = zone_type[i];
         higher_zone_strength = zone_strength[i];
      }
   }

   // Set nearest zones (this part assumes you're storing nearest zones in arrays)
   ner_hi_zone_P1[0] = higher_nerest_zone_P1;
   ner_hi_zone_P2[0] = higher_nerest_zone_P2;
   ner_lo_zone_P1[0] = lower_nerest_zone_P1;
   ner_lo_zone_P2[0] = lower_nerest_zone_P2;
   ner_hi_zone_strength[0] = higher_zone_strength;
   ner_lo_zone_strength[0] = lower_zone_strength;

   // Determine if the price is inside the nearest zone
   if (ner_hi_zone_P1[0] == ner_lo_zone_P1[0])
      ner_price_inside_zone[0] = higher_zone_type;
   else
      ner_price_inside_zone[0] = 0;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool Fractal(int M, int P, int shift)
{
   // Adjust P based on timeframe
   if (timeframe > P)
      P = timeframe;
   P = int(P / int(timeframe) * 2 + MathCeil(P / timeframe / 2));

   // Ensure the shift is within valid bounds
   if (shift < P)
      return false;
   if (shift > Bars(Symbol(), timeframe) - P - 1)
      return false;

   // Loop through the High and Low data to check for fractals
   for (int i = 1; i <= P; i++)
   {
      if (M == UP_POINT)
      {
         // If there's a higher point within the range, it's not a fractal
         if (iHigh(Symbol(), timeframe, shift + i) > iHigh(Symbol(), timeframe, shift))
            return false;
         if (iHigh(Symbol(), timeframe, shift - i) >= iHigh(Symbol(), timeframe, shift))
            return false;
      }
      if (M == DN_POINT)
      {
         // If there's a lower point within the range, it's not a fractal
         if (iLow(Symbol(), timeframe, shift + i) < iLow(Symbol(), timeframe, shift))
            return false;
         if (iLow(Symbol(), timeframe, shift - i) <= iLow(Symbol(), timeframe, shift))
            return false;
      }
   }

   // If the loop completes without returning false, it's a fractal
   return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DeleteZones()
{
   // Get the length of the prefix to identify objects
    int len = StringLen(prefix);
    int total_objects = ObjectsTotal(0, 0, -1);  // Get total number of objects on the chart
    int i = 0;

    // Loop through all objects on the chart
    while (i < total_objects)
    {
        // Get the name of the object at index 'i'
        string objName = ObjectName(0, i, 0, -1);

        // Check if the object's name starts with the prefix
        if (StringSubstr(objName, 0, len) == prefix)
        {
            // If the prefix matches, delete the object
            ObjectDelete(0, objName);
            
            // Since we deleted an object, we don't increment 'i', as the objects shift positions
            total_objects--;  // Reduce total objects since one was deleted
        }
        else
        {
            // If the prefix does not match, move to the next object
            i++;
        }
    }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string TFTS(int tf) //--- Timeframe to string
{
   string tfs;

   switch (tf)
   {
      case PERIOD_M1:    tfs = "M1";    break;
      case PERIOD_M2:    tfs = "M2";    break;
      case PERIOD_M3:    tfs = "M3";    break;
      case PERIOD_M4:    tfs = "M4";    break;
      case PERIOD_M5:    tfs = "M5";    break;
      case PERIOD_M6:    tfs = "M6";    break;
      case PERIOD_M10:   tfs = "M10";   break;
      case PERIOD_M12:   tfs = "M12";   break;
      case PERIOD_M15:   tfs = "M15";   break;
      case PERIOD_M20:   tfs = "M20";   break;
      case PERIOD_M30:   tfs = "M30";   break;
      case PERIOD_H1:    tfs = "H1";    break;
      case PERIOD_H2:    tfs = "H2";    break;
      case PERIOD_H3:    tfs = "H3";    break;
      case PERIOD_H4:    tfs = "H4";    break;
      case PERIOD_H6:    tfs = "H6";    break;
      case PERIOD_H8:    tfs = "H8";    break;
      case PERIOD_H12:   tfs = "H12";   break;
      case PERIOD_D1:    tfs = "D1";    break;
      case PERIOD_W1:    tfs = "W1";    break;
      case PERIOD_MN1:   tfs = "MN1";   break;

      // Optional: Add a default case for unknown or unsupported timeframes
      default:           tfs = "Unknown"; break;
   }

   return tfs;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void FastFractals()
{
   int bars = Bars(Symbol(), timeframe);
   
   // Ensure arrays are properly sized to handle the bars
   ArrayResize(FastUpPts, bars);
   ArrayResize(FastDnPts, bars);
   
   int shift;
   // Determine the limit for how many bars to process
   int limit = MathMin(bars - 1, BackLimit + cnt);
   limit = MathMin(limit, ArraySize(FastUpPts) - 1);
   
   // Calculate P1 based on the timeframe and fractal fast factor
   int P1 = int(timeframe * fractal_fast_factor);
   
   // Initialize FastUpPts and FastDnPts arrays
   FastUpPts[0] = 0.0;
   FastUpPts[1] = 0.0;
   FastDnPts[0] = 0.0;
   FastDnPts[1] = 0.0;
   
   // Loop through the bars in reverse order, ensure shift is valid
   for (shift = limit; shift > cnt + 1; shift--)
   {
      if (shift < 0 || shift >= bars)  // Prevent out-of-range access
         continue;

      // Check for fractals using the Fractal() function for up points
      if (Fractal(UP_POINT, P1, shift) == true)
         FastUpPts[shift] = iHigh(Symbol(), timeframe, shift);  // Store the high value if a fractal is found
      else
         FastUpPts[shift] = 0.0;  // Otherwise, store 0.0

      // Check for fractals using the Fractal() function for down points
      if (Fractal(DN_POINT, P1, shift) == true)
         FastDnPts[shift] = iLow(Symbol(), timeframe, shift);  // Store the low value if a fractal is found
      else
         FastDnPts[shift] = 0.0;  // Otherwise, store 0.0
   }
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SlowFractals()
{
   int bars = Bars(Symbol(), timeframe);

   // Ensure arrays are properly sized to handle the bars
   ArrayResize(SlowUpPts, bars);
   ArrayResize(SlowDnPts, bars);
   ArrayResize(ner_hi_zone_P1, bars);
   ArrayResize(ner_hi_zone_P2, bars);
   ArrayResize(ner_lo_zone_P1, bars);
   ArrayResize(ner_lo_zone_P2, bars);
   ArrayResize(ner_hi_zone_strength, bars);
   ArrayResize(ner_lo_zone_strength, bars);
   ArrayResize(ner_price_inside_zone, bars);

   int shift;
   // Determine the limit for how many bars to process
   int limit = MathMin(bars - 1, BackLimit + cnt);
   limit = MathMin(limit, ArraySize(SlowUpPts) - 1);

   // Calculate P2 based on the timeframe and fractal slow factor
   int P2 = int(timeframe * fractal_slow_factor);

   // Initialize SlowUpPts and SlowDnPts arrays
   SlowUpPts[0] = 0.0;
   SlowUpPts[1] = 0.0;
   SlowDnPts[0] = 0.0;
   SlowDnPts[1] = 0.0;

   // Loop through the bars in reverse order
   for (shift = limit; shift > cnt + 1; shift--)
   {
      if (shift < 0 || shift >= bars)  // Prevent out-of-range access
         continue;

      // Check for fractals using the Fractal() function for up points
      if (Fractal(UP_POINT, P2, shift) == true)
         SlowUpPts[shift] = iHigh(Symbol(), timeframe, shift);  // Store the high value if a fractal is found
      else
         SlowUpPts[shift] = 0.0;  // Otherwise, store 0.0

      // Check for fractals using the Fractal() function for down points
      if (Fractal(DN_POINT, P2, shift) == true)
         SlowDnPts[shift] = iLow(Symbol(), timeframe, shift);  // Store the low value if a fractal is found
      else
         SlowDnPts[shift] = 0.0;  // Otherwise, store 0.0

      // Reset zone-related arrays to 0 for the current shift
      ner_hi_zone_P1[shift] = 0;
      ner_hi_zone_P2[shift] = 0;
      ner_lo_zone_P1[shift] = 0;
      ner_lo_zone_P2[shift] = 0;
      ner_hi_zone_strength[shift] = 0;
      ner_lo_zone_strength[shift] = 0;
      ner_price_inside_zone[shift] = 0;
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
void showLabels()
{
   // Get the time of the bar at the 'cnt' position
   datetime Time = iTime(Symbol(), timeframe, cnt);
   
   // Loop through all identified zones
   for (int i = 0; i < zone_count; i++)
   {
      // Prepare the label based on the zone's strength
      string lbl;
      if (zone_strength[i] == ZONE_PROVEN)
         lbl = "Proven";
      else if (zone_strength[i] == ZONE_VERIFIED)
         lbl = "Verified";
      else if (zone_strength[i] == ZONE_UNTESTED)
         lbl = "Untested";
      else if (zone_strength[i] == ZONE_TURNCOAT)
         lbl = "Turncoat";
      else
         lbl = "Weak";

      // Append Support or Resistance to the label
      if (zone_type[i] == ZONE_SUPPORT)
         lbl = lbl + " " + sup_name;
      else
         lbl = lbl + " " + res_name;

      // Add the test count to the label if applicable
      if (zone_hits[i] > 0 && zone_strength[i] > ZONE_UNTESTED)
      {
         lbl = lbl + ", " + test_name + "=" + string(zone_hits[i]);
      }

      // Calculate horizontal position (adjust_hpos) based on the number of visible bars
      int adjust_hpos;
      long wbpc = ChartGetInteger(0, CHART_VISIBLE_BARS);  // Visible bars on the chart
      int k = PeriodSeconds(timeframe) / 10 + StringLen(lbl);

      if (wbpc < 80)
         adjust_hpos = int(Time) + k * 1;
      else if (wbpc < 125)
         adjust_hpos = int(Time) + k * 2;
      else if (wbpc < 250)
         adjust_hpos = int(Time) + k * 4;
      else if (wbpc < 480)
         adjust_hpos = int(Time) + k * 8;
      else if (wbpc < 950)
         adjust_hpos = int(Time) + k * 16;
      else
         adjust_hpos = int(Time) + k * 32;

      // Shift for label positioning
      int shift = k * zone_label_shift;

      // Vertical position (vpos) of the label is one-third down the zone's range
      double vpos = zone_hi[i] - (zone_hi[i] - zone_lo[i]) / 3;

      // Conditions to skip certain zones based on visibility settings
      if (zone_strength[i] == ZONE_WEAK && !zone_show_weak)
         continue;
      if (zone_strength[i] == ZONE_UNTESTED && !zone_show_untested)
         continue;
      if (zone_strength[i] == ZONE_TURNCOAT && !zone_show_turncoat)
         continue;

      // Create the label object on the chart
      string s = prefix + string(i) + "LBL";
      ObjectCreate(0, s, OBJ_TEXT, 0, 0, 0);
      ObjectSetInteger(0, s, OBJPROP_TIME, adjust_hpos + shift);
      ObjectSetDouble(0, s, OBJPROP_PRICE, vpos);
      ObjectSetString(0, s, OBJPROP_TEXT, lbl);
      ObjectSetString(0, s, OBJPROP_FONT, Text_font);
      ObjectSetInteger(0, s, OBJPROP_FONTSIZE, Text_size);
      ObjectSetInteger(0, s, OBJPROP_COLOR, Text_color);
   }
}

void DrawPivotLevels() {
   ENUM_TIMEFRAMES TimeframeD1 = PERIOD_D1; // Using daily timeframe for pivot calculation

   // Calculate previous day's high, low, close, and open (for today’s pivot)
   prevHigh = iHigh(_Symbol, TimeframeD1, 1);
   prevLow = iLow(_Symbol, TimeframeD1, 1);
   double prevClose = iClose(_Symbol, TimeframeD1, 1);
   double prevOpen = iOpen(_Symbol, TimeframeD1, 1);

   double X;

   // Calculate today's Pivot Points based on previous day's data
   if (prevOpen == prevClose) {
      // Case when previous day's open is equal to close
      X = prevHigh + prevLow + 2 * prevClose;
   }
   else if (prevClose > prevOpen) {
      // Case when the previous day's close is greater than open
      X = 2 * prevHigh + prevLow + prevClose;
   }
   else {
      // Case when the previous day's close is less than open
      X = 2 * prevLow + prevHigh + prevClose;
   }

   // Calculate the pivot, resistance, and support levels
   pivot = X / 4.0;
   r1 = X / 2.0 - prevLow; // Resistance 1
   s1 = X / 2.0 - prevHigh; // Support 1

   datetime timeStart = iTime(_Symbol, TimeframeD1, 0); // Start of today’s daily candle
   datetime timeEnd = TimeCurrent(); // Current time

   // Draw Pivot
   DrawLevel("PivotToday", "P", pivot, timeStart, timeEnd, PivotColor);

   // Draw Support 1
   DrawLevel("S1Today", "S1", s1, timeStart, timeEnd, SupportColor);

   // Draw Resistance 1
   DrawLevel("R1Today", "R1", r1, timeStart, timeEnd, ResistanceColor);

   // Draw Previous Day High
   DrawLevel("PrevDayHigh", "Prev High", prevHigh, timeStart, timeEnd, HighLowColor);

   // Draw Previous Day Low
   DrawLevel("PrevDayLow", "Prev Low", prevLow, timeStart, timeEnd, HighLowColor);
}
//+------------------------------------------------------------------+
//| Function to draw levels (Pivot, S1, R1, High, Low)  |
//+------------------------------------------------------------------+
void DrawLevel(string levelName, string label, double price, datetime timeStart, datetime timeEnd, color clr)
{
   string objName = levelName;
   string objTextName = levelName + "_Label"; // Text label for the level

   // Create or update the trend line for the level
   if (ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_TREND, 0, timeStart, price, timeEnd, price);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
   }
   else
   {
      ObjectMove(0, objName, 0, timeStart, price);
      ObjectMove(0, objName, 1, timeEnd, price);
   }

   // Create or update the text label with the level name and price
   if (ObjectFind(0, objTextName) < 0)
   {
      ObjectCreate(0, objTextName, OBJ_TEXT, 0, timeEnd, price);
      ObjectSetInteger(0, objTextName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objTextName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, objTextName, OBJPROP_TEXT, label + " " + DoubleToString(price, _Digits));
   }
   else
   {
      ObjectMove(0, objTextName, 0, timeEnd, price);
      ObjectSetString(0, objTextName, OBJPROP_TEXT, label + " " + DoubleToString(price, _Digits));
   }
}

void DeletePivotLevels()
{
   // Delete the Pivot, Support, Resistance levels, and their labels
   ObjectDelete(0, "PivotToday");
   ObjectDelete(0, "PivotToday_Label");

   ObjectDelete(0, "S1Today");
   ObjectDelete(0, "S1Today_Label");

   ObjectDelete(0, "R1Today");
   ObjectDelete(0, "R1Today_Label");

   ObjectDelete(0, "PrevDayHigh");
   ObjectDelete(0, "PrevDayHigh_Label");

   ObjectDelete(0, "PrevDayLow");
   ObjectDelete(0, "PrevDayLow_Label");
}

// Function to detect Bullish or Bearish Engulfing pattern
int getEngulfing() {
   // Ensure we have at least 2 candles
   if (Bars(_Symbol, PERIOD_CURRENT) < 2) {
      Print("Not enough bars to check for Engulfing Pattern");
      return 0;
   }

   // Get values for the current candle (index 1) and the previous candle (index 2)
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);

   double open2 = iOpen(_Symbol, PERIOD_CURRENT, 2);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double low2 = iLow(_Symbol, PERIOD_CURRENT, 2);

   double currentPrice = close1;
   double pipDifference = 5 * _Point;

   // Define the body ratio threshold (e.g., 20% of the candle range)
   double bodyRatioThreshold = 0.1;

   // Check the body size of the previous candle (index 2)
   double candleBodySize = MathAbs(open2 - close2);
   double candleRange = high2 - low2;

   // If the body size is less than the threshold, skip this candle for engulfing detection
   if (candleBodySize / candleRange < bodyRatioThreshold) {
      Print("Previous candle has a thin body. Ignoring this pattern for engulfing detection.");
      return 0;
   }

   // Check if the current or previous candle touched any Supply or Demand zones
   bool inDemandZone = false;
   bool inSupplyZone = false;

   for (int i = 0; i < zone_count; i++) {
      // Check for demand (support) zones
      if (zone_type[i] == ZONE_SUPPORT && ((low1 <= zone_hi[i] && low1 >= zone_lo[i]) || (low2 <= zone_hi[i] && low2 >= zone_lo[i]))) {
         inDemandZone = true;
         break;
      }
      // Check for supply (resistance) zones
      if (zone_type[i] == ZONE_RESIST && ((high1 <= zone_hi[i] && high1 >= zone_lo[i]) || (high2 <= zone_hi[i] && high2 >= zone_lo[i]))) {
         inSupplyZone = true;
         break;
      }
   }

   // Bullish Engulfing: Check if in demand zone and below the pivot
   if (open1 < close1 && open2 > close2) {
      if ((currentPrice <= s1 + 25 * _Point || currentPrice <= prevLow + 25 * _Point || inDemandZone) && currentPrice < pivot) {
         if (close1 > high2 && (close1 - high2) >= pipDifference) {
            if (lastBullishEngulfingObj != "") {
               ObjectDelete(0, lastBullishEngulfingObj);
               ObjectDelete(0, lastBullishEngulfingObj + "_Label");
            }
            lastBullishEngulfingObj = createObjWithText(iTime(_Symbol, PERIOD_CURRENT, 1), low1, 217, clrGreen, "Bullish Engulfing", false);
            return 1;
         }
      }
   }

   // Bearish Engulfing: Check if in supply zone and above the pivot
   if (open1 > close1 && open2 < close2) {
      if ((currentPrice > r1 - 10 * _Point || currentPrice > prevHigh - 10 * _Point || inSupplyZone) && currentPrice > pivot) {
         if (close1 < low2 && (low2 - close1) >= pipDifference) {
            if (lastBearishEngulfingObj != "") {
               ObjectDelete(0, lastBearishEngulfingObj);
               ObjectDelete(0, lastBearishEngulfingObj + "_Label");
            }
            lastBearishEngulfingObj = createObjWithText(iTime(_Symbol, PERIOD_CURRENT, 1), high1, 218, clrRed, "Bearish Engulfing", true);
            return -1;
         }
      }
   }

   return 0;  // No pattern detected
}

string createObjWithText(datetime time, double price, int arrowCode, color clr, string txt, bool isBearish) {
   // Create a unique name for the arrow object
   string objName;
   StringConcatenate(objName, "Signal@", time, "at", DoubleToString(price, _Digits), "(", arrowCode, ")");

   // Adjust the price for positioning the arrow above or below the candle
   double arrowPrice = isBearish ? price + 70 * _Point : price - 70 * _Point; // Position arrow 50 points above/below the candle

   // Create the arrow object
   if (ObjectCreate(0, objName, OBJ_ARROW, 0, time, arrowPrice)) {
      ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      
      // Set arrow anchor based on its direction
      ObjectSetInteger(0, objName, OBJPROP_ANCHOR, isBearish ? ANCHOR_TOP : ANCHOR_BOTTOM);  // Bearish arrow above, bullish arrow below
   }

   // Create a unique name for the text label
   string candleName = objName + "_Label";

   // Create the text label object
   if (ObjectCreate(0, candleName, OBJ_TEXT, 0, time, arrowPrice)) {
      ObjectSetString(0, candleName, OBJPROP_TEXT, " " + txt);  // The label for the pattern
      ObjectSetInteger(0, candleName, OBJPROP_COLOR, clr);  // Text color matching the arrow
      ObjectSetInteger(0, candleName, OBJPROP_FONTSIZE, 10);  // Text font size
      ObjectSetString(0, candleName, OBJPROP_FONT, "Arial");  // Font type
   }
   
   // Return the unique object name for later reference
   return objName;
}

bool CheckInputs(){
   if(MagicNumber <= 0){
      Alert("Magicnumber <= 0");
      return false;
   }
   if(InpLotMode==LOT_MODE_FIXED && (InpLots <= 0 || InpLots > 10)){
      Alert("Lots <= 0 or > 10");
      return false;
   }
   if(InpLotMode==LOT_MODE_MONEY && (InpLots <= 0 || InpLots > 1000)){
      Alert("Lots <= 0 or > 1000");
      return false;
   }
   if(InpLotMode==LOT_MODE_PCT_ACCOUNT && (InpLots <= 0 || InpLots > 5)){
      Alert("Lots <= 0 or > 5");
      return false;
   }
   if((InpLotMode==LOT_MODE_MONEY || InpLotMode==LOT_MODE_PCT_ACCOUNT) && Slpoints==0){
      Alert("Selected lot mode needs a stop loss");  
      return false;
   }
   if(Slpoints<0 || Slpoints > 1000){
      Alert("Stop loss < 0 or stop loss > 1000");
      return false;
   }
   return true;
}

double calcLots(double slDistance, double &lots){
   lots = 0.0;
   if(InpLotMode==LOT_MODE_FIXED){
      lots = InpLots;
   }
   else{
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double volumeStep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      
      double riskMoney = InpLotMode == LOT_MODE_MONEY ? InpLots : AccountInfoDouble(ACCOUNT_EQUITY) * InpLots * 0.001;
      double moneyVolumeStep = (slDistance / tickSize) * tickValue * volumeStep;
      lots =  MathFloor(riskMoney/moneyVolumeStep) * volumeStep;
   }
   if(!CheckLots(lots)){return false;}
   return true;
}


bool CheckLots(double &lots){
   double min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lots<min){
      Print("Lot size will be set to the minimun allowable volume");
      lots = min;
      return true;
   }
   if(lots>max){
      Print("Lot size greater than the maximum allowable volume. lots: ",lots," max: ",max);
      return false;
   }
   lots = (int)MathFloor(lots/step) * step;
   return true;
}

void OpenSellOrder()
{
    // Ensure only one trade is running (check if there are any open positions)
    if (PositionsTotal() > 0) 
    {
        Print("Cannot open Sell order. A position is already open.");
        return;
    }
   
    // Check if the cooldown period has passed
    if (TimeCurrent() - lastTradeTime < cooldownPeriodSeconds)
    {
        Print("Cooldown period active. No new trades are allowed at the moment.");
        return;
    }

    double lots;
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Get the current bid price
    double sl;
    
    // Determine SL level based on user choice
    if (UseSwingHighLowSL) {
        sl = FindNearestSwingHigh(SwingLookbackPeriod) + 50 * _Point;  // Use the nearest swing high plus 50 points as SL
    } else {
        sl = price + Slpoints * _Point; // Fixed SL above the current price
    }

    // Identify the nearest key level: either prevHigh or r1
    double nearestKeyLevel = (price > prevHigh) ? prevHigh : r1;
   
    // Calculate the distance between the entry point and the nearest key level in pips
    double distanceToNearestLevel = MathAbs(price - nearestKeyLevel) / _Point;

    // Minimum distance for TP is 30 pips, if less, use the next key level as TP
    if (distanceToNearestLevel < 30)
    {
        nearestKeyLevel = r1; // Use r1 if the distance to prevHigh is less than 20 pips
        distanceToNearestLevel = MathAbs(price - nearestKeyLevel) / _Point;
      
        // Check again if the new key level is still too close, use pivot as a fallback
        if (distanceToNearestLevel < 30)
        {
            nearestKeyLevel = pivot; // Use pivot as a fallback
        }
    }

    double tp = nearestKeyLevel; // Set TP to the nearest valid key level

    if (!calcLots(sl - price, lots))  // Check if calcLots() returns true
    {
        Print("Lot size calculation failed. Unable to open Sell order.");
        return;
    }

    // Setup trade request
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;         // Instant order
    request.symbol = _Symbol;                   // Current symbol
    request.volume = lots;                      // Lot size
    request.type = ORDER_TYPE_SELL;             // Sell order
    request.price = price;                      // Bid price
    request.sl = sl;                            // Stop Loss level
    request.tp = tp;                            // Take Profit level
    request.deviation = 10;                     // Slippage
    request.magic = MagicNumber;                // Magic number for the order
    request.comment = "Bearish Engulfing";      // Comment for the order

    if (OrderSend(request, result)) // Place the order
    {
        Print("Sell order placed successfully: ", result.order);
        openPositionDate = TimeCurrent(); // Store the current date when the position is opened
        lastTradeTime = TimeCurrent();    // Update the last trade time to the current time
    } 
    else 
    {
        Print("Error placing sell order: ", GetLastError());
    }
}

void OpenBuyOrder()
{
    // Ensure only one trade is running (check if there are any open positions)
    if (PositionsTotal() > 0) 
    {
        Print("Cannot open Buy order. A position is already open.");
        return;
    }
   
    // Check if the cooldown period has passed
    if (TimeCurrent() - lastTradeTime < cooldownPeriodSeconds)
    {
        Print("Cooldown period active. No new trades are allowed at the moment.");
        return;
    }

    double lots;
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); // Get the current ask price
    double sl;
    
    // Determine SL level based on user choice
    if (UseSwingHighLowSL) {
        sl = FindNearestSwingLow(SwingLookbackPeriod) - 50 * _Point;  // Use the nearest swing low minus 50 points as SL
    } else {
        sl = price - Slpoints * _Point; // Fixed SL below the current price
    }

    // Identify the nearest key level: either s1 or prevLow
    double nearestKeyLevel = (price < s1) ? s1 : prevLow;
   
    // Calculate the distance between the entry point and the nearest key level in pips
    double distanceToNearestLevel = MathAbs(price - nearestKeyLevel) / _Point;

    // Minimum distance for TP is 20 pips, if less, use the next key level as TP
    if (distanceToNearestLevel < 30)
    {
        nearestKeyLevel = prevLow; // Use prevLow if the distance to s1 is less than 20 pips
        distanceToNearestLevel = MathAbs(price - nearestKeyLevel) / _Point;
      
        // Check again if the new key level is still too close, use pivot as a fallback
        if (distanceToNearestLevel < 30)
        {
            nearestKeyLevel = pivot; // Use pivot as a fallback
        }
    }

    double tp = nearestKeyLevel; // Set TP to the nearest valid key level

    if (!calcLots(price - sl, lots))  // Check if calcLots() returns true
    {
        Print("Lot size calculation failed. Unable to open Buy order.");
        return;
    }

    // Setup trade request
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;         // Instant order
    request.symbol = _Symbol;                   // Current symbol
    request.volume = lots;                      // Lot size
    request.type = ORDER_TYPE_BUY;              // Buy order
    request.price = price;                      // Ask price
    request.sl = sl;                            // Stop Loss level
    request.tp = tp;                            // Take Profit level
    request.deviation = 10;                     // Slippage
    request.magic = MagicNumber;                // Magic number for the order
    request.comment = "Bullish Engulfing";      // Comment for the order

    if (OrderSend(request, result)) // Place the order
    {
        Print("Buy order placed successfully: ", result.order);
        openPositionDate = TimeCurrent(); // Store the current date when the position is opened
        lastTradeTime = TimeCurrent();    // Update the last trade time to the current time
    } 
    else 
    {
        Print("Error placing buy order: ", GetLastError());
    }
}

void UpdateStopLoss(){
   // Return early if there are no Stop Loss points or if trailing is not enabled
   if(Slpoints == 0 || !InpStopLossTrailing) { 
      return; 
   }

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) { 
         Print("Failed to get position ticket"); 
         return; 
      }
      
      // Select position by ticket
      if(!PositionSelectByTicket(ticket)) { 
         Print("Failed to select position by ticket"); 
         return; 
      }
      
      // Get the magic number of the position
      ulong magicnumber;
      if(!PositionGetInteger(POSITION_MAGIC, magicnumber)) { 
         Print("Failed to get position magic number"); 
         return; 
      }

      // Ensure the magic number matches
      if(MagicNumber == magicnumber) {
         // Get the position type (buy or sell)
         long type;
         if(!PositionGetInteger(POSITION_TYPE, type)) { 
            Print("Failed to get position type"); 
            return; 
         }

         // Get the current stop loss and take profit
         double currSL, currTP;
         if(!PositionGetDouble(POSITION_SL, currSL)) { 
            Print("Failed to get position stop loss"); 
            return; 
         }
         if(!PositionGetDouble(POSITION_TP, currTP)) { 
            Print("Failed to get position take profit"); 
            return; 
         }

         // Get the current price based on the position type
         double currPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         int direction = (type == POSITION_TYPE_BUY) ? 1 : -1;

         // Calculate the new stop loss position
         double newSL = NormalizeDouble(currPrice - direction * Slpoints * _Point, _Digits);

         // Check if the new stop loss is better (closer to reducing risk) than the current one
         if((type == POSITION_TYPE_BUY && (newSL > currSL || currSL == 0)) ||
            (type == POSITION_TYPE_SELL && (newSL < currSL || currSL == 0))) {

            // Modify the position to update the stop loss
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = _Symbol;
            request.sl = newSL;
            request.tp = currTP;

            // Send the modification request
            if(!OrderSend(request, result)) {
               Print("Failed to modify position stop loss. Error: ", GetLastError());
            } else {
               Print("Stop loss updated successfully for ticket: ", ticket);
            }
         }
      }
   }
}

void CheckClosePositionByDay()
{
   // Cek jika ada posisi terbuka
   if (PositionsTotal() > 0) 
   {
      datetime currentDate = TimeCurrent(); // Dapatkan waktu saat ini
      MqlDateTime openDateTime, currentDateTime;

      // Konversi waktu posisi terbuka dan waktu saat ini ke struktur MqlDateTime
      TimeToStruct(openPositionDate, openDateTime);
      TimeToStruct(currentDate, currentDateTime);

      // Jika hari sudah berubah dibandingkan dengan hari posisi dibuka
      if (openDateTime.day != currentDateTime.day)
      {
         for (int i = PositionsTotal() - 1; i >= 0; i--) 
         {
            ulong ticket = PositionGetTicket(i);
            if (ticket > 0) 
            {
               // Close all open positions
               if (PositionSelectByTicket(ticket)) 
               {
                  double volume = PositionGetDouble(POSITION_VOLUME);
                  long type = PositionGetInteger(POSITION_TYPE);
                  
                  if (type == POSITION_TYPE_BUY) 
                  {
                     trade.PositionClose(ticket); // Tutup posisi buy
                  }
                  else if (type == POSITION_TYPE_SELL) 
                  {
                     trade.PositionClose(ticket); // Tutup posisi sell
                  }

                  Print("Position closed due to day change.");
               }
            }
         }
      }
   }
}

// Find the nearest swing high within the specified lookback period
double FindNearestSwingHigh(int lookbackPeriod) {
    double swingHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);  // Start with the previous candle's high
    for (int i = 1; i <= lookbackPeriod; i++) {
        double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, i);
        if (currentHigh > swingHigh) {
            swingHigh = currentHigh;
        }
    }
    return swingHigh;
}

// Find the nearest swing low within the specified lookback period
double FindNearestSwingLow(int lookbackPeriod) {
    double swingLow = iLow(_Symbol, PERIOD_CURRENT, 1);  // Start with the previous candle's low
    for (int i = 1; i <= lookbackPeriod; i++) {
        double currentLow = iLow(_Symbol, PERIOD_CURRENT, i);
        if (currentLow < swingLow) {
            swingLow = currentLow;
        }
    }
    return swingLow;
}

void RefreshTimeframeData()
{
    // Reset last bar time to handle new timeframe correctly
    datetime lastBarTime = 0;

    // Determine the number of bars available in the new timeframe
    int bars = Bars(_Symbol, timeframe);
    
    // Resize arrays to the new timeframe's bar count
    ArrayResize(High, bars);
    ArrayResize(Low, bars);
    ArrayResize(Close, bars);
    ArrayResize(ATR, bars);

    // Initialize the data arrays with the latest data
    for (int i = 0; i < bars; i++) {
        High[i] = iHigh(_Symbol, timeframe, i);
        Low[i] = iLow(_Symbol, timeframe, i);
        Close[i] = iClose(_Symbol, timeframe, i);
    }

    // Refresh ATR values for the new timeframe
    if (CopyBuffer(iATR_handle, 0, 0, bars, ATR) == -1) {
        Print("Failed to copy ATR data for the new timeframe.");
        return;
    }
}

//+------------------------------------------------------------------+
