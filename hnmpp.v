`timescale 1ns / 1ps

module HNMPP(
    input clk,
    input reset,
    input [SSIDBITS-1:0] SSID_write,
    input [ROWINDEXBITS_HNM-1:0] rowWrite,
    input [NCOLS_HNM-1:0] dataWrite,
    input write,
    input writeRow,
    input [SSIDBITS-1:0] SSID_read,
    input [ROWINDEXBITS_HNM-1:0] rowRead,
    input read,
    input readRow,
    input fillSequentialRows,
    output reg writeReady,
    output reg readReady,
    output reg [SSIDBITS-1:0] SSID_passed, // the SSID just read
    output reg HNM_readOutput, // whether or not HNM stored 1 for that SSID
    output reg [ROWINDEXBITS_HNM-1:0] rowPassed,
    output reg [NCOLS_HNM-1:0] rowReadOutput,
    output reg newOutput = 0,
    output reg busy
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

    reg writeToBRAM = 0;
    reg [ROWINDEXBITS_HNM-1:0] rowToWrite;
    reg [NCOLS_HNM-1:0] dataToWrite;
    reg [ROWINDEXBITS_HNM-1:0] rowToRead;
    wire [NCOLS_HNM-1:0] dataRead;

    wire [NCOLS_HNM-1:0] dummyRead;
    reg [NCOLS_HNM-1:0] dummyWrite = 0;

    hnmpp HNM_BRAM (
        .clka(clk),
        .ena(1'b1),
        .wea(writeToBRAM),
        .addra(rowToWrite),
        .dina(dataToWrite),
        .douta(dummyRead),
        .clkb(clk),
        .enb(1'b1),
        .web(1'b0),
        .addrb(rowToRead),
        .dinb(dummyWrite),
        .doutb(dataRead)
        );

    //-----------------//
    // HNM WRITE QUEUE //
    //-----------------//

    reg [ROWINDEXBITS_HNM-1:0] queueWriteRow [QUEUESIZE-1:0];
    reg [NCOLS_HNM-1:0] queueNewHitsRow [QUEUESIZE-1:0];
    reg [QUEUESIZEBITS-1:0] nInWriteQueue = 0;
    reg [QUEUESIZE-1:0] waitTimeWriteQueue [2:0];

    wire writeQueueShifted;
    wire [QUEUESIZEBITS-1:0] nInWriteQueueAfterShift;
    assign writeQueueShifted = (nInWriteQueue > 0) && (waitTimeWriteQueue[0] == 0);
    assign nInWriteQueueAfterShift = nInWriteQueue - writeQueueShifted;

    reg inQueue = 0; // whether new write rows are already in queue

    //----------------//
    // HNM READ QUEUE //
    //----------------//

    reg [ROWINDEXBITS_HNM-1:0] queueReadRow [QUEUESIZE-1:0];
    reg [COLINDEXBITS_HNM-1:0] queueReadCol [QUEUESIZE-1:0];
    reg [QUEUESIZE-1:0] queueReadWholeRow = 0; // may not be useful - keeping in code for now
    reg [QUEUESIZEBITS-1:0] nInReadQueue = 0;
    reg [QUEUESIZE-1:0] waitTimeReadQueue [2:0];
    reg [QUEUESIZE-1:0] queueRequestedRead = 0; // whether to block result from going to HCM

    wire readQueueShifted;
    wire [QUEUESIZEBITS-1:0] nInReadQueueAfterShift;
    assign readQueueShifted = (nInReadQueue > 0) && (waitTimeReadQueue[0] == 0);
    assign nInReadQueueAfterShift = nInReadQueue - readQueueShifted;

    //---------------------//
    // COLLISION AVOIDANCE //
    //---------------------//

    reg [QUEUESIZE-1:0] collisionDetected = 0;
    reg [NCOLS_HCM-1:0] dataPreviouslyWritten [QUEUESIZE-1:0];

    //-----------//
    // RESETTING //
    //-----------//

    reg [1:0] resetStatus = 2'b00; // 00 = idle; 01 = resetting BRAM; 10 = last row reset; 11 = complete
    reg [ROWINDEXBITS_HNM-1:0] resetRow = 0;
    reg [3:0] resetDelay = 0; // wait a safe amount of time after resetting before resuming read and write

    //-----------------//
    // FILL SEQUENTIAL //
    //-----------------//

    reg [1:0] fillStatus = 2'b00; // 00 = idle; 01 = filling; 10 = fill finished; 11 = ready to go
    reg [ROWINDEXBITS_HNM-1:0] fillRow = 0;
    reg [3:0] fillDelay = 0; // wait a safe amount of time after testing before resuming read and write

    //-----------------//
    // STUPID BULLSHIT //
    //-----------------//

    reg [QUEUESIZEBITS-1:0] queueN = 0; // can't do loop variable declaration

    //---------//
    // TESTING //
    //---------//

    (*mark_debug="TRUE"*)
    reg [ROWINDEXBITS_HNM-1:0] debugQueueWriteRow [QUEUESIZE-1:0];
    (*mark_debug="TRUE"*)
    reg [12:0] debugQueueNewHitsRow [QUEUESIZE-1:0];
    (*mark_debug="TRUE"*)
    reg [ROWINDEXBITS_HNM-1:0] debugRowToRead;
    (*mark_debug="TRUE"*)
    reg [QUEUESIZEBITS-1:0] debugNInReadQueue = 0;

    genvar i;
    generate
        for (i = 0; i < QUEUESIZE; i = i + 1) begin
            always @(posedge clk) begin
                debugQueueWriteRow[i] <= queueWriteRow[i];
                debugQueueNewHitsRow[i] <= queueNewHitsRow[i][12:0];
                debugRowToRead <= rowToRead;
                debugNInReadQueue <= nInReadQueue;
            end
        end
    endgenerate

    initial begin
        //$monitor ("%g\t%b\t%b\t%b", $time, writeToBRAM, rowToWrite, dataToWrite[6:0]);
        //$monitor ("%b\t%b\t%b\t%b", debugQueueWriteRow[0], debugQueueNewHitsRow[0], debugRowToRead, debugNInReadQueue);
        //$monitor ("%d\t%b\t%b", SSID_passed, HNM_readOutput, newOutput);
    end

    /*initial begin
        test = 2'b01;
        $display ("Filling BRAM");
        $monitor ("%g\t%b\t%b\t%b", $time, writeToBRAM, rowToWrite, dataToWrite[6:0]);
        #10 test = 0;
        #2000 test = 2'b10;
        $display ("Reading BRAM");
        $monitor ("%g\t%b\t%b\t%b", $time, testStatus, rowToRead, dataRead[6:0]);
        #10 test = 0;
    end*/

    always @(posedge clk) begin

        //----------------------//
        // TEST FILL SEQUENTIAL //
        //----------------------//

        if (fillSequentialRows == 1'b1) begin // testing - takes precedence over everything else

            writeReady <= 1'b0; // do not write until test is complete
            readReady <= 1'b0; // do not read until test is complete
            busy <= 1'b1; // flag busy
            writeToBRAM <= 1'b0; // not currently writing
            fillStatus <= 2'b01; // start filling
            fillRow <= 0; // start with the first row
            fillDelay <= 0; // reset the safe delay count
        end

        else if (fillStatus != 2'b00) begin // in the process of filling

            if (fillStatus == 2'b01) begin // filling BRAM sequentially
                writeToBRAM <= 1'b1; // write enabled
                rowToWrite <= fillRow; // row to fill
                dataToWrite <= fillRow; // value to fill is row number
                fillRow <= fillRow + 1; // increment row
                if (fillRow >= NROWS_HNM-1) begin // if the row we just filled is the last one
                    fillStatus <= 2'b10; // continue to the next step
                end
            end

            else if (fillStatus == 2'b10) begin // last row has filled - wait until safe
                writeToBRAM <= 1'b0; // stop writing
                fillDelay <= fillDelay + 1;
                if (fillDelay >= BRAM_WRITEDELAY-1) begin
                    fillStatus <= 2'b11;
                end
            end

            else if (fillStatus == 2'b11) begin // ready to go back to normal operation
                writeReady <= 1'b1; // ready to write
                readReady <= 1'b1; // ready to read
                busy <= 1'b0;
                fillStatus <= 2'b00; // finished testing
            end
        end

        //----------------//
        // TEST READ ROWS //
        //----------------//

        /*if (test != 2'b00) begin // testing - takes precedence over everything else

            testType <= test; // remember what test we're doing
            writeReady <= 1'b0; // do not write until test is complete
            readReady <= 1'b0; // do not read until test is complete
            busy <= 1'b1; // flag busy
            writeToBRAM <= 1'b0; // not currently writing
            testStatus <= 2'b01; // start testing
            testRow <= 0; // start with the first row
            testDelay <= 0; // reset the safe delay count
        end

        else if (testStatus != 2'b00) begin // in the process of testing

            else if (testType == 2'b10) begin
                if (testStatus == 2'b01) begin // reading all rows
                    rowToRead <= testRow; // row to read
                    testRow <= testRow + 1; // increment row
                    if (testRow >= NROWS_HNM-1) begin // if the row we just read is the last one
                        testStatus <= 2'b10; // continue to the next step
                    end
                end

                else if (testStatus == 2'b10) begin // last row has been read - wait until safe
                    testDelay <= testDelay + 1;
                    if (testDelay >= BRAM_WRITEDELAY-1) begin
                        testStatus <= 2'b11;
                    end
                end

                else if (testStatus == 2'b11) begin // ready to go back to normal operation
                    writeReady <= 1'b1; // ready to write
                    readReady <= 1'b1; // ready to read
                    busy <= 1'b0;
                    testStatus <= 2'b00; // finished testing
                end
            end
        end*/

        //-----------//
        // RESET HNM //
        //-----------//

        else if (reset == 1'b1) begin // reset pushed - takes precedence over everything except testing
            writeReady <= 1'b0; // do not write until reset is complete
            readReady <= 1'b0; // do not read until reset is complete
            busy <= 1'b1; // flag busy
            writeToBRAM <= 1'b0; // not currently writing

            nInReadQueue <= 0;
            nInWriteQueue <= 0;
            collisionDetected <= 0;

            resetStatus <= 1'b1; // start resetting BRAM
            resetRow <= 0; // start with the first row
            resetDelay <= 0; // reset the safe delay count
        end

        else if (resetStatus != 2'b00) begin // in the process of resetting

            if (resetStatus == 2'b01) begin // resetting BRAM
                writeToBRAM <= 1'b1; // write enabled
                rowToWrite <= resetRow; // row to reset
                dataToWrite <= 0; // reset the row
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
                writeReady <= 1'b1; // ready to write
                readReady <= 1'b1; // ready to read
                busy <= 1'b0;
                resetStatus <= 2'b00; // finished resetting
            end
        end

        //----------------//
        // READ AND WRITE //
        //----------------//

        else begin

            writeToBRAM <= 1'b0; // don't write
            newOutput <= 1'b0; // we did not just read something out

            //----------------------------------//
            // MOVE QUEUE AND RETURN READ VALUE //
            //----------------------------------//

            if (nInReadQueue > 0) begin

                if (waitTimeReadQueue[0] > 0) begin // nothing to be read yet
                    for (queueN = 0; queueN < QUEUESIZE; queueN = queueN + 1) begin
                        waitTimeReadQueue[queueN] <= waitTimeReadQueue[queueN] - 1; // reduce wait times
                    end
                end

                else begin // read the first item

                    for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                        waitTimeReadQueue[queueN] <= waitTimeReadQueue[queueN+1] - 1; // pop an item
                        queueReadRow[queueN] <= queueReadRow[queueN+1]; // pop an item
                        queueReadCol[queueN] <= queueReadCol[queueN+1]; // pop an item
                        collisionDetected[queueN] <= collisionDetected[queueN+1];
                        queueReadWholeRow[queueN] <= queueReadWholeRow[queueN+1]; // pop an item
                        dataPreviouslyWritten[queueN] <= dataPreviouslyWritten[queueN+1];
                        queueRequestedRead[queueN] <= queueRequestedRead[queueN+1]; // pop an item
                    end
                    nInReadQueue <= nInReadQueue - 1; // reduce number of items in queue

                    newOutput <= 1'b1;
                    if (queueRequestedRead[0]) newOutput <= 0; // don't flag the HCM to start if we're just doing a read
                    rowPassed <= queueReadRow[0];
                    rowReadOutput <= dataRead;
                    SSID_passed <= {queueReadRow[0], queueReadCol[0]};
                    HNM_readOutput <= dataRead[queueReadCol[0]];
                    if (collisionDetected[0]) begin
                        rowReadOutput <= dataPreviouslyWritten[0];
                        HNM_readOutput <= dataPreviouslyWritten[0][queueReadCol[0]];
                    end
                end
            end

            //------------------------------//
            // MOVE QUEUE AND WRITE TO BRAM //
            //------------------------------//

            if (nInWriteQueue > 0) begin

                if (waitTimeWriteQueue[0] > 0) begin // nothing to be written yet
                    for (queueN = 0; queueN < QUEUESIZE; queueN = queueN + 1) begin
                        waitTimeWriteQueue[queueN] <= waitTimeWriteQueue[queueN] - 1; // reduce wait times
                    end
                end

                else begin // write the first item
                    for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                        waitTimeWriteQueue[queueN] <= waitTimeWriteQueue[queueN+1] - 1; // pop an item
                        queueWriteRow[queueN] <= queueWriteRow[queueN+1]; // pop an item
                        queueNewHitsRow[queueN] <= queueNewHitsRow[queueN+1]; // pop an item
                    end
                    nInWriteQueue <= nInWriteQueue - 1; // reduce number of items in queue
                    writeToBRAM <= 1'b1;
                    rowToWrite <= queueWriteRow[0];
                    dataToWrite <= dataRead | queueNewHitsRow[0]; // existing hits on row plus new hits

                    dataPreviouslyWritten[nInReadQueueAfterShift] <= dataRead | queueNewHitsRow[0]; // collision
                    if (collisionDetected[0]) begin
                        dataToWrite <= dataPreviouslyWritten[0] | queueNewHitsRow[0];
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= dataPreviouslyWritten[0] | queueNewHitsRow[0]; // in case of collision
                    end
                end
            end

            //--------------------//
            // ADD TO WRITE QUEUE //
            //--------------------//

            /*// this part of the code is blocking, but it shouldn't matter
            if (write == 1'b1) begin // writing requires a row read request first - see below

                inQueue = 0;

                for (queueN = 0; queueN < QUEUESIZE; queueN = queueN + 1) begin
                    if (queueWriteRow[queueN] == SSID_writeRow && waitTimeWriteQueue[queueN] > 0) begin
                        // if the row was already set to write on the clock edge, don't try to add to that row
                        queueNewHitsRow[queueN - writeQueueShifted] <= queueNewHitsRow[queueN] | (1'b1 << SSID_writeCol);
                        inQueue = 1;
                    end
                end

                if (!inQueue) begin
                    queueWriteRow[nInWriteQueueAfterShift] <= SSID_writeRow; // place in queue until read completes
                    queueNewHitsRow[nInWriteQueueAfterShift] <= 1'b1 << SSID_writeCol; // shift by col number
                    waitTimeWriteQueue[nInWriteQueueAfterShift] <= BRAM_READDELAY;
                    nInWriteQueue <= nInWriteQueueAfterShift + 1; // increase the number of items in queue
                end
            end*/

            if (write == 1'b1) begin // writing requires a row read request first - see below

                // write a new item into the queue if the row is new
                queueWriteRow[nInWriteQueueAfterShift] <= SSID_writeRow; // place in queue until read completes
                queueNewHitsRow[nInWriteQueueAfterShift] <= 1'b1 << SSID_writeCol; // shift by col number
                waitTimeWriteQueue[nInWriteQueueAfterShift] <= BRAM_READDELAY;
                nInWriteQueue <= nInWriteQueueAfterShift + 1; // increase the number of items in queue

                for (queueN = 0; queueN < nInWriteQueue; queueN = queueN + 1) begin
                    // if the row was already set to write on the clock edge, don't try to add to that row
                    if (queueWriteRow[queueN] == SSID_writeRow && waitTimeWriteQueue[queueN] > 0) begin
                        queueNewHitsRow[queueN - writeQueueShifted] <= queueNewHitsRow[queueN] | (1'b1 << SSID_writeCol);
                        // undo the new item in queue
                        queueWriteRow[nInWriteQueueAfterShift] <= queueWriteRow[nInWriteQueueAfterShift];
                        queueNewHitsRow[nInWriteQueueAfterShift] <= queueNewHitsRow[nInWriteQueueAfterShift];
                        waitTimeWriteQueue[nInWriteQueueAfterShift] <= waitTimeWriteQueue[nInWriteQueueAfterShift];
                        nInWriteQueue <= nInWriteQueueAfterShift;
                    end
                end
            end

            //-----------//
            // WRITE ROW //
            //-----------//

            else if (writeRow == 1'b1) begin // write a whole row for testing purposes - no need for queue
                writeToBRAM <= 1'b1;
                rowToWrite <= rowWrite;
                dataToWrite <= dataWrite;
            end

            //-------------------//
            // ADD TO READ QUEUE //
            //-------------------//

            else if (read == 1'b1) begin // do not allow reading if writing is in process
                rowToRead <= SSID_readRow; // request read for this row
                queueReadRow[nInReadQueueAfterShift] <= SSID_readRow; // place row in queue until read completes
                queueReadCol[nInReadQueueAfterShift] <= SSID_readCol; // place col in queue until read completes
                queueReadWholeRow[nInReadQueueAfterShift] <= 0; // mark as a single-SSID read
                waitTimeReadQueue[nInReadQueueAfterShift] <= BRAM_READDELAY; // set the wait time
                nInReadQueue <= nInReadQueueAfterShift + 1; // increase the number of items in queue
                queueRequestedRead[nInReadQueueAfterShift] <= 1; // mark as a silent read (don't pass to HCM)
            end

            //-----------------------//
            // ADD TO ROW READ QUEUE //
            //-----------------------//

            if (write == 1'b1) begin // read a whole row - needed before writing
                rowToRead <= SSID_writeRow; // request read for this row
                queueReadRow[nInReadQueueAfterShift] <= SSID_writeRow; // place row in queue until read completes
                queueReadCol[nInReadQueueAfterShift] <= SSID_writeCol; // place row in queue until read completes
                queueReadWholeRow[nInReadQueueAfterShift] <= 1; // mark as a whole-row read
                waitTimeReadQueue[nInReadQueueAfterShift] <= BRAM_READDELAY; // set the wait time
                nInReadQueue <= nInReadQueueAfterShift + 1; // increase the number of items in queue

                collisionDetected[nInReadQueueAfterShift] <= 0; // no collision
                if ((waitTimeWriteQueue[0] == 0) && (SSID_writeRow == queueWriteRow[0])) begin // if we're going to write a row, and it's the same as the row we're reading (a collision)
                    rowToRead <= SSID_writeRow + 1; // make it a different row
                    collisionDetected[nInReadQueueAfterShift] <= 1;
                end
            end

            else if (readRow == 1'b1) begin // read a whole row
                rowToRead <= rowRead; // request read for this row
                queueReadRow[nInReadQueueAfterShift] <= rowRead; // then place row in queue until read completes
                queueReadWholeRow[nInReadQueueAfterShift] <= 1; // mark as a whole-row read
                waitTimeReadQueue[nInReadQueueAfterShift] <= BRAM_READDELAY; // set the wait time
                nInReadQueue <= nInReadQueueAfterShift + 1; // increase the number of items in queue

                collisionDetected[nInReadQueueAfterShift] <= 0; // no collision
                if ((waitTimeWriteQueue[0] == 0) && (rowRead == queueWriteRow[0])) begin // if we're going to write a row, and it's the same as the row we're reading (a collision)
                    rowToRead <= SSID_writeRow + 1; // make it a different row
                    collisionDetected[nInReadQueueAfterShift] <= 1;
                end
            end

            //-------------------//
            // READ WRITE ENABLE //
            //-------------------//

            readReady <= (nInWriteQueue == 0); // needs better logic here
        end
    end
endmodule
