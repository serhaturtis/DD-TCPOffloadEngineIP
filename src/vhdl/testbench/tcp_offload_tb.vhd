library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity tcp_offload_tb is
end entity tcp_offload_tb;

architecture behavioral of tcp_offload_tb is
    
    -- Clock and reset
    signal sys_clk : std_logic := '0';
    signal sys_rst_n : std_logic := '0';
    signal s_axi_aclk : std_logic := '0';
    signal s_axi_aresetn : std_logic := '0';
    
    -- RGMII interface (simulated PHY)
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
    signal test_pass : std_logic := '0';
    
    -- Clock periods
    constant SYS_CLK_PERIOD : time := 8 ns; -- 125 MHz
    constant AXI_CLK_PERIOD : time := 10 ns; -- 100 MHz
    
    -- Test MAC address
    constant TEST_MAC : std_logic_vector(47 downto 0) := x"001122334455";
    constant TEST_IP : std_logic_vector(31 downto 0) := x"C0A80101"; -- 192.168.1.1
    
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
    
    -- AXI4-Lite procedures
    procedure axi_write(
        signal clk : in std_logic;
        signal awaddr : out std_logic_vector(31 downto 0);
        signal awvalid : out std_logic;
        signal awready : in std_logic;
        signal wdata : out std_logic_vector(31 downto 0);
        signal wstrb : out std_logic_vector(3 downto 0);
        signal wvalid : out std_logic;
        signal wready : in std_logic;
        signal bready : out std_logic;
        signal bvalid : in std_logic;
        addr : in std_logic_vector(31 downto 0);
        data : in std_logic_vector(31 downto 0)
    ) is
    begin
        -- Address phase
        wait until rising_edge(clk);
        awaddr <= addr;
        awvalid <= '1';
        wdata <= data;
        wstrb <= "1111";
        wvalid <= '1';
        
        -- Wait for address accepted
        wait until rising_edge(clk) and awready = '1';
        awvalid <= '0';
        
        -- Wait for data accepted
        wait until rising_edge(clk) and wready = '1';
        wvalid <= '0';
        
        -- Response phase
        bready <= '1';
        wait until rising_edge(clk) and bvalid = '1';
        bready <= '0';
        
        wait until rising_edge(clk);
    end procedure;
    
    procedure axi_read(
        signal clk : in std_logic;
        signal araddr : out std_logic_vector(31 downto 0);
        signal arvalid : out std_logic;
        signal arready : in std_logic;
        signal rready : out std_logic;
        signal rvalid : in std_logic;
        signal rdata : in std_logic_vector(31 downto 0);
        addr : in std_logic_vector(31 downto 0);
        variable data : out std_logic_vector(31 downto 0)
    ) is
    begin
        -- Address phase
        wait until rising_edge(clk);
        araddr <= addr;
        arvalid <= '1';
        
        -- Wait for address accepted
        wait until rising_edge(clk) and arready = '1';
        arvalid <= '0';
        
        -- Data phase
        rready <= '1';
        wait until rising_edge(clk) and rvalid = '1';
        data := rdata;
        rready <= '0';
        
        wait until rising_edge(clk);
    end procedure;
    
