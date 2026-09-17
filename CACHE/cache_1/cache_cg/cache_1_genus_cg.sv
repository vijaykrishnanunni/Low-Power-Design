//
// cache_2way_clock_gated.sv
// VERSION 2 - CLOCK-GATED
//
// Same cache functionality as baseline.
// Clock-enable style RTL for Genus ICG insertion.
//
// Clock-gated register groups:
// 1. FSM state
// 2. Miss-context registers
// 3. Memory-response register
// 4. Cache arrays
// 5. LRU
//

module cache_2way_clock_gated (
    input logic clk,
    input logic rst_n,

    // CPU-side read interface
    input logic        req_valid,
    input logic [31:0] req_addr,
    input logic        req_size,       // 1 = word, 0 = byte
    output logic       req_ready,
    output logic       resp_valid,
    output logic       hit,
    output logic [31:0] rd_data,

    // Memory-side line-fill interface
    output logic        mem_req_valid,
    output logic [31:0] mem_req_addr,
    input logic         mem_req_ready,
    input logic         mem_resp_valid,
    input logic [255:0] mem_resp_data
);

  // Cache storage: 2 ways x 4 sets
  logic        valid_arr [1:0][3:0];
  logic [24:0] tag_arr   [1:0][3:0];
  logic [255:0] data_arr [1:0][3:0];
  logic        lru_arr   [3:0];

  // Address fields
  wire [24:0] req_tag      = req_addr[31:7];
  wire [1:0]  req_index    = req_addr[6:5];
  wire [2:0]  req_word_off = req_addr[4:2];
  wire [1:0]  req_byte_off = req_addr[1:0];

  // Check both ways for a valid tag match
  wire way0_hit = valid_arr[0][req_index] &&
                  (tag_arr[0][req_index] == req_tag);

  wire way1_hit = valid_arr[1][req_index] &&
                  (tag_arr[1][req_index] == req_tag);

  wire lookup_hit = way0_hit | way1_hit;
  wire hit_way    = way1_hit;

  // Select the matching cache line
  wire [255:0] hit_line =
                  way0_hit ? data_arr[0][req_index] :
                             data_arr[1][req_index];

  // Select requested word and byte
  wire [31:0] hit_word = hit_line[32*req_word_off +: 32];
  wire [7:0]  hit_byte = hit_word[8*req_byte_off +: 8];

  // Return either a word or zero-padded byte
  wire [31:0] hit_data =
                req_size ? hit_word :
                           {24'b0, hit_byte};

  // FSM states
  typedef enum logic [1:0] {
      IDLE,
      MISS_REQ,
      MISS_WAIT,
      FILL
  } state_t;

  state_t state, state_n;

  // Latched miss information
  logic [1:0]  miss_index_q;
  logic [24:0] miss_tag_q;
  logic        victim_way_q;
  logic [2:0]  miss_word_off_q;
  logic [1:0]  miss_byte_off_q;
  logic        miss_size_q;

  // Registered memory response
  logic [255:0] mem_resp_data_q;

  // Select requested data from filled cache line
  wire [31:0] fill_word =
              mem_resp_data_q[32*miss_word_off_q +: 32];

  wire [7:0]  fill_byte =
              fill_word[8*miss_byte_off_q +: 8];

  wire [31:0] fill_data =
                miss_size_q ? fill_word :
                              {24'b0, fill_byte};

  // Existing control conditions
  wire fill_wr_en =
              (state == FILL);

  wire miss_accept_en =
              (state == IDLE) &&
              req_valid &&
              !lookup_hit;

  wire hit_en =
              (state == IDLE) &&
              req_valid &&
              lookup_hit;

  // Clock-enable conditions
  // These are intended to be recognized by Genus
  // and converted into library ICG cells.

  // FSM must wake up for a new request and remain active
  // while processing a miss.
  wire fsm_clk_en =
              (state != IDLE) ||
              req_valid;

  // Miss context only changes when a miss is accepted.
  wire miss_ctx_clk_en =
              miss_accept_en;

  // Memory response register only changes when valid
  // memory data is received.
  wire mem_resp_clk_en =
              (state == MISS_WAIT) &&
              mem_resp_valid;

  // Cache arrays only change during FILL.
  wire cache_array_clk_en =
              fill_wr_en;

  // LRU changes only on hit or fill.
  wire lru_clk_en =
              hit_en ||
              fill_wr_en;

  integer wi, si;

  // Combinational FSM and output logic
  always_comb begin

    state_n       = state;
    req_ready     = 1'b0;
    resp_valid    = 1'b0;
    hit           = 1'b0;
    rd_data       = '0;
    mem_req_valid = 1'b0;
    mem_req_addr  = '0;

    unique case (state)

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

      MISS_WAIT: begin

        if (mem_resp_valid)
          state_n = FILL;

      end

      FILL: begin
        resp_valid = 1'b1;
        hit        = 1'b0;
        rd_data    = fill_data;
        state_n    = IDLE;
      end

      default: begin
        state_n = IDLE;
      end

    endcase

  end

  // FSM state register
  // Genus can infer clock gating from fsm_clk_en.
  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin
      state <= IDLE;
    end

    else if (fsm_clk_en) begin
      state <= state_n;
    end

  end

  // Miss-context registers
  // Updated only when a miss is accepted.
  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      miss_index_q    <= '0;
      miss_tag_q      <= '0;
      victim_way_q    <= 1'b0;
      miss_word_off_q <= '0;
      miss_byte_off_q <= '0;
      miss_size_q     <= 1'b0;

    end

    else if (miss_ctx_clk_en) begin

      miss_index_q    <= req_index;
      miss_tag_q      <= req_tag;
      victim_way_q    <= lru_arr[req_index];
      miss_word_off_q <= req_word_off;
      miss_byte_off_q <= req_byte_off;
      miss_size_q     <= req_size;

    end

  end

  // Registered memory response
  // Updated only when memory returns a valid response.
  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin
      mem_resp_data_q <= '0;
    end

    else if (mem_resp_clk_en) begin
      mem_resp_data_q <= mem_resp_data;
    end

  end

  // Cache arrays
  // Written only during FILL.
  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      for (wi = 0; wi < 2; wi = wi + 1)
        for (si = 0; si < 4; si = si + 1)
          valid_arr[wi][si] <= 1'b0;

    end

    else if (cache_array_clk_en) begin

      valid_arr[victim_way_q][miss_index_q] <= 1'b1;
      tag_arr[victim_way_q][miss_index_q]   <= miss_tag_q;
      data_arr[victim_way_q][miss_index_q]  <= mem_resp_data_q;

    end

  end

  // LRU
  // Updated only on hit or fill.
  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      for (si = 0; si < 4; si = si + 1)
        lru_arr[si] <= 1'b0;

    end

    else if (lru_clk_en) begin

      if (hit_en)
        lru_arr[req_index] <= ~hit_way;

      else if (fill_wr_en)
        lru_arr[miss_index_q] <= ~victim_way_q;

    end

  end

endmodule
