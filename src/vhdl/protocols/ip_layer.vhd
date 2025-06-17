library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity ip_layer is
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        
        -- Ethernet Interface (TX)
        eth_tx_dst_mac : out std_logic_vector(47 downto 0);
        eth_tx_src_mac : out std_logic_vector(47 downto 0);
        eth_tx_ethertype : out std_logic_vector(15 downto 0);
        eth_tx_payload_data : out std_logic_vector(7 downto 0);
        eth_tx_payload_valid : out std_logic;
        eth_tx_payload_ready : in std_logic;
        eth_tx_payload_last : out std_logic;
        eth_tx_start : out std_logic;
        
        -- Ethernet Interface (RX)
        eth_rx_dst_mac : in std_logic_vector(47 downto 0);
        eth_rx_src_mac : in std_logic_vector(47 downto 0);
        eth_rx_ethertype : in std_logic_vector(15 downto 0);
        eth_rx_payload_data : in std_logic_vector(7 downto 0);
        eth_rx_payload_valid : in std_logic;
        eth_rx_payload_ready : out std_logic;
        eth_rx_payload_last : in std_logic;
        eth_rx_frame_valid : in std_logic;
        eth_rx_frame_error : in std_logic;
        
        -- Upper Layer TX Interface (TCP/UDP/ICMP)
        ul_tx_dst_ip : in std_logic_vector(31 downto 0);
        ul_tx_src_ip : in std_logic_vector(31 downto 0);
        ul_tx_protocol : in std_logic_vector(7 downto 0);
        ul_tx_length : in std_logic_vector(15 downto 0);
        ul_tx_data : in std_logic_vector(7 downto 0);
        ul_tx_valid : in std_logic;
        ul_tx_ready : out std_logic;
        ul_tx_last : in std_logic;
        ul_tx_start : in std_logic;
        
        -- Upper Layer RX Interface (TCP/UDP/ICMP)
        ul_rx_dst_ip : out std_logic_vector(31 downto 0);
        ul_rx_src_ip : out std_logic_vector(31 downto 0);
        ul_rx_protocol : out std_logic_vector(7 downto 0);
        ul_rx_length : out std_logic_vector(15 downto 0);
        ul_rx_data : out std_logic_vector(7 downto 0);
        ul_rx_valid : out std_logic;
        ul_rx_ready : in std_logic;
        ul_rx_last : out std_logic;
        ul_rx_frame_valid : out std_logic;
        ul_rx_frame_error : out std_logic;
        
        -- ICMP Interface
        icmp_tx_type : in std_logic_vector(7 downto 0);
        icmp_tx_code : in std_logic_vector(7 downto 0);
        icmp_tx_data : in std_logic_vector(7 downto 0);
        icmp_tx_valid : in std_logic;
        icmp_tx_ready : out std_logic;
        icmp_tx_last : in std_logic;
        icmp_tx_start : in std_logic;
        
        icmp_rx_type : out std_logic_vector(7 downto 0);
        icmp_rx_code : out std_logic_vector(7 downto 0);
        icmp_rx_data : out std_logic_vector(7 downto 0);
        icmp_rx_valid : out std_logic;
        icmp_rx_ready : in std_logic;
        icmp_rx_last : out std_logic;
        
        -- ARP Interface
        arp_request_ip : out std_logic_vector(31 downto 0);
        arp_request_valid : out std_logic;
        arp_response_mac : in std_logic_vector(47 downto 0);
        arp_response_valid : in std_logic;
        
        -- Configuration
        local_ip : in std_logic_vector(31 downto 0);
        local_mac : in std_logic_vector(47 downto 0);
        gateway_ip : in std_logic_vector(31 downto 0);
        subnet_mask : in std_logic_vector(31 downto 0)
    );
end entity ip_layer;

