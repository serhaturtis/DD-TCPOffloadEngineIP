# TCP Offload Engine Integration Guide

## 🎯 Integration Overview

This guide provides step-by-step instructions for integrating the TCP Offload Engine into your FPGA design, including hardware connections, software drivers, and system-level considerations.

## 📋 Prerequisites

### Hardware Requirements

| Component | Specification | Notes |
|-----------|---------------|-------|
| **FPGA** | Xilinx 7-series or newer | Zynq, Kintex, Virtex supported |
| **BRAM** | ≥ 1 MB available | For packet buffering |
| **Logic Resources** | ≥ 15,000 LUTs | See resource utilization table |
| **Clock** | 125 MHz reference | System clock input |
| **Ethernet PHY** | RGMII compatible | 10/100/1000 Mbps support |

### Software Requirements

| Tool | Version | Purpose |
|------|---------|---------|
| **Vivado** | ≥ 2019.1 | FPGA implementation |
| **GHDL** | ≥ 0.37 | Simulation (optional) |
| **SDK/Vitis** | Latest | Software development |
| **AXI4 IP** | Standard | Host interface |

## 🔧 Hardware Integration

### Step 1: Clock and Reset Integration

```vhdl
-- Clock management example
entity system_top is
    port (
        -- External clocks
        sys_clk_p : in std_logic;  -- 200 MHz differential
        sys_clk_n : in std_logic;
        
        -- Reset
        cpu_reset_n : in std_logic;
        
        -- Other system signals...
    );
end entity;

architecture rtl of system_top is
    -- Clock signals
    signal clk_200mhz : std_logic;
    signal clk_125mhz : std_logic;
    signal clk_100mhz : std_logic;
    signal locked : std_logic;
    
    -- Reset signals
    signal rst_n_sync : std_logic;
    
begin
    -- Clock wizard instance
    clk_wiz_inst: clk_wiz_0
        port map (
            clk_out1 => clk_125mhz,  -- 125 MHz for TCP engine
            clk_out2 => clk_100mhz,  -- 100 MHz for AXI
            locked => locked,
            clk_in1_p => sys_clk_p,
            clk_in1_n => sys_clk_n
        );
    
    -- Reset synchronizer
    reset_sync_inst: entity work.reset_synchronizer
        port map (
            clk => clk_125mhz,
            async_reset => not (cpu_reset_n and locked),
            sync_reset_n => rst_n_sync
        );
    
    -- TCP Offload Engine instance
    tcp_offload_inst: entity work.tcp_offload_engine_top
        port map (
            sys_clk => clk_125mhz,
            sys_rst_n => rst_n_sync,
            s_axi_aclk => clk_100mhz,
            s_axi_aresetn => rst_n_sync,
            -- Connect other ports...
        );
        
end architecture;
```

### Step 2: RGMII PHY Connections

```vhdl
-- RGMII interface constraints
-- File: tcp_offload_constraints.xdc

# RGMII TX signals
set_property PACKAGE_PIN AA14 [get_ports rgmii_txd[0]]
set_property PACKAGE_PIN AB14 [get_ports rgmii_txd[1]]
set_property PACKAGE_PIN AB13 [get_ports rgmii_txd[2]]
set_property PACKAGE_PIN AA13 [get_ports rgmii_txd[3]]
set_property PACKAGE_PIN AA12 [get_ports rgmii_tx_ctl]
set_property PACKAGE_PIN Y12  [get_ports rgmii_txc]

# RGMII RX signals
set_property PACKAGE_PIN Y14  [get_ports rgmii_rxd[0]]
set_property PACKAGE_PIN Y13  [get_ports rgmii_rxd[1]]
set_property PACKAGE_PIN W14  [get_ports rgmii_rxd[2]]
set_property PACKAGE_PIN W13  [get_ports rgmii_rxd[3]]
set_property PACKAGE_PIN V13  [get_ports rgmii_rx_ctl]
set_property PACKAGE_PIN V12  [get_ports rgmii_rxc]

# MDIO signals
set_property PACKAGE_PIN U12  [get_ports mdc]
set_property PACKAGE_PIN T12  [get_ports mdio]

# I/O standards
set_property IOSTANDARD LVCMOS25 [get_ports rgmii_*]
set_property IOSTANDARD LVCMOS25 [get_ports mdc]
set_property IOSTANDARD LVCMOS25 [get_ports mdio]

# RGMII timing constraints
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]
set_input_delay -clock rgmii_rxc -max 1.0 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -min -0.5 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]

create_generated_clock -name rgmii_txc -source [get_pins clk_wiz_inst/clk_out1] \
                       -divide_by 1 [get_ports rgmii_txc]
set_output_delay -clock rgmii_txc -max 1.0 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
set_output_delay -clock rgmii_txc -min -0.5 [get_ports {rgmii_txd[*] rgmii_tx_ctl}]
```

