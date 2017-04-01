`timescale 1ns / 1ps

//-------------------//
// Testbench for HNM //
//-------------------//

module Testbench_HNM;

    `include "MyParameters.vh"

    wire clk;
    
    Clock clock(
        .clk(clk)
    );

    //-----//
    // DUT //
    //-----//

    reg reset = 0;
    reg writeSSID = 0, writeRow = 0;
    reg readSSID = 0, readRow = 0;
    reg fillSequentialRows = 0;
    reg [SSIDBITS-1:0] SSID_toWrite, SSID_toRead;
    reg [ROWINDEXBITS_HNM-1:0] rowToRead, rowToWrite;
    wire [ROWINDEXBITS_HNM-1:0] rowPassed;
    wire [NCOLS_HNM-1:0] rowReadOutput;
    reg [NCOLS_HNM-1:0] dataToWrite;
    wire [SSIDBITS-1:0] SSID_passed;
    wire HNM_readOutput;

    HNMPP HNM (
        .clk(clk),
        .reset(reset),
        .writeReady(),
        .SSID_write(SSID_toWrite),
        .write(writeSSID),
        .writeRow(writeRow),
        .rowWrite(rowToWrite),
        .dataWrite(dataToWrite),
        .readReady(),
        .SSID_read(SSID_toRead),
        .read(readSSID),
        .rowRead(rowToRead),
        .readRow(readRow),
        .fillSequentialRows(fillSequentialRows),
        .SSID_passed(SSID_passed),
        .HNM_readOutput(HNM_readOutput),
        .rowPassed(rowPassed),
        .rowReadOutput(rowReadOutput),
        .busy()
    );
    
    //------------------//
    // VALIDATION TESTS //
    //------------------//

    reg [2:0] testNumber = 0;
    // 000 = none; 001 = print BRAM; 010 = store alternating; 011 = store incrementing
    // 100 = read SSIDs; 101 = store checkerboard pattern; 110 = store SSIDs from list

    reg [2:0] currentTest = 0; // currently performing test number
    reg [ROWINDEXBITS_HNM-1:0] testingRow = 0; // row number for reading and writing
    reg [SSIDBITS-1:0] testingSSID = 0; // SSID for reading and writing

    reg [ROWINDEXBITS_HNM-1:0] testingSSID_row[45:0] = {8, 8, 8, 8, 8, 8, 8, 8, 2, 9, 4, 12, 3, 3, 1, 4, 4, 4, 4, 4, 4, 4, 4};
    reg [COLINDEXBITS_HNM-1:0] testingSSID_col[45:0] = {0, 3, 7, 8, 8, 8, 5, 11, 11, 7, 1, 7, 5, 6, 8, 12, 4, 4, 7, 2, 1, 8, 6};
    //8 8 8 8 8 8 8  8  2 9 4 12 3 3 1  4 4 4 4 4 4 4 4
    //0 3 7 8 8 8 5 11 11 7 1  7 5 6 8 12 4 4 7 2 1 8 6

    always @(testNumber) begin // whenever the test number changes
        if (currentTest == 2'b00) begin // if not already testing
            currentTest <= testNumber; // start testing
        end
    end

    initial begin

        //$monitor ("%g\t%b\t%b", $time, rowPassed, rowReadOutput[6:0]);
        //$monitor ("%g\t%b\t%b", $time, rowPassed, rowReadOutput[12:0]);
        //$monitor ("%g\t%b\t%b", $time, SSID_passed[6:0], HNM_readOutput);

        testNumber = 3'b001; // print BRAM
        $display ("Printing initial BRAM");
        #5 testNumber = 3'b000;

        #2000 reset = 1; // reset
        $display ("Resetting BRAM");
        #5 reset = 0;

        #2000 testNumber = 3'b001; // print BRAM again
        $display ("Printing second BRAM");
        #5 testNumber = 3'b000;

        //#2000 testNumber = 3'b011; // store row numbers
        //$display ("Storing row numbers");
        //#5 testNumber = 3'b000;

        //#2000 testNumber = 3'b010; // store alternating 0's and 1's, one at a time
        //$display ("Storing alternating bits");
        //#5 testNumber = 3'b000;

        #2000 testNumber = 3'b110; // store SSIDs from list
        $display ("Storing SSIDs from list");
        #5 testNumber = 3'b000;

        //#2000 testNumber = 3'b101; // store checkerboard pattern, one row at a time
        //$display ("Storing checkerboard pattern");
        //#5 testNumber = 3'b000;

        #2000 testNumber = 3'b001; // print BRAM again
        $display ("Printing final BRAM");
        #5 testNumber = 3'b000;

        //#2000 testNumber = 3'b100; // print SSIDs
        //$display ("Printing SSIDs");
        //#5 testNumber = 3'b000;
    end

    always @(posedge clk) begin

        readSSID <= 0;
        readRow <= 0;
        writeSSID <= 0;
        writeRow <= 0;

        if (currentTest == 3'b001) begin // print BRAM
            readRow <= 1'b1; // read enabled
            rowToRead <= testingRow; // row to read
            testingRow <= testingRow + 1; // increment row
            if (testingRow >= NROWS_HNM-1) begin // if the row we just read is the last one
                testingRow <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b010) begin // store alternating bits
            if (testingSSID[0] == 1'b1) begin // write based on the last digit of the SSID
                writeSSID <= 1'b1; // write enabled
                SSID_toWrite <= testingSSID;
            end
            testingSSID <= testingSSID + 1; // increment SSID
            if (testingSSID >= NROWS_HNM-1) begin // if the SSID we just read is the last one
                testingSSID <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b011) begin // store entire matrix
            writeRow <= 1'b1; // write enabled
            rowToWrite <= testingRow; // row number
            dataToWrite <= testingRow; // just write the row number
            testingRow <= testingRow + 1; // increment row
            if (testingRow >= NROWS_HNM-1) begin // if the SSID we just read is the last one
                testingRow <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b101) begin // store checkerboard pattern
            writeRow <= 1'b1; // write enabled
            rowToWrite <= testingRow; // row number
            dataToWrite <= 8'b01010101; // checkerboard pattern
            testingRow <= testingRow + 1; // increment row
            if (testingRow >= NROWS_HNM-1) begin // if the SSID we just read is the last one
                testingRow <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b100) begin // print SSIDs
            readSSID <= 1'b1; // read enabled
            SSID_toRead <= testingSSID; // read sequential SSIDs
            testingSSID <= testingSSID + 1; // increment SSID
            if (testingSSID >= 1000) begin // if we pass some number
                testingSSID <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end

        else if (currentTest == 3'b110) begin // store SSIDs from list
            writeSSID <= 1'b1; // write enabled
            SSID_toWrite <= {testingSSID_row[testingSSID], testingSSID_col[testingSSID]};
            testingSSID <= testingSSID + 1; // increment SSID
            if (testingSSID >= 45-1) begin // if the SSID we just read is the last one
                testingSSID <= 0;
                testNumber <= 3'b000; // stop testing
                currentTest <= 0;
            end
        end
    end
endmodule
