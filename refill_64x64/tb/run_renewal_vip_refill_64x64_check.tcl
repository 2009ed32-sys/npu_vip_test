# 64x64 refill MACLane verification flow:
# 1. Generate the independent Python answer file.
# 2. Build a clean Vivado/XSim project from the repository sources.
# 3. Run the AXI VIP test until the DUT finishes all four data chunks.
# 4. Save each accepted MACLane tag/data/weight packet.
# 5. Compare all expected and actual packets line by line.

set script_dir [file dirname [file normalize [info script]]]
set scenario_dir [file dirname $script_dir]
set repo_dir [file dirname $scenario_dir]
set project_dir [file join $repo_dir .vivado refill_64x64]
set project_name npu_vip_refill_64x64
set generator_path [file join $script_dir generate_renewal_vip_refill_64x64_expected.py]
set expected_path [file join $script_dir renewal_maclane_refill_64x64_expected.txt]
set actual_path [file join $project_dir ${project_name}.sim sim_1 behav xsim renewal_maclane_refill_64x64_actual.txt]

proc find_python {} {
    if {[info exists ::env(RENEWAL_PYTHON)] &&
        [file exists $::env(RENEWAL_PYTHON)]} {
        return [file normalize $::env(RENEWAL_PYTHON)]
    }

    if {[info exists ::env(LOCALAPPDATA)]} {
        set candidates [lsort -dictionary [glob -nocomplain \
            [file join $::env(LOCALAPPDATA) Programs Python "Python*" python.exe]]]
        if {[llength $candidates] > 0} {
            return [lindex $candidates end]
        }
    }

    set command [auto_execok python]
    if {$command ne ""} {
        return [lindex $command 0]
    }

    error "Python was not found. Set RENEWAL_PYTHON to python.exe."
}

proc read_nonempty_lines {path} {
    set fp [open $path r]
    set contents [read $fp]
    close $fp

    set lines {}
    foreach line [split $contents "\n"] {
        set normalized [string tolower [string trim $line]]
        if {$normalized ne ""} {
            lappend lines $normalized
        }
    }
    return $lines
}

foreach variable_name {PYTHONHOME PYTHONPATH} {
    if {[info exists ::env($variable_name)]} {
        unset ::env($variable_name)
    }
}

set python_path [find_python]
puts "Generating independent 64x64 refill MACLane answer file..."
puts [exec $python_path $generator_path 2>@1]

if {![file exists $expected_path]} {
    error "Python did not create the expected file: $expected_path"
}

file delete -force $project_dir
create_project -force $project_name $project_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Keep the original repository RTL and replace only the files needed by refill64.
set override_names {CSB.sv CDMA_data_load.sv CSC.sv renewal.sv}
set rtl_files {}
foreach rtl_file [glob -directory [file join $repo_dir rtl] *.sv] {
    if {[lsearch -exact $override_names [file tail $rtl_file]] < 0} {
        lappend rtl_files $rtl_file
    }
}
foreach rtl_file [glob -directory [file join $scenario_dir rtl] *.sv] {
    lappend rtl_files $rtl_file
}
add_files -norecurse $rtl_files

set ip_files {}
foreach ip_dir [glob -types d -directory [file join $repo_dir vivado ip] *] {
    foreach xci [glob -nocomplain -directory $ip_dir *.xci] {
        lappend ip_files $xci
    }
}
import_ip -files $ip_files
generate_target all [get_ips]

add_files -fileset sim_1 -norecurse [list \
    [file join $repo_dir tb renewal_vip_wrapper.sv] \
    [file join $script_dir renewal_vip_refill_64x64_TB.sv]]
set_property top renewal_vip_refill_64x64_TB [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

file delete -force $actual_path
puts "Running renewal_vip_refill_64x64_TB..."
launch_simulation
run all
close_sim

if {![file exists $actual_path]} {
    close_project
    error "Simulation did not create: $actual_path"
}

set expected_lines [read_nonempty_lines $expected_path]
set actual_lines [read_nonempty_lines $actual_path]

if {[llength $expected_lines] != [llength $actual_lines]} {
    close_project
    error [format "MACLane entry count mismatch: expected=%d actual=%d" \
        [llength $expected_lines] [llength $actual_lines]]
}

for {set index 0} {$index < [llength $expected_lines]} {incr index} {
    set expected [lindex $expected_lines $index]
    set actual [lindex $actual_lines $index]
    if {$expected ne $actual} {
        puts stderr "MACLane comparison FAILED at entry $index"
        puts stderr "  expected: $expected"
        puts stderr "  actual  : $actual"
        close_project
        error "MACLane answer-file comparison failed"
    }
}

puts [format "MACLane refill64 comparison PASSED: %d/%d entries matched" \
    [llength $actual_lines] [llength $expected_lines]]
puts "Expected: $expected_path"
puts "Actual  : $actual_path"
close_project
