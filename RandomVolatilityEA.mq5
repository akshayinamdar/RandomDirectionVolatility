//+------------------------------------------------------------------+
//|                                           RandomVolatilityEA.mq5 |
//|                                 Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input parameters
input group "=== General Settings ==="
input double RiskPercent = 1.0;              // Risk per trade (% of account)
input int MaxPositions = 2;                  // Maximum open positions
input string TradingStartTime = "03:00";     // Trading start time
input string TradingEndTime = "21:00";       // Trading end time

input group "=== Volatility Settings ==="
input int ATRPeriod = 14;                    // ATR period
input int ATRMAperiod = 20;                  // Moving average period for ATR
input double VolatilityThreshold = 0.8;      // Volatility threshold multiplier

input group "=== Risk Management ==="
input double SLMultiplier = 1.5;             // ATR multiplier for stop loss

//--- Global variables
int atrHandle;
datetime lastTradeTime = 0;
int magicNumber = 123456;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize ATR indicator
    atrHandle = iATR(_Symbol, PERIOD_M1, ATRPeriod);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Error creating ATR indicator");
        return(INIT_FAILED);
    }
      // Seed random number generator using a combination of time and memory address
    // This ensures different seeds even during backtesting
    MathSrand((int)TimeLocal() + (int)TimeCurrent() + (int)GetTickCount() + (int)MQL5InfoInteger(MQL5_MEMORY_USED));
    
    Print("RandomVolatilityEA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    
    Print("RandomVolatilityEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Always check trailing stops
    CheckTrailingStops();
    
    // Check if new bar has formed
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
    
    if(currentBarTime == lastBarTime)
        return;
    
    lastBarTime = currentBarTime;
    
    // Main trading logic
    CheckForTradingOpportunity();
}

//+------------------------------------------------------------------+
//| Check for trading opportunity                                    |
//+------------------------------------------------------------------+
void CheckForTradingOpportunity()
{
    // Check trading hours
    if(!IsWithinTradingHours())
        return;
    
    // Check maximum positions
    if(CountOpenPositions() >= MaxPositions)
        return;
    
    // Check volatility condition
    if(!IsLowVolatility())
        return;
    
    // Prevent multiple trades within same minute
    if(TimeLocal() - lastTradeTime < 60)
        return;
    
    // Execute random trade
    ExecuteRandomTrade();
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeLocal(), timeStruct);
    
    int currentHour = timeStruct.hour;
    int currentMinute = timeStruct.min;
    int currentTimeMinutes = currentHour * 60 + currentMinute;
    
    // Parse start time
    string startParts[];
    StringSplit(TradingStartTime, ':', startParts);
    int startHour = (int)StringToInteger(startParts[0]);
    int startMinute = (int)StringToInteger(startParts[1]);
    int startTimeMinutes = startHour * 60 + startMinute;
    
    // Parse end time
    string endParts[];
    StringSplit(TradingEndTime, ':', endParts);
    int endHour = (int)StringToInteger(endParts[0]);
    int endMinute = (int)StringToInteger(endParts[1]);
    int endTimeMinutes = endHour * 60 + endMinute;
    
    return (currentTimeMinutes >= startTimeMinutes && currentTimeMinutes <= endTimeMinutes);
}

//+------------------------------------------------------------------+
//| Count open positions for this EA                                |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == magicNumber)
            {
                count++;
            }
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Check for low volatility condition                              |
//+------------------------------------------------------------------+
bool IsLowVolatility()
{
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    
    // Get ATR values
    if(CopyBuffer(atrHandle, 0, 0, ATRMAperiod + 1, atrBuffer) < 0)
    {
        Print("Error copying ATR buffer");
        return false;
    }
    
    double currentATR = atrBuffer[0];
    double avgATR = 0;
    
    // Calculate average ATR over specified period
    for(int i = 1; i <= ATRMAperiod; i++)
    {
        avgATR += atrBuffer[i];
    }
    avgATR /= ATRMAperiod;
    
    // Check if current ATR is below threshold
    bool lowVol = (currentATR < avgATR * VolatilityThreshold);
    
    if(lowVol)
    {
        Print("Low volatility detected. Current ATR: ", DoubleToString(currentATR, 5), 
              " Average ATR: ", DoubleToString(avgATR, 5));
    }
    
    return lowVol;
}

