# UART Core in Verilog

A complete UART core built step by step in Verilog.
Tested using JDoodle online Verilog compiler.

## Modules
- Baud rate generator
- UART Transmitter TX
- UART Receiver RX
- Configuration register (32-bit)
- FIFO buffer

## Test Results
All tests passed:
- TX sent 0x41 (A) correctly
- RX received 0x41 (A) correctly
- Loopback test: UART spelled correctly
- FIFO: 4 passed 0 failed
- Final integration: ALL TESTS PASSED

## How to simulate
1. Go to jdoodle.com
2. Select Verilog language
3. Paste code from uart_core.v
4. Click Execute

## Author
Built as a Verilog learning project
