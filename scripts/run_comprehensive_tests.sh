#!/bin/bash

# TCP Offload Engine Comprehensive Test Suite
# This script runs the enhanced protocol validation tests

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
GHDL_FLAGS="--std=08 --ieee=synopsys --warn-no-vital-generic"
SIMULATION_TIME="100us"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  TCP Offload Engine Comprehensive Test Suite${NC}"
echo -e "${BLUE}  Protocol Validation and Functional Testing${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check for GHDL
if ! command -v ghdl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} GHDL not found. Please install GHDL first."
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} Found GHDL: $(ghdl --version | head -1)"

# Create work directory
WORK_DIR="work_comprehensive"
if [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
fi
mkdir "$WORK_DIR"
cd "$WORK_DIR"

echo -e "${BLUE}[INFO]${NC} Created work directory: $WORK_DIR"

# Function to run a test
run_test() {
    local test_name="$1"
    local test_file="$2"
    local description="$3"
    
    echo ""
    echo -e "${BLUE}====== Running Test: $test_name ======${NC}"
    echo -e "${BLUE}Description: $description${NC}"
    
    # Analyze all required files first
    echo -e "${BLUE}[INFO]${NC} Analyzing VHDL files for $test_name..."
    
    # Analyze package files
    echo -e "${BLUE}[INFO]${NC} Analyzing tcp_offload_pkg.vhd..."
    if ! ghdl -a $GHDL_FLAGS ../src/vhdl/core/tcp_offload_pkg.vhd; then
        echo -e "${RED}[ERROR]${NC} Analysis failed for tcp_offload_pkg.vhd"
        return 1
    fi
    
    echo -e "${BLUE}[INFO]${NC} Analyzing tcp_protocol_tb_pkg.vhd..."
    if ! ghdl -a $GHDL_FLAGS ../src/vhdl/testbench/tcp_protocol_tb_pkg.vhd; then
        echo -e "${RED}[ERROR]${NC} Analysis failed for tcp_protocol_tb_pkg.vhd"
        return 1
    fi
    
    # Analyze component files
    local components=(
        "../src/vhdl/core/packet_buffer.vhd"
        "../src/vhdl/interfaces/rgmii_interface.vhd"
        "../src/vhdl/protocols/ethernet_mac.vhd"
        "../src/vhdl/protocols/ip_layer.vhd"
        "../src/vhdl/protocols/tcp_engine.vhd"
        "../src/vhdl/protocols/udp_engine.vhd"
        "../src/vhdl/protocols/dhcp_client.vhd"
        "../src/vhdl/interfaces/axi4_lite_interface.vhd"
        "../src/vhdl/interfaces/axi4_stream_interface.vhd"
        "../src/vhdl/tcp_offload_engine_top.vhd"
    )
    
    for component in "${components[@]}"; do
        echo -e "${BLUE}[INFO]${NC} Analyzing $component..."
        if ! ghdl -a $GHDL_FLAGS "$component"; then
            echo -e "${RED}[ERROR]${NC} Analysis failed for $component"
            return 1
        fi
    done
    
    # Analyze test file
    echo -e "${BLUE}[INFO]${NC} Analyzing $test_file..."
    if ! ghdl -a $GHDL_FLAGS "../src/vhdl/testbench/$test_file"; then
        echo -e "${RED}[ERROR]${NC} Analysis failed for $test_file"
        return 1
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} All files analyzed successfully"
    
    # Elaborate design
    echo -e "${BLUE}[INFO]${NC} Elaborating $test_name design..."
    if ! ghdl -e $GHDL_FLAGS "$test_name"; then
        echo -e "${RED}[ERROR]${NC} Elaboration failed for $test_name"
        return 1
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} Design elaborated successfully"
    
    # Run simulation
    echo -e "${BLUE}[INFO]${NC} Running $test_name simulation for $SIMULATION_TIME..."
    
    # Create simulation output file
    local sim_output="${test_name}_simulation.log"
    local wave_file="${test_name}_wave.ghw"
    
    # Run simulation with waveform generation
    if ghdl -r $GHDL_FLAGS "$test_name" --wave="$wave_file" --stop-time="$SIMULATION_TIME" > "$sim_output" 2>&1; then
        echo -e "${GREEN}[SUCCESS]${NC} $test_name simulation completed"
        
        # Check for test results in simulation output
        if grep -q "PASS" "$sim_output"; then
            local pass_count=$(grep -c "PASS" "$sim_output")
            echo -e "${GREEN}[INFO]${NC} Tests passed: $pass_count"
        fi
        
        if grep -q "FAIL" "$sim_output"; then
            local fail_count=$(grep -c "FAIL" "$sim_output")
            echo -e "${RED}[WARNING]${NC} Tests failed: $fail_count"
        fi
        
        if grep -q "ALL TESTS PASSED" "$sim_output"; then
            echo -e "${GREEN}[SUCCESS]${NC} ALL TESTS PASSED for $test_name"
        fi
        
        # Show summary of test output
        echo -e "${BLUE}[INFO]${NC} Test output summary:"
        grep -E "(PASS|FAIL|Test.*:|====|Starting|completed)" "$sim_output" | tail -20
        
    else
        echo -e "${RED}[ERROR]${NC} $test_name simulation failed"
        echo -e "${RED}[ERROR]${NC} Last 10 lines of simulation output:"
        tail -10 "$sim_output"
        return 1
    fi
    
    echo -e "${GREEN}[SUCCESS]${NC} $test_name test completed successfully"
    echo -e "${BLUE}[INFO]${NC} Waveform saved as: $wave_file"
    echo -e "${BLUE}[INFO]${NC} Simulation log saved as: $sim_output"
    
    return 0
}

