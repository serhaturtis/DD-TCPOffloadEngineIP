# TCP Offload Engine Architecture Guide

## 📐 Architecture Overview

This document provides detailed architectural information for the TCP Offload Engine implementation, including design decisions, data flow, timing analysis, and implementation considerations.

## 🏗️ System Architecture

### Hierarchical Design Structure

```
tcp_offload_engine_top
├── Clock Management
│   ├── sys_clk (125 MHz)
│   ├── clk_25mhz (100M operation)
│   └── clk_2_5mhz (10M operation)
├── Reset Synchronization
│   ├── rst_n_sync
│   └── rst_n_125mhz
├── RGMII Physical Layer
│   ├── rgmii_interface
│   │   ├── TX DDR Logic
│   │   ├── RX DDR Logic
│   │   ├── MDIO Controller
│   │   └── Auto-negotiation FSM
│   └── Clock Domain Crossing
├── Ethernet MAC Layer
│   ├── ethernet_mac
│   │   ├── TX Engine
│   │   │   ├── Preamble Generation
│   │   │   ├── Frame Assembly
│   │   │   ├── CRC Generation
│   │   │   └── IFG Management
│   │   ├── RX Engine
│   │   │   ├── Preamble Detection
│   │   │   ├── Frame Parsing
│   │   │   ├── CRC Validation
│   │   │   └── Address Filtering
│   │   └── Flow Control
│   └── Frame Buffering
├── Network Layer
│   ├── ip_layer
│   │   ├── IP Header Processing
│   │   ├── Checksum Calculation
│   │   ├── Fragmentation Support
│   │   ├── Routing Logic
│   │   └── ICMP Engine
│   └── ARP Resolution
├── Transport Layer
│   ├── tcp_engine
│   │   ├── Connection Management (2 connections)
│   │   ├── State Machine (RFC 793)
│   │   ├── Sequence Number Management
│   │   ├── Acknowledgment Processing
│   │   ├── Window Management
│   │   ├── Retransmission Logic
│   │   ├── SACK Processing
│   │   ├── Timestamp Handling
│   │   └── Congestion Control Framework
│   ├── udp_engine
│   │   ├── Port Demultiplexing
│   │   ├── Checksum Processing
│   │   └── DHCP Integration
│   └── dhcp_client
│       ├── DHCP State Machine
│       ├── Option Processing
│       ├── Lease Management
│       └── Renewal Logic
├── Buffer Management
│   ├── packet_buffer (per connection)
│   │   ├── BRAM Interface
│   │   ├── FIFO Logic
│   │   ├── Flow Control
│   │   └── Status Monitoring
│   └── Memory Arbitration
├── Host Interface
│   ├── axi4_lite_interface
│   │   ├── Register Map
│   │   ├── Control Logic
│   │   ├── Status Reporting
│   │   └── Configuration Management
│   └── axi4_stream_interface
│       ├── TX Path (Host → Network)
│       ├── RX Path (Network → Host)
│       ├── Connection Multiplexing
│       └── Data Width Conversion
└── Status and Monitoring
    ├── Link Status LEDs
    ├── Activity Indicators
    ├── Error Reporting
    └── Performance Counters
```

## 🔄 Data Flow Architecture

### TX Data Path (Host to Network)

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Host CPU      │    │  AXI4-Stream    │    │  TCP Engine     │
│                 │    │   Interface     │    │                 │
│ Application     │───►│ ┌─────────────┐ │───►│ ┌─────────────┐ │
│ Data            │    │ │ Connection  │ │    │ │ Header      │ │
│                 │    │ │ Multiplexer │ │    │ │ Generation  │ │
└─────────────────┘    │ └─────────────┘ │    │ └─────────────┘ │
                       │ ┌─────────────┐ │    │ ┌─────────────┐ │
                       │ │   Buffer    │ │    │ │ Checksum    │ │
                       │ │ Management  │ │    │ │ Calculation │ │
                       │ └─────────────┘ │    │ └─────────────┘ │
                       └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  RGMII PHY      │    │ Ethernet MAC    │    │   IP Layer      │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │◄───│ ┌─────────────┐ │◄───│ ┌─────────────┐ │
