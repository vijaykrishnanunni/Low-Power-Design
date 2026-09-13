
# 2-Way Set-Associative Flip-Flop Cache

A small **32-bit, byte-addressable, read-only, 2-way set-associative cache** implemented entirely using **flip-flops**.

This project is the **Version 1 — Baseline (Pre-Low-Power)** implementation. The baseline is intentionally kept simple so that it can later be compared against a low-power optimized version.

---

## 1. Overview

The cache is designed for a 32-bit processor address space and has a total capacity of **256 bytes**.

It uses:

* 2-way set associativity
* 4 sets
* 8 total cache lines
* 32-byte cache lines
* 32-bit CPU data interface
* 25-bit tags
* 1-bit LRU replacement per set
* Valid bits
* Flip-flop-based storage
* Read-only operation
* Whole-line refill from memory
* Single outstanding miss

The cache does **not** use SRAM macros. All cache data and metadata are implemented using registers/flip-flops.

---

# 2. Cache Specifications

| Feature            | Specification            |
| ------------------ | ------------------------ |
| Address width      | 32 bits                  |
| Address type       | Byte-addressable         |
| Cache capacity     | 256 bytes                |
| Cache line size    | 32 bytes                 |
| Words per line     | 8 × 32-bit words         |
| Associativity      | 2-way                    |
| Number of sets     | 4                        |
| Total cache lines  | 8                        |
| Ways per set       | 2                        |
| Data bus           | 32 bits                  |
| Tag                | 25 bits                  |
| Index              | 2 bits                   |
| Word offset        | 3 bits                   |
| Byte offset        | 2 bits                   |
| Replacement policy | 1-bit LRU                |
| Valid bits         | 8                        |
| Cache type         | Read-only                |
| Storage            | Flip-flops               |
| Clock              | Single synchronous clock |
| Reset              | Active-low asynchronous  |
| Miss handling      | One miss at a time       |
| Memory refill      | Complete 32-byte line    |
| Write support      | None                     |

---

# 3. Cache Geometry

The cache capacity is:

```text
256 bytes
```

Each cache line contains:

```text
32 bytes = 8 × 32-bit words
```

Since the cache is 2-way associative:

```text
Total lines = 256 / 32
            = 8 lines
```

With 2 ways:

```text
Number of sets = 8 / 2
               = 4 sets
```

Therefore:

```text
                 256-Byte Cache
                       │
             ┌─────────┴─────────┐
             │                   │
           Way 0               Way 1
             │                   │
          4 sets              4 sets
             │                   │
       32-byte line        32-byte line
```

Each set contains two possible cache lines:

```text
             SET
              │
       ┌──────┴──────┐
       │             │
     Way 0         Way 1
   Valid+Tag      Valid+Tag
     +Data          +Data
```

---

# 4. Address Breakdown

The 32-bit CPU address is divided into four fields:

```text
31                         7 6      5 4       2 1       0
┌───────────────────────────┬────────┬─────────┬─────────┐
│           TAG             │ INDEX  │  WORD   │  BYTE   │
│          25 bits          │ 2 bits │ OFFSET  │ OFFSET  │
│                           │        │ 3 bits  │ 2 bits  │
└───────────────────────────┴────────┴─────────┴─────────┘
```

### Tag

```text
address[31:7]
```

Width:

```text
25 bits
```

The tag identifies which memory block is currently stored in a particular set.

### Index

```text
address[6:5]
```

Width:

```text
2 bits
```

This selects one of the four cache sets:

```text
00 → Set 0
01 → Set 1
10 → Set 2
11 → Set 3
```

### Word Offset

```text
address[4:2]
```

Width:

```text
3 bits
```

There are 8 words in each 32-byte cache line:

```text
000 → Word 0
001 → Word 1
010 → Word 2
...
111 → Word 7
```

### Byte Offset

```text
address[1:0]
```

Width:

```text
2 bits
```

This selects a byte within the selected 32-bit word:

```text
00 → Byte 0
01 → Byte 1
10 → Byte 2
11 → Byte 3
```

---

# 5. Cache Storage

