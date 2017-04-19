`timescale 1ns / 1ps

module HCMPP(
    input clk,
    input [ROWINDEXBITS_HCM-1:0] inputRowToWrite,
    input writeRow,
    input SSIDIsNew,
    input [ROWINDEXBITS_HCM-1:0] inputRowToRead,
    input readRow,
    input [HITINFOBITS-1:0] inputHitInfo,
    input reset,
    output reg writeReady,
    output reg readReady,
    output reg [ROWINDEXBITS_HCM-1:0] rowPassed,
    output reg [MAXHITNBITS-1:0] nOldHits,
    output reg [MAXHITNBITS-1:0] nNewHits,
    output reg [MAXHITNBITS-1:0] readNHits,
    output reg [ROWINDEXBITS_HIM-1:0] readHIM_address,
    output reg [ROWINDEXBITS_HIM-1:0] HIM_address,
    output reg [NCOLS_HIM-1:0] outputNewHitInfo,
    output reg newOutput,
    output reg readFinished = 0,
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
    reg [NCOLS_HIM-1:0] queueNewHitInfo [QUEUESIZE-1:0];
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
    reg [QUEUESIZE-1:0] queueRequestedRead = 0;

    wire readQueueShifted;
    wire [QUEUESIZEBITS-1:0] nInReadQueueAfterShift;
    assign readQueueShifted = (nInReadQueue > 0) && (waitTimeReadQueue[0] == 0);
    assign nInReadQueueAfterShift = nInReadQueue - readQueueShifted;

    //---------------------//
    // COLLISION AVOIDANCE //
    //---------------------//

    reg [QUEUESIZE-1:0] collisionDetected = 0;
    reg [NCOLS_HCM-1:0] dataPreviouslyWritten [QUEUESIZE-1:0];

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
        //$monitor ("%b\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d", writeToBRAM, rowToWrite, rowToWrite[SSIDBITS-1:COLINDEXBITS_HNM], rowToWrite[COLINDEXBITS_HNM-1:0], dataToWrite[MAXHITNBITS-1:0], outputNewHitInfo[ROWINDEXBITS_HCM-1:0], outputNewHitInfo[HITINFOBITS+ROWINDEXBITS_HCM-1:HITINFOBITS], outputNewHitInfo[HITINFOBITS*2+ROWINDEXBITS_HCM:HITINFOBITS*2], outputNewHitInfo[HITINFOBITS*3+ROWINDEXBITS_HCM:HITINFOBITS*3]);
    end

    always @(posedge clk) begin

        if (reset) begin
            nextHIMAddress <= 0;
            collisionDetected <= 0;
            nInReadQueue <= 0;
            nInWriteQueue <= 0;
            readFinished <= 0;
        end

        else begin

            //----------------//
            // READ AND WRITE //
            //----------------//

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
                        collisionDetected[queueN] <= collisionDetected[queueN+1];
                        dataPreviouslyWritten[queueN] <= dataPreviouslyWritten[queueN+1];
                        queueRequestedRead[queueN] <= queueRequestedRead[queueN+1]; // pop an item
                    end
                    nInReadQueue <= nInReadQueue - 1; // reduce number of items in queue

                    readFinished <= 1'b0;
                    if (queueRequestedRead[0]) readFinished <= 1; // only for requested reads
                    readNHits <= dataRead[MAXHITNBITS-1:0];
                    readHIM_address <= dataRead[NCOLS_HCM-1:MAXHITNBITS];

                    if (collisionDetected[0]) begin
                        //$display("Non-collision result for row %d is %b", queueReadRow[0], dataRead);
                        //$display("Data previously written for row %d was %b", queueReadRow[0], dataPreviouslyWritten[0]);
                        readNHits <= dataPreviouslyWritten[0][MAXHITNBITS-1:0];
                        readHIM_address <= dataPreviouslyWritten[0][NCOLS_HCM-1:MAXHITNBITS];
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
                        HIM_address <= nextHIMAddress; // return HIM address
                        nextHIMAddress <= nextHIMAddress + 1;
                        //$display("New row %d, address %d, hitN %d", queueWriteRow[0], nextHIMAddress, queueNewNHits[0]);
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= queueNewNHits[0] | (nextHIMAddress << MAXHITNBITS); // in case of collision
                        //$display("Setting collision readout data to %b", queueWriteRow[0]);
                        nOldHits <= 0;
                        nNewHits <= queueNewNHits[0];
                    end

                    else begin

                        dataToWrite <= dataRead + queueNewNHits[0];
                        HIM_address <= dataRead[NCOLS_HCM-1:MAXHITNBITS]; // return HIM address
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= dataRead + queueNewNHits[0]; // in case of collision
                        nOldHits <= dataRead[MAXHITNBITS-1:0];

                        if (collisionDetected[0]) begin
                            dataToWrite <= dataPreviouslyWritten[0] + queueNewNHits[0];
                            dataPreviouslyWritten[nInReadQueueAfterShift] <= dataPreviouslyWritten[0] + queueNewNHits[0]; // in case of collision
                            nOldHits <= dataPreviouslyWritten[0][MAXHITNBITS-1:0];
                        end

                        //$display("Setting collision readout data to %b", queueWriteRow[0]);
                        //$display("Existing row %d, address %d, hitN %d", queueWriteRow[0], dataRead[10:3], dataRead[2:0] + queueNewNHits[0]);
                        nNewHits <= queueNewNHits[0];
                    end

                    for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                        waitTimeWriteQueue[queueN] <= waitTimeWriteQueue[queueN+1] - 1; // pop an item
                        queueWriteRow[queueN] <= queueWriteRow[queueN+1]; // pop an item
                        queueNewNHits[queueN] <= queueNewNHits[queueN+1]; // pop an item
                        queueSSIDIsNew[queueN] <= queueSSIDIsNew[queueN+1]; // pop an item
                        queueNewHitInfo[queueN] <= queueNewHitInfo[queueN+1]; // pop an item
                    end

                    outputNewHitInfo <= queueNewHitInfo[0]; // return the new hit info
                    nInWriteQueue <= nInWriteQueue - 1; // reduce number of items in queue
                    writeToBRAM <= 1'b1;
                    rowToWrite <= queueWriteRow[0];
                    rowPassed <= queueWriteRow[0];
                    newOutput <= 1'b1;
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
                queueNewHitInfo[nInWriteQueueAfterShift] <= inputHitInfo;

                for (queueN = 0; queueN < nInWriteQueue; queueN = queueN + 1) begin
                    // if the row was already set to write on the clock edge, don't try to add to that row
                    if (queueWriteRow[queueN] == inputRowToWrite && waitTimeWriteQueue[queueN] > 0) begin
                        // undo the new item in queue and add to existing row in queue
                        queueNewNHits[nInWriteQueueAfterShift] <= 0;
                        queueNewNHits[queueN - writeQueueShifted] <= queueNewNHits[queueN] + 1;
                        queueWriteRow[nInWriteQueueAfterShift] <= queueWriteRow[nInWriteQueueAfterShift];
                        waitTimeWriteQueue[nInWriteQueueAfterShift] <= waitTimeWriteQueue[nInWriteQueueAfterShift];
                        nInWriteQueue <= nInWriteQueueAfterShift;
                        queueNewHitInfo[queueN - writeQueueShifted] <= queueNewHitInfo[queueN] | (inputHitInfo << HITINFOBITS*queueNewNHits[queueN]);
                        queueNewHitInfo[nInWriteQueueAfterShift] <= 0;
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

                if (readRow) queueRequestedRead[nInReadQueueAfterShift] <= 1; // mark as a silent read
                else queueRequestedRead[nInReadQueueAfterShift] <= 0; // regular read (pass along results)
            end

            //-------------------//
            // READ WRITE ENABLE //
            //-------------------//

            readReady <= (nInWriteQueue == 0); // needs better logic here
        end
    end
endmodule