│ │ DDR TX      │ │    │ │ Frame       │ │    │ │ IP Header   │ │
│ │ Logic       │ │    │ │ Assembly    │ │    │ │ Processing  │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Clock       │ │    │ │ CRC         │ │    │ │ Routing     │ │
│ │ Generation  │ │    │ │ Generation  │ │    │ │ Logic       │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### RX Data Path (Network to Host)

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  RGMII PHY      │    │ Ethernet MAC    │    │   IP Layer      │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │───►│ ┌─────────────┐ │───►│ ┌─────────────┐ │
│ │ DDR RX      │ │    │ │ Frame       │ │    │ │ IP Header   │ │
│ │ Logic       │ │    │ │ Parsing     │ │    │ │ Validation  │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Clock       │ │    │ │ CRC         │ │    │ │ Protocol    │ │
│ │ Recovery    │ │    │ │ Validation  │ │    │ │ Demux       │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       │
                                ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Host CPU      │    │  AXI4-Stream    │    │  TCP Engine     │
│                 │    │   Interface     │    │                 │
│ Application     │◄───│ ┌─────────────┐ │◄───│ ┌─────────────┐ │
│ Processing      │    │ │ Connection  │ │    │ │ Header      │ │
│                 │    │ │ Demux       │ │    │ │ Processing  │ │
└─────────────────┘    │ └─────────────┘ │    │ └─────────────┘ │
                       │ ┌─────────────┐ │    │ ┌─────────────┐ │
                       │ │   Buffer    │ │    │ │ State       │ │
                       │ │ Management  │ │    │ │ Machine     │ │
                       │ └─────────────┘ │    │ └─────────────┘ │
                       └─────────────────┘    └─────────────────┘
```

## 🕐 Timing Architecture

### Clock Domain Analysis

#### Primary Clock Domains

1. **System Clock Domain (125 MHz)**
   - Main processing clock
   - TCP/UDP engines
   - Buffer management
   - Control logic

2. **AXI Clock Domain (100 MHz)**
   - Host interface
   - Register access
   - Configuration

3. **RGMII RX Clock Domain (125 MHz)**
   - Received from PHY
   - RX data processing
   - Variable frequency (10/100/1000M)

### Clock Domain Crossing

```vhdl
-- Synchronizer for control signals
component cdc_sync is
    generic (
        STAGES : natural := 2
    );
    port (
        src_clk  : in  std_logic;
        dst_clk  : in  std_logic;
        src_data : in  std_logic;
        dst_data : out std_logic
    );
end component;

-- FIFO for data crossing
component cdc_fifo is
    generic (
        DATA_WIDTH : natural := 8;
        DEPTH      : natural := 16
    );
    port (
        wr_clk   : in  std_logic;
        rd_clk   : in  std_logic;
        rst_n    : in  std_logic;
        wr_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        wr_valid : in  std_logic;
        wr_ready : out std_logic;
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_valid : out std_logic;
        rd_ready : in  std_logic
    );
end component;
```

### Timing Constraints

```tcl
# Primary clocks
create_clock -period 8.000 -name sys_clk [get_ports sys_clk]
create_clock -period 10.000 -name axi_clk [get_ports s_axi_aclk]

# RGMII clocks (source synchronous)
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]

# Clock groups (asynchronous)
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks axi_clk] \
    -group [get_clocks rgmii_rxc]