The cache contains three major types of storage:

```text
1. Data
2. Tag
3. Valid
```

It also contains an LRU bit for each set.

## Data Storage

There are:

```text
2 ways × 4 sets × 8 words × 32 bits
```

Therefore:

```text
= 2048 bits
= 256 bytes
```

This exactly matches the cache capacity.

Conceptually:

```text
data[way][set][word]
```

where:

```text
way  = 0 or 1
set  = 0 to 3
word = 0 to 7
```

---

## Tag Storage

Each cache line has a 25-bit tag.

```text
2 ways × 4 sets × 25 bits
= 200 bits
```

Conceptually:

```text
tag[way][set]
```

---

## Valid Bits

Each cache line has one valid bit.

There are 8 lines:

```text
2 ways × 4 sets = 8 valid bits
```

The valid bit indicates whether the corresponding cache line contains valid data.

```text
valid = 1 → cache line contains valid data
valid = 0 → cache line is invalid
```

---

## LRU Bits

There is one LRU bit per set:

```text
4 sets × 1 bit = 4 bits
```

The LRU information determines which way should be replaced when both ways in a set are occupied.

---

# 6. Total Storage

The major storage requirements are:

| Storage    |          Size |
| ---------- | ------------: |
| Data       |     2048 bits |
| Tags       |      200 bits |
| Valid bits |        8 bits |
| LRU        |        4 bits |
| **Total**  | **2260 bits** |

The data portion alone represents the 256-byte cache capacity.

---

# 7. Read Operation

The cache supports two types of CPU read accesses.

### Word Read

```text
req_size = 1
```

The cache:

1. Uses the index to select a set.
2. Compares the requested tag against both ways.
3. Checks the valid bits.
4. Determines whether there is a hit.
5. Uses the word offset to select one of the 8 words.
6. Returns the selected 32-bit word.

```text
Address
   │
   ├── Tag ───────► Tag comparison
   │
   ├── Index ─────► Set selection
   │
   └── Word offset ► Word selection
                         │
                         ▼
                     32-bit data
```

### Byte Read

```text
req_size = 0
```

The cache first selects the 32-bit word using the word offset.

The byte offset then selects one byte from that word.

The selected byte is returned in:

```text
rd_data[7:0]
```

and:

```text
rd_data[31:8] = 0
```

Therefore:

```text
rd_data = {24'b0, selected_byte}
```

---

# 8. Cache Hit

A cache hit occurs when:

```text
valid[way][set] == 1
```

and:

```text
tag[way][set] == address[31:7]
```

for either way.

Conceptually:

```text
                  Address
                     │
          ┌──────────┼──────────┐
          │          │          │
         Tag       Index      Offset
          │          │          │
          │          ▼          │
          │        Set N        │
          │          │          │
          │     ┌────┴────┐     │
          │     │         │     │
          ▼     ▼         ▼     │
       Compare Way 0   Compare Way 1
          │               │
          └───────┬───────┘
                  │
                Hit?
                  │
                  ▼
             Select word
                  │
                  ▼
              CPU data
```

---

# 9. Cache Miss

A miss occurs when neither way contains a valid line with the requested tag.

```text
Way 0 → tag mismatch / invalid
Way 1 → tag mismatch / invalid

          ↓

       Cache MISS
```

Since the cache uses a simple single-miss architecture, only one miss is handled at a time.

The complete cache line is requested from memory:

```text
32 bytes = 256 bits
```

The cache waits for the complete line before generating the miss response.

---

# 10. Miss Handling

The basic miss sequence is:

```text
IDLE
  │
  │ Cache miss
  ▼
MISS_REQ
  │
  │ Send memory request
  ▼
MISS_WAIT
  │
  │ Wait for complete 256-bit line
  ▼
FILL
  │
  │ Store tag + data + valid
  ▼
IDLE
```

There is no critical-word-first or early-restart mechanism.

The complete 32-byte line must be received before the cache completes the refill operation.

---

# 11. Replacement Policy

The cache uses a **1-bit LRU policy per set**.

Each set contains:

```text
Way 0
Way 1
```

