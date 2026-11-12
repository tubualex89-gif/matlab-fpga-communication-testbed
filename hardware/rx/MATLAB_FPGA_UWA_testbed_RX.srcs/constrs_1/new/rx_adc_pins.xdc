# AN9238 ADC pin assignments, copied from the user's working openofdm RX design.
# Assumes the SAME PYNQ-Z2 expansion connector, cable and ADC channel wiring.
# Top-level BD external port names must be adc_clk and adc_data_raw[11:0].
# Clock is FPGA -> ADC; data is ADC -> FPGA. Verify wiring before use.

set_property PACKAGE_PIN Y18 [get_ports adc_clk]
set_property IOSTANDARD LVCMOS33 [get_ports adc_clk]

set_property PACKAGE_PIN Y19 [get_ports {adc_data_raw[0]}]
set_property PACKAGE_PIN Y16 [get_ports {adc_data_raw[1]}]
set_property PACKAGE_PIN Y17 [get_ports {adc_data_raw[2]}]
set_property PACKAGE_PIN U18 [get_ports {adc_data_raw[3]}]
set_property PACKAGE_PIN U19 [get_ports {adc_data_raw[4]}]
set_property PACKAGE_PIN W18 [get_ports {adc_data_raw[5]}]
set_property PACKAGE_PIN W19 [get_ports {adc_data_raw[6]}]
set_property PACKAGE_PIN W14 [get_ports {adc_data_raw[7]}]
set_property PACKAGE_PIN Y14 [get_ports {adc_data_raw[8]}]
set_property PACKAGE_PIN T11 [get_ports {adc_data_raw[9]}]
set_property PACKAGE_PIN T10 [get_ports {adc_data_raw[10]}]
set_property PACKAGE_PIN V16 [get_ports {adc_data_raw[11]}]
set_property IOSTANDARD LVCMOS33 [get_ports {adc_data_raw[*]}]

# Timing deliberately not specified here: the BD is still empty and its
# hierarchy, actual PS 100 MHz clock, ADC-clock output path and PCB delays are
# not known. After integration, use a correctly phased generated clock on the
# adc_clk output and set both min/max input delays relative to that clock,
# accounting for ADC output delay and board clock/data flight times.
# The ADC is sampled in the clk_100m domain; do not declare the ADC and PS
# clocks asynchronous simply because adc_clk is an output.
# The reference project's clk_640kHz path, 1/5 ns delays and button/LED/125 MHz
# port constraints apply to its own design and are intentionally not copied.
# AN9238 OTR is not yet a top-level port; no OTR pin has been assigned.
