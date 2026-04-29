import requests
import logging
import time

logger = logging.getLogger(__name__)

MAX_RETRIES = 3
RETRY_DELAY_SEC = 2

class BackendClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')

    def get_latest_signal(self, symbol: str) -> dict:
        """Fetches the latest signal from the crypto API."""
        try:
            response = requests.get(f"{self.base_url}/api/crypto/latest-signal", params={"symbol": symbol}, timeout=5)
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 204:
                return {} # No content
            else:
                logger.error(f"Failed to get signal: {response.status_code} {response.text}")
                return {}
        except Exception as e:
            logger.error(f"Exception connecting to backend: {e}")
            return {}

    def update_signal_status(self, signal_id: int, status: str) -> bool:
        """
        Updates the close status of a signal with retry logic.
        Retries up to MAX_RETRIES times if the API call fails,
        ensuring close_status is always updated even during backend downtime.
        """
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                payload = {"signalId": signal_id, "status": status}
                response = requests.post(f"{self.base_url}/api/crypto/update-status", json=payload, timeout=5)
                if response.status_code == 200:
                    logger.info(f"Updated signal_id={signal_id} status to '{status}'")
                    return True
                else:
                    logger.error(f"Failed to update status (attempt {attempt}/{MAX_RETRIES}): {response.status_code} {response.text}")
            except Exception as e:
                logger.error(f"Exception updating status (attempt {attempt}/{MAX_RETRIES}): {e}")
            
            if attempt < MAX_RETRIES:
                logger.info(f"Retrying status update in {RETRY_DELAY_SEC}s...")
                time.sleep(RETRY_DELAY_SEC)
        
        logger.error(f"CRITICAL: Failed to update signal_id={signal_id} to '{status}' after {MAX_RETRIES} attempts!")
        return False

    def reset_signal(self, endpoint: str, symbol: str, indicator: str = None) -> bool:
        """Resets an indicator signal (like fvg, macd, etc.)"""
        try:
            payload = {"symbol": symbol, "action": ""}
            if indicator:
                payload["indicator"] = indicator
                
            response = requests.post(f"{self.base_url}/api/crypto/{endpoint}", json=payload, timeout=5)
            if response.status_code == 200:
                logger.info(f"Reset {endpoint} signal for {symbol}")
                return True
            else:
                logger.error(f"Failed to reset {endpoint}: {response.status_code} {response.text}")
                return False
        except Exception as e:
            logger.error(f"Exception resetting signal: {e}")
            return False
