library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity ethernet_mac is
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        
        -- PHY Interface
        phy_tx_data : out std_logic_vector(7 downto 0);
        phy_tx_valid : out std_logic;
        phy_tx_ready : in std_logic;
        phy_tx_last : out std_logic;
        phy_tx_error : out std_logic;
        
        phy_rx_data : in std_logic_vector(7 downto 0);
        phy_rx_valid : in std_logic;
        phy_rx_ready : out std_logic;
        phy_rx_last : in std_logic;
        phy_rx_error : in std_logic;
        
        -- Upper Layer TX Interface
        tx_dst_mac : in std_logic_vector(47 downto 0);
        tx_src_mac : in std_logic_vector(47 downto 0);
        tx_ethertype : in std_logic_vector(15 downto 0);
        tx_payload_data : in std_logic_vector(7 downto 0);
        tx_payload_valid : in std_logic;
        tx_payload_ready : out std_logic;
        tx_payload_last : in std_logic;
        tx_start : in std_logic;
        
        -- Upper Layer RX Interface
        rx_dst_mac : out std_logic_vector(47 downto 0);
        rx_src_mac : out std_logic_vector(47 downto 0);
        rx_ethertype : out std_logic_vector(15 downto 0);
        rx_payload_data : out std_logic_vector(7 downto 0);
        rx_payload_valid : out std_logic;
        rx_payload_ready : in std_logic;
        rx_payload_last : out std_logic;
        rx_frame_valid : out std_logic;
        rx_frame_error : out std_logic;
        
        -- Configuration
        local_mac : in std_logic_vector(47 downto 0);
        promiscuous_mode : in std_logic
    );
end entity ethernet_mac;

architecture rtl of ethernet_mac is
    
    -- TX State Machine
    type tx_state_t is (TX_IDLE, TX_PREAMBLE, TX_SFD, TX_HEADER, TX_PAYLOAD, TX_FCS, TX_IFG);
    signal tx_state : tx_state_t := TX_IDLE;
    signal tx_byte_count : unsigned(15 downto 0) := (others => '0');
    signal tx_bit_count : unsigned(2 downto 0) := (others => '0');
    
    -- RX State Machine
    type rx_state_t is (RX_IDLE, RX_PREAMBLE, RX_SFD, RX_HEADER, RX_PAYLOAD, RX_FCS);
    signal rx_state : rx_state_t := RX_IDLE;
    signal rx_byte_count : unsigned(15 downto 0) := (others => '0');
    signal rx_bit_count : unsigned(2 downto 0) := (others => '0');
    
    -- TX Header Buffer
    type tx_header_array_t is array (0 to 13) of std_logic_vector(7 downto 0);
    signal tx_header_buf : tx_header_array_t := (others => (others => '0'));
    signal tx_header_index : unsigned(3 downto 0) := (others => '0');
    
    -- RX Header Buffer
    type rx_header_array_t is array (0 to 13) of std_logic_vector(7 downto 0);
    signal rx_header_buf : rx_header_array_t := (others => (others => '0'));
    signal rx_header_index : unsigned(3 downto 0) := (others => '0');
    
    -- Preamble and SFD
    constant PREAMBLE_BYTE : std_logic_vector(7 downto 0) := x"55";
    constant SFD_BYTE : std_logic_vector(7 downto 0) := x"D5";
    
    -- CRC32 for FCS
    signal tx_crc32 : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    signal rx_crc32 : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    signal tx_fcs_bytes : unsigned(1 downto 0) := (others => '0');
    signal rx_fcs_bytes : unsigned(1 downto 0) := (others => '0');
    
    -- Frame validation
    signal rx_frame_valid_int : std_logic := '0';
    signal rx_frame_error_int : std_logic := '0';
    signal rx_dst_mac_match : std_logic := '0';
    signal rx_broadcast_match : std_logic := '0';
    
    -- IFG Counter
    signal ifg_counter : unsigned(3 downto 0) := (others => '0');
    
    -- CRC32 calculation function
    function crc32_update(crc : std_logic_vector(31 downto 0); data : std_logic_vector(7 downto 0)) 
        return std_logic_vector is
        variable temp_crc : std_logic_vector(31 downto 0);
        variable poly : std_logic_vector(31 downto 0) := x"04C11DB7";
    begin
        temp_crc := crc;
        for i in 0 to 7 loop
            if (temp_crc(31) xor data(i)) = '1' then
                temp_crc := (temp_crc(30 downto 0) & '0') xor poly;
            else
                temp_crc := temp_crc(30 downto 0) & '0';
            end if;
        end loop;
        return temp_crc;
    end function;
    
