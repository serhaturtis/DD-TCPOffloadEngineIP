library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity tcp_offload_engine_top is
    port (
        -- System Clock and Reset
        sys_clk : in std_logic;
        sys_rst_n : in std_logic;
        
        -- RGMII PHY Interface
        rgmii_txd : out std_logic_vector(3 downto 0);
        rgmii_tx_ctl : out std_logic;
        rgmii_txc : out std_logic;
        rgmii_rxd : in std_logic_vector(3 downto 0);
        rgmii_rx_ctl : in std_logic;
        rgmii_rxc : in std_logic;
        
        -- MDIO Interface
        mdc : out std_logic;
        mdio : inout std_logic;
        
        -- AXI4-Lite Control Interface
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
        
        -- AXI4-Stream Data Interface (TX - Host to Network)
        m_axis_tx_tdata : out std_logic_vector(63 downto 0);
        m_axis_tx_tkeep : out std_logic_vector(7 downto 0);
        m_axis_tx_tvalid : out std_logic;
        m_axis_tx_tready : in std_logic;
        m_axis_tx_tlast : out std_logic;
        m_axis_tx_tuser : out std_logic_vector(7 downto 0);
        
        -- AXI4-Stream Data Interface (RX - Network to Host)
        s_axis_rx_tdata : in std_logic_vector(63 downto 0);
        s_axis_rx_tkeep : in std_logic_vector(7 downto 0);
        s_axis_rx_tvalid : in std_logic;
        s_axis_rx_tready : out std_logic;
        s_axis_rx_tlast : in std_logic;
        s_axis_rx_tuser : in std_logic_vector(7 downto 0);
        
        -- Status LEDs
        link_up_led : out std_logic;
        activity_led : out std_logic;
        error_led : out std_logic
    );
end entity tcp_offload_engine_top;

