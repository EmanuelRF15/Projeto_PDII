library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity pipeline is
    port (
        clock   : in  std_logic;
        reset   : in  std_logic;
        R0_out  : out std_logic_vector(15 downto 0); -- Debug
        R1_out  : out std_logic_vector(15 downto 0); -- Debug
        PC_out  : out std_logic_vector(7 downto 0)   -- Debug
    );
end pipeline;

architecture behavior of pipeline is


    -- TIPOS E MEMÓRIAS

    type data_mem_array  is array (0 to 255) of std_logic_vector(15 downto 0);
    type instr_mem_array is array (0 to 255) of std_logic_vector(15 downto 0);
    type reg_file_array  is array (0 to 15)  of std_logic_vector(15 downto 0);

    --  FORMATO LÓGICO QUE O HARDWARE ESTÁ USANDO:
    --  [15..12] opcode
    --  [11..8]  rd_addr   (destino p/ ALU / carga)
    --  [7..4]   rs_addr   (fonte A)
    --  [3..0]   rt_addr   (fonte B)
    --  [7..0]   imm8      (endereços/imediatos – compartilha os 4 bits de rt)

    signal instr_mem : instr_mem_array := (
        0  => "1010000100000010", -- LDI  R1, 2
        1  => "1010001000000101", -- LDI  R2, 5
        2  => "0001001100010010", -- ADD  R3 = R1+R2 (Forwarding de R1 e R2)
        3  => "1001010000110011", -- ADDI R4 = R3+3 (Forwarding de R3)
        4  => "0111000000010100", -- SW   [20] = R4
        5  => "0000010100010100", -- LW   R5 <- [20]
        6  => "0101001001000101", -- BEQ  R4,R5,+2 (Forwarding de R4 e R5)
        7  => "1010011000000000", -- LDI  R6, 0 (Pulo do BEQ cai aqui se não tomado)
        8  => "1000011000010100", -- MUI  R6 = R1*4
        9  => "0011011100110001", -- MUL  R7 = R3*R1
        10 => "0100000000000000", -- JMP  0
        others => (others => '0')
    );

    signal data_mem : data_mem_array := (others => (others => '0'));
    signal reg_file : reg_file_array := (others => (others => '0'));


    -- REGISTRADORES DE PIPELINE (Records)

    
    signal pc_reg : std_logic_vector(7 downto 0);

    -- 1. IF/ID
    type IF_ID_Type is record
        pc_plus_1 : std_logic_vector(7 downto 0);
        instr     : std_logic_vector(15 downto 0);
    end record;
    signal IF_ID : IF_ID_Type;

    -- 2. ID/EX
    type ID_EX_Type is record
        pc_plus_1 : std_logic_vector(7 downto 0);
        rs_val    : std_logic_vector(15 downto 0); -- Valor lido do RegFile
        rt_val    : std_logic_vector(15 downto 0); -- Valor lido do RegFile
        rs_addr   : std_logic_vector(3 downto 0);  -- Endereço para Forwarding
        rt_addr   : std_logic_vector(3 downto 0);  -- Endereço para Forwarding
        rd_addr   : std_logic_vector(3 downto 0);  -- Destino
        imm8      : std_logic_vector(7 downto 0);
        imm4      : std_logic_vector(3 downto 0);
        opcode    : std_logic_vector(3 downto 0);
        reg_write : std_logic;                     -- Sinal de controle: Escreve no Reg?
    end record;
    signal ID_EX : ID_EX_Type;

    -- 3. EX/MEM
    type EX_MEM_Type is record
        alu_result : std_logic_vector(15 downto 0);
        write_data : std_logic_vector(15 downto 0); -- Dado para SW (vem de RT/forwarding)
        rd_addr    : std_logic_vector(3 downto 0);
        opcode     : std_logic_vector(3 downto 0);
        reg_write  : std_logic;
        imm8       : std_logic_vector(7 downto 0); -- Endereço RAM para SW/LW
    end record;
    signal EX_MEM : EX_MEM_Type;

    -- 4. MEM/WB
    type MEM_WB_Type is record
        final_data : std_logic_vector(15 downto 0); -- Dado final (da RAM ou ALU)
        rd_addr    : std_logic_vector(3 downto 0);
        reg_write  : std_logic;
    end record;
    signal MEM_WB : MEM_WB_Type;

    -- Sinais de Flush e Branch
    signal branch_taken_ex : std_logic;
    signal target_pc       : std_logic_vector(7 downto 0);