### Step 3: AXI4 Interconnect Integration

```tcl
# Vivado block design TCL script
# Create AXI interconnect for CPU access

# Create block design
create_bd_design "system"

# Add processing system (Zynq example)
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0

# Configure PS7 for Ethernet
set_property -dict [list \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_ENET0_ENET0_IO {MIO 16 .. 27} \
    CONFIG.PCW_ENET0_GRP_MDIO_ENABLE {1} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_M_AXI_GP0_DATA_WIDTH {32} \
] [get_bd_cells processing_system7_0]

# Add AXI interconnect
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list CONFIG.NUM_MI {2}] [get_bd_cells axi_interconnect_0]

# Add TCP Offload Engine
create_bd_cell -type module -reference tcp_offload_engine_top tcp_offload_0

# Connect clocks
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins tcp_offload_0/s_axi_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] \
               [get_bd_pins tcp_offload_0/sys_clk]

# Connect resets
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins tcp_offload_0/s_axi_aresetn]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET1_N] \
               [get_bd_pins tcp_offload_0/sys_rst_n]

# Connect AXI interfaces
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                    [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins tcp_offload_0/s_axi]

# Create external ports for RGMII
create_bd_port -dir O -from 3 -to 0 rgmii_txd
create_bd_port -dir O rgmii_tx_ctl
create_bd_port -dir O rgmii_txc
create_bd_port -dir I -from 3 -to 0 rgmii_rxd
create_bd_port -dir I rgmii_rx_ctl
create_bd_port -dir I rgmii_rxc
create_bd_port -dir O mdc
create_bd_port -dir IO mdio

# Connect RGMII ports
connect_bd_net [get_bd_pins tcp_offload_0/rgmii_txd] [get_bd_ports rgmii_txd]
connect_bd_net [get_bd_pins tcp_offload_0/rgmii_tx_ctl] [get_bd_ports rgmii_tx_ctl]
connect_bd_net [get_bd_pins tcp_offload_0/rgmii_txc] [get_bd_ports rgmii_txc]
connect_bd_net [get_bd_ports rgmii_rxd] [get_bd_pins tcp_offload_0/rgmii_rxd]
connect_bd_net [get_bd_ports rgmii_rx_ctl] [get_bd_pins tcp_offload_0/rgmii_rx_ctl]
connect_bd_net [get_bd_ports rgmii_rxc] [get_bd_pins tcp_offload_0/rgmii_rxc]
connect_bd_net [get_bd_pins tcp_offload_0/mdc] [get_bd_ports mdc]
connect_bd_net [get_bd_pins tcp_offload_0/mdio] [get_bd_ports mdio]

# Assign addresses
assign_bd_address [get_bd_addr_segs {tcp_offload_0/s_axi/reg0 }]
set_property range 4K [get_bd_addr_segs {processing_system7_0/Data/SEG_tcp_offload_0_reg0}]
set_property offset 0x43C00000 [get_bd_addr_segs {processing_system7_0/Data/SEG_tcp_offload_0_reg0}]

# Regenerate layout and save
regenerate_bd_layout
save_bd_design
```

### Step 4: AXI4-Stream DMA Integration

```tcl
# Add AXI DMA for high-speed data transfer
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 axi_dma_0

# Configure DMA
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_sg_length_width {26} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_burst_size {16} \
] [get_bd_cells axi_dma_0]

# Connect DMA to interconnect
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M01_AXI] \
                    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

# Connect DMA master interfaces to memory interconnect
# (Create additional interconnect for memory access)
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_SI {2}] [get_bd_cells axi_mem_intercon]

connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] \
                    [get_bd_intf_pins axi_mem_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
                    [get_bd_intf_pins axi_mem_intercon/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_mem_intercon/M00_AXI] \
                    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# Connect streaming interfaces
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
                    [get_bd_intf_pins tcp_offload_0/s_axis_rx]
connect_bd_intf_net [get_bd_intf_pins tcp_offload_0/m_axis_tx] \
                    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# Connect interrupts
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 xlconcat_0
set_property -dict [list CONFIG.NUM_PORTS {2}] [get_bd_cells xlconcat_0]

connect_bd_net [get_bd_pins axi_dma_0/mm2s_introut] [get_bd_pins xlconcat_0/In0]
connect_bd_net [get_bd_pins axi_dma_0/s2mm_introut] [get_bd_pins xlconcat_0/In1]
connect_bd_net [get_bd_pins xlconcat_0/dout] [get_bd_pins processing_system7_0/IRQ_F2P]
```

## 💻 Software Integration

### Step 1: Device Tree Configuration

