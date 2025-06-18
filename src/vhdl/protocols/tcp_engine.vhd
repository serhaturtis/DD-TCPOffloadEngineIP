library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity tcp_engine is
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
        
        -- Application Interface
        app_tx_data : in std_logic_vector(63 downto 0);
        app_tx_keep : in std_logic_vector(7 downto 0);
        app_tx_valid : in std_logic;
        app_tx_ready : out std_logic;
        app_tx_last : in std_logic;
        app_connect : in std_logic;
        app_listen : in std_logic;
        app_close : in std_logic;
        app_port : in std_logic_vector(15 downto 0);
        app_remote_ip : in std_logic_vector(31 downto 0);
        app_remote_port : in std_logic_vector(15 downto 0);
        app_connection_id : in std_logic_vector(0 downto 0);
        
        app_rx_data : out std_logic_vector(63 downto 0);
        app_rx_keep : out std_logic_vector(7 downto 0);
        app_rx_valid : out std_logic;
        app_rx_ready : in std_logic;
        app_rx_last : out std_logic;
        app_connected : out std_logic;
        app_connection_error : out std_logic;
        
        -- Configuration
        local_ip : in std_logic_vector(31 downto 0);
        
        -- Status and Control
        tcp_status : out std_logic_vector(31 downto 0)
    );
end entity tcp_engine;

