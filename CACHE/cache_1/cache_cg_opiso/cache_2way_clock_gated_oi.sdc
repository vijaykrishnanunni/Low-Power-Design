# cache_2way_clock_gated_oi.sdc

# Clock definition
create_clock -name clk -period 1.0 [get_ports clk]

# Clock uncertainty
set_clock_uncertainty 0.05 [get_clocks clk]

# Clock transition
set_clock_transition 0.05 [get_clocks clk]

# Input delays
set_input_delay 0.20 -clock clk [get_ports {
    req_valid
    req_addr
    req_size
    mem_req_ready
    mem_resp_valid
    mem_resp_data
}]

# Output delays
set_output_delay 0.20 -clock clk [get_ports {
    req_ready
    resp_valid
    hit
    rd_data
    mem_req_valid
    mem_req_addr
}]

# Asynchronous reset
set_false_path -from [get_ports rst_n]

# Maximum transition
set_max_transition 0.20 [current_design]

# Maximum fanout
set_max_fanout 20 [current_design]