```dts
// Device tree overlay for TCP Offload Engine
/dts-v1/;
/plugin/;

/ {
    compatible = "xlnx,zynq-7000";
    
    fragment@0 {
        target = <&amba>;
        __overlay__ {
            tcp_offload: tcp_offload@43c00000 {
                compatible = "xlnx,tcp-offload-1.0";
                reg = <0x43c00000 0x1000>;
                interrupt-parent = <&intc>;
                interrupts = <0 59 4>, <0 58 4>;
                interrupt-names = "tx_done", "rx_done";
                
                clock-names = "s_axi_aclk", "sys_clk";
                clocks = <&clkc 15>, <&clkc 16>;
                
                xlnx,num-connections = <2>;
                xlnx,buffer-size = <4096>;
                xlnx,max-frame-size = <1518>;
                
                status = "okay";
            };
            
            axi_dma: dma@40400000 {
                compatible = "xlnx,axi-dma-1.00.a";
                reg = <0x40400000 0x10000>;
                interrupt-parent = <&intc>;
                interrupts = <0 57 4>, <0 56 4>;
                interrupt-names = "mm2s", "s2mm";
                
                #dma-cells = <1>;
                xlnx,addrwidth = <0x20>;
                xlnx,sg-length-width = <0x1a>;
                
                status = "okay";
            };
        };
    };
};
```

### Step 2: Linux Kernel Driver

