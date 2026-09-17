# Library setup
set_db init_lib_search_path <path_to_lib>
set_db library <your_target.lib>

# Enable clock-gating insertion
# IMPORTANT: do this BEFORE elaborate
set_db lp_insert_clock_gating true

# Optional: choose latch-based clock gating
set_db design:<top_design> .lp_clock_gating_style latch

# Optional: minimum number of flops to share one ICG
set_db design:<top_design> .lp_clock_gating_min_flops 1

# Read RTL
read_hdl cache_2way_clock_gated.sv

# Elaborate
elaborate

# Read timing constraints
read_sdc <your_sdc_file>

# Generic synthesis
syn_generic

# Report clock gating
report_clock_gating

# Map to library cells
syn_map

# Optimize
syn_opt

# Report again
report_clock_gating

# Write mapped netlist
write_hdl > cache_2way_cg_mapped.v
