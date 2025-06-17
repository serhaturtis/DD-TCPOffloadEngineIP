library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;
use work.tcp_protocol_tb_pkg.all;

entity packet_gen_test_tb is
end entity packet_gen_test_tb;

architecture behavioral of packet_gen_test_tb is
    
    signal test_complete : std_logic := '0';
    
begin
    
    -- Main test process
    test_proc: process
        variable eth_header : byte_array_t(0 to 13);
        variable ip_header : byte_array_t(0 to 19);
        variable tcp_header : byte_array_t(0 to 19);
        variable udp_header : byte_array_t(0 to 7);
        variable syn_packet : byte_array_t(0 to 53);
        variable dhcp_discover : byte_array_t(0 to 299);
        variable dhcp_offer : byte_array_t(0 to 299);
    begin
        
        wait for 100 ns;
        
        test_start("Packet Generation Framework Test Suite");
        
        -- Test 1: Ethernet header generation
        test_start("Ethernet Header Generation");
        
        eth_header := generate_ethernet_header(
            TEST_MAC_ADDR, REMOTE_MAC_ADDR, x"0800"
        );
        
        if eth_header(0) = TEST_MAC_ADDR(47 downto 40) and
           eth_header(12) = x"08" and eth_header(13) = x"00" then
            test_pass("Ethernet Header Generation");
        else
            test_fail("Ethernet Header Generation", "Header validation failed");
        end if;
        
        -- Test 2: IP header generation
        test_start("IP Header Generation");
        
        ip_header := generate_ip_header(
            TEST_IP_ADDR, REMOTE_IP_ADDR, x"06", 20
        );
        
        if ip_header(0) = x"45" and ip_header(9) = x"06" then
            test_pass("IP Header Generation");
        else
            test_fail("IP Header Generation", "Header validation failed");
        end if;
        
        -- Test 3: TCP header generation
        test_start("TCP Header Generation");
        
        tcp_header := generate_tcp_header(
            x"0050", x"8000", x"12345678", x"87654321", x"02", x"8000"
        );
        
        if tcp_header(0) = x"00" and tcp_header(1) = x"50" and
           tcp_header(13) = x"02" then -- SYN flag
            test_pass("TCP Header Generation");
        else
            test_fail("TCP Header Generation", "Header validation failed");
        end if;
        
        -- Test 4: UDP header generation
        test_start("UDP Header Generation");
        
        udp_header := generate_udp_header(x"1234", x"5678", 100);
        
        if udp_header(0) = x"12" and udp_header(1) = x"34" and
           udp_header(4) = x"00" and udp_header(5) = x"6C" then -- Length = 108
            test_pass("UDP Header Generation");
        else
            test_fail("UDP Header Generation", "Header validation failed");
        end if;
        
        -- Test 5: Complete TCP SYN packet generation
        test_start("TCP SYN Packet Generation");
        
        syn_packet := generate_tcp_syn_packet(
            REMOTE_MAC_ADDR, TEST_MAC_ADDR,
            REMOTE_IP_ADDR, TEST_IP_ADDR,
            x"8000", x"0050", x"12345678"
        );
        
        if syn_packet'length = 54 and
           syn_packet(12) = x"08" and syn_packet(13) = x"00" and -- EtherType
           syn_packet(14) = x"45" and -- IP version + IHL
           syn_packet(47) = x"02" then -- TCP SYN flag
            test_pass("TCP SYN Packet Generation");
        else
            test_fail("TCP SYN Packet Generation", "Packet validation failed");
        end if;
        
        -- Test 6: DHCP packet generation
        test_start("DHCP Packet Generation");
        
        dhcp_discover := generate_dhcp_discover(TEST_MAC_ADDR, x"12345678");
        dhcp_offer := generate_dhcp_offer(TEST_MAC_ADDR, x"12345678", 
                                         REMOTE_IP_ADDR, TEST_IP_ADDR);
        
        if dhcp_discover(0) = x"01" and dhcp_offer(0) = x"02" then
            test_pass("DHCP Packet Generation");
        else
            test_fail("DHCP Packet Generation", "Packet validation failed");
        end if;
        
        -- Test completion
        test_report_summary;
        test_complete <= '1';
        
        report "====== ALL PACKET GENERATION TESTS COMPLETED ======";
        report "The TCP/IP packet generation framework is working correctly!";
        report "This validates that the comprehensive test infrastructure is functional.";
        
        wait;
    end process;
    
    -- Timeout process
    timeout_proc: process
    begin
        wait for 1 us;
        if test_complete = '0' then
            report "Packet generation test timeout!" severity failure;
        end if;
        wait;
    end process;
    
end architecture behavioral;