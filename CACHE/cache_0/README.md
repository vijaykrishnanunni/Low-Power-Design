
2-way
256 bytes
8-byte lines
32-bit address
Read only
LRU
Valid bit

### Design Assumptions & Limitations

* **Read-only cache** *(no write operations, dirty bits, write-back or write-through logic).*
* **No cache coherence** *(single-core/single-cache system; no multi-core coherence protocol).*
* **No cache prefetching.**
* **No ECC/parity or error-correction logic.**
* **No cache banking or SRAM macros** *(storage is implemented using flip-flops).*
* **No multiple outstanding misses / MSHRs** *(only one cache miss is handled at a time).*
* **No hardware support for unaligned word accesses** *(word accesses are assumed to be 4-byte aligned).*
* **No virtual-memory/TLB interaction** *(addresses are treated as physical addresses).*
* **No critical-word-first or early restart** *(the complete cache line is received before the miss response is generated).*
* **Simple memory request/response interface** with a **32-byte (256-bit) line fill**.
* **Single clock domain** with an active-low asynchronous reset.
* Cache geometry is **fixed** for this project and is not parameterized.
