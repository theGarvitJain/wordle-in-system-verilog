create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1" }  [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list \
  CONFIG.PSU__FPGA_PL1_ENABLE {0} \
  CONFIG.PSU__USE__M_AXI_GP1 {0} \
] [get_bd_cells zynq_ultra_ps_e_0]


create_bd_cell -type ip -vlnv UWATERLOO.CA:user:wordle_top:1.0 wordle_top_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_2
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_3
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_4
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_5
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_6

set_property name ref_word_idx [get_bd_cells axi_gpio_0]
set_property -dict [list \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_GPIO_WIDTH {10} \
] [get_bd_cells ref_word_idx]
set_property name guess_word [get_bd_cells axi_gpio_1]
set_property CONFIG.C_ALL_OUTPUTS {1} [get_bd_cells guess_word]
set_property name guess_id [get_bd_cells axi_gpio_2]
set_property -dict [list \
  CONFIG.C_ALL_OUTPUTS {1} \
  CONFIG.C_GPIO_WIDTH {4} \
] [get_bd_cells guess_id]
set_property name ready [get_bd_cells axi_gpio_3]
set_property -dict [list \
  CONFIG.C_ALL_INPUTS {1} \
  CONFIG.C_GPIO_WIDTH {1} \
] [get_bd_cells ready]
set_property name result [get_bd_cells axi_gpio_4]
set_property -dict [list \
  CONFIG.C_ALL_INPUTS {1} \
  CONFIG.C_GPIO_WIDTH {8} \
] [get_bd_cells result]
set_property name guess_count [get_bd_cells axi_gpio_5]
set_property -dict [list \
  CONFIG.C_ALL_INPUTS {1} \
  CONFIG.C_GPIO_WIDTH {4} \
] [get_bd_cells guess_count]
set_property name game_status [get_bd_cells axi_gpio_6]
set_property -dict [list \
  CONFIG.C_ALL_INPUTS {1} \
  CONFIG.C_GPIO_WIDTH {2} \
] [get_bd_cells game_status]

connect_bd_net [get_bd_pins ref_word_idx/gpio_io_o] [get_bd_pins wordle_top_0/i_ref_word_idx]
connect_bd_net [get_bd_pins guess_word/gpio_io_o] [get_bd_pins wordle_top_0/i_guess_word]
connect_bd_net [get_bd_pins guess_id/gpio_io_o] [get_bd_pins wordle_top_0/i_guess_id]
connect_bd_net [get_bd_pins ready/gpio_io_i] [get_bd_pins wordle_top_0/o_ready]
connect_bd_net [get_bd_pins result/gpio_io_i] [get_bd_pins wordle_top_0/o_result]
connect_bd_net [get_bd_pins guess_count/gpio_io_i] [get_bd_pins wordle_top_0/o_guess_count]
connect_bd_net [get_bd_pins game_status/gpio_io_i] [get_bd_pins wordle_top_0/o_game_status]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/game_status/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins game_status/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/guess_count/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins guess_count/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/guess_id/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins guess_id/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/guess_word/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins guess_word/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/ready/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins ready/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/ref_word_idx/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins ref_word_idx/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} Slave {/result/S_AXI} ddr_seg {Auto} intc_ip {New AXI SmartConnect} master_apm {0}}  [get_bd_intf_pins result/S_AXI]
apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { Clk {/zynq_ultra_ps_e_0/pl_clk0 (99 MHz)} Freq {99} Ref_Clk0 {} Ref_Clk1 {} Ref_Clk2 {}}  [get_bd_pins wordle_top_0/clk]

regenerate_bd_layout
validate_bd_design
save_bd_design