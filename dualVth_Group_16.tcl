# Procedure to swap the most critical cells to High-Vt (HVT)
proc swap_some_cells_to_hvt {lvt_to_swap} {
    set cells [get_cells]                ;# Get all cells in the design
    set library_name "CORE65LPHVT"
    foreach cell $lvt_to_swap {
        foreach_in_collection cell_ref [get_cells] {
            set full_name [get_attribute $cell_ref full_name]
            set ref_name [get_attribute $cell_ref ref_name]
            if {$cell == $full_name} {
                regsub {_LL} $ref_name "_LH" new_ref_name
                size_cell $cell_ref "${library_name}/${new_ref_name}"
            }  
        }
    }
} 

# Procedure to swap a cell to Low-Vt (LVT)
proc swap_cell_to_lvt {cell} {
    set ref_name [get_attribute $cell ref_name]
    set library_name "CORE65LPLVT"
    regsub {_LH} $ref_name "_LL" new_ref_name
    size_cell $cell "${library_name}/${new_ref_name}"
}

# Procedure to sort cells by power
proc sort_cells_by_power {list_cells} {
    set sorted_cells ""
    set sorted_cells [lsort -real -increasing -index 1 $list_cells]     ;# Sort cells based on power (index 1)
    return $sorted_cells
}

# Procedure to determine the list of LVT cells to swap
proc list_to_swap {lvt_sorted} {
    set num_cells [sizeof_collection [get_cells]]           ;# Get the total number of cells in the design
    set number_cell 0                                       ;# Initialize the cell counter
    set cells_to_not_change [expr $num_cells * 80 / 100]    ;# Calculate the number of cells to not change (80% of total)

    foreach cell $lvt_sorted {
        set cell_name [lindex $cell 0 0]
        if {$number_cell > $cells_to_not_change } {
            lappend lvt_to_swap "$cell_name"                ;# Add the cell name to the list of cells to swap
        }
        incr number_cell
    }
    return $lvt_to_swap
}

# Procedure to generate a list of HVT cells
proc list_hvt {} {
    set hvt_cells [get_cells -filter "lib_cell.threshold_voltage_group == HVT"]

    foreach_in_collection cell $hvt_cells {
        set cell_name [get_attribute $cell full_name]
        set cell_power [get_attribute $cell leakage_power]  ;# Get the leakage power of the cell
        lappend list_cells "$cell_name $cell_power"         ;# Add cell name and power to the list
    }
    return $list_cells
}

# Procedure to generate a filtered and sorted list of LVT cells by slack
proc fitered_and_sorted_by_slack {} {   
    set lvt_cells [get_cells -filter "lib_cell.threshold_voltage_group == LVT"]
    set lvt_sorted ""

    foreach_in_collection cell $lvt_cells {
        set cell_path [get_timing_paths -through $cell]
        set cell_slack [get_attribute $cell_path slack]
        set cell_name [get_attribute $cell full_name]
        lappend lvt_sorted "$cell_name $cell_slack"
    }
    set lvt_sorted [lsort -real -increasing -index 1 $lvt_sorted]
    return $lvt_sorted
}

proc check_contest_constraints {slackThreshold maxFanoutEndpointCost} {
    update_timing -full
    # Check Slack
    set msc_slack [get_attribute [get_timing_paths] slack]
    if {$msc_slack < 0} {
        return 0
    }
    # Check Fanout Endpoint Cost
    foreach_in_collection cell [get_cells] {
        set paths [get_timing_paths -through $cell -nworst 1 -max_paths 10000 -slack_lesser_than $slackThreshold]
        set cell_fanout_endpoint_cost 0.0
        foreach_in_collection path $paths {
            set this_cost [expr $slackThreshold - [get_attribute $path slack]]
            set cell_fanout_endpoint_cost [expr $cell_fanout_endpoint_cost + $this_cost]
        }
        if {$cell_fanout_endpoint_cost >= $maxFanoutEndpointCost} {
            puts "FCE Violated: $cell_fanout_endpoint_cost"
            set cell_name [get_attribute $cell full_name]
            set cell_ref_name [get_attribute $cell ref_name]
            return 0
        }
    }
    return 1
}

# Main procedure for dual Vth optimization
proc dualVth {slackThreshold maxFanoutEndpointCost} {
    set lvt_sorted [fitered_and_sorted_by_slack]        ;# Get sorted list of LVT cells by slack
    set lvt_to_swap [list_to_swap $lvt_sorted]          ;# Get list of LVT cells to swap to HVT
    swap_some_cells_to_hvt $lvt_to_swap                 ;# Swap the previous LVT list to HVT

    # WHILE TIMING CONSTRAINTS ARE NOT MET
    while {[check_contest_constraints $slackThreshold $maxFanoutEndpointCost] == 0} {
        set list_cells [list_hvt]                       ;# Get list of HVT cells

        # SORT CELLS BY LEAKAGE POWER  
        set sorted_cells [sort_cells_by_power $list_cells]

        # FIRST CELL FROM HVT TO LVT
        set cell_name [lindex $sorted_cells 0 0]

        # SWAP the cell to LVT
        swap_cell_to_lvt [get_cells $cell_name]

        # SECOND CELL FROM HVT TO LVT
        set cell_name [lindex $sorted_cells 1 0]
        
        # SWAP the cell to LVT
        swap_cell_to_lvt [get_cells $cell_name]
    }
    return 1
}