library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity rgmii_interface is
    port (
        -- Clock and Reset
        clk_125mhz : in std_logic;
        clk_25mhz : in std_logic;
        clk_2_5mhz : in std_logic;
        rst_n : in std_logic;
        
        -- RGMII PHY Interface
        rgmii_txd : out std_logic_vector(3 downto 0);
        rgmii_tx_ctl : out std_logic;
        rgmii_txc : out std_logic;
        rgmii_rxd : in std_logic_vector(3 downto 0);
        rgmii_rx_ctl : in std_logic;
        rgmii_rxc : in std_logic;
        
        -- Management Interface (MDIO)
        mdc : out std_logic;
        mdio : inout std_logic;
        
        -- Internal MAC Interface
        mac_tx_data : in std_logic_vector(7 downto 0);
        mac_tx_valid : in std_logic;
        mac_tx_ready : out std_logic;
        mac_tx_last : in std_logic;
        mac_tx_error : in std_logic;
        
        mac_rx_data : out std_logic_vector(7 downto 0);
        mac_rx_valid : out std_logic;
        mac_rx_ready : in std_logic;
        mac_rx_last : out std_logic;
        mac_rx_error : out std_logic;
        
        -- Status and Control
        link_up : out std_logic;
        link_speed : out std_logic_vector(1 downto 0); -- 00=10M, 01=100M, 10=1000M
        link_duplex : out std_logic; -- 0=half, 1=full
        auto_neg_complete : out std_logic
    );
end entity rgmii_interface;

architecture rtl of rgmii_interface is
    
    -- MDIO State Machine
    type mdio_state_t is (IDLE, PREAMBLE, START, OP, PHY_ADDR, REG_ADDR, TURNAROUND, DATA, COMPLETE);
    signal mdio_state : mdio_state_t := IDLE;
    signal mdio_bit_count : unsigned(5 downto 0) := (others => '0');
    signal mdio_data_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal mdio_write_data : std_logic_vector(15 downto 0) := (others => '0');
    signal mdio_read_data : std_logic_vector(15 downto 0) := (others => '0');
    signal mdio_phy_addr : std_logic_vector(4 downto 0) := "00001";
    signal mdio_reg_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal mdio_op : std_logic_vector(1 downto 0) := "10"; -- Read operation
    signal mdio_start : std_logic := '0';
    signal mdio_done : std_logic := '0';
    signal mdio_clk_div : unsigned(7 downto 0) := (others => '0');
    signal mdio_clk : std_logic := '0';
    signal mdio_dir : std_logic := '0'; -- 0=output, 1=input
    signal mdio_out : std_logic := '0';
    signal mdio_in : std_logic := '0';
    
    -- Auto-negotiation
    type auto_neg_state_t is (AN_RESET, AN_ENABLE, AN_RESTART, AN_WAIT_COMPLETE, AN_READ_STATUS, AN_COMPLETE);
    signal auto_neg_state : auto_neg_state_t := AN_RESET;
    signal auto_neg_timer : unsigned(23 downto 0) := (others => '0');
    
    -- PHY Registers
    signal phy_control_reg : std_logic_vector(15 downto 0) := x"1000"; -- Auto-neg enable
    signal phy_status_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_an_adv_reg : std_logic_vector(15 downto 0) := x"01E1"; -- 10/100/1000 capabilities
    signal phy_an_lpa_reg : std_logic_vector(15 downto 0) := (others => '0');
    signal phy_1000t_control : std_logic_vector(15 downto 0) := x"0300"; -- 1000T capabilities
    signal phy_1000t_status : std_logic_vector(15 downto 0) := (others => '0');
    
    -- RGMII TX
    signal rgmii_tx_clk_sel : std_logic_vector(1 downto 0) := "10"; -- 1000M default
    signal rgmii_tx_clk_int : std_logic;
    signal tx_data_ddr : std_logic_vector(3 downto 0);
    signal tx_ctl_ddr : std_logic;
    signal tx_nibble_sel : std_logic := '0';
    signal tx_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_valid_reg : std_logic := '0';
    signal tx_error_reg : std_logic := '0';
    
    -- RGMII RX
    signal rx_data_ddr : std_logic_vector(3 downto 0);
    signal rx_ctl_ddr : std_logic;
    signal rx_nibble_sel : std_logic := '0';
    signal rx_data_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid_reg : std_logic := '0';
    signal rx_error_reg : std_logic := '0';
    signal rx_clk_div : std_logic := '0';
    
    -- Status signals
    signal link_up_int : std_logic := '0';
    signal link_speed_int : std_logic_vector(1 downto 0) := "10";
    signal link_duplex_int : std_logic := '1';
    signal auto_neg_complete_int : std_logic := '0';
    
