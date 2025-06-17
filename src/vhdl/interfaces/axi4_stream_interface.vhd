library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity axi4_stream_interface is
    port (
        -- AXI4-Stream Clock and Reset
        aclk : in std_logic;
        aresetn : in std_logic;
        
        -- AXI4-Stream Master (TX) - Data from host to network
        m_axis_tx_tdata : out std_logic_vector(63 downto 0);
        m_axis_tx_tkeep : out std_logic_vector(7 downto 0);
        m_axis_tx_tvalid : out std_logic;
        m_axis_tx_tready : in std_logic;
        m_axis_tx_tlast : out std_logic;
        m_axis_tx_tuser : out std_logic_vector(7 downto 0);
        
        -- AXI4-Stream Slave (RX) - Data from network to host
        s_axis_rx_tdata : in std_logic_vector(63 downto 0);
        s_axis_rx_tkeep : in std_logic_vector(7 downto 0);
        s_axis_rx_tvalid : in std_logic;
        s_axis_rx_tready : out std_logic;
        s_axis_rx_tlast : in std_logic;
        s_axis_rx_tuser : in std_logic_vector(7 downto 0);
        
        -- Internal TCP Engine Interface (TX)
        tcp_tx_data : in std_logic_vector(63 downto 0);
        tcp_tx_keep : in std_logic_vector(7 downto 0);
        tcp_tx_valid : in std_logic;
        tcp_tx_ready : out std_logic;
        tcp_tx_last : in std_logic;
        tcp_connection_id : in std_logic_vector(0 downto 0);
        
        -- Internal TCP Engine Interface (RX)
        tcp_rx_data : out std_logic_vector(63 downto 0);
        tcp_rx_keep : out std_logic_vector(7 downto 0);
        tcp_rx_valid : out std_logic;
        tcp_rx_ready : in std_logic;
        tcp_rx_last : out std_logic;
        tcp_rx_connection_id : out std_logic_vector(0 downto 0);
        
        -- Control and Status
        stream_control : in std_logic_vector(31 downto 0);
        stream_status : out std_logic_vector(31 downto 0);
        
        -- Connection mapping
        connection_active : in std_logic_vector(1 downto 0);
        connection_ports : in std_logic_vector(31 downto 0)
    );
end entity axi4_stream_interface;

