//+------------------------------------------------------------------+
//|                                           SelectiveSignalEA.mq5 |
//|                                    Selective Signal Trading EA   |
//|                   Bollinger Bands + RSI + Volume with Random Selection |
//+------------------------------------------------------------------+
#property copyright "Selective Signal EA"
#property link      ""
#property version   "1.00"
#property description "EA that selectively takes 1-2 trades per day using quality assessment and weighted randomness"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input Parameters
input group "=== Trading Limits ==="
input int MaxDailyTrades = 2;                    // Maximum trades per day
input double MinQualityThreshold = 60.0;         // Minimum signal quality (0-100)
input double RandomnessFactor = 0.5;             // Randomness factor (0-1)

input group "=== Indicator Settings ==="
input int BB_Period = 20;                        // Bollinger Bands period
input double BB_Deviation = 2.0;                 // BB standard deviation
input int RSI_Period = 14;                       // RSI period
input int Volume_Period = 20;                    // Volume average period
input double Volume_MinRatio = 1.2;              // Minimum volume ratio

input group "=== Market Condition Settings ==="
input int ADX_Period = 14;                       // ADX period
input double ADX_TrendThreshold = 25.0;          // ADX trend threshold
input double BandWidth_ContractingThreshold = 0.5; // Band width threshold

input group "=== Trading Hours ==="
input int StartHour = 6;                         // Trading start hour (GMT)
input int EndHour = 18;                          // Trading end hour (GMT)
input bool EnableSessionFiltering = true;        // Enable session filtering

input group "=== Risk Management ==="
input double LotSize = 0.1;                      // Fixed lot size
input bool UsePercentRisk = false;               // Use percentage risk
input double RiskPercent = 1.0;                  // Risk percentage per trade
input int ATR_Period = 14;                       // ATR period for stops
input double ATR_StopMultiplier = 1.5;           // ATR stop multiplier
input double ATR_TrailMultiplier = 1.0;          // ATR trailing multiplier
input int MinimumStopPips = 15;                  // Minimum stop distance (pips)
input double RiskRewardRatio = 2.0;              // Minimum risk-reward ratio
input int BreakEvenBuffer = 5;                   // Break-even buffer (pips)

input group "=== Advanced Settings ==="
input bool DeterministicMode = false;            // Deterministic mode for backtesting
input bool EnablePartialClose = false;           // Enable partial position management
input int PartialClosePercent = 50;              // Percentage to close at 1:1 R:R

//--- Global Variables
int tradesExecutedToday = 0;
datetime lastTradeDate = 0;
datetime lastBarTime = 0;
bool isTrendingMarket = false;
double currentBandWidth = 0.0;
double avgBandWidth = 0.0;

//--- Indicator Handles
int handleBB, handleRSI, handleADX, handleATR;

