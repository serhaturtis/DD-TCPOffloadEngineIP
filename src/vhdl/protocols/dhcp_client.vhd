library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity dhcp_client is
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        
        -- UDP Interface
        udp_tx_data : out std_logic_vector(7 downto 0);
        udp_tx_valid : out std_logic;
        udp_tx_ready : in std_logic;
        udp_tx_last : out std_logic;
        udp_tx_start : out std_logic;
        
        udp_rx_data : in std_logic_vector(7 downto 0);
        udp_rx_valid : in std_logic;
        udp_rx_ready : out std_logic;
        udp_rx_last : in std_logic;
        
        -- Configuration Outputs
        assigned_ip : out std_logic_vector(31 downto 0);
        subnet_mask : out std_logic_vector(31 downto 0);
        gateway_ip : out std_logic_vector(31 downto 0);
        dns_server : out std_logic_vector(31 downto 0);
        lease_time : out std_logic_vector(31 downto 0);
        
        -- Control
        start_dhcp : in std_logic;
        renew_lease : in std_logic;
        release_lease : in std_logic;
        
        -- Status
        dhcp_complete : out std_logic;
        dhcp_error : out std_logic;
        dhcp_state : out std_logic_vector(7 downto 0);
        
        -- Hardware Configuration
        client_mac : in std_logic_vector(47 downto 0);
        client_id : in std_logic_vector(31 downto 0)
    );
end entity dhcp_client;

architecture rtl of dhcp_client is
    
    -- DHCP State Machine
    type dhcp_state_t is (
        DHCP_INIT,
        DHCP_SELECTING,
        DHCP_REQUESTING,
        DHCP_BOUND,
        DHCP_RENEWING,
        DHCP_REBINDING,
        DHCP_INIT_REBOOT,
        DHCP_ERR
    );
    signal dhcp_state_int : dhcp_state_t := DHCP_INIT;
    
    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_HEADER, TX_OPT, TX_SEND);
    signal tx_state : tx_state_t := TX_IDLE;
    
    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_HEADER, RX_OPT, RX_PROCESS);
    signal rx_state : rx_state_t := RX_IDLE;
    
    -- DHCP Message Structure (simplified)
    type dhcp_message_t is record
        op : std_logic_vector(7 downto 0);      -- Message type
        htype : std_logic_vector(7 downto 0);   -- Hardware type
        hlen : std_logic_vector(7 downto 0);    -- Hardware length
        hops : std_logic_vector(7 downto 0);    -- Hops
        xid : std_logic_vector(31 downto 0);    -- Transaction ID
        secs : std_logic_vector(15 downto 0);   -- Seconds
        flags : std_logic_vector(15 downto 0);  -- Flags
        ciaddr : std_logic_vector(31 downto 0); -- Client IP
        yiaddr : std_logic_vector(31 downto 0); -- Your IP
        siaddr : std_logic_vector(31 downto 0); -- Server IP
        giaddr : std_logic_vector(31 downto 0); -- Gateway IP
        chaddr : std_logic_vector(127 downto 0); -- Client hardware address
        sname : std_logic_vector(511 downto 0); -- Server name (64 bytes)
        boot_file : std_logic_vector(1023 downto 0); -- Boot file name (128 bytes)
        magic_cookie : std_logic_vector(31 downto 0); -- Magic cookie
    end record;
    
    -- DHCP Message Buffers
    signal tx_dhcp_msg : dhcp_message_t;
    signal rx_dhcp_msg : dhcp_message_t;
    
    -- DHCP Options
    type dhcp_options_array_t is array (0 to 255) of std_logic_vector(7 downto 0);
    signal tx_options_buf : dhcp_options_array_t := (others => (others => '0'));
    signal rx_options_buf : dhcp_options_array_t := (others => (others => '0'));
    signal tx_options_length : unsigned(7 downto 0) := (others => '0');
    signal rx_options_length : unsigned(7 downto 0) := (others => '0');
    
    -- Transmission counters
    signal tx_byte_count : unsigned(15 downto 0) := (others => '0');
    signal rx_byte_count : unsigned(15 downto 0) := (others => '0');
    signal tx_options_count : unsigned(7 downto 0) := (others => '0');
    signal rx_options_count : unsigned(7 downto 0) := (others => '0');
    
    -- Transaction ID
    signal transaction_id : std_logic_vector(31 downto 0) := x"12345678";
    
    -- Server information
    signal server_ip : std_logic_vector(31 downto 0) := (others => '0');
    signal offered_ip : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Lease information
    signal lease_time_int : std_logic_vector(31 downto 0) := (others => '0');
    signal renewal_time : std_logic_vector(31 downto 0) := (others => '0');
    signal rebind_time : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Timers
    signal lease_timer : unsigned(31 downto 0) := (others => '0');
    signal renewal_timer : unsigned(31 downto 0) := (others => '0');
    signal timeout_timer : unsigned(31 downto 0) := (others => '0');
    
    -- Status flags
    signal dhcp_complete_int : std_logic := '0';
    signal dhcp_error_int : std_logic := '0';
    
    -- Message type constants
    constant DHCP_DISCOVER : std_logic_vector(7 downto 0) := x"01";
    constant DHCP_OFFER : std_logic_vector(7 downto 0) := x"02";
    constant DHCP_REQUEST : std_logic_vector(7 downto 0) := x"03";
    constant DHCP_DECLINE : std_logic_vector(7 downto 0) := x"04";
    constant DHCP_ACK : std_logic_vector(7 downto 0) := x"05";
    constant DHCP_NAK : std_logic_vector(7 downto 0) := x"06";
    constant DHCP_RELEASE : std_logic_vector(7 downto 0) := x"07";
    constant DHCP_INFORM : std_logic_vector(7 downto 0) := x"08";
    
    -- Option type constants
    constant OPT_SUBNET_MASK : std_logic_vector(7 downto 0) := x"01";
    constant OPT_ROUTER : std_logic_vector(7 downto 0) := x"03";
    constant OPT_DNS_SERVER : std_logic_vector(7 downto 0) := x"06";
    constant OPT_LEASE_TIME : std_logic_vector(7 downto 0) := x"33";
    constant OPT_MESSAGE_TYPE : std_logic_vector(7 downto 0) := x"35";
    constant OPT_SERVER_ID : std_logic_vector(7 downto 0) := x"36";
    constant OPT_RENEWAL_TIME : std_logic_vector(7 downto 0) := x"3A";
    constant OPT_REBIND_TIME : std_logic_vector(7 downto 0) := x"3B";
    constant OPT_CLIENT_ID : std_logic_vector(7 downto 0) := x"3D";
    constant OPT_END : std_logic_vector(7 downto 0) := x"FF";
    
