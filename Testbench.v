`timescale 1ns / 1ps

//-----------//
// Testbench //
//-----------//

module Testbench();

    wire clk;
    reg reset = 0;
    reg read = 1;
    reg write = 1;
    wire [7:0] SSID_write, SSID_read;

    initial begin
        //$monitor ("%g\t%b\t%b\t%b", $time, clk, SSID_write, SSID_read);
    end
    
    Clock clock(
        .clk(clk)
    );
    
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

    HNMPP HNM (
        .SSID(),
        .write(),
        .read(),
        .reset(),
        .HNM_writeReady(),
        .HNM_readReady(),
        .HNM_SSIDHit()
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
