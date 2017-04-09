localparam BRAM_READDELAY = 2;
localparam BRAM_WRITEDELAY = 1;

localparam NROWS_HNM = 128;
localparam NCOLS_HNM = 512;
localparam ROWINDEXBITS_HNM = 7; //$clog2(NROWS_HNM);
localparam COLINDEXBITS_HNM = 9; //$clog2(NCOLS_HNM);

localparam MAXHITN = 5; // at most 5 hits
localparam MAXHITNBITS = 2;

localparam NROWS_HIM = 2048; // can store this many hits per event
localparam HITINFOBITS = 32; // 32 bits of info about each hit
localparam NCOLS_HIM = HITINFOBITS * MAXHITN;
localparam ROWINDEXBITS_HIM = 11; //$clog2(NROWS_HIM);

localparam NROWS_HCM = NROWS_HNM * NCOLS_HNM;
localparam ROWINDEXBITS_HCM = ROWINDEXBITS_HNM + COLINDEXBITS_HNM;
localparam NCOLS_HCM = ROWINDEXBITS_HIM + MAXHITNBITS;

localparam SSIDBITS = ROWINDEXBITS_HNM + COLINDEXBITS_HNM;

localparam QUEUESIZE = BRAM_READDELAY + 2;
localparam QUEUESIZEBITS = 3;
