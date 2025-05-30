# Selective Signal Trading EA - Requirements Document

## Project Overview

### Core Concept
Design an Expert Advisor (EA) that acknowledges no technical indicator works 100% of the time. Instead of taking every signal, the EA will:
- Limit trades to 1-2 positions per day maximum
- Randomly skip signals to avoid overtrading
- Focus on signal quality over quantity
- Balance randomness with intelligent signal assessment

### Philosophy
- Most indicators work ~80% of the time
- Selective trading can improve overall performance
- Random skipping prevents curve-fitting to specific market conditions
- Quality over quantity approach

## Technical Specifications

### Timeframe
- **Primary**: H1 (1-hour) charts
- **Rationale**: 
  - Sufficient signals for 1-2 daily trades
  - Good balance between signal quality and quantity
  - Reduces noise compared to lower timeframes
  - Better volume profile for analysis

### Entry Strategy: Bollinger Bands + RSI + Volume

#### Core Indicators
1. **Bollinger Bands**
   - Period: 20
   - Standard Deviation: 2.0 (ranging markets) / 2.5-3.0 (trending markets)
   - Adaptive based on market conditions

2. **RSI (Relative Strength Index)**
   - Period: 14
   - Overbought: 70
   - Oversold: 30

3. **Volume Analysis**
   - Compare current volume to 20-period average
   - Minimum volume ratio: 1.2x average

#### Market Condition Detection
- **ADX Indicator** for trend strength detection
- **Band Width Measurement** for volatility assessment
- **Automatic Strategy Adjustment**:
  - Ranging Markets: Trade band extremes with mean reversion
  - Trending Markets: Trade pullbacks to middle band

### Entry Conditions

#### Buy Signal
- Price touches or breaks below lower Bollinger Band
- RSI < 30 (oversold condition)
- Volume > 1.2x recent average
- Signal quality assessment passes minimum threshold

#### Sell Signal
- Price touches or breaks above upper Bollinger Band
- RSI > 70 (overbought condition)
- Volume > 1.2x recent average
- Signal quality assessment passes minimum threshold

## Signal Quality Assessment System

### Quality Score Calculation (0-100 scale)
1. **Bollinger Band Deviation Score (40% weight)**
   - Higher deviation from mean = higher score
   - Formula: `Math.Min(100, deviation * 25)`

2. **RSI Extremity Score (40% weight)**
   - For buy signals: Score = `100 - (RSI * 2)` when RSI ≤ 30
   - For sell signals: Score = `(RSI - 50) * 2` when RSI ≥ 70
   - Neutral RSI (30-70) = 0 score

3. **Volume Score (20% weight)**
   - Higher relative volume = higher score
   - Formula: `Math.Min(100, volumeRatio * 50)`

### Minimum Quality Threshold
- Default: 60/100
- Configurable parameter
- Signals below threshold are automatically rejected

## Random Selection Algorithm

### Weighted Probability Approach
Combines signal quality with controlled randomness:

```
finalProbability = baseProbability * (randomnessFactor + (1-randomnessFactor) * qualityFactor)
```

#### Key Components
1. **Base Probability**
   - Calculated based on remaining trades for the day
   - Considers hours left in trading session
   - Formula: `(maxDailyTrades - tradesExecutedToday) / potentialSignalsLeft`

2. **Quality Factor**
   - Signal quality score normalized to 0-1 range
   - Higher quality signals get higher probability

3. **Randomness Factor (0-1)**
   - 0.0 = Always select highest quality signals
   - 1.0 = Completely random selection
   - 0.5 = Balanced approach (recommended)

## Configuration Parameters

### Trading Limits
- `MaxDailyTrades`: 2 (default)
- `MinQualityThreshold`: 60 (default, 0-100 scale)
- `RandomnessFactor`: 0.5 (default, 0-1 range)

### Indicator Settings
- `BB_Period`: 20
- `BB_Deviation`: 2.0 (ranging) / 2.5-3.0 (trending)
- `RSI_Period`: 14
- `Volume_Period`: 20 (for average calculation)
- `Volume_MinRatio`: 1.2

