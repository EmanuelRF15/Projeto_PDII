# Criando um clock virtual chamado "virtclk"

create_clock -name {clock} -period 1.100 -waveform { 0.000 0.550 } clock

# Configurando delay de entrada e de saida

set_input_delay -clock clock 0.1 [all_inputs]

set_output_delay -clock clock 0.1 [all_outputs]