//--- Global Variable Names
string GV_TradesCount = "SSE_TradesCount_" + Symbol();
string GV_LastDate = "SSE_LastDate_" + Symbol();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize indicators
    handleBB = iBands(Symbol(), PERIOD_H1, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
    handleRSI = iRSI(Symbol(), PERIOD_H1, RSI_Period, PRICE_CLOSE);
    handleADX = iADX(Symbol(), PERIOD_H1, ADX_Period);
    handleATR = iATR(Symbol(), PERIOD_H1, ATR_Period);
    
    if(handleBB == INVALID_HANDLE || handleRSI == INVALID_HANDLE || 
       handleADX == INVALID_HANDLE || handleATR == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return INIT_FAILED;
    }
    
    // Initialize random seed
    if(DeterministicMode)
        MathSrand(12345); // Fixed seed for backtesting
    else
        MathSrand((int)TimeLocal());
    
    // Restore daily counters
    RestoreDailyCounters();
    
    Print("SelectiveSignalEA initialized successfully");
    Print("Trading Hours: ", StartHour, ":00 - ", EndHour, ":00 GMT");
    Print("Max Daily Trades: ", MaxDailyTrades);
    Print("Quality Threshold: ", MinQualityThreshold);
    Print("Randomness Factor: ", RandomnessFactor);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Save daily counters
    SaveDailyCounters();
    
    // Release indicator handles
    IndicatorRelease(handleBB);
    IndicatorRelease(handleRSI);
    IndicatorRelease(handleADX);
    IndicatorRelease(handleATR);
    
    Print("SelectiveSignalEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new H1 bar
    datetime currentBarTime = iTime(Symbol(), PERIOD_H1, 0);
    if(currentBarTime == lastBarTime)
        return;
    
    lastBarTime = currentBarTime;
    
    // Check for new trading day
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
    
    if(currentDate != lastTradeDate)
    {
        ResetDailyCounters();
        lastTradeDate = currentDate;
    }
    
    // Check if within trading hours
    if(EnableSessionFiltering && !IsWithinTradingHours())
        return;
    
    // Check daily trade limit
    if(tradesExecutedToday >= MaxDailyTrades)
        return;
    
    // Update market conditions
    UpdateMarketConditions();
    
    // Manage existing positions
    ManagePositions();
    
    // Look for new signals
    ProcessSignals();
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int currentHour = dt.hour;
    
    if(StartHour <= EndHour)
        return (currentHour >= StartHour && currentHour < EndHour);
    else
        return (currentHour >= StartHour || currentHour < EndHour);
}

//+------------------------------------------------------------------+
//| Update market conditions                                         |
//+------------------------------------------------------------------+
void UpdateMarketConditions()
{
    double adxArray[1];
    if(CopyBuffer(handleADX, 0, 1, 1, adxArray) <= 0)
        return;
    
    isTrendingMarket = (adxArray[0] > ADX_TrendThreshold);
    
    // Calculate band width
    double upperArray[1], lowerArray[1], middleArray[1];
    if(CopyBuffer(handleBB, 1, 1, 1, upperArray) > 0 &&
       CopyBuffer(handleBB, 2, 1, 1, lowerArray) > 0 &&
       CopyBuffer(handleBB, 0, 1, 1, middleArray) > 0)
    {
        currentBandWidth = (upperArray[0] - lowerArray[0]) / middleArray[0];
        
        // Calculate average band width over 20 periods
        double bandWidthArray[20];
        double sumBandWidth = 0;
        for(int i = 1; i <= 20; i++)
        {
            double upper[], lower[], middle[];
            if(CopyBuffer(handleBB, 1, i, 1, upper) > 0 &&
               CopyBuffer(handleBB, 2, i, 1, lower) > 0 &&
               CopyBuffer(handleBB, 0, i, 1, middle) > 0)
            {
                bandWidthArray[i-1] = (upper[0] - lower[0]) / middle[0];
                sumBandWidth += bandWidthArray[i-1];
            }
        }
        avgBandWidth = sumBandWidth / 20.0;
    }
    
    // Adjust BB deviation based on market conditions
    double newDeviation = BB_Deviation;
    if(isTrendingMarket)
        newDeviation = MathMax(2.5, BB_Deviation * 1.25);
    
    // Update BB handle if deviation changed significantly
    if(MathAbs(newDeviation - BB_Deviation) > 0.1)
    {
        IndicatorRelease(handleBB);
        handleBB = iBands(Symbol(), PERIOD_H1, BB_Period, 0, newDeviation, PRICE_CLOSE);
    }
}

//+------------------------------------------------------------------+
//| Process signals for entry                                       |
//+------------------------------------------------------------------+
void ProcessSignals()
{
    // Get indicator values
    double upperArray[1], lowerArray[1], middleArray[1];
    double rsiArray[1];
    double closeArray[2];
    
    if(CopyBuffer(handleBB, 1, 1, 1, upperArray) <= 0 ||
       CopyBuffer(handleBB, 2, 1, 1, lowerArray) <= 0 ||
       CopyBuffer(handleBB, 0, 1, 1, middleArray) <= 0 ||
       CopyBuffer(handleRSI, 0, 1, 1, rsiArray) <= 0 ||
       CopyClose(Symbol(), PERIOD_H1, 1, 2, closeArray) <= 0)
        return;
    
    double upper = upperArray[0];
    double lower = lowerArray[0];
    double middle = middleArray[0];
    double rsi = rsiArray[0];
    double close = closeArray[0];
    
    // Calculate volume ratio
    double volumeRatio = CalculateVolumeRatio();
    
    // Check for buy signal
    if(close <= lower && rsi < 30 && volumeRatio >= Volume_MinRatio)
    {
        double deviation = MathAbs((middle - close) / (middle - lower));
        double signalQuality = AssessSignalQuality(deviation, rsi, volumeRatio, true);
        
        if(signalQuality >= MinQualityThreshold && ShouldTakeTrade(signalQuality))
        {
            OpenPosition(ORDER_TYPE_BUY, signalQuality);
        }
        else
        {
            Print("BUY signal skipped - Quality: ", DoubleToString(signalQuality, 1));
        }
    }
    
    // Check for sell signal
    if(close >= upper && rsi > 70 && volumeRatio >= Volume_MinRatio)
    {
        double deviation = MathAbs((close - middle) / (upper - middle));
        double signalQuality = AssessSignalQuality(deviation, rsi, volumeRatio, false);
        
        if(signalQuality >= MinQualityThreshold && ShouldTakeTrade(signalQuality))
        {
            OpenPosition(ORDER_TYPE_SELL, signalQuality);
        }
        else
        {
            Print("SELL signal skipped - Quality: ", DoubleToString(signalQuality, 1));
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate volume ratio                                           |
//+------------------------------------------------------------------+
double CalculateVolumeRatio()
{
    long volumeArray[21];
    if(CopyTickVolume(Symbol(), PERIOD_H1, 1, Volume_Period + 1, volumeArray) <= 0)
        return 1.0;
    
    double avgVolume = 0;
    for(int i = 1; i <= Volume_Period; i++)
        avgVolume += volumeArray[i];
    avgVolume /= Volume_Period;
    
    return (avgVolume > 0) ? (double)volumeArray[0] / avgVolume : 1.0;
}

//+------------------------------------------------------------------+
//| Assess signal quality (0-100 scale)                             |
//+------------------------------------------------------------------+
double AssessSignalQuality(double deviation, double rsi, double volumeRatio, bool isBuySignal)
{
    // BB Deviation Score (40% weight)
    double bbScore = MathMin(100, deviation * 25);
    
    // RSI Extremity Score (40% weight)
    double rsiScore = 0;
    if(isBuySignal && rsi <= 30)
        rsiScore = 100 - (rsi * 2);
    else if(!isBuySignal && rsi >= 70)
        rsiScore = (rsi - 50) * 2;
    
    // Volume Score (20% weight)
    double volumeScore = MathMin(100, volumeRatio * 50);
    
    // Weighted average
    double quality = (bbScore * 0.4) + (rsiScore * 0.4) + (volumeScore * 0.2);
    
    return MathMax(0, MathMin(100, quality));
}

//+------------------------------------------------------------------+
//| Determine if trade should be taken based on probability         |
//+------------------------------------------------------------------+
bool ShouldTakeTrade(double signalQuality)
{
    if(tradesExecutedToday >= MaxDailyTrades)
        return false;
    
    // Calculate hours left in trading session
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int hoursLeft = EndHour - dt.hour;
    if(hoursLeft <= 0) hoursLeft = 24 + hoursLeft;
    
    // Calculate base probability
    int potentialSignalsLeft = MathMax(1, hoursLeft);
    double baseProbability = (double)(MaxDailyTrades - tradesExecutedToday) / potentialSignalsLeft;
    
    // Quality factor (normalized 0-1)
    double qualityFactor = signalQuality / 100.0;
    
    // Calculate final probability
    double finalProbability = baseProbability * (RandomnessFactor + (1 - RandomnessFactor) * qualityFactor);
    finalProbability = MathMin(1.0, finalProbability);
    
    // Random decision
    double randomValue = (double)MathRand() / 32767.0;
    bool decision = (randomValue < finalProbability);
    
    Print("Signal Quality: ", DoubleToString(signalQuality, 1), 
          ", Probability: ", DoubleToString(finalProbability * 100, 1), "%",
          ", Decision: ", decision ? "TAKE" : "SKIP");
    
    return decision;
}

//+------------------------------------------------------------------+
//| Open position                                                    |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE orderType, double signalQuality)
{
    double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    // Calculate position size
    double lots = CalculatePositionSize(orderType);
    if(lots <= 0) return;
    
    // Calculate stop loss and take profit
    double stopLoss = CalculateStopLoss(orderType, price);
    double takeProfit = CalculateTakeProfit(orderType, price, stopLoss);
    
    // Open position
    string comment = StringFormat("SSE_Q%.1f", signalQuality);
    
    if(trade.PositionOpen(Symbol(), orderType, lots, price, stopLoss, takeProfit, comment))
    {
        tradesExecutedToday++;
        SaveDailyCounters();
        
        Print("Position opened: ", EnumToString(orderType), 
              " | Lots: ", DoubleToString(lots, 2),
              " | Price: ", DoubleToString(price, Digits()),
              " | SL: ", DoubleToString(stopLoss, Digits()),
              " | TP: ", DoubleToString(takeProfit, Digits()),
              " | Quality: ", DoubleToString(signalQuality, 1));
    }
    else
    {
        Print("Failed to open position: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate position size                                          |
//+------------------------------------------------------------------+
double CalculatePositionSize(ENUM_ORDER_TYPE orderType)
{
    if(!UsePercentRisk)
        return LotSize;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * RiskPercent / 100.0;
    
    double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double stopLoss = CalculateStopLoss(orderType, price);
    double stopDistance = MathAbs(price - stopLoss);
    
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    
    double lots = (riskAmount / (stopDistance / tickSize * tickValue));
    lots = MathFloor(lots / lotStep) * lotStep;
    
    double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    
    return MathMax(minLot, MathMin(maxLot, lots));
}

//+------------------------------------------------------------------+
//| Calculate stop loss                                              |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice)
{
    double atrArray[1];
    if(CopyBuffer(handleATR, 0, 1, 1, atrArray) <= 0)
        return 0;
    
    double atr = atrArray[0];
    double multiplier = isTrendingMarket ? 2.0 : ATR_StopMultiplier;
    double stopDistance = MathMax(atr * multiplier, MinimumStopPips * Point() * 10);
    
    if(orderType == ORDER_TYPE_BUY)
        return entryPrice - stopDistance;
    else
        return entryPrice + stopDistance;
}

//+------------------------------------------------------------------+
//| Calculate take profit                                            |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss)
{
    // Get Bollinger Band targets
    double upperArray[1], lowerArray[1];
    if(CopyBuffer(handleBB, 1, 1, 1, upperArray) <= 0 ||
       CopyBuffer(handleBB, 2, 1, 1, lowerArray) <= 0)
        return 0;
    
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double minTarget = entryPrice + (orderType == ORDER_TYPE_BUY ? 1 : -1) * stopDistance * RiskRewardRatio;
    
    double bbTarget;
    if(orderType == ORDER_TYPE_BUY)
    {
        bbTarget = upperArray[0];
        return MathMax(bbTarget, minTarget);
    }
    else
    {
        bbTarget = lowerArray[0];
        return MathMin(bbTarget, minTarget);
    }
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) != Symbol()) continue;
        
        ulong ticket = PositionGetInteger(POSITION_TICKET);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Calculate ATR for trailing
        double atrArray[1];
        if(CopyBuffer(handleATR, 0, 1, 1, atrArray) <= 0) continue;
        double atr = atrArray[0];
        
        // Check for break-even move
        double breakEvenTrigger = atr;
        bool shouldMoveToBreakEven = false;
        
        if(posType == POSITION_TYPE_BUY && currentPrice >= openPrice + breakEvenTrigger)
            shouldMoveToBreakEven = true;
        else if(posType == POSITION_TYPE_SELL && currentPrice <= openPrice - breakEvenTrigger)
            shouldMoveToBreakEven = true;
        
        if(shouldMoveToBreakEven && MathAbs(stopLoss - openPrice) > BreakEvenBuffer * Point() * 10)
        {
            double newStopLoss = openPrice + (posType == POSITION_TYPE_BUY ? 1 : -1) * BreakEvenBuffer * Point() * 10;
            if(trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
            {
                Print("Position moved to break-even: ", ticket);
            }
        }
        
        // Check for trailing stop
        double trailTrigger = MathAbs(openPrice - stopLoss) * 1.5;
        double profit = (posType == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
        
        if(profit >= trailTrigger)
        {
            double trailDistance = atr * ATR_TrailMultiplier;
            double newStopLoss;
            
            if(posType == POSITION_TYPE_BUY)
            {
                newStopLoss = currentPrice - trailDistance;
                if(newStopLoss > stopLoss)
                {
                    if(trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
                    {
                        Print("Trailing stop updated for BUY position: ", ticket, " New SL: ", DoubleToString(newStopLoss, Digits()));
                    }
                }
            }
            else
            {
                newStopLoss = currentPrice + trailDistance;
                if(newStopLoss < stopLoss)
                {
                    if(trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
                    {
                        Print("Trailing stop updated for SELL position: ", ticket, " New SL: ", DoubleToString(newStopLoss, Digits()));
                    }
                }
            }
        }
        
        // Partial close at 1:1 R:R if enabled
        if(EnablePartialClose && profit >= MathAbs(openPrice - stopLoss))
        {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "_PARTIAL") == -1) // Not already partially closed
            {
                double currentLots = PositionGetDouble(POSITION_VOLUME);
                double closeVolume = currentLots * PartialClosePercent / 100.0;
                
                if(trade.PositionClosePartial(ticket, closeVolume))
                {
                    Print("Partial close executed: ", ticket, " Volume: ", DoubleToString(closeVolume, 2));
                    // Update comment to mark as partially closed
                    // Note: MT5 doesn't allow comment modification, this is just for logging
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
    tradesExecutedToday = 0;
    SaveDailyCounters();
    Print("Daily counters reset - New trading day started");
}

//+------------------------------------------------------------------+
//| Save daily counters to global variables                         |
//+------------------------------------------------------------------+
void SaveDailyCounters()
{
    GlobalVariableSet(GV_TradesCount, tradesExecutedToday);
    GlobalVariableSet(GV_LastDate, lastTradeDate);
}

//+------------------------------------------------------------------+
//| Restore daily counters from global variables                    |
//+------------------------------------------------------------------+
void RestoreDailyCounters()
{
    if(GlobalVariableCheck(GV_TradesCount))
    {
        tradesExecutedToday = (int)GlobalVariableGet(GV_TradesCount);
        lastTradeDate = (datetime)GlobalVariableGet(GV_LastDate);
        
        // Check if it's a new day
        MqlDateTime dt;
        TimeToStruct(TimeGMT(), dt);
        datetime currentDate = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
        
        if(currentDate != lastTradeDate)
        {
            ResetDailyCounters();
        }
        else
        {
            Print("Daily counters restored: Trades today = ", tradesExecutedToday);
        }
    }
    else
    {
        ResetDailyCounters();
    }
}
