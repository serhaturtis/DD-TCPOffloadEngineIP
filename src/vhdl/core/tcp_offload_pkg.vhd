library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tcp_offload_pkg is
    
    -- Clock and Reset
    constant CLK_FREQ_HZ : natural := 125_000_000;
    constant RGMII_CLK_FREQ_HZ : natural := 125_000_000;
    
    -- Buffer Sizes
    constant TX_BUFFER_SIZE : natural := 4096;
    constant RX_BUFFER_SIZE : natural := 4096;
    constant TCP_CONNECTIONS : natural := 2;
    
    -- Ethernet Frame Constants
    constant ETH_HEADER_LEN : natural := 14;
    constant ETH_FCS_LEN : natural := 4;
    constant ETH_MIN_FRAME : natural := 64;
    constant ETH_MAX_FRAME : natural := 1518;
    constant ETH_TYPE_IP : std_logic_vector(15 downto 0) := x"0800";
    constant ETH_TYPE_ARP : std_logic_vector(15 downto 0) := x"0806";
    
    -- IP Constants
    constant IP_HEADER_LEN : natural := 20;
    constant IP_VERSION : std_logic_vector(3 downto 0) := x"4";
    constant IP_PROTO_ICMP : std_logic_vector(7 downto 0) := x"01";
    constant IP_PROTO_TCP : std_logic_vector(7 downto 0) := x"06";
    constant IP_PROTO_UDP : std_logic_vector(7 downto 0) := x"11";
    
    -- TCP Constants
    constant TCP_HEADER_LEN : natural := 20;
    constant TCP_MSS : natural := 1460;
    constant TCP_WINDOW_SIZE : natural := 4096;
    
    -- TCP Flags
    constant TCP_FLAG_FIN : natural := 0;
    constant TCP_FLAG_SYN : natural := 1;
    constant TCP_FLAG_RST : natural := 2;
    constant TCP_FLAG_PSH : natural := 3;
    constant TCP_FLAG_ACK : natural := 4;
    constant TCP_FLAG_URG : natural := 5;
    
    -- TCP States
    type tcp_state_t is (
        TCP_CLOSED,
        TCP_LISTEN,
        TCP_SYN_SENT,
        TCP_SYN_RCVD,
        TCP_ESTABLISHED,
        TCP_FIN_WAIT_1,
        TCP_FIN_WAIT_2,
        TCP_CLOSE_WAIT,
        TCP_CLOSING,
        TCP_LAST_ACK,
        TCP_TIME_WAIT
    );
    
    -- UDP Constants
    constant UDP_HEADER_LEN : natural := 8;
    
    -- DHCP Constants
    constant DHCP_SERVER_PORT : natural := 67;
    constant DHCP_CLIENT_PORT : natural := 68;
    constant DHCP_MAGIC_COOKIE : std_logic_vector(31 downto 0) := x"63825363";
    
    -- AXI4-Lite Address Map
    constant AXI_ADDR_WIDTH : natural := 32;
    constant AXI_DATA_WIDTH : natural := 32;
    
    -- Control Registers
    constant REG_CONTROL : std_logic_vector(31 downto 0) := x"00000000";
    constant REG_STATUS : std_logic_vector(31 downto 0) := x"00000004";
    constant REG_MAC_ADDR_LOW : std_logic_vector(31 downto 0) := x"00000008";
    constant REG_MAC_ADDR_HIGH : std_logic_vector(31 downto 0) := x"0000000C";
    constant REG_IP_ADDR : std_logic_vector(31 downto 0) := x"00000010";
    constant REG_SUBNET_MASK : std_logic_vector(31 downto 0) := x"00000014";
    constant REG_GATEWAY : std_logic_vector(31 downto 0) := x"00000018";
    constant REG_TCP_PORT_0 : std_logic_vector(31 downto 0) := x"0000001C";
    constant REG_TCP_PORT_1 : std_logic_vector(31 downto 0) := x"00000020";
    
    -- AXI4-Stream
    type axi4s_t is record
        tdata : std_logic_vector(63 downto 0);
        tkeep : std_logic_vector(7 downto 0);
        tlast : std_logic;
        tvalid : std_logic;
        tready : std_logic;
    end record;
    
    -- TCP Connection Record
    type tcp_connection_t is record
        state : tcp_state_t;
        local_ip : std_logic_vector(31 downto 0);
        local_port : std_logic_vector(15 downto 0);
        remote_ip : std_logic_vector(31 downto 0);
        remote_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0);
        ack_num : std_logic_vector(31 downto 0);
        window_size : std_logic_vector(15 downto 0);
        rcv_wnd : std_logic_vector(15 downto 0);
        mss : std_logic_vector(15 downto 0);
        sack_permitted : std_logic;
        timestamp_enabled : std_logic;
        last_timestamp : std_logic_vector(31 downto 0);
        rto : std_logic_vector(31 downto 0);
        cwnd : std_logic_vector(31 downto 0);
        ssthresh : std_logic_vector(31 downto 0);
    end record;
    
    type tcp_connection_array_t is array (0 to TCP_CONNECTIONS-1) of tcp_connection_t;
    
    -- Error Handling Types
    type error_status_t is record
        checksum_error : std_logic;
        buffer_overflow : std_logic;
        connection_timeout : std_logic;
        invalid_state_transition : std_logic;
        malformed_packet : std_logic;
        phy_error : std_logic;
        congestion_drop : std_logic;
        retransmit_limit : std_logic;
    end record;
    
    type error_counter_t is record
        rx_checksum_errors : unsigned(15 downto 0);
        tx_checksum_errors : unsigned(15 downto 0);
        buffer_overflows : unsigned(15 downto 0);
        connection_timeouts : unsigned(15 downto 0);
        invalid_transitions : unsigned(15 downto 0);
        malformed_packets : unsigned(15 downto 0);
        phy_errors : unsigned(15 downto 0);
        congestion_drops : unsigned(15 downto 0);
        retransmit_timeouts : unsigned(15 downto 0);
        total_errors : unsigned(31 downto 0);
    end record;
    
    -- Error Recovery Actions
    type recovery_action_t is (
        RECOVER_NONE,
        RECOVER_RESET_CONNECTION,
        RECOVER_RETRANSMIT,
        RECOVER_REDUCE_WINDOW,
        RECOVER_RESET_INTERFACE,
        RECOVER_SYSTEM_RESET
    );
    
    -- Performance Monitoring
    type performance_metrics_t is record
        packets_transmitted : unsigned(31 downto 0);
        packets_received : unsigned(31 downto 0);
        bytes_transmitted : unsigned(31 downto 0);
        bytes_received : unsigned(31 downto 0);
        connections_established : unsigned(15 downto 0);
        connections_closed : unsigned(15 downto 0);
        average_rtt : unsigned(31 downto 0);
        throughput_mbps : unsigned(31 downto 0);
    end record;
    
    -- Error register addresses
    constant REG_ERROR_STATUS : std_logic_vector(31 downto 0) := x"00000030";
    constant REG_ERROR_MASK : std_logic_vector(31 downto 0) := x"00000034";
    constant REG_ERROR_COUNTERS : std_logic_vector(31 downto 0) := x"00000038";
    constant REG_PERFORMANCE_METRICS : std_logic_vector(31 downto 0) := x"00000040";
    
    -- Packet Buffer Entry
    type packet_buffer_entry_t is record
        data : std_logic_vector(63 downto 0);
        keep : std_logic_vector(7 downto 0);
        last : std_logic;
        valid : std_logic;
    end record;
    
    -- Functions
    function reverse_bytes(input : std_logic_vector) return std_logic_vector;
    function calculate_checksum(data : std_logic_vector) return std_logic_vector;
    function tcp_state_to_slv(state : tcp_state_t) return std_logic_vector;
    