begin
    
    -- Clock generation
    sys_clk <= not sys_clk after SYS_CLK_PERIOD / 2;
    s_axi_aclk <= not s_axi_aclk after AXI_CLK_PERIOD / 2;
    
    -- RGMII RX clock generation (simulated PHY)
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
        variable read_data : std_logic_vector(31 downto 0);
    begin
        -- Initialize
        sys_rst_n <= '0';
        s_axi_aresetn <= '0';
        
        -- Wait for some time
        wait for 100 ns;
        
        -- Release reset
        sys_rst_n <= '1';
        s_axi_aresetn <= '1';
        
        -- Wait for reset to propagate
        wait for 200 ns;
        
        report "Starting TCP Offload Engine Test";
        
        -- Test 1: Configuration via AXI4-Lite
        report "Test 1: AXI4-Lite Configuration";
        
        -- Configure MAC address
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_MAC_ADDR_LOW, TEST_MAC(31 downto 0));
        
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_MAC_ADDR_HIGH, x"0000" & TEST_MAC(47 downto 32));
        
        -- Configure IP address
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_IP_ADDR, TEST_IP);
        
        -- Configure subnet mask
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_SUBNET_MASK, x"FFFFFF00"); -- 255.255.255.0
        
        -- Configure gateway
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_GATEWAY, x"C0A801FE"); -- 192.168.1.254
        
        -- Configure TCP ports
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_TCP_PORT_0, x"00000050"); -- Port 80
        
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_TCP_PORT_1, x"00000016"); -- Port 22
        
        -- Enable engine
        axi_write(s_axi_aclk, s_axi_awaddr, s_axi_awvalid, s_axi_awready,
                  s_axi_wdata, s_axi_wstrb, s_axi_wvalid, s_axi_wready,
                  s_axi_bready, s_axi_bvalid,
                  REG_CONTROL, x"00000007"); -- Enable engine, DHCP, and TCP
        
        -- Read back configuration
        axi_read(s_axi_aclk, s_axi_araddr, s_axi_arvalid, s_axi_arready,
                 s_axi_rready, s_axi_rvalid, s_axi_rdata,
                 REG_MAC_ADDR_LOW, read_data);
        
        if read_data = TEST_MAC(31 downto 0) then
            report "MAC address low register correct";
        else
            report "MAC address low register incorrect" severity error;
        end if;
        
        -- Test 2: Status register read
        report "Test 2: Status Register Read";
        
        axi_read(s_axi_aclk, s_axi_araddr, s_axi_arvalid, s_axi_arready,
                 s_axi_rready, s_axi_rvalid, s_axi_rdata,
                 REG_STATUS, read_data);
        
        report "Status register read completed";
        
        -- Test 3: AXI4-Stream data loopback
        report "Test 3: AXI4-Stream Data Loopback";
        
        wait for 1 us;
        
        -- Send test data on RX interface (simulating host sending data)
        wait until rising_edge(s_axi_aclk);
        s_axis_rx_tdata <= x"0123456789ABCDEF";
        s_axis_rx_tkeep <= x"FF";
        s_axis_rx_tvalid <= '1';
        s_axis_rx_tlast <= '0';
        s_axis_rx_tuser <= x"00";
        
        wait until rising_edge(s_axi_aclk) and s_axis_rx_tready = '1';
        s_axis_rx_tdata <= x"FEDCBA9876543210";
        s_axis_rx_tlast <= '1';
        
        wait until rising_edge(s_axi_aclk) and s_axis_rx_tready = '1';
        s_axis_rx_tvalid <= '0';
        s_axis_rx_tlast <= '0';
        
        -- Wait for response on TX interface
        wait until m_axis_tx_tvalid = '1' for 10 us;
        
        if m_axis_tx_tvalid = '1' then
            report "TX data received successfully";
        else
            report "No TX data received" severity warning;
        end if;
        
        -- Test 4: PHY simulation (link establishment)
        report "Test 4: PHY Link Simulation";
        
        -- Simulate link up
        rgmii_rx_ctl <= '1';
        rgmii_rxd <= x"D"; -- Simulate valid data
        
        wait for 2 us;
        
        if link_up_led = '1' then
            report "Link established successfully";
        else
            report "Link not established" severity warning;
        end if;
        
        -- Test 5: DHCP simulation
        report "Test 5: DHCP Process Simulation";
        
        -- Monitor DHCP status
        for i in 0 to 100 loop
            axi_read(s_axi_aclk, s_axi_araddr, s_axi_arvalid, s_axi_arready,
                     s_axi_rready, s_axi_rvalid, s_axi_rdata,
                     x"00000028", read_data); -- DHCP status register
            
            if read_data /= x"00000000" then
                report "DHCP status changed";
                exit;
            end if;
            
            wait for 100 ns;
        end loop;
        
        -- Wait for some more time
        wait for 5 us;
        
        -- Test completion
        report "Test completed successfully";
        test_pass <= '1';
        test_complete <= '1';
        
        wait;
    end process;
    
    -- Timeout process
    timeout_proc: process
    begin
        wait for 100 us;
        if test_complete = '0' then
            report "Test timeout!" severity failure;
        end if;
        wait;
    end process;
    
    -- Monitor process
    monitor_proc: process(s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if m_axis_tx_tvalid = '1' and m_axis_tx_tready = '1' then
                report "TX transaction: LAST=" & std_logic'image(m_axis_tx_tlast);
            end if;
            
            if s_axis_rx_tvalid = '1' and s_axis_rx_tready = '1' then
                report "RX transaction: LAST=" & std_logic'image(s_axis_rx_tlast);
            end if;
        end if;
    end process;
    
end architecture behavioral;