architecture rtl of tcp_engine is
    
    -- TCP Connection Table
    signal tcp_connections : tcp_connection_array_t := (others => (
        state => TCP_CLOSED,
        local_ip => (others => '0'),
        local_port => (others => '0'),
        remote_ip => (others => '0'),
        remote_port => (others => '0'),
        seq_num => (others => '0'),
        ack_num => (others => '0'),
        window_size => std_logic_vector(to_unsigned(TCP_WINDOW_SIZE, 16)),
        rcv_wnd => std_logic_vector(to_unsigned(TCP_WINDOW_SIZE, 16)),
        mss => std_logic_vector(to_unsigned(TCP_MSS, 16)),
        sack_permitted => '1',
        timestamp_enabled => '1',
        last_timestamp => (others => '0'),
        rto => x"00000FA0", -- 4000ms initial RTO
        cwnd => x"000005DC", -- 1 MSS initial congestion window
        ssthresh => x"0000FFFF" -- Large initial slow start threshold
    ));
    
    -- Current connection being processed
    signal current_conn : natural range 0 to 1 := 0;
    signal active_conn : natural range 0 to 1 := 0;
    signal tx_active_conn : natural range 0 to 1 := 0;
    signal rx_active_conn : natural range 0 to 1 := 0;
    signal rx_conn_valid : std_logic := '0';
    
    -- Connection management requests
    signal conn_req_valid : std_logic := '0';
    signal conn_req_id : natural range 0 to 1 := 0;
    signal conn_req_state : tcp_state_t := TCP_CLOSED;
    signal conn_req_type : std_logic_vector(1 downto 0) := "00"; -- 00: none, 01: TX, 10: RX
    
    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_HEADER, TX_OPTIONS, TX_PAYLOAD, TX_SEND);
    signal tx_state : tx_state_t := TX_IDLE;
    
    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_HEADER, RX_OPTIONS, RX_PAYLOAD, RX_PROCESS);
    signal rx_state : rx_state_t := RX_IDLE;
    
    -- TCP Header (20 bytes minimum)
    type tcp_header_array_t is array (0 to 19) of std_logic_vector(7 downto 0);
    signal tx_tcp_header : tcp_header_array_t := (others => (others => '0'));
    signal rx_tcp_header : tcp_header_array_t := (others => (others => '0'));
    signal tx_header_index : unsigned(4 downto 0) := (others => '0');
    signal rx_header_index : unsigned(4 downto 0) := (others => '0');
    
    -- TCP Options
    type tcp_options_array_t is array (0 to 39) of std_logic_vector(7 downto 0);
    signal tx_tcp_options : tcp_options_array_t := (others => (others => '0'));
    signal rx_tcp_options : tcp_options_array_t := (others => (others => '0'));
    signal tx_options_length : unsigned(5 downto 0) := (others => '0');
    signal rx_options_length : unsigned(5 downto 0) := (others => '0');
    signal tx_options_index : unsigned(5 downto 0) := (others => '0');
    signal rx_options_index : unsigned(5 downto 0) := (others => '0');
    
    -- Parsed RX Header Fields
    signal rx_src_port : std_logic_vector(15 downto 0);
    signal rx_dst_port : std_logic_vector(15 downto 0);
    signal rx_seq_num : std_logic_vector(31 downto 0);
    signal rx_ack_num : std_logic_vector(31 downto 0);
    signal rx_header_len : unsigned(3 downto 0);
    signal rx_flags : std_logic_vector(7 downto 0);
    signal rx_window : std_logic_vector(15 downto 0);
    signal rx_checksum : std_logic_vector(15 downto 0);
    signal rx_urgent : std_logic_vector(15 downto 0);
    
    -- Checksum calculation
    signal tx_checksum : unsigned(19 downto 0) := (others => '0');
    signal rx_checksum_calc : unsigned(19 downto 0) := (others => '0');
    signal checksum_valid : std_logic := '0';
    
    -- Timers (simplified - would use proper timer implementation)
    type timer_array_t is array (0 to 1) of unsigned(31 downto 0);
    signal retransmit_timers : timer_array_t := (others => (others => '0'));
    signal keepalive_timers : timer_array_t := (others => (others => '0'));
    signal time_wait_timers : timer_array_t := (others => (others => '0'));
    
    -- Congestion Control
    signal dup_ack_count : natural range 0 to 7 := 0;
    signal fast_recovery : std_logic := '0';
    signal slow_start : std_logic := '1';
    
    -- Segment Processing
    signal segment_acceptable : std_logic := '0';
    signal send_ack : std_logic := '0';
    signal send_rst : std_logic := '0';
    signal connection_match : std_logic := '0';
    signal listening_match : std_logic := '0';
    
    -- SACK Support
    type sack_block_t is record
        left_edge : std_logic_vector(31 downto 0);
        right_edge : std_logic_vector(31 downto 0);
        valid : std_logic;
    end record;
    type sack_blocks_array_t is array (0 to 3) of sack_block_t;
    signal sack_blocks : sack_blocks_array_t := (others => ((others => '0'), (others => '0'), '0'));
    
    -- Timestamp Support
    signal timestamp_val : std_logic_vector(31 downto 0) := (others => '0');
    signal timestamp_echo : std_logic_vector(31 downto 0) := (others => '0');
    signal timestamp_counter : unsigned(31 downto 0) := (others => '0');
    
    -- Error Handling and Monitoring
    signal error_status : error_status_t := (others => '0');
    signal error_counters : error_counter_t := (others => (others => '0'));
    signal performance_metrics : performance_metrics_t := (others => (others => '0'));
    signal recovery_action : recovery_action_t := RECOVER_NONE;
    signal error_mask : std_logic_vector(7 downto 0) := (others => '0');
    signal error_interrupt : std_logic := '0';
    
    -- Connection health monitoring
    type connection_health_t is record
        consecutive_timeouts : unsigned(3 downto 0);
        last_activity : unsigned(31 downto 0);
        rtt_samples : unsigned(31 downto 0);
        packet_loss_rate : unsigned(15 downto 0);
    end record;
    type connection_health_array_t is array (0 to 1) of connection_health_t;
    signal connection_health : connection_health_array_t := (others => ((others => '0'), (others => '0'), (others => '0'), (others => '0')));
    
    -- Functions
    function calculate_tcp_checksum(
        src_ip : std_logic_vector(31 downto 0);
        dst_ip : std_logic_vector(31 downto 0);
        header : tcp_header_array_t;
        options : tcp_options_array_t;
        options_len : natural;
        payload_len : natural
    ) return std_logic_vector is
        variable sum : unsigned(19 downto 0) := (others => '0');
        variable pseudo_header_sum : unsigned(19 downto 0) := (others => '0');
        variable result : std_logic_vector(15 downto 0);
    begin
        -- Pseudo header checksum
        pseudo_header_sum := unsigned(src_ip(31 downto 16)) + unsigned(src_ip(15 downto 0)) +
                           unsigned(dst_ip(31 downto 16)) + unsigned(dst_ip(15 downto 0)) +
                           to_unsigned(6, 16) + -- TCP protocol
                           to_unsigned(20 + options_len + payload_len, 16);
        
        sum := pseudo_header_sum;
        
        -- TCP header checksum (excluding checksum field)
        for i in 0 to 9 loop
            if i /= 8 then -- Skip checksum field
                sum := sum + unsigned(header(i*2)) * 256 + unsigned(header(i*2+1));
            end if;
        end loop;
        
        -- Options checksum
        if options_len > 0 then
            for i in 0 to (options_len/2) loop
                if (i*2+1) < options_len then
                    sum := sum + unsigned(options(i*2)) * 256 + unsigned(options(i*2+1));
                end if;
            end loop;
        end if;
        
        -- Add carry
        while sum(19 downto 16) /= 0 loop
            sum := sum(15 downto 0) + sum(19 downto 16);
        end loop;
        
        result := not std_logic_vector(sum(15 downto 0));
        return result;
    end function;
    
    function is_sequence_acceptable(
        seq : std_logic_vector(31 downto 0);
        rcv_nxt : std_logic_vector(31 downto 0);
        rcv_wnd : std_logic_vector(15 downto 0)
    ) return std_logic is
        variable seq_num : unsigned(31 downto 0);
        variable rcv_next : unsigned(31 downto 0);
        variable window : unsigned(15 downto 0);
    begin
        seq_num := unsigned(seq);
        rcv_next := unsigned(rcv_nxt);
        window := unsigned(rcv_wnd);
        
        if window = 0 then
            if seq_num = rcv_next then
                return '1';
            else
                return '0';
            end if;
        else
            if (seq_num >= rcv_next and seq_num < rcv_next + window) then
                return '1';
            else
                return '0';
            end if;
        end if;
    end function;
    
