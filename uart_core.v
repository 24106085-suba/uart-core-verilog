// ============================================================
// COMPLETE UART CORE
// Modules: baud_gen, uart_tx, uart_rx, uart_config, fifo
// Final integrated testbench
// ============================================================

// ------------------------------------------------------------
// 1. BAUD RATE GENERATOR
// ------------------------------------------------------------
module baud_gen #(
    parameter CLKS_PER_BIT = 10
)(
    input  wire clk,
    input  wire reset,
    output reg  baud_tick
);
    reg [12:0] counter;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            counter   <= 0;
            baud_tick <= 0;
        end else if(counter == CLKS_PER_BIT-1) begin
            counter   <= 0;
            baud_tick <= 1;
        end else begin
            counter   <= counter + 1;
            baud_tick <= 0;
        end
    end
endmodule

// ------------------------------------------------------------
// 2. UART TRANSMITTER
// ------------------------------------------------------------
module uart_tx #(
    parameter CLKS_PER_BIT = 10
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       send,
    input  wire [7:0] tx_byte,
    output reg        tx,
    output reg        busy
);
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0] state;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;
    wire      baud_tick;

    baud_gen #(.CLKS_PER_BIT(CLKS_PER_BIT)) bg(
        .clk(clk),.reset(reset),.baud_tick(baud_tick)
    );

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE; tx<=1; busy<=0;
            bit_idx<=0; shift_reg<=0;
        end else begin
            case(state)
                IDLE: begin
                    tx<=1; busy<=0;
                    if(send) begin
                        shift_reg<=tx_byte;
                        state<=START; busy<=1;
                    end
                end
                START: begin
                    tx<=0;
                    if(baud_tick) begin
                        bit_idx<=0; state<=DATA;
                    end
                end
                DATA: begin
                    tx<=shift_reg[bit_idx];
                    if(baud_tick) begin
                        if(bit_idx==7) state<=STOP;
                        else bit_idx<=bit_idx+1;
                    end
                end
                STOP: begin
                    tx<=1;
                    if(baud_tick) begin
                        state<=IDLE; busy<=0;
                    end
                end
            endcase
        end
    end
endmodule

// ------------------------------------------------------------
// 3. UART RECEIVER
// ------------------------------------------------------------
module uart_rx #(
    parameter CLKS_PER_BIT = 10
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output reg  [7:0] rx_byte,
    output reg        rx_done
);
    localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
    reg [1:0]  state;
    reg [2:0]  bit_idx;
    reg [12:0] clk_count;

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state<=IDLE; rx_byte<=0;
            rx_done<=0; bit_idx<=0; clk_count<=0;
        end else begin
            rx_done<=0;
            case(state)
                IDLE: begin
                    clk_count<=0; bit_idx<=0;
                    if(rx==0) state<=START;
                end
                START: begin
                    if(clk_count==(CLKS_PER_BIT/2)-1) begin
                        if(rx==0) begin
                            clk_count<=0; state<=DATA;
                        end else state<=IDLE;
                    end else clk_count<=clk_count+1;
                end
                DATA: begin
                    if(clk_count==CLKS_PER_BIT-1) begin
                        clk_count<=0;
                        rx_byte[bit_idx]<=rx;
                        if(bit_idx==7) begin
                            bit_idx<=0; state<=STOP;
                        end else bit_idx<=bit_idx+1;
                    end else clk_count<=clk_count+1;
                end
                STOP: begin
                    if(clk_count==CLKS_PER_BIT-1) begin
                        rx_done<=1; clk_count<=0; state<=IDLE;
                    end else clk_count<=clk_count+1;
                end
            endcase
        end
    end
endmodule

// ------------------------------------------------------------
// 4. CONFIGURATION REGISTER
// ------------------------------------------------------------
module uart_config(
    input  wire        clk,
    input  wire        reset,
    input  wire        wr,
    input  wire [31:0] cfg,
    output reg  [23:0] cpb,
    output reg         stop2,
    output reg  [1:0]  par,
    output reg  [1:0]  db
);
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            cpb<=5208; stop2<=0; par<=0; db<=0;
        end else if(wr) begin
            cpb   <= cfg[23:0];
            stop2 <= cfg[24];
            par   <= cfg[26:25];
            db    <= cfg[28:27];
        end
    end
endmodule

// ------------------------------------------------------------
// 5. FIFO BUFFER
// ------------------------------------------------------------
module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 8
)(
    input  wire             clk,
    input  wire             reset,
    input  wire             wr_en,
    input  wire             rd_en,
    input  wire [WIDTH-1:0] din,
    output reg  [WIDTH-1:0] dout,
    output wire             full,
    output wire             empty
);
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [2:0] wr_ptr=0, rd_ptr=0;
    reg [3:0] count=0;

    assign full  = (count==DEPTH);
    assign empty = (count==0);

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            wr_ptr<=0; rd_ptr<=0; count<=0; dout<=0;
        end else begin
            if(wr_en && !full) begin
                mem[wr_ptr]<=din;
                wr_ptr<=wr_ptr+1;
                count<=count+1;
            end
            if(rd_en && !empty) begin
                dout<=mem[rd_ptr];
                rd_ptr<=rd_ptr+1;
                count<=count-1;
            end
        end
    end
