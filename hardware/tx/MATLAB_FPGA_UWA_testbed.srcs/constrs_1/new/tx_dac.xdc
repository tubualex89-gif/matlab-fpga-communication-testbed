# DAC pin mapping adapted from openofdm tx_dac.xdc.
# Requires Testbed_tx_wrapper as top, with ports DAC[13:0] and dac_clk.
# Verify that the current board and DAC wiring match the reference hardware.
set_property PACKAGE_PIN Y18 [get_ports {DAC[0]}]
set_property PACKAGE_PIN Y19 [get_ports {DAC[1]}]
set_property PACKAGE_PIN Y16 [get_ports {DAC[2]}]
set_property PACKAGE_PIN Y17 [get_ports {DAC[3]}]
set_property PACKAGE_PIN U18 [get_ports {DAC[4]}]
set_property PACKAGE_PIN U19 [get_ports {DAC[5]}]
set_property PACKAGE_PIN W18 [get_ports {DAC[6]}]
set_property PACKAGE_PIN W19 [get_ports {DAC[7]}]
set_property PACKAGE_PIN W14 [get_ports {DAC[8]}]
set_property PACKAGE_PIN Y14 [get_ports {DAC[9]}]
set_property PACKAGE_PIN T11 [get_ports {DAC[10]}]
set_property PACKAGE_PIN T10 [get_ports {DAC[11]}]
set_property PACKAGE_PIN V16 [get_ports {DAC[12]}]
set_property PACKAGE_PIN W16 [get_ports {DAC[13]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DAC[*]}]
set_property DRIVE 4 [get_ports {DAC[*]}]
set_property SLEW SLOW [get_ports {DAC[*]}]

# Reference main output clk_640kHz uses V12; verify DAC clock wiring.
set_property PACKAGE_PIN V12 [get_ports {dac_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_clk}]
# Second output matches the W13 clock-copy pin used by the working reference.
set_property PACKAGE_PIN W13 [get_ports {dac_wrt}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_wrt}]

# No output delays or generated-clock constraints have been inferred.
# Define and verify those using the DAC datasheet, PCB clock/data delays,
# the actual PS FCLK source and the synthesized divider clock topology.
# Do not copy unrelated asynchronous clock groups or debug constraints.
