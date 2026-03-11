package com.devtrade.controller;

import com.devtrade.dto.IctMasterRequest;
import com.devtrade.dto.MacdRequest;
import com.devtrade.dto.PitchFanChanformsRequest;
import com.devtrade.dto.TradeRequest;
import com.devtrade.service.TradeService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/trade")
public class TradeController {

    @Autowired
    private TradeService tradeService;

    @PostMapping("/pitchFan")
    public ResponseEntity<String> pitchFan(@RequestBody TradeRequest request) {
        tradeService.updatePitchFan(request.getSymbol(), request.getAction(), request.getSl());
        return ResponseEntity.ok("PitchFan updated successfully");
    }

    @PostMapping("/macd_hist1")
    public ResponseEntity<String> updateMacdHist1(@RequestBody MacdRequest request) {
        tradeService.updateMacdHist1(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("MACD Hist 1 updated successfully");
    }

    @PostMapping("/macd_hist2")
    public ResponseEntity<String> updateMacdHist2(@RequestBody MacdRequest request) {
        tradeService.updateMacdHist2(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("MACD Hist 2 updated successfully");
    }

    @PostMapping("/macd1_sig_cross")
    public ResponseEntity<String> updateMacd1SigCross(@RequestBody MacdRequest request) {
        tradeService.updateMacd1SigCross(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("MACD1 Sig Cross updated successfully");
    }

    @PostMapping("/macd2_sig_cross")
    public ResponseEntity<String> updateMacd2SigCross(@RequestBody MacdRequest request) {
        tradeService.updateMacd2SigCross(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("MACD2 Sig Cross updated successfully");
    }

    @PostMapping("/fvg")
    public ResponseEntity<String> updateFvg(@RequestBody IctMasterRequest request) {
        tradeService.updateFvg(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("FVG updated successfully");
    }

    @PostMapping("/ob")
    public ResponseEntity<String> updateOb(@RequestBody IctMasterRequest request) {
        tradeService.updateOb(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("OB updated successfully");
    }

    @PostMapping("/bb")
    public ResponseEntity<String> updateBb(@RequestBody IctMasterRequest request) {
        tradeService.updateBb(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("BB updated successfully");
    }

    @PostMapping("/rb")
    public ResponseEntity<String> updateRb(@RequestBody IctMasterRequest request) {
        tradeService.updateRb(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("RB updated successfully");
    }

    @PostMapping("/pitchFanChanforms")
    public ResponseEntity<String> insertPitchFanChanForms(@RequestBody PitchFanChanformsRequest request) {
        tradeService.insertPitchFanChanForms(request.getSymbol(), request.getAction());
        return ResponseEntity.ok("PitchFan Chan Forms updated (deactivated and inserted) successfully");
    }

    @PostMapping("/fibo")
    public ResponseEntity<String> updateFibo(@RequestBody com.devtrade.dto.FiboRequest request) {
        tradeService.updateFibo(request.getSymbol(), request.getFibo0_5(), request.getFibo61_8(), request.getFiboPoc());
        return ResponseEntity.ok("Fibo values updated successfully");
    }

    @PostMapping("/fiboChangeforms")
    public ResponseEntity<String> insertFiboChangeForms(@RequestBody com.devtrade.dto.FiboRequest request) {
        tradeService.fibChangeForms(request.getSymbol(), request.getFibo0_5(), request.getFibo61_8(),
                request.getFiboPoc());
        return ResponseEntity.ok("Fibo Change Forms updated successfully");
    }
}
