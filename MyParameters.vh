localparam BRAM_READDELAY = 2;
localparam BRAM_WRITEDELAY = 1;

localparam NROWS_HNM = 128;
localparam NCOLS_HNM = 512;
localparam ROWINDEXBITS_HNM = 7; //$clog2(NROWS_HNM);
localparam COLINDEXBITS_HNM = 9; //$clog2(NCOLS_HNM);

localparam SSIDBITS = ROWINDEXBITS_HNM + COLINDEXBITS_HNM;

localparam NROWS_HCM = NROWS_HNM * NCOLS_HNM;
localparam ROWINDEXBITS_HCM = 16; //$clog2(NROWS_HCM);

localparam QUEUESIZE = BRAM_READDELAY + 2;
localparam QUEUESIZEBITS = 3;
