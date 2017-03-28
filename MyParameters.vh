localparam BRAM_READDELAY = 2;
localparam BRAM_WRITEDELAY = 4;

localparam NROWS_HNM = 128;
localparam NCOLS_HNM = 512;
localparam ROWINDEXBITS_HNM = $clog2(NROWS_HNM);
localparam COLINDEXBITS_HNM = $clog2(NCOLS_HNM);

localparam SSIDBITS = ROWINDEXBITS_HNM + COLINDEXBITS_HNM;

localparam NROWS_HCM = NROWS_HNM * NCOLS_HNM;
localparam ROWINDEXBITS_HCM = $clog2(NROWS_HCM);