The LRU bit records which way should be replaced when a new line needs to be allocated and both ways are valid.

Conceptually:

```text
             Set N
               │
        ┌──────┴──────┐
        │             │
      Way 0         Way 1
        │             │
        └──────┬──────┘
               │
             LRU bit
               │
        Select victim way
```

If one way is invalid, the invalid way can be used instead of replacing a valid line.

---

# 12. Memory Interface

The cache uses a simple request/response memory interface.

The memory refill transfers an entire cache line:

```text
256 bits = 32 bytes
```

The cache does not fetch only the requested word.

Conceptually:

```text
Cache
  │
  │  Memory request
  ▼
Memory
  │
  │  256-bit line
  ▼
Cache
```

After receiving the complete line, the cache stores it and can return the requested word/byte to the CPU.

---

# 13. Single Outstanding Miss

The design does not contain MSHRs.

Therefore:

```text
Maximum outstanding cache misses = 1
```

While a miss is being serviced, the cache does not maintain multiple independent outstanding memory requests.

This keeps the baseline architecture simple and makes it suitable for studying the cache architecture before adding more advanced techniques.

---

# 14. Alignment Assumption

Word accesses are assumed to be **4-byte aligned**.

For a word access:

```text
address[1:0] = 2'b00
```

Unaligned word accesses are not supported by this baseline implementation.

Byte accesses can use all four byte-offset values:

```text
00
01
10
11
```

---

# 15. Reset

The cache uses an:

```text
Active-low asynchronous reset
```

During reset, the cache's valid bits are cleared so that all cache lines are initially considered invalid.

Conceptually:

```text
reset = 0
   │
   ├── valid bits → 0
   └── cache starts empty
```

---

# 16. Design Scope

This is intentionally a **baseline cache implementation**.

The following features are NOT included:

* Write operations
* Dirty bits
* Write-back policy
* Write-through policy
* Cache coherence
* Prefetching
* ECC
* Parity
* Cache banking
* SRAM macros
* Multiple outstanding misses
* MSHRs
* Critical-word-first
* Early restart
* Virtual-memory/TLB interaction
* Way prediction
* Power gating
* Clock gating
* Operand isolation
* DVFS

These features can be considered in later versions of the design.

---

# 17. Baseline → Low-Power Study

The main purpose of keeping this version simple is to provide a **reference implementation** for a later low-power version.

The baseline can be synthesized and analyzed for:

```text
Area
Power
Timing
```

A future low-power version can then introduce techniques such as:

```text
Clock gating
Power gating
Operand isolation
Way prediction
Banking
DVFS
```

and compare the results against this frozen baseline.

The comparison can be performed using the same cache functionality and geometry wherever practical.

---

# 18. Key Design Characteristics

The baseline cache can be summarized as:

```text
                 32-bit CPU Address
                         │
        ┌────────────────┼────────────────┐
        │                │                │
       TAG             INDEX            OFFSET
     25 bits           2 bits            5 bits
        │                │                │
        │                ▼                │
        │             4 Sets              │
        │                │                │
        │         ┌──────┴──────┐         │
        │         │             │         │
        ▼       Way 0         Way 1       │
    Tag Compare   │             │         │
        │         │             │         │
        └─────────┴──────┬──────┘         │
                         │                │
                       Hit/Miss            │
                         │                │
                         ▼                ▼
                    Word Select       Byte Select
                         │                │
                         └───────┬────────┘
                                 ▼
                             rd_data
```

---

# 19. Summary

This project implements a fixed-geometry:

> **256-byte, 2-way set-associative, 32-byte-line, read-only cache using flip-flop storage.**

The cache contains:

```text
4 sets
2 ways per set
8 total cache lines
8 words per line
32 bits per word
25-bit tag
2-bit index
3-bit word offset
2-bit byte offset
1-bit LRU per set
1 valid bit per line
```

The baseline uses a simple FSM:

```text
IDLE → MISS_REQ → MISS_WAIT → FILL → IDLE
```

and supports only **one outstanding miss at a time**.

This baseline serves as the functional reference for future **low-power cache optimization and synthesis comparison**.