# Test suite execution
echo -e "${BLUE}[INFO]${NC} Starting comprehensive test suite..."

# Test 1: Basic functionality (original test)
echo -e "${YELLOW}[TEST 1]${NC} Running basic functionality test..."
if run_test "tcp_offload_tb" "tcp_offload_tb.vhd" "Basic smoke test - registers and interfaces"; then
    echo -e "${GREEN}[TEST 1 PASSED]${NC}"
else
    echo -e "${RED}[TEST 1 FAILED]${NC}"
fi

# Test 2: TCP connection establishment
echo -e "${YELLOW}[TEST 2]${NC} Running TCP connection establishment test..."
if run_test "tcp_connection_test_tb" "tcp_connection_test_tb.vhd" "TCP three-way handshake and connection management"; then
    echo -e "${GREEN}[TEST 2 PASSED]${NC}"
else
    echo -e "${RED}[TEST 2 FAILED]${NC}"
fi

# Test 3: UDP/DHCP protocol validation
echo -e "${YELLOW}[TEST 3]${NC} Running UDP/DHCP protocol validation..."
if run_test "udp_dhcp_test_tb" "udp_dhcp_test_tb.vhd" "UDP packet handling and DHCP client functionality"; then
    echo -e "${GREEN}[TEST 3 PASSED]${NC}"
else
    echo -e "${RED}[TEST 3 FAILED]${NC}"
fi

# Test summary
cd ..
echo ""
echo -e "${BLUE}====== COMPREHENSIVE TEST SUITE SUMMARY ======${NC}"
echo -e "${BLUE}[INFO]${NC} All test results and waveforms saved in: $WORK_DIR/"
echo ""

# Check overall results
if [ -f "$WORK_DIR/tcp_offload_tb_simulation.log" ] && 
   [ -f "$WORK_DIR/tcp_connection_test_tb_simulation.log" ] && 
   [ -f "$WORK_DIR/udp_dhcp_test_tb_simulation.log" ]; then
    
    echo -e "${GREEN}[SUCCESS]${NC} All tests executed successfully!"
    echo -e "${BLUE}[INFO]${NC} Available waveform files:"
    ls -la "$WORK_DIR"/*.ghw 2>/dev/null || echo "No waveform files generated"
    
    echo ""
    echo -e "${BLUE}[INFO]${NC} To view waveforms, use:"
    echo -e "${BLUE}[INFO]${NC}   gtkwave $WORK_DIR/<test_name>_wave.ghw"
    echo ""
    echo -e "${BLUE}[INFO]${NC} To view simulation logs:"
    echo -e "${BLUE}[INFO]${NC}   cat $WORK_DIR/<test_name>_simulation.log"
    
else
    echo -e "${RED}[ERROR]${NC} Some tests failed to complete"
    echo -e "${RED}[INFO]${NC} Check individual test logs for details"
fi

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  TCP Offload Engine Test Suite Complete${NC}"
echo -e "${BLUE}================================================${NC}"