begin
    
    -- TX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            tx_state <= TX_IDLE;
            tx_byte_count <= (others => '0');
            tx_bit_count <= (others => '0');
            tx_header_index <= (others => '0');
            tx_crc32 <= x"FFFFFFFF";
            tx_fcs_bytes <= (others => '0');
            ifg_counter <= (others => '0');
            phy_tx_data <= (others => '0');
            phy_tx_valid <= '0';
            phy_tx_last <= '0';
            phy_tx_error <= '0';
            tx_payload_ready <= '0';
        elsif rising_edge(clk) then
            case tx_state is
                when TX_IDLE =>
                    phy_tx_valid <= '0';
                    phy_tx_last <= '0';
                    phy_tx_error <= '0';
                    tx_payload_ready <= '0';
                    tx_crc32 <= x"FFFFFFFF";
                    
                    if tx_start = '1' then
                        tx_state <= TX_PREAMBLE;
                        tx_byte_count <= to_unsigned(7, 16);
                        
                        -- Prepare header
                        tx_header_buf(0) <= tx_dst_mac(47 downto 40);
                        tx_header_buf(1) <= tx_dst_mac(39 downto 32);
                        tx_header_buf(2) <= tx_dst_mac(31 downto 24);
                        tx_header_buf(3) <= tx_dst_mac(23 downto 16);
                        tx_header_buf(4) <= tx_dst_mac(15 downto 8);
                        tx_header_buf(5) <= tx_dst_mac(7 downto 0);
                        tx_header_buf(6) <= tx_src_mac(47 downto 40);
                        tx_header_buf(7) <= tx_src_mac(39 downto 32);
                        tx_header_buf(8) <= tx_src_mac(31 downto 24);
                        tx_header_buf(9) <= tx_src_mac(23 downto 16);
                        tx_header_buf(10) <= tx_src_mac(15 downto 8);
                        tx_header_buf(11) <= tx_src_mac(7 downto 0);
                        tx_header_buf(12) <= tx_ethertype(15 downto 8);
                        tx_header_buf(13) <= tx_ethertype(7 downto 0);
                        tx_header_index <= (others => '0');
                    end if;
                
                when TX_PREAMBLE =>
                    if phy_tx_ready = '1' then
                        phy_tx_data <= PREAMBLE_BYTE;
                        phy_tx_valid <= '1';
                        if tx_byte_count = 0 then
                            tx_state <= TX_SFD;
                        else
                            tx_byte_count <= tx_byte_count - 1;
                        end if;
                    end if;
                
                when TX_SFD =>
                    if phy_tx_ready = '1' then
                        phy_tx_data <= SFD_BYTE;
                        phy_tx_valid <= '1';
                        tx_state <= TX_HEADER;
                        tx_header_index <= (others => '0');
                    end if;
                
                when TX_HEADER =>
                    if phy_tx_ready = '1' then
                        phy_tx_data <= tx_header_buf(to_integer(tx_header_index));
                        phy_tx_valid <= '1';
                        tx_crc32 <= crc32_update(tx_crc32, tx_header_buf(to_integer(tx_header_index)));
                        
                        if tx_header_index = 13 then
                            tx_state <= TX_PAYLOAD;
                            tx_payload_ready <= '1';
                        else
                            tx_header_index <= tx_header_index + 1;
                        end if;
                    end if;
                
                when TX_PAYLOAD =>
                    tx_payload_ready <= phy_tx_ready;
                    if tx_payload_valid = '1' and phy_tx_ready = '1' then
                        phy_tx_data <= tx_payload_data;
                        phy_tx_valid <= '1';
                        tx_crc32 <= crc32_update(tx_crc32, tx_payload_data);
                        
                        if tx_payload_last = '1' then
                            tx_state <= TX_FCS;
                            tx_fcs_bytes <= (others => '0');
                            tx_payload_ready <= '0';
                        end if;
                    else
                        phy_tx_valid <= '0';
                    end if;
                
                when TX_FCS =>
                    if phy_tx_ready = '1' then
                        case tx_fcs_bytes is
                            when "00" => phy_tx_data <= not tx_crc32(7 downto 0);
                            when "01" => phy_tx_data <= not tx_crc32(15 downto 8);
                            when "10" => phy_tx_data <= not tx_crc32(23 downto 16);
                            when "11" => phy_tx_data <= not tx_crc32(31 downto 24);
                            when others => phy_tx_data <= (others => '0');
                        end case;
                        phy_tx_valid <= '1';
                        
                        if tx_fcs_bytes = 3 then
                            phy_tx_last <= '1';
                            tx_state <= TX_IFG;
                            ifg_counter <= to_unsigned(12, 4);
                        else
                            tx_fcs_bytes <= tx_fcs_bytes + 1;
                        end if;
                    end if;
                
                when TX_IFG =>
                    phy_tx_valid <= '0';
                    phy_tx_last <= '0';
                    if ifg_counter = 0 then
                        tx_state <= TX_IDLE;
                    else
                        ifg_counter <= ifg_counter - 1;
                    end if;
            end case;
        end if;
    end process;
    
    -- RX State Machine
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rx_state <= RX_IDLE;
            rx_byte_count <= (others => '0');
            rx_bit_count <= (others => '0');
            rx_header_index <= (others => '0');
            rx_crc32 <= x"FFFFFFFF";
            rx_fcs_bytes <= (others => '0');
            rx_frame_valid_int <= '0';
            rx_frame_error_int <= '0';
            phy_rx_ready <= '1';
            rx_payload_valid <= '0';
            rx_payload_last <= '0';
        elsif rising_edge(clk) then
            case rx_state is
                when RX_IDLE =>
                    phy_rx_ready <= '1';
                    rx_payload_valid <= '0';
                    rx_payload_last <= '0';
                    rx_frame_valid_int <= '0';
                    rx_frame_error_int <= '0';
                    rx_crc32 <= x"FFFFFFFF";
                    
                    if phy_rx_valid = '1' and phy_rx_data = PREAMBLE_BYTE then
                        rx_state <= RX_PREAMBLE;
                        rx_byte_count <= to_unsigned(6, 16);
                    end if;
                
                when RX_PREAMBLE =>
                    if phy_rx_valid = '1' then
                        if phy_rx_data = PREAMBLE_BYTE then
                            if rx_byte_count = 0 then
                                rx_state <= RX_SFD;
                            else
                                rx_byte_count <= rx_byte_count - 1;
                            end if;
                        elsif phy_rx_data = SFD_BYTE then
                            rx_state <= RX_SFD;
                        else
                            rx_state <= RX_IDLE;
                        end if;
                    end if;
                
                when RX_SFD =>
                    if phy_rx_valid = '1' then
                        if phy_rx_data = SFD_BYTE then
                            rx_state <= RX_HEADER;
                            rx_header_index <= (others => '0');
                        else
                            rx_state <= RX_IDLE;
                        end if;
                    end if;
                
                when RX_HEADER =>
                    if phy_rx_valid = '1' then
                        rx_header_buf(to_integer(rx_header_index)) <= phy_rx_data;
                        rx_crc32 <= crc32_update(rx_crc32, phy_rx_data);
                        
                        if rx_header_index = 13 then
                            rx_state <= RX_PAYLOAD;
                            
                            -- Extract header fields
                            rx_dst_mac <= rx_header_buf(0) & rx_header_buf(1) & rx_header_buf(2) & 
                                         rx_header_buf(3) & rx_header_buf(4) & phy_rx_data;
                            rx_src_mac <= rx_header_buf(6) & rx_header_buf(7) & rx_header_buf(8) & 
                                         rx_header_buf(9) & rx_header_buf(10) & rx_header_buf(11);
                            rx_ethertype <= rx_header_buf(12) & rx_header_buf(13);
                            
                            -- Check if frame is for us
                            rx_dst_mac_match <= '1' when (rx_header_buf(0) & rx_header_buf(1) & rx_header_buf(2) & 
                                                         rx_header_buf(3) & rx_header_buf(4) & phy_rx_data) = local_mac else '0';
                            rx_broadcast_match <= '1' when (rx_header_buf(0) & rx_header_buf(1) & rx_header_buf(2) & 
                                                           rx_header_buf(3) & rx_header_buf(4) & phy_rx_data) = x"FFFFFFFFFFFF" else '0';
                        else
                            rx_header_index <= rx_header_index + 1;
                        end if;
                    end if;
                
                when RX_PAYLOAD =>
                    if phy_rx_valid = '1' then
                        if phy_rx_last = '1' then
                            rx_state <= RX_FCS;
                            rx_fcs_bytes <= (others => '0');
                        else
                            rx_payload_data <= phy_rx_data;
                            rx_payload_valid <= (rx_dst_mac_match or rx_broadcast_match or promiscuous_mode);
                            rx_crc32 <= crc32_update(rx_crc32, phy_rx_data);
                        end if;
                    else
                        rx_payload_valid <= '0';
                    end if;
                
                when RX_FCS =>
                    if phy_rx_valid = '1' then
                        rx_fcs_bytes <= rx_fcs_bytes + 1;
                        if rx_fcs_bytes = 3 then
                            rx_payload_last <= '1';
                            rx_frame_valid_int <= (rx_dst_mac_match or rx_broadcast_match or promiscuous_mode);
                            if rx_crc32 = x"C704DD7B" then
                                rx_frame_error_int <= phy_rx_error;
                            else
                                rx_frame_error_int <= '1';
                            end if;
                            rx_state <= RX_IDLE;
                        end if;
                    end if;
            end case;
        end if;
    end process;
    
    -- Output assignments
    rx_frame_valid <= rx_frame_valid_int;
    rx_frame_error <= rx_frame_error_int;
    
end architecture rtl;