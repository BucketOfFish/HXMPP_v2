`timescale 1ns / 1ps

//-------------------//
// Testbench for HXM //
//-------------------//

/*module Testbench_All(
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
    );*/

module Testbench_All;

    wire clk;
    Clock clock(
        .clk(clk)
    );

    `include "MyParameters.vh"

    //-------//
    // HNMPP //
    //-------//

    // Pass SSIDs and hit infos in here. Can read or write.

    reg reset = 0;
    reg write = 0;
    reg [ROWINDEXBITS_HCM-1:0] writeSSID;
    reg [HITINFOBITS-1:0] writeHitInfo;
    reg read = 0;
    reg [ROWINDEXBITS_HCM-1:0] readSSID;

    wire readFinished;
    wire [SSIDBITS-1:0] SSID_read;
    wire hitThisEvent;
    wire [MAXHITNBITS-1:0] nHits;
    wire [NCOLS_HIM-1:0] hitInfo_read;

    hxmpp hxm (
        .clk(clk),
        .reset(reset),
        .write(write),
        .writeSSID(writeSSID),
        .writeHitInfo(writeHitInfo),
        .read(read),
        .readSSID(readSSID),
        .readFinished(readFinished),
        .SSID_read(SSID_read),
        .hitThisEvent(hitThisEvent),
        .nHits(nHits),
        .hitInfo_read(hitInfo_read)
    );

    //------------------//
    // VALIDATION TESTS //
    //------------------//

    reg [2:0] testNumber = 0;
    // 000 = none; 001 = store SSIDs from list; 010 = read SSIDs

    reg [2:0] currentTest = 0; // currently performing test number
    reg [5:0] testingIndex = 0; // SSID and hit info for reading and writing

    reg [ROWINDEXBITS_HNM-1:0] testingSSID_row[22:0] = {8, 8, 8, 8, 8, 8, 8, 8, 2, 9, 4, 12, 3, 3, 8, 4, 4, 4, 4, 4, 4, 4, 4};
    reg [COLINDEXBITS_HNM-1:0] testingSSID_col[22:0] = {8, 0, 7, 0, 8, 8, 5, 11, 11, 7, 1, 7, 5, 6, 8, 12, 4, 4, 7, 2, 1, 8, 6};
    reg [HITINFOBITS-1:0] testingHitInfo[22:0] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23};

    integer currentTime = 0;

    initial begin
        //$monitor ("%b\t%d\t%d\t%b", HNM_newOutput, HNM_SSID_passed[SSIDBITS-1:COLINDEXBITS_HNM], HNM_SSID_passed[COLINDEXBITS_HNM-1:0], HNM_hitExisted);
        //$monitor ("%b\t%d\t%d\t%b", HCM_newOutput, HCM_SSID_passed[SSIDBITS-1:COLINDEXBITS_HNM], HCM_SSID_passed[COLINDEXBITS_HNM-1:0], HCM_nHits);
        //$monitor ("HCM\t%b\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d", HCM_newOutput, HCM_SSID_passed, HCM_SSID_passed[SSIDBITS-1:COLINDEXBITS_HNM], HCM_SSID_passed[COLINDEXBITS_HNM-1:0], HCM_nOldHits, HCM_nNewHits, HIM_address, HCM_newHitInfo[ROWINDEXBITS_HCM-1:0], HCM_newHitInfo[HITINFOBITS+ROWINDEXBITS_HCM-1:HITINFOBITS], HCM_newHitInfo[HITINFOBITS*2+ROWINDEXBITS_HCM:HITINFOBITS*2], HCM_newHitInfo[HITINFOBITS*3+ROWINDEXBITS_HCM:HITINFOBITS*3]);
        $monitor ("%b\t%d\t%b\t%d\t%d\t%d\t%d\t%d", readFinished, SSID_read, hitThisEvent, nHits, hitInfo_read[ROWINDEXBITS_HCM-1:0], hitInfo_read[HITINFOBITS+ROWINDEXBITS_HCM-1:HITINFOBITS], hitInfo_read[HITINFOBITS*2+ROWINDEXBITS_HCM:HITINFOBITS*2], hitInfo_read[HITINFOBITS*3+ROWINDEXBITS_HCM:HITINFOBITS*3]);
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

        if (currentTime == 400) begin
            testNumber <= 3'b010; // reading SSIDs from list
            $display ("Reading SSIDs from list");
        end
        if (currentTime == 401) testNumber <= 3'b000;

        if (currentTime > 600) begin
            currentTime <= 0;
        end

        //------------------//
        // CONTENT OF TESTS //
        //------------------//

        write <= 0;
        read <= 0;

        if (currentTest == 3'b001) begin // store SSIDs from list
            write <= 1'b1; // write enabled
            writeSSID <= {testingSSID_row[testingIndex], testingSSID_col[testingIndex]};
            //writeHitInfo <= testingHitInfo[testingIndex];
            writeHitInfo <= {testingSSID_row[testingIndex], testingSSID_col[testingIndex]};
            testingIndex <= testingIndex + 1; // increment index
            if (testingIndex >= 22) begin // if the SSID we just read is the last one
                testingIndex <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        if (currentTest == 3'b010) begin // read SSIDs from list
            read <= 1'b1; // read enabled
            readSSID <= {testingSSID_row[testingIndex], testingSSID_col[testingIndex]};
            testingIndex <= testingIndex + 1; // increment index
            if (testingIndex >= 22) begin // if the SSID we just read is the last one
                testingIndex <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end
    end
endmodule
