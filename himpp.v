`timescale 1ns / 1ps

module HIMPP(
    input clk,
    input reset,
    input writeRow,
    input [ROWINDEXBITS_HIM-1:0] inputRowToWrite,
    input readRow,
    input [ROWINDEXBITS_HIM-1:0] inputRowToRead,
    input [NCOLS_HIM-1:0] inputHitInfo,
    input [MAXHITNBITS-1:0] nOldHits,
    input [MAXHITNBITS-1:0] nNewHits,
    output reg [NCOLS_HIM-1:0] hitInfo_read,
    output reg readFinished = 0,
    output reg writeReady,
    output reg readReady,
    output reg busy
    );

    `include "MyParameters.vh"

    //-------------//
    // HIM BRAM IP //
    //-------------//

    (*mark_debug="TRUE"*)
    reg writeToBRAM = 0;
    (*mark_debug="TRUE"*)
    reg [ROWINDEXBITS_HIM-1:0] rowToWrite;
    (*mark_debug="TRUE"*)
    reg [NCOLS_HIM-1:0] dataToWrite;
    reg [ROWINDEXBITS_HIM-1:0] rowToRead;
    wire [NCOLS_HIM-1:0] dataRead;

    wire [NCOLS_HIM-1:0] dummyRead;
    reg [NCOLS_HIM-1:0] dummyWrite = 0;

    himpp HIM_BRAM (
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
    // HIM WRITE QUEUE //
    //-----------------//

    reg [ROWINDEXBITS_HIM-1:0] queueWriteRow [QUEUESIZE-1:0];
    reg [QUEUESIZE-1:0] queueNNewHits;
    reg [QUEUESIZE-1:0] queueNOldHits [MAXHITNBITS-1:0];
    reg [NCOLS_HIM-1:0] queueNewHitsInfo [QUEUESIZE-1:0];
    reg [QUEUESIZEBITS-1:0] nInWriteQueue = 0;
    reg [QUEUESIZE-1:0] waitTimeWriteQueue [2:0];

    wire writeQueueShifted;
    wire [QUEUESIZEBITS-1:0] nInWriteQueueAfterShift;
    assign writeQueueShifted = (nInWriteQueue > 0) && (waitTimeWriteQueue[0] == 0);
    assign nInWriteQueueAfterShift = nInWriteQueue - writeQueueShifted;

    //----------------//
    // HIM READ QUEUE //
    //----------------//

    reg [ROWINDEXBITS_HIM-1:0] queueReadRow [QUEUESIZE-1:0];
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
    reg [NCOLS_HIM-1:0] dataPreviouslyWritten [QUEUESIZE-1:0];

    //-----------------//
    // STUPID BULLSHIT //
    //-----------------//

    reg [QUEUESIZEBITS-1:0] queueN = 0; // can't do loop variable declaration

    //---------//
    // TESTING //
    //---------//

    initial begin
        //$monitor ("%g\t%b\t%b\t%b", $time, writeToBRAM, rowToWrite, dataToWrite[6:0]);
        //$monitor ("%b\t%b\t%b\t%b", debugQueueWriteRow[0], debugQueueNewHitsRow[0], debugRowToRead, debugNInReadQueue);
        //$monitor ("HIM\t%b\t%d\t%d\t%d\t%d\t%d", writeToBRAM, rowToWrite, dataToWrite[ROWINDEXBITS_HCM-1:0], dataToWrite[HITINFOBITS+ROWINDEXBITS_HCM-1:HITINFOBITS], dataToWrite[HITINFOBITS*2+ROWINDEXBITS_HCM:HITINFOBITS*2], dataToWrite[HITINFOBITS*3+ROWINDEXBITS_HCM:HITINFOBITS*3]);
    end

    always @(posedge clk) begin

        if (reset) begin
            collisionDetected <= 0;
            nInReadQueue <= 0;
            nInWriteQueue <= 0;
        end

        else begin

            //----------------//
            // READ AND WRITE //
            //----------------//

            writeToBRAM <= 1'b0; // don't write
            readFinished <= 0;

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
                    hitInfo_read <= dataRead;

                    if (collisionDetected[0]) begin
                        hitInfo_read <= dataPreviouslyWritten[0];
                        //$display("Non-collision result for row %d is %b", queueReadRow[0], dataRead);
                        //$display("Data previously written for row %d was %b", queueReadRow[0], dataPreviouslyWritten[0]);
                    end

                    if (queueRequestedRead[0]) readFinished <= 1; // only for requested reads
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

                    if (queueNOldHits[0] == 0) begin // first hit for this SSID
                        dataToWrite <= queueNewHitsInfo[0];
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= queueNewHitsInfo[0];
                    end

                    else begin

                        dataToWrite <= dataRead | (queueNewHitsInfo[0] << queueNOldHits[0]*HITINFOBITS);
                        dataPreviouslyWritten[nInReadQueueAfterShift] <= dataRead | (queueNewHitsInfo[0] << queueNOldHits[0]*HITINFOBITS);

                        if (collisionDetected[0]) begin
                            dataToWrite <= dataPreviouslyWritten[0] | (queueNewHitsInfo[0] << queueNOldHits[0]*HITINFOBITS);
                            dataPreviouslyWritten[nInReadQueueAfterShift] <= dataPreviouslyWritten[0] | (queueNewHitsInfo[0] << queueNOldHits[0]*HITINFOBITS);
                        end
                    end

                    for (queueN = 0; queueN < QUEUESIZE - 1; queueN = queueN + 1) begin
                        waitTimeWriteQueue[queueN] <= waitTimeWriteQueue[queueN+1] - 1; // pop an item
                        queueNewHitsInfo[queueN] <= queueNewHitsInfo[queueN+1]; // pop an item
                        queueNNewHits[queueN] <= queueNNewHits[queueN+1]; // pop an item
                        queueNOldHits[queueN] <= queueNOldHits[queueN+1]; // pop an item
                        queueWriteRow[queueN] <= queueWriteRow[queueN+1]; // pop an item
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
                queueNNewHits[nInWriteQueueAfterShift] <= nNewHits;
                queueNOldHits[nInWriteQueueAfterShift] <= nOldHits;
                queueNewHitsInfo[nInWriteQueueAfterShift] <= inputHitInfo;
                queueWriteRow[nInWriteQueueAfterShift] <= inputRowToWrite; // place in queue until read completes
                waitTimeWriteQueue[nInWriteQueueAfterShift] <= BRAM_READDELAY;
                nInWriteQueue <= nInWriteQueueAfterShift + 1; // increase the number of items in queue
                //$display("Just checking - %b\t%b", queueNewHitsInfo[nInWriteQueueAfterShift], queueNNewHits[nInWriteQueueAfterShift]);

                for (queueN = 0; queueN < nInWriteQueue; queueN = queueN + 1) begin
                    // if the row was already set to write on the clock edge, don't try to add to that row
                    if (queueWriteRow[queueN] == inputRowToWrite && waitTimeWriteQueue[queueN] > 0) begin
                        // undo the new item in queue and add to existing row in queue
                        nInWriteQueue <= 0;
                        queueNNewHits[queueN - writeQueueShifted] <= queueNNewHits[queueN] + nNewHits;
                        queueNOldHits[queueN - writeQueueShifted] <= queueNOldHits[queueN] + nOldHits;
                        queueNewHitsInfo[queueN - writeQueueShifted] <= queueNewHitsInfo[queueN] | (inputHitInfo << queueNNewHits[queueN]*HITINFOBITS);
                        //$display("Just checking - %b\t%b", queueNewHitsInfo[queueN], (inputHitInfo << queueNNewHits[queueN]*HITINFOBITS));
                        queueWriteRow[nInWriteQueueAfterShift] <= queueWriteRow[nInWriteQueueAfterShift];
                        waitTimeWriteQueue[nInWriteQueueAfterShift] <= waitTimeWriteQueue[nInWriteQueueAfterShift];
                        nInWriteQueue <= nInWriteQueueAfterShift;
                    end
                end
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

                if (readRow) queueRequestedRead[nInReadQueueAfterShift] <= 1;
                else queueRequestedRead[nInReadQueueAfterShift] <= 0;
            end

            //-------------------//
            // READ WRITE ENABLE //
            //-------------------//

            readReady <= (nInWriteQueue == 0); // needs better logic here
        end
    end
endmodule
