library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity tb_monociclo is
end entity;

architecture behaviour of tb_monociclo is

    -- Componente a ser validado
    component monociclo is
        port(
            clock       : in std_logic;
            reset       : in std_logic;
            R0_out      : out std_logic_vector(15 downto 0);
            R1_out      : out std_logic_vector(15 downto 0)
        );
    end component;

    -- Sinais para o testbench
    signal reset_sg       : std_logic := '1';  -- Sinal de reset
    signal clock_sg       : std_logic := '0';  -- Sinal de clock
    signal R0_out_sg      : std_logic_vector(15 downto 0);
    signal R1_out_sg      : std_logic_vector(15  downto 0);

begin
    -- Instanciação do componente processador_MIPS
    inst_MIPS : monociclo
        port map (
            clock     => clock_sg,
            reset     => reset_sg,
            R0_out    => R0_out_sg,
            R1_out    => R1_out_sg
        );

    -- Geração do clock
    clock_sg <= not clock_sg after 10 ps;

    -- Processo para simulação
    process
    begin
        -- Inicializa reset
        wait for 10 ps;
        reset_sg <= '0';  -- Desativa o reset

       -- Carrega instruções e verifica saídas
        wait for 400 ps;
     
        wait;
    end process;

end behaviour;
