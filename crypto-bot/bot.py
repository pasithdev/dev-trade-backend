import time
import os
import logging
from dotenv import load_dotenv
from backend_client import BackendClient
from binance_client import BinanceFuturesClient

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Load config
load_dotenv()
BINANCE_API_KEY = os.getenv("BINANCE_API_KEY")
BINANCE_API_SECRET = os.getenv("BINANCE_API_SECRET")
BINANCE_TESTNET = os.getenv("BINANCE_TESTNET", "True").lower() == "true"
BACKEND_URL = os.getenv("BACKEND_URL", "http://127.0.0.1:8080")

SYMBOL = os.getenv("SYMBOL", "BTCUSDT")
TRADE_USDT_AMOUNT = float(os.getenv("TRADE_USDT_AMOUNT", "50"))
POLL_INTERVAL_SEC = int(os.getenv("POLL_INTERVAL_SEC", "5"))
TARGET_PROFIT_PERCENT = float(os.getenv("TARGET_PROFIT_PERCENT", "1.5"))
SWING_BARS = int(os.getenv("SWING_BARS", "20"))
TIMEFRAME = os.getenv("TIMEFRAME", "1m")
LEVERAGE = int(os.getenv("LEVERAGE", "10"))

# Globals for state tracking
g_pending_setup = -1  # -1=None, 0=BUY, 1=SELL
g_pending_signal_id = 0
g_has_active_order = False
g_active_order_type = -1 # 0=BUY, 1=SELL
g_last_signal_id = 0
g_active_entry_price = 0.0  # Track entry price for profit logging

backend = BackendClient(BACKEND_URL)
binance = BinanceFuturesClient(BINANCE_API_KEY, BINANCE_API_SECRET, BINANCE_TESTNET)


def reset_close_signals(signal: dict, pos_type: int):
    """Resets signals that trigger a close condition to avoid looping on them."""
    if pos_type == 0:  # BUY position
        if signal.get('fvg') == "FVG_BEAR": backend.reset_signal("fvg", SYMBOL, "fvg")
        if signal.get('ob') == "OB_BEAR":   backend.reset_signal("ob", SYMBOL, "ob")
        if signal.get('bb') == "BB_BEAR":   backend.reset_signal("bb", SYMBOL, "bb")
        if signal.get('rb') == "RB_BEAR":   backend.reset_signal("rb", SYMBOL, "rb")
    else:  # SELL position
        if signal.get('fvg') == "FVG_BULL": backend.reset_signal("fvg", SYMBOL, "fvg")
        if signal.get('ob') == "OB_BULL":   backend.reset_signal("ob", SYMBOL, "ob")
        if signal.get('bb') == "BB_BULL":   backend.reset_signal("bb", SYMBOL, "bb")
        if signal.get('rb') == "RB_BULL":   backend.reset_signal("rb", SYMBOL, "rb")

def reset_entry_signals():
    """Resets MACD signals so we don't re-enter immediately."""
    backend.reset_signal("macd_hist1", SYMBOL)
    backend.reset_signal("macd_hist2", SYMBOL)

def should_close_buy(signal: dict) -> bool:
    if signal.get('fvg') == "FVG_BEAR" or signal.get('ob') == "OB_BEAR" or signal.get('bb') == "BB_BEAR" or signal.get('rb') == "RB_BEAR":
        logger.info(f"Close BUY condition met -> fvg: {signal.get('fvg')} | ob: {signal.get('ob')} | bb: {signal.get('bb')} | rb: {signal.get('rb')}")
        return True
    return False

def should_close_sell(signal: dict) -> bool:
    if signal.get('fvg') == "FVG_BULL" or signal.get('ob') == "OB_BULL" or signal.get('bb') == "BB_BULL" or signal.get('rb') == "RB_BULL":
        logger.info(f"Close SELL condition met -> fvg: {signal.get('fvg')} | ob: {signal.get('ob')} | bb: {signal.get('bb')} | rb: {signal.get('rb')}")
        return True
    return False

