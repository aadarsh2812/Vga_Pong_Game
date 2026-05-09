// ============================================================
//  Pong — Altera DE2 (Cyclone II EP2C35F672C6N)
//  Resolution : 640 x 480 @ 60 Hz  |  System clk : 50 MHz
//  Controls:
//    KEY[1] = P1 (Left)  Paddle UP
//    KEY[0] = P1 (Left)  Paddle DOWN
//    KEY[3] = P2 (Right) Paddle UP
//    KEY[2] = P2 (Right) Paddle DOWN
//    SW[0]  = Reset Game (toggle ON to reset)
// ============================================================
module vga_pong (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [17:0] SW,
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B
);

// ============================================================
// 1. Pixel Clock 25 MHz
// ============================================================
reg pix_clk_en;
always @(posedge CLOCK_50)
    pix_clk_en <= ~pix_clk_en;

assign VGA_CLK    = ~pix_clk_en;
assign VGA_SYNC_N = 1'b0;

// ============================================================
// 2. VGA Timing 640x480 @ 60Hz
// ============================================================
localparam H_VISIBLE=640, H_FRONT=16, H_SYNC=96, H_BACK=48, H_TOTAL=800;
localparam V_VISIBLE=480, V_FRONT=10, V_SYNC=2,  V_BACK=33, V_TOTAL=525;

reg [9:0] h_cnt, v_cnt;
always @(posedge CLOCK_50) begin
    if (pix_clk_en) begin
        if (h_cnt == H_TOTAL-1) begin
            h_cnt <= 0;
            v_cnt <= (v_cnt == V_TOTAL-1) ? 10'd0 : v_cnt + 10'd1;
        end else begin
            h_cnt <= h_cnt + 10'd1;
        end
    end
end