```c
// tcp_offload_driver.c
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_device.h>
#include <linux/interrupt.h>
#include <linux/dma-mapping.h>
#include <linux/uio_driver.h>

#define DRIVER_NAME "tcp_offload"
#define DEVICE_NAME "tcp_offload"

// Register offsets (from VHDL design)
#define REG_CONTROL         0x0000
#define REG_STATUS          0x0004
#define REG_MAC_ADDR_LOW    0x0008
#define REG_MAC_ADDR_HIGH   0x000C
#define REG_IP_ADDR         0x0010
#define REG_SUBNET_MASK     0x0014
#define REG_GATEWAY         0x0018
#define REG_TCP_PORT_0      0x001C
#define REG_TCP_PORT_1      0x0020

struct tcp_offload_dev {
    struct platform_device *pdev;
    void __iomem *regs;
    int irq_tx;
    int irq_rx;
    struct dma_chan *tx_chan;
    struct dma_chan *rx_chan;
    
    // Device state
    u32 control_reg;
    u8 mac_addr[6];
    u32 ip_addr;
    u32 subnet_mask;
    u32 gateway;
    u16 tcp_ports[2];
    
    // Statistics
    u64 tx_packets;
    u64 rx_packets;
    u64 tx_bytes;
    u64 rx_bytes;
    u32 errors;
};

// Register access functions
static inline void tcp_offload_write(struct tcp_offload_dev *dev, 
                                   u32 offset, u32 value)
{
    iowrite32(value, dev->regs + offset);
}

static inline u32 tcp_offload_read(struct tcp_offload_dev *dev, u32 offset)
{
    return ioread32(dev->regs + offset);
}

// Configuration functions
static int tcp_offload_configure_mac(struct tcp_offload_dev *dev, 
                                    const u8 *mac_addr)
{
    u32 mac_low, mac_high;
    
    memcpy(dev->mac_addr, mac_addr, 6);
    
    mac_low = (mac_addr[0] << 0) | (mac_addr[1] << 8) | 
              (mac_addr[2] << 16) | (mac_addr[3] << 24);
    mac_high = (mac_addr[4] << 0) | (mac_addr[5] << 8);
    
    tcp_offload_write(dev, REG_MAC_ADDR_LOW, mac_low);
    tcp_offload_write(dev, REG_MAC_ADDR_HIGH, mac_high);
    
    dev_info(&dev->pdev->dev, "MAC address configured: %pM\n", mac_addr);
    return 0;
}

static int tcp_offload_configure_ip(struct tcp_offload_dev *dev,
                                  u32 ip_addr, u32 subnet_mask, u32 gateway)
{
    dev->ip_addr = ip_addr;
    dev->subnet_mask = subnet_mask;
    dev->gateway = gateway;
    
    tcp_offload_write(dev, REG_IP_ADDR, ip_addr);
    tcp_offload_write(dev, REG_SUBNET_MASK, subnet_mask);
    tcp_offload_write(dev, REG_GATEWAY, gateway);
    
    dev_info(&dev->pdev->dev, "IP configuration: %pI4/%pI4 via %pI4\n",
             &ip_addr, &subnet_mask, &gateway);
    return 0;
}

static int tcp_offload_configure_ports(struct tcp_offload_dev *dev,
                                     u16 port0, u16 port1)
{
    dev->tcp_ports[0] = port0;
    dev->tcp_ports[1] = port1;
    
    tcp_offload_write(dev, REG_TCP_PORT_0, port0);
    tcp_offload_write(dev, REG_TCP_PORT_1, port1);
    
    dev_info(&dev->pdev->dev, "TCP ports configured: %u, %u\n", port0, port1);
    return 0;
}

// Control functions
static int tcp_offload_enable(struct tcp_offload_dev *dev)
{
    dev->control_reg |= 0x07; // Enable engine, DHCP, and TCP
    tcp_offload_write(dev, REG_CONTROL, dev->control_reg);
    
    dev_info(&dev->pdev->dev, "TCP offload engine enabled\n");
    return 0;
}

static int tcp_offload_disable(struct tcp_offload_dev *dev)
{
    dev->control_reg &= ~0x07; // Disable all
    tcp_offload_write(dev, REG_CONTROL, dev->control_reg);
    
    dev_info(&dev->pdev->dev, "TCP offload engine disabled\n");
    return 0;
}

// Interrupt handlers
static irqreturn_t tcp_offload_tx_irq(int irq, void *dev_id)
{
    struct tcp_offload_dev *dev = dev_id;
    
    // Handle TX completion
    dev->tx_packets++;
    
    return IRQ_HANDLED;
}

static irqreturn_t tcp_offload_rx_irq(int irq, void *dev_id)
{
    struct tcp_offload_dev *dev = dev_id;
    
    // Handle RX completion
    dev->rx_packets++;
    
    return IRQ_HANDLED;
}

// Sysfs attributes
static ssize_t status_show(struct device *dev, struct device_attribute *attr,
                          char *buf)
{
    struct tcp_offload_dev *tcp_dev = dev_get_drvdata(dev);
    u32 status = tcp_offload_read(tcp_dev, REG_STATUS);
    
    return sprintf(buf, "0x%08x\n", status);
}

static ssize_t mac_addr_show(struct device *dev, struct device_attribute *attr,
                            char *buf)
{
    struct tcp_offload_dev *tcp_dev = dev_get_drvdata(dev);
    
    return sprintf(buf, "%pM\n", tcp_dev->mac_addr);
}

static ssize_t mac_addr_store(struct device *dev, struct device_attribute *attr,
                             const char *buf, size_t count)
{
    struct tcp_offload_dev *tcp_dev = dev_get_drvdata(dev);
    u8 mac_addr[6];
    
    if (sscanf(buf, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
               &mac_addr[0], &mac_addr[1], &mac_addr[2],
               &mac_addr[3], &mac_addr[4], &mac_addr[5]) != 6) {
        return -EINVAL;
    }
    
    tcp_offload_configure_mac(tcp_dev, mac_addr);
    return count;
}

static ssize_t stats_show(struct device *dev, struct device_attribute *attr,
                         char *buf)
{
    struct tcp_offload_dev *tcp_dev = dev_get_drvdata(dev);
    
    return sprintf(buf, "TX packets: %llu\n"
                       "RX packets: %llu\n"
                       "TX bytes: %llu\n"
                       "RX bytes: %llu\n"
                       "Errors: %u\n",
                   tcp_dev->tx_packets, tcp_dev->rx_packets,
                   tcp_dev->tx_bytes, tcp_dev->rx_bytes,
                   tcp_dev->errors);
}

static DEVICE_ATTR_RO(status);
static DEVICE_ATTR_RW(mac_addr);
static DEVICE_ATTR_RO(stats);

static struct attribute *tcp_offload_attrs[] = {
    &dev_attr_status.attr,
    &dev_attr_mac_addr.attr,
    &dev_attr_stats.attr,
    NULL,
};

static const struct attribute_group tcp_offload_attr_group = {
    .attrs = tcp_offload_attrs,
};

// Device operations
static int tcp_offload_probe(struct platform_device *pdev)
{
    struct tcp_offload_dev *dev;
    struct resource *res;
    int ret;
    
    dev_info(&pdev->dev, "Probing TCP offload engine\n");
    
    // Allocate device structure
    dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
    if (!dev)
        return -ENOMEM;
    
    dev->pdev = pdev;
    platform_set_drvdata(pdev, dev);
    
    // Map registers
    res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    dev->regs = devm_ioremap_resource(&pdev->dev, res);
    if (IS_ERR(dev->regs))
        return PTR_ERR(dev->regs);
    
    // Get interrupts
    dev->irq_tx = platform_get_irq_byname(pdev, "tx_done");
    if (dev->irq_tx < 0) {
        dev_err(&pdev->dev, "Failed to get TX interrupt\n");
        return dev->irq_tx;
    }
    
    dev->irq_rx = platform_get_irq_byname(pdev, "rx_done");
    if (dev->irq_rx < 0) {
        dev_err(&pdev->dev, "Failed to get RX interrupt\n");
        return dev->irq_rx;
    }
    
    // Request interrupts
    ret = devm_request_irq(&pdev->dev, dev->irq_tx, tcp_offload_tx_irq,
                          0, "tcp_offload_tx", dev);
    if (ret) {
        dev_err(&pdev->dev, "Failed to request TX interrupt\n");
        return ret;
    }
    
    ret = devm_request_irq(&pdev->dev, dev->irq_rx, tcp_offload_rx_irq,
                          0, "tcp_offload_rx", dev);
    if (ret) {
        dev_err(&pdev->dev, "Failed to request RX interrupt\n");
        return ret;
    }
    
    // Create sysfs attributes
    ret = sysfs_create_group(&pdev->dev.kobj, &tcp_offload_attr_group);
    if (ret) {
        dev_err(&pdev->dev, "Failed to create sysfs attributes\n");
        return ret;
    }
    
    // Initialize device with default configuration
    // Default MAC: 00:11:22:33:44:55
    u8 default_mac[] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55};
    tcp_offload_configure_mac(dev, default_mac);
    
    // Default IP: 192.168.1.100/24 via 192.168.1.1
    tcp_offload_configure_ip(dev, 0xC0A80164, 0xFFFFFF00, 0xC0A80101);
    
    // Default ports: 80, 22
    tcp_offload_configure_ports(dev, 80, 22);
    
    dev_info(&pdev->dev, "TCP offload engine probed successfully\n");
    return 0;
}

static int tcp_offload_remove(struct platform_device *pdev)
{
    struct tcp_offload_dev *dev = platform_get_drvdata(pdev);
    
    // Disable engine
    tcp_offload_disable(dev);
    
    // Remove sysfs attributes
    sysfs_remove_group(&pdev->dev.kobj, &tcp_offload_attr_group);
    
    dev_info(&pdev->dev, "TCP offload engine removed\n");
    return 0;
}

// Device tree matching
static const struct of_device_id tcp_offload_of_match[] = {
    { .compatible = "xlnx,tcp-offload-1.0", },
    { /* end of list */ },
};
MODULE_DEVICE_TABLE(of, tcp_offload_of_match);

static struct platform_driver tcp_offload_driver = {
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = tcp_offload_of_match,
    },
    .probe = tcp_offload_probe,
    .remove = tcp_offload_remove,
};

module_platform_driver(tcp_offload_driver);

MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("TCP Offload Engine Driver");
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("platform:" DRIVER_NAME);
```