begin

    -- Debug
    PC_out <= pc_reg;
    R0_out <= reg_file(0); -- Exemplo
    R1_out <= reg_file(1); -- Exemplo

    process(clock, reset)
        -- Variáveis para lógica combinacional da ALU e Forwarding
        variable alu_in_a : std_logic_vector(15 downto 0);
        variable alu_in_b : std_logic_vector(15 downto 0);
        variable v_mul_res: std_logic_vector(31 downto 0);
        
        -- Variáveis temporárias para decodificação
        variable v_opcode       : std_logic_vector(3 downto 0);
        variable v_reg_write_id : std_logic;
    begin
        if reset = '1' then
            pc_reg   <= (others => '0');
            reg_file <= (others => (others => '0'));
            
            -- Reset Pipeline Registers
            IF_ID  <= ((others=>'0'), (others=>'0'));
            ID_EX  <= ((others=>'0'), (others=>'0'), (others=>'0'),
                       (others=>'0'), (others=>'0'), (others=>'0'),
                       (others=>'0'), (others=>'0'), (others=>'0'), '0');
            EX_MEM <= ((others=>'0'), (others=>'0'), (others=>'0'),
                       (others=>'0'), '0', (others=>'0'));
            MEM_WB <= ((others=>'0'), (others=>'0'), '0');

        elsif rising_edge(clock) then
            

            -- ESTÁGIO 5: WB (WRITE BACK)

            if MEM_WB.reg_write = '1' then
                reg_file(conv_integer(MEM_WB.rd_addr)) <= MEM_WB.final_data;
            end if;


            -- ESTÁGIO 4: MEM (MEMORY ACCESS)

            MEM_WB.rd_addr   <= EX_MEM.rd_addr;
            MEM_WB.reg_write <= EX_MEM.reg_write;

            if EX_MEM.opcode = "0000" then -- LW
                MEM_WB.final_data <= data_mem(conv_integer(EX_MEM.imm8));
            elsif EX_MEM.opcode = "0111" then -- SW
                -- Aqui o dado vem de EX_MEM.write_data (que é alu_in_b = RT com forwarding)
                data_mem(conv_integer(EX_MEM.imm8)) <= EX_MEM.write_data;
                MEM_WB.final_data <= (others => '0'); -- SW não escreve em Reg
            else
                -- Para instruções ALU, o dado final é o resultado da ALU
                MEM_WB.final_data <= EX_MEM.alu_result;
            end if;

            -- ESTÁGIO 3: EX (EXECUTE) + FORWARDING UNIT
            
            -- 1. FORWARDING LOGIC (A Mágica acontece aqui)
            
            -- Entrada A da ALU (Forwarding para RS)
            if (EX_MEM.reg_write = '1' and EX_MEM.rd_addr = ID_EX.rs_addr) then
                -- Hazard EX: A instrução logo à frente calculou o valor que precisamos agora
                alu_in_a := EX_MEM.alu_result; 
            elsif (MEM_WB.reg_write = '1' and MEM_WB.rd_addr = ID_EX.rs_addr) then
                -- Hazard MEM: A instrução 2 ciclos à frente calculou o valor
                alu_in_a := MEM_WB.final_data;
            else
                -- Sem Hazard: usa o valor lido do banco de registradores
                alu_in_a := ID_EX.rs_val;
            end if;

            -- Entrada B da ALU (Forwarding para RT)
            if (EX_MEM.reg_write = '1' and EX_MEM.rd_addr = ID_EX.rt_addr) then
                alu_in_b := EX_MEM.alu_result;
            elsif (MEM_WB.reg_write = '1' and MEM_WB.rd_addr = ID_EX.rt_addr) then
                alu_in_b := MEM_WB.final_data;
            else
                alu_in_b := ID_EX.rt_val;
            end if;

            -- 2. EXECUÇÃO DA ALU (Usando alu_in_a e alu_in_b)
            EX_MEM.rd_addr   <= ID_EX.rd_addr;
            EX_MEM.opcode    <= ID_EX.opcode;
            EX_MEM.reg_write <= ID_EX.reg_write;
            EX_MEM.imm8      <= ID_EX.imm8;
            
            -- Valor a ser escrito na memória (SW) vem de alu_in_b (RT com forwarding)
            EX_MEM.write_data <= alu_in_b; 

            v_mul_res := (others => '0');

            case ID_EX.opcode is
                when "1010" => -- LDI
                    EX_MEM.alu_result <= "00000000" & ID_EX.imm8;
                when "0001" => -- ADD
                    EX_MEM.alu_result <= alu_in_a + alu_in_b;
                when "0010" => -- SUB
                    EX_MEM.alu_result <= alu_in_a - alu_in_b;
                when "1001" => -- ADDI (Usa Forwarding em A, Imediato em B)
                    EX_MEM.alu_result <= alu_in_a + ("000000000000" & ID_EX.imm4);
                when "0011" => -- MUL
                    v_mul_res := alu_in_a * alu_in_b;
                    EX_MEM.alu_result <= v_mul_res(15 downto 0);
                when others =>
                    EX_MEM.alu_result <= (others => '0');
            end case;

            -- 3. Lógica de Branch (Calculado no EX)
            branch_taken_ex <= '0';
            if ID_EX.opcode = "0100" then -- JMP
                branch_taken_ex <= '1';
                target_pc <= ID_EX.imm8;
            elsif ID_EX.opcode = "0101" then -- BEQ (Compara alu_in_a e alu_in_b forwarded)
                if alu_in_a = alu_in_b then
                    branch_taken_ex <= '1';
                    target_pc <= ID_EX.pc_plus_1 + ("0000" & ID_EX.rd_addr); 
                end if;
            end if;


            -- ESTÁGIO 2: ID (DECODE)

            v_opcode := IF_ID.instr(15 downto 12);
            
            -- Define se a instrução escreve no RegFile (Sinal de Controle Simples)
            if v_opcode = "0111" or v_opcode = "0100" or v_opcode = "0101" or 
               v_opcode = "0110" or v_opcode = "1111" then 
                v_reg_write_id := '0'; -- SW, JMP, Branches, NOP não escrevem em Reg
            else
                v_reg_write_id := '1'; -- ADD, SUB, LDI, LW, etc. escrevem
            end if;

            ID_EX.pc_plus_1 <= IF_ID.pc_plus_1;
            ID_EX.opcode    <= v_opcode;
            ID_EX.rd_addr   <= IF_ID.instr(11 downto 8);
            ID_EX.rs_addr   <= IF_ID.instr(7 downto 4);
            ID_EX.rt_addr   <= IF_ID.instr(3 downto 0);
            ID_EX.imm8      <= IF_ID.instr(7 downto 0);
            ID_EX.imm4      <= IF_ID.instr(3 downto 0);
            ID_EX.reg_write <= v_reg_write_id;

            -- Leitura padrão (sem saber se está velho)
            ID_EX.rs_val <= reg_file(conv_integer(IF_ID.instr(7 downto 4)));
            ID_EX.rt_val <= reg_file(conv_integer(IF_ID.instr(3 downto 0)));

            -- Flush no ID se houver branch
            if branch_taken_ex = '1' then
                ID_EX.reg_write <= '0'; -- Anula instrução transformando em NOP
                ID_EX.opcode    <= "1111";
            end if;


            -- ESTÁGIO 1: IF (FETCH)

            if branch_taken_ex = '1' then
                pc_reg <= target_pc;
                IF_ID.instr <= (others => '0'); -- NOP/Flush
            else
                pc_reg <= pc_reg + 1;
                IF_ID.pc_plus_1 <= pc_reg + 1;
                IF_ID.instr <= instr_mem(conv_integer(pc_reg));
            end if;

        end if;
    end process;

end behavior;   