library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tcp_offload_pkg.all;

entity packet_buffer is
    generic (
        BUFFER_DEPTH : natural := 512; -- 4KB buffer (512 x 64-bit words)
        ADDR_WIDTH : natural := 9
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        
        -- Write Interface
        wr_data : in std_logic_vector(63 downto 0);
        wr_keep : in std_logic_vector(7 downto 0);
        wr_last : in std_logic;
        wr_valid : in std_logic;
        wr_ready : out std_logic;
        
        -- Read Interface
        rd_data : out std_logic_vector(63 downto 0);
        rd_keep : out std_logic_vector(7 downto 0);
        rd_last : out std_logic;
        rd_valid : out std_logic;
        rd_ready : in std_logic;
        
        -- Control Interface
        buffer_reset : in std_logic;
        buffer_full : out std_logic;
        buffer_empty : out std_logic;
        buffer_count : out std_logic_vector(ADDR_WIDTH downto 0)
    );
end entity packet_buffer;

architecture rtl of packet_buffer is
    
    type ram_type is array (0 to BUFFER_DEPTH-1) of std_logic_vector(63 downto 0);
    type keep_ram_type is array (0 to BUFFER_DEPTH-1) of std_logic_vector(7 downto 0);
    type last_ram_type is array (0 to BUFFER_DEPTH-1) of std_logic;
    
    signal data_ram : ram_type := (others => (others => '0'));
    signal keep_ram : keep_ram_type := (others => (others => '0'));
    signal last_ram : last_ram_type := (others => '0');
    
    signal wr_ptr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal rd_ptr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal buffer_count_int : unsigned(ADDR_WIDTH downto 0) := (others => '0');
    
    signal full_int : std_logic := '0';
    signal empty_int : std_logic := '1';
    
    signal rd_data_reg : std_logic_vector(63 downto 0) := (others => '0');
    signal rd_keep_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal rd_last_reg : std_logic := '0';
    signal rd_valid_reg : std_logic := '0';
    
begin
    
    -- Buffer status
    full_int <= '1' when buffer_count_int = BUFFER_DEPTH else '0';
    empty_int <= '1' when buffer_count_int = 0 else '0';
    
    buffer_full <= full_int;
    buffer_empty <= empty_int;
    buffer_count <= std_logic_vector(buffer_count_int);
    
    wr_ready <= not full_int;
    
    -- Write process
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            wr_ptr <= (others => '0');
        elsif rising_edge(clk) then
            if buffer_reset = '1' then
                wr_ptr <= (others => '0');
            elsif wr_valid = '1' and full_int = '0' then
                data_ram(to_integer(wr_ptr)) <= wr_data;
                keep_ram(to_integer(wr_ptr)) <= wr_keep;
                last_ram(to_integer(wr_ptr)) <= wr_last;
                wr_ptr <= wr_ptr + 1;
            end if;
        end if;
    end process;
    
    -- Read process
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            rd_ptr <= (others => '0');
            rd_data_reg <= (others => '0');
            rd_keep_reg <= (others => '0');
            rd_last_reg <= '0';
            rd_valid_reg <= '0';
        elsif rising_edge(clk) then
            if buffer_reset = '1' then
                rd_ptr <= (others => '0');
                rd_valid_reg <= '0';
            elsif rd_ready = '1' then
                if empty_int = '0' then
                    rd_data_reg <= data_ram(to_integer(rd_ptr));
                    rd_keep_reg <= keep_ram(to_integer(rd_ptr));
                    rd_last_reg <= last_ram(to_integer(rd_ptr));
                    rd_valid_reg <= '1';
                    rd_ptr <= rd_ptr + 1;
                else
                    rd_valid_reg <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- Buffer count
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            buffer_count_int <= (others => '0');
        elsif rising_edge(clk) then
            if buffer_reset = '1' then
                buffer_count_int <= (others => '0');
            else
                if (wr_valid = '1' and full_int = '0') and (rd_ready = '0' or rd_valid_reg = '0') then
                    buffer_count_int <= buffer_count_int + 1;
                elsif (wr_valid = '0' or full_int = '1') and (rd_ready = '1' and rd_valid_reg = '1') then
                    buffer_count_int <= buffer_count_int - 1;
                end if;
            end if;
        end if;
    end process;
    
    -- Output assignments
    rd_data <= rd_data_reg;
    rd_keep <= rd_keep_reg;
    rd_last <= rd_last_reg;
    rd_valid <= rd_valid_reg;
    
end architecture rtl;