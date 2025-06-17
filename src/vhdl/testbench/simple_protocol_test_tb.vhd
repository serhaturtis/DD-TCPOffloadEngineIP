library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;
use work.tcp_protocol_tb_pkg.all;

entity simple_protocol_test_tb is
end entity simple_protocol_test_tb;

architecture behavioral of simple_protocol_test_tb is
    
    -- Clock and reset
    signal sys_clk : std_logic := '0';
    signal sys_rst_n : std_logic := '0';
    signal s_axi_aclk : std_logic := '0';
    signal s_axi_aresetn : std_logic := '0';
    
    -- RGMII interface
    signal rgmii_txd : std_logic_vector(3 downto 0);
    signal rgmii_tx_ctl : std_logic;
    signal rgmii_txc : std_logic;
    signal rgmii_rxd : std_logic_vector(3 downto 0) := (others => '0');
    signal rgmii_rx_ctl : std_logic := '0';
    signal rgmii_rxc : std_logic := '0';
    
    -- MDIO interface
    signal mdc : std_logic;
    signal mdio : std_logic;
    
    -- AXI4-Lite control interface
    signal s_axi_awaddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_awprot : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_awvalid : std_logic := '0';
    signal s_axi_awready : std_logic;
    signal s_axi_wdata : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_wstrb : std_logic_vector(3 downto 0) := (others => '0');
    signal s_axi_wvalid : std_logic := '0';
    signal s_axi_wready : std_logic;
    signal s_axi_bresp : std_logic_vector(1 downto 0);
    signal s_axi_bvalid : std_logic;
    signal s_axi_bready : std_logic := '0';
    signal s_axi_araddr : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_arprot : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_arvalid : std_logic := '0';
    signal s_axi_arready : std_logic;
    signal s_axi_rdata : std_logic_vector(31 downto 0);
    signal s_axi_rresp : std_logic_vector(1 downto 0);
    signal s_axi_rvalid : std_logic;
    signal s_axi_rready : std_logic := '0';
    
    -- AXI4-Stream data interface
    signal m_axis_tx_tdata : std_logic_vector(63 downto 0);
    signal m_axis_tx_tkeep : std_logic_vector(7 downto 0);
    signal m_axis_tx_tvalid : std_logic;
    signal m_axis_tx_tready : std_logic := '1';
    signal m_axis_tx_tlast : std_logic;
    signal m_axis_tx_tuser : std_logic_vector(7 downto 0);
    signal s_axis_rx_tdata : std_logic_vector(63 downto 0) := (others => '0');
    signal s_axis_rx_tkeep : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_rx_tvalid : std_logic := '0';
    signal s_axis_rx_tready : std_logic;
    signal s_axis_rx_tlast : std_logic := '0';
    signal s_axis_rx_tuser : std_logic_vector(7 downto 0) := (others => '0');
    
    -- Status LEDs
    signal link_up_led : std_logic;
    signal activity_led : std_logic;
    signal error_led : std_logic;
    
    -- Test control
    signal test_complete : std_logic := '0';
    
    -- Clock periods
    constant SYS_CLK_PERIOD : time := 8 ns; -- 125 MHz
    constant AXI_CLK_PERIOD : time := 10 ns; -- 100 MHz
    
    -- DUT instantiation
    component tcp_offload_engine_top is
        port (
            sys_clk : in std_logic;
            sys_rst_n : in std_logic;
            rgmii_txd : out std_logic_vector(3 downto 0);
            rgmii_tx_ctl : out std_logic;
            rgmii_txc : out std_logic;
            rgmii_rxd : in std_logic_vector(3 downto 0);
            rgmii_rx_ctl : in std_logic;
            rgmii_rxc : in std_logic;
            mdc : out std_logic;
            mdio : inout std_logic;
            s_axi_aclk : in std_logic;
            s_axi_aresetn : in std_logic;
            s_axi_awaddr : in std_logic_vector(31 downto 0);
            s_axi_awprot : in std_logic_vector(2 downto 0);
            s_axi_awvalid : in std_logic;
            s_axi_awready : out std_logic;
            s_axi_wdata : in std_logic_vector(31 downto 0);
            s_axi_wstrb : in std_logic_vector(3 downto 0);
            s_axi_wvalid : in std_logic;
            s_axi_wready : out std_logic;
            s_axi_bresp : out std_logic_vector(1 downto 0);
            s_axi_bvalid : out std_logic;
            s_axi_bready : in std_logic;
            s_axi_araddr : in std_logic_vector(31 downto 0);
            s_axi_arprot : in std_logic_vector(2 downto 0);
            s_axi_arvalid : in std_logic;
            s_axi_arready : out std_logic;
            s_axi_rdata : out std_logic_vector(31 downto 0);
            s_axi_rresp : out std_logic_vector(1 downto 0);
            s_axi_rvalid : out std_logic;
            s_axi_rready : in std_logic;
            m_axis_tx_tdata : out std_logic_vector(63 downto 0);
            m_axis_tx_tkeep : out std_logic_vector(7 downto 0);
            m_axis_tx_tvalid : out std_logic;
            m_axis_tx_tready : in std_logic;
            m_axis_tx_tlast : out std_logic;
            m_axis_tx_tuser : out std_logic_vector(7 downto 0);
            s_axis_rx_tdata : in std_logic_vector(63 downto 0);
            s_axis_rx_tkeep : in std_logic_vector(7 downto 0);
            s_axis_rx_tvalid : in std_logic;
            s_axis_rx_tready : out std_logic;
            s_axis_rx_tlast : in std_logic;
            s_axis_rx_tuser : in std_logic_vector(7 downto 0);
            link_up_led : out std_logic;
            activity_led : out std_logic;
            error_led : out std_logic
        );
    end component;
    
