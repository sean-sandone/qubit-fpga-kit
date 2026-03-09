# KCU105: Bank 0 VCCO is 1.8V
#set_property CONFIG_VOLTAGE 1.8 [current_design]
#set_property CFGBVS GND         [current_design]

## 125 MHz clock (differential)
set_property PACKAGE_PIN G10 [get_ports clk_125mhz_p]
set_property PACKAGE_PIN F10 [get_ports clk_125mhz_n]
set_property IOSTANDARD LVDS [get_ports {clk_125mhz_p clk_125mhz_n}]
create_clock -name clk125 -period 8.000 [get_ports clk_125mhz_p]

# Bank  95 VCCO -          - IO_L2P_T0L_N2_FOE_B_65
set_property PACKAGE_PIN G25 [get_ports USB_UART_TX]
set_property IOSTANDARD LVCMOS18 [get_ports USB_UART_TX]
# Bank  95 VCCO -          - IO_L3P_T0L_N4_AD15P_A26_65
set_property PACKAGE_PIN K26 [get_ports USB_UART_RX]
set_property IOSTANDARD LVCMOS18 [get_ports USB_UART_RX]

## RESET
set_property PACKAGE_PIN AN8      [get_ports "CPU_RESET"] 
set_property IOSTANDARD  LVCMOS18 [get_ports "CPU_RESET"] 

## User LEDS
set_property PACKAGE_PIN AP8      [get_ports GPIO_LED_0_LS]
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_0_LS]
set_property PACKAGE_PIN H23      [get_ports GPIO_LED_1_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_1_LS] 
set_property PACKAGE_PIN P20      [get_ports GPIO_LED_2_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_2_LS] 
set_property PACKAGE_PIN P21      [get_ports GPIO_LED_3_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_3_LS] 
set_property PACKAGE_PIN N22      [get_ports GPIO_LED_4_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_4_LS] 
set_property PACKAGE_PIN M22      [get_ports GPIO_LED_5_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_5_LS] 
set_property PACKAGE_PIN R23      [get_ports GPIO_LED_6_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_6_LS] 
set_property PACKAGE_PIN P23      [get_ports GPIO_LED_7_LS] 
set_property IOSTANDARD  LVCMOS18 [get_ports GPIO_LED_7_LS] 

## UART RX is async 
set_false_path -from [get_ports USB_UART_TX]