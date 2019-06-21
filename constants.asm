;; Undocumented operations
ldsi		equ	38h	; DE = SP + imm8
lhlx		equ	0edh	; HL = (DE) 
shlx		equ 	0d9h	; (DE) = HL
dsub		equ	8h	; HL -= BC

;; Constants
vm_speed	equ	512	; Reduced speed is 768 Hz. 
maxram 		equ	0f5f4h	; Maximum memory
origin		equ	8000h	
relocate	equ	7676h	; Relocation marker
memsize		equ	1000h	; The Chip-8 VM needs 4KB of memory
entry_point	equ	0200h	; Chip-8 program entry point


;; ROM functions
beep		equ	4229h
memcpy		equ	6bdbh	; copy BC bytes from HL to DC 
srcnam		equ	20afh	; find file whose name is in FILNAM 
buf_ch_upper	equ	0fe8h	; get character in M, make it uppercase, and store in A
inlin		equ	463eh	; read line from keyboard and place at kbuf
bzero		equ	4f0ah	; starting at HL, set B bytes of memory to 0.
memset		equ	4f0bh	; starting at HL, set B bytes of memory to A
chkdc		equ	5aa9h	; Find file
isr_exit	equ	71f7h	; Interrupt exit routine
drvwait         equ     7548h   ; wait for selected LCD driver to be ready
lcdread         equ     74f5h   ; read LCD memory
lcdwrite        equ     74f6h   ; write LCD memory
scan_key        equ     7242h	; Scan the keyboard

;; RAM locations
kbuf		equ	0f685h	; line input buffer
altlcd		equ	0fcc0h	
strend		equ	0fbb6h	; start of free memory
lcdbuf          equ     0ffech  ; used as temporary storage to read from and write to the LCD
isrvec		equ	0f5ffh	; Timer ISR vector 
sentinel	equ	0ff3fh	; Location for ISR sentinel (last value in LCD memory)
type_buf_len	equ	0ffaah	; Amount of characters in the typeahead buffer
timer		equ	0f92fh	; Timer (to seed RNG with)
keydown		equ	0ff90h	; This location in memory holds 2 iff a key is held down. 

;; Variables used by the relocator 
getPC		equ	0f685h	; location to store the routine that finds the PC
rlc_offset	equ	0f687h	; relocation offset (from 8000)
rlc_index	equ	0f689h	; relocation index
v_no_relocate	equ	0f68bh
v_relocate_loop	equ	0f68dh
rlc_end_addr	equ	0f68fh

;; Jumps to relocated subroutines (spaced 5 bytes apart so the relocation NOPs aren't a problem)
;; (The relocator is done by now so we can reuse its memory locations)
rlc_jptbl_start	equ	0f685h	; This is the start address for the jump table. 
r_cls		equ	0f685h	; a 'jmp cls' is written here
r_drawsprite	equ	0f68ah	; a 'jmp drawsprite' is written here
r_xcab_rnd	equ	0f68fh	; a 'jmp xcab_rnd' is written here
r_reg_C		equ	0f694h  ; usw. usw. 
r_reg_B		equ	0f699h
r_hl_I		equ	0f69eh

;; Jump table
jptbl		equ	0f700h	; 128-byte jump table for 8 and F. 

;; Variables used by the program itself
vm_mem_start	equ	0ff46h	; Start of VM memory
slow_delay	equ	0ff48h	; Delay timer for slow mode
reg_V		equ	0ff50h	; base location for registers
reg_VF		equ	0ff5fh	; the VF register 
counter		equ	0ff60h	; Counter for interrupt routine
reg_DT		equ	0ff61h	; Delay timer
reg_ST		equ	0ff62h	; Sound timer
stackptr	equ	0ff63h	; Stack pointer (8-bit, points into first page of VM memory)
reg_I		equ	0ff64h	; Memory pointer
funkey		equ	0ff66h	; Will be set to the function key row by the ISR
rnddat		equ	0ff67h	; This will hold 4 bytes of state for the random number generator
quirks		equ	0ff6bh  ; Quirks byte