### Market Condition Settings
- `ADX_Period`: 14
- `ADX_TrendThreshold`: 25
- `BandWidth_ContractingThreshold`: 0.5 (adaptive to 20-day average of band width)

### Trading Hours Settings
- `StartHour`: 8 (GMT, start of trading session)
- `EndHour`: 16 (GMT, end of trading session)
- `EnableSessionFiltering`: true (default)

## Risk Management Requirements

### Position Sizing
- Fixed lot size or percentage-based (configurable)
- Maximum risk per trade: 1-2% of account

### Stop Loss Strategy: ATR-Based Dynamic Stops
**Primary Approach: Average True Range (ATR) Based**
- Use 14-period ATR to set dynamic stop distances
- For BUY trades: Entry Price - (ATR × 1.5)
- For SELL trades: Entry Price + (ATR × 1.5)
- Minimum stop distance: 15 pips (to avoid normal market noise)

**Advantages:**
- Automatically adapts to current market volatility
- Wider stops during volatile periods, tighter during calm periods
- Complements Bollinger Bands approach (both adapt to volatility)
- Statistically sound method based on actual market movement
- Works equally well in trending and ranging conditions

### Take Profit Strategy: Combined BB Target + Risk-Reward
**Multi-Level Approach:**

1. **Primary Target: Opposite Bollinger Band**
   - For BUY trades: Upper Bollinger Band level
   - For SELL trades: Lower Bollinger Band level

2. **Minimum Risk-Reward Enforcement:**
   - Ensure target provides at least 1:2 risk-reward ratio
   - If opposite BB doesn't provide 1:2 R:R, extend target to achieve it
   - Calculate: Minimum target = Entry ± (Stop distance × 2)

3. **Target Selection Logic:**
   - For BUY: `TakeProfit = Max(UpperBB, EntryPrice + (StopDistance × 2))`
   - For SELL: `TakeProfit = Min(LowerBB, EntryPrice - (StopDistance × 2))`

### Advanced Risk Management Features

#### Trailing Stop System
- **Activation:** Once trade reaches 1.5× stop distance in profit
- **Trail Distance:** ATR × 1.0 (tighter than initial stop)
- **Purpose:** Lock in partial profits while allowing extended moves

#### Break-Even Automation
- **Trigger:** Price moves 1× ATR in favorable direction
- **Action:** Move stop to entry price + small buffer (3-5 pips)
- **Benefit:** Secures position against reversals while giving room for price action

#### Partial Position Management (Optional)
- **First Target:** Close 50% of position at 1:1 risk-reward ratio
- **Remaining Position:** Move stop to break-even, let run to full target
- **Alternative:** Use trailing stop on remainder for extended moves

#### Market Condition Adjustments
**For Trending Markets (ADX > 25):**
- Wider initial stops: ATR × 2.0
- Higher profit targets: 1:3 risk-reward ratio
- More aggressive trailing (ATR × 0.8)

**For Ranging Markets (ADX ≤ 25):**
- Standard stops: ATR × 1.5
- Conservative targets: 1:2 risk-reward ratio
- Standard trailing (ATR × 1.0)

### Risk Management Parameters
- `ATR_Period`: 14
- `ATR_StopMultiplier`: 1.5 (ranging) / 2.0 (trending)
- `ATR_TrailMultiplier`: 1.0
- `MinimumStopPips`: 15
- `RiskRewardRatio`: 2.0 (minimum)
- `BreakEvenBuffer`: 5 (pips)
- `PartialClosePercent`: 50 (optional)

### Implementation Parameters
- `DeterministicMode`: false (for backtesting reproducibility)
- `EnablePartialClose`: false (optional position management)
- `Platform`: MT5 (single compact .mq5 file)
- `VolumeType`: Tick Volume (more readily available)

### Daily Limits
- Maximum 2 trades per day
- No new trades after daily limit reached
- Reset counter at start of new trading day
- Emergency stop: Halt trading if daily loss exceeds 4% of account

## Implementation Architecture

### Platform & Structure
- **Target Platform**: MetaTrader 5 (MT5)
- **File Structure**: Single compact .mq5 file
- **Scope**: Single currency pair per EA instance
- **Volume Data**: Tick volume analysis

