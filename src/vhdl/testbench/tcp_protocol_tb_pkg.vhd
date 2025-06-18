library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

package tcp_protocol_tb_pkg is
    
    -- Test configuration constants
    constant TEST_MAC_ADDR : std_logic_vector(47 downto 0) := x"001122334455";
    constant TEST_IP_ADDR : std_logic_vector(31 downto 0) := x"C0A80101"; -- 192.168.1.1
    constant REMOTE_MAC_ADDR : std_logic_vector(47 downto 0) := x"AABBCCDDEEFF";
    constant REMOTE_IP_ADDR : std_logic_vector(31 downto 0) := x"C0A80102"; -- 192.168.1.2
    constant GATEWAY_IP : std_logic_vector(31 downto 0) := x"C0A801FE"; -- 192.168.1.254
    constant SUBNET_MASK : std_logic_vector(31 downto 0) := x"FFFFFF00"; -- 255.255.255.0
    
    -- Protocol constants
    constant ETH_TYPE_IP : std_logic_vector(15 downto 0) := x"0800";
    constant ETH_TYPE_ARP : std_logic_vector(15 downto 0) := x"0806";
    constant IP_PROTO_ICMP : std_logic_vector(7 downto 0) := x"01";
    constant IP_PROTO_TCP : std_logic_vector(7 downto 0) := x"06";
    constant IP_PROTO_UDP : std_logic_vector(7 downto 0) := x"11";
    
    -- TCP flags
    constant TCP_FLAG_FIN : natural := 0;
    constant TCP_FLAG_SYN : natural := 1;
    constant TCP_FLAG_RST : natural := 2;
    constant TCP_FLAG_PSH : natural := 3;
    constant TCP_FLAG_ACK : natural := 4;
    constant TCP_FLAG_URG : natural := 5;
    
    -- Test results
    type test_result_t is (TEST_PASS, TEST_FAIL, TEST_TIMEOUT);
    
    -- Packet structures for testing
    type ethernet_header_t is record
        dst_mac : std_logic_vector(47 downto 0);
        src_mac : std_logic_vector(47 downto 0);
        eth_type : std_logic_vector(15 downto 0);
    end record;
    
    type ip_header_t is record
        version : std_logic_vector(3 downto 0);
        ihl : std_logic_vector(3 downto 0);
        tos : std_logic_vector(7 downto 0);
        length : std_logic_vector(15 downto 0);
        id : std_logic_vector(15 downto 0);
        flags : std_logic_vector(2 downto 0);
        frag_offset : std_logic_vector(12 downto 0);
        ttl : std_logic_vector(7 downto 0);
        protocol : std_logic_vector(7 downto 0);
        checksum : std_logic_vector(15 downto 0);
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
    end record;
    
    type tcp_header_t is record
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0);
        ack_num : std_logic_vector(31 downto 0);
        data_offset : std_logic_vector(3 downto 0);
        reserved : std_logic_vector(3 downto 0);
        flags : std_logic_vector(7 downto 0);
        window : std_logic_vector(15 downto 0);
        checksum : std_logic_vector(15 downto 0);
        urgent : std_logic_vector(15 downto 0);
    end record;
    
    type udp_header_t is record
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        length : std_logic_vector(15 downto 0);
        checksum : std_logic_vector(15 downto 0);
    end record;
    
    -- RGMII simulation types
    type rgmii_frame_t is record
        data : std_logic_vector(0 to 1023*8-1); -- Max frame size
        length : natural;
        valid : std_logic;
    end record;
    
    -- Test vector arrays
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
    
    -- Packet generation functions
    function generate_ethernet_header(
        dst_mac : std_logic_vector(47 downto 0);
        src_mac : std_logic_vector(47 downto 0);
        eth_type : std_logic_vector(15 downto 0)
    ) return byte_array_t;
    
    function generate_ip_header(
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        protocol : std_logic_vector(7 downto 0);
        payload_length : natural
    ) return byte_array_t;
    
    function generate_tcp_header(
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0);
        ack_num : std_logic_vector(31 downto 0);
        flags : std_logic_vector(7 downto 0);
        window : std_logic_vector(15 downto 0)
    ) return byte_array_t;
    
    function generate_udp_header(
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        payload_length : natural
    ) return byte_array_t;
    
    function generate_tcp_syn_packet(
        src_mac : std_logic_vector(47 downto 0);
        dst_mac : std_logic_vector(47 downto 0);
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0)
    ) return byte_array_t;
    
    function generate_tcp_synack_packet(
        src_mac : std_logic_vector(47 downto 0);
        dst_mac : std_logic_vector(47 downto 0);
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0);
        ack_num : std_logic_vector(31 downto 0)
    ) return byte_array_t;
    
    function generate_dhcp_discover(
        client_mac : std_logic_vector(47 downto 0);
        transaction_id : std_logic_vector(31 downto 0)
    ) return byte_array_t;
    
    function generate_dhcp_offer(
        client_mac : std_logic_vector(47 downto 0);
        transaction_id : std_logic_vector(31 downto 0);
        offered_ip : std_logic_vector(31 downto 0);
        server_ip : std_logic_vector(31 downto 0)
    ) return byte_array_t;
    
    -- Checksum calculation functions
    function calculate_ip_checksum(header : byte_array_t) return std_logic_vector;
    function calculate_tcp_checksum(
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        tcp_segment : byte_array_t
    ) return std_logic_vector;
    
    -- Validation functions
    function validate_ethernet_header(packet : byte_array_t; expected : ethernet_header_t) return boolean;
    function validate_ip_header(packet : byte_array_t; expected : ip_header_t) return boolean;
    function validate_tcp_header(packet : byte_array_t; expected : tcp_header_t) return boolean;
    
    -- RGMII simulation procedures
    procedure send_rgmii_frame(
        signal clk : in std_logic;
        signal txd : out std_logic_vector(3 downto 0);
        signal tx_ctl : out std_logic;
        frame_data : in byte_array_t
    );
    
    procedure receive_rgmii_frame(
        signal clk : in std_logic;
        signal rxd : in std_logic_vector(3 downto 0);
        signal rx_ctl : in std_logic;
        variable frame_data : out byte_array_t;
        variable frame_length : out natural;
        variable frame_valid : out boolean
    );
    
    -- Test reporting procedures
    procedure test_start(test_name : string);
    procedure test_pass(test_name : string);
    procedure test_fail(test_name : string; error_msg : string);
    procedure test_report_summary;
    
