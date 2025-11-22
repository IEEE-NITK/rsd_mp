// Stub XilinxMacros.vh for functional simulation
// This file provides minimal definitions needed for functional simulation
// without requiring the full Xilinx synthesis macros

// AXI4 bus parameters for RSD (stub values for functional simulation)
`ifndef MEMORY_AXI4_BASE_ADDR
`define MEMORY_AXI4_BASE_ADDR 32'h10000000
`endif

`ifndef MEMORY_AXI4_DATA_BIT_NUM
`define MEMORY_AXI4_DATA_BIT_NUM 64
`endif

// Maximum outstanding read/write process IDs
// These match CacheSystemTypes::MEM_ACCESS_SERIAL_BIT_SIZE
`ifndef MEMORY_AXI4_READ_ID_WIDTH
`define MEMORY_AXI4_READ_ID_WIDTH 2
`endif

`ifndef MEMORY_AXI4_READ_ID_NUM
`define MEMORY_AXI4_READ_ID_NUM (1<<`MEMORY_AXI4_READ_ID_WIDTH)
`endif

`ifndef MEMORY_AXI4_WRITE_ID_WIDTH
`define MEMORY_AXI4_WRITE_ID_WIDTH 1
`endif

`ifndef MEMORY_AXI4_WRITE_ID_NUM
`define MEMORY_AXI4_WRITE_ID_NUM (1<<`MEMORY_AXI4_WRITE_ID_WIDTH)
`endif

`ifndef MEMORY_AXI4_ADDR_BIT_SIZE
`define MEMORY_AXI4_ADDR_BIT_SIZE 32
`endif

// AXI4 user bus widths (not used)
`ifndef MEMORY_AXI4_AWUSER_WIDTH
`define MEMORY_AXI4_AWUSER_WIDTH 0
`endif

`ifndef MEMORY_AXI4_ARUSER_WIDTH
`define MEMORY_AXI4_ARUSER_WIDTH 0
`endif

`ifndef MEMORY_AXI4_WUSER_WIDTH
`define MEMORY_AXI4_WUSER_WIDTH 0
`endif

`ifndef MEMORY_AXI4_RUSER_WIDTH
`define MEMORY_AXI4_RUSER_WIDTH 0
`endif

`ifndef MEMORY_AXI4_BUSER_WIDTH
`define MEMORY_AXI4_BUSER_WIDTH 0
`endif

// PS-PL Control Register parameters (stub values)
`ifndef PS_PL_CTRL_REG_ADDR_BIT_SIZE
`define PS_PL_CTRL_REG_ADDR_BIT_SIZE 4
`endif

`ifndef PS_PL_CTRL_REG_DATA_BIT_SIZE
`define PS_PL_CTRL_REG_DATA_BIT_SIZE 32
`endif

`ifndef PS_PL_CTRL_REG_SIZE
`define PS_PL_CTRL_REG_SIZE 16
`endif

`ifndef PS_PL_CTRL_REG_ADDR_LSB
`define PS_PL_CTRL_REG_ADDR_LSB 2
`endif

`ifndef PS_PL_CTRL_REG_AWPROT_WIDTH
`define PS_PL_CTRL_REG_AWPROT_WIDTH 3
`endif

`ifndef PS_PL_CTRL_REG_ARPROT_WIDTH
`define PS_PL_CTRL_REG_ARPROT_WIDTH 3
`endif

`ifndef PS_PL_CTRL_REG_WSTRB_WIDTH
`define PS_PL_CTRL_REG_WSTRB_WIDTH 4
`endif

`ifndef PS_PL_CTRL_REG_BRESP_WIDTH
`define PS_PL_CTRL_REG_BRESP_WIDTH 2
`endif

`ifndef PS_PL_CTRL_REG_RRESP_WIDTH
`define PS_PL_CTRL_REG_RRESP_WIDTH 2
`endif

// PS-PL Control Queue parameters (stub values)
`ifndef PS_PL_CTRL_QUEUE_DATA_BIT_SIZE
`define PS_PL_CTRL_QUEUE_DATA_BIT_SIZE 32
`endif

`ifndef PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE
`define PS_PL_CTRL_QUEUE_ADDR_BIT_SIZE 4
`endif

`ifndef PS_PL_CTRL_QUEUE_SIZE
`define PS_PL_CTRL_QUEUE_SIZE 16
`endif

// Stub macros for AXI4 interface expansion (not used in functional sim)
`ifndef EXPAND_AXI4MEMORY_PORT
`define EXPAND_AXI4MEMORY_PORT
`endif

`ifndef EXPAND_CONTROL_REGISTER_PORT
`define EXPAND_CONTROL_REGISTER_PORT
`endif

`ifndef CONNECT_AXI4MEMORY_IF
`define CONNECT_AXI4MEMORY_IF
`endif

`ifndef CONNECT_CONTROL_REGISTER_IF
`define CONNECT_CONTROL_REGISTER_IF
`endif