def calculate_profit_percent(entry_price: float, current_price: float, pos_type: str) -> float:
    if pos_type == 'BUY':
        return ((current_price - entry_price) / entry_price) * 100.0
    else:
        return ((entry_price - current_price) / entry_price) * 100.0

def reset_cycle(reason: str):
    """
    Resets all cycle state variables after a position is closed.
    Equivalent to the cycle reset in MQ5's OnTradeTransaction().
    """
    global g_has_active_order, g_active_order_type, g_last_signal_id, g_active_entry_price
    g_has_active_order = False
    g_active_order_type = -1
    g_last_signal_id = 0
    g_active_entry_price = 0.0
    logger.info(f"Cycle reset ({reason}). Ready for next signal.")

def handle_position_closed():
    """
    Handles the case when a tracked position disappears from Binance.
    This is the Python equivalent of OnTradeTransaction() in the MQ5 EA.
    
    Detects:
    - Stop Loss hit (STOP_MARKET order filled)
    - Take Profit hit (TAKE_PROFIT_MARKET order filled)
    - Manual close by user
    - Closed by bot
    
    Always updates close_status='closed' in the database with retry logic.
    """
    global g_last_signal_id

    # Determine WHY the position was closed (like DEAL_REASON_SL, etc. in MQ5)
    reason = binance.get_close_reason(SYMBOL)
    
    # Calculate final profit if we tracked the entry price
    profit_str = ""
    if g_active_entry_price > 0:
        current_price = binance.get_current_price(SYMBOL)
        if current_price > 0:
            pos_type = "BUY" if g_active_order_type == 0 else "SELL"
            profit_pct = calculate_profit_percent(g_active_entry_price, current_price, pos_type)
            profit_str = f" | Estimated P/L: {profit_pct:.2f}%"

    logger.info("=== Position Closed Detected ===")
    logger.info(f"   Reason: {reason}")
    logger.info(f"   Signal ID: {g_last_signal_id}{profit_str}")
    
    # Update database close_status to 'closed' (with retry)
    logger.info(f"Updating close_status='closed' for signal_id={g_last_signal_id} (Reason: {reason})")
    backend.update_signal_status(g_last_signal_id, "closed")
    
    # Reset cycle
    reset_cycle(reason)