### Signal Processing Approach
- **Evaluation Timing**: At close of each H1 bar for clean data
- **Multiple Signals**: Keep highest quality signal within same hour
- **Market Hours**: Configurable trading session filtering (8:00-16:00 GMT default)
- **Weekend Handling**: Reset daily counters at 00:00 server time

### Data Persistence Strategy
- **Daily Trade Counts**: Saved to GlobalVariables with timestamp validation
- **Randomness**: Deterministic mode available for backtesting reproducibility
- **Market Condition Cache**: Updated at each H1 bar close

### Main Components
1. **SignalGenerator**: Detects BB + RSI + Volume signals
2. **SignalEvaluator**: Calculates quality scores
3. **MarketConditionDetector**: Identifies trending vs ranging markets
4. **TradeSelector**: Implements random selection algorithm
5. **PositionManager**: Handles trade execution and management
6. **DailyTracker**: Monitors daily trade count and resets

### Key Functions
- `OnTick()`: Main entry point for signal processing
- `OnInit()`: Initialize parameters and restore daily counters
- `AssessSignalQuality()`: Calculates 0-100 quality score
- `ShouldTakeTrade()`: Implements probability-based selection
- `DetectMarketCondition()`: ADX and band width analysis
- `AdjustParameters()`: Dynamic parameter adjustment
- `ManagePositions()`: Handle trailing stops and position management
- `IsWithinTradingHours()`: Check if current time allows trading
- `ResetDailyCounters()`: Reset counters for new trading day

## Testing & Optimization Requirements

### Backtesting Scope
- Multiple currency pairs (major pairs recommended)
- Different market conditions (trending, ranging, volatile)
- Minimum 1-2 years of historical data
- Various randomness factor settings

### Performance Metrics
- Win rate comparison: All signals vs. Selected signals
- Profit factor improvement
- Maximum drawdown reduction
- Sharpe ratio enhancement
- Monthly consistency

### Parameter Optimization
- Randomness factor (0.3 - 0.7 range)
- Quality threshold (50 - 80 range)
- Maximum daily trades (1 - 3 range)
- BB deviation settings for different conditions

## Monitoring & Logging

### Built-in Logging
- Signal generation and quality scores logged to MT5 journal
- Selection decisions (taken/skipped) with reasons
- Daily trade count and market condition status
- Position management actions (trailing stops, break-even moves)

### Performance Tracking
- Daily trade count via global variables
- Quality scores of taken vs. skipped signals in journal
- Market condition detection accuracy
- Parameter adjustment history

### Alert System
- Daily trade limit reached notification
- Unusually low signal quality periods
- System errors or initialization failures
- Position management alerts (break-even, trailing activation)

## Future Enhancement Ideas

### Advanced Features
1. **Multi-timeframe Confluence** (Future)
   - D1 trend direction filter
   - H4 intermediate trend confirmation
   - H1 precise entry timing

2. **Machine Learning Integration** (Future)
   - Historical signal success rate analysis
   - Dynamic quality threshold adjustment
   - Pattern recognition enhancement

3. **Enhanced Market Session Awareness** (Future)
   - Time-based signal weighting
   - Session-specific parameters
   - Holiday detection filters

4. **Adaptive Randomness** (Future)
   - Increase randomness during uncertain periods
   - Reduce randomness during high-confidence periods
   - Market volatility-based adjustment

5. **Multi-Currency Support** (Future)
   - Portfolio-based EA managing multiple pairs
   - Cross-pair correlation analysis
   - Global daily limits across all pairs

## Success Criteria

### Primary Goals
- Reduce overtrading while maintaining profitability
- Improve risk-adjusted returns compared to taking all signals
- Achieve consistent monthly performance
- Minimize emotional decision-making through systematic approach

### Measurable Targets
- Win rate: >60%
- Profit factor: >1.5
- Maximum drawdown: <10%
- Monthly positive return consistency: >80%
- Sharpe ratio: >1.0

---

*Document Version: 1.0*  
*Created: May 30, 2025*  
*Author: GitHub Copilot - EA Development Assistant*
