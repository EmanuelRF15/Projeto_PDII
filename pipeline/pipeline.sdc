# Criando um clock virtual chamado "virtclk"

create_clock -name {clock} -period 1.060 -waveform { 0.000 0.530 } clock

# Configurando delay de entrada e de saida

set_input_delay -clock clock 0.1 [all_inputs]

set_output_delay -clock clock 0.1 [all_outputs]
