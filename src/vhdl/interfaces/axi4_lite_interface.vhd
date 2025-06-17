library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity axi4_lite_interface is
    port (
        -- AXI4-Lite Clock and Reset
        s_axi_aclk : in std_logic;
        s_axi_aresetn : in std_logic;
        
        -- AXI4-Lite Write Address Channel
        s_axi_awaddr : in std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot : in std_logic_vector(2 downto 0);
        s_axi_awvalid : in std_logic;
        s_axi_awready : out std_logic;
        
        -- AXI4-Lite Write Data Channel
        s_axi_wdata : in std_logic_vector(AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb : in std_logic_vector((AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid : in std_logic;
        s_axi_wready : out std_logic;
        
        -- AXI4-Lite Write Response Channel
        s_axi_bresp : out std_logic_vector(1 downto 0);
        s_axi_bvalid : out std_logic;
        s_axi_bready : in std_logic;
        
        -- AXI4-Lite Read Address Channel
        s_axi_araddr : in std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot : in std_logic_vector(2 downto 0);
        s_axi_arvalid : in std_logic;
        s_axi_arready : out std_logic;
        
        -- AXI4-Lite Read Data Channel
        s_axi_rdata : out std_logic_vector(AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp : out std_logic_vector(1 downto 0);
        s_axi_rvalid : out std_logic;
        s_axi_rready : in std_logic;
        
        -- Internal Register Interface
        reg_control : out std_logic_vector(31 downto 0);
        reg_status : in std_logic_vector(31 downto 0);
        reg_mac_addr_low : out std_logic_vector(31 downto 0);
        reg_mac_addr_high : out std_logic_vector(31 downto 0);
        reg_ip_addr : out std_logic_vector(31 downto 0);
        reg_subnet_mask : out std_logic_vector(31 downto 0);
        reg_gateway : out std_logic_vector(31 downto 0);
        reg_tcp_port_0 : out std_logic_vector(31 downto 0);
        reg_tcp_port_1 : out std_logic_vector(31 downto 0);
        
        -- Additional status registers (read-only)
        tcp_status : in std_logic_vector(31 downto 0);
        dhcp_status : in std_logic_vector(31 downto 0);
        link_status : in std_logic_vector(31 downto 0);
        packet_counters : in std_logic_vector(31 downto 0)
    );
end entity axi4_lite_interface;

architecture rtl of axi4_lite_interface is
    
    -- AXI4-Lite State Machines
    type axi_write_state_t is (IDLE, ADDR_READY, DATA_READY, RESP_VALID);
    type axi_read_state_t is (IDLE, ADDR_READY, DATA_VALID);
    
    signal axi_write_state : axi_write_state_t := IDLE;
    signal axi_read_state : axi_read_state_t := IDLE;
    
    -- Internal registers
    signal reg_control_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_mac_addr_low_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_mac_addr_high_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_ip_addr_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_subnet_mask_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_gateway_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_tcp_port_0_int : std_logic_vector(31 downto 0) := (others => '0');
    signal reg_tcp_port_1_int : std_logic_vector(31 downto 0) := (others => '0');
    
    -- AXI4-Lite internal signals
    signal axi_awaddr : std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
    signal axi_awready : std_logic := '0';
    signal axi_wready : std_logic := '0';
    signal axi_bresp : std_logic_vector(1 downto 0) := "00";
    signal axi_bvalid : std_logic := '0';
    signal axi_araddr : std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
    signal axi_arready : std_logic := '0';
    signal axi_rdata : std_logic_vector(AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal axi_rresp : std_logic_vector(1 downto 0) := "00";
    signal axi_rvalid : std_logic := '0';
    
    -- Address decoding
    signal write_addr_valid : std_logic := '0';
    signal read_addr_valid : std_logic := '0';
    signal addr_decode_error : std_logic := '0';
    
begin
    
    -- AXI4-Lite outputs
    s_axi_awready <= axi_awready;
    s_axi_wready <= axi_wready;
    s_axi_bresp <= axi_bresp;
    s_axi_bvalid <= axi_bvalid;
    s_axi_arready <= axi_arready;
    s_axi_rdata <= axi_rdata;
    s_axi_rresp <= axi_rresp;
    s_axi_rvalid <= axi_rvalid;
    
    -- Register outputs
    reg_control <= reg_control_int;
    reg_mac_addr_low <= reg_mac_addr_low_int;
    reg_mac_addr_high <= reg_mac_addr_high_int;
    reg_ip_addr <= reg_ip_addr_int;
    reg_subnet_mask <= reg_subnet_mask_int;
    reg_gateway <= reg_gateway_int;
    reg_tcp_port_0 <= reg_tcp_port_0_int;
    reg_tcp_port_1 <= reg_tcp_port_1_int;
    
    -- AXI4-Lite Write State Machine
    process(s_axi_aclk, s_axi_aresetn)
    begin
        if s_axi_aresetn = '0' then
            axi_write_state <= IDLE;
            axi_awready <= '0';
            axi_wready <= '0';
            axi_bvalid <= '0';
            axi_bresp <= "00";
            axi_awaddr <= (others => '0');
            
            -- Reset all writable registers
            reg_control_int <= (others => '0');
            reg_mac_addr_low_int <= (others => '0');
            reg_mac_addr_high_int <= (others => '0');
            reg_ip_addr_int <= (others => '0');
            reg_subnet_mask_int <= (others => '0');
            reg_gateway_int <= (others => '0');
            reg_tcp_port_0_int <= (others => '0');
            reg_tcp_port_1_int <= (others => '0');
            
        elsif rising_edge(s_axi_aclk) then
            case axi_write_state is
                when IDLE =>
                    axi_awready <= '1';
                    axi_wready <= '0';
                    axi_bvalid <= '0';
                    if s_axi_awvalid = '1' then
                        axi_awaddr <= s_axi_awaddr;
                        axi_write_state <= ADDR_READY;
                        axi_awready <= '0';
                        axi_wready <= '1';
                    end if;
                
                when ADDR_READY =>
                    if s_axi_wvalid = '1' then
                        axi_write_state <= DATA_READY;
                        axi_wready <= '0';
                        
                        -- Decode address and write to register
                        if axi_awaddr = REG_CONTROL then
                                if s_axi_wstrb(0) = '1' then
                                    reg_control_int(7 downto 0) <= s_axi_wdata(7 downto 0);
                                end if;
                                if s_axi_wstrb(1) = '1' then
                                    reg_control_int(15 downto 8) <= s_axi_wdata(15 downto 8);
                                end if;
                                if s_axi_wstrb(2) = '1' then
                                    reg_control_int(23 downto 16) <= s_axi_wdata(23 downto 16);
                                end if;
                                if s_axi_wstrb(3) = '1' then
                                    reg_control_int(31 downto 24) <= s_axi_wdata(31 downto 24);
                                end if;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_MAC_ADDR_LOW then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_mac_addr_low_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_MAC_ADDR_HIGH then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_mac_addr_high_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_IP_ADDR then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_ip_addr_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_SUBNET_MASK then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_subnet_mask_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_GATEWAY then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_gateway_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_TCP_PORT_0 then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_tcp_port_0_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        elsif axi_awaddr = REG_TCP_PORT_1 then
                                for i in 0 to 3 loop
                                    if s_axi_wstrb(i) = '1' then
                                        reg_tcp_port_1_int((i+1)*8-1 downto i*8) <= s_axi_wdata((i+1)*8-1 downto i*8);
                                    end if;
                                end loop;
                                axi_bresp <= "00"; -- OKAY
                                
                        else
                                axi_bresp <= "10"; -- SLVERR
                        end if;
                    end if;
                
                when DATA_READY =>
                    axi_write_state <= RESP_VALID;
                    axi_bvalid <= '1';
                
                when RESP_VALID =>
                    if s_axi_bready = '1' then
                        axi_write_state <= IDLE;
                        axi_bvalid <= '0';
                    end if;
            end case;
        end if;
    end process;
    
    -- AXI4-Lite Read State Machine
    process(s_axi_aclk, s_axi_aresetn)
    begin
        if s_axi_aresetn = '0' then
            axi_read_state <= IDLE;
            axi_arready <= '0';
            axi_rvalid <= '0';
            axi_rresp <= "00";
            axi_rdata <= (others => '0');
            axi_araddr <= (others => '0');
        elsif rising_edge(s_axi_aclk) then
            case axi_read_state is
                when IDLE =>
                    axi_arready <= '1';
                    axi_rvalid <= '0';
                    if s_axi_arvalid = '1' then
                        axi_araddr <= s_axi_araddr;
                        axi_read_state <= ADDR_READY;
                        axi_arready <= '0';
                    end if;
                
                when ADDR_READY =>
                    axi_read_state <= DATA_VALID;
                    axi_rvalid <= '1';
                    
                    -- Decode address and read from register
                    if axi_araddr = REG_CONTROL then
                            axi_rdata <= reg_control_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_STATUS then
                            axi_rdata <= reg_status;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_MAC_ADDR_LOW then
                            axi_rdata <= reg_mac_addr_low_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_MAC_ADDR_HIGH then
                            axi_rdata <= reg_mac_addr_high_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_IP_ADDR then
                            axi_rdata <= reg_ip_addr_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_SUBNET_MASK then
                            axi_rdata <= reg_subnet_mask_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_GATEWAY then
                            axi_rdata <= reg_gateway_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_TCP_PORT_0 then
                            axi_rdata <= reg_tcp_port_0_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = REG_TCP_PORT_1 then
                            axi_rdata <= reg_tcp_port_1_int;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = x"00000024" then -- TCP Status
                            axi_rdata <= tcp_status;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = x"00000028" then -- DHCP Status
                            axi_rdata <= dhcp_status;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = x"0000002C" then -- Link Status
                            axi_rdata <= link_status;
                            axi_rresp <= "00"; -- OKAY
                            
                    elsif axi_araddr = x"00000030" then -- Packet Counters
                            axi_rdata <= packet_counters;
                            axi_rresp <= "00"; -- OKAY
                            
                    else
                            axi_rdata <= (others => '0');
                            axi_rresp <= "10"; -- SLVERR
                    end if;
                
                when DATA_VALID =>
                    if s_axi_rready = '1' then
                        axi_read_state <= IDLE;
                        axi_rvalid <= '0';
                    end if;
            end case;
        end if;
    end process;
    
end architecture rtl;