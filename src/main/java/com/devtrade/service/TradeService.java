package com.devtrade.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.SQLException;

@Service
public class TradeService {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    public void insertPitchFan(String symbol, String action, Double sl) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_insert_pitch_fan(?, ?, ?)}")) {
                cs.setString(1, symbol);
                cs.setString(2, action);
                if (sl != null) {
                    cs.setDouble(3, sl);
                } else {
                    cs.setNull(3, java.sql.Types.DECIMAL);
                }
                cs.execute();
            }
            return null;
        });
    }

    public void updateMacdHist1(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_macd_hist1(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateMacdHist2(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_macd_hist2(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateMacd1SigCross(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_macd1_sig_cross(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateMacd2SigCross(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_macd2_sig_cross(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateFvg(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_fvg(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateOb(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_ob(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateBb(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_bb(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updateRb(String action) {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_rb(?)}")) {
                cs.setString(1, action);
                cs.execute();
            }
            return null;
        });
    }

    public void updatePitchFanChanForms() {
        jdbcTemplate.execute((Connection conn) -> {
            try (CallableStatement cs = conn.prepareCall("{call sp_update_pitch_fan_chan_forms()}")) {
                cs.execute();
            }
            return null;
        });
    }
}
