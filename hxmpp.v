`timescale 1ns / 1ps

//----------------//
// COMPLETE HXMPP //
//----------------//

module hxmpp(
    input clk,
    input reset,
    input write,
    input [ROWINDEXBITS_HCM-1:0] writeSSID,
    input [HITINFOBITS-1:0] writeHitInfo,
    input read,
    input [ROWINDEXBITS_HCM-1:0] readSSID,
    output [SSIDBITS-1:0] SSID_read, // return value
    output [HITINFOBITS-1:0] hitInfo_read // return value
    );

    `include "MyParameters.vh"

    //-----//
    // HNM //
    //-----//

    // Pass SSIDs in here. Watch HNM_SSID_passed and HNM_hitExisted. This will
    // return the SSIDs after they're done storing, along with whether there
    // was a hit in there previously.

    wire [SSIDBITS-1:0] HNM_SSID_passed;
    wire HNM_hitExisted;
    wire HNM_newOutput;

    wire [ROWINDEXBITS_HNM-1:0] HNM_rowPassed;
    wire [NCOLS_HNM-1:0] HNM_rowReadOutput;
    wire HNM_readReady, HNM_writeReady, HNM_busy;

    HNMPP HNM (
        .clk(clk),
        .reset(reset),
        .write(write),
        .SSID_write(writeSSID),
        .writeRow(0),
        .rowWrite(0),
        .dataWrite(0),
        .SSID_read(0),
        .read(0),
        .rowRead(0),
        .readRow(0),
        .fillSequentialRows(0),
        .rowPassed(HNM_rowPassed),
        .rowReadOutput(HNM_rowReadOutput),
        .SSID_passed(HNM_SSID_passed),
        .HNM_readOutput(HNM_hitExisted),
        .newOutput(HNM_newOutput),
        .writeReady(HNM_writeReady),
        .readReady(HNM_readReady),
        .busy(HNM_busy)
    );

    //-----//
    // HCM //
    //-----//

    // Pass SSIDs as they come from HNM. Also pass whether these SSIDs were
    // newly stored. Pass hit info too. Watch as the SSIDs come back out, along
    // with the HIM address, how many hits were pre-existing, and the new hits
    // along with their info.

    reg [HITINFOBITS-1:0] HCM_inputHitInfo,

    wire [ROWINDEXBITS_HCM-1:0] HCM_SSID_passed;
    wire [MAXHITNBITS-1:0] HCM_nOldHits;
    wire [MAXHITNBITS-1:0] HCM_nNewHits;
    wire HCM_newOutput;

    wire HCM_readReady, HCM_writeReady, HCM_busy;

    wire [NCOLS_HIM-1:0] HCM_newHitInfo;
    wire [ROWINDEXBITS_HIM-1:0] HIM_address;

    HCMPP HCM (
        .clk(clk),
        .reset(reset),
        .writeRow(HNM_newOutput),
        .inputRowToWrite(HNM_SSID_passed),
        .SSIDIsNew(~HNM_hitExisted),
        .inputRowToRead(0),
        .readRow(0),
        .inputHitInfo(HCM_inputHitInfo),
        .rowPassed(HCM_SSID_passed),
        .nOldHits(HCM_nOldHits),
        .nNewHits(HCM_nNewHits),
        .HIM_address(HIM_address),
        .outputNewHitInfo(HCM_newHitInfo),
        .newOutput(HCM_newOutput),
        .writeReady(HCM_writeReady),
        .readReady(HCM_readReady),
        .busy(HCM_busy)
    );

    //----------------//
    // HIT INFO QUEUE //
    //----------------//

    reg [NCOLS_HIM-1:0] queueHitInfo [QUEUESIZE-1:0];
    reg [QUEUESIZEBITS-1:0] nInQueue = 0;

    reg [QUEUESIZEBITS-1:0] queueN = 0; // can't do loop variable declaration

    always @(posedge clk) begin

        if (write) queueHitInfo[nInQueue - HNM_newOutput] <= writeHitInfo; // add hit info to queue for new hit
        HCM_inputHitInfo <= queueHitInfo[0]; // the first hit info in the queue is the next to be used by HCM

        if (HNM_newOutput) begin // if the first item has been used
            for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                queueHitInfo[queueN] <= queueHitInfo[queueN+1]; // pop an item
            end
            nInQueue <= nInQueue - 1;
        end
    end

    //-----//
    // HIM //
    //-----//

    // Pass SSIDs as they come from HCM, along with the existing number of
    // hits, new hits, and hit info.

    wire HIM_readReady, HIM_writeReady, HIM_busy;

    HIMPP HIM (
        .clk(clk),
        .reset(reset),
        .writeRow(HCM_newOutput),
        .inputRowToWrite(HIM_address),
        .inputRowToRead(0),
        .readRow(0),
        .inputHitInfo(HCM_newHitInfo),
        .nOldHits(HCM_nOldHits),
        .nNewHits(HCM_nNewHits),
        .writeReady(HIM_writeReady),
        .readReady(HIM_readReady),
        .busy(HIM_busy)
    );

endmodule