endmodule

// ------------------------------------------------------------
// 6. COMPLETE INTEGRATION TESTBENCH
//    TX -> RX loopback, bytes stored in FIFO, config tested
// ------------------------------------------------------------
module tb_uart_complete;
    reg clk=0, reset=1;

    // --- TX wires ---
    reg        send=0;
    reg  [7:0] tx_byte=0;
    wire       tx_line;
    wire       tx_busy;

    // --- RX wires ---
    wire [7:0] rx_byte;
    wire       rx_done;

    // --- FIFO wires ---
    reg        fifo_rd=0;
    wire [7:0] fifo_dout;
    wire       fifo_full, fifo_empty;

    // --- Config wires ---
    reg        cfg_wr=0;
    reg [31:0] cfg_word=0;
    wire [23:0] cpb;
    wire        stop2;
    wire [1:0]  par, db;

    // Instantiate all 4 modules
    uart_tx   #(.CLKS_PER_BIT(10)) TX(
        .clk(clk),.reset(reset),
        .send(send),.tx_byte(tx_byte),
        .tx(tx_line),.busy(tx_busy)
    );

    uart_rx   #(.CLKS_PER_BIT(10)) RX(
        .clk(clk),.reset(reset),
        .rx(tx_line),
        .rx_byte(rx_byte),.rx_done(rx_done)
    );

    fifo #(.WIDTH(8),.DEPTH(8)) RXFIFO(
        .clk(clk),.reset(reset),
        .wr_en(rx_done),
        .rd_en(fifo_rd),
        .din(rx_byte),
        .dout(fifo_dout),
        .full(fifo_full),
        .empty(fifo_empty)
    );

    uart_config CFG(
        .clk(clk),.reset(reset),
        .wr(cfg_wr),.cfg(cfg_word),
        .cpb(cpb),.stop2(stop2),
        .par(par),.db(db)
    );

    always #5 clk=~clk;

    // Capture received byte
    reg [7:0] captured=0;
    always @(posedge clk)
        if(rx_done) captured<=rx_byte;

    // Send one byte over TX
    task send_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            tx_byte=data; send=1;
            @(posedge clk); send=0;
            wait(tx_busy==0);
            repeat(30) @(posedge clk);
        end
    endtask

    // Read one byte from FIFO
    task read_fifo;
        begin
            @(posedge clk); fifo_rd=1;
            @(posedge clk); fifo_rd=0;
            @(posedge clk);
        end
    endtask

    integer pass=0, fail=0;

    task check;
        input [7:0] exp;
        begin
            if(fifo_dout==exp) begin
                $display("  PASS: got 0x%02X", fifo_dout);
                pass=pass+1;
            end else begin
                $display("  FAIL: got 0x%02X exp 0x%02X",
                         fifo_dout, exp);
                fail=fail+1;
            end
        end
    endtask

    reg [31:0] w;

    initial begin
        $display("=========================================");
        $display("   COMPLETE UART CORE - FINAL TEST");
        $display("=========================================");
        #15 reset=0;
        repeat(10) @(posedge clk);

        // -- Config Test --
        $display("");
        $display("--- Config Register ---");
        w=0; w[23:0]=434; w[24]=0; w[26:25]=2; w[28:27]=0;
        @(posedge clk); cfg_word=w; cfg_wr=1;
        @(posedge clk); cfg_wr=0;
        @(posedge clk);
        $display("  cpb=%0d (exp 434) %s",
            cpb, cpb==434?"PASS":"FAIL");
        $display("  par=%02b (exp 10=even) %s",
            par, par==2?"PASS":"FAIL");

        // -- TX->RX Loopback Test --
        $display("");
        $display("--- TX to RX Loopback ---");
        send_byte(8'h41); // A
        send_byte(8'h55); // U
        send_byte(8'h52); // R
        send_byte(8'h54); // T

        // -- FIFO Test --
        $display("");
        $display("--- FIFO Read Back ---");
        $display("  FIFO empty=%0b (exp 0)", fifo_empty);
        read_fifo; check(8'h41);
        read_fifo; check(8'h55);
        read_fifo; check(8'h52);
        read_fifo; check(8'h54);
        $display("  FIFO empty=%0b (exp 1)", fifo_empty);

        $display("");
        $display("=========================================");
        $display("  RESULT: %0d passed, %0d failed", pass, fail);
        if(fail==0)
            $display("  ALL TESTS PASSED - UART CORE COMPLETE!");
        $display("=========================================");
        $finish;
    end
endmodule
