library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity udp_engine is
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        
        -- IP Layer Interface
        ip_tx_dst_ip : out std_logic_vector(31 downto 0);
        ip_tx_src_ip : out std_logic_vector(31 downto 0);
        ip_tx_protocol : out std_logic_vector(7 downto 0);
        ip_tx_length : out std_logic_vector(15 downto 0);
        ip_tx_data : out std_logic_vector(7 downto 0);
        ip_tx_valid : out std_logic;
        ip_tx_ready : in std_logic;
        ip_tx_last : out std_logic;
        ip_tx_start : out std_logic;
        
        ip_rx_dst_ip : in std_logic_vector(31 downto 0);
        ip_rx_src_ip : in std_logic_vector(31 downto 0);
        ip_rx_protocol : in std_logic_vector(7 downto 0);
        ip_rx_length : in std_logic_vector(15 downto 0);
        ip_rx_data : in std_logic_vector(7 downto 0);
        ip_rx_valid : in std_logic;
        ip_rx_ready : out std_logic;
        ip_rx_last : in std_logic;
        ip_rx_frame_valid : in std_logic;
        ip_rx_frame_error : in std_logic;
        
        -- Application TX Interface
        app_tx_dst_ip : in std_logic_vector(31 downto 0);
        app_tx_dst_port : in std_logic_vector(15 downto 0);
        app_tx_src_port : in std_logic_vector(15 downto 0);
        app_tx_data : in std_logic_vector(63 downto 0);
        app_tx_keep : in std_logic_vector(7 downto 0);
        app_tx_valid : in std_logic;
        app_tx_ready : out std_logic;
        app_tx_last : in std_logic;
        app_tx_start : in std_logic;
        
        -- Application RX Interface
        app_rx_src_ip : out std_logic_vector(31 downto 0);
        app_rx_src_port : out std_logic_vector(15 downto 0);
        app_rx_dst_port : out std_logic_vector(15 downto 0);
        app_rx_data : out std_logic_vector(63 downto 0);
        app_rx_keep : out std_logic_vector(7 downto 0);
        app_rx_valid : out std_logic;
        app_rx_ready : in std_logic;
        app_rx_last : out std_logic;
        app_rx_frame_valid : out std_logic;
        app_rx_frame_error : out std_logic;
        
        -- DHCP Interface
        dhcp_tx_data : in std_logic_vector(7 downto 0);
        dhcp_tx_valid : in std_logic;
        dhcp_tx_ready : out std_logic;
        dhcp_tx_last : in std_logic;
        dhcp_tx_start : in std_logic;
        
        dhcp_rx_data : out std_logic_vector(7 downto 0);
        dhcp_rx_valid : out std_logic;
        dhcp_rx_ready : in std_logic;
        dhcp_rx_last : out std_logic;
        
        -- Configuration
        local_ip : in std_logic_vector(31 downto 0)
    );
end entity udp_engine;

