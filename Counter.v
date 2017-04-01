`timescale 1ns / 1ps

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

//---------//
// Counter //
//---------//

module Counter(
    input clk,
    input reset,
    input enable,
    output reg [7:0] count
    );

    initial begin
        count = 0;
    end

    always @(posedge clk) begin
        if (reset == 1'b1) begin
            count = 7'b0;
        end
        else if (enable == 1'b1) begin
            count = count+1;
        end
    end

endmodule

/*module Counter
(
input clk,
output reg [15:0] SSID = -1,
);

reg [3:0] xPos[45:0] = {0, 3, 7, 8, 8, 8, 5, 11, 11, 7, 1, 7, 5, 15, 8, 12, 4, 4, 7, 2, 1, 13, 6, 0, 3, 7, 8, 8, 8, 5, 11, 11, 7, 1, 7, 5, 15, 8, 12, 4, 4, 7, 2, 1, 13, 6};
reg [3:0] yPos[45:0] = {8, 8, 8, 8, 8, 8, 8, 8, 4, 4, 4, 12, 3, 3, 1, 4, 4, 4, 4, 4, 4, 4, 4, 8, 8, 8, 8, 8, 8, 8, 8, 4, 4, 4, 12, 3, 3, 1, 4, 4, 4, 4, 4, 4, 4, 4};
integer count = -1;
integer readCount = 0;

always @(posedge clock) begin
    count = count+1;
    SSID = {xPos[count], yPos[count]};
    $display (count);
end

endmodule*/
