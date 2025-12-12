library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity monociclo is
    port (
        clock   : in  std_logic;
        reset   : in  std_logic;
        R0_out  : out std_logic_vector(15 downto 0);
        R1_out  : out std_logic_vector(15 downto 0)
    );
end monociclo;

architecture behavior of monociclo is

    -- Definição dos atributos de síntese para o Genus (Cadence)
    attribute syn_ramstyle : string;
    attribute syn_romstyle : string;

    -- PC
    signal pc_reg : std_logic_vector(7 downto 0);  

    -- TIPOS DE MEMÓRIA (Reduzidos para 32 posições para facilitar a síntese)
    type data_mem_array  is array (0 to 31) of std_logic_vector(15 downto 0);
    type instr_mem_array is array (0 to 31) of std_logic_vector(15 downto 0);
    type reg_file_array  is array (0 to 15) of std_logic_vector(15 downto 0);

    -- MEMÓRIA DE INSTRUÇÕES
    signal instr_mem : instr_mem_array := (
        0  => "1010000100000010", -- LDI  R1, 2
        1  => "1010001000000101", -- LDI  R2, 5
        2  => "0001001100010010", -- ADD  R3 = R1+R2
        3  => "1001010000110011", -- ADDI R4 = R3+3
        4  => "0111010000010000", -- SW   [16] = R4
        5  => "0000010100010000", -- LW   R5 <- [16]
        6  => "0101001001000101", -- BEQ  R4,R5,+2
        7  => "1010011000000000", -- LDI  R6, 0
        8  => "1000011000010100", -- MUI  R6 = R1*4
        9  => "0011011100110001", -- MUL  R7 = R3*R1
        10 => "0010100001110001", -- SUB  R8 = R7-R1
        11 => "0110001001111000", -- BNE  R7,R8,+2
        12 => "1010100100000000", -- LDI  R9, 0
        13 => "1011100101000001", -- SUI  R9 = R4-1
        14 => "0001101001101001", -- ADD  R10 = R6+R9
        15 => "0100000000000000", -- JMP  0
        others => (others => '1')
    );

    -- Aplica o atributo para forçar implementação como Lógica/Registradores
    attribute syn_romstyle of instr_mem : signal is "logic";

    -- MEMÓRIA DE DADOS (RAM)
    signal data_mem : data_mem_array := (others => (others => '0'));
    
    -- Aplica atributo para forçar Flip-Flops (evita Black Box)
    attribute syn_ramstyle of data_mem : signal is "registers";

    -- BANCO DE REGISTRADORES
    signal reg_file : reg_file_array := (others => (others => '0'));
    
    -- Aplica atributo para forçar Flip-Flops
    attribute syn_ramstyle of reg_file : signal is "registers";

    -- SINAIS DE DECODIFICAÇÃO E CONTROLE
    signal opcode         : std_logic_vector(3 downto 0);
    signal reg_dest       : std_logic_vector(3 downto 0);
    signal reg_rs         : std_logic_vector(3 downto 0);
    signal reg_rt_or_imm4 : std_logic_vector(3 downto 0);
    signal imm8           : std_logic_vector(7 downto 0);
    signal branch_offset  : std_logic_vector(3 downto 0);

    signal branch_taken   : std_logic;
    signal mul_rs_rt      : std_logic_vector(31 downto 0);
    signal mul_rs_imm4    : std_logic_vector(31 downto 0);
    signal rs_eq_rt       : std_logic;
    
    signal rs_value       : std_logic_vector(15 downto 0);
    signal rt_value       : std_logic_vector(15 downto 0);

    -- Sinal auxiliar para limitar o índice de leitura (evita erro de simulação/síntese com mem reduzida)
    signal pc_idx : integer;

begin

    -- Limita o índice do PC para não estourar o array de 32 posições (0 a 31)
    -- Isso garante que a síntese não crie lógica desnecessária para endereços > 31
    pc_idx <= conv_integer(pc_reg(4 downto 0)); 

    -- DECODIFICAÇÃO
    opcode         <= instr_mem(pc_idx)(15 downto 12);
    reg_dest       <= instr_mem(pc_idx)(11 downto 8);
    reg_rs         <= instr_mem(pc_idx)(7  downto 4);
    reg_rt_or_imm4 <= instr_mem(pc_idx)(3  downto 0);
    imm8           <= instr_mem(pc_idx)(7  downto 0);

    branch_offset  <= reg_dest; 

    -- LEITURA DO BANCO DE REGISTRADORES
    rs_value <= reg_file(conv_integer(reg_rs));
    rt_value <= reg_file(conv_integer(reg_rt_or_imm4));

    -- SAÍDAS
    R0_out <= rs_value;
    R1_out <= rt_value;

    -- ALU
    rs_eq_rt    <= '1' when (rs_value = rt_value) else '0';
    mul_rs_rt   <= rs_value * rt_value;
    mul_rs_imm4 <= rs_value * ("000000000000" & reg_rt_or_imm4);

    branch_taken <= '1' when (opcode = "0100") or                      
                            (opcode = "0101" and rs_eq_rt = '1') or    
                            (opcode = "0110" and rs_eq_rt = '0')       
                    else '0';

    -- PROCESSO SÍNCRONO
    process(reset, clock)
    begin
        if reset = '1' then
            -- Reset síncrono ou assíncrono (dependendo da biblioteca, aqui resetando regs chave)
            pc_reg <= (others => '0');
            -- Resetar o banco de registradores inteiro consome muita área, 
            -- mas garante estado inicial conhecido.
            for i in 0 to 15 loop
                reg_file(i) <= (others => '0');
            end loop;

        elsif rising_edge(clock) then
            
            -- ETAPA 1: EXECUTAR A INSTRUÇÃO
            case opcode is
                when "0000" =>  -- LW
                    -- Nota: Usando 'conv_integer' limitado a 5 bits para data_mem tbm
                    reg_file(conv_integer(reg_dest)) <= 
                        data_mem(conv_integer(imm8(4 downto 0)));

                when "1010" =>  -- LDI
                    reg_file(conv_integer(reg_dest)) <= ("00000000" & imm8); 

                when "0111" =>  -- SW
                    data_mem(conv_integer(imm8(4 downto 0))) <= 
                        reg_file(conv_integer(reg_dest));

                when "0001" =>  -- ADD
                    reg_file(conv_integer(reg_dest)) <= rs_value + rt_value;

                when "0010" =>  -- SUB
                    reg_file(conv_integer(reg_dest)) <= rs_value - rt_value;

                when "0011" =>  -- MUL
                    reg_file(conv_integer(reg_dest)) <= mul_rs_rt(15 downto 0);        

                when "1000" =>  -- MUI
                    reg_file(conv_integer(reg_dest)) <= mul_rs_imm4(15 downto 0);        

                when "1001" =>  -- ADDI
                    reg_file(conv_integer(reg_dest)) <= rs_value + ("000000000000" & reg_rt_or_imm4);

                when "1011" =>  -- SUI
                    reg_file(conv_integer(reg_dest)) <= rs_value - ("000000000000" & reg_rt_or_imm4);

                when others =>
                    null;
            end case;

            -- ETAPA 2: ATUALIZAR PC
            if branch_taken = '0' then
                pc_reg <= pc_reg + 1;
            else
                if (opcode = "0101") or (opcode = "0110") then
                    pc_reg <= pc_reg + ("0000" & branch_offset);        
                elsif (opcode = "0100") then
                    pc_reg <= imm8;
                end if;
            end if;
        end if;
    end process;
 
end behavior;