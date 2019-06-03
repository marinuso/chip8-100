;; Undocumented operations
ldsi		equ	38h	; DE = SP + imm8
lhlx		equ	0edh	; HL = (DE) 
shlx		equ 	0d9h	; (DE) = HL
dsub		equ	8h	; HL -= BC

;; Constants
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

;; Variables used by the relocator 
getPC		equ	0f685h	; location to store the routine that finds the PC
rlc_offset	equ	0f687h	; relocation offset (from 8000)
rlc_index	equ	0f689h	; relocation index
v_no_relocate	equ	0f68bh
v_relocate_loop	equ	0f68dh
rlc_end_addr	equ	0f68fh

;; Jumps to relocated subroutines
r_cls		equ	0f691h	; a 'jmp cls' is written here

;; Variables used by the program itself
vm_mem_start	equ	0ff46h	; Start of VM memory

reg_V		equ	0ff50h	; Regs V0..VF stored here
reg_VF		equ	0ff5fh
