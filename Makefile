# TCP Offload Engine Makefile
# Provides convenient targets for common development tasks

.PHONY: all build test clean help install-deps check-deps

# Default target
all: build test

# Build the project
build:
	@echo "Building TCP Offload Engine..."
	@./scripts/build.sh

# Run tests
test:
	@echo "Running test suite..."
	@./scripts/run_tests.sh

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@./scripts/clean.sh

# Check dependencies
check-deps:
	@echo "Checking dependencies..."
	@which ghdl >/dev/null 2>&1 || (echo "ERROR: GHDL not found. Please install GHDL." && exit 1)
	@which gtkwave >/dev/null 2>&1 || echo "WARNING: GTKWave not found. Waveform viewing will not be available."
	@echo "Dependencies check completed."

# Install dependencies (Ubuntu/Debian)
install-deps:
	@echo "Installing dependencies..."
	@sudo apt-get update
	@sudo apt-get install -y ghdl gtkwave
	@echo "Dependencies installed."

# Quick test (packet generation only)
test-quick:
	@echo "Running quick test..."
	@cd work 2>/dev/null || ./scripts/build.sh
	@cd work && ghdl -r --std=08 --ieee=synopsys packet_gen_test_tb --stop-time=2us

# Elaborate top-level design
elaborate:
	@echo "Elaborating top-level design..."
	@cd work 2>/dev/null || ./scripts/build.sh
	@cd work && ghdl -e --std=08 --ieee=synopsys tcp_offload_engine_top

# Generate project documentation
docs:
	@echo "Project documentation available in docs/ directory"
	@ls -la docs/

# Show project structure
structure:
	@echo "TCP Offload Engine Project Structure:"
	@find . -type f -name "*.vhd" -o -name "*.md" -o -name "*.sh" | grep -v work | sort

# Development workflow
dev: clean build test-quick
	@echo "Development cycle completed successfully!"

# Release preparation
release: clean build test docs
	@echo "Release preparation completed!"
	@echo "All tests passed and documentation is ready."

# Help target
help:
	@echo "TCP Offload Engine Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  all          - Build and test (default)"
	@echo "  build        - Compile all VHDL files"
	@echo "  test         - Run complete test suite"
	@echo "  test-quick   - Run quick packet generation test"
	@echo "  clean        - Remove all build artifacts"
	@echo "  elaborate    - Elaborate top-level design"
	@echo "  check-deps   - Check for required tools"
	@echo "  install-deps - Install dependencies (Ubuntu/Debian)"
	@echo "  structure    - Show project file structure"
	@echo "  docs         - Show documentation files"
	@echo "  dev          - Development cycle (clean + build + quick test)"
	@echo "  release      - Release preparation (clean + build + test + docs)"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build   # Compile the project"
	@echo "  make test    # Run all tests"
	@echo "  make dev     # Quick development cycle"