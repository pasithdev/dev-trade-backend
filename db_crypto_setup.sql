USE devtrade;

CREATE TABLE IF NOT EXISTS trade_crypto (
    signal_id INT AUTO_INCREMENT PRIMARY KEY,
    symbol VARCHAR(50) NOT NULL,
    pitch_fan VARCHAR(50),
    macd_hist1 VARCHAR(50),
    macd_hist2 VARCHAR(50),
    macd1_sig_cross VARCHAR(50),
    macd2_sig_cross VARCHAR(50),
    fvg VARCHAR(50),
    ob VARCHAR(50),
    bb VARCHAR(50),
    rb VARCHAR(50),
    blue_mode VARCHAR(50),
    sl DECIMAL(10, 4),
    fibo_0_5 DECIMAL (10,4),
    fibo_61_8 DECIMAL (10,4),
    fibo_poc DECIMAL (10,4),
    close_status VARCHAR(50),
    is_active VARCHAR(1) DEFAULT 'Y',
    trade_action VARCHAR(50) DEFAULT 'enabled' -- enabled, disabled, manual
);

DELIMITER //

DROP PROCEDURE IF EXISTS crypto_sp_update_pitch_fan //
CREATE PROCEDURE crypto_sp_update_pitch_fan(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50),
    IN p_sl DECIMAL(10, 4)
)
BEGIN
    UPDATE trade_crypto
    SET pitch_fan = p_action, sl = IFNULL(p_sl, sl)
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_macd_hist1 //
CREATE PROCEDURE crypto_sp_update_macd_hist1(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET macd_hist1 = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_macd_hist2 //
CREATE PROCEDURE crypto_sp_update_macd_hist2(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET macd_hist2 = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_macd1_sig_cross //
CREATE PROCEDURE crypto_sp_update_macd1_sig_cross(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET macd1_sig_cross = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_macd2_sig_cross //
CREATE PROCEDURE crypto_sp_update_macd2_sig_cross(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET macd2_sig_cross = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_fvg //
CREATE PROCEDURE crypto_sp_update_fvg(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET fvg = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_ob //
CREATE PROCEDURE crypto_sp_update_ob(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET ob = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_bb //
CREATE PROCEDURE crypto_sp_update_bb(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET bb = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_rb //
CREATE PROCEDURE crypto_sp_update_rb(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET rb = p_action
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_insert_blue_mode //
CREATE PROCEDURE crypto_sp_insert_blue_mode(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    DECLARE v_close_status VARCHAR(50);
    DECLARE v_signal_id INT;

    SELECT close_status, signal_id INTO v_close_status, v_signal_id
    FROM trade_crypto
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;

    IF v_signal_id IS NULL OR IFNULL(v_close_status, '') != 'open' THEN
        IF v_signal_id IS NOT NULL THEN
            UPDATE trade_crypto
            SET is_active = 'N'
            WHERE signal_id = v_signal_id;
        END IF;

        INSERT INTO trade_crypto (symbol, blue_mode, is_active)
        VALUES (p_symbol, p_action, 'Y');
    END IF;
END //

DROP PROCEDURE IF EXISTS crypto_sp_insert_pitch_fan_chan_forms //
CREATE PROCEDURE crypto_sp_insert_pitch_fan_chan_forms(
    IN p_symbol VARCHAR(50),
    IN p_action VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET is_active = 'N'
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;

    INSERT INTO trade_crypto (symbol, pitch_fan, is_active)
    VALUES (p_symbol, p_action, 'Y');
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_fibo //
CREATE PROCEDURE crypto_sp_update_fibo(
    IN p_symbol VARCHAR(50),
    IN p_fibo_0_5 DECIMAL(10, 4),
    IN p_fibo_61_8 DECIMAL(10, 4),
    IN p_fibo_poc DECIMAL(10, 4)
)
BEGIN
    UPDATE trade_crypto
    SET fibo_0_5 = p_fibo_0_5,
        fibo_61_8 = p_fibo_61_8,
        fibo_poc = p_fibo_poc
    WHERE is_active = 'Y' AND symbol = p_symbol
    ORDER BY signal_id DESC
    LIMIT 1;
END //

DROP PROCEDURE IF EXISTS crypto_sp_get_latest_signal //
CREATE PROCEDURE crypto_sp_get_latest_signal(
    IN p_symbol VARCHAR(50)
)
BEGIN
    SELECT signal_id, symbol, pitch_fan, macd_hist1, macd_hist2, 
           macd1_sig_cross, macd2_sig_cross, fvg, ob, bb, rb, blue_mode,
           sl, fibo_0_5, fibo_61_8, fibo_poc, close_status, is_active, trade_action
    FROM trade_crypto
    WHERE signal_id = (
        SELECT MAX(signal_id) 
        FROM trade_crypto 
        WHERE symbol = p_symbol 
          AND is_active = 'Y'
    )
      AND symbol = p_symbol
      AND is_active = 'Y'
      AND (close_status IS NULL OR close_status != 'closed');
END //

DROP PROCEDURE IF EXISTS crypto_sp_update_signal_status //
CREATE PROCEDURE crypto_sp_update_signal_status(
    IN p_signal_id INT,
    IN p_status VARCHAR(50)
)
BEGIN
    UPDATE trade_crypto
    SET close_status = p_status,
        is_active = CASE
            WHEN p_status = 'open'   THEN 'Y'
            WHEN p_status = 'closed' THEN 'N'
            ELSE is_active
        END
    WHERE signal_id = p_signal_id;
END //

DELIMITER ;
