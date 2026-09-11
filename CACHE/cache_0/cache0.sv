// =============================================================================
// cache_2way_baseline.sv
// VERSION 1 -- BASELINE (frozen spec, pre-low-power)
// "Simplified ARM-inspired 32-bit, byte-addressable, 2-way set-associative
//  cache" -- NOT a claim of matching any specific ARM core's real cache.
//
// Read-only, 2-way set-associative, flip-flop based cache. Hard-coded to
// the frozen geometry below (no parameters) to keep the RTL simple for
// the synthesis/power baseline. This is the design that later gets
// modified into the low-power variant.
//
// Specification (frozen):
//   CPU address width   : 32 bits, byte-addressable
//   Cache capacity       : 256 bytes
//   Cache line size        : 32 bytes (8 x 32-bit words)
//   Associativity            : 2-way set associative
//   Total lines                : 8   |  Number of sets : 4  |  Ways/set : 2
//   Byte offset : 2 bits  |  Word offset : 3 bits  |  Index : 2 bits  |  Tag : 25 bits
//   Data storage : 2 x 4 x 256 = 2048 bits   (== 256 B, matches capacity)
//   Tag storage  : 2 x 4 x 25  =  200 bits
//   Valid bits   : 8
//   CPU data bus  : 32 bits, with a byte/word select (req_size)
//   Replacement policy : 1-bit LRU per set
//   Dirty bit / write support / prefetch / ECC : none
//   Multiple outstanding misses : no -- one miss at a time
//   Memory interface : simple request/response, whole-line fill
//   Clock : single synchronous clock   |   Reset : active-low
//
// Address format:
//   [31:7] TAG (25b)  [6:5] INDEX (2b)  [4:2] WORD OFFSET (3b)  [1:0] BYTE OFFSET (2b)
//
// req_size selects the CPU access granularity:
//   req_size = 1 -> word access  : rd_data = the selected 32-bit word
//   req_size = 0 -> byte access  : rd_data = selected byte in rd_data[7:0],
//                                   rd_data[31:8] zero-padded
//
// Explicitly OUT of scope here (left for the low-power variant): write
// ops, dirty bits, write-back/write-through, prefetch, ECC, coherence,
// banking, power gating, clock gating, operand isolation, way
// prediction, DVFS, SRAM.
// =============================================================================