begin
    
    -- Clock selection for different speeds
    rgmii_tx_clk_int <= clk_125mhz when rgmii_tx_clk_sel = "10" else  -- 1000M
                        clk_25mhz when rgmii_tx_clk_sel = "01" else   -- 100M
                        clk_2_5mhz;                                    -- 10M
    
    -- MDIO Clock Generation (2.5MHz max)
    process(clk_125mhz, rst_n)
    begin
        if rst_n = '0' then
            mdio_clk_div <= (others => '0');
            mdio_clk <= '0';
        elsif rising_edge(clk_125mhz) then
            mdio_clk_div <= mdio_clk_div + 1;
            if mdio_clk_div = 24 then -- 125MHz / 50 = 2.5MHz
                mdio_clk_div <= (others => '0');
                mdio_clk <= not mdio_clk;
            end if;
        end if;
    end process;
    
    mdc <= mdio_clk;
    
    -- MDIO Bidirectional Control
    mdio <= mdio_out when mdio_dir = '0' else 'Z';
    mdio_in <= mdio;
    
    -- MDIO State Machine
    process(clk_125mhz, rst_n)
    begin
        if rst_n = '0' then
            mdio_state <= IDLE;
            mdio_bit_count <= (others => '0');
            mdio_data_reg <= (others => '0');
            mdio_done <= '0';
            mdio_dir <= '0';
            mdio_out <= '1';
        elsif rising_edge(clk_125mhz) then
            if rising_edge(mdio_clk) then
                case mdio_state is
                    when IDLE =>
                        mdio_done <= '0';
                        mdio_dir <= '0';
                        mdio_out <= '1';
                        if mdio_start = '1' then
                            mdio_state <= PREAMBLE;
                            mdio_bit_count <= to_unsigned(31, 6);
                            mdio_data_reg <= x"FFFFFFFF";
                        end if;
                    
                    when PREAMBLE =>
                        mdio_out <= mdio_data_reg(31);
                        mdio_data_reg <= mdio_data_reg(30 downto 0) & '0';
                        if mdio_bit_count = 0 then
                            mdio_state <= START;
                            mdio_bit_count <= to_unsigned(1, 6);
                            mdio_data_reg(1 downto 0) <= "01"; -- Start bits
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when START =>
                        mdio_out <= mdio_data_reg(1);
                        mdio_data_reg <= mdio_data_reg(0) & '0';
                        if mdio_bit_count = 0 then
                            mdio_state <= OP;
                            mdio_bit_count <= to_unsigned(1, 6);
                            mdio_data_reg(1 downto 0) <= mdio_op;
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when OP =>
                        mdio_out <= mdio_data_reg(1);
                        mdio_data_reg <= mdio_data_reg(0) & '0';
                        if mdio_bit_count = 0 then
                            mdio_state <= PHY_ADDR;
                            mdio_bit_count <= to_unsigned(4, 6);
                            mdio_data_reg(4 downto 0) <= mdio_phy_addr;
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when PHY_ADDR =>
                        mdio_out <= mdio_data_reg(4);
                        mdio_data_reg <= mdio_data_reg(3 downto 0) & '0';
                        if mdio_bit_count = 0 then
                            mdio_state <= REG_ADDR;
                            mdio_bit_count <= to_unsigned(4, 6);
                            mdio_data_reg(4 downto 0) <= mdio_reg_addr;
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when REG_ADDR =>
                        mdio_out <= mdio_data_reg(4);
                        mdio_data_reg <= mdio_data_reg(3 downto 0) & '0';
                        if mdio_bit_count = 0 then
                            mdio_state <= TURNAROUND;
                            mdio_bit_count <= to_unsigned(1, 6);
                            if mdio_op = "10" then -- Read
                                mdio_dir <= '1'; -- Switch to input
                            else -- Write
                                mdio_data_reg(1 downto 0) <= "10";
                            end if;
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when TURNAROUND =>
                        if mdio_op = "10" then -- Read
                            mdio_dir <= '1';
                        else -- Write
                            mdio_out <= mdio_data_reg(1);
                            mdio_data_reg <= mdio_data_reg(0) & '0';
                        end if;
                        
                        if mdio_bit_count = 0 then
                            mdio_state <= DATA;
                            mdio_bit_count <= to_unsigned(15, 6);
                            if mdio_op = "01" then -- Write
                                mdio_data_reg(15 downto 0) <= mdio_write_data;
                            end if;
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when DATA =>
                        if mdio_op = "10" then -- Read
                            mdio_read_data <= mdio_read_data(14 downto 0) & mdio_in;
                        else -- Write
                            mdio_out <= mdio_data_reg(15);
                            mdio_data_reg <= mdio_data_reg(14 downto 0) & '0';
                        end if;
                        
                        if mdio_bit_count = 0 then
                            mdio_state <= COMPLETE;
                        else
                            mdio_bit_count <= mdio_bit_count - 1;
                        end if;
                    
                    when COMPLETE =>
                        mdio_state <= IDLE;
                        mdio_done <= '1';
                        mdio_dir <= '0';
                        mdio_out <= '1';
                end case;
            end if;
        end if;
    end process;
    
    -- Auto-negotiation State Machine
    process(clk_125mhz, rst_n)
    begin
        if rst_n = '0' then
            auto_neg_state <= AN_RESET;
            auto_neg_timer <= (others => '0');
            link_up_int <= '0';
            auto_neg_complete_int <= '0';
            link_speed_int <= "10";
            link_duplex_int <= '1';
        elsif rising_edge(clk_125mhz) then
            auto_neg_timer <= auto_neg_timer + 1;
            
            case auto_neg_state is
                when AN_RESET =>
                    if auto_neg_timer = x"FFFFFF" then -- Wait ~134ms
                        auto_neg_state <= AN_ENABLE;
                        auto_neg_timer <= (others => '0');
                        mdio_reg_addr <= "00000"; -- Control register
                        mdio_write_data <= x"1000"; -- Enable auto-negotiation
                        mdio_op <= "01"; -- Write
                        mdio_start <= '1';
                    end if;
                
                when AN_ENABLE =>
                    mdio_start <= '0';
                    if mdio_done = '1' then
                        auto_neg_state <= AN_RESTART;
                        auto_neg_timer <= (others => '0');
                        mdio_write_data <= x"1200"; -- Restart auto-negotiation
                        mdio_start <= '1';
                    end if;
                
                when AN_RESTART =>
                    mdio_start <= '0';
                    if mdio_done = '1' then
                        auto_neg_state <= AN_WAIT_COMPLETE;
                        auto_neg_timer <= (others => '0');
                    end if;
                
                when AN_WAIT_COMPLETE =>
                    if auto_neg_timer = x"FFFFFF" then -- Check periodically
                        auto_neg_state <= AN_READ_STATUS;
                        auto_neg_timer <= (others => '0');
                        mdio_reg_addr <= "00001"; -- Status register
                        mdio_op <= "10"; -- Read
                        mdio_start <= '1';
                    end if;
                
                when AN_READ_STATUS =>
                    mdio_start <= '0';
                    if mdio_done = '1' then
                        phy_status_reg <= mdio_read_data;
                        if mdio_read_data(5) = '1' and mdio_read_data(2) = '1' then -- Auto-neg complete and link up
                            auto_neg_state <= AN_COMPLETE;
                            link_up_int <= '1';
                            auto_neg_complete_int <= '1';
                            -- Determine speed and duplex from negotiation result
                            link_speed_int <= "10"; -- Assume 1000M for now
                            link_duplex_int <= '1'; -- Full duplex
                        else
                            auto_neg_state <= AN_WAIT_COMPLETE;
                        end if;
                        auto_neg_timer <= (others => '0');
                    end if;
                
                when AN_COMPLETE =>
                    -- Monitor link status
                    if auto_neg_timer = x"FFFFFF" then
                        auto_neg_state <= AN_READ_STATUS;
                        auto_neg_timer <= (others => '0');
                        mdio_start <= '1';
                    end if;
            end case;
        end if;
    end process;
    
    -- RGMII TX Path
    process(rgmii_tx_clk_int, rst_n)
    begin
        if rst_n = '0' then
            tx_nibble_sel <= '0';
            tx_data_reg <= (others => '0');
            tx_valid_reg <= '0';
            tx_error_reg <= '0';
            mac_tx_ready <= '0';
        elsif rising_edge(rgmii_tx_clk_int) then
            mac_tx_ready <= '1'; -- Always ready for now
            
            if mac_tx_valid = '1' then
                if tx_nibble_sel = '0' then
                    tx_data_reg <= mac_tx_data;
                    tx_valid_reg <= '1';
                    tx_error_reg <= mac_tx_error;
                    tx_nibble_sel <= '1';
                    tx_data_ddr <= mac_tx_data(3 downto 0);
                    tx_ctl_ddr <= '1';
                else
                    tx_nibble_sel <= '0';
                    tx_data_ddr <= tx_data_reg(7 downto 4);
                    tx_ctl_ddr <= not tx_error_reg;
                end if;
            else
                tx_valid_reg <= '0';
                tx_data_ddr <= (others => '0');
                tx_ctl_ddr <= '0';
                tx_nibble_sel <= '0';
            end if;
        end if;
    end process;
    
    -- RGMII RX Path
    process(rgmii_rxc, rst_n)
    begin
        if rst_n = '0' then
            rx_nibble_sel <= '0';
            rx_data_reg <= (others => '0');
            rx_valid_reg <= '0';
            rx_error_reg <= '0';
        elsif rising_edge(rgmii_rxc) then
            if rx_nibble_sel = '0' then
                rx_data_reg(3 downto 0) <= rgmii_rxd;
                rx_nibble_sel <= '1';
                rx_valid_reg <= rgmii_rx_ctl;
                rx_error_reg <= '0';
            else
                rx_data_reg(7 downto 4) <= rgmii_rxd;
                rx_nibble_sel <= '0';
                rx_error_reg <= not rgmii_rx_ctl and rx_valid_reg;
            end if;
        end if;
    end process;
    
    process(rgmii_rxc, rst_n)
    begin
        if rst_n = '0' then
            rx_clk_div <= '0';
        elsif falling_edge(rgmii_rxc) then
            rx_clk_div <= not rx_clk_div;
        end if;
    end process;
    
    -- Output RX data on divided clock
    process(rx_clk_div, rst_n)
    begin
        if rst_n = '0' then
            mac_rx_data <= (others => '0');
            mac_rx_valid <= '0';
            mac_rx_last <= '0';
            mac_rx_error <= '0';
        elsif rising_edge(rx_clk_div) then
            mac_rx_data <= rx_data_reg;
            mac_rx_valid <= rx_valid_reg;
            mac_rx_error <= rx_error_reg;
            mac_rx_last <= '0'; -- Will be determined by MAC layer
        end if;
    end process;
    
    -- DDR Output for RGMII
    rgmii_txc <= rgmii_tx_clk_int;
    
    -- DDR registers for TX (would use ODDR primitives in real implementation)
    process(rgmii_tx_clk_int, rst_n)
    begin
        if rst_n = '0' then
            rgmii_txd <= (others => '0');
            rgmii_tx_ctl <= '0';
        elsif rising_edge(rgmii_tx_clk_int) then
            rgmii_txd <= tx_data_ddr;
            rgmii_tx_ctl <= tx_ctl_ddr;
        end if;
    end process;
    
    -- Status outputs
    link_up <= link_up_int;
    link_speed <= link_speed_int;
    link_duplex <= link_duplex_int;
    auto_neg_complete <= auto_neg_complete_int;
    
end architecture rtl;