end package tcp_protocol_tb_pkg;

package body tcp_protocol_tb_pkg is
    
    -- Test tracking variables (made non-shared for VHDL-2008 compatibility)
    -- Note: In real implementation, these would be part of a protected type
    
    function generate_ethernet_header(
        dst_mac : std_logic_vector(47 downto 0);
        src_mac : std_logic_vector(47 downto 0);
        eth_type : std_logic_vector(15 downto 0)
    ) return byte_array_t is
        variable header : byte_array_t(0 to 13);
    begin
        -- Destination MAC (6 bytes)
        header(0) := dst_mac(47 downto 40);
        header(1) := dst_mac(39 downto 32);
        header(2) := dst_mac(31 downto 24);
        header(3) := dst_mac(23 downto 16);
        header(4) := dst_mac(15 downto 8);
        header(5) := dst_mac(7 downto 0);
        
        -- Source MAC (6 bytes)
        header(6) := src_mac(47 downto 40);
        header(7) := src_mac(39 downto 32);
        header(8) := src_mac(31 downto 24);
        header(9) := src_mac(23 downto 16);
        header(10) := src_mac(15 downto 8);
        header(11) := src_mac(7 downto 0);
        
        -- EtherType (2 bytes)
        header(12) := eth_type(15 downto 8);
        header(13) := eth_type(7 downto 0);
        
        return header;
    end function;
    
    function generate_ip_header(
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        protocol : std_logic_vector(7 downto 0);
        payload_length : natural
    ) return byte_array_t is
        variable header : byte_array_t(0 to 19);
        variable total_length : std_logic_vector(15 downto 0);
        variable checksum : std_logic_vector(15 downto 0);
    begin
        total_length := std_logic_vector(to_unsigned(20 + payload_length, 16));
        
        header(0) := x"45"; -- Version 4, IHL 5 (20 bytes)
        header(1) := x"00"; -- TOS
        header(2) := total_length(15 downto 8); -- Total length
        header(3) := total_length(7 downto 0);
        header(4) := x"00"; -- ID
        header(5) := x"01";
        header(6) := x"40"; -- Flags: Don't fragment
        header(7) := x"00"; -- Fragment offset
        header(8) := x"40"; -- TTL
        header(9) := protocol; -- Protocol
        header(10) := x"00"; -- Checksum (calculated later)
        header(11) := x"00";
        header(12) := src_ip(31 downto 24); -- Source IP
        header(13) := src_ip(23 downto 16);
        header(14) := src_ip(15 downto 8);
        header(15) := src_ip(7 downto 0);
        header(16) := dst_ip(31 downto 24); -- Destination IP
        header(17) := dst_ip(23 downto 16);
        header(18) := dst_ip(15 downto 8);
        header(19) := dst_ip(7 downto 0);
        
        -- Calculate checksum (simplified - would need proper implementation)
        checksum := calculate_ip_checksum(header);
        header(10) := checksum(15 downto 8);
        header(11) := checksum(7 downto 0);
        
        return header;
    end function;
    
    function generate_tcp_header(
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0);
        ack_num : std_logic_vector(31 downto 0);
        flags : std_logic_vector(7 downto 0);
        window : std_logic_vector(15 downto 0)
    ) return byte_array_t is
        variable header : byte_array_t(0 to 19);
    begin
        header(0) := src_port(15 downto 8); -- Source port
        header(1) := src_port(7 downto 0);
        header(2) := dst_port(15 downto 8); -- Destination port
        header(3) := dst_port(7 downto 0);
        header(4) := seq_num(31 downto 24); -- Sequence number
        header(5) := seq_num(23 downto 16);
        header(6) := seq_num(15 downto 8);
        header(7) := seq_num(7 downto 0);
        header(8) := ack_num(31 downto 24); -- Acknowledgment number
        header(9) := ack_num(23 downto 16);
        header(10) := ack_num(15 downto 8);
        header(11) := ack_num(7 downto 0);
        header(12) := x"50"; -- Data offset (5 words = 20 bytes)
        header(13) := flags; -- Flags
        header(14) := window(15 downto 8); -- Window size
        header(15) := window(7 downto 0);
        header(16) := x"00"; -- Checksum (calculated later)
        header(17) := x"00";
        header(18) := x"00"; -- Urgent pointer
        header(19) := x"00";
        
        return header;
    end function;
    
    function generate_udp_header(
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        payload_length : natural
    ) return byte_array_t is
        variable header : byte_array_t(0 to 7);
        variable udp_length : std_logic_vector(15 downto 0);
    begin
        udp_length := std_logic_vector(to_unsigned(payload_length + 8, 16));
        
        header(0) := src_port(15 downto 8); -- Source port
        header(1) := src_port(7 downto 0);
        header(2) := dst_port(15 downto 8); -- Destination port
        header(3) := dst_port(7 downto 0);
        header(4) := udp_length(15 downto 8); -- Length
        header(5) := udp_length(7 downto 0);
        header(6) := x"00"; -- Checksum (simplified)
        header(7) := x"00";
        
        return header;
    end function;
    
    function generate_dhcp_discover(
        client_mac : std_logic_vector(47 downto 0);
        transaction_id : std_logic_vector(31 downto 0)
    ) return byte_array_t is
        variable packet : byte_array_t(0 to 299); -- DHCP message
    begin
        packet(0) := x"01"; -- BOOTREQUEST
        packet(1) := x"01"; -- Ethernet
        packet(2) := x"06"; -- Hardware address length
        packet(3) := x"00"; -- Hops
        packet(4) := transaction_id(31 downto 24);
        packet(5) := transaction_id(23 downto 16);
        packet(6) := transaction_id(15 downto 8);
        packet(7) := transaction_id(7 downto 0);
        
        -- Fill rest with zeros for simplicity
        for i in 8 to 299 loop
            packet(i) := x"00";
        end loop;
        
        return packet;
    end function;
    
    function generate_dhcp_offer(
        client_mac : std_logic_vector(47 downto 0);
        transaction_id : std_logic_vector(31 downto 0);
        offered_ip : std_logic_vector(31 downto 0);
        server_ip : std_logic_vector(31 downto 0)
    ) return byte_array_t is
        variable packet : byte_array_t(0 to 299); -- DHCP message
    begin
        packet(0) := x"02"; -- BOOTREPLY
        packet(1) := x"01"; -- Ethernet
        packet(2) := x"06"; -- Hardware address length
        packet(3) := x"00"; -- Hops
        packet(4) := transaction_id(31 downto 24);
        packet(5) := transaction_id(23 downto 16);
        packet(6) := transaction_id(15 downto 8);
        packet(7) := transaction_id(7 downto 0);
        
        -- Fill rest with zeros for simplicity
        for i in 8 to 299 loop
            packet(i) := x"00";
        end loop;
        
        return packet;
    end function;
    
    function generate_tcp_syn_packet(
        src_mac : std_logic_vector(47 downto 0);
        dst_mac : std_logic_vector(47 downto 0);
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0)
    ) return byte_array_t is
        variable eth_header : byte_array_t(0 to 13);
        variable ip_header : byte_array_t(0 to 19);
        variable tcp_header : byte_array_t(0 to 19);
        variable packet : byte_array_t(0 to 53); -- 14 + 20 + 20 = 54 bytes
        variable flags : std_logic_vector(7 downto 0);
    begin
        -- Generate headers
        eth_header := generate_ethernet_header(dst_mac, src_mac, ETH_TYPE_IP);
        ip_header := generate_ip_header(src_ip, dst_ip, IP_PROTO_TCP, 20);
        
        -- TCP SYN flag
        flags := (TCP_FLAG_SYN => '1', others => '0');
        tcp_header := generate_tcp_header(src_port, dst_port, seq_num, x"00000000", flags, x"8000");
        
        -- Combine headers
        packet(0 to 13) := eth_header;
        packet(14 to 33) := ip_header;
        packet(34 to 53) := tcp_header;
        
        return packet;
    end function;
    
    function generate_tcp_synack_packet(
        src_mac : std_logic_vector(47 downto 0);
        dst_mac : std_logic_vector(47 downto 0);
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        src_port : std_logic_vector(15 downto 0);
        dst_port : std_logic_vector(15 downto 0);
        seq_num : std_logic_vector(31 downto 0);
        ack_num : std_logic_vector(31 downto 0)
    ) return byte_array_t is
        variable eth_header : byte_array_t(0 to 13);
        variable ip_header : byte_array_t(0 to 19);
        variable tcp_header : byte_array_t(0 to 19);
        variable packet : byte_array_t(0 to 53);
        variable flags : std_logic_vector(7 downto 0);
    begin
        -- Generate headers
        eth_header := generate_ethernet_header(dst_mac, src_mac, ETH_TYPE_IP);
        ip_header := generate_ip_header(src_ip, dst_ip, IP_PROTO_TCP, 20);
        
        -- TCP SYN+ACK flags
        flags := (TCP_FLAG_SYN => '1', TCP_FLAG_ACK => '1', others => '0');
        tcp_header := generate_tcp_header(src_port, dst_port, seq_num, ack_num, flags, x"8000");
        
        -- Combine headers
        packet(0 to 13) := eth_header;
        packet(14 to 33) := ip_header;
        packet(34 to 53) := tcp_header;
        
        return packet;
    end function;
    
    -- Simplified checksum functions (for demonstration)
    function calculate_ip_checksum(header : byte_array_t) return std_logic_vector is
    begin
        return x"0000"; -- Simplified - real implementation would calculate proper checksum
    end function;
    
    function calculate_tcp_checksum(
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        tcp_segment : byte_array_t
    ) return std_logic_vector is
    begin
        return x"0000"; -- Simplified - real implementation would calculate proper checksum
    end function;
    
    -- Validation functions (simplified)
    function validate_ethernet_header(packet : byte_array_t; expected : ethernet_header_t) return boolean is
    begin
        -- Validate destination MAC
        if packet(0) & packet(1) & packet(2) & packet(3) & packet(4) & packet(5) /= expected.dst_mac then
            return false;
        end if;
        -- Validate source MAC
        if packet(6) & packet(7) & packet(8) & packet(9) & packet(10) & packet(11) /= expected.src_mac then
            return false;
        end if;
        -- Validate EtherType
        if packet(12) & packet(13) /= expected.eth_type then
            return false;
        end if;
        return true;
    end function;
    
    function validate_ip_header(packet : byte_array_t; expected : ip_header_t) return boolean is
    begin
        -- Simplified validation - check key fields
        if packet(14) /= x"45" then -- Version + IHL
            return false;
        end if;
        if packet(23) /= expected.protocol then
            return false;
        end if;
        return true;
    end function;
    
    function validate_tcp_header(packet : byte_array_t; expected : tcp_header_t) return boolean is
    begin
        -- Simplified validation - check key fields
        if packet(34) & packet(35) /= expected.src_port then
            return false;
        end if;
        if packet(36) & packet(37) /= expected.dst_port then
            return false;
        end if;
        return true;
    end function;
    
    -- RGMII simulation procedures (simplified)
    procedure send_rgmii_frame(
        signal clk : in std_logic;
        signal txd : out std_logic_vector(3 downto 0);
        signal tx_ctl : out std_logic;
        frame_data : in byte_array_t
    ) is
    begin
        -- Simplified RGMII transmission
        tx_ctl <= '1';
        for i in 0 to frame_data'length-1 loop
            wait until rising_edge(clk);
            txd <= frame_data(i)(3 downto 0);
            wait until falling_edge(clk);
            txd <= frame_data(i)(7 downto 4);
        end loop;
        wait until rising_edge(clk);
        tx_ctl <= '0';
        txd <= "0000";
    end procedure;
    
    procedure receive_rgmii_frame(
        signal clk : in std_logic;
        signal rxd : in std_logic_vector(3 downto 0);
        signal rx_ctl : in std_logic;
        variable frame_data : out byte_array_t;
        variable frame_length : out natural;
        variable frame_valid : out boolean
    ) is
        variable byte_count : natural := 0;
    begin
        -- Simplified RGMII reception
        frame_length := 0;
        frame_valid := false;
        
        -- Wait for frame start
        wait until rx_ctl = '1';
        frame_valid := true;
        
        -- Receive frame data
        while rx_ctl = '1' and byte_count < frame_data'length loop
            wait until rising_edge(clk);
            frame_data(byte_count)(3 downto 0) := rxd;
            wait until falling_edge(clk);
            frame_data(byte_count)(7 downto 4) := rxd;
            byte_count := byte_count + 1;
        end loop;
        
        frame_length := byte_count;
    end procedure;
    
    -- Test reporting procedures (simplified without shared variables)
    procedure test_start(test_name : string) is
    begin
        report "====== Starting Test: " & test_name & " ======";
    end procedure;
    
    procedure test_pass(test_name : string) is
    begin
        report "PASS: " & test_name;
    end procedure;
    
    procedure test_fail(test_name : string; error_msg : string) is
    begin
        report "FAIL: " & test_name & " - " & error_msg severity error;
    end procedure;
    
    procedure test_report_summary is
    begin
        report "====== Test Summary ======";
        report "Check individual test results above";
    end procedure;
    
end package body tcp_protocol_tb_pkg;