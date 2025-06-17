# Changelog

All notable changes to the TCP Offload Engine project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Performance benchmarking suite
- Advanced error injection testing
- Real PHY simulation models
- Production deployment guides

### Changed
- TBD

### Fixed
- TBD

## [1.0.0-beta] - 2024-06-17

### Added
- Complete TCP/IP protocol stack implementation
- RGMII interface with auto-negotiation support
- AXI4-Lite control interface
- AXI4-Stream data interface
- TCP engine with advanced features (SACK, timestamps)
- UDP engine with DHCP client
- Comprehensive test infrastructure
- Protocol packet generation library
- Automated test execution scripts
- Professional documentation suite

### Technical Features
- **TCP Protocol**: Full state machine, three-way handshake, connection management
- **UDP Protocol**: Packet transmission/reception, DHCP integration
- **DHCP Client**: DISCOVER/OFFER/REQUEST/ACK sequence support
- **Ethernet MAC**: Frame processing and RGMII interface
- **IP Layer**: IPv4 with ICMP basic support
- **Buffer Management**: 4KB BRAM-based packet buffering per connection
- **Multi-Connection**: Support for 2 simultaneous TCP connections

### Test Infrastructure
- **Protocol Validation**: TCP connection establishment tests
- **Packet Generation**: Validated Ethernet/IP/TCP/UDP packet creation
- **Integration Testing**: End-to-end functionality verification
- **Automated Testing**: Script-based test execution with reporting
- **Waveform Generation**: GTKWave-compatible simulation outputs

### Documentation
- System architecture documentation
- Integration guide for FPGA designs
- Comprehensive testing guide
- Test results and validation summary
- API reference and register maps

### Fixed
- Eliminated infinite metavalue warnings in simulation
- Resolved VHDL compilation and elaboration issues
- Fixed signal initialization and bounds checking
- Corrected multiple driver conflicts in state machines
- Improved error handling throughout the design

### Known Limitations
- Simplified checksums in some protocols (marked for future enhancement)
- Limited error scenario testing
- No real PHY hardware validation yet
- Performance characterization needed

## Project History

### Phase 1: Initial Implementation
- Created basic TCP/IP stack structure
- Implemented core VHDL modules
- Basic compilation achieved

### Phase 2: Infrastructure Development  
- Fixed compilation and simulation issues
- Developed test infrastructure
- Created packet generation framework

### Phase 3: Validation & Organization
- Implemented comprehensive testing
- Validated packet generation
- Organized project structure
- Created professional documentation

---

## Version Format

Versions follow semantic versioning: `MAJOR.MINOR.PATCH[-PRERELEASE]`

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backward compatible)
- **PATCH**: Bug fixes (backward compatible)
- **PRERELEASE**: Development versions (alpha, beta, rc)