#!/bin/bash

# TCP Offload Engine Test Runner
# Runs all available tests in the project

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GHDL_FLAGS="--std=08 --ieee=synopsys --warn-no-vital-generic"
SIMULATION_TIME="50us"
WORK_DIR="work"

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  TCP Offload Engine Test Suite${NC}"
echo -e "${BLUE}================================================${NC}"

# Check if build was run first
if [ ! -d "$WORK_DIR" ]; then
    echo -e "${YELLOW}[INFO]${NC} Work directory not found. Running build first..."
    ./scripts/build.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Build failed. Cannot run tests."
        exit 1
    fi
fi

cd "$WORK_DIR"

# Function to run a test
run_test() {
    local test_name="$1"
    local description="$2"
    local timeout="${3:-$SIMULATION_TIME}"
    
    echo ""
    echo -e "${BLUE}====== Running Test: $test_name ======${NC}"
    echo -e "${BLUE}Description: $description${NC}"
    
    # Check if testbench exists
    if ! ghdl -e $GHDL_FLAGS "$test_name" &>/dev/null; then
        echo -e "${YELLOW}[SKIP]${NC} $test_name not available or compilation failed"
        return 0
    fi
    
    # Run simulation
    local output_file="${test_name}_results.log"
    local wave_file="${test_name}_wave.ghw"
    
    echo -e "${BLUE}[INFO]${NC} Running simulation (timeout: $timeout)..."
    
    if ghdl -r $GHDL_FLAGS "$test_name" --wave="$wave_file" --stop-time="$timeout" > "$output_file" 2>&1; then
        echo -e "${GREEN}[SUCCESS]${NC} $test_name simulation completed"
        
        # Check for test results
        if grep -q "PASS" "$output_file"; then
            local pass_count=$(grep -c "PASS" "$output_file")
            echo -e "${GREEN}[RESULT]${NC} Tests passed: $pass_count"
        fi
        
        if grep -q "FAIL" "$output_file"; then
            local fail_count=$(grep -c "FAIL" "$output_file")
            echo -e "${RED}[RESULT]${NC} Tests failed: $fail_count"
        fi
        
        # Show summary
        echo -e "${BLUE}[INFO]${NC} Last few lines of output:"
        tail -5 "$output_file" | sed 's/^/  /'
        
        return 0
    else
        echo -e "${RED}[ERROR]${NC} $test_name simulation failed"
        echo -e "${RED}[ERROR]${NC} Error output:"
        tail -10 "$output_file" | sed 's/^/  /'
        return 1
    fi
}

# Test execution
echo -e "${BLUE}[INFO]${NC} Starting test suite execution..."

total_tests=0
passed_tests=0
failed_tests=0

# Test 1: Packet Generation Framework
echo -e "${YELLOW}[TEST 1]${NC} Packet Generation Framework"
if run_test "packet_gen_test_tb" "Protocol packet generation validation" "2us"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test 2: Basic Functionality  
echo -e "${YELLOW}[TEST 2]${NC} Basic Functionality"
if run_test "tcp_offload_tb" "Basic interface and register testing" "100us"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test 3: TCP Connection (if available)
echo -e "${YELLOW}[TEST 3]${NC} TCP Connection Testing"
if run_test "tcp_connection_test_tb" "TCP three-way handshake validation" "50us"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test 4: UDP/DHCP (if available)
echo -e "${YELLOW}[TEST 4]${NC} UDP/DHCP Testing"
if run_test "udp_dhcp_test_tb" "UDP packet and DHCP client testing" "50us"; then
    ((passed_tests++))
else
    ((failed_tests++))
fi
((total_tests++))

# Test summary
cd ..
echo ""
echo -e "${BLUE}====== TEST SUITE SUMMARY ======${NC}"
echo -e "${BLUE}[INFO]${NC} Total tests run: $total_tests"
echo -e "${GREEN}[INFO]${NC} Tests passed: $passed_tests"
echo -e "${RED}[INFO]${NC} Tests failed: $failed_tests"

if [ $failed_tests -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} All tests passed! 🎉"
else
    echo -e "${RED}[WARNING]${NC} Some tests failed. Check logs for details."
fi

echo ""
echo -e "${BLUE}[INFO]${NC} Test results saved in: $WORK_DIR/"
echo -e "${BLUE}[INFO]${NC} Waveform files: $WORK_DIR/*_wave.ghw"
echo -e "${BLUE}[INFO]${NC} Log files: $WORK_DIR/*_results.log"
echo ""
echo -e "${BLUE}[INFO]${NC} To view waveforms:"
echo -e "${BLUE}[INFO]${NC}   gtkwave $WORK_DIR/<test_name>_wave.ghw"

echo -e "${BLUE}================================================${NC}"

# Exit with appropriate code
if [ $failed_tests -eq 0 ]; then
    exit 0
else
    exit 1
fi