module cache_2way_baseline (
    input  logic clk,
    input  logic rst_n,

    // ---------------- CPU-side read interface ----------------
    input  logic          req_valid,
    input  logic [31:0]   req_addr,
    input  logic          req_size,    // 1 = word access, 0 = byte access
    output logic          req_ready,   // core can accept a new request
    output logic          resp_valid,  // rd_data valid this cycle
    output logic          hit,         // 1 = served from cache (same cycle as resp_valid on a hit)
    output logic [31:0]   rd_data,

    // ---------------- Memory-side line-fill interface ----------------
    output logic          mem_req_valid,
    output logic [31:0]   mem_req_addr,   // address of missing line (offset bits = 0)
    input  logic          mem_req_ready,
    input  logic          mem_resp_valid,
    input  logic [255:0]  mem_resp_data   // whole 32-byte line, one shot
);

  // ---------------------------------------------------------------------
  // Storage arrays (2 ways x 4 sets), pure flip-flops
  // ---------------------------------------------------------------------
  logic         valid_arr [1:0][3:0];
  logic [24:0]  tag_arr   [1:0][3:0];
  logic [255:0] data_arr  [1:0][3:0];      // 32-byte line per entry
  logic         lru_arr   [3:0];           // lru_arr[set] = way number that is LRU

  // ---------------------------------------------------------------------
  // Address decode: [31:7] tag, [6:5] index, [4:2] word offset, [1:0] byte offset
  // ---------------------------------------------------------------------
  wire [24:0] req_tag      = req_addr[31:7];
  wire [1:0]  req_index    = req_addr[6:5];
  wire [2:0]  req_word_off = req_addr[4:2];
  wire [1:0]  req_byte_off = req_addr[1:0];

  // ---------------------------------------------------------------------
  // Combinational hit detection
  // ---------------------------------------------------------------------
  wire way0_hit = valid_arr[0][req_index] && (tag_arr[0][req_index] == req_tag);
  wire way1_hit = valid_arr[1][req_index] && (tag_arr[1][req_index] == req_tag);
  wire lookup_hit = way0_hit | way1_hit;
  wire hit_way     = way1_hit;                // 0 -> way0, 1 -> way1
  wire [255:0] hit_line = way0_hit ? data_arr[0][req_index] : data_arr[1][req_index];

  // Word-select (8:1) then byte-select (4:1) out of the hit line
  wire [31:0] hit_word = hit_line[32*req_word_off +: 32];
  wire [7:0]  hit_byte = hit_word[8*req_byte_off +: 8];
  wire [31:0] hit_data = req_size ? hit_word : {24'b0, hit_byte};

  // ---------------------------------------------------------------------
  // FSM: IDLE -> MISS_REQ -> MISS_WAIT -> FILL -> IDLE
  // ---------------------------------------------------------------------
  typedef enum logic [1:0] {IDLE, MISS_REQ, MISS_WAIT, FILL} state_t;
  state_t state, state_n;

  // Latched miss context: enough to write the array AND reconstruct the
  // originally-requested word/byte once the line comes back
  logic [1:0] miss_index_q;
  logic [24:0] miss_tag_q;
  logic        victim_way_q;
  logic [2:0]  miss_word_off_q;
  logic [1:0]  miss_byte_off_q;
  logic        miss_size_q;

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) state <= IDLE;
    else        state <= state_n;

  // Latch the memory response the cycle it's valid (MISS_WAIT), since
  // mem_resp_data is only guaranteed valid while mem_resp_valid is high --
  // by the FILL cycle (one clock later) the memory is free to drop or
  // change it. Both the CPU-facing read and the array write use the
  // latched copy, never the raw combinational mem_resp_data.
  logic [255:0] mem_resp_data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mem_resp_data_q <= '0;
    else if (state == MISS_WAIT && mem_resp_valid)
      mem_resp_data_q <= mem_resp_data;
  end

  // Fill-cycle data select, taken from the latched line using the
  // latched offset/size (no need to go back through the array)
  wire [31:0] fill_word = mem_resp_data_q[32*miss_word_off_q +: 32];
  wire [7:0]  fill_byte = fill_word[8*miss_byte_off_q +: 8];
  wire [31:0] fill_data = miss_size_q ? fill_word : {24'b0, fill_byte};

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
            resp_valid = 1'b1;          // combinational hit, same-cycle response
            hit        = 1'b1;
            rd_data    = hit_data;
          end else begin
            state_n = MISS_REQ;
          end
        end
      end

      MISS_REQ: begin
        mem_req_valid = 1'b1;
        mem_req_addr  = {miss_tag_q, miss_index_q, 5'b00000};  // 32B-aligned line address
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

      default: state_n = IDLE;
    endcase
  end

  // Latch miss context when leaving IDLE on a miss
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      miss_index_q    <= '0;
      miss_tag_q      <= '0;
      victim_way_q    <= 1'b0;
      miss_word_off_q <= '0;
      miss_byte_off_q <= '0;
      miss_size_q     <= 1'b0;
    end else if (state == IDLE && req_valid && !lookup_hit) begin
      miss_index_q    <= req_index;
      miss_tag_q      <= req_tag;
      victim_way_q    <= lru_arr[req_index];   // current LRU way is the victim
      miss_word_off_q <= req_word_off;
      miss_byte_off_q <= req_byte_off;
      miss_size_q     <= req_size;
    end
  end

  // ---------------------------------------------------------------------
  // Fill write (single indexed write on FILL) + LRU update
  // ---------------------------------------------------------------------
  wire fill_wr_en = (state == FILL);
  integer wi, si;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (wi = 0; wi < 2; wi = wi + 1)
        for (si = 0; si < 4; si = si + 1)
          valid_arr[wi][si] <= 1'b0;
    end else if (fill_wr_en) begin
      valid_arr[victim_way_q][miss_index_q] <= 1'b1;
    end
  end

  always_ff @(posedge clk)
    if (fill_wr_en)
      tag_arr[victim_way_q][miss_index_q] <= miss_tag_q;

  always_ff @(posedge clk)
    if (fill_wr_en)
      data_arr[victim_way_q][miss_index_q] <= mem_resp_data_q;

  // LRU: on a hit, the *other* way becomes LRU; on a fill, the way NOT
  // just filled becomes LRU (the filled way is now MRU)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (si = 0; si < 4; si = si + 1)
        lru_arr[si] <= 1'b0;                    // arbitrary: way0 LRU first
    end else if (state == IDLE && req_valid && lookup_hit) begin
      lru_arr[req_index] <= ~hit_way;
    end else if (fill_wr_en) begin
      lru_arr[miss_index_q] <= ~victim_way_q;
    end
  end

endmodule
any mistakws?