begin
    
    -- State encoding for output
    dhcp_state <= x"01" when dhcp_state_int = DHCP_INIT else
                  x"02" when dhcp_state_int = DHCP_SELECTING else
                  x"03" when dhcp_state_int = DHCP_REQUESTING else
                  x"04" when dhcp_state_int = DHCP_BOUND else
                  x"05" when dhcp_state_int = DHCP_RENEWING else
                  x"06" when dhcp_state_int = DHCP_REBINDING else
                  x"07" when dhcp_state_int = DHCP_INIT_REBOOT else
                  x"FF";
    
    -- Main DHCP State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            dhcp_state_int <= DHCP_INIT;
            dhcp_complete_int <= '0';
            dhcp_error_int <= '0';
            lease_timer <= (others => '0');
            renewal_timer <= (others => '0');
            timeout_timer <= (others => '0');
            transaction_id <= x"12345678";
        elsif rising_edge(clk) then
            -- Increment timers
            lease_timer <= lease_timer + 1;
            renewal_timer <= renewal_timer + 1;
            timeout_timer <= timeout_timer + 1;
            
            case dhcp_state_int is
                when DHCP_INIT =>
                    dhcp_complete_int <= '0';
                    dhcp_error_int <= '0';
                    if start_dhcp = '1' then
                        dhcp_state_int <= DHCP_SELECTING;
                        transaction_id <= std_logic_vector(unsigned(transaction_id) + 1);
                        timeout_timer <= (others => '0');
                        -- Trigger DISCOVER transmission
                    end if;
                
                when DHCP_SELECTING =>
                    -- Wait for OFFER
                    if timeout_timer = x"07735940" then -- 2 seconds timeout
                        dhcp_state_int <= DHCP_ERR;
                        dhcp_error_int <= '1';
                    elsif rx_state = RX_PROCESS then
                        -- Process received OFFER
                        dhcp_state_int <= DHCP_REQUESTING;
                        offered_ip <= rx_dhcp_msg.yiaddr;
                        timeout_timer <= (others => '0');
                    end if;
                
                when DHCP_REQUESTING =>
                    -- Wait for ACK
                    if timeout_timer = x"07735940" then -- 2 seconds timeout
                        dhcp_state_int <= DHCP_INIT;
                    elsif rx_state = RX_PROCESS then
                        -- Process received ACK
                        dhcp_state_int <= DHCP_BOUND;
                        dhcp_complete_int <= '1';
                        assigned_ip <= rx_dhcp_msg.yiaddr;
                        lease_timer <= (others => '0');
                        renewal_timer <= (others => '0');
                    end if;
                
                when DHCP_BOUND =>
                    -- Check for renewal time
                    if renewal_timer >= unsigned(renewal_time) then
                        dhcp_state_int <= DHCP_RENEWING;
                        timeout_timer <= (others => '0');
                    elsif renew_lease = '1' then
                        dhcp_state_int <= DHCP_RENEWING;
                        timeout_timer <= (others => '0');
                    elsif release_lease = '1' then
                        dhcp_state_int <= DHCP_INIT;
                        dhcp_complete_int <= '0';
                        -- Send RELEASE message
                    end if;
                
                when DHCP_RENEWING =>
                    -- Try to renew with original server
                    if timeout_timer = x"0EE6B280" then -- 4 seconds timeout
                        dhcp_state_int <= DHCP_REBINDING;
                        timeout_timer <= (others => '0');
                    elsif rx_state = RX_PROCESS then
                        dhcp_state_int <= DHCP_BOUND;
                        lease_timer <= (others => '0');
                        renewal_timer <= (others => '0');
                    end if;
                
                when DHCP_REBINDING =>
                    -- Try to rebind with any server
                    if timeout_timer = x"1DCD6500" then -- 8 seconds timeout
                        dhcp_state_int <= DHCP_INIT;
                        dhcp_complete_int <= '0';
                    elsif rx_state = RX_PROCESS then
                        dhcp_state_int <= DHCP_BOUND;
                        lease_timer <= (others => '0');
                        renewal_timer <= (others => '0');
                    end if;
                
                when DHCP_INIT_REBOOT =>
                    -- Not implemented in this simple version
                    dhcp_state_int <= DHCP_INIT;
                
                when DHCP_ERR =>
                    dhcp_error_int <= '1';
                    if start_dhcp = '1' then
                        dhcp_state_int <= DHCP_INIT;
                        dhcp_error_int <= '0';
                    end if;
            end case;
        end if;
    end process;
    
    -- TX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_state <= TX_IDLE;
            tx_byte_count <= (others => '0');
            tx_options_count <= (others => '0');
            udp_tx_valid <= '0';
            udp_tx_last <= '0';
            udp_tx_start <= '0';
        elsif rising_edge(clk) then
            case tx_state is
                when TX_IDLE =>
                    udp_tx_valid <= '0';
                    udp_tx_last <= '0';
                    udp_tx_start <= '0';
                    
                    if (dhcp_state_int = DHCP_SELECTING) or 
                       (dhcp_state_int = DHCP_REQUESTING) or
                       (dhcp_state_int = DHCP_RENEWING) or
                       (dhcp_state_int = DHCP_REBINDING) then
                        tx_state <= TX_HEADER;
                        tx_byte_count <= (others => '0');
                        
                        -- Build DHCP message
                        tx_dhcp_msg.op <= x"01"; -- BOOTREQUEST
                        tx_dhcp_msg.htype <= x"01"; -- Ethernet
                        tx_dhcp_msg.hlen <= x"06"; -- 6 bytes
                        tx_dhcp_msg.hops <= x"00";
                        tx_dhcp_msg.xid <= transaction_id;
                        tx_dhcp_msg.secs <= x"0000";
                        tx_dhcp_msg.flags <= x"8000"; -- Broadcast flag
                        tx_dhcp_msg.ciaddr <= (others => '0');
                        tx_dhcp_msg.yiaddr <= (others => '0');
                        tx_dhcp_msg.siaddr <= (others => '0');
                        tx_dhcp_msg.giaddr <= (others => '0');
                        tx_dhcp_msg.chaddr <= client_mac & x"00000000000000000000";
                        tx_dhcp_msg.sname <= (others => '0');
                        tx_dhcp_msg.boot_file <= (others => '0');
                        tx_dhcp_msg.magic_cookie <= DHCP_MAGIC_COOKIE;
                        
                        -- Build options
                        tx_options_count <= (others => '0');
                        tx_options_buf(0) <= OPT_MESSAGE_TYPE;
                        tx_options_buf(1) <= x"01"; -- Length
                        if dhcp_state_int = DHCP_SELECTING then
                            tx_options_buf(2) <= DHCP_DISCOVER;
                        else
                            tx_options_buf(2) <= DHCP_REQUEST;
                        end if;
                        tx_options_buf(3) <= OPT_CLIENT_ID;
                        tx_options_buf(4) <= x"07"; -- Length
                        tx_options_buf(5) <= x"01"; -- Hardware type
                        tx_options_buf(6) <= client_mac(47 downto 40);
                        tx_options_buf(7) <= client_mac(39 downto 32);
                        tx_options_buf(8) <= client_mac(31 downto 24);
                        tx_options_buf(9) <= client_mac(23 downto 16);
                        tx_options_buf(10) <= client_mac(15 downto 8);
                        tx_options_buf(11) <= client_mac(7 downto 0);
                        tx_options_buf(12) <= OPT_END;
                        tx_options_length <= to_unsigned(13, 8);
                        
                        udp_tx_start <= '1';
                    end if;
                
                when TX_HEADER =>
                    udp_tx_start <= '0';
                    if udp_tx_ready = '1' then
                        udp_tx_valid <= '1';
                        
                        -- Send DHCP header bytes sequentially
                        case tx_byte_count is
                            when x"0000" => udp_tx_data <= tx_dhcp_msg.op;
                            when x"0001" => udp_tx_data <= tx_dhcp_msg.htype;
                            when x"0002" => udp_tx_data <= tx_dhcp_msg.hlen;
                            when x"0003" => udp_tx_data <= tx_dhcp_msg.hops;
                            when x"0004" => udp_tx_data <= tx_dhcp_msg.xid(31 downto 24);
                            when x"0005" => udp_tx_data <= tx_dhcp_msg.xid(23 downto 16);
                            when x"0006" => udp_tx_data <= tx_dhcp_msg.xid(15 downto 8);
                            when x"0007" => udp_tx_data <= tx_dhcp_msg.xid(7 downto 0);
                            -- Continue for all header fields...
                            when x"00EC" => -- Start of magic cookie
                                udp_tx_data <= DHCP_MAGIC_COOKIE(31 downto 24);
                            when x"00ED" => 
                                udp_tx_data <= DHCP_MAGIC_COOKIE(23 downto 16);
                            when x"00EE" => 
                                udp_tx_data <= DHCP_MAGIC_COOKIE(15 downto 8);
                            when x"00EF" => 
                                udp_tx_data <= DHCP_MAGIC_COOKIE(7 downto 0);
                                tx_state <= TX_OPT;
                                tx_options_count <= (others => '0');
                            when others => 
                                udp_tx_data <= x"00"; -- Padding
                        end case;
                        
                        tx_byte_count <= tx_byte_count + 1;
                    end if;
                
                when TX_OPT =>
                    if udp_tx_ready = '1' then
                        udp_tx_data <= tx_options_buf(to_integer(tx_options_count));
                        udp_tx_valid <= '1';
                        
                        if tx_options_count = tx_options_length - 1 then
                            udp_tx_last <= '1';
                            tx_state <= TX_IDLE;
                        else
                            tx_options_count <= tx_options_count + 1;
                        end if;
                    end if;
                
                when TX_SEND =>
                    tx_state <= TX_IDLE;
            end case;
        end if;
    end process;
    
    -- RX State Machine (simplified)
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rx_state <= RX_IDLE;
            rx_byte_count <= (others => '0');
            udp_rx_ready <= '1';
        elsif rising_edge(clk) then
            case rx_state is
                when RX_IDLE =>
                    udp_rx_ready <= '1';
                    if udp_rx_valid = '1' then
                        rx_state <= RX_HEADER;
                        rx_byte_count <= (others => '0');
                    end if;
                
                when RX_HEADER =>
                    if udp_rx_valid = '1' then
                        -- Receive DHCP header
                        case rx_byte_count is
                            when x"0000" => rx_dhcp_msg.op <= udp_rx_data;
                            when x"0004" => rx_dhcp_msg.xid(31 downto 24) <= udp_rx_data;
                            when x"0005" => rx_dhcp_msg.xid(23 downto 16) <= udp_rx_data;
                            when x"0006" => rx_dhcp_msg.xid(15 downto 8) <= udp_rx_data;
                            when x"0007" => rx_dhcp_msg.xid(7 downto 0) <= udp_rx_data;
                            when x"0010" => rx_dhcp_msg.yiaddr(31 downto 24) <= udp_rx_data;
                            when x"0011" => rx_dhcp_msg.yiaddr(23 downto 16) <= udp_rx_data;
                            when x"0012" => rx_dhcp_msg.yiaddr(15 downto 8) <= udp_rx_data;
                            when x"0013" => rx_dhcp_msg.yiaddr(7 downto 0) <= udp_rx_data;
                            when x"00EF" => 
                                if udp_rx_data = DHCP_MAGIC_COOKIE(7 downto 0) then
                                    rx_state <= RX_OPT;
                                    rx_options_count <= (others => '0');
                                end if;
                            when others => null;
                        end case;
                        rx_byte_count <= rx_byte_count + 1;
                    end if;
                
                when RX_OPT =>
                    if udp_rx_valid = '1' then
                        rx_options_buf(to_integer(rx_options_count)) <= udp_rx_data;
                        rx_options_count <= rx_options_count + 1;
                        
                        if udp_rx_last = '1' then
                            rx_state <= RX_PROCESS;
                        end if;
                    end if;
                
                when RX_PROCESS =>
                    -- Process received options
                    rx_state <= RX_IDLE;
            end case;
        end if;
    end process;
    
    -- Output assignments
    dhcp_complete <= dhcp_complete_int;
    dhcp_error <= dhcp_error_int;
    lease_time <= lease_time_int;
    
end architecture rtl;