architecture rtl of axi4_stream_interface is
    
    -- TX Buffer for each connection
    component packet_buffer is
        generic (
            BUFFER_DEPTH : natural := 512;
            ADDR_WIDTH : natural := 9
        );
        port (
            clk : in std_logic;
            rst_n : in std_logic;
            wr_data : in std_logic_vector(63 downto 0);
            wr_keep : in std_logic_vector(7 downto 0);
            wr_last : in std_logic;
            wr_valid : in std_logic;
            wr_ready : out std_logic;
            rd_data : out std_logic_vector(63 downto 0);
            rd_keep : out std_logic_vector(7 downto 0);
            rd_last : out std_logic;
            rd_valid : out std_logic;
            rd_ready : in std_logic;
            buffer_reset : in std_logic;
            buffer_full : out std_logic;
            buffer_empty : out std_logic;
            buffer_count : out std_logic_vector(9 downto 0)
        );
    end component;
    
    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_CONN_0, TX_CONN_1, TX_ARBITRATE);
    signal tx_state : tx_state_t := TX_IDLE;
    
    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_HEADER, RX_PAYLOAD, RX_ROUTE);
    signal rx_state : rx_state_t := RX_IDLE;
    
    -- TX Buffers for each connection
    signal tx_buf_wr_data : std_logic_vector(63 downto 0);
    signal tx_buf_wr_keep : std_logic_vector(7 downto 0);
    signal tx_buf_wr_last : std_logic;
    signal tx_buf_wr_valid : std_logic_vector(1 downto 0);
    signal tx_buf_wr_ready : std_logic_vector(1 downto 0);
    
    -- Array types
    type axi4s_array_t is array(0 to 1) of axi4s_t;
    
    signal tx_buf_rd_data : axi4s_t;
    signal tx_buf_rd_data_arr : axi4s_array_t;
    signal tx_buf_rd_ready : std_logic_vector(1 downto 0);
    
    signal tx_buf_reset : std_logic_vector(1 downto 0);
    signal tx_buf_full : std_logic_vector(1 downto 0);
    signal tx_buf_empty : std_logic_vector(1 downto 0);
    type count_array_t is array(0 to 1) of std_logic_vector(9 downto 0);
    signal tx_buf_count : count_array_t;
    
    -- RX Buffers for each connection
    signal rx_buf_wr_data : std_logic_vector(63 downto 0);
    signal rx_buf_wr_keep : std_logic_vector(7 downto 0);
    signal rx_buf_wr_last : std_logic;
    signal rx_buf_wr_valid : std_logic_vector(1 downto 0);
    signal rx_buf_wr_ready : std_logic_vector(1 downto 0);
    
    signal rx_buf_rd_data : axi4s_array_t;
    signal rx_buf_rd_ready : std_logic_vector(1 downto 0);
    
    signal rx_buf_reset : std_logic_vector(1 downto 0);
    signal rx_buf_full : std_logic_vector(1 downto 0);
    signal rx_buf_empty : std_logic_vector(1 downto 0);
    signal rx_buf_count : count_array_t;
    
    -- Arbitration
    signal tx_arbiter_conn : natural range 0 to 1 := 0;
    signal rx_current_conn : natural range 0 to 1 := 0;
    signal tx_active_conn : std_logic_vector(1 downto 0) := "00";
    
    -- Packet header parsing
    signal rx_header_valid : std_logic := '0';
    signal rx_dest_port : std_logic_vector(15 downto 0);
    signal rx_payload_count : unsigned(15 downto 0) := (others => '0');
    
    -- Round-robin counter for TX arbitration
    signal tx_round_robin : unsigned(0 downto 0) := (others => '0');
    
    -- Stream control bits
    signal enable_stream : std_logic;
    signal reset_buffers : std_logic;
    signal loopback_mode : std_logic;
    
    -- Status counters
    signal tx_packet_count : unsigned(15 downto 0) := (others => '0');
    signal rx_packet_count : unsigned(15 downto 0) := (others => '0');
    signal tx_byte_count : unsigned(31 downto 0) := (others => '0');
    signal rx_byte_count : unsigned(31 downto 0) := (others => '0');
    