### Step 3: User Space Library

```c
// libtcp_offload.h
#ifndef LIBTCP_OFFLOAD_H
#define LIBTCP_OFFLOAD_H

#include <stdint.h>
#include <stdbool.h>

// Connection handle
typedef struct tcp_offload_connection tcp_offload_connection_t;

// Configuration structure
typedef struct {
    uint8_t mac_addr[6];
    uint32_t ip_addr;
    uint32_t subnet_mask;
    uint32_t gateway;
    bool enable_dhcp;
} tcp_offload_config_t;

// Statistics structure
typedef struct {
    uint64_t tx_packets;
    uint64_t rx_packets;
    uint64_t tx_bytes;
    uint64_t rx_bytes;
    uint32_t errors;
    uint32_t connections_active;
} tcp_offload_stats_t;

// API functions
int tcp_offload_init(void);
void tcp_offload_cleanup(void);

int tcp_offload_configure(const tcp_offload_config_t *config);
int tcp_offload_enable(void);
int tcp_offload_disable(void);

tcp_offload_connection_t *tcp_offload_listen(uint16_t port);
tcp_offload_connection_t *tcp_offload_connect(uint32_t ip, uint16_t port);
void tcp_offload_close(tcp_offload_connection_t *conn);

int tcp_offload_send(tcp_offload_connection_t *conn, 
                    const void *data, size_t len);
int tcp_offload_receive(tcp_offload_connection_t *conn,
                       void *data, size_t len);

int tcp_offload_get_stats(tcp_offload_stats_t *stats);
bool tcp_offload_is_connected(tcp_offload_connection_t *conn);

#endif // LIBTCP_OFFLOAD_H
```

