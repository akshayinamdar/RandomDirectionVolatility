Pure Random Direction Volatility Expansion EA
Perfect! Let's design the EA with a purely random approach after volatility contraction. Here's the implementation plan:

Core Strategy
Monitor volatility using ATR(14) on M1 timeframe
When volatility drops below 80% of 20-period average, prepare for entry
Randomly choose direction (50/50 chance for BUY or SELL)
Use ATR-based stop loss and fixed 8-point target (adjustable per instrument)

if(lowVolatility && IsWithinTradingHours() && CountOpenPositions() < MaxPositions) {
    // Generate random number for direction (0 or 1)
    int direction = MathRand() % 2;
    
    // Calculate position size based on risk
    double stopLossSize = currentATR * SLMultiplier;
    double lotSize = CalculateLotSize(stopLossSize);
    
    // Get symbol-specific TP
    double takeProfit = GetSymbolTakeProfit();
    
    // Open position in random direction
    if(direction == 0) {
        // BUY
        double sl = Bid - stopLossSize;
        double tp = Bid + takeProfit * Point;
        OrderSend(Symbol(), OP_BUY, lotSize, Ask, 3, sl, tp);
    } else {
        // SELL
        double sl = Ask + stopLossSize;
        double tp = Ask - takeProfit * Point;
        OrderSend(Symbol(), OP_SELL, lotSize, Bid, 3, sl, tp);
    }
}