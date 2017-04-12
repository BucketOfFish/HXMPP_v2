`timescale 1ns / 1ps

module HCMPP(
    input clk,
    input [ROWINDEXBITS_HCM-1:0] inputRowToWrite,
    input writeRow,
    input SSIDIsNew,
    input [ROWINDEXBITS_HCM-1:0] inputRowToRead,
    input readRow,
    input reset,
    output reg writeReady,
    output reg readReady,
    output reg [ROWINDEXBITS_HCM-1:0] rowPassed,
    output reg [NCOLS_HCM-1:0] rowReadOutput,
    output reg busy
    );

    `include "MyParameters.vh"

    //-------------//
    // HCM BRAM IP //
    //-------------//

    reg writeToBRAM = 0;
    reg [ROWINDEXBITS_HCM-1:0] rowToWrite;
    reg [NCOLS_HCM-1:0] dataToWrite;
    reg [ROWINDEXBITS_HCM-1:0] rowToRead;
    wire [NCOLS_HCM-1:0] dataRead;

    wire [NCOLS_HCM-1:0] dummyRead;
    reg [NCOLS_HCM-1:0] dummyWrite = 0;

    hcmpp HCM_BRAM (
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
    // HCM WRITE QUEUE //
    //-----------------//

    reg [ROWINDEXBITS_HCM-1:0] queueWriteRow [QUEUESIZE-1:0];
    reg [MAXHITNBITS-1:0] queueNewNHits [QUEUESIZE-1:0];
    reg [QUEUESIZE-1:0] queueSSIDIsNew;
    reg [QUEUESIZEBITS-1:0] nInWriteQueue = 0;
    reg [QUEUESIZE-1:0] waitTimeWriteQueue [2:0];

    wire writeQueueShifted;
    wire [QUEUESIZEBITS-1:0] nInWriteQueueAfterShift;
    assign writeQueueShifted = (nInWriteQueue > 0) && (waitTimeWriteQueue[0] == 0);
    assign nInWriteQueueAfterShift = nInWriteQueue - writeQueueShifted;

    reg [ROWINDEXBITS_HIM-1:0] nextHIMAddress = 0; // next available address

    //----------------//
    // HCM READ QUEUE //
    //----------------//

    reg [ROWINDEXBITS_HCM-1:0] queueReadRow [QUEUESIZE-1:0];
    reg [QUEUESIZEBITS-1:0] nInReadQueue = 0;
    reg [QUEUESIZE-1:0] waitTimeReadQueue [2:0];

    wire readQueueShifted;
    wire [QUEUESIZEBITS-1:0] nInReadQueueAfterShift;
    assign readQueueShifted = (nInReadQueue > 0) && (waitTimeReadQueue[0] == 0);
    assign nInReadQueueAfterShift = nInReadQueue - readQueueShifted;

    //-----------//
    // COLLISION //
    //-----------//

    reg [QUEUESIZE-1:0] collisionDetected = 0;
    reg [NCOLS_HCM-1:0] dataPreviouslyWritten [QUEUESIZE-1:0];
    reg [NCOLS_HCM-1:0] dataSetToWrite;

    //-----------------//
    // FILL SEQUENTIAL //
    //-----------------//

    reg [1:0] fillStatus = 2'b00; // 00 = idle; 01 = filling; 10 = fill finished; 11 = ready to go
    reg [ROWINDEXBITS_HCM-1:0] fillRow = 0;
    reg [3:0] fillDelay = 0; // wait a safe amount of time after testing before resuming read and write

    //-----------------//
    // STUPID BULLSHIT //
    //-----------------//

    reg [QUEUESIZEBITS-1:0] queueN = 0; // can't do loop variable declaration

    //---------//
    // TESTING //
    //---------//

    (*mark_debug="TRUE"*)
    reg [ROWINDEXBITS_HCM-1:0] debugQueueWriteRow [QUEUESIZE-1:0];
    (*mark_debug="TRUE"*)
    reg [MAXHITNBITS-1:0] debugQueueNewNHits [QUEUESIZE-1:0];
    (*mark_debug="TRUE"*)
    reg [ROWINDEXBITS_HCM-1:0] debugRowToRead;
    (*mark_debug="TRUE"*)
    reg [QUEUESIZEBITS-1:0] debugNInReadQueue = 0;

    genvar i;
    generate
        for (i = 0; i < QUEUESIZE; i = i + 1) begin
            always @(posedge clk) begin
                debugQueueWriteRow[i] <= queueWriteRow[i];
                debugQueueNewNHits[i] <= queueNewNHits[i];
                debugRowToRead <= rowToRead;
                debugNInReadQueue <= nInReadQueue;
            end
        end
    endgenerate

    initial begin
        //$monitor ("%g\t%b\t%b\t%b", $time, writeToBRAM, rowToWrite, dataToWrite[6:0]);
        //$monitor ("%b\t%b\t%b\t%b", debugQueueWriteRow[0], debugQueueNewHitsRow[0], debugRowToRead, debugNInReadQueue);
    end

    always @(posedge clk) begin

        if (reset) begin
            nextHIMAddress <= 0;
            collisionDetected <= 0;
        end

        else begin

            //----------------//
            // READ AND WRITE //
            //----------------//

            writeToBRAM <= 1'b0; // don't write

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
                        collisionDetected[queueN] <= collisionDetected[queueN+1];
                        dataPreviouslyWritten[queueN] <= dataPreviouslyWritten[queueN+1];
                    end
                    nInReadQueue <= nInReadQueue - 1; // reduce number of items in queue
                    rowPassed <= queueReadRow[0];
                    rowReadOutput <= dataRead;

                    if (collisionDetected[0]) begin
                        rowReadOutput <= dataPreviouslyWritten[0];
                        //$display("Non-collision result for row %d is %b", queueReadRow[0], dataRead);
                        //$display("Data previously written for row %d was %b", queueReadRow[0], dataPreviouslyWritten[0]);
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

                    if (queueSSIDIsNew[0]) begin
                        dataToWrite <= queueNewNHits[0] | (nextHIMAddress << MAXHITNBITS);
                        nextHIMAddress <= nextHIMAddress + 1;
                        //$display("New row %d, address %d, hitN %d", queueWriteRow[0], nextHIMAddress, queueNewNHits[0]);
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= queueNewNHits[0] | (nextHIMAddress << MAXHITNBITS); // in case of collision
                        //$display("Setting collision readout data to %b", queueWriteRow[0]);
                    end

                    else begin

                        dataToWrite <= dataRead + queueNewNHits[0];
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= dataRead + queueNewNHits[0]; // in case of collision

                        if (collisionDetected[0]) begin
                            dataToWrite <= dataPreviouslyWritten[0] + queueNewNHits[0];
                            dataPreviouslyWritten[nInReadQueueAfterShift] <= dataPreviouslyWritten[0] + queueNewNHits[0]; // in case of collision
                        end

                        //$display("Setting collision readout data to %b", queueWriteRow[0]);
                        //$display("Existing row %d, address %d, hitN %d", queueWriteRow[0], dataRead[10:3], dataRead[2:0] + queueNewNHits[0]);
                    end

                    for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                        waitTimeWriteQueue[queueN] <= waitTimeWriteQueue[queueN+1] - 1; // pop an item
                        queueWriteRow[queueN] <= queueWriteRow[queueN+1]; // pop an item
                        queueNewNHits[queueN] <= queueNewNHits[queueN+1]; // pop an item
                        queueSSIDIsNew[queueN] <= queueSSIDIsNew[queueN+1]; // pop an item
                    end

                    nInWriteQueue <= nInWriteQueue - 1; // reduce number of items in queue
                    writeToBRAM <= 1'b1;
                    rowToWrite <= queueWriteRow[0];
                end
            end

            //--------------------//
            // ADD TO WRITE QUEUE //
            //--------------------//

            if (writeRow == 1'b1) begin // writing requires a row read request first - see below


                // add to queue if not already there
                queueSSIDIsNew[nInWriteQueueAfterShift] <= SSIDIsNew;
                queueNewNHits[nInWriteQueueAfterShift] <= 1;
                queueWriteRow[nInWriteQueueAfterShift] <= inputRowToWrite; // place in queue until read completes
                waitTimeWriteQueue[nInWriteQueueAfterShift] <= BRAM_READDELAY;
                nInWriteQueue <= nInWriteQueueAfterShift + 1; // increase the number of items in queue

                for (queueN = 0; queueN < nInWriteQueue; queueN = queueN + 1) begin
                    // if the row was already set to write on the clock edge, don't try to add to that row
                    if (queueWriteRow[queueN] == inputRowToWrite && waitTimeWriteQueue[queueN] > 0) begin
                        // undo the new item in queue and add to existing row in queue
                        queueNewNHits[nInWriteQueueAfterShift] <= 0;
                        queueNewNHits[queueN - writeQueueShifted] <= queueNewNHits[queueN] + 1;
                        queueWriteRow[nInWriteQueueAfterShift] <= queueWriteRow[nInWriteQueueAfterShift];
                        waitTimeWriteQueue[nInWriteQueueAfterShift] <= waitTimeWriteQueue[nInWriteQueueAfterShift];
                        nInWriteQueue <= nInWriteQueueAfterShift;
                    end
                end
                //$display("%d - %d:%d, %d:%d, %d:%d, %d:%d", nInWriteQueue, queueWriteRow[0], queueNewNHits[0], queueWriteRow[1], queueNewNHits[1], queueWriteRow[2], queueNewNHits[2], queueWriteRow[3], queueNewNHits[3]);
            end

            //-----------------------//
            // ADD TO ROW READ QUEUE //
            //-----------------------//

            if (writeRow == 1'b1 || readRow == 1'b1) begin // read a whole row

                rowToRead <= writeRow ? inputRowToWrite : inputRowToRead; // request read for this row
                collisionDetected[nInReadQueueAfterShift] <= 0; // no collision

                if ((waitTimeWriteQueue[0] == 0) && ((writeRow && (inputRowToWrite == queueWriteRow[0])) || (!writeRow && (inputRowToRead == queueWriteRow[0])))) begin // if we're going to write a row, and it's the same as the row we're reading (a collision)
                    rowToRead <= (writeRow ? inputRowToWrite : inputRowToRead) + 1; // make it a different row
                    collisionDetected[nInReadQueueAfterShift] <= 1;
                end

                queueReadRow[nInReadQueueAfterShift] <= writeRow ? inputRowToWrite : inputRowToRead; // place row in queue until read completes
                waitTimeReadQueue[nInReadQueueAfterShift] <= BRAM_READDELAY; // set the wait time
                nInReadQueue <= nInReadQueueAfterShift + 1; // increase the number of items in queue
            end

            //-------------------//
            // READ WRITE ENABLE //
            //-------------------//

            readReady <= (nInWriteQueue == 0); // needs better logic here
        end
    end
endmodule
