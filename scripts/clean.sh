#!/bin/bash

# TCP Offload Engine Clean Script
# Removes all generated files and build artifacts

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  TCP Offload Engine Clean Script${NC}"
echo -e "${BLUE}================================================${NC}"

echo -e "${BLUE}[INFO]${NC} Cleaning build artifacts..."

# Remove work directories
if [ -d "work" ]; then
    echo -e "${BLUE}[INFO]${NC} Removing work/ directory..."
    rm -rf work/
fi

if [ -d "work_comprehensive" ]; then
    echo -e "${BLUE}[INFO]${NC} Removing work_comprehensive/ directory..."
    rm -rf work_comprehensive/
fi

if [ -d "work_test" ]; then
    echo -e "${BLUE}[INFO]${NC} Removing work_test/ directory..."
    rm -rf work_test/
fi

if [ -d "work_simple" ]; then
    echo -e "${BLUE}[INFO]${NC} Removing work_simple/ directory..."
    rm -rf work_simple/
fi

# Remove GHDL generated files
echo -e "${BLUE}[INFO]${NC} Removing GHDL artifacts..."
find . -name "*.cf" -delete 2>/dev/null
find . -name "*.o" -delete 2>/dev/null
find . -name "e~*" -delete 2>/dev/null

# Remove simulation files
echo -e "${BLUE}[INFO]${NC} Removing simulation files..."
find . -name "*.ghw" -delete 2>/dev/null
find . -name "*.vcd" -delete 2>/dev/null
find . -name "*.fst" -delete 2>/dev/null

# Remove log files
echo -e "${BLUE}[INFO]${NC} Removing log files..."
find . -name "*.log" -delete 2>/dev/null

# Remove temporary files
echo -e "${BLUE}[INFO]${NC} Removing temporary files..."
find . -name "*~" -delete 2>/dev/null
find . -name "*.tmp" -delete 2>/dev/null
find . -name "*.temp" -delete 2>/dev/null

# Remove Vivado files (if any)
echo -e "${BLUE}[INFO]${NC} Removing Vivado artifacts..."
find . -name "*.jou" -delete 2>/dev/null
find . -name "*.str" -delete 2>/dev/null
find . -name "vivado*.backup*" -delete 2>/dev/null

# Remove any build directories
for dir in build synth impl out; do
    if [ -d "$dir" ]; then
        echo -e "${BLUE}[INFO]${NC} Removing $dir/ directory..."
        rm -rf "$dir/"
    fi
done

echo -e "${GREEN}[SUCCESS]${NC} Clean completed!"
echo ""
echo -e "${BLUE}[INFO]${NC} Removed:"
echo -e "${BLUE}[INFO]${NC}   - All work directories"
echo -e "${BLUE}[INFO]${NC}   - GHDL compiled files"
echo -e "${BLUE}[INFO]${NC}   - Simulation waveforms"
echo -e "${BLUE}[INFO]${NC}   - Log files"
echo -e "${BLUE}[INFO]${NC}   - Temporary files"
echo ""
echo -e "${BLUE}[INFO]${NC} Source files preserved in src/ directory"
echo -e "${BLUE}================================================${NC}"