architecture rtl of udp_engine is
    
    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_SETUP, TX_CHECKSUM, TX_HEADER, TX_PAYLOAD, TX_SEND);
    signal tx_state : tx_state_t := TX_IDLE;
    
    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_HEADER, RX_PAYLOAD);
    signal rx_state : rx_state_t := RX_IDLE;
    
    -- UDP Header (8 bytes)
    type udp_header_array_t is array (0 to 7) of std_logic_vector(7 downto 0);
    signal tx_udp_header : udp_header_array_t := (others => (others => '0'));
    signal rx_udp_header : udp_header_array_t := (others => (others => '0'));
    signal tx_header_index : unsigned(2 downto 0) := (others => '0');
    signal rx_header_index : unsigned(2 downto 0) := (others => '0');
    
    -- Parsed RX Header Fields
    signal rx_src_port : std_logic_vector(15 downto 0);
    signal rx_dst_port : std_logic_vector(15 downto 0);
    signal rx_length : std_logic_vector(15 downto 0);
    signal rx_checksum : std_logic_vector(15 downto 0);
    
    -- Checksum calculation
    signal tx_checksum_calc : unsigned(19 downto 0) := (others => '0');
    signal rx_checksum_calc : unsigned(19 downto 0) := (others => '0');
    signal checksum_valid : std_logic := '0';
    
    -- Intermediate checksum signals
    signal tx_src_port_concat : std_logic_vector(15 downto 0);
    signal tx_dst_port_concat : std_logic_vector(15 downto 0);
    signal tx_length_concat : std_logic_vector(15 downto 0);
    
    -- Internal routing
    signal is_dhcp_packet : std_logic := '0';
    signal dhcp_tx_active : std_logic := '0';
    
    -- Payload length calculation
    signal tx_payload_length : unsigned(15 downto 0) := (others => '0');
    signal rx_payload_length : unsigned(15 downto 0) := (others => '0');
    signal tx_udp_length : unsigned(15 downto 0) := (others => '0');
    signal tx_checksum_result : std_logic_vector(15 downto 0) := (others => '0');
    signal rx_payload_count : unsigned(15 downto 0) := (others => '0');
    
    -- Functions
    function calculate_udp_checksum(
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        header : udp_header_array_t;
        payload_len : natural
    ) return std_logic_vector is
        variable sum : unsigned(19 downto 0) := (others => '0');
        variable pseudo_header_sum : unsigned(19 downto 0) := (others => '0');
        variable result : std_logic_vector(15 downto 0);
        variable safe_payload_len : natural;
        variable safe_src_ip : std_logic_vector(31 downto 0);
        variable safe_dst_ip : std_logic_vector(31 downto 0);
    begin
        -- Bounds check for payload length
        if payload_len > 65535 then
            safe_payload_len := 1472; -- Typical UDP payload size
        else
            safe_payload_len := payload_len;
        end if;
        
        -- Handle uninitialized IP addresses
        if src_ip = (src_ip'range => 'U') or src_ip = (src_ip'range => 'X') then
            safe_src_ip := (others => '0');
        else
            safe_src_ip := src_ip;
        end if;
        
        if dst_ip = (dst_ip'range => 'U') or dst_ip = (dst_ip'range => 'X') then
            safe_dst_ip := (others => '0');
        else
            safe_dst_ip := dst_ip;
        end if;
        
        -- Pseudo header checksum
        pseudo_header_sum := unsigned(safe_src_ip(31 downto 16)) + unsigned(safe_src_ip(15 downto 0)) +
                           unsigned(safe_dst_ip(31 downto 16)) + unsigned(safe_dst_ip(15 downto 0)) +
                           to_unsigned(17, 16) + -- UDP protocol
                           to_unsigned(8 + safe_payload_len, 16);
        
        sum := pseudo_header_sum;
        
        -- UDP header checksum (excluding checksum field)
        sum := sum + unsigned(header(0)) * 256 + unsigned(header(1)); -- Source port
        sum := sum + unsigned(header(2)) * 256 + unsigned(header(3)); -- Destination port
        sum := sum + unsigned(header(4)) * 256 + unsigned(header(5)); -- Length
        -- Skip checksum field (header(6) & header(7))
        
        -- Add carry
        while sum(19 downto 16) /= 0 loop
            sum := sum(15 downto 0) + sum(19 downto 16);
        end loop;
        
        result := not std_logic_vector(sum(15 downto 0));
        return result;
    end function;
    
    function count_payload_bytes(keep : std_logic_vector(7 downto 0)) return natural is
        variable count : natural := 0;
    begin
        for i in 0 to 7 loop
            if keep(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;
    
begin
    
    -- TX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_state <= TX_IDLE;
            tx_header_index <= (others => '0');
            tx_payload_length <= (others => '0');
            ip_tx_start <= '0';
            ip_tx_valid <= '0';
            ip_tx_last <= '0';
            app_tx_ready <= '0';
            dhcp_tx_ready <= '0';
            dhcp_tx_active <= '0';
        elsif rising_edge(clk) then
            case tx_state is
                when TX_IDLE =>
                    ip_tx_start <= '0';
                    ip_tx_valid <= '0';
                    ip_tx_last <= '0';
                    app_tx_ready <= '0';
                    dhcp_tx_ready <= '0';
                    dhcp_tx_active <= '0';
                    
                    if dhcp_tx_start = '1' then
                        -- DHCP packet transmission
                        dhcp_tx_active <= '1';
                        tx_state <= TX_SETUP;
                        tx_header_index <= (others => '0');
                        
                    elsif app_tx_start = '1' then
                        -- Application UDP packet transmission
                        tx_state <= TX_SETUP;
                        tx_header_index <= (others => '0');
                        
                        -- Calculate payload length (simplified)
                        tx_payload_length <= to_unsigned(1024, 16); -- Placeholder
                    end if;
                
                when TX_SETUP =>
                    if dhcp_tx_active = '1' then
                        -- Build UDP header for DHCP
                        tx_udp_header(0) <= std_logic_vector(to_unsigned(DHCP_CLIENT_PORT, 16)(15 downto 8));
                        tx_udp_header(1) <= std_logic_vector(to_unsigned(DHCP_CLIENT_PORT, 16)(7 downto 0));
                        tx_udp_header(2) <= std_logic_vector(to_unsigned(DHCP_SERVER_PORT, 16)(15 downto 8));
                        tx_udp_header(3) <= std_logic_vector(to_unsigned(DHCP_SERVER_PORT, 16)(7 downto 0));
                        tx_udp_header(4) <= x"01"; -- Length (will be calculated)
                        tx_udp_header(5) <= x"2C"; -- 300 bytes typical DHCP
                        tx_udp_header(6) <= x"00"; -- Checksum (will be calculated)
                        tx_udp_header(7) <= x"00";
                    else
                        -- Build UDP header for application
                        tx_udp_header(0) <= app_tx_src_port(15 downto 8);
                        tx_udp_header(1) <= app_tx_src_port(7 downto 0);
                        tx_udp_header(2) <= app_tx_dst_port(15 downto 8);
                        tx_udp_header(3) <= app_tx_dst_port(7 downto 0);
                        tx_udp_length <= tx_payload_length + 8;
                        tx_udp_header(4) <= std_logic_vector(tx_udp_length(15 downto 8));
                        tx_udp_header(5) <= std_logic_vector(tx_udp_length(7 downto 0));
                        tx_udp_header(6) <= x"00"; -- Checksum (will be calculated)
                        tx_udp_header(7) <= x"00";
                    end if;
                    tx_state <= TX_CHECKSUM;
                
                when TX_CHECKSUM =>
                    -- Prepare concatenated header fields
                    tx_src_port_concat <= tx_udp_header(0) & tx_udp_header(1);
                    tx_dst_port_concat <= tx_udp_header(2) & tx_udp_header(3);
                    tx_length_concat <= tx_udp_header(4) & tx_udp_header(5);
                    
                    -- Calculate proper UDP checksum
                    if dhcp_tx_active = '1' then
                        -- Calculate checksum for DHCP packet
                        -- UDP pseudo-header: src_ip(4) + dst_ip(4) + proto(1) + length(2) + udp_header(8)
                        tx_checksum_calc <= 
                            -- Source IP (local_ip)
                            unsigned(local_ip(31 downto 16)) + unsigned(local_ip(15 downto 0)) +
                            -- Destination IP (broadcast)
                            to_unsigned(16#FFFF#, 16) + to_unsigned(16#FFFF#, 16) +
                            -- Protocol (UDP = 17)
                            to_unsigned(17, 16) +
                            -- UDP length (300 bytes)
                            to_unsigned(300, 16) +
                            -- UDP header fields
                            unsigned(tx_src_port_concat) + -- src port
                            unsigned(tx_dst_port_concat) + -- dst port  
                            unsigned(tx_length_concat);  -- length
                        
                        -- Set up IP header for DHCP
                        ip_tx_dst_ip <= x"FFFFFFFF"; -- Broadcast
                        ip_tx_src_ip <= local_ip;
                        ip_tx_protocol <= IP_PROTO_UDP;
                        ip_tx_length <= x"012C"; -- 300 bytes
                    else
                        -- Calculate checksum for application packet
                        tx_checksum_calc <= 
                            -- Source IP
                            unsigned(local_ip(31 downto 16)) + unsigned(local_ip(15 downto 0)) +
                            -- Destination IP
                            unsigned(app_tx_dst_ip(31 downto 16)) + unsigned(app_tx_dst_ip(15 downto 0)) +
                            -- Protocol (UDP = 17)
                            to_unsigned(17, 16) +
                            -- UDP length
                            unsigned(tx_length_concat) +
                            -- UDP header fields
                            unsigned(tx_src_port_concat) + -- src port
                            unsigned(tx_dst_port_concat) + -- dst port
                            unsigned(tx_length_concat);  -- length
                        
                        -- Set up IP header for application
                        ip_tx_dst_ip <= app_tx_dst_ip;
                        ip_tx_src_ip <= local_ip;
                        ip_tx_protocol <= IP_PROTO_UDP;
                        ip_tx_length <= std_logic_vector(tx_payload_length + 28); -- UDP + IP headers
                    end if;
                    
                    tx_state <= TX_HEADER;
                
                when TX_HEADER =>
                    -- Calculate final checksum (one's complement)
                    -- Add carry bits and take one's complement
                    tx_checksum_result <= not std_logic_vector(tx_checksum_calc(15 downto 0) + 
                                                              resize(tx_checksum_calc(19 downto 16), 16));
                    
                    -- Update header with calculated checksum
                    tx_udp_header(6) <= tx_checksum_result(15 downto 8);
                    tx_udp_header(7) <= tx_checksum_result(7 downto 0);
                    
                    ip_tx_start <= '1';
                    tx_state <= TX_SEND;
                
                when TX_SEND =>
                    ip_tx_start <= '0';
                    if ip_tx_ready = '1' then
                        ip_tx_data <= tx_udp_header(to_integer(tx_header_index));
                        ip_tx_valid <= '1';
                        
                        if tx_header_index = 7 then
                            tx_state <= TX_PAYLOAD;
                            if dhcp_tx_active = '1' then
                                dhcp_tx_ready <= '1';
                            else
                                app_tx_ready <= '1';
                            end if;
                        else
                            tx_header_index <= tx_header_index + 1;
                        end if;
                    end if;
                
                when TX_PAYLOAD =>
                    if dhcp_tx_active = '1' then
                        dhcp_tx_ready <= ip_tx_ready;
                        if dhcp_tx_valid = '1' and ip_tx_ready = '1' then
                            ip_tx_data <= dhcp_tx_data;
                            ip_tx_valid <= '1';
                            ip_tx_last <= dhcp_tx_last;
                            if dhcp_tx_last = '1' then
                                tx_state <= TX_IDLE;
                                dhcp_tx_ready <= '0';
                                dhcp_tx_active <= '0';
                            end if;
                        else
                            ip_tx_valid <= '0';
                            ip_tx_last <= '0';
                        end if;
                    else
                        app_tx_ready <= ip_tx_ready;
                        if app_tx_valid = '1' and ip_tx_ready = '1' then
                            -- Convert 64-bit to 8-bit data (simplified)
                            ip_tx_data <= app_tx_data(7 downto 0);
                            ip_tx_valid <= '1';
                            ip_tx_last <= app_tx_last;
                            if app_tx_last = '1' then
                                tx_state <= TX_IDLE;
                                app_tx_ready <= '0';
                            end if;
                        else
                            ip_tx_valid <= '0';
                            ip_tx_last <= '0';
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
            ip_rx_ready <= '1';
            app_rx_valid <= '0';
            app_rx_last <= '0';
            app_rx_frame_valid <= '0';
            app_rx_frame_error <= '0';
            dhcp_rx_valid <= '0';
            dhcp_rx_last <= '0';
            is_dhcp_packet <= '0';
        elsif rising_edge(clk) then
            case rx_state is
                when RX_IDLE =>
                    app_rx_valid <= '0';
                    app_rx_last <= '0';
                    app_rx_frame_valid <= '0';
                    app_rx_frame_error <= '0';
                    dhcp_rx_valid <= '0';
                    dhcp_rx_last <= '0';
                    is_dhcp_packet <= '0';
                    
                    if ip_rx_frame_valid = '1' and ip_rx_protocol = IP_PROTO_UDP then
                        rx_state <= RX_HEADER;
                        rx_header_index <= (others => '0');
                        rx_payload_count <= (others => '0');
                    end if;
                
                when RX_HEADER =>
                    if ip_rx_valid = '1' then
                        rx_udp_header(to_integer(rx_header_index)) <= ip_rx_data;
                        
                        -- Parse header fields as we receive them
                        case rx_header_index is
                            when "000" => rx_src_port(15 downto 8) <= ip_rx_data;
                            when "001" => rx_src_port(7 downto 0) <= ip_rx_data;
                            when "010" => rx_dst_port(15 downto 8) <= ip_rx_data;
                            when "011" => 
                                rx_dst_port(7 downto 0) <= ip_rx_data;
                                -- Check if this is a DHCP packet with valid data
                                if rx_udp_header(2) /= "UUUUUUUU" and ip_rx_data /= "UUUUUUUU" then
                                    if (unsigned(rx_udp_header(2)) * 256 + unsigned(ip_rx_data)) = DHCP_CLIENT_PORT or
                                       (unsigned(rx_udp_header(2)) * 256 + unsigned(ip_rx_data)) = DHCP_SERVER_PORT then
                                        is_dhcp_packet <= '1';
                                    end if;
                                end if;
                            when "100" => rx_length(15 downto 8) <= ip_rx_data;
                            when "101" => 
                                rx_length(7 downto 0) <= ip_rx_data;
                                -- Calculate payload length with valid data check
                                if rx_udp_header(4) /= "UUUUUUUU" and ip_rx_data /= "UUUUUUUU" then
                                    rx_payload_length <= (unsigned(rx_udp_header(4)) * 256 + unsigned(ip_rx_data)) - 8;
                                else
                                    rx_payload_length <= (others => '0');
                                end if;
                            when "110" => rx_checksum(15 downto 8) <= ip_rx_data;
                            when "111" => rx_checksum(7 downto 0) <= ip_rx_data;
                            when others => null;
                        end case;
                        
                        if rx_header_index = 7 then
                            rx_state <= RX_PAYLOAD;
                            
                            -- Set up output header fields
                            app_rx_src_ip <= ip_rx_src_ip;
                            app_rx_src_port <= rx_src_port;
                            app_rx_dst_port <= rx_udp_header(2) & ip_rx_data;
                            
                            -- Validate checksum (simplified)
                            checksum_valid <= '1';
                        else
                            rx_header_index <= rx_header_index + 1;
                        end if;
                    end if;
                
                when RX_PAYLOAD =>
                    if is_dhcp_packet = '1' then
                        if ip_rx_valid = '1' and app_rx_ready = '1' then
                            dhcp_rx_data <= ip_rx_data;
                            dhcp_rx_valid <= '1';
                            dhcp_rx_last <= ip_rx_last;
                            rx_payload_count <= rx_payload_count + 1;
                            
                            if ip_rx_last = '1' then
                                rx_state <= RX_IDLE;
                            end if;
                        else
                            dhcp_rx_valid <= '0';
                            dhcp_rx_last <= '0';
                        end if;
                    else
                        if ip_rx_valid = '1' and app_rx_ready = '1' then
                            -- Convert 8-bit to 64-bit data (simplified)
                            app_rx_data <= ip_rx_data & x"0000000000000";
                            app_rx_keep <= x"01";
                            app_rx_valid <= '1';
                            app_rx_last <= ip_rx_last;
                            rx_payload_count <= rx_payload_count + 1;
                            
                            if ip_rx_last = '1' then
                                app_rx_frame_valid <= checksum_valid and not ip_rx_frame_error;
                                app_rx_frame_error <= not checksum_valid or ip_rx_frame_error;
                                rx_state <= RX_IDLE;
                            end if;
                        else
                            app_rx_valid <= '0';
                            app_rx_last <= '0';
                        end if;
                    end if;
            end case;
        end if;
    end process;
    
end architecture rtl;