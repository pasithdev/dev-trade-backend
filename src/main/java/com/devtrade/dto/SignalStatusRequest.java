package com.devtrade.dto;

public class SignalStatusRequest {
    private int signalId;
    private String status;

    public int getSignalId() {
        return signalId;
    }

    public void setSignalId(int signalId) {
        this.signalId = signalId;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }
}
