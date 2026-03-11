package com.devtrade.dto;

public class FiboRequest {
    private String symbol;
    private Double fibo0_5;
    private Double fibo61_8;
    private Double fiboPoc;

    public String getSymbol() {
        return symbol;
    }

    public void setSymbol(String symbol) {
        this.symbol = symbol;
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
}