# Input delays for RGMII (setup/hold)
set_input_delay -clock rgmii_rxc -max 2.0 [get_ports {rgmii_rxd rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -min -0.5 [get_ports {rgmii_rxd rgmii_rx_ctl}]

# Output delays for RGMII
set_output_delay -clock sys_clk -max 1.0 [get_ports {rgmii_txd rgmii_tx_ctl}]
set_output_delay -clock sys_clk -min -0.5 [get_ports {rgmii_txd rgmii_tx_ctl}]

# False paths for configuration registers
set_false_path -from [get_pins */config_reg*/C] -to [get_pins */sync_reg*/D]
```

## 💾 Memory Architecture

### Buffer Organization

```
                    ┌─────────────────────────────────────┐
                    │         BRAM Pool (Total)            │
                    │              144 KB                  │
                    └─────────────────────────────────────┘
                                     │
            ┌─────────────┬──────────┼──────────┬─────────────┐
            │             │          │          │             │
    ┌───────▼───────┐ ┌───▼───┐ ┌────▼────┐ ┌───▼───┐ ┌───────▼───────┐
    │ TCP Conn 0    │ │ TCP   │ │  UDP    │ │ DHCP  │ │ Control/      │
    │ TX: 4KB       │ │ Conn 0│ │ Buffer  │ │Buffer │ │ Status        │
    │ RX: 4KB       │ │ RX:4KB│ │ 2KB     │ │ 1KB   │ │ 1KB           │
    └───────────────┘ └───────┘ └─────────┘ └───────┘ └───────────────┘
    
    ┌───────────────┐ ┌───────┐
    │ TCP Conn 1    │ │ TCP   │
    │ TX: 4KB       │ │ Conn 1│
    │ RX: 4KB       │ │ RX:4KB│
    └───────────────┘ └───────┘
```

### Buffer Management Strategy

#### Round-Robin Arbitration
```vhdl
-- Buffer arbiter for fair access
process(clk, rst_n)
begin
    if rst_n = '0' then
        current_buffer <= 0;
        arbiter_state <= IDLE;
    elsif rising_edge(clk) then
        case arbiter_state is
            when IDLE =>
                if buffer_request /= "00" then
                    arbiter_state <= GRANT;
                    -- Find next requesting buffer
                    for i in 0 to NUM_BUFFERS-1 loop
                        if buffer_request((current_buffer + i) mod NUM_BUFFERS) = '1' then
                            current_buffer <= (current_buffer + i) mod NUM_BUFFERS;
                            exit;
                        end if;
                    end loop;
                end if;
            
            when GRANT =>
                if buffer_done(current_buffer) = '1' then
                    arbiter_state <= IDLE;
                    current_buffer <= (current_buffer + 1) mod NUM_BUFFERS;
                end if;
        end case;
    end if;
end process;
```

#### Flow Control
```vhdl
-- Back-pressure flow control
signal almost_full_threshold : unsigned(ADDR_WIDTH-1 downto 0) := 
    to_unsigned(BUFFER_DEPTH - 16, ADDR_WIDTH);

process(clk, rst_n)
begin
    if rst_n = '0' then
        flow_control_active <= '0';
    elsif rising_edge(clk) then
        if buffer_count >= almost_full_threshold then
            flow_control_active <= '1';
        elsif buffer_count <= almost_full_threshold - 8 then
            flow_control_active <= '0';
        end if;
    end if;
end process;

-- Apply flow control
ready_output <= ready_internal and not flow_control_active;
```

## 🌐 Protocol Stack Architecture

### TCP State Machine Implementation

```vhdl
-- TCP connection state record
type tcp_connection_state_t is record
    -- RFC 793 state
    state : tcp_state_t;
    
    -- Sequence space
    snd_una : unsigned(31 downto 0);  -- Send unacknowledged
    snd_nxt : unsigned(31 downto 0);  -- Send next
    snd_wnd : unsigned(15 downto 0);  -- Send window
    snd_up  : unsigned(15 downto 0);  -- Send urgent pointer
    snd_wl1 : unsigned(31 downto 0);  -- Segment seq num for last window update
    snd_wl2 : unsigned(31 downto 0);  -- Segment ack num for last window update
    iss     : unsigned(31 downto 0);  -- Initial send sequence number
    
    rcv_nxt : unsigned(31 downto 0);  -- Receive next
    rcv_wnd : unsigned(15 downto 0);  -- Receive window
    rcv_up  : unsigned(15 downto 0);  -- Receive urgent pointer
    irs     : unsigned(31 downto 0);  -- Initial receive sequence number
    
    -- Timers
    retransmit_timer : unsigned(31 downto 0);
    persist_timer    : unsigned(31 downto 0);
    keepalive_timer  : unsigned(31 downto 0);
    
    -- Round Trip Time
    rtt_estimate : unsigned(31 downto 0);
    rtt_variance : unsigned(31 downto 0);
    rto          : unsigned(31 downto 0);  -- Retransmission timeout
    
    -- Congestion control
    cwnd         : unsigned(31 downto 0);  -- Congestion window
    ssthresh     : unsigned(31 downto 0);  -- Slow start threshold
    dup_ack_count: unsigned(7 downto 0);   -- Duplicate ACK counter
    
    -- Options
    mss              : unsigned(15 downto 0);  -- Maximum segment size
    window_scale     : unsigned(3 downto 0);   -- Window scaling factor
    sack_permitted   : std_logic;              -- SACK option enabled
    timestamp_enabled: std_logic;              -- Timestamp option enabled
end record;
```

### State Transition Logic

```vhdl
-- Main TCP state machine
process(clk, rst_n)
begin
    if rst_n = '0' then
        for i in 0 to TCP_CONNECTIONS-1 loop
            tcp_conn(i).state <= TCP_CLOSED;
        end loop;
    elsif rising_edge(clk) then
        for i in 0 to TCP_CONNECTIONS-1 loop
            case tcp_conn(i).state is
                when TCP_CLOSED =>
                    if listen_request(i) = '1' then
                        tcp_conn(i).state <= TCP_LISTEN;
                    elsif connect_request(i) = '1' then
                        tcp_conn(i).state <= TCP_SYN_SENT;
                        tcp_conn(i).iss <= generate_isn();
                        tcp_conn(i).snd_nxt <= tcp_conn(i).iss + 1;
                    end if;
                
                when TCP_LISTEN =>
                    if syn_received(i) = '1' then
                        tcp_conn(i).state <= TCP_SYN_RCVD;
                        tcp_conn(i).irs <= rx_seq_num;
                        tcp_conn(i).rcv_nxt <= rx_seq_num + 1;
                        tcp_conn(i).iss <= generate_isn();
                        tcp_conn(i).snd_nxt <= tcp_conn(i).iss + 1;
                    end if;
                
                when TCP_SYN_SENT =>
                    if syn_ack_received(i) = '1' then
                        tcp_conn(i).state <= TCP_ESTABLISHED;
                        tcp_conn(i).irs <= rx_seq_num;
                        tcp_conn(i).rcv_nxt <= rx_seq_num + 1;
                        tcp_conn(i).snd_una <= rx_ack_num;
                    elsif syn_received(i) = '1' then
                        tcp_conn(i).state <= TCP_SYN_RCVD;
                        tcp_conn(i).irs <= rx_seq_num;
                        tcp_conn(i).rcv_nxt <= rx_seq_num + 1;
                    end if;
                
                when TCP_SYN_RCVD =>
                    if ack_received(i) = '1' and 
                       rx_ack_num = tcp_conn(i).snd_nxt then
                        tcp_conn(i).state <= TCP_ESTABLISHED;
                        tcp_conn(i).snd_una <= rx_ack_num;
                    end if;
                
                when TCP_ESTABLISHED =>
                    if fin_received(i) = '1' then
                        tcp_conn(i).state <= TCP_CLOSE_WAIT;
                        tcp_conn(i).rcv_nxt <= tcp_conn(i).rcv_nxt + 1;
                    elsif close_request(i) = '1' then
                        tcp_conn(i).state <= TCP_FIN_WAIT_1;
                    end if;
                
                -- Additional states...
                when others =>
                    null;
            end case;
        end loop;
    end if;
end process;
```

### Congestion Control Implementation

```vhdl
-- Congestion control state machine
process(clk, rst_n)
begin
    if rst_n = '0' then
        for i in 0 to TCP_CONNECTIONS-1 loop
            tcp_conn(i).cwnd <= to_unsigned(MSS, 32);
            tcp_conn(i).ssthresh <= to_unsigned(65535, 32);
            tcp_conn(i).dup_ack_count <= (others => '0');
        end loop;
    elsif rising_edge(clk) then
        for i in 0 to TCP_CONNECTIONS-1 loop
            if new_ack_received(i) = '1' then
                -- Reset duplicate ACK counter
                tcp_conn(i).dup_ack_count <= (others => '0');
                
                -- Slow start or congestion avoidance
                if tcp_conn(i).cwnd < tcp_conn(i).ssthresh then
                    -- Slow start: cwnd += MSS
                    tcp_conn(i).cwnd <= tcp_conn(i).cwnd + MSS;
                else
                    -- Congestion avoidance: cwnd += MSS * MSS / cwnd
                    tcp_conn(i).cwnd <= tcp_conn(i).cwnd + 
                        (MSS * MSS) / tcp_conn(i).cwnd;
                end if;
                
            elsif duplicate_ack_received(i) = '1' then
                tcp_conn(i).dup_ack_count <= tcp_conn(i).dup_ack_count + 1;
                
                -- Fast retransmit/recovery
                if tcp_conn(i).dup_ack_count = 3 then
                    tcp_conn(i).ssthresh <= tcp_conn(i).cwnd / 2;
                    tcp_conn(i).cwnd <= tcp_conn(i).ssthresh + 3 * MSS;
                    trigger_retransmit(i) <= '1';
                elsif tcp_conn(i).dup_ack_count > 3 then
                    tcp_conn(i).cwnd <= tcp_conn(i).cwnd + MSS;
                end if;
                
            elsif timeout_occurred(i) = '1' then
                -- Timeout: enter slow start
                tcp_conn(i).ssthresh <= tcp_conn(i).cwnd / 2;
                tcp_conn(i).cwnd <= to_unsigned(MSS, 32);
                tcp_conn(i).dup_ack_count <= (others => '0');
            end if;
        end loop;
    end if;
end process;
```

## 🔌 Interface Architecture

### AXI4-Lite Register Interface

```vhdl
-- Register map implementation
process(clk, rst_n)
begin
    if rst_n = '0' then
        -- Initialize all registers
        reg_control <= (others => '0');
        reg_mac_addr_low <= (others => '0');
        reg_mac_addr_high <= (others => '0');
        -- ... other registers
    elsif rising_edge(clk) then
        -- Write operations
        if axi_write_valid = '1' and axi_write_ready = '1' then
            case axi_write_addr is
                when REG_CONTROL =>
                    reg_control <= axi_write_data;
                when REG_MAC_ADDR_LOW =>
                    reg_mac_addr_low <= axi_write_data;
                when REG_MAC_ADDR_HIGH =>
                    reg_mac_addr_high <= axi_write_data;
                -- ... other write cases
                when others =>
                    null;
            end case;
        end if;
        
        -- Read operations
        if axi_read_valid = '1' and axi_read_ready = '1' then
            case axi_read_addr is
                when REG_CONTROL =>
                    axi_read_data <= reg_control;
                when REG_STATUS =>
                    axi_read_data <= build_status_register();
                when REG_MAC_ADDR_LOW =>
                    axi_read_data <= reg_mac_addr_low;
                -- ... other read cases
                when others =>
                    axi_read_data <= (others => '0');
            end case;
        end if;
    end if;
end process;
```

### AXI4-Stream Data Path

```vhdl
-- Stream interface with connection multiplexing
process(clk, rst_n)
begin
    if rst_n = '0' then
        stream_state <= IDLE;
        current_connection <= 0;
    elsif rising_edge(clk) then
        case stream_state is
            when IDLE =>
                -- Check for data from any connection
                for i in 0 to TCP_CONNECTIONS-1 loop
                    if tcp_tx_valid(i) = '1' then
                        current_connection <= i;
                        stream_state <= TRANSMIT;
                        exit;
                    end if;
                end loop;
            
            when TRANSMIT =>
                if m_axis_tvalid = '1' and m_axis_tready = '1' then
                    -- Forward data from current connection
                    m_axis_tdata <= tcp_tx_data(current_connection);
                    m_axis_tkeep <= tcp_tx_keep(current_connection);
                    m_axis_tlast <= tcp_tx_last(current_connection);
                    m_axis_tuser <= std_logic_vector(to_unsigned(current_connection, 8));
                    
                    if tcp_tx_last(current_connection) = '1' then
                        stream_state <= IDLE;
                    end if;
                end if;
            
            when others =>
                stream_state <= IDLE;
        end case;
    end if;
end process;
```

## 🚀 Performance Optimization

### Pipeline Architecture

```vhdl
-- Multi-stage pipeline for high throughput
architecture pipelined of tcp_processor is
    -- Pipeline stages
    signal stage1_valid, stage2_valid, stage3_valid : std_logic;
    signal stage1_data, stage2_data, stage3_data : std_logic_vector(63 downto 0);
    
begin
    -- Stage 1: Header parsing
    stage1_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            stage1_valid <= '0';
        elsif rising_edge(clk) then
            if input_valid = '1' and pipeline_ready = '1' then
                stage1_data <= parse_headers(input_data);
                stage1_valid <= '1';
            else
                stage1_valid <= '0';
            end if;
        end if;
    end process;
    
    -- Stage 2: Checksum calculation
    stage2_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            stage2_valid <= '0';
        elsif rising_edge(clk) then
            if stage1_valid = '1' then
                stage2_data <= calculate_checksum(stage1_data);
                stage2_valid <= '1';
            else
                stage2_valid <= '0';
            end if;
        end if;
    end process;
    
    -- Stage 3: Protocol processing
    stage3_proc: process(clk, rst_n)
    begin
        if rst_n = '0' then
            stage3_valid <= '0';
        elsif rising_edge(clk) then
            if stage2_valid = '1' then
                stage3_data <= process_protocol(stage2_data);
                stage3_valid <= '1';
            else
                stage3_valid <= '0';
            end if;
        end if;
    end process;
    
    output_data <= stage3_data;
    output_valid <= stage3_valid;
    pipeline_ready <= not (stage1_valid and stage2_valid and stage3_valid);
    
end architecture;
```

### Parallel Processing

```vhdl
-- Parallel connection processing
gen_connections: for i in 0 to TCP_CONNECTIONS-1 generate
    tcp_conn_inst: entity work.tcp_connection
        port map (
            clk => clk,
            rst_n => rst_n,
            
            -- Independent processing per connection
            rx_data => demux_rx_data(i),
            rx_valid => demux_rx_valid(i),
            rx_ready => demux_rx_ready(i),
            
            tx_data => mux_tx_data(i),
            tx_valid => mux_tx_valid(i),
            tx_ready => mux_tx_ready(i),
            
            -- Connection state
            connection_state => tcp_states(i),
            
            -- Configuration
            local_port => tcp_ports(i),
            remote_ip => remote_ips(i),
            remote_port => remote_ports(i)
        );
end generate;

-- Output multiplexer with priority
mux_proc: process(clk, rst_n)
begin
    if rst_n = '0' then
        output_select <= 0;
    elsif rising_edge(clk) then
        -- Round-robin arbitration
        if mux_tx_valid(output_select) = '1' and mux_tx_ready(output_select) = '1' then
            if mux_tx_last(output_select) = '1' then
                output_select <= (output_select + 1) mod TCP_CONNECTIONS;
            end if;
        else
            -- Find next valid connection
            for i in 1 to TCP_CONNECTIONS loop
                if mux_tx_valid((output_select + i) mod TCP_CONNECTIONS) = '1' then
                    output_select <= (output_select + i) mod TCP_CONNECTIONS;
                    exit;
                end if;
            end loop;
        end if;
    end if;
end process;
```

## 🛡️ Error Handling Architecture

### Hierarchical Error Management

```vhdl
-- Error reporting hierarchy
type error_vector_t is record
    -- Physical layer errors
    rgmii_crc_error    : std_logic;
    rgmii_align_error  : std_logic;
    rgmii_length_error : std_logic;
    
    -- MAC layer errors
    mac_frame_error    : std_logic;
    mac_buffer_overflow: std_logic;
    mac_underrun       : std_logic;
    
    -- IP layer errors
    ip_checksum_error  : std_logic;
    ip_version_error   : std_logic;
    ip_fragment_error  : std_logic;
    
    -- TCP layer errors
    tcp_checksum_error : std_logic;
    tcp_sequence_error : std_logic;
    tcp_connection_error: std_logic;
    
    -- System errors
    buffer_overflow    : std_logic;
    clock_error        : std_logic;
    configuration_error: std_logic;
end record;

signal error_status : error_vector_t;

-- Error collection and reporting
process(clk, rst_n)
begin
    if rst_n = '0' then
        error_status <= (others => '0');
        error_counter <= (others => '0');
    elsif rising_edge(clk) then
        -- Collect errors from all layers
        error_status.rgmii_crc_error <= rgmii_error_flag;
        error_status.mac_frame_error <= mac_error_flag;
        error_status.ip_checksum_error <= ip_error_flag;
        error_status.tcp_checksum_error <= tcp_error_flag;
        
        -- Count total errors
        if (error_status.rgmii_crc_error or 
            error_status.mac_frame_error or 
            error_status.ip_checksum_error or 
            error_status.tcp_checksum_error) = '1' then
            error_counter <= error_counter + 1;
        end if;
        
        -- Error LED indication
        error_led <= error_status.rgmii_crc_error or 
                    error_status.mac_frame_error or 
                    error_status.ip_checksum_error or 
                    error_status.tcp_checksum_error;
    end if;
end process;
```

### Recovery Mechanisms

```vhdl
-- Automatic error recovery
process(clk, rst_n)
begin
    if rst_n = '0' then
        recovery_state <= NORMAL;
        recovery_timer <= (others => '0');
    elsif rising_edge(clk) then
        case recovery_state is
            when NORMAL =>
                if error_status.buffer_overflow = '1' then
                    recovery_state <= FLUSH_BUFFERS;
                    recovery_timer <= to_unsigned(1000, recovery_timer'length); -- 1000 cycles
                elsif error_status.tcp_connection_error = '1' then
                    recovery_state <= RESET_CONNECTIONS;
                    recovery_timer <= to_unsigned(5000, recovery_timer'length); -- 5000 cycles
                end if;
            
            when FLUSH_BUFFERS =>
                -- Clear all buffers
                buffer_reset <= '1';
                if recovery_timer = 0 then
                    recovery_state <= NORMAL;
                    buffer_reset <= '0';
                else
                    recovery_timer <= recovery_timer - 1;
                end if;
            
            when RESET_CONNECTIONS =>
                -- Reset TCP connections
                tcp_reset <= '1';
                if recovery_timer = 0 then
                    recovery_state <= NORMAL;
                    tcp_reset <= '0';
                else
                    recovery_timer <= recovery_timer - 1;
                end if;
        end case;
    end if;
end process;
```

## 📊 Monitoring and Debug

### Built-in Logic Analyzer

```vhdl
-- Integrated debug capture
entity debug_capture is
    generic (
        CAPTURE_DEPTH : natural := 1024;
        DATA_WIDTH : natural := 64
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        
        -- Trigger conditions
        trigger_enable : in std_logic;
        trigger_pattern : in std_logic_vector(DATA_WIDTH-1 downto 0);
        trigger_mask : in std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Data to capture
        capture_data : in std_logic_vector(DATA_WIDTH-1 downto 0);
        capture_valid : in std_logic;
        
        -- Readout interface
        read_addr : in std_logic_vector(9 downto 0);
        read_data : out std_logic_vector(DATA_WIDTH-1 downto 0);
        read_valid : out std_logic;
        
        -- Status
        capture_armed : out std_logic;
        capture_triggered : out std_logic;
        capture_complete : out std_logic
    );
end entity;
```

### Performance Counters

```vhdl
-- Comprehensive performance monitoring
type performance_counters_t is record
    -- Packet counters
    tx_packets : unsigned(31 downto 0);
    rx_packets : unsigned(31 downto 0);
    tx_bytes : unsigned(63 downto 0);
    rx_bytes : unsigned(63 downto 0);
    
    -- Error counters
    crc_errors : unsigned(31 downto 0);
    frame_errors : unsigned(31 downto 0);
    buffer_overflows : unsigned(31 downto 0);
    
    -- TCP specific
    tcp_connections_opened : unsigned(31 downto 0);
    tcp_connections_closed : unsigned(31 downto 0);
    tcp_retransmissions : unsigned(31 downto 0);
    tcp_out_of_order : unsigned(31 downto 0);
    
    -- Latency measurements
    min_latency : unsigned(31 downto 0);
    max_latency : unsigned(31 downto 0);
    avg_latency : unsigned(31 downto 0);
end record;

signal perf_counters : performance_counters_t;

-- Counter update process
process(clk, rst_n)
begin
    if rst_n = '0' then
        perf_counters <= (others => (others => '0'));
    elsif rising_edge(clk) then
        -- Update packet counters
        if tx_packet_complete = '1' then
            perf_counters.tx_packets <= perf_counters.tx_packets + 1;
            perf_counters.tx_bytes <= perf_counters.tx_bytes + tx_packet_length;
        end if;
        
        if rx_packet_complete = '1' then
            perf_counters.rx_packets <= perf_counters.rx_packets + 1;
            perf_counters.rx_bytes <= perf_counters.rx_bytes + rx_packet_length;
        end if;
        
        -- Update error counters
        if crc_error_detected = '1' then
            perf_counters.crc_errors <= perf_counters.crc_errors + 1;
        end if;
        
        -- Update TCP counters
        if tcp_connection_established = '1' then
            perf_counters.tcp_connections_opened <= 
                perf_counters.tcp_connections_opened + 1;
        end if;
        
        if tcp_retransmit_triggered = '1' then
            perf_counters.tcp_retransmissions <= 
                perf_counters.tcp_retransmissions + 1;
        end if;
    end if;
end process;
```

This architecture document provides a comprehensive view of the TCP Offload Engine's internal structure, enabling effective implementation, debugging, and optimization for your specific FPGA platform and application requirements.