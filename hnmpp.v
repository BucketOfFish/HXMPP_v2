`timescale 1ns / 1ps

module HNMPP(
    input clk,
    input [SSIDBITS-1:0] SSID,
    input write,
    input read,
    input reset,
    output reg HNM_writeReady,
    output reg HNM_readReady,
    output reg HNM_SSIDHit,
    output testResult
    );

    `include "MyParameters.vh"

    //------------//
    // SPLIT SSID //
    //------------//

    wire [ROWINDEXBITS_HNM-1:0] SSID_Row;
    wire [COLINDEXBITS_HNM-1:0] SSID_Col;
    assign {SSID_Row, SSID_Col} = SSID;

    //-------------//
    // HNM BRAM IP //
    //-------------//

    reg [ROWINDEXBITS_HNM-1:0] rowToWrite;
    reg [NCOLS_HNM-1:0] dataToStore;
    reg writeToBRAM;
    reg [ROWINDEXBITS_HNM-1:0] rowToRead;
    wire [NCOLS_HNM-1:0] dataRead;
    reg readFromBRAM;

    assign testResult = (dataRead == 0); // used for reset test

    hnmpp HNM (
        .clka(clk),
        .ena(1'b1),
        .wea(writeToBRAM),
        .addra(rowToWrite),
        .dina(dataToStore),
        .douta(),
        .clkb(clk),
        .enb(1'b1),
        .web(readFromBRAM),
        .addrb(rowToRead),
        .dinb(),
        .doutb(dataRead)
        );

    //--------------//
    // RESET STATUS //
    //--------------//

    reg resetStatus = 2'b00; // 00 = idle; 01 = resetting BRAM; 10 = last row reset; 11 = complete
    reg [ROWINDEXBITS_HNM-1:0] resetRow = 0;
    reg [3:0] resetDelay = 0; // wait a safe amount of time after resetting before resuming read and write

    always @(posedge clk) begin

        //-----------//
        // RESET HNM //
        //-----------//

        if (reset == 1'b1) begin // reset pushed - takes precedence over everything else
            HNM_writeReady <= 1'b0; // do not write until reset is complete
            HNM_readReady <= 1'b0; // do not read until reset is complete
            writeToBRAM <= 1'b0; // not currently writing
            readFromBRAM <= 1'b0; // not currently reading
            //clear queues 
            resetStatus <= 1'b1; // start resetting BRAM
            resetRow <= 0; // start with the first row
            resetDelay <= 0; // reset the safe delay count
        end

        else if (resetStatus != 2'b00) begin // in the process of resetting

            if (resetStatus == 2'b01) begin // resetting BRAM
                writeToBRAM <= 1'b1; // write enabled
                rowToWrite <= resetRow; // row to reset
                dataToStore <= 0; // reset the row
                resetRow <= resetRow + 1; // increment row
                if (resetRow >= NROWS_HNM-1) begin // if the row we just reset is the last one
                    resetStatus <= 2'b10; // continue to the next step
                end
            end

            else if (resetStatus == 2'b10) begin // last row has reset - wait until safe
                writeToBRAM <= 1'b0; // stop writing
                resetDelay <= resetDelay + 1;
                if (resetDelay >= BRAM_WRITEDELAY-1) begin
                    resetStatus <= 2'b11;
                end
            end

            else if (resetStatus == 2'b11) begin // ready to go back to normal operation
                HNM_writeReady <= 1'b1; // ready to write
                HNM_readReady <= 1'b1; // ready to read
                resetStatus <= 2'b00; // finished resetting
            end
        end

        //----------------//
        // READ AND WRITE //
        //----------------//

        else begin
            writeToBRAM <= 1'b0;
            readFromBRAM <= 1'b0;
        end

    end

endmodule
