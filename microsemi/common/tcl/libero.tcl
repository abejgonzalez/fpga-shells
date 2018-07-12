#==============================================================================
# Build a Libero project from Chisel generated Verilog and the Libero TCL
# scriplets generated by each IP block FPGA-Shell.
#==============================================================================

######### Script arguments #########

if {$argc != 5} {
	puts "!!! ERROR !!!: This script takes 5 arguments from the Chisel build environment: BUILD_DIR MODEL PROJECT CONFIG BOARD" 
	exit
}

puts "*****************************************************************"
puts "******************** Building Libero project ********************"
puts "*****************************************************************"

set chisel_build_dir [lindex $argv 0]
set chisel_model [lindex $argv 1]
set chisel_project [lindex $argv 2]
set chisel_config [lindex $argv 3]
set chisel_board  [lindex $argv 4]

puts "Number of arguments: $argc"
puts "Chisel build directory: $chisel_build_dir"
puts "Chisel model: $chisel_model"
puts "Chisel project: $chisel_project"
puts "Chisel config: $chisel_config"
puts "Chisel board: $chisel_board"

set Prjname "$chisel_model"
set Proj "./Libero/$Prjname"

set FPExpressDir "$chisel_build_dir/FlashProExpress"
puts "FlashPro Express folder: $FPExpressDir"
file mkdir $FPExpressDir

set scriptdir [file dirname [info script]]
set commondir [file dirname $scriptdir]
set boarddir [file join [ file dirname $commondir] $chisel_board]

###########################################
set CoreJTAGDebugver {2.0.100}
set PF_DDR3ver {2.1.101}
set PF_DDR4ver {2.1.101}
set PF_CCCver {1.0.112}
set PF_INIT_MONITORver {2.0.101}
set PF_CORERESETPFver {2.0.112}
set PF_PCIEver {1.0.230}
set PF_XCVR_REF_CLKver {1.0.103}
set PF_TX_PLLver {1.0.109}

set use_enhanced_constraint_flow 1
set tb {testbench}
file delete -force "$Proj"
set rootcomp {Top_SD}
set rootcomp1 Top_SD
set TOP Top_SD

set SimTime 100us
set NUM_TX_PLL 1
set quad 1
set txpll_refclk_mode "ded"
set xcvrrefclk_refclk_mode "diff"

#########ORIGINAl SETTINGS#############

#Device Selection
source [file join $boarddir tcl board.tcl]

#Analysis operating conditions
set TEMPR {EXT}
set VOLTR {EXT}
set IOVOLTR_12 {EXT}
set IOVOLTR_15 {EXT}
set IOVOLTR_18 {EXT}
set IOVOLTR_25 {EXT}
set IOVOLTR_33 {EXT}

#Design Flow
set HDL {VERILOG}
set Block 0
set SAPI 0
set vmflow 1
set synth 1
set fanout {10}

#########ORIGINAl SETTINGS#############

new_project -ondemand_build_dh 1 -location "$Proj" -name "$Prjname" -project_description {} -block_mode $Block -standalone_peripheral_initialization $SAPI -use_enhanced_constraint_flow $use_enhanced_constraint_flow -hdl $HDL -family $family -die $die -package $package -speed $speed -die_voltage $die_voltage -part_range $part_range -adv_options IO_DEFT_STD:$IOTech -adv_options RESTRICTPROBEPINS:$ResProbe -adv_options RESTRICTSPIPINS:$ResSPI -adv_options TEMPR:$TEMPR -adv_options VCCI_1.2_VOLTR:$IOVOLTR_12 -adv_options VCCI_1.5_VOLTR:$IOVOLTR_15 -adv_options VCCI_1.8_VOLTR:$IOVOLTR_18 -adv_options VCCI_2.5_VOLTR:$IOVOLTR_25 -adv_options VCCI_3.3_VOLTR:$IOVOLTR_33 -adv_options VOLTR:$VOLTR 

#
# Import Chisel generated verilog files into Libero project
#
import_files \
         -convert_EDN_to_HDL 0 \
         -hdl_source "$chisel_build_dir/$chisel_project.$chisel_config.v" \
         -hdl_source "../../fpga-shells/xilinx/common/vsrc/PowerOnResetFPGAOnly.v" \
         -hdl_source "../../rocket-chip/src/main/resources/vsrc/AsyncResetReg.v" \
         -hdl_source "../../rocket-chip/src/main/resources/vsrc/plusarg_reader.v"

#
# Execute all design entry scripts generated from Chisel flow.
#
set tclfiles [glob -directory $chisel_build_dir *.tcl ]

foreach f $tclfiles {
    puts "---------- Executing Libero TCL script: $f ----------"
    source $f
}

#
# Build design hierarchy and set project root to design's top level
#
build_design_hierarchy         

set proj_root $chisel_model
append proj_root "::work"
puts "project root: $proj_root"
set_root -module $proj_root

#
# Import IO, Placement and timing constrainst
#
puts "-----------------------------------------------------------------"
puts "------------------ Applying design constraints ------------------"
puts "-----------------------------------------------------------------"

set sdc    $chisel_project.$chisel_config.shell.sdc
set io_pdc $chisel_project.$chisel_config.shell.io.pdc

import_files -fp_pdc [file join $boarddir constraints floor_plan.pdc]
import_files -io_pdc [file join $boarddir constraints pin_constraints.pdc]
import_files                    -io_pdc [file join $chisel_build_dir $io_pdc]
import_files -convert_EDN_to_HDL 0 -sdc [file join $chisel_build_dir $sdc]

organize_tool_files -tool {PLACEROUTE} \
         -file $Proj/constraint/fp/floor_plan.pdc \
         -file $Proj/constraint/io/pin_constraints.pdc \
         -file $Proj/constraint/io/$io_pdc \
         -file $Proj/constraint/$sdc \
         -module $proj_root -input_type {constraint} 

organize_tool_files -tool {VERIFYTIMING} \
         -file $Proj/constraint/$sdc \
         -module $proj_root -input_type {constraint} 
         
run_tool -name {CONSTRAINT_MANAGEMENT} 
derive_constraints_sdc

#
# Synthesis
#
puts "-----------------------------------------------------------------"
puts "--------------------------- Synthesis ---------------------------"
puts "-----------------------------------------------------------------"
run_tool -name {SYNTHESIZE}

#
# Place and route
#
puts "-----------------------------------------------------------------"
puts "------------------------ Place and Route ------------------------"
puts "-----------------------------------------------------------------"
configure_tool -name {PLACEROUTE} -params {EFFORT_LEVEL:true} -params {REPAIR_MIN_DELAY:true} -params {TDPR:true} 
run_tool -name {PLACEROUTE}

#
# Generate programming files
#
puts "-----------------------------------------------------------------"
puts "------------------ Generate programming files -------------------"
puts "-----------------------------------------------------------------"
run_tool -name {GENERATEPROGRAMMINGDATA} 

run_tool -name {GENERATEPROGRAMMINGFILE} 

export_prog_job \
    -job_file_name $chisel_model \
    -export_dir $FPExpressDir \
    -bitstream_file_type {TRUSTED_FACILITY} \
    -bitstream_file_components {}
