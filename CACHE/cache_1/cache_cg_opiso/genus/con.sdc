# ============================================================
# Clock
# ============================================================

create_clock -name clk -period 10.0 [get_ports clk]

# Clock uncertainty
set_clock_uncertainty -setup 0.2 [get_clocks clk]
set_clock_uncertainty -hold  0.1 [get_clocks clk]


# ============================================================
# Reset
# ============================================================

set_false_path -from [get_ports rst_n]


# ============================================================
# CPU-side inputs
# ============================================================

set_input_delay 2.0 -clock clk [get_ports req_valid]
set_input_delay 2.0 -clock clk [get_ports req_addr]
set_input_delay 2.0 -clock clk [get_ports req_size]


# ============================================================
# Memory-side inputs
# ============================================================

set_input_delay 2.0 -clock clk [get_ports mem_req_ready]
set_input_delay 2.0 -clock clk [get_ports mem_resp_valid]
set_input_delay 2.0 -clock clk [get_ports mem_resp_data]


# ============================================================
# CPU-side outputs
# ============================================================

set_output_delay 2.0 -clock clk [get_ports req_ready]
set_output_delay 2.0 -clock clk [get_ports resp_valid]
set_output_delay 2.0 -clock clk [get_ports hit]
set_output_delay 2.0 -clock clk [get_ports rd_data]


# ============================================================
# Memory-side outputs
# ============================================================

set_output_delay 2.0 -clock clk [get_ports mem_req_valid]
set_output_delay 2.0 -clock clk [get_ports mem_req_addr]


# ============================================================
# Input drive strength / output load
# ============================================================

set_driving_cell -lib_cell INVX1 [get_ports req_valid]
set_driving_cell -lib_cell INVX1 [get_ports req_addr]
set_driving_cell -lib_cell INVX1 [get_ports req_size]

set_driving_cell -lib_cell INVX1 [get_ports mem_req_ready]
set_driving_cell -lib_cell INVX1 [get_ports mem_resp_valid]
set_driving_cell -lib_cell INVX1 [get_ports mem_resp_data]

set_load 0.05 [get_ports req_ready]
set_load 0.05 [get_ports resp_valid]
set_load 0.05 [get_ports hit]
set_load 0.05 [get_ports rd_data]
set_load 0.05 [get_ports mem_req_valid]
set_load 0.05 [get_ports mem_req_addr]
