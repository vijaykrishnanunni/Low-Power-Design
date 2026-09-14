//
// cache_2way_baseline.sv
// VERSION 1 - BASELINE (frozen spec, pre-low-power)
//
// Read-only, 2-way set-associative cache
// 256-byte capacity, 32-byte line, 4 sets
// Flip-flop based storage, no SRAM
//

module cache_2way_baseline (
    input logic clk,
    input logic rst_n,

    // CPU-side read interface
    input  logic        req_valid,
    input  logic [31:0] req_addr,
    input  logic        req_size,       // 1 = word, 0 = byte
    output logic        req_ready,
    output logic        resp_valid,
    output logic        hit,
    output logic [31:0] rd_data,

    // Memory-side line-fill interface
    output logic        mem_req_valid,
    output logic [31:0] mem_req_addr,
    input  logic         mem_req_ready,
    input  logic         mem_resp_valid,
    input  logic [255:0] mem_resp_data
);

  // Cache storage: 2 ways x 4 sets
  logic        valid_arr [1:0][3:0];
  logic [24:0] tag_arr   [1:0][3:0];
  logic [255:0] data_arr  [1:0][3:0];
  logic        lru_arr   [3:0];

  // Address fields: tag [31:7], index [6:5], word offset [4:2], byte offset [1:0]
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

  // Select requested word and byte from the cache line
  wire [31:0] hit_word = hit_line[32*req_word_off +: 32];
  wire [7:0]  hit_byte = hit_word[8*req_byte_off +: 8];

  // Return either a word or zero-padded byte
  wire [31:0] hit_data = req_size ? hit_word : {24'b0, hit_byte};

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

  // Select requested data from the filled cache line
  wire [31:0] fill_word = mem_resp_data_q[32*miss_word_off_q +: 32];
  wire [7:0]  fill_byte = fill_word[8*miss_byte_off_q +: 8];

  wire [31:0] fill_data =
                miss_size_q ? fill_word : {24'b0, fill_byte};

  // Cache write occurs during FILL
  wire fill_wr_en = (state == FILL);

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
        req_ready = 1'b1;                       // Cache can accept request

        if (req_valid) begin

          if (lookup_hit) begin
            resp_valid = 1'b1;                  // Hit response valid
            hit        = 1'b1;                  // Request was a hit
            rd_data    = hit_data;              // Return requested data
          end

          else begin
            state_n = MISS_REQ;                 // Start miss handling
          end

        end
      end

      MISS_REQ: begin
        mem_req_valid = 1'b1;                   // Request missing line

        mem_req_addr = {
            miss_tag_q,
            miss_index_q,
            5'b00000
        };                                       // 32-byte aligned address

        if (mem_req_ready)
          state_n = MISS_WAIT;                  // Memory accepted request
      end

      MISS_WAIT: begin

        if (mem_resp_valid)
          state_n = FILL;                       // Memory returned cache line

      end

      FILL: begin
        resp_valid = 1'b1;                      // Return data after miss
        hit        = 1'b0;                      // Original access was a miss
        rd_data    = fill_data;                 // Select requested word/byte
        state_n    = IDLE;                      // Return to idle
      end

      default: state_n = IDLE;                 // Recover to idle

    endcase

  end


  // All sequential logic
  always_ff @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      state <= IDLE;                             // FSM state reset

      mem_resp_data_q <= '0;                    // Memory response reset

      miss_index_q    <= '0;                    // Miss index reset
      miss_tag_q      <= '0;                    // Miss tag reset
      victim_way_q    <= 1'b0;                  // Victim way reset
      miss_word_off_q <= '0;                    // Word offset reset
      miss_byte_off_q <= '0;                    // Byte offset reset
      miss_size_q     <= 1'b0;                  // Request size reset

      for (wi = 0; wi < 2; wi = wi + 1)
        for (si = 0; si < 4; si = si + 1)
          valid_arr[wi][si] <= 1'b0;             // All entries invalid

      for (si = 0; si < 4; si = si + 1)
        lru_arr[si] <= 1'b0;                     // Way0 initially LRU

    end

    else begin

      state <= state_n;                          // Update FSM state

      if (state == MISS_WAIT && mem_resp_valid)
        mem_resp_data_q <= mem_resp_data;        // Capture memory response

      if (state == IDLE && req_valid && !lookup_hit) begin
        miss_index_q    <= req_index;            // Save miss set index
        miss_tag_q      <= req_tag;              // Save requested tag
        victim_way_q    <= lru_arr[req_index];  // Save LRU victim way
        miss_word_off_q <= req_word_off;         // Save word offset
        miss_byte_off_q <= req_byte_off;         // Save byte offset
        miss_size_q     <= req_size;             // Save byte/word request
      end
    //since it takes several cycles if missed to finally feed CPU data, the req addr info are stored by the cache


      if (fill_wr_en)
        valid_arr[victim_way_q][miss_index_q] <= 1'b1;  // Set valid bit

      if (fill_wr_en)
        tag_arr[victim_way_q][miss_index_q] <= miss_tag_q; // Store tag

      if (fill_wr_en)
        data_arr[victim_way_q][miss_index_q] <= mem_resp_data_q; // Store line

      if (state == IDLE && req_valid && lookup_hit)
        lru_arr[req_index] <= ~hit_way;           // Other way becomes LRU

      else if (fill_wr_en)
        lru_arr[miss_index_q] <= ~victim_way_q;   // Filled way becomes MRU

    end

  end

endmodule