```c
// libtcp_offload.c
#include "libtcp_offload.h"
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define DEVICE_PATH "/dev/tcp_offload"
#define SYSFS_PATH "/sys/class/tcp_offload/tcp_offload"
#define REGISTER_MAP_SIZE 0x1000

// Internal structures
struct tcp_offload_connection {
    int id;
    uint16_t local_port;
    uint32_t remote_ip;
    uint16_t remote_port;
    bool active;
};

static struct {
    int fd;
    void *reg_map;
    bool initialized;
    tcp_offload_connection_t connections[2];
} tcp_offload_ctx = {0};

// Register access macros
#define REG_READ(offset) \
    (*((volatile uint32_t *)((char *)tcp_offload_ctx.reg_map + (offset))))
#define REG_WRITE(offset, value) \
    (*((volatile uint32_t *)((char *)tcp_offload_ctx.reg_map + (offset))) = (value))

// API implementation
int tcp_offload_init(void)
{
    if (tcp_offload_ctx.initialized) {
        return 0; // Already initialized
    }
    
    // Open device
    tcp_offload_ctx.fd = open(DEVICE_PATH, O_RDWR);
    if (tcp_offload_ctx.fd < 0) {
        fprintf(stderr, "Failed to open device: %s\n", strerror(errno));
        return -1;
    }
    
    // Map registers
    tcp_offload_ctx.reg_map = mmap(NULL, REGISTER_MAP_SIZE,
                                  PROT_READ | PROT_WRITE, MAP_SHARED,
                                  tcp_offload_ctx.fd, 0);
    if (tcp_offload_ctx.reg_map == MAP_FAILED) {
        fprintf(stderr, "Failed to map registers: %s\n", strerror(errno));
        close(tcp_offload_ctx.fd);
        return -1;
    }
    
    // Initialize connection structures
    memset(tcp_offload_ctx.connections, 0, sizeof(tcp_offload_ctx.connections));
    
    tcp_offload_ctx.initialized = true;
    printf("TCP offload engine initialized\n");
    return 0;
}

void tcp_offload_cleanup(void)
{
    if (!tcp_offload_ctx.initialized) {
        return;
    }
    
    // Disable engine
    tcp_offload_disable();
    
    // Close all connections
    for (int i = 0; i < 2; i++) {
        if (tcp_offload_ctx.connections[i].active) {
            tcp_offload_close(&tcp_offload_ctx.connections[i]);
        }
    }
    
    // Unmap registers
    if (tcp_offload_ctx.reg_map != MAP_FAILED) {
        munmap(tcp_offload_ctx.reg_map, REGISTER_MAP_SIZE);
    }
    
    // Close device
    if (tcp_offload_ctx.fd >= 0) {
        close(tcp_offload_ctx.fd);
    }
    
    tcp_offload_ctx.initialized = false;
    printf("TCP offload engine cleaned up\n");
}

int tcp_offload_configure(const tcp_offload_config_t *config)
{
    if (!tcp_offload_ctx.initialized) {
        return -1;
    }
    
    // Configure MAC address
    uint32_t mac_low = (config->mac_addr[0] << 0) | (config->mac_addr[1] << 8) |
                       (config->mac_addr[2] << 16) | (config->mac_addr[3] << 24);
    uint32_t mac_high = (config->mac_addr[4] << 0) | (config->mac_addr[5] << 8);
    
    REG_WRITE(0x0008, mac_low);
    REG_WRITE(0x000C, mac_high);
    
    // Configure IP settings
    REG_WRITE(0x0010, config->ip_addr);
    REG_WRITE(0x0014, config->subnet_mask);
    REG_WRITE(0x0018, config->gateway);
    
    printf("TCP offload configured: IP=%08x, Gateway=%08x\n",
           config->ip_addr, config->gateway);
    return 0;
}

int tcp_offload_enable(void)
{
    if (!tcp_offload_ctx.initialized) {
        return -1;
    }
    
    // Enable engine, DHCP, and TCP
    REG_WRITE(0x0000, 0x07);
    
    printf("TCP offload engine enabled\n");
    return 0;
}

int tcp_offload_disable(void)
{
    if (!tcp_offload_ctx.initialized) {
        return -1;
    }
    
    // Disable all functionality
    REG_WRITE(0x0000, 0x00);
    
    printf("TCP offload engine disabled\n");
    return 0;
}

tcp_offload_connection_t *tcp_offload_listen(uint16_t port)
{
    if (!tcp_offload_ctx.initialized) {
        return NULL;
    }
    
    // Find available connection slot
    for (int i = 0; i < 2; i++) {
        if (!tcp_offload_ctx.connections[i].active) {
            tcp_offload_ctx.connections[i].id = i;
            tcp_offload_ctx.connections[i].local_port = port;
            tcp_offload_ctx.connections[i].active = true;
            
            // Configure port in hardware
            REG_WRITE(0x001C + (i * 4), port);
            
            printf("Listening on port %u (connection %d)\n", port, i);
            return &tcp_offload_ctx.connections[i];
        }
    }
    
    printf("No available connection slots\n");
    return NULL;
}

tcp_offload_connection_t *tcp_offload_connect(uint32_t ip, uint16_t port)
{
    if (!tcp_offload_ctx.initialized) {
        return NULL;
    }
    
    // Find available connection slot
    for (int i = 0; i < 2; i++) {
        if (!tcp_offload_ctx.connections[i].active) {
            tcp_offload_ctx.connections[i].id = i;
            tcp_offload_ctx.connections[i].remote_ip = ip;
            tcp_offload_ctx.connections[i].remote_port = port;
            tcp_offload_ctx.connections[i].active = true;
            
            // Configure connection in hardware
            // (Implementation depends on specific hardware interface)
            
            printf("Connecting to %08x:%u (connection %d)\n", ip, port, i);
            return &tcp_offload_ctx.connections[i];
        }
    }
    
    printf("No available connection slots\n");
    return NULL;
}

void tcp_offload_close(tcp_offload_connection_t *conn)
{
    if (!conn || !conn->active) {
        return;
    }
    
    printf("Closing connection %d\n", conn->id);
    
    // Reset connection in hardware
    // (Implementation depends on specific hardware interface)
    
    conn->active = false;
}

int tcp_offload_send(tcp_offload_connection_t *conn,
                    const void *data, size_t len)
{
    if (!conn || !conn->active) {
        return -1;
    }
    
    // Send data through DMA interface
    // (Implementation depends on DMA driver interface)
    
    printf("Sending %zu bytes on connection %d\n", len, conn->id);
    return len;
}

int tcp_offload_receive(tcp_offload_connection_t *conn,
                       void *data, size_t len)
{
    if (!conn || !conn->active) {
        return -1;
    }
    
    // Receive data through DMA interface
    // (Implementation depends on DMA driver interface)
    
    printf("Receiving up to %zu bytes on connection %d\n", len, conn->id);
    return 0; // Return actual bytes received
}

int tcp_offload_get_stats(tcp_offload_stats_t *stats)
{
    if (!tcp_offload_ctx.initialized || !stats) {
        return -1;
    }
    
    // Read statistics from sysfs
    FILE *f = fopen(SYSFS_PATH "/stats", "r");
    if (!f) {
        return -1;
    }
    
    fscanf(f, "TX packets: %llu\n", &stats->tx_packets);
    fscanf(f, "RX packets: %llu\n", &stats->rx_packets);
    fscanf(f, "TX bytes: %llu\n", &stats->tx_bytes);
    fscanf(f, "RX bytes: %llu\n", &stats->rx_bytes);
    fscanf(f, "Errors: %u\n", &stats->errors);
    
    fclose(f);
    
    // Count active connections
    stats->connections_active = 0;
    for (int i = 0; i < 2; i++) {
        if (tcp_offload_ctx.connections[i].active) {
            stats->connections_active++;
        }
    }
    
    return 0;
}

bool tcp_offload_is_connected(tcp_offload_connection_t *conn)
{
    if (!conn) {
        return false;
    }
    
    // Check connection status in hardware
    uint32_t status = REG_READ(0x0004);
    uint32_t conn_mask = 1 << (5 + conn->id); // Bits 5-6 for connections 0-1
    
    return (status & conn_mask) != 0;
}
```

