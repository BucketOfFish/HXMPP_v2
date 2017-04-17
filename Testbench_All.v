`timescale 1ns / 1ps

//-------------------//
// Testbench for HXM //
//-------------------//

module Testbench_All(
    input clk_p,
    input clk_n
    );

    wire clk;
    // derive signal from external differential clock: ext_clk_[p/n]
    IBUFDS # (
        .DIFF_TERM("FALSE"), // differential termination
        .IBUF_LOW_PWR("TRUE"), // low power vs. performance setting for referenced I/O standards
        .IOSTANDARD("DEFAULT") // specify the input I/O standard
    ) IBUFDS_ext_clk_inst (
        .O(clk), // buffer output
        .I(clk_p), // diff_p buffer input (connect directly to top-level port)
        .IB(clk_n) // diff_n buffer input (connect directly to top-level port)
    );

/*module Testbench_All;

    wire clk;
    Clock clock(
        .clk(clk)
    );*/

    `include "MyParameters.vh"

    //--------//
    // Common //
    //--------//

    reg reset = 0;

    //-----//
    // HNM //
    //-----//

    // Pass SSIDs in here. Watch HNM_SSID_passed and HNM_hitExisted. This will
    // return the SSIDs after they're done storing, along with whether there
    // was a hit in there previously.

    reg HNM_writeSSID = 0;
    reg [SSIDBITS-1:0] HNM_SSID_toWrite;

    wire [SSIDBITS-1:0] HNM_SSID_passed;
    wire HNM_hitExisted;
    wire HNM_newOutput;

    wire [ROWINDEXBITS_HNM-1:0] HNM_rowPassed;
    wire [NCOLS_HNM-1:0] HNM_rowReadOutput;
    wire HNM_readReady, HNM_writeReady, HNM_busy;

    HNMPP HNM (
        .clk(clk),
        .reset(reset),
        .write(HNM_writeSSID),
        .SSID_write(HNM_SSID_toWrite),
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
    // newly stored. Watch as the SSIDs come back out, along with the HIM
    // address and how many hits were pre-existing.

    (*mark_debug="TRUE"*)
    wire [ROWINDEXBITS_HCM-1:0] HCM_SSID_passed;
    (*mark_debug="TRUE"*)
    wire [MAXHITNBITS-1:0] HCM_nOldHits;
    (*mark_debug="TRUE"*)
    wire [MAXHITNBITS-1:0] HCM_nNewHits;
    (*mark_debug="TRUE"*)
    wire HCM_newOutput;

    wire HCM_readReady, HCM_writeReady, HCM_busy;

    reg [HITINFOBITS-1:0] inputHitInfo;
    (*mark_debug="TRUE"*)
    wire [NCOLS_HIM-1:0] HCM_newHitInfo;

    HCMPP HCM (
        .clk(clk),
        .reset(reset),
        .writeRow(HNM_newOutput),
        .inputRowToWrite(HNM_SSID_passed),
        .SSIDIsNew(~HNM_hitExisted),
        .inputRowToRead(0),
        .readRow(0),
        .inputHitInfo({16'b0, HNM_SSID_passed}),
        .rowPassed(HCM_SSID_passed),
        .nOldHits(HCM_nOldHits),
        .nNewHits(HCM_nNewHits),
        .outputNewHitInfo(HCM_newHitInfo),
        .newOutput(HCM_newOutput),
        .writeReady(HCM_writeReady),
        .readReady(HCM_readReady),
        .busy(HCM_busy)
    );
    
    //------------------//
    // VALIDATION TESTS //
    //------------------//

    reg [2:0] testNumber = 0;
    // 000 = none; 001 = store SSIDs from list

    reg [2:0] currentTest = 0; // currently performing test number
    reg [SSIDBITS-1:0] testingSSID = 0; // SSID for reading and writing

    reg [ROWINDEXBITS_HNM-1:0] testingSSID_row[22:0] = {8, 8, 8, 8, 8, 8, 8, 8, 2, 9, 4, 12, 3, 3, 8, 4, 4, 4, 4, 4, 4, 4, 4};
    reg [COLINDEXBITS_HNM-1:0] testingSSID_col[22:0] = {8, 0, 7, 8, 8, 8, 5, 11, 11, 7, 1, 7, 5, 6, 8, 12, 4, 4, 7, 2, 1, 8, 6};

    integer currentTime = 0;

    initial begin
        //$monitor ("%b\t%d\t%d\t%b", HNM_newOutput, HNM_SSID_passed[SSIDBITS-1:COLINDEXBITS_HNM], HNM_SSID_passed[COLINDEXBITS_HNM-1:0], HNM_hitExisted);
        //$monitor ("%b\t%d\t%d\t%b", HCM_newOutput, HCM_SSID_passed[SSIDBITS-1:COLINDEXBITS_HNM], HCM_SSID_passed[COLINDEXBITS_HNM-1:0], HCM_nHits);
        $monitor ("%b\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d", HCM_newOutput, HCM_SSID_passed, HCM_SSID_passed[SSIDBITS-1:COLINDEXBITS_HNM], HCM_SSID_passed[COLINDEXBITS_HNM-1:0], HCM_nOldHits, HCM_nNewHits, HCM_newHitInfo[ROWINDEXBITS_HCM-1:0], HCM_newHitInfo[HITINFOBITS+ROWINDEXBITS_HCM-1:HITINFOBITS], HCM_newHitInfo[HITINFOBITS*2+ROWINDEXBITS_HCM:HITINFOBITS*2], HCM_newHitInfo[HITINFOBITS*3+ROWINDEXBITS_HCM:HITINFOBITS*3]);
    end

    always @(posedge clk) begin

        currentTime <= currentTime + 1;

        if (currentTest == 2'b00) begin // if not already testing
            currentTest <= testNumber; // start testing
        end

        //--------------//
        // SET UP TESTS //
        //--------------//

        if (currentTime == 0) begin
            reset <= 1;
            $display ("Reset");
        end
        if (currentTime == 1) reset <= 0;

        if (currentTime == 200) begin
            testNumber <= 3'b001; // store SSIDs from list
            $display ("Storing SSIDs from list");
        end
        if (currentTime == 201) testNumber <= 3'b000;

        if (currentTime > 400) begin
            reset <= 0;
            currentTime <= 0;
        end

        //------------------//
        // CONTENT OF TESTS //
        //------------------//

        HNM_writeSSID <= 0;

        if (currentTest == 3'b001) begin // store SSIDs from list
            HNM_writeSSID <= 1'b1; // write enabled
            HNM_SSID_toWrite <= {testingSSID_row[testingSSID], testingSSID_col[testingSSID]};
            testingSSID <= testingSSID + 1; // increment SSID
            if (testingSSID >= 22) begin // if the SSID we just read is the last one
                testingSSID <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end
    end
endmodule