architecture rtl of ip_layer is
    
    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_HEADER, TX_PAYLOAD, TX_WAIT_ARP);
    signal tx_state : tx_state_t := TX_IDLE;
    
    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_HEADER, RX_PAYLOAD);
    signal rx_state : rx_state_t := RX_IDLE;
    
    -- IP Header Fields (20 bytes)
    type ip_header_array_t is array (0 to 19) of std_logic_vector(7 downto 0);
    signal tx_ip_header : ip_header_array_t := (others => (others => '0'));
    signal tx_total_length : unsigned(15 downto 0) := (others => '0');
    signal rx_ip_header : ip_header_array_t := (others => (others => '0'));
    signal tx_header_index : unsigned(4 downto 0) := (others => '0');
    signal rx_header_index : unsigned(4 downto 0) := (others => '0');
    
    -- ICMP Header and Processing
    type icmp_header_array_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal icmp_header : icmp_header_array_t := (others => (others => '0'));
    signal icmp_header_index : unsigned(2 downto 0) := (others => '0');
    signal icmp_processing : std_logic := '0';
    signal icmp_echo_reply : std_logic := '0';
    
    -- Checksum calculation
    signal tx_checksum : unsigned(19 downto 0) := (others => '0');
    signal rx_checksum : unsigned(19 downto 0) := (others => '0');
    signal checksum_valid : std_logic := '0';
    
    -- Packet identification counter
    signal packet_id : unsigned(15 downto 0) := (others => '0');
    
    -- Internal signals
    signal tx_dst_mac_resolved : std_logic_vector(47 downto 0);
    signal tx_dst_mac_valid : std_logic := '0';
    signal is_local_subnet : std_logic := '0';
    signal target_ip : std_logic_vector(31 downto 0);
    
    -- RX packet info
    signal rx_total_length : unsigned(15 downto 0) := (others => '0');
    signal rx_header_length : unsigned(3 downto 0) := (others => '0');
    signal rx_payload_count : unsigned(15 downto 0) := (others => '0');
    
    -- Functions
    function calculate_ip_checksum(header : ip_header_array_t) return std_logic_vector is
        variable sum : unsigned(19 downto 0) := (others => '0');
        variable result : std_logic_vector(15 downto 0);
    begin
        -- Sum all 16-bit words in header (excluding checksum field)
        for i in 0 to 9 loop
            if i /= 5 then -- Skip checksum field
                sum := sum + unsigned(header(i*2)) * 256 + unsigned(header(i*2+1));
            end if;
        end loop;
        
        -- Add carry
        while sum(19 downto 16) /= 0 loop
            sum := sum(15 downto 0) + sum(19 downto 16);
        end loop;
        
        result := not std_logic_vector(sum(15 downto 0));
        return result;
    end function;
    