## 🧪 Testing and Validation

### Step 1: Hardware-in-the-Loop Testing

```c
// test_tcp_offload.c
#include "libtcp_offload.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int test_basic_configuration(void)
{
    printf("Testing basic configuration...\n");
    
    tcp_offload_config_t config = {
        .mac_addr = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55},
        .ip_addr = inet_addr("192.168.1.100"),
        .subnet_mask = inet_addr("255.255.255.0"),
        .gateway = inet_addr("192.168.1.1"),
        .enable_dhcp = false
    };
    
    if (tcp_offload_configure(&config) < 0) {
        printf("Configuration failed\n");
        return -1;
    }
    
    if (tcp_offload_enable() < 0) {
        printf("Enable failed\n");
        return -1;
    }
    
    printf("Basic configuration test passed\n");
    return 0;
}

int test_tcp_server(void)
{
    printf("Testing TCP server...\n");
    
    tcp_offload_connection_t *server = tcp_offload_listen(8080);
    if (!server) {
        printf("Failed to create server\n");
        return -1;
    }
    
    printf("Server listening on port 8080\n");
    
    // Wait for connection (simplified)
    for (int i = 0; i < 100; i++) {
        if (tcp_offload_is_connected(server)) {
            printf("Client connected!\n");
            
            // Echo server example
            char buffer[1024];
            int len = tcp_offload_receive(server, buffer, sizeof(buffer));
            if (len > 0) {
                printf("Received %d bytes: %.*s\n", len, len, buffer);
                tcp_offload_send(server, buffer, len);
                printf("Echoed back %d bytes\n", len);
            }
            break;
        }
        usleep(100000); // 100ms
    }
    
    tcp_offload_close(server);
    printf("TCP server test completed\n");
    return 0;
}

int test_performance(void)
{
    printf("Testing performance...\n");
    
    tcp_offload_stats_t stats_before, stats_after;
    tcp_offload_get_stats(&stats_before);
    
    // Perform some operations
    tcp_offload_connection_t *server = tcp_offload_listen(9090);
    
    // Simulate traffic (would need external client)
    sleep(5);
    
    tcp_offload_get_stats(&stats_after);
    
    printf("Performance results:\n");
    printf("  TX packets: %llu -> %llu (delta: %llu)\n",
           stats_before.tx_packets, stats_after.tx_packets,
           stats_after.tx_packets - stats_before.tx_packets);
    printf("  RX packets: %llu -> %llu (delta: %llu)\n",
           stats_before.rx_packets, stats_after.rx_packets,
           stats_after.rx_packets - stats_before.rx_packets);
    
    tcp_offload_close(server);
    return 0;
}

int main(int argc, char *argv[])
{
    printf("TCP Offload Engine Test Suite\n");
    printf("=============================\n");
    
    if (tcp_offload_init() < 0) {
        printf("Failed to initialize TCP offload engine\n");
        return 1;
    }
    
    int tests_passed = 0;
    int total_tests = 3;
    
    if (test_basic_configuration() == 0) tests_passed++;
    if (test_tcp_server() == 0) tests_passed++;
    if (test_performance() == 0) tests_passed++;
    
    printf("\nTest Results: %d/%d tests passed\n", tests_passed, total_tests);
    
    tcp_offload_cleanup();
    
    return (tests_passed == total_tests) ? 0 : 1;
}
```