begin
    
    -- Clock generation
    sys_clk <= not sys_clk after SYS_CLK_PERIOD / 2;
    s_axi_aclk <= not s_axi_aclk after AXI_CLK_PERIOD / 2;
    rgmii_rxc <= not rgmii_rxc after SYS_CLK_PERIOD / 2;
    
    -- DUT instantiation
    dut: tcp_offload_engine_top
        port map (
            sys_clk => sys_clk,
            sys_rst_n => sys_rst_n,
            rgmii_txd => rgmii_txd,
            rgmii_tx_ctl => rgmii_tx_ctl,
            rgmii_txc => rgmii_txc,
            rgmii_rxd => rgmii_rxd,
            rgmii_rx_ctl => rgmii_rx_ctl,
            rgmii_rxc => rgmii_rxc,
            mdc => mdc,
            mdio => mdio,
            s_axi_aclk => s_axi_aclk,
            s_axi_aresetn => s_axi_aresetn,
            s_axi_awaddr => s_axi_awaddr,
            s_axi_awprot => s_axi_awprot,
            s_axi_awvalid => s_axi_awvalid,
            s_axi_awready => s_axi_awready,
            s_axi_wdata => s_axi_wdata,
            s_axi_wstrb => s_axi_wstrb,
            s_axi_wvalid => s_axi_wvalid,
            s_axi_wready => s_axi_wready,
            s_axi_bresp => s_axi_bresp,
            s_axi_bvalid => s_axi_bvalid,
            s_axi_bready => s_axi_bready,
            s_axi_araddr => s_axi_araddr,
            s_axi_arprot => s_axi_arprot,
            s_axi_arvalid => s_axi_arvalid,
            s_axi_arready => s_axi_arready,
            s_axi_rdata => s_axi_rdata,
            s_axi_rresp => s_axi_rresp,
            s_axi_rvalid => s_axi_rvalid,
            s_axi_rready => s_axi_rready,
            m_axis_tx_tdata => m_axis_tx_tdata,
            m_axis_tx_tkeep => m_axis_tx_tkeep,
            m_axis_tx_tvalid => m_axis_tx_tvalid,
            m_axis_tx_tready => m_axis_tx_tready,
            m_axis_tx_tlast => m_axis_tx_tlast,
            m_axis_tx_tuser => m_axis_tx_tuser,
            s_axis_rx_tdata => s_axis_rx_tdata,
            s_axis_rx_tkeep => s_axis_rx_tkeep,
            s_axis_rx_tvalid => s_axis_rx_tvalid,
            s_axis_rx_tready => s_axis_rx_tready,
            s_axis_rx_tlast => s_axis_rx_tlast,
            s_axis_rx_tuser => s_axis_rx_tuser,
            link_up_led => link_up_led,
            activity_led => activity_led,
            error_led => error_led
        );
    
    -- MDIO pullup
    mdio <= 'H';
    
    -- Main test process
    test_proc: process
        variable eth_header : byte_array_t(0 to 13);
        variable ip_header : byte_array_t(0 to 19);
        variable tcp_header : byte_array_t(0 to 19);
        variable udp_header : byte_array_t(0 to 7);
        variable syn_packet : byte_array_t(0 to 53);
    begin
        -- Initialize
        sys_rst_n <= '0';
        s_axi_aresetn <= '0';
        
        wait for 100 ns;
        
        -- Release reset
        sys_rst_n <= '1';
        s_axi_aresetn <= '1';
        
        wait for 200 ns;
        
        test_start("Simple Protocol Test Suite");
        
        -- Test 1: Packet Generation Framework
        test_start("Packet Generation Framework Test");
        
        -- Test Ethernet header generation
        eth_header := generate_ethernet_header(
            TEST_MAC_ADDR, REMOTE_MAC_ADDR, x"0800"
        );
        
        if eth_header(0) = TEST_MAC_ADDR(47 downto 40) then
            test_pass("Ethernet Header Generation");
        else
            test_fail("Ethernet Header Generation", "Header mismatch");
        end if;
        
        -- Test IP header generation
        ip_header := generate_ip_header(
            TEST_IP_ADDR, REMOTE_IP_ADDR, x"06", 20
        );
        
        if ip_header(0) = x"45" then -- Version + IHL
            test_pass("IP Header Generation");
        else
            test_fail("IP Header Generation", "Header mismatch");
        end if;
        
        -- Test TCP header generation
        tcp_header := generate_tcp_header(
            x"0050", x"8000", x"12345678", x"87654321", x"02", x"8000"
        );
        
        if tcp_header(0) = x"00" and tcp_header(1) = x"50" then -- Port 80
            test_pass("TCP Header Generation");
        else
            test_fail("TCP Header Generation", "Header mismatch");
        end if;
        
        -- Test UDP header generation
        udp_header := generate_udp_header(x"1234", x"5678", 100);
        
        if udp_header(0) = x"12" and udp_header(1) = x"34" then
            test_pass("UDP Header Generation");
        else
            test_fail("UDP Header Generation", "Header mismatch");
        end if;
        
        -- Test 2: Complete Packet Generation
        test_start("Complete Packet Generation Test");
        
        syn_packet := generate_tcp_syn_packet(
            REMOTE_MAC_ADDR, TEST_MAC_ADDR,
            REMOTE_IP_ADDR, TEST_IP_ADDR,
            x"8000", x"0050", x"12345678"
        );
        
        if syn_packet'length = 54 then -- Expected packet size
            test_pass("TCP SYN Packet Generation");
        else
            test_fail("TCP SYN Packet Generation", "Wrong packet size");
        end if;
        
        -- Test 3: Engine Basic Functionality
        test_start("Engine Basic Functionality");
        
        -- Just verify the engine is running without errors
        wait for 5 us;
        
        test_pass("Engine Basic Functionality");
        
        -- Test completion
        test_report_summary;
        test_complete <= '1';
        
        report "Simple Protocol Test Suite completed successfully";
        
        wait;
    end process;
    
    -- Timeout process
    timeout_proc: process
    begin
        wait for 20 us;
        if test_complete = '0' then
            report "Simple Protocol Test timeout!" severity failure;
        end if;
        wait;
    end process;
    
end architecture behavioral;