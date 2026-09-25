//
// cache_2way_clock_gated_oi.v
// VERSION 3 - CLOCK-GATED + OPERAND ISOLATION
//
// Same cache functionality as baseline.
// Clock-enable style RTL for Genus ICG insertion.
// Operand isolation added to the CPU-side lookup operands.
//

module cache_2way_clock_gated_oi (
    input         clk,
    input         rst_n,

    // CPU-side read interface
    input         req_valid,
    input  [31:0] req_addr,
    input         req_size,       // 1 = word, 0 = byte
    output reg    req_ready,
    output reg    resp_valid,
    output reg    hit,
    output reg [31:0] rd_data,

    // Memory-side line-fill interface
    output reg    mem_req_valid,
    output reg [31:0] mem_req_addr,
    input         mem_req_ready,
    input         mem_resp_valid,
    input  [255:0] mem_resp_data
);

  // ------------------------------------------------------------
  // Cache storage: 2 ways x 4 sets
  // ------------------------------------------------------------

  reg        valid_arr [1:0][3:0];
  reg [24:0] tag_arr   [1:0][3:0];
  reg [255:0] data_arr [1:0][3:0];
  reg        lru_arr   [3:0];

  // ------------------------------------------------------------
  // FSM states
  // ------------------------------------------------------------

  localparam IDLE      = 2'b00;
  localparam MISS_REQ  = 2'b01;
  localparam MISS_WAIT = 2'b10;
  localparam FILL      = 2'b11;

  reg [1:0] state;
  reg [1:0] state_n;

  // ------------------------------------------------------------
  // Latched miss information
  // ------------------------------------------------------------

  reg [1:0]  miss_index_q;
  reg [24:0] miss_tag_q;
  reg        victim_way_q;
  reg [2:0]  miss_word_off_q;
  reg [1:0]  miss_byte_off_q;
  reg        miss_size_q;

  // ------------------------------------------------------------
  // Registered memory response
  // ------------------------------------------------------------

  reg [255:0] mem_resp_data_q;

  // ------------------------------------------------------------
  // Operand isolation enable
  //
  // Lookup logic is active only when the cache is in IDLE
  // and a valid CPU request is present.
  // ------------------------------------------------------------

  wire lookup_en;

  assign lookup_en =
              (state == IDLE) &&
              req_valid;

  // ------------------------------------------------------------
  // Operand isolation
  //
  // Real operands pass when lookup_en = 1.
  // Constant zero is supplied when lookup_en = 0.
  // ------------------------------------------------------------

  wire [31:0] iso_req_addr;
  wire        iso_req_size;

  assign iso_req_addr =
              lookup_en ? req_addr : 32'b0;

  assign iso_req_size =
              lookup_en ? req_size : 1'b0;

  // ------------------------------------------------------------
  // Address fields from isolated address
  // ------------------------------------------------------------

  wire [24:0] req_tag;
  wire [1:0]  req_index;
  wire [2:0]  req_word_off;
  wire [1:0]  req_byte_off;

  assign req_tag =
              iso_req_addr[31:7];

  assign req_index =
              iso_req_addr[6:5];

  assign req_word_off =
              iso_req_addr[4:2];

  assign req_byte_off =
              iso_req_addr[1:0];

  // ------------------------------------------------------------
  // Check both ways for a valid tag match
  // ------------------------------------------------------------

  wire way0_hit;
  wire way1_hit;

  assign way0_hit =
              valid_arr[0][req_index] &&
              (tag_arr[0][req_index] == req_tag);

  assign way1_hit =
              valid_arr[1][req_index] &&
              (tag_arr[1][req_index] == req_tag);

  wire lookup_hit;
  wire hit_way;

  assign lookup_hit = way0_hit | way1_hit;
  assign hit_way    = way1_hit;

  // ------------------------------------------------------------
  // Select the matching cache line
  // ------------------------------------------------------------

  wire [255:0] hit_line;

  assign hit_line =
              way0_hit ? data_arr[0][req_index] :
                         data_arr[1][req_index];

  // ------------------------------------------------------------
  // Select requested word and byte
  // ------------------------------------------------------------

  wire [31:0] hit_word;
  wire [7:0]  hit_byte;

  assign hit_word =
              hit_line[32*req_word_off +: 32];

  assign hit_byte =
              hit_word[8*req_byte_off +: 8];

  // ------------------------------------------------------------
  // Return either a word or zero-padded byte
  // ------------------------------------------------------------

  wire [31:0] hit_data;

  assign hit_data =
              iso_req_size ? hit_word :
                             {24'b0, hit_byte};

  // ------------------------------------------------------------
  // Select requested data from filled cache line
  // ------------------------------------------------------------

  wire [31:0] fill_word;
  wire [7:0]  fill_byte;
  wire [31:0] fill_data;

  assign fill_word =
              mem_resp_data_q[32*miss_word_off_q +: 32];

  assign fill_byte =
              fill_word[8*miss_byte_off_q +: 8];

  assign fill_data =
              miss_size_q ? fill_word :
                            {24'b0, fill_byte};

  // ------------------------------------------------------------
  // Existing control conditions
  // ------------------------------------------------------------

  wire fill_wr_en;
  wire miss_accept_en;
  wire hit_en;

  assign fill_wr_en =
              (state == FILL);

  assign miss_accept_en =
              (state == IDLE) &&
              req_valid &&
              !lookup_hit;

  assign hit_en =
              (state == IDLE) &&
              req_valid &&
              lookup_hit;

  // ------------------------------------------------------------
  // Clock-enable conditions
  // ------------------------------------------------------------

  // FSM wakes up for a new request and remains active
  // while processing a miss.
  wire fsm_clk_en;

  assign fsm_clk_en =
              (state != IDLE) ||
              req_valid;

  // Miss context changes only when a miss is accepted.
  wire miss_ctx_clk_en;

  assign miss_ctx_clk_en =
              miss_accept_en;

  // Memory response register changes only when a valid
  // memory response is received.
  wire mem_resp_clk_en;

  assign mem_resp_clk_en =
              (state == MISS_WAIT) &&
              mem_resp_valid;

  // Cache arrays change only during FILL.
  wire cache_array_clk_en;

  assign cache_array_clk_en =
              fill_wr_en;

  // LRU changes only on hit or fill.
  wire lru_clk_en;

  assign lru_clk_en =
              hit_en ||
              fill_wr_en;

  integer wi;
  integer si;

  // ------------------------------------------------------------
  // Combinational FSM and output logic
  // ------------------------------------------------------------

  always @(*) begin

    state_n       = state;
    req_ready     = 1'b0;
    resp_valid    = 1'b0;
    hit           = 1'b0;
    rd_data       = 32'b0;
    mem_req_valid = 1'b0;
    mem_req_addr  = 32'b0;

    case (state)

      // --------------------------------------------------------
      // IDLE
      // --------------------------------------------------------

      IDLE: begin

        req_ready = 1'b1;

        if (req_valid) begin

          if (lookup_hit) begin

            resp_valid = 1'b1;
            hit        = 1'b1;
            rd_data    = hit_data;

          end

          else begin

            state_n = MISS_REQ;

          end

        end

      end

      // --------------------------------------------------------
      // MISS_REQ
      // --------------------------------------------------------

      MISS_REQ: begin

        mem_req_valid = 1'b1;

        mem_req_addr = {
            miss_tag_q,
            miss_index_q,
            5'b00000
        };

        if (mem_req_ready)
          state_n = MISS_WAIT;

      end

      // --------------------------------------------------------
      // MISS_WAIT
      // --------------------------------------------------------

      MISS_WAIT: begin

        if (mem_resp_valid)
          state_n = FILL;

      end

      // --------------------------------------------------------
      // FILL
      // --------------------------------------------------------

      FILL: begin

        resp_valid = 1'b1;
        hit        = 1'b0;
        rd_data    = fill_data;
        state_n    = IDLE;

      end

      // --------------------------------------------------------
      // DEFAULT
      // --------------------------------------------------------

      default: begin

        state_n = IDLE;

      end

    endcase

  end

  // ------------------------------------------------------------
  // FSM state register
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      state <= IDLE;

    end

    else if (fsm_clk_en) begin

      state <= state_n;

    end

  end

  // ------------------------------------------------------------
  // Miss-context registers
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      miss_index_q    <= 2'b0;
      miss_tag_q      <= 25'b0;
      victim_way_q    <= 1'b0;
      miss_word_off_q <= 3'b0;
      miss_byte_off_q <= 2'b0;
      miss_size_q     <= 1'b0;

    end

    else if (miss_ctx_clk_en) begin

      miss_index_q    <= req_index;
      miss_tag_q      <= req_tag;
      victim_way_q    <= lru_arr[req_index];
      miss_word_off_q <= req_word_off;
      miss_byte_off_q <= req_byte_off;
      miss_size_q     <= iso_req_size;

    end

  end

  // ------------------------------------------------------------
  // Registered memory response
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      mem_resp_data_q <= 256'b0;

    end

    else if (mem_resp_clk_en) begin

      mem_resp_data_q <= mem_resp_data;

    end

  end

  // ------------------------------------------------------------
  // Cache arrays
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      for (wi = 0; wi < 2; wi = wi + 1) begin

        for (si = 0; si < 4; si = si + 1) begin

          valid_arr[wi][si] <= 1'b0;

        end

      end

    end

    else if (cache_array_clk_en) begin

      valid_arr[victim_way_q][miss_index_q] <= 1'b1;
      tag_arr[victim_way_q][miss_index_q]   <= miss_tag_q;
      data_arr[victim_way_q][miss_index_q]  <= mem_resp_data_q;

    end

  end

  // ------------------------------------------------------------
  // LRU
  // ------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      for (si = 0; si < 4; si = si + 1) begin

        lru_arr[si] <= 1'b0;

      end

    end

    else if (lru_clk_en) begin

      if (hit_en) begin

        lru_arr[req_index] <= ~hit_way;

      end

      else if (fill_wr_en) begin

        lru_arr[miss_index_q] <= ~victim_way_q;

      end

    end

  end

endmodule
