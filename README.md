# TCP Offload Engine

A hardware-accelerated TCP/IP stack implementation in VHDL for Xilinx FPGAs with RGMII interface.

## 🚀 Features

- **Complete TCP/IP Stack**: TCP, UDP, DHCP, ICMP protocols
- **RGMII Interface**: 125 MHz operation with auto-negotiation
- **Dual Interfaces**: AXI4-Lite control + AXI4-Stream data
- **Hardware Acceleration**: Offloads TCP processing from CPU
- **Multi-Connection**: Supports minimum 2 simultaneous TCP connections
- **Advanced TCP Features**: SACK, timestamps, congestion control
- **FPGA Optimized**: Uses Block RAM for 4KB packet buffering

## 📁 Project Structure

```
tcp-offload-engine/
├── src/vhdl/                    # VHDL source code
│   ├── core/                    # Core components
│   │   ├── tcp_offload_pkg.vhd     # Package definitions
│   │   └── packet_buffer.vhd       # BRAM packet buffering
│   ├── interfaces/              # Interface modules
│   │   ├── rgmii_interface.vhd     # RGMII PHY interface
│   │   ├── axi4_lite_interface.vhd # AXI4-Lite control
│   │   └── axi4_stream_interface.vhd # AXI4-Stream data
│   ├── protocols/               # Protocol implementations
│   │   ├── ethernet_mac.vhd        # Ethernet MAC layer
│   │   ├── ip_layer.vhd            # IP layer with ICMP
│   │   ├── tcp_engine.vhd          # TCP protocol engine
│   │   ├── udp_engine.vhd          # UDP protocol engine
│   │   └── dhcp_client.vhd         # DHCP client
│   ├── testbench/               # Test infrastructure
│   │   ├── tcp_protocol_tb_pkg.vhd # Test utilities
│   │   ├── tcp_offload_tb.vhd      # Basic functionality test
│   │   ├── tcp_connection_test_tb.vhd # TCP connection tests
│   │   ├── udp_dhcp_test_tb.vhd    # UDP/DHCP tests
│   │   └── packet_gen_test_tb.vhd  # Packet generation tests
│   └── tcp_offload_engine_top.vhd # Top-level integration
├── scripts/                     # Build and test scripts
│   ├── run_sim.sh                  # Basic simulation
│   └── run_comprehensive_tests.sh # Full test suite
├── docs/                        # Documentation
│   ├── ARCHITECTURE.md             # System architecture
│   ├── INTEGRATION_GUIDE.md        # Integration guide
│   ├── COMPREHENSIVE_TESTING_GUIDE.md # Testing guide
│   └── TEST_SUITE_SUMMARY.md       # Test results summary
├── tests/                       # Test configurations
├── examples/                    # Usage examples
└── tools/                       # Development tools
```

## 🔧 Requirements

### Hardware
- **FPGA**: Xilinx 7-series or later
- **PHY**: RGMII-compatible Gigabit Ethernet PHY
- **Resources**: ~50K LUTs, ~100 Block RAMs (estimated)

### Software
- **GHDL**: 1.0.0 or later for simulation
- **GTKWave**: For waveform viewing
- **Vivado**: 2019.1 or later for synthesis

## 🚀 Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/your-org/tcp-offload-engine.git
cd tcp-offload-engine
```

### 2. Run Basic Tests
```bash
# Basic functionality test
chmod +x scripts/run_sim.sh
./scripts/run_sim.sh

# Comprehensive protocol tests
chmod +x scripts/run_comprehensive_tests.sh
./scripts/run_comprehensive_tests.sh
```

### 3. View Results
```bash
# View simulation logs
cat work/simulation.log

