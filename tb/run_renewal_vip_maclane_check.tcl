# MACLane 검증 흐름:
# 1. Python으로 정답을 생성한다.
# 2. Python 결과를 renewal_maclane_expected.txt에 저장한다.
# 3. Vivado/XSim으로 renewal_vip_TB를 실행한다.
# 4. TB의 MACLane 출력을 renewal_maclane_actual.txt에 저장한다.
# 5. Tcl이 expected 파일과 actual 파일을 한 줄씩 비교한다.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set project_dir [file join $repo_dir .vivado]
set generator_path [file join $script_dir generate_renewal_vip_expected.py]
set expected_path [file join $script_dir renewal_maclane_expected.txt]
set actual_path [file join $project_dir npu_vip_test.sim sim_1 behav xsim renewal_maclane_actual.txt]

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

# Step 1: Python 정답 생성기를 실행한다.
puts "Generating independent MACLane answer file..."
puts [exec $python_path $generator_path 2>@1]

# Step 2: Python이 renewal_maclane_expected.txt에 정답을 저장한다.
if {![file exists $expected_path]} {
    error "Python did not create the expected file: $expected_path"
}

# Step 3: Vivado/XSim 프로젝트를 생성하고 renewal_vip_TB를 실행한다.
file delete -force $project_dir
create_project -force npu_vip_test $project_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [glob -directory [file join $repo_dir rtl] *.sv]

set ip_files {}
foreach ip_dir [glob -types d -directory [file join $repo_dir vivado ip] *] {
    foreach xci [glob -nocomplain -directory $ip_dir *.xci] {
        lappend ip_files $xci
    }
}
import_ip -files $ip_files
generate_target all [get_ips]

add_files -fileset sim_1 -norecurse [list \
    [file join $script_dir renewal_vip_wrapper.sv] \
    [file join $script_dir renewal_vip_TB.sv]]
set_property top renewal_vip_TB [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

file delete -force $actual_path
puts "Running renewal_vip_TB..."
launch_simulation
run all
close_sim

# Step 4: TB가 기록한 renewal_maclane_actual.txt를 확인한다.
if {![file exists $actual_path]} {
    close_project
    error "Simulation did not create: $actual_path"
}

# Step 5: expected 파일과 actual 파일을 한 줄씩 비교한다.
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

puts [format "MACLane comparison PASSED: %d entries matched" \
    [llength $actual_lines]]
puts "Expected: $expected_path"
puts "Actual  : $actual_path"
close_project
