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
    output reg readFinished,
    output reg [SSIDBITS-1:0] SSID_readReturn,
    output reg hitThisEventReturn,
    output reg [MAXHITNBITS-1:0] nHitsReturn,
    output reg [NCOLS_HIM-1:0] hitInfo_readReturn
    );

    `include "MyParameters.vh"

    wire [SSIDBITS-1:0] SSID_read;
    wire hitThisEvent;
    wire [MAXHITNBITS-1:0] nHits;
    
    assign SSID_read = HNM_SSID_passed;
    assign hitThisEvent = HNM_hitExisted;
    assign nHits = readNHits;

    //-------------------//
    // READ OUTPUT QUEUE //
    //-------------------//

    reg [SSIDBITS-1:0] queueSSID_read [QUEUESIZE-1:0];
    reg [QUEUESIZE-1:0] queueHitThisEvent;
    reg [MAXHITNBITS-1:0] queueNHits [QUEUESIZE-1:0];
    reg [QUEUESIZEBITS-1:0] nInReadoutQueue = 0;

    reg [QUEUESIZEBITS-1:0] readoutQueueN = 0; // can't do loop variable declaration

    always @(posedge clk) begin

        readFinished <= 0;

        if (HCM_readoutFinished) begin // add info to queue while waiting to read HIM
            queueSSID_read[nInReadoutQueue - HIM_readoutFinished] <= SSID_read;
            queueHitThisEvent[nInReadoutQueue - HIM_readoutFinished] <= hitThisEvent;
            queueNHits[nInReadoutQueue - HIM_readoutFinished] <= nHits;
            nInReadoutQueue <= nInReadoutQueue + 1;
            if (HIM_readoutFinished) nInReadoutQueue <= nInReadoutQueue;
        end

        if (HIM_readoutFinished) begin // time to return info
            for (readoutQueueN = 0; readoutQueueN < QUEUESIZE - 1; readoutQueueN = readoutQueueN + 1) begin
                queueSSID_read[readoutQueueN] <= queueSSID_read[readoutQueueN+1]; // pop an item
                queueHitThisEvent[readoutQueueN] <= queueHitThisEvent[readoutQueueN+1]; // pop an item
                queueNHits[readoutQueueN] <= queueNHits[readoutQueueN+1]; // pop an item
            end
            nInReadoutQueue <= nInReadoutQueue - 1;
            if (HCM_readoutFinished) nInReadoutQueue <= nInReadoutQueue;

            readFinished <= 1;
            SSID_readReturn <= queueSSID_read[0];
            hitThisEventReturn <= queueHitThisEvent[0];
            nHitsReturn <= queueNHits[0];
            hitInfo_readReturn <= hitInfo_read;
        end
    end

    //----------------//
    // HIT INFO QUEUE //
    //----------------//

    (*mark_debug="TRUE"*)
    reg [NCOLS_HIM-1:0] queueHitInfo [QUEUESIZE-1:0];
    (*mark_debug="TRUE"*)
    reg [QUEUESIZEBITS-1:0] nInQueue = 0;

    reg [QUEUESIZEBITS-1:0] queueN = 0; // can't do loop variable declaration

    always @(posedge clk) begin

        if (HNM_newOutput) begin // if the first item has been used
            for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                queueHitInfo[queueN] <= queueHitInfo[queueN+1]; // pop an item
            end
            nInQueue <= nInQueue - 1;
        end

        if (write) begin
            queueHitInfo[nInQueue - HNM_newOutput] <= writeHitInfo; // add hit info to queue for new hit
            nInQueue <= nInQueue + 1;
            if (HNM_newOutput) nInQueue <= nInQueue;
        end
    end

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
        .read(read),
        .SSID_read(readSSID),
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

    wire [MAXHITNBITS-1:0] HCM_nOldHits;
    wire [MAXHITNBITS-1:0] HCM_nNewHits;
    wire [MAXHITNBITS-1:0] readNHits;
    wire HCM_newOutput;

    wire HCM_readReady, HCM_writeReady, HCM_busy;

    wire [NCOLS_HIM-1:0] HCM_newHitInfo;
    wire [ROWINDEXBITS_HIM-1:0] HIM_address;
    wire [SSIDBITS-1:0] placeholderRowPassed;

    wire [ROWINDEXBITS_HIM-1:0] readHIM_address;
    wire HCM_readoutFinished;

    HCMPP HCM (
        .clk(clk),
        .reset(reset),
        .writeRow(HNM_newOutput && ~read),
        .inputRowToWrite(HNM_SSID_passed),
        .SSIDIsNew(~HNM_hitExisted),
        .readRow(read),
        .inputRowToRead(readSSID),
        .inputHitInfo(queueHitInfo[0]),
        .rowPassed(placeholderRowPassed),
        .nOldHits(HCM_nOldHits),
        .nNewHits(HCM_nNewHits),
        .readNHits(readNHits),
        .readHIM_address(readHIM_address),
        .HIM_address(HIM_address),
        .outputNewHitInfo(HCM_newHitInfo),
        .newOutput(HCM_newOutput),
        .readFinished(HCM_readoutFinished),
        .writeReady(HCM_writeReady),
        .readReady(HCM_readReady),
        .busy(HCM_busy)
    );

    //-----//
    // HIM //
    //-----//

    // Pass SSIDs as they come from HCM, along with the existing number of
    // hits, new hits, and hit info.

    wire HIM_readReady, HIM_writeReady, HIM_busy;
    wire [NCOLS_HIM-1:0] hitInfo_read;

    HIMPP HIM (
        .clk(clk),
        .reset(reset),
        .writeRow(HCM_newOutput && ~read),
        .inputRowToWrite(HIM_address),
        .readRow(HCM_readoutFinished),
        .inputRowToRead(readHIM_address),
        .inputHitInfo(HCM_newHitInfo),
        .nOldHits(HCM_nOldHits),
        .nNewHits(HCM_nNewHits),
        .hitInfo_read(hitInfo_read),
        .readFinished(HIM_readoutFinished),
        .writeReady(HIM_writeReady),
        .readReady(HIM_readReady),
        .busy(HIM_busy)
    );

endmodule
