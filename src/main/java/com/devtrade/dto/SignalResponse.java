package com.devtrade.dto;

public class SignalResponse {
    private int signalId;
    private String symbol;
    private String pitchFan;
    private String macdHist1;
    private String macdHist2;
    private String macd1SigCross;
    private String macd2SigCross;
    private String fvg;
    private String ob;
    private String bb;
    private String rb;
    private String blueMode;
    private Double sl;
    private Double fibo0_5;
    private Double fibo61_8;
    private Double fiboPoc;
    private String closeStatus;
    private String isActive;

    // Getters and Setters
    public int getSignalId() {
        return signalId;
    }

    public void setSignalId(int signalId) {
        this.signalId = signalId;
    }

    public String getSymbol() {
        return symbol;
    }

    public void setSymbol(String symbol) {
        this.symbol = symbol;
    }

    public String getPitchFan() {
        return pitchFan;
    }

    public void setPitchFan(String pitchFan) {
        this.pitchFan = pitchFan;
    }

    public String getMacdHist1() {
        return macdHist1;
    }

    public void setMacdHist1(String macdHist1) {
        this.macdHist1 = macdHist1;
    }

    public String getMacdHist2() {
        return macdHist2;
    }

    public void setMacdHist2(String macdHist2) {
        this.macdHist2 = macdHist2;
    }

    public String getMacd1SigCross() {
        return macd1SigCross;
    }

    public void setMacd1SigCross(String macd1SigCross) {
        this.macd1SigCross = macd1SigCross;
    }

    public String getMacd2SigCross() {
        return macd2SigCross;
    }

    public void setMacd2SigCross(String macd2SigCross) {
        this.macd2SigCross = macd2SigCross;
    }

    public String getFvg() {
        return fvg;
    }

    public void setFvg(String fvg) {
        this.fvg = fvg;
    }

    public String getOb() {
        return ob;
    }

    public void setOb(String ob) {
        this.ob = ob;
    }

    public String getBb() {
        return bb;
    }

    public void setBb(String bb) {
        this.bb = bb;
    }

    public String getRb() {
        return rb;
    }

    public void setRb(String rb) {
        this.rb = rb;
    }

    public String getBlueMode() {
        return blueMode;
    }

    public void setBlueMode(String blueMode) {
        this.blueMode = blueMode;
    }

    public Double getSl() {
        return sl;
    }

    public void setSl(Double sl) {
        this.sl = sl;
    }

    public Double getFibo0_5() {
        return fibo0_5;
    }

    public void setFibo0_5(Double fibo0_5) {
        this.fibo0_5 = fibo0_5;
    }

    public Double getFibo61_8() {
        return fibo61_8;
    }

    public void setFibo61_8(Double fibo61_8) {
        this.fibo61_8 = fibo61_8;
    }

    public Double getFiboPoc() {
        return fiboPoc;
    }

    public void setFiboPoc(Double fiboPoc) {
        this.fiboPoc = fiboPoc;
    }

    public String getCloseStatus() {
        return closeStatus;
    }

    public void setCloseStatus(String closeStatus) {
        this.closeStatus = closeStatus;
    }

    public String getIsActive() {
        return isActive;
    }

    public void setIsActive(String isActive) {
        this.isActive = isActive;
    }
}