def main_loop():
    global g_pending_setup, g_pending_signal_id, g_has_active_order, g_active_order_type, g_last_signal_id, g_active_entry_price
    
    logger.info("Bot started. Setting leverage and polling backend...")
    binance.set_leverage(SYMBOL, LEVERAGE)
    
    while True:
        try:
            time.sleep(POLL_INTERVAL_SEC)
            
            # ============================================================
            # STEP 1: Check if tracked position was closed externally
            #         (SL hit, TP hit, manual close by user)
            #         This is the Python equivalent of OnTradeTransaction()
            # ============================================================
            if g_has_active_order:
                pos = binance.get_open_position(SYMBOL)
                if pos is None:
                    # Position is gone! Detect reason and update DB
                    handle_position_closed()
                    continue
            
            # ============================================================
            # STEP 2: Read signal from backend
            # ============================================================
            signal = backend.get_latest_signal(SYMBOL)
            if not signal:
                continue
                
            signal_id = signal.get('signalId', 0)
            if signal_id == 0:
                continue

            # ============================================================
            # STEP 3: If active position exists, check for close logic
            # ============================================================
            if g_has_active_order:
                pos = binance.get_open_position(SYMBOL)
                
                # Double-check: position might have closed between step 1 and here
                if pos is None:
                    handle_position_closed()
                    continue
                
                should_close = False
                if g_active_order_type == 0:
                    should_close = should_close_buy(signal)
                elif g_active_order_type == 1:
                    should_close = should_close_sell(signal)
                    
                if should_close:
                    current_price = binance.get_current_price(SYMBOL)
                    profit_pct = calculate_profit_percent(pos['entry_price'], current_price, pos['type'])
                    
                    if TARGET_PROFIT_PERCENT > 0 and profit_pct < TARGET_PROFIT_PERCENT:
                        logger.info(f"Close signal for {pos['type']} but profit {profit_pct:.2f}% < target {TARGET_PROFIT_PERCENT}%. Resetting signals, waiting.")
                        reset_close_signals(signal, g_active_order_type)
                    else:
                        logger.info(f"Closing {pos['type']} position | Profit: {profit_pct:.2f}%")
                        binance.close_position(SYMBOL)
                        backend.update_signal_status(g_last_signal_id, "closed")
                        reset_cycle(f"EA close signal | Profit: {profit_pct:.2f}%")
                continue

            # ============================================================
            # STEP 4: No active position - check if we should open one
            # ============================================================
            if signal.get('tradeAction') != "enabled":
                if g_pending_setup != -1:
                    logger.info(f"Trade action is '{signal.get('tradeAction')}'. Cancelling pending setup.")
                    g_pending_setup = -1
                    g_pending_signal_id = 0
                continue

            # Priority 1: Check for Blue Mode setup
            blue_mode = signal.get('blueMode')
            if blue_mode == "liq_bear":
                if g_pending_setup != 0:
                    logger.info("Priority 1 Met: BUY Setup Initialized (Blue Mode: liq_bear). Waiting for MACD buy...")
                    g_pending_setup = 0
                    g_pending_signal_id = signal_id
            elif blue_mode == "liq_bull":
                if g_pending_setup != 1:
                    logger.info("Priority 1 Met: SELL Setup Initialized (Blue Mode: liq_bull). Waiting for MACD sell...")
                    g_pending_setup = 1
                    g_pending_signal_id = signal_id
            else:
                if g_pending_setup != -1:
                    type_str = "BUY" if g_pending_setup == 0 else "SELL"
                    logger.info(f"Blue Mode changed to '{blue_mode}'. Cancelling pending {type_str} setup.")
                    g_pending_setup = -1
                    g_pending_signal_id = 0

            if g_pending_setup != -1 and signal_id != g_last_signal_id:
                type_str = "BUY" if g_pending_setup == 0 else "SELL"
                # logger.info(f"Waiting for Priority 2 (macd_hist1/macd_hist2) to confirm {type_str} setup...")

            # Priority 2: Check for MACD trigger
            macd_1 = signal.get('macdHist1')
            macd_2 = signal.get('macdHist2')
            
            if g_pending_setup == 0 and (macd_1 == "buy" or macd_2 == "buy"):
                logger.info(f"Priority 2 Met: BUY Triggered (macd_hist1: {macd_1}, macd_hist2: {macd_2})!")
                swing_sl = binance.get_swing_low(SYMBOL, TIMEFRAME, SWING_BARS)
                
                if binance.open_buy_order(SYMBOL, TRADE_USDT_AMOUNT, swing_sl):
                    g_has_active_order = True
                    g_active_order_type = 0
                    g_last_signal_id = signal_id
                    g_pending_setup = -1
                    # Track entry price for profit calculation on external close
                    pos = binance.get_open_position(SYMBOL)
                    if pos:
                        g_active_entry_price = pos['entry_price']
                    backend.update_signal_status(signal_id, "open")
                    reset_entry_signals()
                    
            elif g_pending_setup == 1 and (macd_1 == "sell" or macd_2 == "sell"):
                logger.info(f"Priority 2 Met: SELL Triggered (macd_hist1: {macd_1}, macd_hist2: {macd_2})!")
                swing_sl = binance.get_swing_high(SYMBOL, TIMEFRAME, SWING_BARS)
                
                if binance.open_sell_order(SYMBOL, TRADE_USDT_AMOUNT, swing_sl):
                    g_has_active_order = True
                    g_active_order_type = 1
                    g_last_signal_id = signal_id
                    g_pending_setup = -1
                    # Track entry price for profit calculation on external close
                    pos = binance.get_open_position(SYMBOL)
                    if pos:
                        g_active_entry_price = pos['entry_price']
                    backend.update_signal_status(signal_id, "open")
                    reset_entry_signals()
                    
            if signal_id != g_last_signal_id:
                g_last_signal_id = signal_id

        except Exception as e:
            logger.error(f"Error in main loop: {e}")

if __name__ == "__main__":
    main_loop()
