		include	"constants.asm"

		org	altlcd			; Non-relocatable part that runs from ALTLCD.

		jmp	start
		
		;;;; Interrupt routine (this place in ALTLCD is safe) 
isr		push	psw			; Save all registers
		push	b
		push	d
		push	h
		;; Check if the program is still in memory and deregister if not
		;; (the program itself does not use the LCD routines in ROM; the lowermost 
		;; LCD RAM location is set to 0 (a value it will never have) to indicate no 
		;; other program has touched it yet. Any CLS (such as on "Menu" or reset)
		;; will overwrite it with a nonzero value. 
		lda	sentinel
		ana	a
		jz	isr_run
		;; The LCD RAM has been touched - deregister myself and stop
		mvi	a,0c9h			; RET
		sta	isrvec
isrdone		pop	h			; Restore all registers
		pop	d
		pop	b
		pop	psw
		ret
		
isr_run		lxi	h,isrdone		; so we can safely 'ret' in the rest of the routine
		push	h
		lxi	h,counter		; Countdown (we need to run only every 4 cycles)
		dcr	m
		rnz		
		mvi	m,4			; Reset counter
		inr	l			; Look at delay timer
		xra	a
		ora	m			
		jz	isr_st			; If nonzero, decrease by 1
		dcr	m 
isr_st		inr	l			; Look at sound timer
		xra	a
		ora	m
		jz	isr_snd_off
		dcr	m
		ret
isr_snd_off	in	0bah			; If sound timer 0, turn off the speaker
		ori	4
		out 	0bah
		ret
		
		
		;;;; Set up the jump table in memory
		; Set every entry in the table to point to a 'ret'
start		lxi	h,jptbl		
		mvi	b,127		
		mvi	a,low fn_ret
		call	memset
		; Set the defined entries in the table to their definitions
		lxi	d,func_tbl	; Function table
		mvi	b,ftblsz	; amount of entries in the function table 
		mvi	h,high jptbl	; Page for jump table
load_jptbl	ldax	d		; Get location of next byte in jump table
		inx	d
		mov	l,a
		ldax	d		; Get entry for that location
		inx	d
		mov	m,a		; Store it
		dcr	b
		jnz	load_jptbl 
		
		;;;; Machine initialization
		call	r_cls		; Clear the screen
		sta	sentinel	; Zero the sentinel value in LCD RAM (cls ends with A=0)
		lxi 	h,stackptr	; Zero stack pointer
		mov	m,a		
		dcx	h
		mov	m,a 		; Zero ST
		dcx	h
		mov	m,a		; Zero DT
		dcx	h
		mvi	m,4		; Set the ISR countdown to 4
		lxi	h,isr		; Register the ISR 
		lxi	d,isrvec + 1	; ...carefully, address first...
		db	shlx
		dcx	d
		mvi	a,0c3h		; ..and only then the RET
		stax	d 
		
		lhld	vm_mem_start	; Find the entry point
		inr	h
		inr	h
		xchg			; Set DE = entry point
		
		; The machine cycle loop is located further on in RAM, so that all opcode routines 
		; are in FDxx, so we only need 1-byte values in the lookup table.
		jmp 	cycle		
		
;;;;; Opcode routines ;;;;;
; Input: BC = 16-bit instruction; DE = address of next instruction 
; Output: DE = address of next instruction
; These must all be in FDxx
		
;; 00E0=cls 00EE=ret; anything else should be ignored
op_0		mvi	a,0e0h		; cls?
		cmp	c
		jz	r_cls
		mvi	a,0eeh		; ret? 
		cmp	c
		rnz			; if _not_, return
		; Pop address from stack and set the PC to it
		lxi	h,stackptr
		dcr	m		
		dcr	m
		mov	l,m
		lda	vm_mem_start + 1
		mov	h,a
		xchg
		db	lhlx
		xchg
		ret 

;; 2XXX: CALL XXX
op_2		; Push current PC on stack (it has already been incremented) 
		xchg
		lda	stackptr
		mov	e,a
		lda	vm_mem_start + 1
		mov	d,a
		db	shlx
		inr	e		
		inr	e		
		sta	stackptr
		; Fall through into JMP 
		
;; 1XXX: JP XXX	
op_1		mov	a,b		; Zero out high nybble of high byte
		ani	0fh
		lxi	h,vm_mem_start + 1
		add	m		; Add offset
		mov	d,a
		mov	e,c		; Low byte of address is unchanged
		ret

;; 5XY0: SE Vx, Vy - Skip next instruction if Vx = Vy
op_5		call	reg_C		; Get Vy
		mov	c,a		; Store where KK would be
		; Fall through into 3XKK
		
;; 3XKK: SE Vx, KK - Skip next instruction if Vx = KK
op_3		call	reg_B		; Get Vx
		cmp	c		; Compare to KK
		rnz			; If not equal, do nothing
		inx	d		; If equal, advance PC
		inx	d
		ret 

;; 9XY0: SNE Vx, Vy - Skip next instruction if Vx = Vy
op_9		call	reg_C		; Get Vy
		mov	c,a		; Store where KK would be
		; Fall through in to 4XKK
		
;; 4XKK: SNE Vx, KK - Skip next instruction if Vx != KK
op_4		call	reg_B		; Get Vx
		cmp	c		; Compare to KK
		rz			; If equal, do nothing
		inx	d		; If not equal, advance PC 
		inx	d
		ret		
;; 6XKK: LD Vx, KK - Set Vx = KK
op_6		call	reg_B		; Get Vx
		mov	m,c 		; Store KK
		ret


;; 7XKK: ADD Vx, KK - Set Vx = Vx + KK
op_7		call	reg_B		; Get Vx
		add	c		; Add KK
		mov	m,a		; Store it back
		ret		
		
;; 8XYF: Vx = F(Vx, Vy) 
;;  where: F = 0 = Vy      (LD Vx, Vy)
;;         F = 1 = Vx|Vy   (OR Vx, Vy)
;;         F = 2 = Vx&Vy   (AND Vx, Vy)
;;         F = 3 = Vx^Vy   (XOR Vx, Vy)
;;         F = 4 = Vx+Vy   (ADD Vx, Vy)
;;         F = 5 = Vx-Vy   (SUB Vx, Vy)
;;         F = 6 = Vx<<1   (SHR Vx) 
;;         F = 7 = Vy-Vx   (SUBN Vx, Vy)
;;         F = E = Vx>>1   (SHL Vx) 	
op_8		push	d		; Store the PC
		call	reg_C		; Retrieve the resgister values
		mov	e,a
		call	reg_B
		mov	d,a
		
		mov	a,c		; Get F from the instruction 
		ani	0fh
		lxi	h,op_8_ret	; Push return address on stack
		push	h
		mvi	h,high jptbl	; Look up F in the jump table
		mov	l,a
		mov	l,m
		mvi	h,high fn8_ld
		
		mov	a,d		; Preload Vx into the accumulator
		pchl
op_8_ret	mov	d,a		; Store Vx back 
		call	reg_B
		mov	m,d
		pop	d
		ret

;; ANNN: Set I = NNN
op_A		mov	a,b		; Zero out high nybble of high byte
		ani	0fh
		mov	h,a
		mov	l,c		; Low byte stays the same 
		shld	reg_I
		ret

;; BNNN: JP V0, NNN - Jump to NNN+V0 		
op_B		lxi	h,reg_V		; Set HL = V0 
		mov	l,m
		inr	h		; zero H (H=FF here)
		dad	b		; Add address to it
		mov	b,h		; Put address back in BC
		mov	c,l
		jmp	op_1		; the jump routine takes care of the high nybble

;; DXYN: DRW Vx, Vy, N - At coords (Vx, Vy), draw N-byte sprite from memory at I 
op_D		push	d		; We need it for the coordinates
		call	reg_C		; Y coordinate register 
		mov	e,a
		call	reg_B		; X coordinate register 
		mov	d,a
		mov	a,c		; Number of bytes
		ani	0fh
		mov	b,a
		call	hl_I
		call	r_drawsprite
pop_d_ret	pop	d
		ret 
	
;; Ex9E: SKP Vx; ExA1: SNKP Vx: skip if key Vx is (not) pressed	
op_E		call	reg_B		; Retrieve Vx
		call	keyscan
		push	psw
		
		mvi	a,9eh		; Skip if pressed?
		cmp	c
		jz	op_E_skp
		; Skip if not pressed 
		pop	psw
		rz
		db	21h		; lxi h,_ to skip 'pop psw/rnz'
		; Skip if pressed
op_E_skp	pop	psw
		rnz
		inx	d
		inx	d
		ret 

;; Fxff: ff(&Vx) where: 
;;	ff = 07 = LD Vx, DT
;;	ff = 0A = LD Vx, K
;;	ff = 15 = LD DT, Vx
;;	ff = 18 = LD ST, Vx
;;	ff = 1E = ADD I, Vx
;;	ff = 29 = LD F, Vx (set I=sprite location for font[Vx])
;;	ff = 33 = LD B, Vx ( (I,I+1,I+2) = BCD(Vx) )
;;	ff = 55 = LD [I], Vx
;;	ff = 65 = LD Vx, [I]
;;
;; The jump table stores ff as ff+1 so the same table as 8 can be used.

op_F		push	d
		; Push address of "pop d - ret" onto stack
		lxi	h,pop_d_ret
		push	h
		; Find address of function and push it on the stack
		mvi	h,high jptbl
		mov	l,c
		inr	l 
		mov	l,m
		mvi	h,high fn8_ld
		push	h
		; Retrieve register and continue into the function
		jmp	reg_B
	
;; Cxkk = generate a random number, AND it with KK, and store it in Vx 	
op_C		push	b
		push	d
		call	random		; BASIC's RND function
		mvi	d,8
		lxi	h,fac1		; XOR together a bunch of the data
nextbyte	rlc
		xra	m		
		dcr	d
		jnz 	nextbyte
		pop	d
		pop	b
		ana	c		; AND it with KK
		mov	c,a
		call	reg_B
		mov	m,c
		ret
		
;;;;;; Functions ;;;;;;
; These must all be in FExx 

;; Fn8: Input: A = D = Vx, E = Vy, carry flag = 0
;; Output: A = new Vx
;; B must be preserved. 
fn8_ld		mov	a,e
		ret

fn8_or		ora	e
		ret

fn8_and		ana	e
		ret

fn8_xor		xra	e
		ret

fn8_subn	mov	e,a
		mov	d,e
fn8_sub		sub	e
		cmc			; Chip-8 carry flag is opposite of 8085 carry flag here
		db	16h		; mvi d,_ - to skip the 'add e' below  
fn8_add		add	e
		;; Update VF to current carry flag
fn8_updateVF 	mov	d,a
		ral 
		ani	1
		sta	reg_VF
		mov	a,d
fn_ret		ret

fn8_shl		ral
		db	16h		; mvi d,_ to skip the 'rar' below
fn8_shr		rar
		jmp	fn8_updateVF
		
;; FnF: input: HL points at Vx register, A = contents of Vx register
fnf_ld_Vx_DT	lda	reg_DT
		mov	m,a
		ret

		;; Wait for key press, store key press in Vx
fnf_ld_Vx_K	call	keyscan		; Is key Vx pressed?
		rz			; If yes, stop.
		inr	a		; If not, try next key
		ani	0fh
		mov	m,a
		jmp	fnf_ld_Vx_K
		
fnf_ld_DT_Vx	sta	reg_DT		; Store delay timer
		ret
		
fnf_ld_ST_Vx	sta	reg_ST		; Store sound timer
		ana	a
		rz			; If zero, do nothing (the ISR will turn the sound off)
		di
		in	0bah		; Otherwise, turn the sound on
		ani	219
		ori	32
		out	0bah 
		ei
		ret

fnf_add_I_Vx	lhld	reg_I		; I register
		add	l
		mov	l,a		; Add Vx
		mvi	a,0
		adc	h		; Increment high byte if necessary
		ani	0fh		; Keep I within bounds of memory
		mov	h,a
store_reg_I	shld	reg_I
		ret
		
		;; Set I = font[Vx] 
		;; which is 0100 + Vx * 5
fnf_ld_F_Vx	mov	l,a
		add	a
		add	a
		add	l
		mov	l,a
		mvi	h,1		; Font is in first page
		jmp	store_reg_I
		
		;; Store BCD at [I..I+2].
		;; We don't worry about two bytes of overflow, there's room, and it's
		;; undefined behaviour anyway (The first 2 pages are supposed to b
		;; reserved for the interpreter.)
fnf_ld_B_Vx	lxi	d,640ah		; D=100 (64h), E=10 (Ah)
		mov	b,a
		call	hl_I
		mov	a,b
		mvi	b,-1
		mov	m,b
hundreds	inr	m
		sub	d
		jnc	hundreds
		add	d
		inx	h
		mov	m,b
tens		inr	m
		sub	e
		jnc	tens
		add	e
		inx	h
		mov	m,a
		ret
		
fnf_ld_I_Vx	mvi	a,0ebh		; ld_I_Vx; use an XCHG
		db	6		; 6 = mvi b,_ = skip the 'xra a'. 
fnf_ld_Vx_I	xra	a		; ld_Vx_I: use a NOP
		sta	ldivx_nop_xchg
		mov	c,m		; BC = Vx
		mvi	b,0
		lxi	d,reg_V		; DE = *V0
		call	hl_I		; HL = [I]
ldivx_nop_xchg	xchg			; with XCHG, copy Vx->[I]; with NOP, [I]->Vx; this is rewritten
		jmp	memcpy		; copy from HL to DE for BC byte
		
;;;;; One machine cycle (VM inner loop) ;;;;;
cycle		lxi	h,cycle		; Push the address onto the stack, so the opcode 
		push	h		; routine can RET
		
		db	lhlx		; Retrieve 2-byte instruction 
		mov	b,l		; Store in BC. Low/high swap is on purpose, Chip-8 is high-endian
		mov	c,h 
		inx	d		; Point to next instruction  
		inx	d
		
		mov	a,b		; Get high nybble of first byte of instruction (opcode)
		rlc 
		rlc 
		rlc 
		rlc
		ani 	0fh
		mvi	h,high op_tbl	; Look up the entry point in the table
		adi	low op_tbl
		mov	l,a
		mov	l,m
		mvi	h,high op_0
		pchl
		
		
;;;;; Subroutines ;;;;;

		;;;; Get register in upper C
reg_C		mov	a,c
		rrc
		rrc
		rrc
		rrc
		db	26h		; mvi h,_ : to skip mov a,b below
		;;;; Get register in lower B
reg_B		mov 	a,b
		ani	0fh
		ori	low reg_V
		mov	l,a
		mvi	h,high reg_V
		mov	a,m
		ret 
		;;;; Set HL = [I]
hl_I		lda	vm_mem_start + 1
		lhld	reg_I
		add	h
		mov	h,a
		ret
		
		;;;; Scan the keyboard
		; Input: A = hex value of key to test
		; Output: zero flag set if key down, reset if key up 	
keyscan		push	h
		push	b
		lxi	h,keyin		; Keyboard input line table
		add	l
		mov	l,a		; Index Vx into keyboard input line table 
		mov	a,m
		di
		out	0b9h		; Set keyboard output lines
		in	0e8h		; Read keyboard input lines
		ei 
		mov	b,a		; Store keyboard input in B
		mov	a,l
		adi	16		; Output line table is 16 bytes beyond input line table
		mov	l,a
		
		mov	a,m		; Input line table
		ora	b
		pop 	b
		pop	h
		ret


;;;;;; Control data ;;;;;;

		;;;; Opcode routine entry points. TABLE MUST NOT CROSS PAGE BOUNDARY
op_tbl		db	low op_0, low op_1, low op_2, low op_3
		db	low op_4, low op_5, low op_6, low op_7
		db	low op_8, low op_9, low op_A, low op_B
		db	low op_C, low op_D, low op_E, low op_F

		;;;; Function table for 8xyf and Fxff
		; Fxff all has its functions increased by 1 so they don't conflict.
		; This table may (probably does) cross a page boundary
		;
		; 8xyf 
func_tbl	db	00h,low fn8_ld
		db	01h,low fn8_or
		db	02h,low fn8_and
		db	03h,low fn8_xor
		db	04h,low fn8_add
		db	05h,low fn8_sub
		db	06h,low fn8_shr
		db	07h,low fn8_subn
		db	0eh,low fn8_shl
		; Fxff
		db	1 + 07h, low fnf_ld_Vx_DT
		db	1 + 0ah, low fnf_ld_Vx_K
		db	1 + 15h, low fnf_ld_DT_Vx
		db	1 + 18h, low fnf_ld_ST_Vx
		db	1 + 1eh, low fnf_add_I_Vx
		db	1 + 29h, low fnf_ld_F_Vx
		db	1 + 33h, low fnf_ld_B_Vx
		db	1 + 55h, low fnf_ld_I_Vx
		db	1 + 65h, low fnf_ld_Vx_I
ftblsz		equ	($ - func_tbl) >> 1

	
		;;;; Keyboard mapping 
		; 5 6 7 8   ==  1 2 3 C
		; T Y U I   ==  4 5 6 D
		; G H J K   ==  7 8 9 E 
		; B N M ,   ==  A 0 B F 

		; Chip-8 nybble -> keyboard input lines. TABLE MUST NOT CROSS PAGE BOUNDARY
keyin		db	0feh, 0efh, 0efh, 0efh
		db	0fbh, 0fbh, 0fbh, 0fdh
		db	0fdh, 0fdh, 0feh, 0feh
		db	0efh, 0fbh, 0fdh, 0feh
		; Chip-8 nybble -> keyboard output lines 
keyout		db	0dfh, 0efh, 0dfh, 0bfh
		db	0efh, 0dfh, 0bfh, 0efh
		db	0dfh, 0bfh, 0efh, 0bfh
		db	07fh, 07fh, 07fh, 0f7h
		
		