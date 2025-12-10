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

   
    -- PC
   
    signal pc_reg : std_logic_vector(7 downto 0);  

   
    -- TIPOS DE MEMÓRIA
   
    type data_mem_array  is array (0 to 255) of std_logic_vector(15 downto 0);
    type instr_mem_array is array (0 to 255) of std_logic_vector(15 downto 0);
    type reg_file_array  is array (0 to 15)  of std_logic_vector(15 downto 0);

   
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

   
    -- MEMÓRIA DE DADOS (RAM)
   
    signal data_mem : data_mem_array := (
        others => (others => '0')
    );

   
    -- BANCO DE REGISTRADORES
   
    signal reg_file : reg_file_array := (others => (others => '0'));

   
    -- CAMPOS DECODIFICADOS DA INSTRUÇÃO
    -- Formato: [15..12]=opcode, [11..8]=rd/offset, [7..4]=rs, [3..0]=rt/imm4
   
    signal opcode        : std_logic_vector(3 downto 0);
    signal reg_dest      : std_logic_vector(3 downto 0);  -- rd ou offset de branch
    signal reg_rs        : std_logic_vector(3 downto 0);  -- fonte A (rs)
    signal reg_rt_or_imm4: std_logic_vector(3 downto 0);  -- fonte B (rt) OU imm4
    signal imm8          : std_logic_vector(7 downto 0);  -- imediato de 8 bits
    signal branch_offset : std_logic_vector(3 downto 0);  -- offset de branch (4 bits)

   
    -- SINAIS DE CONTROLE E DADOS INTERNOS
   
    signal branch_taken   : std_logic;
    signal mul_rs_rt      : std_logic_vector(31 downto 0);
    signal mul_rs_imm4    : std_logic_vector(31 downto 0);
    signal rs_eq_rt       : std_logic;
    
    -- Valores lidos do banco de registradores
    signal rs_value       : std_logic_vector(15 downto 0);
    signal rt_value       : std_logic_vector(15 downto 0);

begin

   
    -- DECODIFICAÇÃO DA INSTRUÇÃO NA POSIÇÃO PC
   
    opcode         <= instr_mem(conv_integer(pc_reg))(15 downto 12);
    reg_dest       <= instr_mem(conv_integer(pc_reg))(11 downto 8);
    reg_rs         <= instr_mem(conv_integer(pc_reg))(7  downto 4);
    reg_rt_or_imm4 <= instr_mem(conv_integer(pc_reg))(3  downto 0);
    imm8           <= instr_mem(conv_integer(pc_reg))(7  downto 0);

    branch_offset  <= reg_dest;  -- mesmo campo usado como offset no branch

   
    -- LEITURA DO BANCO DE REGISTRADORES (rs e rt)
   
    rs_value <= reg_file(conv_integer(reg_rs));
    rt_value <= reg_file(conv_integer(reg_rt_or_imm4));

    -- Só para visualização no testbench (não são R0/R1 fixos)
    R0_out <= rs_value;
    R1_out <= rt_value;

   
    -- "ALU" E SINAIS AUXILIARES
   
    rs_eq_rt    <= '1' when (rs_value = rt_value) else '0';

    -- Multiplicação registrador x registrador
    mul_rs_rt   <= rs_value * rt_value;

    -- Multiplicação registrador x imediato de 4 bits (zero-extend)
    mul_rs_imm4 <= rs_value * ("000000000000" & reg_rt_or_imm4);

    -- Lógica do branch: JMP, BEQ, BNE
    branch_taken <= '1' when (opcode = "0100") or                      -- JMP
                            (opcode = "0101" and rs_eq_rt = '1') or    -- BEQ
                            (opcode = "0110" and rs_eq_rt = '0')       -- BNE
                    else '0';

   
    -- PROCESSO SÍNCRONO: EXECUÇÃO DA INSTRUÇÃO + ATUALIZAÇÃO DO PC
   
    process(reset, clock)
    begin
        if reset = '1' then
            reg_file <= (others => (others => '0'));
            pc_reg   <= (others => '0');

        elsif rising_edge(clock) then
            
           
            -- ETAPA 1: EXECUTAR A INSTRUÇÃO (ESCRITA EM REG/ MEM)
           
            case opcode is
                when "0000" =>  -- LW: rd <- MEM[imm8]
                    reg_file(conv_integer(reg_dest)) <= 
                        data_mem(conv_integer(imm8));

                when "1010" =>  -- LDI: rd <- imm8 (zero-extend)
                    reg_file(conv_integer(reg_dest)) <= 
                        ("00000000" & imm8); 

                when "0111" =>  -- SW: MEM[imm8] <- rd
                    data_mem(conv_integer(imm8)) <= 
                        reg_file(conv_integer(reg_dest));

                when "0001" =>  -- ADD: rd <- rs + rt
                    reg_file(conv_integer(reg_dest)) <= 
                        rs_value + rt_value;

                when "0010" =>  -- SUB: rd <- rs - rt
                    reg_file(conv_integer(reg_dest)) <= 
                        rs_value - rt_value;

                when "0011" =>  -- MUL: rd <- (rs * rt) (16 LSBs)
                    reg_file(conv_integer(reg_dest)) <= 
                        mul_rs_rt(15 downto 0);        

                when "1000" =>  -- MUI: rd <- rs * imm4
                    reg_file(conv_integer(reg_dest)) <= 
                        mul_rs_imm4(15 downto 0);        

                when "1001" =>  -- ADDI: rd <- rs + imm4
                    reg_file(conv_integer(reg_dest)) <= 
                        rs_value + ("000000000000" & reg_rt_or_imm4);

                when "1011" =>  -- SUI: rd <- rs - imm4
                    reg_file(conv_integer(reg_dest)) <= 
                        rs_value - ("000000000000" & reg_rt_or_imm4);

                when others =>
                    null;
            end case;

           
            -- ETAPA 2: ATUALIZAR PC (PC+1 OU SALTO)
           
            if branch_taken = '0' then
                -- Caminho normal: próxima instrução
                pc_reg <= pc_reg + 1;
            else
                -- Caminho de desvio
                if (opcode = "0101") or (opcode = "0110") then
                    -- BEQ/BNE: salto relativo (PC = PC + offset)
                    pc_reg <= pc_reg + ("0000" & branch_offset);        
                elsif (opcode = "0100") then
                    -- JMP: salto absoluto (PC = imm8)
                    pc_reg <= imm8;
                end if;
            end if;
        end if;
    end process;
 
end behavior;