begin
    
    -- Timestamp counter
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            timestamp_counter <= (others => '0');
        elsif rising_edge(clk) then
            timestamp_counter <= timestamp_counter + 1;
        end if;
    end process;
    
    timestamp_val <= std_logic_vector(timestamp_counter);
    
    -- Active connection selection (RX has priority for connection processing)
    active_conn <= rx_active_conn when rx_conn_valid = '1' else tx_active_conn;
    
    -- TX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_state <= TX_IDLE;
            tx_header_index <= (others => '0');
            tx_options_index <= (others => '0');
            tx_options_length <= (others => '0');
            ip_tx_start <= '0';
            ip_tx_valid <= '0';
            ip_tx_last <= '0';
            app_tx_ready <= '0';
            current_conn <= 0;
            tx_active_conn <= 0;
        elsif rising_edge(clk) then
            case tx_state is
                when TX_IDLE =>
                    ip_tx_start <= '0';
                    ip_tx_valid <= '0';
                    ip_tx_last <= '0';
                    app_tx_ready <= '0';
                    
                    -- Check for application requests
                    if app_connect = '1' and app_connection_id /= "U" then
                        -- Initiate connection with bounds checking
                        if to_integer(unsigned(app_connection_id)) <= 1 then
                            tx_active_conn <= to_integer(unsigned(app_connection_id));
                            tcp_connections(to_integer(unsigned(app_connection_id))).state <= TCP_SYN_SENT;
                            tcp_connections(to_integer(unsigned(app_connection_id))).local_port <= app_port;
                            tcp_connections(to_integer(unsigned(app_connection_id))).remote_ip <= app_remote_ip;
                            tcp_connections(to_integer(unsigned(app_connection_id))).remote_port <= app_remote_port;
                            tcp_connections(to_integer(unsigned(app_connection_id))).seq_num <= x"12345678"; -- Random ISN
                            tx_state <= TX_HEADER;
                            current_conn <= to_integer(unsigned(app_connection_id));
                        end if;
                        
                        -- Build SYN packet
                        tx_tcp_header(0) <= app_port(15 downto 8);
                        tx_tcp_header(1) <= app_port(7 downto 0);
                        tx_tcp_header(2) <= app_remote_port(15 downto 8);
                        tx_tcp_header(3) <= app_remote_port(7 downto 0);
                        tx_tcp_header(4) <= x"12"; -- Sequence number
                        tx_tcp_header(5) <= x"34";
                        tx_tcp_header(6) <= x"56";
                        tx_tcp_header(7) <= x"78";
                        tx_tcp_header(8) <= x"00"; -- Ack number
                        tx_tcp_header(9) <= x"00";
                        tx_tcp_header(10) <= x"00";
                        tx_tcp_header(11) <= x"00";
                        tx_tcp_header(12) <= x"A0"; -- Header length (10 words) + Reserved
                        tx_tcp_header(13) <= x"02"; -- SYN flag
                        tx_tcp_header(14) <= tcp_connections(current_conn).window_size(15 downto 8);
                        tx_tcp_header(15) <= tcp_connections(current_conn).window_size(7 downto 0);
                        tx_tcp_header(16) <= x"00"; -- Checksum (calculated later)
                        tx_tcp_header(17) <= x"00";
                        tx_tcp_header(18) <= x"00"; -- Urgent pointer
                        tx_tcp_header(19) <= x"00";
                        
                        -- Add options for SYN
                        tx_tcp_options(0) <= x"02"; -- MSS option
                        tx_tcp_options(1) <= x"04"; -- Length
                        tx_tcp_options(2) <= tcp_connections(current_conn).mss(15 downto 8);
                        tx_tcp_options(3) <= tcp_connections(current_conn).mss(7 downto 0);
                        tx_tcp_options(4) <= x"04"; -- SACK permitted
                        tx_tcp_options(5) <= x"02";
                        tx_tcp_options(6) <= x"08"; -- Timestamp option
                        tx_tcp_options(7) <= x"0A";
                        tx_tcp_options(8) <= timestamp_val(31 downto 24);
                        tx_tcp_options(9) <= timestamp_val(23 downto 16);
                        tx_tcp_options(10) <= timestamp_val(15 downto 8);
                        tx_tcp_options(11) <= timestamp_val(7 downto 0);
                        tx_tcp_options(12) <= x"00"; -- Timestamp echo
                        tx_tcp_options(13) <= x"00";
                        tx_tcp_options(14) <= x"00";
                        tx_tcp_options(15) <= x"00";
                        tx_tcp_options(16) <= x"01"; -- NOP
                        tx_tcp_options(17) <= x"03"; -- Window scale
                        tx_tcp_options(18) <= x"03"; -- Length
                        tx_tcp_options(19) <= x"07"; -- Scale factor
                        tx_options_length <= to_unsigned(20, 6);
                        
                        -- Update header length
                        tx_tcp_header(12) <= x"F0"; -- 15 words (60 bytes total)
                        
                        -- Set up IP header
                        ip_tx_dst_ip <= app_remote_ip;
                        ip_tx_src_ip <= local_ip;
                        ip_tx_protocol <= IP_PROTO_TCP;
                        ip_tx_length <= x"003C"; -- 60 bytes
                        ip_tx_start <= '1';
                        
                    elsif app_listen = '1' and app_connection_id /= "U" then
                        -- Set up listening state with bounds checking
                        if to_integer(unsigned(app_connection_id)) <= 1 then
                            tcp_connections(to_integer(unsigned(app_connection_id))).state <= TCP_LISTEN;
                            tcp_connections(to_integer(unsigned(app_connection_id))).local_port <= app_port;
                        end if;
                        
                    elsif app_tx_valid = '1' and app_connection_id /= "U" then
                        -- Send data with bounds checking
                        if to_integer(unsigned(app_connection_id)) <= 1 and 
                           tcp_connections(to_integer(unsigned(app_connection_id))).state = TCP_ESTABLISHED then
                            tx_state <= TX_HEADER;
                            current_conn <= to_integer(unsigned(app_connection_id));
                        end if;
                        -- Build data packet...
                        
                    elsif send_ack = '1' or send_rst = '1' then
                        -- Send control packet
                        tx_state <= TX_HEADER;
                        -- Build control packet...
                    end if;
                
                when TX_HEADER =>
                    ip_tx_start <= '0';
                    if ip_tx_ready = '1' then
                        ip_tx_data <= tx_tcp_header(to_integer(tx_header_index));
                        ip_tx_valid <= '1';
                        
                        if tx_header_index = 19 then
                            if tx_options_length > 0 then
                                tx_state <= TX_OPTIONS;
                                tx_options_index <= (others => '0');
                            else
                                tx_state <= TX_PAYLOAD;
                                app_tx_ready <= '1';
                            end if;
                        else
                            tx_header_index <= tx_header_index + 1;
                        end if;
                    end if;
                
                when TX_OPTIONS =>
                    if ip_tx_ready = '1' then
                        ip_tx_data <= tx_tcp_options(to_integer(tx_options_index));
                        ip_tx_valid <= '1';
                        
                        if tx_options_index = tx_options_length - 1 then
                            tx_state <= TX_PAYLOAD;
                            app_tx_ready <= '1';
                        else
                            tx_options_index <= tx_options_index + 1;
                        end if;
                    end if;
                
                when TX_PAYLOAD =>
                    app_tx_ready <= ip_tx_ready;
                    if app_tx_valid = '1' and ip_tx_ready = '1' then
                        -- Convert 64-bit to 8-bit data
                        -- This is simplified - proper implementation would handle byte alignment
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
                
                when TX_SEND =>
                    tx_state <= TX_IDLE;
            end case;
        end if;
    end process;
    
    
    -- RX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rx_state <= RX_IDLE;
            rx_header_index <= (others => '0');
            rx_options_index <= (others => '0');
            rx_options_length <= (others => '0');
            ip_rx_ready <= '1';
            app_rx_valid <= '0';
            app_rx_last <= '0';
            app_connected <= '0';
            app_connection_error <= '0';
            connection_match <= '0';
            listening_match <= '0';
            send_ack <= '0';
            send_rst <= '0';
            rx_active_conn <= 0;
            rx_conn_valid <= '0';
        elsif rising_edge(clk) then
            case rx_state is
                when RX_IDLE =>
                    app_rx_valid <= '0';
                    app_rx_last <= '0';
                    send_ack <= '0';
                    send_rst <= '0';
                    connection_match <= '0';
                    listening_match <= '0';
                    rx_conn_valid <= '0';
                    
                    if ip_rx_frame_valid = '1' and ip_rx_protocol = IP_PROTO_TCP then
                        rx_state <= RX_HEADER;
                        rx_header_index <= (others => '0');
                    end if;
                
                when RX_HEADER =>
                    if ip_rx_valid = '1' then
                        rx_tcp_header(to_integer(rx_header_index)) <= ip_rx_data;
                        
                        -- Parse header fields as we receive them
                        case rx_header_index is
                            when "00000" => rx_src_port(15 downto 8) <= ip_rx_data;
                            when "00001" => rx_src_port(7 downto 0) <= ip_rx_data;
                            when "00010" => rx_dst_port(15 downto 8) <= ip_rx_data;
                            when "00011" => rx_dst_port(7 downto 0) <= ip_rx_data;
                            when "00100" => rx_seq_num(31 downto 24) <= ip_rx_data;
                            when "00101" => rx_seq_num(23 downto 16) <= ip_rx_data;
                            when "00110" => rx_seq_num(15 downto 8) <= ip_rx_data;
                            when "00111" => rx_seq_num(7 downto 0) <= ip_rx_data;
                            when "01000" => rx_ack_num(31 downto 24) <= ip_rx_data;
                            when "01001" => rx_ack_num(23 downto 16) <= ip_rx_data;
                            when "01010" => rx_ack_num(15 downto 8) <= ip_rx_data;
                            when "01011" => rx_ack_num(7 downto 0) <= ip_rx_data;
                            when "01100" => rx_header_len <= unsigned(ip_rx_data(7 downto 4));
                            when "01101" => rx_flags <= ip_rx_data;
                            when "01110" => rx_window(15 downto 8) <= ip_rx_data;
                            when "01111" => rx_window(7 downto 0) <= ip_rx_data;
                            when "10000" => rx_checksum(15 downto 8) <= ip_rx_data;
                            when "10001" => rx_checksum(7 downto 0) <= ip_rx_data;
                            when "10010" => rx_urgent(15 downto 8) <= ip_rx_data;
                            when "10011" => rx_urgent(7 downto 0) <= ip_rx_data;
                            when others => null;
                        end case;
                        
                        if rx_header_index = 19 then
                            -- Calculate options length with bounds checking
                            if ip_rx_data /= "UUUUUUUU" and unsigned(ip_rx_data(7 downto 4)) >= 5 then
                                rx_options_length <= to_unsigned((to_integer(unsigned(ip_rx_data(7 downto 4))) - 5) * 4, 6);
                            else
                                rx_options_length <= (others => '0');
                            end if;
                            
                            -- Check for connection match
                            for i in 0 to 1 loop
                                if tcp_connections(i).local_port = (rx_tcp_header(2) & ip_rx_data) and
                                   tcp_connections(i).remote_port = (rx_tcp_header(0) & rx_tcp_header(1)) and
                                   tcp_connections(i).remote_ip = ip_rx_src_ip and
                                   tcp_connections(i).state /= TCP_CLOSED then
                                    connection_match <= '1';
                                    rx_active_conn <= i;
                                    rx_conn_valid <= '1';
                                    exit;
                                end if;
                            end loop;
                            
                            -- Check for listening match
                            for i in 0 to 1 loop
                                if tcp_connections(i).local_port = (rx_tcp_header(2) & ip_rx_data) and
                                   tcp_connections(i).state = TCP_LISTEN then
                                    listening_match <= '1';
                                    rx_active_conn <= i;
                                    rx_conn_valid <= '1';
                                    exit;
                                end if;
                            end loop;
                            
                            if ip_rx_data /= "UUUUUUUU" and to_integer(unsigned(ip_rx_data(7 downto 4))) > 5 then
                                rx_state <= RX_OPTIONS;
                                rx_options_index <= (others => '0');
                            else
                                rx_state <= RX_PAYLOAD;
                            end if;
                        else
                            rx_header_index <= rx_header_index + 1;
                        end if;
                    end if;
                
                when RX_OPTIONS =>
                    if ip_rx_valid = '1' then
                        rx_tcp_options(to_integer(rx_options_index)) <= ip_rx_data;
                        
                        if rx_options_index = rx_options_length - 1 then
                            rx_state <= RX_PAYLOAD;
                        else
                            rx_options_index <= rx_options_index + 1;
                        end if;
                    end if;
                
                when RX_PAYLOAD =>
                    if ip_rx_valid = '1' and app_rx_ready = '1' then
                        -- Convert 8-bit to 64-bit data (simplified)
                        app_rx_data <= ip_rx_data & x"0000000000000";
                        app_rx_keep <= x"01";
                        app_rx_valid <= '1';
                        app_rx_last <= ip_rx_last;
                        
                        if ip_rx_last = '1' then
                            rx_state <= RX_PROCESS;
                        end if;
                    else
                        app_rx_valid <= '0';
                        app_rx_last <= '0';
                    end if;
                
                when RX_PROCESS =>
                    -- Process received segment based on TCP state machine
                    case tcp_connections(active_conn).state is
                        when TCP_LISTEN =>
                            if rx_flags(TCP_FLAG_SYN) = '1' and rx_flags(TCP_FLAG_ACK) = '0' then
                                -- SYN received, send SYN-ACK
                                -- tcp_connections(active_conn).state <= TCP_SYN_RCVD;
                                -- tcp_connections(active_conn).remote_ip <= ip_rx_src_ip;
                                -- tcp_connections(active_conn).remote_port <= rx_src_port;
                                -- tcp_connections(active_conn).ack_num <= std_logic_vector(unsigned(rx_seq_num) + 1);
                                send_ack <= '1';
                            end if;
                        
                        when TCP_SYN_SENT =>
                            if rx_flags(TCP_FLAG_SYN) = '1' and rx_flags(TCP_FLAG_ACK) = '1' then
                                -- SYN-ACK received
                                -- tcp_connections(active_conn).state <= TCP_ESTABLISHED;
                                -- tcp_connections(active_conn).ack_num <= std_logic_vector(unsigned(rx_seq_num) + 1);
                                app_connected <= '1';
                                send_ack <= '1';
                            elsif rx_flags(TCP_FLAG_SYN) = '1' then
                                -- Simultaneous open
                                -- tcp_connections(active_conn).state <= TCP_SYN_RCVD;
                                -- tcp_connections(active_conn).ack_num <= std_logic_vector(unsigned(rx_seq_num) + 1);
                                send_ack <= '1';
                            end if;
                        
                        when TCP_ESTABLISHED =>
                            if rx_flags(TCP_FLAG_FIN) = '1' then
                                -- tcp_connections(active_conn).state <= TCP_CLOSE_WAIT;
                                -- tcp_connections(active_conn).ack_num <= std_logic_vector(unsigned(rx_seq_num) + 1);
                                send_ack <= '1';
                            elsif rx_flags(TCP_FLAG_ACK) = '1' then
                                -- Update acknowledgment
                                -- tcp_connections(active_conn).ack_num <= rx_ack_num;
                            end if;
                        
                        when others =>
                            -- Handle other states
                            null;
                    end case;
                    
                    rx_state <= RX_IDLE;
                    rx_conn_valid <= '0';
            end case;
        end if;
    end process;
    
    -- Timer management (simplified)
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            retransmit_timers <= (others => (others => '0'));
            keepalive_timers <= (others => (others => '0'));
            time_wait_timers <= (others => (others => '0'));
        elsif rising_edge(clk) then
            for i in 0 to 1 loop
                if tcp_connections(i).state /= TCP_CLOSED then
                    retransmit_timers(i) <= retransmit_timers(i) + 1;
                    keepalive_timers(i) <= keepalive_timers(i) + 1;
                    
                    if tcp_connections(i).state = TCP_TIME_WAIT then
                        time_wait_timers(i) <= time_wait_timers(i) + 1;
                    end if;
                end if;
            end loop;
        end if;
    end process;
    
    -- Error Handling and Recovery Process
    process(clk, rst_n)
        variable checksum_calc : std_logic_vector(15 downto 0);
    begin
        if rst_n = '0' then
            error_status <= (others => '0');
            error_counters <= (others => (others => '0'));
            performance_metrics <= (others => (others => '0'));
            recovery_action <= RECOVER_NONE;
            error_interrupt <= '0';
            connection_health <= (others => ((others => '0'), (others => '0'), (others => '0'), (others => '0')));
        elsif rising_edge(clk) then
            -- Clear one-shot error flags
            error_status.checksum_error <= '0';
            error_status.malformed_packet <= '0';
            error_status.invalid_state_transition <= '0';
            error_interrupt <= '0';
            recovery_action <= RECOVER_NONE;
            
            -- RX Checksum validation
            if rx_state = RX_PROCESS and ip_rx_frame_valid = '1' then
                checksum_calc := calculate_tcp_checksum(
                    src_ip => ip_rx_src_ip,
                    dst_ip => ip_rx_dst_ip, 
                    header => rx_tcp_header,
                    options => rx_tcp_options,
                    options_len => to_integer(rx_options_length),
                    payload_len => 0
                );
                
                if checksum_calc /= rx_checksum then
                    error_status.checksum_error <= '1';
                    error_counters.rx_checksum_errors <= error_counters.rx_checksum_errors + 1;
                    error_counters.total_errors <= error_counters.total_errors + 1;
                    if error_mask(0) = '1' then
                        error_interrupt <= '1';
                    end if;
                    recovery_action <= RECOVER_RESET_CONNECTION;
                end if;
                
                -- Update performance metrics
                performance_metrics.packets_received <= performance_metrics.packets_received + 1;
                performance_metrics.bytes_received <= performance_metrics.bytes_received + unsigned(ip_rx_length);
            end if;
            
            -- TX Statistics
            if tx_state = TX_SEND and ip_tx_last = '1' then
                performance_metrics.packets_transmitted <= performance_metrics.packets_transmitted + 1;
                performance_metrics.bytes_transmitted <= performance_metrics.bytes_transmitted + unsigned(ip_tx_length);
            end if;
            
            -- Buffer overflow detection
            for i in 0 to 1 loop
                if tcp_connections(i).state /= TCP_CLOSED then
                    -- Update connection activity
                    connection_health(i).last_activity <= connection_health(i).last_activity + 1;
                    
                    -- Timeout detection
                    if retransmit_timers(i) > unsigned(tcp_connections(i).rto) then
                        connection_health(i).consecutive_timeouts <= connection_health(i).consecutive_timeouts + 1;
                        error_status.connection_timeout <= '1';
                        error_counters.connection_timeouts <= error_counters.connection_timeouts + 1;
                        error_counters.total_errors <= error_counters.total_errors + 1;
                        
                        if connection_health(i).consecutive_timeouts > 5 then
                            error_status.retransmit_limit <= '1';
                            error_counters.retransmit_timeouts <= error_counters.retransmit_timeouts + 1;
                            recovery_action <= RECOVER_RESET_CONNECTION;
                            if error_mask(7) = '1' then
                                error_interrupt <= '1';
                            end if;
                        else
                            recovery_action <= RECOVER_RETRANSMIT;
                        end if;
                        
                        if error_mask(2) = '1' then
                            error_interrupt <= '1';
                        end if;
                    end if;
                    
                    -- Reset timeout counter on activity
                    if send_ack = '1' or send_rst = '1' then
                        connection_health(i).consecutive_timeouts <= (others => '0');
                        connection_health(i).last_activity <= (others => '0');
                    end if;
                end if;
            end loop;
            
            -- Connection state transitions
            if app_connected = '1' then
                performance_metrics.connections_established <= performance_metrics.connections_established + 1;
            end if;
            
            -- PHY error detection (simplified)
            if ip_rx_frame_error = '1' then
                error_status.phy_error <= '1';
                error_counters.phy_errors <= error_counters.phy_errors + 1;
                error_counters.total_errors <= error_counters.total_errors + 1;
                if error_mask(5) = '1' then
                    error_interrupt <= '1';
                end if;
            end if;
        end if;
    end process;
    
    
    -- Status output
    tcp_status <= tcp_state_to_slv(tcp_connections(0).state) & 
                  tcp_state_to_slv(tcp_connections(1).state) & 
                  x"0000";
    
end architecture rtl;