`timescale 1ns / 1ps

module HNMPP(
    input clk,
    input [SSIDBITS-1:0] SSID_write,
    input write,
    input [SSIDBITS-1:0] SSID_read,
    input read,
    input reset,
    output reg HNM_writeReady,
    output reg HNM_readReady,
    output reg [SSIDBITS-1:0] HNM_SSID_read, // the SSID just read
    output reg HNM_SSIDHit, // whether or not HNM stored 1 for that SSID
    output testResult
    );

    `include "MyParameters.vh"

    //------------//
    // SPLIT SSID //
    //------------//

    wire [ROWINDEXBITS_HNM-1:0] SSID_writeRow, SSID_readRow;
    wire [COLINDEXBITS_HNM-1:0] SSID_writeCol, SSID_readCol;
    assign {SSID_writeRow, SSID_writeCol} = SSID_write;
    assign {SSID_readRow, SSID_readCol} = SSID_read;

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

    hnmpp HNM_BRAM (
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

    //-----------------//
    // HNM WRITE QUEUE //
    //-----------------//

    reg [ROWINDEXBITS_HNM-1:0] queueRowIndex [QUEUESIZE-1:0];
    reg [NCOLS_HNM-1:0] queueNewHitsRow [QUEUESIZE-1:0];
    reg [QUEUESIZE-1:0] queueFilled;

    //--------------//
    // RESET STATUS //
    //--------------//

    reg resetStatus = 2'b00; // 00 = idle; 01 = resetting BRAM; 10 = last row reset; 11 = complete
    reg [ROWINDEXBITS_HNM-1:0] resetRow = 0;
    reg [3:0] resetDelay = 0; // wait a safe amount of time after resetting before resuming read and write

    //---------//
    // TESTING //
    //---------//

    reg [1:0] test = 0; // 01 = fill sequentially; 10 = read all rows
    reg [1:0] testType = 0;
    reg testStatus = 2'b00; // 00 = idle; 01 = testing; 10 = test finished; 11 = ready to go
    reg [ROWINDEXBITS_HNM-1:0] testRow = 0;
    reg [3:0] testDelay = 0; // wait a safe amount of time after testing before resuming read and write

    initial begin
        test = 2'b01;
        $display ("Filling BRAM");
        $monitor ("%g\t%b\t%b", $time, rowToWrite, dataToStore);
        #5 test = 0;
        #1000 test = 2'b10;
        $display ("Reading BRAM");
        $monitor ("%g\t%b\t%b", $time, rowToRead, dataRead);
        #5 test = 0;
    end

    always @(posedge clk) begin

        //-----------//
        // TEST FILL //
        //-----------//

        if (test != 2'b00) begin // testing - takes precedence over everything else

            testType <= test; // remember what test we're doing
            HNM_writeReady <= 1'b0; // do not write until test is complete
            HNM_readReady <= 1'b0; // do not read until test is complete
            writeToBRAM <= 1'b0; // not currently writing
            readFromBRAM <= 1'b0; // not currently reading
            testStatus <= 2'b01; // start testing
            testRow <= 0; // start with the first row
            testDelay <= 0; // reset the safe delay count
        end

        else if (testStatus != 2'b00) begin // in the process of testing

            //-----------//
            // FILL BRAM //
            //-----------//

            if (testType == 2'b01) begin
                if (testStatus == 2'b01) begin // filling BRAM sequentially
                    writeToBRAM <= 1'b1; // write enabled
                    rowToWrite <= testRow; // row to fill
                    dataToStore <= testRow; // value to fill is row number
                    testRow <= testRow + 1; // increment row
                    if (testRow >= NROWS_HNM-1) begin // if the row we just filled is the last one
                        testStatus <= 2'b10; // continue to the next step
                    end
                end

                else if (testStatus == 2'b10) begin // last row has filled - wait until safe
                    writeToBRAM <= 1'b0; // stop writing
                    testDelay <= testDelay + 1;
                    if (testDelay >= BRAM_WRITEDELAY-1) begin
                        testStatus <= 2'b11;
                    end
                end

                else if (testStatus == 2'b11) begin // ready to go back to normal operation
                    HNM_writeReady <= 1'b1; // ready to write
                    HNM_readReady <= 1'b1; // ready to read
                    testStatus <= 2'b00; // finished testing
                end
            end

            //-----------//
            // READ ROWS //
            //-----------//

            else if (testType == 2'b10) begin
                if (testStatus == 2'b01) begin // reading all rows
                    readFromBRAM <= 1'b1; // read enabled
                    rowToRead <= testRow; // row to read
                    testRow <= testRow + 1; // increment row
                    if (testRow >= NROWS_HNM-1) begin // if the row we just read is the last one
                        testStatus <= 2'b10; // continue to the next step
                    end
                end

                else if (testStatus == 2'b10) begin // last row has been read - wait until safe
                    readFromBRAM <= 1'b0; // stop reading
                    testDelay <= testDelay + 1;
                    if (testDelay >= BRAM_WRITEDELAY-1) begin
                        testStatus <= 2'b11;
                    end
                end

                else if (testStatus == 2'b11) begin // ready to go back to normal operation
                    HNM_writeReady <= 1'b1; // ready to write
                    HNM_readReady <= 1'b1; // ready to read
                    testStatus <= 2'b00; // finished testing
                end
            end
        end

        //-----------//
        // RESET HNM //
        //-----------//

        else if (reset == 1'b1) begin // reset pushed - takes precedence over everything except testing
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

            writeToBRAM <= 1'b0; // don't write
            readFromBRAM <= 1'b0; // don't read

            //---------------//
            // WRITE TO BRAM //
            //---------------//

    //reg [ROWINDEXBITS_HNM-1:0] queueRowIndex [QUEUESIZE-1:0];
    //reg [NCOLS_HNM-1:0] queueNewHitsRow [QUEUESIZE-1:0];
    //reg [QUEUESIZE-1:0] queueFilled;

            if (write == 1'b1) begin // writing takes precedence over reading
                
            end

            //----------------//
            // READ FROM BRAM //
            //----------------//

            else if (read == 1'b1) begin // do not allow reading if writing is in process
            end
        end

    end

    //-------//
    // FIFOS //
    //-------//

    /*SSID_FIFO SSID_HNM_read ( // this FIFO stores the SSIDs from read requests
        .clk(clk),
        .srst(reset),
        .wr_en(read), // store an incoming SSID when the read flag is high
        .din(SSID_read), // track the SSID to read
        .rd_en(),
        .dout(),
        .full(),
        .empty()
    );*/

endmodule