assign VGA_HS      = ~((h_cnt >= H_VISIBLE + H_FRONT) && (h_cnt < H_VISIBLE + H_FRONT + H_SYNC));
assign VGA_VS      = ~((v_cnt >= V_VISIBLE + V_FRONT) && (v_cnt < V_VISIBLE + V_FRONT + V_SYNC));
wire   visible     =  (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
assign VGA_BLANK_N =   visible;

// ============================================================
// 3. Frame Tick ~60 Hz
// ============================================================
reg [19:0] gcnt;
reg        frame_tick;
always @(posedge CLOCK_50) begin
    if (gcnt == 20'd833_332) begin
        gcnt <= 0;
        frame_tick <= 1;
    end else begin
        gcnt <= gcnt + 20'd1;
        frame_tick <= 0;
    end
end

// ============================================================
// 4. Button + Switch Debounce
// ============================================================
reg [19:0] db_k0, db_k1, db_k2, db_k3, db_sw;
reg        k0s, k1s, k2s, k3s, sw0s;

initial begin
    db_k0 = 0; db_k1 = 0; db_k2 = 0; db_k3 = 0; db_sw = 0;
    k0s = 1; k1s = 1; k2s = 1; k3s = 1; sw0s = 0;
end

always @(posedge CLOCK_50) begin
    // KEY[0] - P1 Down
    if (KEY[0] == k0s) db_k0 <= 0;
    else begin db_k0 <= db_k0 + 1; if (&db_k0) k0s <= KEY[0]; end

    // KEY[1] - P1 Up
    if (KEY[1] == k1s) db_k1 <= 0;
    else begin db_k1 <= db_k1 + 1; if (&db_k1) k1s <= KEY[1]; end

    // KEY[2] - P2 Down
    if (KEY[2] == k2s) db_k2 <= 0;
    else begin db_k2 <= db_k2 + 1; if (&db_k2) k2s <= KEY[2]; end

    // KEY[3] - P2 Up
    if (KEY[3] == k3s) db_k3 <= 0;
    else begin db_k3 <= db_k3 + 1; if (&db_k3) k3s <= KEY[3]; end

    // SW[0] - Reset
    if (SW[0] == sw0s) db_sw <= 0;
    else begin db_sw <= db_sw + 1; if (&db_sw) sw0s <= SW[0]; end
end

// ============================================================
// 5. Game Constants
// ============================================================
localparam [9:0]
    PAD_W    = 10'd12,
    PAD_H    = 10'd72,
    BALL_S   = 10'd10,
    LPAD_X   = 10'd24,
    RPAD_X   = 10'd604,
    PAD_SPD  = 10'd5,
    BSX      = 10'd5,
    BSY      = 10'd4,
    WALL_T   = 10'd8,
    PAD_YMIN = 10'd8,
    PAD_YMAX = 10'd400;

localparam [3:0] WIN_SCORE = 4'd7;

// ============================================================
// 6. Game Registers
// ============================================================
reg [9:0] lpy, rpy;
reg [9:0] bx, by;
reg       bxd, byd;
reg [3:0] lscore, rscore;
reg       gover, lwon;
reg [6:0] serve_cnt;

// ============================================================
// 7. Digit Font 8x7
// ============================================================
function [7:0] dig_row;
    input [3:0] d;
    input [2:0] r;
    begin
        case (d)
          4'd0: case(r) 3'd0:dig_row=8'h3C; 3'd1:dig_row=8'h66; 3'd2:dig_row=8'h6E;
                        3'd3:dig_row=8'h76; 3'd4:dig_row=8'h66; 3'd5:dig_row=8'h66;
                        3'd6:dig_row=8'h3C; default:dig_row=0; endcase
          4'd1: case(r) 3'd0:dig_row=8'h18; 3'd1:dig_row=8'h38; 3'd2:dig_row=8'h18;
                        3'd3:dig_row=8'h18; 3'd4:dig_row=8'h18; 3'd5:dig_row=8'h18;
                        3'd6:dig_row=8'h7E; default:dig_row=0; endcase
          4'd2: case(r) 3'd0:dig_row=8'h3C; 3'd1:dig_row=8'h66; 3'd2:dig_row=8'h06;
                        3'd3:dig_row=8'h1C; 3'd4:dig_row=8'h30; 3'd5:dig_row=8'h60;
                        3'd6:dig_row=8'h7E; default:dig_row=0; endcase
          4'd3: case(r) 3'd0:dig_row=8'h3C; 3'd1:dig_row=8'h66; 3'd2:dig_row=8'h06;
                        3'd3:dig_row=8'h1C; 3'd4:dig_row=8'h06; 3'd5:dig_row=8'h66;
                        3'd6:dig_row=8'h3C; default:dig_row=0; endcase
          4'd4: case(r) 3'd0:dig_row=8'h0C; 3'd1:dig_row=8'h1C; 3'd2:dig_row=8'h3C;
                        3'd3:dig_row=8'h6C; 3'd4:dig_row=8'h7E; 3'd5:dig_row=8'h0C;
                        3'd6:dig_row=8'h0C; default:dig_row=0; endcase
          4'd5: case(r) 3'd0:dig_row=8'h7E; 3'd1:dig_row=8'h60; 3'd2:dig_row=8'h7C;
                        3'd3:dig_row=8'h06; 3'd4:dig_row=8'h06; 3'd5:dig_row=8'h66;
                        3'd6:dig_row=8'h3C; default:dig_row=0; endcase
          4'd6: case(r) 3'd0:dig_row=8'h1C; 3'd1:dig_row=8'h30; 3'd2:dig_row=8'h60;
                        3'd3:dig_row=8'h7C; 3'd4:dig_row=8'h66; 3'd5:dig_row=8'h66;
                        3'd6:dig_row=8'h3C; default:dig_row=0; endcase
          4'd7: case(r) 3'd0:dig_row=8'h7E; 3'd1:dig_row=8'h06; 3'd2:dig_row=8'h0C;
                        3'd3:dig_row=8'h18; 3'd4:dig_row=8'h18; 3'd5:dig_row=8'h18;
                        3'd6:dig_row=8'h18; default:dig_row=0; endcase
          4'd8: case(r) 3'd0:dig_row=8'h3C; 3'd1:dig_row=8'h66; 3'd2:dig_row=8'h66;
                        3'd3:dig_row=8'h3C; 3'd4:dig_row=8'h66; 3'd5:dig_row=8'h66;
                        3'd6:dig_row=8'h3C; default:dig_row=0; endcase
          4'd9: case(r) 3'd0:dig_row=8'h3C; 3'd1:dig_row=8'h66; 3'd2:dig_row=8'h66;
                        3'd3:dig_row=8'h3E; 3'd4:dig_row=8'h06; 3'd5:dig_row=8'h0C;
                        3'd6:dig_row=8'h38; default:dig_row=0; endcase
          default: dig_row = 8'h00;
        endcase
    end
endfunction

// ============================================================
// 8. Banner Font (P=10, W=11, I=12, N=13, S=14, space=15)
// ============================================================
function [7:0] chr_row;
    input [3:0] c;
    input [2:0] r;
    begin
        case (c)
          4'd10: case(r) 3'd0:chr_row=8'hFC; 3'd1:chr_row=8'h66; 3'd2:chr_row=8'h66;
                         3'd3:chr_row=8'hFC; 3'd4:chr_row=8'h60; 3'd5:chr_row=8'h60;
                         3'd6:chr_row=8'h60; default:chr_row=0; endcase // P
          4'd11: case(r) 3'd0:chr_row=8'hC6; 3'd1:chr_row=8'hC6; 3'd2:chr_row=8'hC6;
                         3'd3:chr_row=8'hD6; 3'd4:chr_row=8'hFE; 3'd5:chr_row=8'h6C;
                         3'd6:chr_row=8'h28; default:chr_row=0; endcase // W
          4'd12: case(r) 3'd0:chr_row=8'h7E; 3'd1:chr_row=8'h18; 3'd2:chr_row=8'h18;
                         3'd3:chr_row=8'h18; 3'd4:chr_row=8'h18; 3'd5:chr_row=8'h18;
                         3'd6:chr_row=8'h7E; default:chr_row=0; endcase // I
          4'd13: case(r) 3'd0:chr_row=8'hC6; 3'd1:chr_row=8'hE6; 3'd2:chr_row=8'hF6;
                         3'd3:chr_row=8'hDE; 3'd4:chr_row=8'hCE; 3'd5:chr_row=8'hC6;
                         3'd6:chr_row=8'hC6; default:chr_row=0; endcase // N
          4'd14: case(r) 3'd0:chr_row=8'h3C; 3'd1:chr_row=8'h66; 3'd2:chr_row=8'h60;
                         3'd3:chr_row=8'h3C; 3'd4:chr_row=8'h06; 3'd5:chr_row=8'h66;
                         3'd6:chr_row=8'h3C; default:chr_row=0; endcase // S
          default: chr_row = dig_row(c, r);
        endcase
    end
endfunction

// ============================================================
// 9. Game Logic
// ============================================================
always @(posedge CLOCK_50) begin
    if (sw0s) begin
        lpy       <= 10'd204;
        rpy       <= 10'd204;
        bx        <= 10'd315;
        by        <= 10'd235;
        bxd       <= 1'b0;
        byd       <= 1'b0;
        lscore    <= 4'd0;
        rscore    <= 4'd0;
        gover     <= 1'b0;
        lwon      <= 1'b0;
        serve_cnt <= 7'd0;
    end
    else if (frame_tick && !gover) begin

        // P1 (Left) Paddle
        if (!k1s && lpy > PAD_YMIN) lpy <= lpy - PAD_SPD;
        if (!k0s && lpy < PAD_YMAX) lpy <= lpy + PAD_SPD;

        // P2 (Right) Paddle
        if (!k3s && rpy > PAD_YMIN) rpy <= rpy - PAD_SPD;
        if (!k2s && rpy < PAD_YMAX) rpy <= rpy + PAD_SPD;

        // Ball
        if (serve_cnt > 7'd0) begin
            serve_cnt <= serve_cnt - 7'd1;
        end else begin
            if (!bxd) bx <= bx + BSX; else bx <= bx - BSX;
            if (!byd) by <= by + BSY; else by <= by - BSY;

            // Top wall
            if (byd && by < WALL_T + BSY) begin
                byd <= 1'b0; by <= WALL_T;
            end
            // Bottom wall
            if (!byd && by + BALL_S + BSY >= 10'd472) begin
                byd <= 1'b1; by <= 10'd472 - BALL_S;
            end
            // Left paddle bounce
            if (bxd &&
                bx + BALL_S > LPAD_X && bx < LPAD_X + PAD_W &&
                by + BALL_S > lpy    && by < lpy + PAD_H) begin
                bxd <= 1'b0; bx <= LPAD_X + PAD_W;
            end
            // Right paddle bounce
            if (!bxd &&
                bx + BALL_S > RPAD_X && bx < RPAD_X + PAD_W &&
                by + BALL_S > rpy    && by < rpy + PAD_H) begin
                bxd <= 1'b1; bx <= RPAD_X - BALL_S;
            end
            // Left player scores
            if (!bxd && bx + BALL_S + BSX >= 10'd640) begin
                lscore <= lscore + 4'd1;
                bx <= 10'd315; by <= 10'd235;
                bxd <= 1'b0; byd <= 1'b0;
                serve_cnt <= 7'd90;
                if (lscore == WIN_SCORE - 4'd1) begin gover <= 1'b1; lwon <= 1'b1; end
            end
            // Right player scores
            if (bxd && bx < BSX) begin
                rscore <= rscore + 4'd1;
                bx <= 10'd315; by <= 10'd235;
                bxd <= 1'b1; byd <= 1'b1;
                serve_cnt <= 7'd90;
                if (rscore == WIN_SCORE - 4'd1) begin gover <= 1'b1; lwon <= 1'b0; end
            end
        end
    end
end

// ============================================================
// 10. Pixel Rendering
// ============================================================

// Walls
wire wall_on = (v_cnt < WALL_T) || (v_cnt >= 10'd472);

// Centre dashed line
wire cline_on = ((h_cnt == 10'd319) || (h_cnt == 10'd320)) && v_cnt[3];

// Paddles
wire lpad_on = (h_cnt >= LPAD_X) && (h_cnt < LPAD_X + PAD_W) &&
               (v_cnt >= lpy)    && (v_cnt < lpy + PAD_H);
wire rpad_on = (h_cnt >= RPAD_X) && (h_cnt < RPAD_X + PAD_W) &&
               (v_cnt >= rpy)    && (v_cnt < rpy + PAD_H);

// Ball
wire ball_on = (h_cnt >= bx) && (h_cnt < bx + BALL_S) &&
               (v_cnt >= by) && (v_cnt < by + BALL_S);

// --------------------------------------------------------
// Left score digit (2x scaled, 16x14 px at h=264, v=20)
// --------------------------------------------------------
wire in_ldig = (h_cnt >= 10'd264) && (h_cnt < 10'd280) &&
               (v_cnt >= 10'd20)  && (v_cnt < 10'd34);
wire [2:0] ldig_fc = h_cnt[3:1] - 3'd4;
wire [2:0] ldig_fr = v_cnt[3:1] - 3'd2;
reg  [7:0] ldig_bits;
reg        ldig_px;
always @(*) begin
    ldig_bits = dig_row(lscore, ldig_fr);
    ldig_px   = in_ldig && ldig_bits[3'd7 - ldig_fc];
end

// --------------------------------------------------------
// Right score digit (2x scaled, 16x14 px at h=356, v=20)
// --------------------------------------------------------
wire in_rdig = (h_cnt >= 10'd356) && (h_cnt < 10'd372) &&
               (v_cnt >= 10'd20)  && (v_cnt < 10'd34);
wire [2:0] rdig_fc = h_cnt[3:1] - 3'd2;
wire [2:0] rdig_fr = v_cnt[3:1] - 3'd2;
reg  [7:0] rdig_bits;
reg        rdig_px;
always @(*) begin
    rdig_bits = dig_row(rscore, rdig_fr);
    rdig_px   = in_rdig && rdig_bits[3'd7 - rdig_fc];
end

// --------------------------------------------------------
// P1 label below left score (1x scale, 8x7 at h=264, v=38)
// --------------------------------------------------------
wire in_p1l = (h_cnt >= 10'd264) && (h_cnt < 10'd272) &&
              (v_cnt >= 10'd38)  && (v_cnt < 10'd45);
wire [2:0] p1l_fc = h_cnt[2:0];
wire [2:0] p1l_fr = v_cnt[2:0] - 3'd3;
reg  [7:0] p1l_bits;
reg        p1l_px;
always @(*) begin
    p1l_bits = chr_row(4'd10, p1l_fr); // P
    p1l_px   = in_p1l && p1l_bits[3'd7 - p1l_fc];
end

wire in_p1n = (h_cnt >= 10'd272) && (h_cnt < 10'd280) &&
              (v_cnt >= 10'd38)  && (v_cnt < 10'd45);
wire [2:0] p1n_fc = h_cnt[2:0];
wire [2:0] p1n_fr = v_cnt[2:0] - 3'd3;
reg  [7:0] p1n_bits;
reg        p1n_px;
always @(*) begin
    p1n_bits = dig_row(4'd1, p1n_fr); // 1
    p1n_px   = in_p1n && p1n_bits[3'd7 - p1n_fc];
end

// --------------------------------------------------------
// P2 label below right score (1x scale, 8x7 at h=356, v=38)
// --------------------------------------------------------
wire in_p2l = (h_cnt >= 10'd356) && (h_cnt < 10'd364) &&
              (v_cnt >= 10'd38)  && (v_cnt < 10'd45);
wire [2:0] p2l_fc = h_cnt[2:0];
wire [2:0] p2l_fr = v_cnt[2:0] - 3'd3;
reg  [7:0] p2l_bits;
reg        p2l_px;
always @(*) begin
    p2l_bits = chr_row(4'd10, p2l_fr); // P
    p2l_px   = in_p2l && p2l_bits[3'd7 - p2l_fc];
end

wire in_p2n = (h_cnt >= 10'd364) && (h_cnt < 10'd372) &&
              (v_cnt >= 10'd38)  && (v_cnt < 10'd45);
wire [2:0] p2n_fc = h_cnt[2:0];
wire [2:0] p2n_fr = v_cnt[2:0] - 3'd3;
reg  [7:0] p2n_bits;
reg        p2n_px;
always @(*) begin
    p2n_bits = dig_row(4'd2, p2n_fr); // 2
    p2n_px   = in_p2n && p2n_bits[3'd7 - p2n_fc];
end

// --------------------------------------------------------
// Banner background
// --------------------------------------------------------
wire ban_bg = gover &&
              (h_cnt >= 10'd236) && (h_cnt < 10'd404) &&
              (v_cnt >= 10'd218) && (v_cnt < 10'd252);

// Banner text "P1 WINS" or "P2 WINS"
wire in_ban = gover &&
              (h_cnt >= 10'd264) && (h_cnt < 10'd376) &&
              (v_cnt >= 10'd226) && (v_cnt < 10'd240);

wire [2:0] ban_cpos = (h_cnt - 10'd264) >> 4;
wire [2:0] ban_fc   = h_cnt[3:1];
wire [2:0] ban_fr   = v_cnt[3:1] - 3'd4;

reg [3:0] ban_ccode;
always @(*) begin
    case (ban_cpos)
        3'd0: ban_ccode = 4'd10;              // P
        3'd1: ban_ccode = lwon ? 4'd1 : 4'd2; // 1 or 2
        3'd2: ban_ccode = 4'd15;              // space
        3'd3: ban_ccode = 4'd11;              // W
        3'd4: ban_ccode = 4'd12;              // I
        3'd5: ban_ccode = 4'd13;              // N
        3'd6: ban_ccode = 4'd14;              // S
        default: ban_ccode = 4'd15;
    endcase
end

reg [7:0] ban_bits;
reg       ban_px;
always @(*) begin
    ban_bits = chr_row(ban_ccode, ban_fr);
    ban_px   = in_ban && ban_bits[3'd7 - ban_fc];
end

// ============================================================
// 11. Colour Mixer
// ============================================================
reg [7:0] ro, go_out, bo;
always @(*) begin
    if      (!visible)       {ro, go_out, bo} = 24'h000000;
    else if (ban_px)         {ro, go_out, bo} = 24'hFFFFFF;
    else if (ban_bg)         {ro, go_out, bo} = lwon ? 24'h004455 : 24'h552200;
    else if (wall_on)        {ro, go_out, bo} = 24'h38BDF8;
    else if (ball_on)        {ro, go_out, bo} = 24'hFFFFFF;
    else if (lpad_on)        {ro, go_out, bo} = 24'h00E5FF;
    else if (rpad_on)        {ro, go_out, bo} = 24'hFF6B00;
    else if (ldig_px)        {ro, go_out, bo} = 24'h00E5FF;
    else if (rdig_px)        {ro, go_out, bo} = 24'hFF6B00;
    else if (p1l_px|p1n_px)  {ro, go_out, bo} = 24'h00E5FF;
    else if (p2l_px|p2n_px)  {ro, go_out, bo} = 24'hFF6B00;
    else if (cline_on)       {ro, go_out, bo} = 24'h1E293B;
    else                     {ro, go_out, bo} = 24'h0B1120;
end

assign VGA_R = ro;
assign VGA_G = go_out;
assign VGA_B = bo;

endmodule