# View waveforms
gtkwave work/wave.ghw
```

## 📋 Configuration

### AXI4-Lite Register Map
| Address | Register | Description |
|---------|----------|-------------|
| 0x00 | CONTROL | Engine enable, protocol enables |
| 0x04 | STATUS | Link status, engine status |
| 0x08 | MAC_ADDR_LOW | MAC address [31:0] |
| 0x0C | MAC_ADDR_HIGH | MAC address [47:32] |
| 0x10 | IP_ADDR | Local IP address |
| 0x14 | SUBNET_MASK | Subnet mask |
| 0x18 | GATEWAY | Gateway IP address |
| 0x1C | TCP_PORT_0 | TCP port 0 configuration |
| 0x20 | TCP_PORT_1 | TCP port 1 configuration |

### Key Parameters
- **Clock Frequency**: 125 MHz (system), 100 MHz (AXI)
- **Buffer Size**: 4KB per connection
- **Maximum Frame Size**: 1518 bytes
- **TCP Window Size**: Configurable, default 8KB

## 🧪 Testing

The project includes comprehensive test suites:

### Test Levels
1. **Unit Tests**: Individual component validation
2. **Protocol Tests**: TCP/UDP/DHCP protocol compliance
3. **Integration Tests**: End-to-end functionality
4. **Performance Tests**: Throughput and latency

### Test Coverage
- ✅ **Packet Generation**: Validated protocol packet creation
- ✅ **Interface Testing**: AXI4-Lite/Stream functionality
- ✅ **Basic Protocol**: TCP handshake, UDP packets, DHCP discovery
- ⚠️ **Advanced Features**: SACK, timestamps (framework ready)
- ❌ **Performance**: Throughput testing (planned)

See [Testing Guide](docs/COMPREHENSIVE_TESTING_GUIDE.md) for details.

## 🏗️ Architecture

The TCP Offload Engine implements a complete hardware TCP/IP stack:

```
┌─────────────────────────────────────────────────────────┐
│                    Host Application                     │
└─────────────────────┬───────────────────────────────────┘
                      │ AXI4-Stream
┌─────────────────────▼───────────────────────────────────┐
│              AXI4-Stream Interface                      │
├─────────────────────┬───────────────────────────────────┤
│               TCP Engine                                │
├─────────────────────┼───────────────────────────────────┤
│            UDP Engine        │        DHCP Client       │
├─────────────────────┴───────────────────────────────────┤
│                     IP Layer                            │
├─────────────────────────────────────────────────────────┤
│                  Ethernet MAC                           │
├─────────────────────────────────────────────────────────┤
│                 RGMII Interface                         │
└─────────────────────┬───────────────────────────────────┘
                      │ RGMII
┌─────────────────────▼───────────────────────────────────┐
│                Ethernet PHY                             │
└─────────────────────────────────────────────────────────┘
```

See [Architecture Guide](docs/ARCHITECTURE.md) for detailed design.

## 📖 Documentation

- **[Architecture](docs/ARCHITECTURE.md)**: System design and component details
- **[Integration Guide](docs/INTEGRATION_GUIDE.md)**: How to integrate into your design
- **[Testing Guide](docs/COMPREHENSIVE_TESTING_GUIDE.md)**: Complete testing methodology
- **[Test Results](docs/TEST_SUITE_SUMMARY.md)**: Current validation status

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Development Standards
- All VHDL code must be VHDL-2008 compliant
- Comprehensive test coverage required
- Documentation must be updated
- Follow existing coding style

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🏷️ Status

**Current Version**: 1.0.0-beta  
**Status**: Development/Testing  
**Last Updated**: 2024-06-17

### Readiness Levels
- 🟢 **Development Ready**: Core infrastructure complete
- 🟡 **Testing Phase**: Protocol validation in progress  
- 🔴 **Production**: Additional validation required

## 📞 Support

- **Issues**: Use GitHub Issues for bug reports
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Check the `docs/` folder

## 🙏 Acknowledgments

- Built using GHDL open-source VHDL simulator
- Tested with GTKWave waveform viewer
- Designed for Xilinx FPGA platforms