architecture rtl of tcp_offload_engine_top is
    
    -- Clock generation
    signal clk_125mhz : std_logic;
    signal clk_25mhz : std_logic;
    signal clk_2_5mhz : std_logic;
    signal clk_locked : std_logic;
    
    -- Reset synchronization
    signal rst_n_sync : std_logic;
    signal rst_n_125mhz : std_logic;
    
    -- Configuration registers
    signal reg_control : std_logic_vector(31 downto 0);
    signal reg_status : std_logic_vector(31 downto 0);
    signal reg_mac_addr_low : std_logic_vector(31 downto 0);
    signal reg_mac_addr_high : std_logic_vector(31 downto 0);
    signal reg_ip_addr : std_logic_vector(31 downto 0);
    signal reg_subnet_mask : std_logic_vector(31 downto 0);
    signal reg_gateway : std_logic_vector(31 downto 0);
    signal reg_tcp_port_0 : std_logic_vector(31 downto 0);
    signal reg_tcp_port_1 : std_logic_vector(31 downto 0);
    
    -- MAC address reconstruction
    signal local_mac : std_logic_vector(47 downto 0);
    
    -- Status signals
    signal tcp_status : std_logic_vector(31 downto 0);
    signal dhcp_status : std_logic_vector(31 downto 0);
    signal link_status : std_logic_vector(31 downto 0);
    signal packet_counters : std_logic_vector(31 downto 0);
    
    -- RGMII to MAC interface
    signal mac_tx_data : std_logic_vector(7 downto 0);
    signal mac_tx_valid : std_logic;
    signal mac_tx_ready : std_logic;
    signal mac_tx_last : std_logic;
    signal mac_tx_error : std_logic;
    signal mac_rx_data : std_logic_vector(7 downto 0);
    signal mac_rx_valid : std_logic;
    signal mac_rx_ready : std_logic;
    signal mac_rx_last : std_logic;
    signal mac_rx_error : std_logic;
    
    -- Ethernet MAC to IP interface
    signal eth_tx_dst_mac : std_logic_vector(47 downto 0);
    signal eth_tx_src_mac : std_logic_vector(47 downto 0);
    signal eth_tx_ethertype : std_logic_vector(15 downto 0);
    signal eth_tx_payload_data : std_logic_vector(7 downto 0);
    signal eth_tx_payload_valid : std_logic;
    signal eth_tx_payload_ready : std_logic;
    signal eth_tx_payload_last : std_logic;
    signal eth_tx_start : std_logic;
    signal eth_rx_dst_mac : std_logic_vector(47 downto 0);
    signal eth_rx_src_mac : std_logic_vector(47 downto 0);
    signal eth_rx_ethertype : std_logic_vector(15 downto 0);
    signal eth_rx_payload_data : std_logic_vector(7 downto 0);
    signal eth_rx_payload_valid : std_logic;
    signal eth_rx_payload_ready : std_logic;
    signal eth_rx_payload_last : std_logic;
    signal eth_rx_frame_valid : std_logic;
    signal eth_rx_frame_error : std_logic;
    
    -- IP layer interfaces
    signal ip_tx_dst_ip : std_logic_vector(31 downto 0);
    signal ip_tx_src_ip : std_logic_vector(31 downto 0);
    signal ip_tx_protocol : std_logic_vector(7 downto 0);
    signal ip_tx_length : std_logic_vector(15 downto 0);
    signal ip_tx_data : std_logic_vector(7 downto 0);
    signal ip_tx_valid : std_logic;
    signal ip_tx_ready : std_logic;
    signal ip_tx_last : std_logic;
    signal ip_tx_start : std_logic;
    signal ip_rx_dst_ip : std_logic_vector(31 downto 0);
    signal ip_rx_src_ip : std_logic_vector(31 downto 0);
    signal ip_rx_protocol : std_logic_vector(7 downto 0);
    signal ip_rx_length : std_logic_vector(15 downto 0);
    signal ip_rx_data : std_logic_vector(7 downto 0);
    signal ip_rx_valid : std_logic;
    signal ip_rx_ready : std_logic;
    signal ip_rx_last : std_logic;
    signal ip_rx_frame_valid : std_logic;
    signal ip_rx_frame_error : std_logic;
    
    -- TCP engine interfaces
    signal tcp_tx_data : std_logic_vector(63 downto 0);
    signal tcp_tx_keep : std_logic_vector(7 downto 0);
    signal tcp_tx_valid : std_logic;
    signal tcp_tx_ready : std_logic;
    signal tcp_tx_last : std_logic;
    signal tcp_connection_id : std_logic_vector(0 downto 0) := "0";
    signal tcp_rx_data : std_logic_vector(63 downto 0);
    signal tcp_rx_keep : std_logic_vector(7 downto 0);
    signal tcp_rx_valid : std_logic;
    signal tcp_rx_ready : std_logic;
    signal tcp_rx_last : std_logic;
    signal tcp_rx_connection_id : std_logic_vector(0 downto 0);
    
    -- UDP/DHCP interfaces
    signal udp_tx_dst_ip : std_logic_vector(31 downto 0);
    signal udp_tx_src_ip : std_logic_vector(31 downto 0);
    signal udp_tx_protocol : std_logic_vector(7 downto 0);
    signal udp_tx_length : std_logic_vector(15 downto 0);
    signal udp_tx_data : std_logic_vector(7 downto 0);
    signal udp_tx_valid : std_logic;
    signal udp_tx_ready : std_logic;
    signal udp_tx_last : std_logic;
    signal udp_tx_start : std_logic;
    signal udp_rx_dst_ip : std_logic_vector(31 downto 0);
    signal udp_rx_src_ip : std_logic_vector(31 downto 0);
    signal udp_rx_protocol : std_logic_vector(7 downto 0);
    signal udp_rx_length : std_logic_vector(15 downto 0);
    signal udp_rx_data : std_logic_vector(7 downto 0);
    signal udp_rx_valid : std_logic;
    signal udp_rx_ready : std_logic;
    signal udp_rx_last : std_logic;
    signal udp_rx_frame_valid : std_logic;
    signal udp_rx_frame_error : std_logic;
    
    -- DHCP interface
    signal dhcp_tx_data : std_logic_vector(7 downto 0);
    signal dhcp_tx_valid : std_logic;
    signal dhcp_tx_ready : std_logic;
    signal dhcp_tx_last : std_logic;
    signal dhcp_tx_start : std_logic;
    signal dhcp_rx_data : std_logic_vector(7 downto 0);
    signal dhcp_rx_valid : std_logic;
    signal dhcp_rx_ready : std_logic;
    signal dhcp_rx_last : std_logic;
    
    -- DHCP configuration outputs
    signal dhcp_assigned_ip : std_logic_vector(31 downto 0);
    signal dhcp_subnet_mask : std_logic_vector(31 downto 0);
    signal dhcp_gateway_ip : std_logic_vector(31 downto 0);
    signal dhcp_dns_server : std_logic_vector(31 downto 0);
    signal dhcp_lease_time : std_logic_vector(31 downto 0);
    signal dhcp_complete : std_logic;
    signal dhcp_error : std_logic;
    signal dhcp_state : std_logic_vector(7 downto 0);
    
    -- Link status
    signal link_up : std_logic;
    signal link_speed : std_logic_vector(1 downto 0);
    signal link_duplex : std_logic;
    signal auto_neg_complete : std_logic;
    
    -- Stream control
    signal stream_control : std_logic_vector(31 downto 0);
    signal stream_status : std_logic_vector(31 downto 0);
    signal connection_active : std_logic_vector(1 downto 0);
    signal connection_ports : std_logic_vector(31 downto 0);
    
    -- Control flags
    signal engine_enable : std_logic;
    signal dhcp_enable : std_logic;
    signal tcp_enable : std_logic;
    
    -- Component declarations
    component rgmii_interface is
        port (
            clk_125mhz : in std_logic;
            clk_25mhz : in std_logic;
            clk_2_5mhz : in std_logic;
            rst_n : in std_logic;
            rgmii_txd : out std_logic_vector(3 downto 0);
            rgmii_tx_ctl : out std_logic;
            rgmii_txc : out std_logic;
            rgmii_rxd : in std_logic_vector(3 downto 0);
            rgmii_rx_ctl : in std_logic;
            rgmii_rxc : in std_logic;
            mdc : out std_logic;
            mdio : inout std_logic;
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
            link_up : out std_logic;
            link_speed : out std_logic_vector(1 downto 0);
            link_duplex : out std_logic;
            auto_neg_complete : out std_logic
        );
    end component;
    
    component ethernet_mac is
        port (
            clk : in std_logic;
            rst_n : in std_logic;
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
            tx_dst_mac : in std_logic_vector(47 downto 0);
            tx_src_mac : in std_logic_vector(47 downto 0);
            tx_ethertype : in std_logic_vector(15 downto 0);
            tx_payload_data : in std_logic_vector(7 downto 0);
            tx_payload_valid : in std_logic;
            tx_payload_ready : out std_logic;
            tx_payload_last : in std_logic;
            tx_start : in std_logic;
            rx_dst_mac : out std_logic_vector(47 downto 0);
            rx_src_mac : out std_logic_vector(47 downto 0);
            rx_ethertype : out std_logic_vector(15 downto 0);
            rx_payload_data : out std_logic_vector(7 downto 0);
            rx_payload_valid : out std_logic;
            rx_payload_ready : in std_logic;
            rx_payload_last : out std_logic;
            rx_frame_valid : out std_logic;
            rx_frame_error : out std_logic;
            local_mac : in std_logic_vector(47 downto 0);
            promiscuous_mode : in std_logic
        );
    end component;
    
    component ip_layer is
        port (
            clk : in std_logic;
            rst_n : in std_logic;
            eth_tx_dst_mac : out std_logic_vector(47 downto 0);
            eth_tx_src_mac : out std_logic_vector(47 downto 0);
            eth_tx_ethertype : out std_logic_vector(15 downto 0);
            eth_tx_payload_data : out std_logic_vector(7 downto 0);
            eth_tx_payload_valid : out std_logic;
            eth_tx_payload_ready : in std_logic;
            eth_tx_payload_last : out std_logic;
            eth_tx_start : out std_logic;
            eth_rx_dst_mac : in std_logic_vector(47 downto 0);
            eth_rx_src_mac : in std_logic_vector(47 downto 0);
            eth_rx_ethertype : in std_logic_vector(15 downto 0);
            eth_rx_payload_data : in std_logic_vector(7 downto 0);
            eth_rx_payload_valid : in std_logic;
            eth_rx_payload_ready : out std_logic;
            eth_rx_payload_last : in std_logic;
            eth_rx_frame_valid : in std_logic;
            eth_rx_frame_error : in std_logic;
            ul_tx_dst_ip : in std_logic_vector(31 downto 0);
            ul_tx_src_ip : in std_logic_vector(31 downto 0);
            ul_tx_protocol : in std_logic_vector(7 downto 0);
            ul_tx_length : in std_logic_vector(15 downto 0);
            ul_tx_data : in std_logic_vector(7 downto 0);
            ul_tx_valid : in std_logic;
            ul_tx_ready : out std_logic;
            ul_tx_last : in std_logic;
            ul_tx_start : in std_logic;
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
            arp_request_ip : out std_logic_vector(31 downto 0);
            arp_request_valid : out std_logic;
            arp_response_mac : in std_logic_vector(47 downto 0);
            arp_response_valid : in std_logic;
            local_ip : in std_logic_vector(31 downto 0);
            local_mac : in std_logic_vector(47 downto 0);
            gateway_ip : in std_logic_vector(31 downto 0);
            subnet_mask : in std_logic_vector(31 downto 0)
        );
    end component;
    
    component tcp_engine is
        port (
            clk : in std_logic;
            rst_n : in std_logic;
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
            local_ip : in std_logic_vector(31 downto 0);
            tcp_status : out std_logic_vector(31 downto 0)
        );
    end component;
    
    component udp_engine is
        port (
            clk : in std_logic;
            rst_n : in std_logic;
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
            app_tx_dst_ip : in std_logic_vector(31 downto 0);
            app_tx_dst_port : in std_logic_vector(15 downto 0);
            app_tx_src_port : in std_logic_vector(15 downto 0);
            app_tx_data : in std_logic_vector(63 downto 0);
            app_tx_keep : in std_logic_vector(7 downto 0);
            app_tx_valid : in std_logic;
            app_tx_ready : out std_logic;
            app_tx_last : in std_logic;
            app_tx_start : in std_logic;
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
            dhcp_tx_data : in std_logic_vector(7 downto 0);
            dhcp_tx_valid : in std_logic;
            dhcp_tx_ready : out std_logic;
            dhcp_tx_last : in std_logic;
            dhcp_tx_start : in std_logic;
            dhcp_rx_data : out std_logic_vector(7 downto 0);
            dhcp_rx_valid : out std_logic;
            dhcp_rx_ready : in std_logic;
            dhcp_rx_last : out std_logic;
            local_ip : in std_logic_vector(31 downto 0)
        );
    end component;
    
    component dhcp_client is
        port (
            clk : in std_logic;
            rst_n : in std_logic;
            udp_tx_data : out std_logic_vector(7 downto 0);
            udp_tx_valid : out std_logic;
            udp_tx_ready : in std_logic;
            udp_tx_last : out std_logic;
            udp_tx_start : out std_logic;
            udp_rx_data : in std_logic_vector(7 downto 0);
            udp_rx_valid : in std_logic;
            udp_rx_ready : out std_logic;
            udp_rx_last : in std_logic;
            assigned_ip : out std_logic_vector(31 downto 0);
            subnet_mask : out std_logic_vector(31 downto 0);
            gateway_ip : out std_logic_vector(31 downto 0);
            dns_server : out std_logic_vector(31 downto 0);
            lease_time : out std_logic_vector(31 downto 0);
            start_dhcp : in std_logic;
            renew_lease : in std_logic;
            release_lease : in std_logic;
            dhcp_complete : out std_logic;
            dhcp_error : out std_logic;
            dhcp_state : out std_logic_vector(7 downto 0);
            client_mac : in std_logic_vector(47 downto 0);
            client_id : in std_logic_vector(31 downto 0)
        );
    end component;
    
    component axi4_lite_interface is
        port (
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
            reg_control : out std_logic_vector(31 downto 0);
            reg_status : in std_logic_vector(31 downto 0);
            reg_mac_addr_low : out std_logic_vector(31 downto 0);
            reg_mac_addr_high : out std_logic_vector(31 downto 0);
            reg_ip_addr : out std_logic_vector(31 downto 0);
            reg_subnet_mask : out std_logic_vector(31 downto 0);
            reg_gateway : out std_logic_vector(31 downto 0);
            reg_tcp_port_0 : out std_logic_vector(31 downto 0);
            reg_tcp_port_1 : out std_logic_vector(31 downto 0);
            tcp_status : in std_logic_vector(31 downto 0);
            dhcp_status : in std_logic_vector(31 downto 0);
            link_status : in std_logic_vector(31 downto 0);
            packet_counters : in std_logic_vector(31 downto 0)
        );
    end component;
    
    component axi4_stream_interface is
        port (
            aclk : in std_logic;
            aresetn : in std_logic;
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
            tcp_tx_data : in std_logic_vector(63 downto 0);
            tcp_tx_keep : in std_logic_vector(7 downto 0);
            tcp_tx_valid : in std_logic;
            tcp_tx_ready : out std_logic;
            tcp_tx_last : in std_logic;
            tcp_connection_id : in std_logic_vector(0 downto 0);
            tcp_rx_data : out std_logic_vector(63 downto 0);
            tcp_rx_keep : out std_logic_vector(7 downto 0);
            tcp_rx_valid : out std_logic;
            tcp_rx_ready : in std_logic;
            tcp_rx_last : out std_logic;
            tcp_rx_connection_id : out std_logic_vector(0 downto 0);
            stream_control : in std_logic_vector(31 downto 0);
            stream_status : out std_logic_vector(31 downto 0);
            connection_active : in std_logic_vector(1 downto 0);
            connection_ports : in std_logic_vector(31 downto 0)
        );
    end component;
    
