package com.devtrade.controller;

import com.devtrade.dto.BlueModeRequest;
import com.devtrade.dto.IctMasterRequest;
import com.devtrade.dto.MacdRequest;
import com.devtrade.dto.PitchFanChanformsRequest;
import com.devtrade.dto.TradeRequest;
import com.devtrade.service.CryptoTradeService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/crypto")
public class CryptoTradeController {

    @Autowired
    private CryptoTradeService cryptoTradeService;

    @PostMapping("/pitchFan")
    public ResponseEntity<String> pitchFan(@RequestBody TradeRequest request) {
        cryptoTradeService.updatePitchFan(request.getSymbol(), request.getAction(), request.getSl());
        return ResponseEntity.ok("Crypto PitchFan updated successfully");
    }

    @PostMapping("/macd_hist1")
    public ResponseEntity<String> updateMacdHist1(@RequestBody MacdRequest request) {
        cryptoTradeService.updateMacdHist1(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto MACD Hist 1 updated successfully");
    }

    @PostMapping("/macd_hist2")
    public ResponseEntity<String> updateMacdHist2(@RequestBody MacdRequest request) {
        cryptoTradeService.updateMacdHist2(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto MACD Hist 2 updated successfully");
    }

    @PostMapping("/macd1_sig_cross")
    public ResponseEntity<String> updateMacd1SigCross(@RequestBody MacdRequest request) {
        cryptoTradeService.updateMacd1SigCross(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto MACD1 Sig Cross updated successfully");
    }

    @PostMapping("/macd2_sig_cross")
    public ResponseEntity<String> updateMacd2SigCross(@RequestBody MacdRequest request) {
        cryptoTradeService.updateMacd2SigCross(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto MACD2 Sig Cross updated successfully");
    }

    @PostMapping("/fvg")
    public ResponseEntity<String> updateFvg(@RequestBody IctMasterRequest request) {
        cryptoTradeService.updateFvg(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto FVG updated successfully");
    }

    @PostMapping("/ob")
    public ResponseEntity<String> updateOb(@RequestBody IctMasterRequest request) {
        cryptoTradeService.updateOb(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto OB updated successfully");
    }

    @PostMapping("/bb")
    public ResponseEntity<String> updateBb(@RequestBody IctMasterRequest request) {
        cryptoTradeService.updateBb(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto BB updated successfully");
    }

    @PostMapping("/rb")
    public ResponseEntity<String> updateRb(@RequestBody IctMasterRequest request) {
        cryptoTradeService.updateRb(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto RB updated successfully");
    }

    @PostMapping("/blue_mode")
    public ResponseEntity<String> insertBlueMode(@RequestBody BlueModeRequest request) {
        cryptoTradeService.insertBlueMode(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto Blue Mode inserted successfully");
    }

    @PostMapping("/pitchFanChanforms")
    public ResponseEntity<String> insertPitchFanChanForms(@RequestBody PitchFanChanformsRequest request) {
        cryptoTradeService.insertPitchFanChanForms(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("Crypto PitchFan Chan Forms updated (deactivated and inserted) successfully");
    }

    @PostMapping("/fibo")
    public ResponseEntity<String> updateFibo(@RequestBody com.devtrade.dto.FiboRequest request) {
        cryptoTradeService.updateFibo(request.getSymbol(), request.getFibo0_5(), request.getFibo61_8(), request.getFiboPoc());
        return ResponseEntity.ok("Crypto Fibo values updated successfully");
    }

    @PostMapping("/fiboChangeforms")
    public ResponseEntity<String> insertFiboChangeForms(@RequestBody com.devtrade.dto.FiboRequest request) {
        cryptoTradeService.fibChangeForms(request.getSymbol(), request.getFibo0_5(), request.getFibo61_8(),
                request.getFiboPoc());
        return ResponseEntity.ok("Crypto Fibo Change Forms updated successfully");
    }

    @org.springframework.web.bind.annotation.GetMapping("/latest-signal")
    public ResponseEntity<com.devtrade.dto.SignalResponse> getLatestSignal(
            @org.springframework.web.bind.annotation.RequestParam String symbol) {
        com.devtrade.dto.SignalResponse signal = cryptoTradeService.getLatestSignal(symbol);
        if (signal != null) {
            return ResponseEntity.ok(signal);
        } else {
            return ResponseEntity.noContent().build();
        }
    }

    @PostMapping("/update-status")
    public ResponseEntity<String> updateSignalStatus(@RequestBody com.devtrade.dto.SignalStatusRequest request) {
        cryptoTradeService.updateSignalStatus(request.getSignalId(), request.getStatus());
        return ResponseEntity.ok("Crypto Signal status updated successfully");
    }
}