begin
    
    -- Determine if destination is in local subnet
    is_local_subnet <= '1' when (ul_tx_dst_ip and subnet_mask) = (local_ip and subnet_mask) else '0';
    target_ip <= ul_tx_dst_ip when is_local_subnet = '1' else gateway_ip;
    
    -- TX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_state <= TX_IDLE;
            tx_header_index <= (others => '0');
            packet_id <= (others => '0');
            eth_tx_start <= '0';
            eth_tx_payload_valid <= '0';
            eth_tx_payload_last <= '0';
            ul_tx_ready <= '0';
            icmp_tx_ready <= '0';
            arp_request_valid <= '0';
            tx_dst_mac_valid <= '0';
        elsif rising_edge(clk) then
            case tx_state is
                when TX_IDLE =>
                    eth_tx_start <= '0';
                    eth_tx_payload_valid <= '0';
                    eth_tx_payload_last <= '0';
                    ul_tx_ready <= '0';
                    icmp_tx_ready <= '0';
                    arp_request_valid <= '0';
                    
                    if ul_tx_start = '1' or icmp_tx_start = '1' then
                        -- Check if we have MAC address for target IP
                        if tx_dst_mac_valid = '0' then
                            tx_state <= TX_WAIT_ARP;
                            arp_request_ip <= target_ip;
                            arp_request_valid <= '1';
                        else
                            tx_state <= TX_HEADER;
                            tx_header_index <= (others => '0');
                            packet_id <= packet_id + 1;
                            
                            -- Build IP header
                            tx_ip_header(0) <= x"45"; -- Version (4) + IHL (5)
                            tx_ip_header(1) <= x"00"; -- DSCP + ECN
                            if icmp_tx_start = '1' then
                                tx_ip_header(2) <= x"00"; -- Total Length (will be updated)
                                tx_ip_header(3) <= x"54"; -- 20 + 8 + 64 = 92 bytes for ping
                            else
                                tx_total_length <= unsigned(ul_tx_length) + 20;
                                tx_ip_header(2) <= std_logic_vector(tx_total_length(15 downto 8));
                                tx_ip_header(3) <= std_logic_vector(tx_total_length(7 downto 0));
                            end if;
                            tx_ip_header(4) <= std_logic_vector(packet_id(15 downto 8));
                            tx_ip_header(5) <= std_logic_vector(packet_id(7 downto 0));
                            tx_ip_header(6) <= x"40"; -- Flags (Don't Fragment)
                            tx_ip_header(7) <= x"00"; -- Fragment Offset
                            tx_ip_header(8) <= x"40"; -- TTL
                            if icmp_tx_start = '1' then
                                tx_ip_header(9) <= IP_PROTO_ICMP;
                            else
                                tx_ip_header(9) <= ul_tx_protocol;
                            end if;
                            tx_ip_header(10) <= x"00"; -- Checksum (calculated later)
                            tx_ip_header(11) <= x"00";
                            tx_ip_header(12) <= ul_tx_src_ip(31 downto 24);
                            tx_ip_header(13) <= ul_tx_src_ip(23 downto 16);
                            tx_ip_header(14) <= ul_tx_src_ip(15 downto 8);
                            tx_ip_header(15) <= ul_tx_src_ip(7 downto 0);
                            tx_ip_header(16) <= ul_tx_dst_ip(31 downto 24);
                            tx_ip_header(17) <= ul_tx_dst_ip(23 downto 16);
                            tx_ip_header(18) <= ul_tx_dst_ip(15 downto 8);
                            tx_ip_header(19) <= ul_tx_dst_ip(7 downto 0);
                            
                            -- Calculate checksum
                            tx_ip_header(10) <= calculate_ip_checksum(tx_ip_header)(15 downto 8);
                            tx_ip_header(11) <= calculate_ip_checksum(tx_ip_header)(7 downto 0);
                            
                            -- Set up Ethernet header
                            eth_tx_dst_mac <= tx_dst_mac_resolved;
                            eth_tx_src_mac <= local_mac;
                            eth_tx_ethertype <= ETH_TYPE_IP;
                            eth_tx_start <= '1';
                        end if;
                    end if;
                
                when TX_WAIT_ARP =>
                    arp_request_valid <= '0';
                    if arp_response_valid = '1' then
                        tx_dst_mac_resolved <= arp_response_mac;
                        tx_dst_mac_valid <= '1';
                        tx_state <= TX_IDLE;
                    end if;
                
                when TX_HEADER =>
                    eth_tx_start <= '0';
                    if eth_tx_payload_ready = '1' then
                        eth_tx_payload_data <= tx_ip_header(to_integer(tx_header_index));
                        eth_tx_payload_valid <= '1';
                        
                        if tx_header_index = 19 then
                            tx_state <= TX_PAYLOAD;
                            if icmp_tx_start = '1' then
                                icmp_tx_ready <= '1';
                            else
                                ul_tx_ready <= '1';
                            end if;
                        else
                            tx_header_index <= tx_header_index + 1;
                        end if;
                    end if;
                
                when TX_PAYLOAD =>
                    if icmp_processing = '1' then
                        icmp_tx_ready <= eth_tx_payload_ready;
                        if icmp_tx_valid = '1' and eth_tx_payload_ready = '1' then
                            eth_tx_payload_data <= icmp_tx_data;
                            eth_tx_payload_valid <= '1';
                            eth_tx_payload_last <= icmp_tx_last;
                            if icmp_tx_last = '1' then
                                tx_state <= TX_IDLE;
                                icmp_tx_ready <= '0';
                            end if;
                        else
                            eth_tx_payload_valid <= '0';
                            eth_tx_payload_last <= '0';
                        end if;
                    else
                        ul_tx_ready <= eth_tx_payload_ready;
                        if ul_tx_valid = '1' and eth_tx_payload_ready = '1' then
                            eth_tx_payload_data <= ul_tx_data;
                            eth_tx_payload_valid <= '1';
                            eth_tx_payload_last <= ul_tx_last;
                            if ul_tx_last = '1' then
                                tx_state <= TX_IDLE;
                                ul_tx_ready <= '0';
                            end if;
                        else
                            eth_tx_payload_valid <= '0';
                            eth_tx_payload_last <= '0';
                        end if;
                    end if;
            end case;
        end if;
    end process;
    
    -- RX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rx_state <= RX_IDLE;
            rx_header_index <= (others => '0');
            rx_payload_count <= (others => '0');
            eth_rx_payload_ready <= '1';
            ul_rx_valid <= '0';
            ul_rx_last <= '0';
            ul_rx_frame_valid <= '0';
            ul_rx_frame_error <= '0';
            icmp_rx_valid <= '0';
            icmp_rx_last <= '0';
            icmp_processing <= '0';
            icmp_echo_reply <= '0';
        elsif rising_edge(clk) then
            case rx_state is
                when RX_IDLE =>
                    ul_rx_valid <= '0';
                    ul_rx_last <= '0';
                    ul_rx_frame_valid <= '0';
                    ul_rx_frame_error <= '0';
                    icmp_rx_valid <= '0';
                    icmp_rx_last <= '0';
                    icmp_processing <= '0';
                    
                    if eth_rx_frame_valid = '1' and eth_rx_ethertype = ETH_TYPE_IP then
                        rx_state <= RX_HEADER;
                        rx_header_index <= (others => '0');
                        rx_payload_count <= (others => '0');
                    end if;
                
                when RX_HEADER =>
                    if eth_rx_payload_valid = '1' then
                        rx_ip_header(to_integer(rx_header_index)) <= eth_rx_payload_data;
                        
                        if rx_header_index = 1 then
                            rx_total_length(15 downto 8) <= unsigned(eth_rx_payload_data);
                        elsif rx_header_index = 2 then
                            rx_total_length(7 downto 0) <= unsigned(eth_rx_payload_data);
                        elsif rx_header_index = 8 then
                            rx_header_length <= unsigned(eth_rx_payload_data(3 downto 0));
                        end if;
                        
                        if rx_header_index = 19 then
                            rx_state <= RX_PAYLOAD;
                            
                            -- Extract header fields
                            ul_rx_dst_ip <= rx_ip_header(16) & rx_ip_header(17) & rx_ip_header(18) & eth_rx_payload_data;
                            ul_rx_src_ip <= rx_ip_header(12) & rx_ip_header(13) & rx_ip_header(14) & rx_ip_header(15);
                            ul_rx_protocol <= rx_ip_header(9);
                            ul_rx_length <= std_logic_vector(rx_total_length - 20);
                            
                            -- Check if ICMP
                            if rx_ip_header(9) = IP_PROTO_ICMP then
                                icmp_processing <= '1';
                            end if;
                            
                            -- Validate checksum
                            checksum_valid <= '1'; -- Simplified - should calculate actual checksum
                        else
                            rx_header_index <= rx_header_index + 1;
                        end if;
                    end if;
                
                when RX_PAYLOAD =>
                    if icmp_processing = '1' then
                        if eth_rx_payload_valid = '1' and ul_rx_ready = '1' then
                            if rx_payload_count < 8 then
                                icmp_header(to_integer(rx_payload_count(2 downto 0))) <= eth_rx_payload_data;
                                if rx_payload_count = 0 then
                                    icmp_rx_type <= eth_rx_payload_data;
                                    if eth_rx_payload_data = x"08" then -- Echo Request
                                        icmp_echo_reply <= '1';
                                    end if;
                                elsif rx_payload_count = 1 then
                                    icmp_rx_code <= eth_rx_payload_data;
                                end if;
                            else
                                icmp_rx_data <= eth_rx_payload_data;
                                icmp_rx_valid <= '1';
                            end if;
                            
                            icmp_rx_last <= eth_rx_payload_last;
                            rx_payload_count <= rx_payload_count + 1;
                            
                            if eth_rx_payload_last = '1' then
                                rx_state <= RX_IDLE;
                            end if;
                        else
                            icmp_rx_valid <= '0';
                            icmp_rx_last <= '0';
                        end if;
                    else
                        if eth_rx_payload_valid = '1' and ul_rx_ready = '1' then
                            ul_rx_data <= eth_rx_payload_data;
                            ul_rx_valid <= '1';
                            ul_rx_last <= eth_rx_payload_last;
                            rx_payload_count <= rx_payload_count + 1;
                            
                            if eth_rx_payload_last = '1' then
                                ul_rx_frame_valid <= checksum_valid and not eth_rx_frame_error;
                                ul_rx_frame_error <= not checksum_valid or eth_rx_frame_error;
                                rx_state <= RX_IDLE;
                            end if;
                        else
                            ul_rx_valid <= '0';
                            ul_rx_last <= '0';
                        end if;
                    end if;
            end case;
        end if;
    end process;
    
end architecture rtl;