# TRS-80 Chip-8 VM Makefile

ASM=asm8080
MKBAS=python3 rlcbasic.py

chip8h.bin: chip8h.asm
	$(ASM) -lchip8h.lst chip8h.asm

chip8r.bin: chip8r.asm
	$(ASM) -lchip8r.lst chip8r.asm

chip8.bin: chip8r.bin chip8h.bin
	cat chip8r.bin chip8h.bin > chip8.bin

make: chip8.bin
	$(MKBAS) chip8.bin > chip8.ba

clean:
	rm *.bin *.lst *.hex *.ba

