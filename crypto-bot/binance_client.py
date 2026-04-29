import pandas as pd
from binance.client import Client
from binance.exceptions import BinanceAPIException
import math
import logging

logger = logging.getLogger(__name__)

class BinanceFuturesClient:
    def __init__(self, api_key: str, api_secret: str, testnet: bool = True):
        self.client = Client(api_key, api_secret, testnet=testnet)
        self.symbol_info = {}

    def get_symbol_info(self, symbol: str):
        """Caches symbol info for lot size and price filters."""
        if symbol not in self.symbol_info:
            info = self.client.futures_exchange_info()
            for s in info['symbols']:
                if s['symbol'] == symbol:
                    self.symbol_info[symbol] = s
                    break
        return self.symbol_info.get(symbol)

    def set_leverage(self, symbol: str, leverage: int):
        """Sets the leverage for the given symbol."""
        try:
            self.client.futures_change_leverage(symbol=symbol, leverage=leverage)
            logger.info(f"Successfully set leverage to {leverage}x for {symbol}")
        except BinanceAPIException as e:
            logger.error(f"Error setting leverage: {e}")

    def calculate_lot_size(self, symbol: str, usdt_amount: float, current_price: float) -> float:
        """Calculates valid quantity based on fixed USDT amount."""
        info = self.get_symbol_info(symbol)
        if not info:
            logger.error(f"Could not fetch symbol info for {symbol}")
            return 0.0

        step_size = float([f['stepSize'] for f in info['filters'] if f['filterType'] == 'LOT_SIZE'][0])
        precision = int(round(-math.log(step_size, 10), 0))
        
        raw_qty = usdt_amount / current_price
        # Round down to step_size
        qty = math.floor(raw_qty / step_size) * step_size
        return round(qty, precision)

    def format_price(self, symbol: str, price: float) -> float:
        """Formats price to correct tick size."""
        info = self.get_symbol_info(symbol)
        if not info:
            return price
            
        tick_size = float([f['tickSize'] for f in info['filters'] if f['filterType'] == 'PRICE_FILTER'][0])
        precision = int(round(-math.log(tick_size, 10), 0))
        
        # Round to tick_size
        formatted_price = round(round(price / tick_size) * tick_size, precision)
        return formatted_price

    def get_open_position(self, symbol: str):
        """Returns the open position for the symbol if one exists."""
        try:
            positions = self.client.futures_position_information(symbol=symbol)
            for pos in positions:
                amt = float(pos['positionAmt'])
                if amt != 0:
                    return {
                        'type': 'BUY' if amt > 0 else 'SELL',
                        'amount': amt,
                        'entry_price': float(pos['entryPrice']),
                        'unrealized_profit': float(pos['unRealizedProfit'])
                    }
            return None
        except BinanceAPIException as e:
            logger.error(f"Error fetching position: {e}")
            return None

    def get_close_reason(self, symbol: str, order_id: int = None) -> str:
        """
        Determines why a position was closed by checking recent order history.
        Returns: 'Stop Loss hit', 'Take Profit hit', 'Manual close', 'Closed by bot', or 'Unknown'
        
        This is the Python equivalent of OnTradeTransaction() in the MQ5 EA.
        It checks recent filled orders to find STOP_MARKET (SL) or TAKE_PROFIT_MARKET (TP).
        """
        try:
            # Get recent orders (last 50)
            orders = self.client.futures_get_all_orders(symbol=symbol, limit=50)
            if not orders:
                return "Unknown"
            
            # Look at the most recent filled orders (newest first)
            filled_orders = [o for o in orders if o.get('status') == 'FILLED']
            if not filled_orders:
                return "Unknown"
            
            # Check the last few filled orders for SL/TP triggers
            for order in reversed(filled_orders[-5:]):
                order_type = order.get('type', '')
                
                if order_type == 'STOP_MARKET':
                    return "Stop Loss hit"
                elif order_type == 'TAKE_PROFIT_MARKET':
                    return "Take Profit hit"
                elif order_type == 'MARKET':
                    # Could be manual close or bot close
                    # Check if it was a reduce-only or close
                    if order.get('reduceOnly', False) or order.get('closePosition', False):
                        return "Manual close"
            
            # If the last order is just a regular MARKET, it's likely manual
            last_order = filled_orders[-1]
            if last_order.get('type') == 'MARKET':
                return "Manual close"
            
            return "Unknown"
            
        except BinanceAPIException as e:
            logger.error(f"Error fetching close reason: {e}")
            return "Unknown"

    def get_klines_df(self, symbol: str, interval: str, limit: int):
        """Fetches klines and returns as a pandas DataFrame."""
        try:
            klines = self.client.futures_klines(symbol=symbol, interval=interval, limit=limit)
            df = pd.DataFrame(klines, columns=['timestamp', 'open', 'high', 'low', 'close', 'volume', 'close_time', 'qav', 'num_trades', 'taker_base_vol', 'taker_quote_vol', 'ignore'])
            df['high'] = df['high'].astype(float)
            df['low'] = df['low'].astype(float)
            df['close'] = df['close'].astype(float)
            return df
        except BinanceAPIException as e:
            logger.error(f"Error fetching klines: {e}")
            return None

    def get_swing_low(self, symbol: str, interval: str, bars: int) -> float:
        """Gets the lowest low over the last 'bars' (excluding current open bar)."""
        df = self.get_klines_df(symbol, interval, bars + 1)
        if df is not None and not df.empty:
            # exclude the very last row as it is the currently open bar
            return df['low'].iloc[:-1].min()
        return 0.0

    def get_swing_high(self, symbol: str, interval: str, bars: int) -> float:
        """Gets the highest high over the last 'bars' (excluding current open bar)."""
        df = self.get_klines_df(symbol, interval, bars + 1)
        if df is not None and not df.empty:
            # exclude the very last row
            return df['high'].iloc[:-1].max()
        return 0.0
        
    def get_current_price(self, symbol: str) -> float:
        try:
            ticker = self.client.futures_symbol_ticker(symbol=symbol)
            return float(ticker['price'])
        except Exception as e:
            logger.error(f"Error getting price: {e}")
            return 0.0

    def open_buy_order(self, symbol: str, usdt_amount: float, sl_price: float) -> bool:
        """Opens a Market BUY and sets a Stop Market SL."""
        current_price = self.get_current_price(symbol)
        qty = self.calculate_lot_size(symbol, usdt_amount, current_price)
        sl_price = self.format_price(symbol, sl_price)
        
        if qty <= 0:
            logger.error(f"Calculated quantity is 0 for {symbol}")
            return False

        try:
            # 1. Place Market Buy
            logger.info(f"Placing BUY MARKET order for {qty} {symbol}")
            order = self.client.futures_create_order(
                symbol=symbol,
                side='BUY',
                type='MARKET',
                quantity=qty
            )
            logger.info(f"BUY Order placed: {order['orderId']}")
            
            # 2. Place SL order
            if sl_price > 0 and sl_price < current_price:
                logger.info(f"Placing STOP_MARKET SELL SL at {sl_price}")
                self.client.futures_create_order(
                    symbol=symbol,
                    side='SELL',
                    type='STOP_MARKET',
                    stopPrice=sl_price,
                    closePosition=True
                )
            return True
        except BinanceAPIException as e:
            logger.error(f"Error opening buy order: {e}")
            return False

    def open_sell_order(self, symbol: str, usdt_amount: float, sl_price: float) -> bool:
        """Opens a Market SELL and sets a Stop Market SL."""
        current_price = self.get_current_price(symbol)
        qty = self.calculate_lot_size(symbol, usdt_amount, current_price)
        sl_price = self.format_price(symbol, sl_price)
        
        if qty <= 0:
            logger.error(f"Calculated quantity is 0 for {symbol}")
            return False

        try:
            # 1. Place Market Sell
            logger.info(f"Placing SELL MARKET order for {qty} {symbol}")
            order = self.client.futures_create_order(
                symbol=symbol,
                side='SELL',
                type='MARKET',
                quantity=qty
            )
            logger.info(f"SELL Order placed: {order['orderId']}")
            
            # 2. Place SL order
            if sl_price > 0 and sl_price > current_price:
                logger.info(f"Placing STOP_MARKET BUY SL at {sl_price}")
                self.client.futures_create_order(
                    symbol=symbol,
                    side='BUY',
                    type='STOP_MARKET',
                    stopPrice=sl_price,
                    closePosition=True
                )
            return True
        except BinanceAPIException as e:
            logger.error(f"Error opening sell order: {e}")
            return False

    def close_position(self, symbol: str):
        """Closes any open position for the symbol and cancels open SL/TP orders."""
        try:
            pos = self.get_open_position(symbol)
            if pos:
                side = 'SELL' if pos['type'] == 'BUY' else 'BUY'
                qty = abs(pos['amount'])
                logger.info(f"Closing {pos['type']} position of {qty} {symbol}")
                self.client.futures_create_order(
                    symbol=symbol,
                    side=side,
                    type='MARKET',
                    quantity=qty
                )
            # Cancel all open orders (SL)
            self.client.futures_cancel_all_open_orders(symbol=symbol)
            return True
        except BinanceAPIException as e:
            logger.error(f"Error closing position: {e}")
            return False
