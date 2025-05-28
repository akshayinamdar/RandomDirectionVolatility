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
input int TradingStartHour = 3;              // Trading session start hour (0-23)
input int TradingStartMinute = 0;            // Trading session start minute (0-59)
input int TradingEndHour = 21;               // Trading session end hour (0-23)
input int TradingEndMinute = 0;              // Trading session end minute (0-59)

input group "=== Price Action Settings ==="
input int ChannelPeriod = 10;                // Period for price channel calculation
input int ChannelMAPeriod = 20;              // Moving average period for channel width
input double ChannelThreshold = 0.7;         // Channel contraction threshold multiplier
input double MinChannelWidth = 5.0;          // Minimum channel width filter (points)
input double MeanReversionBias = 20.0;       // Mean reversion bias strength (0-50%)

input group "=== Risk Management ==="
input double SLMultiplier = 1.5;             // Channel width multiplier for stop loss

input group "=== Take Profit Settings ==="
input double TPPoints_EURUSD = 8.0;          // Take profit for EURUSD (points)
input double TPPoints_GBPUSD = 8.0;          // Take profit for GBPUSD (points)
input double TPPoints_USDJPY = 8.0;          // Take profit for USDJPY (points)
input double TPPoints_BTCUSD = 80.0;         // Take profit for BTCUSD (points)
input double TPPoints_Default = 8.0;         // Default take profit (points)