begin
    
    -- Extract control bits
    enable_stream <= stream_control(0);
    reset_buffers <= stream_control(1);
    loopback_mode <= stream_control(2);
    
    -- Status register
    stream_status <= std_logic_vector(tx_packet_count(15 downto 4)) & 
                    std_logic_vector(rx_packet_count(15 downto 4)) &
                    tx_buf_full & tx_buf_empty & 
                    rx_buf_full & rx_buf_empty;
    
    -- TX Buffers instantiation
    gen_tx_buffers: for i in 0 to 1 generate
        tx_buffer_inst: packet_buffer
            generic map (
                BUFFER_DEPTH => 512,
                ADDR_WIDTH => 9
            )
            port map (
                clk => aclk,
                rst_n => aresetn,
                wr_data => tx_buf_wr_data,
                wr_keep => tx_buf_wr_keep,
                wr_last => tx_buf_wr_last,
                wr_valid => tx_buf_wr_valid(i),
                wr_ready => tx_buf_wr_ready(i),
                rd_data => tx_buf_rd_data_arr(i).tdata,
                rd_keep => tx_buf_rd_data_arr(i).tkeep,
                rd_last => tx_buf_rd_data_arr(i).tlast,
                rd_valid => tx_buf_rd_data_arr(i).tvalid,
                rd_ready => tx_buf_rd_ready(i),
                buffer_reset => tx_buf_reset(i),
                buffer_full => tx_buf_full(i),
                buffer_empty => tx_buf_empty(i),
                buffer_count => tx_buf_count(i)
            );
            
        tx_buf_reset(i) <= reset_buffers or not aresetn;
    end generate;
    
    -- RX Buffers instantiation
    gen_rx_buffers: for i in 0 to 1 generate
        rx_buffer_inst: packet_buffer
            generic map (
                BUFFER_DEPTH => 512,
                ADDR_WIDTH => 9
            )
            port map (
                clk => aclk,
                rst_n => aresetn,
                wr_data => rx_buf_wr_data,
                wr_keep => rx_buf_wr_keep,
                wr_last => rx_buf_wr_last,
                wr_valid => rx_buf_wr_valid(i),
                wr_ready => rx_buf_wr_ready(i),
                rd_data => rx_buf_rd_data(i).tdata,
                rd_keep => rx_buf_rd_data(i).tkeep,
                rd_last => rx_buf_rd_data(i).tlast,
                rd_valid => rx_buf_rd_data(i).tvalid,
                rd_ready => rx_buf_rd_ready(i),
                buffer_reset => rx_buf_reset(i),
                buffer_full => rx_buf_full(i),
                buffer_empty => rx_buf_empty(i),
                buffer_count => rx_buf_count(i)
            );
            
        rx_buf_reset(i) <= reset_buffers or not aresetn;
    end generate;
    
    -- TX Buffer Write Interface (from TCP engine)
    tx_buf_wr_data <= tcp_tx_data;
    tx_buf_wr_keep <= tcp_tx_keep;
    tx_buf_wr_last <= tcp_tx_last;
    
    -- Route TX data to appropriate buffer based on connection ID
    process(tcp_connection_id, tcp_tx_valid)
        variable conn_id : natural;
    begin
        tx_buf_wr_valid <= (others => '0');
        if tcp_tx_valid = '1' and tcp_connection_id /= "U" then
            conn_id := to_integer(unsigned(tcp_connection_id));
            if conn_id <= 1 then
                tx_buf_wr_valid(conn_id) <= '1';
            end if;
        end if;
    end process;
    
    tcp_tx_ready <= tx_buf_wr_ready(to_integer(unsigned(tcp_connection_id))) when 
                    tcp_tx_valid = '1' and tcp_connection_id /= "U" and 
                    to_integer(unsigned(tcp_connection_id)) <= 1 else '0';
    
    -- TX Arbiter State Machine
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            tx_state <= TX_IDLE;
            tx_arbiter_conn <= 0;
            tx_round_robin <= (others => '0');
            tx_buf_rd_ready <= (others => '0');
            m_axis_tx_tvalid <= '0';
            m_axis_tx_tlast <= '0';
            tx_packet_count <= (others => '0');
            tx_byte_count <= (others => '0');
        elsif rising_edge(aclk) then
            case tx_state is
                when TX_IDLE =>
                    m_axis_tx_tvalid <= '0';
                    m_axis_tx_tlast <= '0';
                    tx_buf_rd_ready <= (others => '0');
                    
                    if enable_stream = '1' then
                        tx_state <= TX_ARBITRATE;
                    end if;
                
                when TX_ARBITRATE =>
                    -- Round-robin arbitration with bounds checking
                    if tx_round_robin <= 1 then
                        if tx_buf_empty(to_integer(tx_round_robin)) = '0' and 
                           connection_active(to_integer(tx_round_robin)) = '1' then
                            tx_arbiter_conn <= to_integer(tx_round_robin);
                            if tx_round_robin = 0 then
                                tx_state <= TX_CONN_0;
                            else
                                tx_state <= TX_CONN_1;
                            end if;
                            tx_buf_rd_ready(to_integer(tx_round_robin)) <= '1';
                        else
                            tx_round_robin <= tx_round_robin + 1;
                        end if;
                    else
                        tx_round_robin <= (others => '0');
                    end if;
                
                when TX_CONN_0 =>
                    if m_axis_tx_tready = '1' then
                        m_axis_tx_tdata <= tx_buf_rd_data_arr(0).tdata;
                        m_axis_tx_tkeep <= tx_buf_rd_data_arr(0).tkeep;
                        m_axis_tx_tvalid <= tx_buf_rd_data_arr(0).tvalid;
                        m_axis_tx_tlast <= tx_buf_rd_data_arr(0).tlast;
                        m_axis_tx_tuser <= x"00"; -- Connection 0
                        
                        if tx_buf_rd_data_arr(0).tvalid = '1' then
                            tx_byte_count <= tx_byte_count + 8; -- Simplified byte counting
                            
                            if tx_buf_rd_data_arr(0).tlast = '1' then
                                tx_state <= TX_ARBITRATE;
                                tx_buf_rd_ready(0) <= '0';
                                tx_packet_count <= tx_packet_count + 1;
                                tx_round_robin <= tx_round_robin + 1;
                            end if;
                        end if;
                    end if;
                
                when TX_CONN_1 =>
                    if m_axis_tx_tready = '1' then
                        m_axis_tx_tdata <= tx_buf_rd_data_arr(1).tdata;
                        m_axis_tx_tkeep <= tx_buf_rd_data_arr(1).tkeep;
                        m_axis_tx_tvalid <= tx_buf_rd_data_arr(1).tvalid;
                        m_axis_tx_tlast <= tx_buf_rd_data_arr(1).tlast;
                        m_axis_tx_tuser <= x"01"; -- Connection 1
                        
                        if tx_buf_rd_data_arr(1).tvalid = '1' then
                            tx_byte_count <= tx_byte_count + 8; -- Simplified byte counting
                            
                            if tx_buf_rd_data_arr(1).tlast = '1' then
                                tx_state <= TX_ARBITRATE;
                                tx_buf_rd_ready(1) <= '0';
                                tx_packet_count <= tx_packet_count + 1;
                                tx_round_robin <= tx_round_robin + 1;
                            end if;
                        end if;
                    end if;
            end case;
        end if;
    end process;
    
    -- RX State Machine
    process(aclk, aresetn)
    begin
        if aresetn = '0' then
            rx_state <= RX_IDLE;
            rx_current_conn <= 0;
            rx_buf_wr_valid <= (others => '0');
            s_axis_rx_tready <= '0';
            rx_packet_count <= (others => '0');
            rx_byte_count <= (others => '0');
            rx_payload_count <= (others => '0');
        elsif rising_edge(aclk) then
            case rx_state is
                when RX_IDLE =>
                    s_axis_rx_tready <= '1';
                    rx_buf_wr_valid <= (others => '0');
                    
                    if s_axis_rx_tvalid = '1' and enable_stream = '1' then
                        rx_state <= RX_HEADER;
                        rx_payload_count <= (others => '0');
                        -- Parse TUSER to determine connection with bounds checking
                        if s_axis_rx_tuser(0 downto 0) /= "U" then
                            if to_integer(unsigned(s_axis_rx_tuser(0 downto 0))) <= 1 then
                                rx_current_conn <= to_integer(unsigned(s_axis_rx_tuser(0 downto 0)));
                            else
                                rx_current_conn <= 0;
                            end if;
                        else
                            rx_current_conn <= 0;
                        end if;
                    end if;
                
                when RX_HEADER =>
                    if s_axis_rx_tvalid = '1' then
                        -- First data contains routing information
                        rx_dest_port <= s_axis_rx_tdata(15 downto 0);
                        rx_state <= RX_PAYLOAD;
                        rx_payload_count <= rx_payload_count + 1;
                    end if;
                
                when RX_PAYLOAD =>
                    s_axis_rx_tready <= rx_buf_wr_ready(rx_current_conn);
                    rx_buf_wr_data <= s_axis_rx_tdata;
                    rx_buf_wr_keep <= s_axis_rx_tkeep;
                    rx_buf_wr_last <= s_axis_rx_tlast;
                    rx_buf_wr_valid(rx_current_conn) <= s_axis_rx_tvalid;
                    
                    if s_axis_rx_tvalid = '1' and rx_buf_wr_ready(rx_current_conn) = '1' then
                        rx_byte_count <= rx_byte_count + 8; -- Simplified byte counting
                        rx_payload_count <= rx_payload_count + 1;
                        
                        if s_axis_rx_tlast = '1' then
                            rx_state <= RX_ROUTE;
                            rx_packet_count <= rx_packet_count + 1;
                        end if;
                    end if;
                
                when RX_ROUTE =>
                    rx_buf_wr_valid <= (others => '0');
                    rx_state <= RX_IDLE;
            end case;
        end if;
    end process;
    
    -- RX Buffer Read Interface (to TCP engine)
    -- Simplified: always read from connection 0 for this example
    tcp_rx_data <= rx_buf_rd_data(0).tdata;
    tcp_rx_keep <= rx_buf_rd_data(0).tkeep;
    tcp_rx_valid <= rx_buf_rd_data(0).tvalid;
    tcp_rx_last <= rx_buf_rd_data(0).tlast;
    tcp_rx_connection_id <= "0";
    
    rx_buf_rd_ready(0) <= tcp_rx_ready;
    rx_buf_rd_ready(1) <= '0'; -- Not used in this simplified version
    
end architecture rtl;