begin
    
    -- Clock generation (simplified - would use proper MMCM/PLL in real design)
    clk_125mhz <= sys_clk; -- Assume 125MHz input
    clk_25mhz <= sys_clk; -- Divided clock for 100M operation
    clk_2_5mhz <= sys_clk; -- Divided clock for 10M operation
    clk_locked <= '1';
    
    -- Reset synchronization
    process(clk_125mhz, sys_rst_n)
    begin
        if sys_rst_n = '0' then
            rst_n_sync <= '0';
            rst_n_125mhz <= '0';
        elsif rising_edge(clk_125mhz) then
            rst_n_sync <= '1';
            rst_n_125mhz <= rst_n_sync;
        end if;
    end process;
    
    -- Configuration
    local_mac <= reg_mac_addr_high(15 downto 0) & reg_mac_addr_low;
    engine_enable <= reg_control(0);
    dhcp_enable <= reg_control(1);
    tcp_enable <= reg_control(2);
    
    -- Status construction
    reg_status <= x"0000" & dhcp_complete & dhcp_error & auto_neg_complete & link_up & 
                 link_speed & link_duplex & clk_locked & engine_enable & 
                 dhcp_enable & tcp_enable & "00000";
    
    dhcp_status <= dhcp_lease_time;
    link_status <= x"000000" & dhcp_state;
    packet_counters <= x"00000000"; -- Placeholder
    
    connection_active <= "11" when tcp_enable = '1' else "00";
    connection_ports <= reg_tcp_port_1(15 downto 0) & reg_tcp_port_0(15 downto 0);
    stream_control <= reg_control;
    
    -- Status LEDs
    link_up_led <= link_up;
    activity_led <= eth_tx_payload_valid or eth_rx_payload_valid;
    error_led <= dhcp_error or not clk_locked;
    
    -- Component instantiations
    rgmii_inst: rgmii_interface
        port map (
            clk_125mhz => clk_125mhz,
            clk_25mhz => clk_25mhz,
            clk_2_5mhz => clk_2_5mhz,
            rst_n => rst_n_125mhz,
            rgmii_txd => rgmii_txd,
            rgmii_tx_ctl => rgmii_tx_ctl,
            rgmii_txc => rgmii_txc,
            rgmii_rxd => rgmii_rxd,
            rgmii_rx_ctl => rgmii_rx_ctl,
            rgmii_rxc => rgmii_rxc,
            mdc => mdc,
            mdio => mdio,
            mac_tx_data => mac_tx_data,
            mac_tx_valid => mac_tx_valid,
            mac_tx_ready => mac_tx_ready,
            mac_tx_last => mac_tx_last,
            mac_tx_error => mac_tx_error,
            mac_rx_data => mac_rx_data,
            mac_rx_valid => mac_rx_valid,
            mac_rx_ready => mac_rx_ready,
            mac_rx_last => mac_rx_last,
            mac_rx_error => mac_rx_error,
            link_up => link_up,
            link_speed => link_speed,
            link_duplex => link_duplex,
            auto_neg_complete => auto_neg_complete
        );
    
    ethernet_mac_inst: ethernet_mac
        port map (
            clk => clk_125mhz,
            rst_n => rst_n_125mhz,
            phy_tx_data => mac_tx_data,
            phy_tx_valid => mac_tx_valid,
            phy_tx_ready => mac_tx_ready,
            phy_tx_last => mac_tx_last,
            phy_tx_error => mac_tx_error,
            phy_rx_data => mac_rx_data,
            phy_rx_valid => mac_rx_valid,
            phy_rx_ready => mac_rx_ready,
            phy_rx_last => mac_rx_last,
            phy_rx_error => mac_rx_error,
            tx_dst_mac => eth_tx_dst_mac,
            tx_src_mac => eth_tx_src_mac,
            tx_ethertype => eth_tx_ethertype,
            tx_payload_data => eth_tx_payload_data,
            tx_payload_valid => eth_tx_payload_valid,
            tx_payload_ready => eth_tx_payload_ready,
            tx_payload_last => eth_tx_payload_last,
            tx_start => eth_tx_start,
            rx_dst_mac => eth_rx_dst_mac,
            rx_src_mac => eth_rx_src_mac,
            rx_ethertype => eth_rx_ethertype,
            rx_payload_data => eth_rx_payload_data,
            rx_payload_valid => eth_rx_payload_valid,
            rx_payload_ready => eth_rx_payload_ready,
            rx_payload_last => eth_rx_payload_last,
            rx_frame_valid => eth_rx_frame_valid,
            rx_frame_error => eth_rx_frame_error,
            local_mac => local_mac,
            promiscuous_mode => '0'
        );
    
    ip_layer_inst: ip_layer
        port map (
            clk => clk_125mhz,
            rst_n => rst_n_125mhz,
            eth_tx_dst_mac => eth_tx_dst_mac,
            eth_tx_src_mac => eth_tx_src_mac,
            eth_tx_ethertype => eth_tx_ethertype,
            eth_tx_payload_data => eth_tx_payload_data,
            eth_tx_payload_valid => eth_tx_payload_valid,
            eth_tx_payload_ready => eth_tx_payload_ready,
            eth_tx_payload_last => eth_tx_payload_last,
            eth_tx_start => eth_tx_start,
            eth_rx_dst_mac => eth_rx_dst_mac,
            eth_rx_src_mac => eth_rx_src_mac,
            eth_rx_ethertype => eth_rx_ethertype,
            eth_rx_payload_data => eth_rx_payload_data,
            eth_rx_payload_valid => eth_rx_payload_valid,
            eth_rx_payload_ready => eth_rx_payload_ready,
            eth_rx_payload_last => eth_rx_payload_last,
            eth_rx_frame_valid => eth_rx_frame_valid,
            eth_rx_frame_error => eth_rx_frame_error,
            ul_tx_dst_ip => ip_tx_dst_ip,
            ul_tx_src_ip => ip_tx_src_ip,
            ul_tx_protocol => ip_tx_protocol,
            ul_tx_length => ip_tx_length,
            ul_tx_data => ip_tx_data,
            ul_tx_valid => ip_tx_valid,
            ul_tx_ready => ip_tx_ready,
            ul_tx_last => ip_tx_last,
            ul_tx_start => ip_tx_start,
            ul_rx_dst_ip => ip_rx_dst_ip,
            ul_rx_src_ip => ip_rx_src_ip,
            ul_rx_protocol => ip_rx_protocol,
            ul_rx_length => ip_rx_length,
            ul_rx_data => ip_rx_data,
            ul_rx_valid => ip_rx_valid,
            ul_rx_ready => ip_rx_ready,
            ul_rx_last => ip_rx_last,
            ul_rx_frame_valid => ip_rx_frame_valid,
            ul_rx_frame_error => ip_rx_frame_error,
            icmp_tx_type => (others => '0'),
            icmp_tx_code => (others => '0'),
            icmp_tx_data => (others => '0'),
            icmp_tx_valid => '0',
            icmp_tx_ready => open,
            icmp_tx_last => '0',
            icmp_tx_start => '0',
            icmp_rx_type => open,
            icmp_rx_code => open,
            icmp_rx_data => open,
            icmp_rx_valid => open,
            icmp_rx_ready => '1',
            icmp_rx_last => open,
            arp_request_ip => open,
            arp_request_valid => open,
            arp_response_mac => (others => '0'),
            arp_response_valid => '0',
            local_ip => reg_ip_addr,
            local_mac => local_mac,
            gateway_ip => reg_gateway,
            subnet_mask => reg_subnet_mask
        );
    
    tcp_engine_inst: tcp_engine
        port map (
            clk => clk_125mhz,
            rst_n => rst_n_125mhz and tcp_enable,
            ip_tx_dst_ip => ip_tx_dst_ip,
            ip_tx_src_ip => ip_tx_src_ip,
            ip_tx_protocol => ip_tx_protocol,
            ip_tx_length => ip_tx_length,
            ip_tx_data => ip_tx_data,
            ip_tx_valid => ip_tx_valid,
            ip_tx_ready => ip_tx_ready,
            ip_tx_last => ip_tx_last,
            ip_tx_start => ip_tx_start,
            ip_rx_dst_ip => ip_rx_dst_ip,
            ip_rx_src_ip => ip_rx_src_ip,
            ip_rx_protocol => ip_rx_protocol,
            ip_rx_length => ip_rx_length,
            ip_rx_data => ip_rx_data,
            ip_rx_valid => ip_rx_valid,
            ip_rx_ready => ip_rx_ready,
            ip_rx_last => ip_rx_last,
            ip_rx_frame_valid => ip_rx_frame_valid,
            ip_rx_frame_error => ip_rx_frame_error,
            app_tx_data => tcp_tx_data,
            app_tx_keep => tcp_tx_keep,
            app_tx_valid => tcp_tx_valid,
            app_tx_ready => tcp_tx_ready,
            app_tx_last => tcp_tx_last,
            app_connect => '0',
            app_listen => '1',
            app_close => '0',
            app_port => reg_tcp_port_0(15 downto 0),
            app_remote_ip => (others => '0'),
            app_remote_port => (others => '0'),
            app_connection_id => tcp_connection_id,
            app_rx_data => tcp_rx_data,
            app_rx_keep => tcp_rx_keep,
            app_rx_valid => tcp_rx_valid,
            app_rx_ready => tcp_rx_ready,
            app_rx_last => tcp_rx_last,
            app_connected => open,
            app_connection_error => open,
            local_ip => reg_ip_addr,
            tcp_status => tcp_status
        );
    
    udp_engine_inst: udp_engine
        port map (
            clk => clk_125mhz,
            rst_n => rst_n_125mhz,
            ip_tx_dst_ip => udp_tx_dst_ip,
            ip_tx_src_ip => udp_tx_src_ip,
            ip_tx_protocol => udp_tx_protocol,
            ip_tx_length => udp_tx_length,
            ip_tx_data => udp_tx_data,
            ip_tx_valid => udp_tx_valid,
            ip_tx_ready => udp_tx_ready,
            ip_tx_last => udp_tx_last,
            ip_tx_start => udp_tx_start,
            ip_rx_dst_ip => udp_rx_dst_ip,
            ip_rx_src_ip => udp_rx_src_ip,
            ip_rx_protocol => udp_rx_protocol,
            ip_rx_length => udp_rx_length,
            ip_rx_data => udp_rx_data,
            ip_rx_valid => udp_rx_valid,
            ip_rx_ready => udp_rx_ready,
            ip_rx_last => udp_rx_last,
            ip_rx_frame_valid => udp_rx_frame_valid,
            ip_rx_frame_error => udp_rx_frame_error,
            app_tx_dst_ip => (others => '0'),
            app_tx_dst_port => (others => '0'),
            app_tx_src_port => (others => '0'),
            app_tx_data => (others => '0'),
            app_tx_keep => (others => '0'),
            app_tx_valid => '0',
            app_tx_ready => open,
            app_tx_last => '0',
            app_tx_start => '0',
            app_rx_src_ip => open,
            app_rx_src_port => open,
            app_rx_dst_port => open,
            app_rx_data => open,
            app_rx_keep => open,
            app_rx_valid => open,
            app_rx_ready => '1',
            app_rx_last => open,
            app_rx_frame_valid => open,
            app_rx_frame_error => open,
            dhcp_tx_data => dhcp_tx_data,
            dhcp_tx_valid => dhcp_tx_valid,
            dhcp_tx_ready => dhcp_tx_ready,
            dhcp_tx_last => dhcp_tx_last,
            dhcp_tx_start => dhcp_tx_start,
            dhcp_rx_data => dhcp_rx_data,
            dhcp_rx_valid => dhcp_rx_valid,
            dhcp_rx_ready => dhcp_rx_ready,
            dhcp_rx_last => dhcp_rx_last,
            local_ip => reg_ip_addr
        );
    
    dhcp_client_inst: dhcp_client
        port map (
            clk => clk_125mhz,
            rst_n => rst_n_125mhz and dhcp_enable,
            udp_tx_data => dhcp_tx_data,
            udp_tx_valid => dhcp_tx_valid,
            udp_tx_ready => dhcp_tx_ready,
            udp_tx_last => dhcp_tx_last,
            udp_tx_start => dhcp_tx_start,
            udp_rx_data => dhcp_rx_data,
            udp_rx_valid => dhcp_rx_valid,
            udp_rx_ready => dhcp_rx_ready,
            udp_rx_last => dhcp_rx_last,
            assigned_ip => dhcp_assigned_ip,
            subnet_mask => dhcp_subnet_mask,
            gateway_ip => dhcp_gateway_ip,
            dns_server => dhcp_dns_server,
            lease_time => dhcp_lease_time,
            start_dhcp => dhcp_enable,
            renew_lease => '0',
            release_lease => '0',
            dhcp_complete => dhcp_complete,
            dhcp_error => dhcp_error,
            dhcp_state => dhcp_state,
            client_mac => local_mac,
            client_id => x"12345678"
        );
    
    axi4_lite_inst: axi4_lite_interface
        port map (
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
            reg_control => reg_control,
            reg_status => reg_status,
            reg_mac_addr_low => reg_mac_addr_low,
            reg_mac_addr_high => reg_mac_addr_high,
            reg_ip_addr => reg_ip_addr,
            reg_subnet_mask => reg_subnet_mask,
            reg_gateway => reg_gateway,
            reg_tcp_port_0 => reg_tcp_port_0,
            reg_tcp_port_1 => reg_tcp_port_1,
            tcp_status => tcp_status,
            dhcp_status => dhcp_status,
            link_status => link_status,
            packet_counters => packet_counters
        );
    
    axi4_stream_inst: axi4_stream_interface
        port map (
            aclk => s_axi_aclk,
            aresetn => s_axi_aresetn,
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
            tcp_tx_data => tcp_tx_data,
            tcp_tx_keep => tcp_tx_keep,
            tcp_tx_valid => tcp_tx_valid,
            tcp_tx_ready => tcp_tx_ready,
            tcp_tx_last => tcp_tx_last,
            tcp_connection_id => tcp_connection_id,
            tcp_rx_data => tcp_rx_data,
            tcp_rx_keep => tcp_rx_keep,
            tcp_rx_valid => tcp_rx_valid,
            tcp_rx_ready => tcp_rx_ready,
            tcp_rx_last => tcp_rx_last,
            tcp_rx_connection_id => tcp_rx_connection_id,
            stream_control => stream_control,
            stream_status => stream_status,
            connection_active => connection_active,
            connection_ports => connection_ports
        );
    
end architecture rtl;