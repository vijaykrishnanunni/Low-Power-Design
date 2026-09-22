upf_version 3.1

set_design_top cache_2way_clock_gated_oi

# ============================================================
# 1. LOGIC CONTROL SIGNALS
# ============================================================
# These controls are assumed to come from always-on logic.

create_logic_port cache_sleep   -direction in
create_logic_port cache_iso     -direction in
create_logic_port cache_save    -direction in
create_logic_port cache_restore -direction in


# ============================================================
# 2. SUPPLY PORTS
# ============================================================

create_supply_port VDD_AON   -direction in
create_supply_port VDD_CACHE -direction in
create_supply_port VDD_RET   -direction in
create_supply_port VSS       -direction in


# ============================================================
# 3. SUPPLY NETS
# ============================================================

create_supply_net VDD_AON
create_supply_net VDD_CACHE
create_supply_net VDD_RET
create_supply_net VSS


connect_supply_net VDD_AON   -ports VDD_AON
connect_supply_net VDD_CACHE -ports VDD_CACHE
connect_supply_net VDD_RET   -ports VDD_RET
connect_supply_net VSS       -ports VSS


# ============================================================
# 4. SUPPLY SETS
# ============================================================

create_supply_set SS_AON \
    -function {power VDD_AON} \
    -function {ground VSS}

create_supply_set SS_CACHE \
    -function {power VDD_CACHE} \
    -function {ground VSS}

create_supply_set SS_RET \
    -function {power VDD_RET} \
    -function {ground VSS}


# ============================================================
# 5. CACHE POWER DOMAIN
# ============================================================

create_power_domain PD_CACHE \
    -include_scope \
    -supply {primary SS_CACHE}


# ============================================================
# 6. POWER SWITCH
# ============================================================
#
# VDD_AON -> power switch -> VDD_CACHE
#
# cache_sleep = 0 : cache ON
# cache_sleep = 1 : cache OFF
#

create_power_switch PS_CACHE \
    -domain PD_CACHE \
    -input_supply_port {vin VDD_AON} \
    -output_supply_port {vout VDD_CACHE} \
    -control_port {sleep cache_sleep} \
    -on_state {CACHE_ON vin {!sleep}} \
    -off_state {CACHE_OFF {sleep}}


# Map to an actual library power-switch cell.
# Replace with the cell available in your .lib.

# map_power_switch PS_CACHE \
#     -domain PD_CACHE \
#     -lib_cells {YOUR_POWER_SWITCH_CELL}


# ============================================================
# 7. OUTPUT ISOLATION
# ============================================================
#
# When cache power is OFF:
# cache outputs are clamped to 0.
#
# Outputs of your cache include:
# req_ready
# resp_valid
# hit
# rd_data
# mem_req_valid
# mem_req_addr
#

set_isolation ISO_CACHE_OUT \
    -domain PD_CACHE \
    -applies_to outputs \
    -clamp_value 0 \
    -isolation_signal cache_iso \
    -isolation_sense high \
    -location parent


# Map to actual library isolation cells.
# Replace with your library cell names.

# map_isolation_cell ISO_CACHE_OUT \
#     -domain PD_CACHE \
#     -lib_cells {YOUR_ISO_CELL}


# ============================================================
# 8. RETENTION
# ============================================================
#
# Retention supply remains ON while main cache supply
# is switched OFF.
#

set_retention RET_CACHE \
    -domain PD_CACHE \
    -retention_power_net VDD_RET \
    -retention_ground_net VSS


# Save before power OFF
# Restore after power ON

set_retention_control RET_CACHE \
    -domain PD_CACHE \
    -save_signal {cache_save high} \
    -restore_signal {cache_restore high}


# Map to actual retention FF cells.
# Replace with your library retention-cell name.

# map_retention_cell RET_CACHE \
#     -domain PD_CACHE \
#     -lib_cells {YOUR_RETENTION_FF_CELL}


# ============================================================
# 9. LEVEL SHIFTERS
# ============================================================
#
# ONLY needed if the cache and surrounding logic operate
# at different voltages.
#
# Example:
# always-on domain = 1.0 V
# cache domain     = 0.8 V
#
# If both are 0.8 V, do NOT insert level shifters.
#

# set_level_shifter LS_CACHE_OUT \
#     -domain PD_CACHE \
#     -applies_to outputs \
#     -location parent

# set_level_shifter LS_CACHE_IN \
#     -domain PD_CACHE \
#     -applies_to inputs \
#     -location self


# Map to actual library level-shifter cells.

# map_level_shifter_cell LS_CACHE_OUT \
#     -domain PD_CACHE \
#     -lib_cells {YOUR_LS_LOW_TO_HIGH_CELL}

# map_level_shifter_cell LS_CACHE_IN \
#     -domain PD_CACHE \
#     -lib_cells {YOUR_LS_HIGH_TO_LOW_CELL}


# ============================================================
# 10. POWER STATES
# ============================================================

add_power_state PD_CACHE \
    -state CACHE_ACTIVE \
        -supply_expr {
            SS_CACHE == {FULL_ON 0.8}
        } \
    -state CACHE_OFF \
        -supply_expr {
            SS_CACHE == {OFF}
        }


# ============================================================
# 11. POWER STATE TABLE
# ============================================================

create_pst CACHE_PST \
    -supplies {
        VDD_AON
        VDD_CACHE
        VDD_RET
        VSS
    }


add_pst_state CACHE_ON \
    -pst CACHE_PST \
    -state {
        AON_ON
        CACHE_ON
        RET_ON
        GND
    }


add_pst_state CACHE_SLEEP \
    -pst CACHE_PST \
    -state {
        AON_ON
        CACHE_OFF
        RET_ON
        GND
    }