//+------------------------------------------------------------------+
//| Execute random trade                                             |
//+------------------------------------------------------------------+
void ExecuteRandomTrade()
{    // Generate random direction (0 = BUY, 1 = SELL)
    // Add extra randomization by using tick count and memory usage
    int extraRandom = (int)GetTickCount() + (int)MQL5InfoInteger(MQL5_MEMORY_USED);
    int direction = (MathRand() + extraRandom) % 2;
    
    // Get current ATR for stop loss calculation
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) < 0)
    {
        Print("Error getting ATR for trade execution");
        return;
    }
      double currentATR = atrBuffer[0];
    double stopLossSize = currentATR * SLMultiplier;
    
    // Calculate position size
    double lotSize = CalculateLotSize(stopLossSize);
    if(lotSize <= 0)
    {
        Print("Invalid lot size calculated");
        return;
    }
    
    // Get current prices
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lotSize;
    request.magic = magicNumber;
    request.deviation = 3;
      if(direction == 0) // BUY
    {
        request.type = ORDER_TYPE_BUY;
        request.price = ask;
        request.sl = bid - stopLossSize;
        request.tp = 0; // No take profit
        
        Print("Executing RANDOM BUY trade. Volume: ", lotSize, " SL: ", request.sl);
    }
    else // SELL
    {
        request.type = ORDER_TYPE_SELL;
        request.price = bid;
        request.sl = ask + stopLossSize;
        request.tp = 0; // No take profit
        
        Print("Executing RANDOM SELL trade. Volume: ", lotSize, " SL: ", request.sl);
    }
    
    // Send order
    if(OrderSend(request, result))
    {
        Print("Trade executed successfully. Ticket: ", result.order);
        lastTradeTime = TimeLocal();
    }
    else
    {
        Print("Trade execution failed. Error: ", GetLastError(), " Return code: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                     |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossSize)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * RiskPercent / 100.0;
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickValue == 0 || tickSize == 0)
    {
        Print("Error getting symbol tick information");
        return 0;
    }
    
    // Calculate risk per lot
    double riskPerLot = (stopLossSize / tickSize) * tickValue;
    
    if(riskPerLot <= 0)
    {
        Print("Invalid risk per lot calculation");
        return 0;
    }
    
    // Calculate lot size
    double lotSize = riskAmount / riskPerLot;
    
    // Get symbol trading specifications
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    // Normalize lot size
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
    
    Print("Calculated lot size: ", lotSize, " Risk amount: ", riskAmount, " Stop loss size: ", stopLossSize);
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Check and update trailing stops for open positions               |
//+------------------------------------------------------------------+
void CheckTrailingStops()
{
    // Check if enough time has passed since last check
    static datetime lastTrailingCheck = 0;
    if(TimeLocal() - lastTrailingCheck < 30) return;
    lastTrailingCheck = TimeLocal();
    
    // Get current ATR value
    double atrBuffer[];
    ArraySetAsSeries(atrBuffer, true);
    
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) < 0)
    {
        Print("Error getting ATR for trailing stop");
        return;
    }
    
    double currentATR = atrBuffer[0];
    
    // Use existing SLMultiplier for trailing distance
    double trailingDistance = currentATR * SLMultiplier;
    
    // Use VolatilityThreshold to determine activation distance
    // When price moves in favor by this much, start trailing
    double activationDistance = currentATR * VolatilityThreshold;
    
    // Current market prices
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check all open positions
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        
        // Only process our positions for this symbol
        if(PositionGetString(POSITION_SYMBOL) != _Symbol || 
           PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
           
        double positionSL = PositionGetDouble(POSITION_SL);
        double positionTP = PositionGetDouble(POSITION_TP);
        double positionOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        // Calculate new SL level
        double newSL = 0.0;
        bool modifyNeeded = false;
        
        if(positionType == POSITION_TYPE_BUY)
        {
            // For BUY positions, only trail if price has moved enough
            if(bid - positionOpenPrice >= activationDistance)
            {
                newSL = bid - trailingDistance;
                // Only modify if new SL is higher than current SL
                modifyNeeded = (positionSL == 0 || newSL > positionSL + _Point);
            }
        }
        else // SELL position
        {
            // For SELL positions, only trail if price has moved enough
            if(positionOpenPrice - ask >= activationDistance)
            {
                newSL = ask + trailingDistance;
                // Only modify if new SL is lower than current SL
                modifyNeeded = (positionSL == 0 || newSL < positionSL - _Point);
            }
        }
        
        // If modification is needed, update the stop loss
        if(modifyNeeded)
        {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.symbol = _Symbol;
            request.position = ticket;
            request.sl = NormalizeDouble(newSL, _Digits);
            request.tp = positionTP;  // Keep TP the same
            
            if(OrderSend(request, result))
            {
                Print("Trailing stop updated for ticket #", ticket, 
                      " New SL: ", request.sl, " ATR: ", currentATR);
            }
            else
            {
                Print("Failed to update trailing stop. Error: ", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