### Step 2: Network Testing

```bash
#!/bin/bash
# network_test.sh

echo "TCP Offload Engine Network Test"
echo "================================"

# Configuration
FPGA_IP="192.168.1.100"
TEST_PORT=8080
TEST_DATA="Hello from TCP offload engine!"

# Test 1: Ping test
echo "Test 1: Ping connectivity"
if ping -c 3 $FPGA_IP > /dev/null 2>&1; then
    echo "✓ Ping test passed"
else
    echo "✗ Ping test failed"
    exit 1
fi

# Test 2: TCP connection test
echo "Test 2: TCP connection"
if timeout 5 bash -c "echo '$TEST_DATA' | nc $FPGA_IP $TEST_PORT"; then
    echo "✓ TCP connection test passed"
else
    echo "✗ TCP connection test failed"
fi

# Test 3: Performance test
echo "Test 3: Performance test"
echo "Sending 1MB of data..."
dd if=/dev/zero bs=1024 count=1024 2>/dev/null | \
    timeout 10 nc $FPGA_IP $TEST_PORT > /dev/null

if [ $? -eq 0 ]; then
    echo "✓ Performance test passed"
else
    echo "✗ Performance test failed"
fi

# Test 4: Concurrent connections
echo "Test 4: Concurrent connections"
nc $FPGA_IP 8080 < /dev/null &
PID1=$!
nc $FPGA_IP 8081 < /dev/null &
PID2=$!

sleep 2
kill $PID1 $PID2 2>/dev/null

echo "✓ Concurrent connections test completed"

echo "Network testing completed"
```

## 🔍 Debugging and Troubleshooting

### Common Integration Issues

#### 1. Clock Domain Crossing Issues
```vhdl
-- Add proper synchronizers
signal sync_reg : std_logic_vector(1 downto 0) := "00";

process(dst_clk, rst_n)
begin
    if rst_n = '0' then
        sync_reg <= "00";
        output_sync <= '0';
    elsif rising_edge(dst_clk) then
        sync_reg <= sync_reg(0) & input_async;
        output_sync <= sync_reg(1);
    end if;
end process;
```

#### 2. AXI Protocol Violations
```c
// Check AXI transaction completion
static int axi_write_safe(void __iomem *base, u32 offset, u32 value)
{
    unsigned long timeout = jiffies + HZ; // 1 second timeout
    
    iowrite32(value, base + offset);
    
    // Wait for transaction completion (if applicable)
    while (time_before(jiffies, timeout)) {
        if (/* check completion status */) {
            return 0;
        }
        cpu_relax();
    }
    
    return -ETIMEDOUT;
}
```

#### 3. RGMII Timing Issues
```tcl
# Relax timing constraints if needed
set_input_delay -clock rgmii_rxc -max 2.0 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]
set_input_delay -clock rgmii_rxc -min -1.0 [get_ports {rgmii_rxd[*] rgmii_rx_ctl}]

# Add timing exceptions for configuration paths
set_false_path -from [get_cells config_reg*] -to [get_cells rgmii_*]
```

### Performance Optimization

#### 1. Buffer Sizing
```vhdl
-- Optimize buffer sizes based on application
generic (
    TX_BUFFER_SIZE : natural := 8192;  -- Increase for high throughput
    RX_BUFFER_SIZE : natural := 8192;
    BUFFER_ALMOST_FULL : natural := 7680  -- 93.75% threshold
);
```

#### 2. Interrupt Coalescing
```c
// Reduce interrupt overhead
#define MAX_PACKETS_PER_IRQ 32
#define MAX_USECS_PER_IRQ   50

static void configure_interrupt_coalescing(struct tcp_offload_dev *dev)
{
    // Configure hardware interrupt coalescing
    tcp_offload_write(dev, REG_IRQ_COALESCE_PACKETS, MAX_PACKETS_PER_IRQ);
    tcp_offload_write(dev, REG_IRQ_COALESCE_USECS, MAX_USECS_PER_IRQ);
}
```

This integration guide provides comprehensive instructions for successfully implementing the TCP Offload Engine in your FPGA system, from hardware connections to software drivers and testing procedures.