`timescale 1ns / 1ps

//-----------//
// Testbench //
//-----------//

module Testbench();

    `include "MyParameters.vh"

    wire clk;
    
    Clock clock(
        .clk(clk)
    );

    reg reset = 0;
    reg read = 1;
    reg write = 1;
    reg [7:0] SSID;
    
    /*Counter counter(
        .clk(clk),
        .reset(reset),
        .enable(1),
        .count(SSID_write)
    );*/
    
    /*SSID_FIFO SSID_List (
        .clk(clk),      // input wire clk
        .srst(reset),    // input wire srst
        .din(SSID_write),      // input wire [7 : 0] din
        .wr_en(write),  // input wire wr_en
        .rd_en(read),  // input wire rd_en
        .dout(SSID_read),    // output wire [7 : 0] dout
        .full(),    // output wire full
        .empty()  // output wire empty
    );*/

    //------------------//
    // VALIDATION TESTS //
    //------------------//

    reg [1:0] testNumber = 0; // 00 = no test; 01 = print BRAM

    reg [1:0] testing = 0; // currently performing test number
    reg [NROWS_HNM-1:0] testingRow = 0; // test parameter

    always @(testNumber) begin // whenever the test number changes
        if (testing == 2'b00) begin // if not already testing
            testing <= testNumber; // start testing
        end
    end

    initial begin
        $monitor ("%g\t%b\t%b", $time, SSID, testResult);
        testNumber = 2'b01; // print BRAM
        $display ("Printing initial BRAM");
        #5 testNumber = 2'b00;
        #1000 reset = 1; // reset
        $display ("Resetting BRAM");
        #5 reset = 0;
        #1000 testNumber = 2'b01; // print BRAM again
        $display ("Printing final BRAM");
        #5 testNumber = 2'b00;
    end

    always @(posedge clk) begin

        if (testing == 2'b01) begin // print BRAM
            read <= 1'b1; // read enabled
            SSID <= testingRow; // row to read
            testingRow <= testingRow + 1; // increment row
            if (testingRow >= NROWS_HNM-1) begin // if the row we just read is the last one
                testingRow <= 0;
                testNumber <= 2'b00; // stop testing
                testing <= 0;
            end
        end
    end

    //-----//
    // DUT //
    //-----//

    HNMPP HNM (
        .clk(clk),
        .SSID(SSID),
        .write(write),
        .read(read),
        .reset(reset),
        .HNM_writeReady(),
        .HNM_readReady(),
        .HNM_SSIDHit(),
        .testResult(testResult)
    );

endmodule

//-------//
// Clock //
//-------//

module Clock
(output reg clk);

    initial begin
        $display ("Starting clock");
        clk = 0;
    end
    
    always begin
        #5 clk = ~clk;
    end

endmodule
