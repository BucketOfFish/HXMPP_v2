`timescale 1ns / 1ps

//-------------------//
// Testbench for HCM //
//-------------------//

module Testbench_HCM(
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

/*module Testbench_HCM;

    wire clk;
    Clock clock(
        .clk(clk)
    );*/

    `include "MyParameters.vh"

    //-----//
    // DUT //
    //-----//

    reg writeRow = 0;
    reg readRow = 0;
    reg reset = 0;
    reg SSIDIsNew = 0;
    reg [ROWINDEXBITS_HCM-1:0] rowToRead, rowToWrite;
    wire [ROWINDEXBITS_HCM-1:0] rowPassed;
    wire [NCOLS_HCM-1:0] rowReadOutput;

    wire readReady, writeReady, busy;

    HCMPP HCM (
        .clk(clk),
        .writeReady(readReady),
        .writeRow(writeRow),
        .inputRowToWrite(rowToWrite),
        .SSIDIsNew(SSIDIsNew), // whether or not this SSID is new for the event
        .readReady(writeReady),
        .inputRowToRead(rowToRead),
        .readRow(readRow),
        .reset(reset),
        .rowPassed(rowPassed),
        .rowReadOutput(rowReadOutput),
        .busy(busy)
    );
    
    //---------------//
    // DEBUG SIGNALS //
    //---------------//

    (*mark_debug="TRUE"*)
    reg [12:0] debugRowReadOutput;
    (*mark_debug="TRUE"*)
    reg [ROWINDEXBITS_HCM-1:0] debugRowPassed;

    // debug signals
    always @(posedge clk) begin
        debugRowReadOutput <= rowReadOutput[12:0];
        debugRowPassed <= rowPassed;
    end
    
    //------------------//
    // VALIDATION TESTS //
    //------------------//

    reg [2:0] testNumber = 0;
    // 000 = none; 001 = print BRAM; 010 = store incrementing; 011 = store SSIDs from list

    reg [2:0] currentTest = 0; // currently performing test number
    reg [ROWINDEXBITS_HCM-1:0] testingRow = 0; // row number for reading and writing
    reg [SSIDBITS-1:0] testingSSID = 0; // SSID for reading and writing

    reg [ROWINDEXBITS_HCM-1:0] testingStoreRow[22:0] = {0, 3, 1, 1, 1, 1, 1, 3, 4, 7, 2, 1, 5, 4, 4, 2, 8, 9, 65534, 65534, 65534, 65533, 65534};
    reg [ROWINDEXBITS_HCM-1:0] testingSSIDIsNew[22:0] = {1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1};

    integer currentTime = 0;

    initial begin
        $monitor ("%d\t%b", debugRowPassed, debugRowReadOutput[12:0]);
        //$monitor ("%d\t%d\t%b", currentTime, rowPassed, rowReadOutput[12:0]);
        //$monitor ("%g\t%b\t%b", $time, SSID_passed[6:0], HCM_readOutput);
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
            testNumber <= 3'b001; // print BRAM
            $display ("Printing initial BRAM");
        end
        if (currentTime == 1) testNumber <= 3'b000;

        /*if (currentTime == 200) begin
            testNumber <= 3'b010; // store incrementing
            $display ("Storing incrementing rows");
        end
        if (currentTime == 201) testNumber <= 3'b000;*/

        if (currentTime == 200) begin
            testNumber <= 3'b011; // store SSIDs from list
            $display ("Storing SSIDs from list");
        end
        if (currentTime == 201) testNumber <= 3'b000;

        if (currentTime == 400) begin
            testNumber <= 3'b001; // print BRAM again
            $display ("Printing final BRAM");
        end
        if (currentTime == 401) testNumber <= 3'b000;

        if (currentTime == 600) begin
            reset <= 1;
            $display ("Reset");
        end
        if (currentTime > 600) begin
            reset <= 0;
            currentTime <= 0;
        end

        //------------------//
        // CONTENT OF TESTS //
        //------------------//

        readRow <= 0;
        writeRow <= 0;

        if (currentTest == 3'b001) begin // print BRAM
            readRow <= 1'b1; // read enabled
            rowToRead <= testingRow; // row to read
            testingRow <= testingRow + 1; // increment row
            if (testingRow == 49) begin // read the first 50 rows
                testingRow <= NROWS_HCM - 50;
            end
            else if (testingRow == NROWS_HCM - 1) begin // read the last 50 rows
                testingRow <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b010) begin // store incrementing
            writeRow <= 1'b1; // write enabled
            rowToWrite <= testingRow; // row number
            SSIDIsNew <= 1; // every row is new for this event
            testingRow <= testingRow + 1; // increment row
            if (testingRow == 49) begin // first 50 rows
                testingRow <= NROWS_HCM - 50;
            end
            else if (testingRow == NROWS_HCM - 1) begin // last 50 rows
                testingRow <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b011) begin // store SSIDs from list
            writeRow <= 1'b1; // write enabled
            rowToWrite <= testingStoreRow[testingSSID];
            SSIDIsNew <= testingSSIDIsNew[testingSSID];
            testingSSID <= testingSSID + 1; // increment SSID
            if (testingSSID >= 22) begin // if the SSID we just read is the last one
                testingSSID <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end
    end
endmodule
