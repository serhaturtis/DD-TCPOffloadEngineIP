#!/bin/bash

# TCP Offload Engine Build Script
# Compiles all VHDL files in correct dependency order

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GHDL_FLAGS="--std=08 --ieee=synopsys --warn-no-vital-generic"
WORK_DIR="work"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  TCP Offload Engine Build Script${NC}"
echo -e "${BLUE}================================================${NC}"

# Check for GHDL
if ! command -v ghdl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} GHDL not found. Please install GHDL first."
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} Found GHDL: $(ghdl --version | head -1)"

# Create work directory
if [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
fi
mkdir "$WORK_DIR"
cd "$WORK_DIR"

echo -e "${BLUE}[INFO]${NC} Created work directory: $WORK_DIR"

# Function to compile a VHDL file
compile_vhdl() {
    local file="$1"
    local description="$2"
    
    echo -e "${BLUE}[INFO]${NC} Compiling $description: $(basename $file)"
    if ! ghdl -a $GHDL_FLAGS "$file"; then
        echo -e "${RED}[ERROR]${NC} Compilation failed for $file"
        return 1
    fi
    return 0
}

# Compile in dependency order
echo -e "${BLUE}[INFO]${NC} Starting compilation..."

# 1. Package files (must be first)
compile_vhdl "../src/vhdl/core/tcp_offload_pkg.vhd" "Core package" || exit 1

# 2. Core components
compile_vhdl "../src/vhdl/core/packet_buffer.vhd" "Packet buffer" || exit 1

# 3. Interface modules
compile_vhdl "../src/vhdl/interfaces/rgmii_interface.vhd" "RGMII interface" || exit 1
compile_vhdl "../src/vhdl/interfaces/axi4_lite_interface.vhd" "AXI4-Lite interface" || exit 1
compile_vhdl "../src/vhdl/interfaces/axi4_stream_interface.vhd" "AXI4-Stream interface" || exit 1

# 4. Protocol implementations
compile_vhdl "../src/vhdl/protocols/ethernet_mac.vhd" "Ethernet MAC" || exit 1
compile_vhdl "../src/vhdl/protocols/ip_layer.vhd" "IP layer" || exit 1
compile_vhdl "../src/vhdl/protocols/tcp_engine.vhd" "TCP engine" || exit 1
compile_vhdl "../src/vhdl/protocols/udp_engine.vhd" "UDP engine" || exit 1
compile_vhdl "../src/vhdl/protocols/dhcp_client.vhd" "DHCP client" || exit 1

# 5. Top-level integration
compile_vhdl "../src/vhdl/tcp_offload_engine_top.vhd" "Top-level integration" || exit 1

echo -e "${GREEN}[SUCCESS]${NC} All source files compiled successfully!"

# 6. Test infrastructure (optional)
echo -e "${BLUE}[INFO]${NC} Compiling test infrastructure..."
compile_vhdl "../src/vhdl/testbench/tcp_protocol_tb_pkg.vhd" "Test package" || exit 1
compile_vhdl "../src/vhdl/testbench/tcp_offload_tb.vhd" "Basic testbench" || exit 1
compile_vhdl "../src/vhdl/testbench/packet_gen_test_tb.vhd" "Packet generation test" || exit 1

echo -e "${GREEN}[SUCCESS]${NC} Test infrastructure compiled successfully!"

# Build summary
echo ""
echo -e "${BLUE}====== BUILD SUMMARY ======${NC}"
echo -e "${GREEN}[SUCCESS]${NC} TCP Offload Engine build completed successfully!"
echo -e "${BLUE}[INFO]${NC} All VHDL files compiled without errors"
echo -e "${BLUE}[INFO]${NC} Work directory: $WORK_DIR"
echo ""
echo -e "${BLUE}[INFO]${NC} Next steps:"
echo -e "${BLUE}[INFO]${NC}   Run tests: ../scripts/run_tests.sh"
echo -e "${BLUE}[INFO]${NC}   Elaborate design: ghdl -e $GHDL_FLAGS tcp_offload_engine_top"
echo -e "${BLUE}[INFO]${NC}   Run simulation: ghdl -r $GHDL_FLAGS <testbench_name>"

cd ..
echo -e "${BLUE}================================================${NC}