//--- Global variables
datetime lastTradeTime = 0;
int magicNumber = 123456;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Seed random number generator using a combination of time and memory address
    // This ensures different seeds even during backtesting
    MathSrand((int)TimeLocal() + (int)TimeCurrent() + (int)GetTickCount() + (int)MQL5InfoInteger(MQL5_MEMORY_USED));
    
    Print("RandomVolatilityEA (Price Channel Version) initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
      // Check price channel contraction condition
    if(!IsChannelContracted())
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
//| Check if current time is within trading hours                   |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
    MqlDateTime timeStruct;
    TimeToStruct(TimeLocal(), timeStruct);
    
    int currentHour = timeStruct.hour;
    int currentMinute = timeStruct.min;
    int currentTimeMinutes = currentHour * 60 + currentMinute;
    
    // Calculate session times in minutes
    int startTimeMinutes = TradingStartHour * 60 + TradingStartMinute;
    int endTimeMinutes = TradingEndHour * 60 + TradingEndMinute;
    
    // Handle cases where trading session spans midnight
    if(startTimeMinutes <= endTimeMinutes) {
        // Normal case (e.g., 3:00-21:00)
        return (currentTimeMinutes >= startTimeMinutes && currentTimeMinutes <= endTimeMinutes);
    } else {
        // Overnight case (e.g., 22:00-3:00)
        return (currentTimeMinutes >= startTimeMinutes || currentTimeMinutes <= endTimeMinutes);
    }
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
//| Check for channel contraction condition                         |
//+------------------------------------------------------------------+
bool IsChannelContracted()
{
    // Get current channel width using existing function
    double currentChannelWidth = GetCurrentChannelWidth();
    if(currentChannelWidth <= 0)
    {
        Print("Error getting current channel width");
        return false;
    }
    
    if(currentChannelWidth < MinChannelWidth * _Point)
    {
        Print("Market too quiet. Channel width: ", currentChannelWidth, 
            " Minimum required: ", MinChannelWidth * _Point);
        return false;
    }

    double highBuffer[], lowBuffer[];
    ArraySetAsSeries(highBuffer, true);
    ArraySetAsSeries(lowBuffer, true);
    
    // Get high and low data for historical average calculation
    if(CopyHigh(_Symbol, PERIOD_M1, 0, ChannelMAPeriod + ChannelPeriod, highBuffer) < 0 ||
       CopyLow(_Symbol, PERIOD_M1, 0, ChannelMAPeriod + ChannelPeriod, lowBuffer) < 0)
    {
        Print("Error copying price data");
        return false;
    }
    
    // Calculate average channel width over longer period
    double avgChannelWidth = 0;
    int count = 0;
    
    for(int i = ChannelPeriod; i < ChannelMAPeriod + ChannelPeriod; i += ChannelPeriod)
    {
        double periodHigh = highBuffer[ArrayMaximum(highBuffer, i, ChannelPeriod)];
        double periodLow = lowBuffer[ArrayMinimum(lowBuffer, i, ChannelPeriod)];
        double periodChannelWidth = periodHigh - periodLow;
        
        avgChannelWidth += periodChannelWidth;
        count++;
    }
    
    if(count > 0)
        avgChannelWidth /= count;
    else
        return false;
    
    // Check if current channel width is below threshold
    bool contracted = (currentChannelWidth < avgChannelWidth * ChannelThreshold);
    
    if(contracted)
    {
        Print("Channel contraction detected. Current width: ", DoubleToString(currentChannelWidth, 5), 
              " Average width: ", DoubleToString(avgChannelWidth, 5));
    }
    
    return contracted;
}

//+------------------------------------------------------------------+
//| Execute random trade                                             |
//+------------------------------------------------------------------+
void ExecuteRandomTrade()
{
    // Calculate price position within channel for mean reversion bias
    double channelPosition = CalculatePriceInChannelPosition();
      // Apply mean reversion bias: favor opposite direction when price is at extremes
    // When channelPosition is negative (bottom of channel), favor BUY
    // When channelPosition is positive (top of channel), favor SELL
    int biasPercentage = 50 - (int)(channelPosition * MeanReversionBias); // Use configurable bias strength
    
    // Generate random number with bias
    int extraRandom = (int)GetTickCount() + (int)MQL5InfoInteger(MQL5_MEMORY_USED);
    int randomValue = (MathRand() + extraRandom) % 100;
    int direction = (randomValue < biasPercentage) ? 0 : 1; // 0=BUY, 1=SELL
      Print("Channel position: ", DoubleToString(channelPosition, 3), 
          " Bias percentage for BUY: ", biasPercentage, "% (Bias strength: ", MeanReversionBias, "%) Random value: ", randomValue,
          " Direction: ", (direction == 0 ? "BUY" : "SELL"));
    
    // Get current channel width for stop loss calculation
    double currentChannelWidth = GetCurrentChannelWidth();
    if(currentChannelWidth <= 0)
    {
        Print("Error getting channel width for trade execution");
        return;
    }
    
    double stopLossSize = currentChannelWidth * SLMultiplier;
    
    // Get symbol-specific take profit
    double takeProfit = GetSymbolTakeProfit();
    
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
        request.tp = bid + takeProfit * _Point;
        
        Print("Executing RANDOM BUY trade. Volume: ", lotSize, " SL: ", request.sl, " TP: ", request.tp);
    }
    else // SELL
    {
        request.type = ORDER_TYPE_SELL;
        request.price = bid;
        request.sl = ask + stopLossSize;
        request.tp = ask - takeProfit * _Point;
        
        Print("Executing RANDOM SELL trade. Volume: ", lotSize, " SL: ", request.sl, " TP: ", request.tp);
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
//| Get current channel width                                       |
//+------------------------------------------------------------------+
double GetCurrentChannelWidth()
{
    double highBuffer[], lowBuffer[];
    ArraySetAsSeries(highBuffer, true);
    ArraySetAsSeries(lowBuffer, true);
    
    // Get high and low data for current channel period
    if(CopyHigh(_Symbol, PERIOD_M1, 0, ChannelPeriod, highBuffer) < 0 ||
       CopyLow(_Symbol, PERIOD_M1, 0, ChannelPeriod, lowBuffer) < 0)
    {
        Print("Error copying price data for channel width calculation");
        return 0;
    }
    
    // Calculate current channel width
    double currentHigh = highBuffer[ArrayMaximum(highBuffer, 0, ChannelPeriod)];
    double currentLow = lowBuffer[ArrayMinimum(lowBuffer, 0, ChannelPeriod)];
    double channelWidth = currentHigh - currentLow;
    
    return channelWidth;
}

//+------------------------------------------------------------------+
//| Get symbol-specific take profit                                 |
//+------------------------------------------------------------------+
double GetSymbolTakeProfit()
{
    string symbol = _Symbol;
    
    if(StringFind(symbol, "EURUSD") >= 0)
        return TPPoints_EURUSD;
    else if(StringFind(symbol, "GBPUSD") >= 0)
        return TPPoints_GBPUSD;
    else if(StringFind(symbol, "USDJPY") >= 0)
        return TPPoints_USDJPY;
    else if(StringFind(symbol, "BTCUSD") >= 0)
        return TPPoints_BTCUSD;
    else
        return TPPoints_Default;
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
//| Calculate price position within the channel                      |
//+------------------------------------------------------------------+
double CalculatePriceInChannelPosition()
{
    // Use GetCurrentChannelWidth for consistent channel calculation
    double channelWidth = GetCurrentChannelWidth();
    if(channelWidth <= 0)
    {
        Print("Error getting channel width for price position calculation");
        return 0; // Return middle of channel on error
    }
    
    double highBuffer[], lowBuffer[];
    ArraySetAsSeries(highBuffer, true);
    ArraySetAsSeries(lowBuffer, true);
    
    // Get high and low data for channel period
    if(CopyHigh(_Symbol, PERIOD_M1, 0, ChannelPeriod, highBuffer) < 0 ||
       CopyLow(_Symbol, PERIOD_M1, 0, ChannelPeriod, lowBuffer) < 0)
    {
        Print("Error copying price data for price position calculation");
        return 0; // Return middle of channel on error
    }
    
    // Find highest high and lowest low
    double highestHigh = highBuffer[ArrayMaximum(highBuffer, 0, ChannelPeriod)];
    double lowestLow = lowBuffer[ArrayMinimum(lowBuffer, 0, ChannelPeriod)];
    
    // Get current price (use close price)
    double currentPrice = iClose(_Symbol, PERIOD_M1, 0);
    
    // Calculate position within channel (0 to 1)
    double relativePosition = (currentPrice - lowestLow) / channelWidth;
    
    // Convert to -1 to 1 range (bottom to top)
    double normalizedPosition = (relativePosition * 2) - 1;
    
    Print("Price position in channel: ", DoubleToString(normalizedPosition, 3), 
          " (", DoubleToString(relativePosition * 100, 1), "% from bottom)");
    
    return normalizedPosition;
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
    
    // Get current channel width for trailing calculations
    double currentChannelWidth = GetCurrentChannelWidth();
    if(currentChannelWidth <= 0)
    {
        Print("Error getting channel width for trailing stop");
        return;
    }
    
    // Use existing SLMultiplier for trailing distance
    double trailingDistance = currentChannelWidth * SLMultiplier;
    
    // Use ChannelThreshold to determine activation distance
    // When price moves in favor by this much, start trailing
    double activationDistance = currentChannelWidth * ChannelThreshold;
    
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
                      " New SL: ", request.sl, " Channel Width: ", currentChannelWidth);
            }
            else
            {
                Print("Failed to update trailing stop. Error: ", GetLastError());
            }
        }
    }
}

//+------------------------------------------------------------------+