end package tcp_offload_pkg;

package body tcp_offload_pkg is
    
    function reverse_bytes(input : std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(input'range);
        variable byte_count : natural := input'length / 8;
    begin
        for i in 0 to byte_count-1 loop
            result((i+1)*8-1 downto i*8) := input((byte_count-i)*8-1 downto (byte_count-i-1)*8);
        end loop;
        return result;
    end function;
    
    function calculate_checksum(data : std_logic_vector) return std_logic_vector is
        variable sum : unsigned(31 downto 0) := (others => '0');
        variable result : std_logic_vector(15 downto 0);
        variable word_count : natural := data'length / 16;
    begin
        for i in 0 to word_count-1 loop
            sum := sum + unsigned(data((i+1)*16-1 downto i*16));
        end loop;
        
        while sum(31 downto 16) /= 0 loop
            sum := sum(15 downto 0) + sum(31 downto 16);
        end loop;
        
        result := not std_logic_vector(sum(15 downto 0));
        return result;
    end function;
    
    function tcp_state_to_slv(state : tcp_state_t) return std_logic_vector is
    begin
        case state is
            when TCP_CLOSED     => return x"00";
            when TCP_LISTEN     => return x"01";
            when TCP_SYN_SENT   => return x"02";
            when TCP_SYN_RCVD   => return x"03";
            when TCP_ESTABLISHED => return x"04";
            when TCP_FIN_WAIT_1 => return x"05";
            when TCP_FIN_WAIT_2 => return x"06";
            when TCP_CLOSE_WAIT => return x"07";
            when TCP_CLOSING    => return x"08";
            when TCP_LAST_ACK   => return x"09";
            when TCP_TIME_WAIT  => return x"0A";
            when others         => return x"FF";
        end case;
    end function;
    
end package body tcp_offload_pkg;