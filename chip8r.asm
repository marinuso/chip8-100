		include	"constants.asm"

		org	origin		
		
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		;;;;;; Self-relocator
		
		;;; Figure out where we are
start		lxi	h,0e9e1h	; POP H / PCHL 
		shld	getPC
		call	getPC	
		lxi	b,$ - start - origin
		db	dsub
		shld	rlc_offset	; Offset to add to relocated addresses
		push	h
		lxi	b,program
		dad	b
		shld	rlc_index	; Address to start relocation
		lxi	b,relocsize	; Address to end relocation 
		dad	b
		shld	rlc_end_addr
		
		;;; Calculate jumps for relocation routine
		pop	h
		push 	h
		lxi	d,no_relocate
		dad	d
		shld	v_no_relocate
		
		pop	h
		lxi	d,relocate_loop
		dad	d
		shld	v_relocate_loop
		
		;;; If the relocation marker (76 76, or HLT HLT) is found, NOP it out, 
		;;; and assume the next 3 bytes are an instruction containing an address
		;;; that needs to be adjusted.
		;;; It's simple enough to choke on things like 'lxi h,7676h'.
		lhld	rlc_index
		xchg
relocate_loop	db	lhlx		; Get current word
		push	d		; Is it the relocation marker?
		lxi	d,relocate	
		rst	3
		pop	d
no_rlc_jmp	lhld	v_no_relocate
		push	h
		rnz			; If not, try next byte 
		pop	h
		lxi	h,0		; If yes, nop out the marker
		db	shlx		
		inx	d		; Advance past the marker
		inx	d
		inx	d		; and past the instruction byte
		push	d		; Get the address word
		db	lhlx
		xchg			; Add the offset 
		lhld	rlc_offset
		dad	d
		pop	d
		db	shlx 		; Store the word back
		inx	d
no_relocate	inx	d		; Next location 
		lhld	rlc_end_addr	; Are we there yet?
		rst	3
		lhld	v_relocate_loop
		push	h
		rnz	
program		;;; Program follows

		;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		
		;;;; Set up memory	
		lxi	h,beep		; Put the "BEEP" address onto the stack, so that
		xthl			; we can do RET in case of a failure.
		;;;; Check if enough memory is available.
		; (4096 bytes VM memory + 128 stack bytes + 256 so we can page-align the VM image)
		;
		db	ldsi,0		; load stack in HL
		xchg
		lxi	b,(memsize + 512)	; 256 stack bytes, 256 extra bytes for page alignment
		db	dsub		; subtract VM image size
		xchg			; DE = minimum start address of VM image
		lhld	strend		; HL = actual start of free memory
		rst	3		; HL < DE?
		rnc			; if yes, beep and exit, not enough memory
		
		;;;; Ask for file and figure out where it starts
		call	inlin		; Ask for filename
		rc			; Ctrl+C = stop
		; Make the filename in the keyboard buffer uppercase
uppercase	inx	h
		call	buf_ch_upper
		mov	m,a
		ana	a
		dw	relocate
		jnz	uppercase
		; Find the file 
		lxi	d,kbuf
		call	chkdc		; Find the file in the directory
		rz			; No file, beep and exit.
		mvi	a,0c0h		; Valid .DO file?
		ana	m
		cmp	m
		rnz			; No: beep and exit. 
		inx	h		; start address now under HL
		xchg			; Load start address
		db	lhlx
		xchg			; Start address in DE
		
		;;;; Find a page-aligned start address for the VM memory
		lhld	strend		; Start of free memory
		inr	h		; Next page
		mvi	l,0		; Start of next page
		shld	vm_mem_start	; Store it as start of VM memory
		
		;;;; Load the program into memory at 0200h.
		xchg			; Start of memory in DE, start of hex file in HL.
		inr	d		; Move ahead 2 pages. 
		push	d		; The font will be loaded in page 1 later. 
		inr	d
		
		lxi	b,memsize - entry_point 	; Max amount of bytes to read
hex_load_loop	push	b
		dw	relocate
		call	hex_byte	; Read a byte from the hexadecimal file
		pop	b
		dw	relocate
		jc	font_load 	; If EOF then done
		stax	d		; If not, store the byte
		inx	d		; Advance the pointer
		dcx	b		; One fewer byte left
		mov	a,b		; Out of memory?
		ora	c
		dw	relocate
		jnz	hex_load_loop	; If not, go get another byte
		
		;;;; Unpack the font data and load it into page 1.
		; The font consists of 5 bytes per hex digit, with the data in the high nybble
		; and the low nybble set to 0. The font is stored packed in the executable file,
		; with two digits per byte, one in each nybble. 
		dw	relocate
font_load	lxi	d,font		; DE = location of font data
		pop	h		; HL = page 1 of VM memory (from the stack)
		lxi	b,28f0h		; B=40 (28h) packed font bytes, C=0F0h
font_load_loop	ldax	d 		; Get current input byte
		ana	c		; Zero out low nybble
		mov	m,a		; Store it in VM memory
		inr	l		; Next byte in VM memory
		ldax	d		; Get current input byte again
		rlc			; Rotate low nybble into high nybble
		rlc
		rlc
		rlc 
		ana	c		; Zero out low nybble
		mov	m,a		; Store it in VM memory
		inr	l		; Next VM byte
		inx	d		; Next input byte
		dcr	b		; Done yet?
		dw	relocate
		jnz	font_load_loop	; If not, next byte

		;;;; Copy the relocated jump table 
		;;;; Calculate and store 'jmp cls' in a known address
		dw	relocate
		lxi	h,rlc_jptbl
		lxi	d,rlc_jptbl_start
		lxi	b,rlc_jptbl_sz
		call	memcpy
		
		;;;; Program the timer to generate a square wave, and set it to output to
		;;;; the speaker, but leave the speaker off.
		di
		xra	a
		out	0bch
		mvi	a,10h | 40h
		out	0bdh
		mvi	a,0c3h
		out	0b8h
		in	0bah
		ani	0dbh
		ori	24h
		out	0bah
		ei
		
		;;;; Check the quirks byte to see if sprites should wrap, and rewrite the routine accordingly
		dw	relocate
		lxi	h,allow_wrap_1
		lxi	d,(allow_wrap_2 - allow_wrap_1)

		lda	quirks
		ral
		dw	relocate
		jnc	no_wrap
		;; We should wrap: allow_wrap_2 must have a NOP and allow_wrap_1 must have 'mov e,a'
		mvi	m,05fh	;mov e,a
		dad	d
		mvi	m,0
		dw	relocate
		jmp	copy_high
		;; No wrap: allow_wrap_2 must have RET and allow_wrap_1 most have RNZ
no_wrap		mvi	m,0c0h	;rnz
		dad	d
		mvi	m,0c9h  ;ret
		

		
		;;;; Copy the code that's supposed to run from ALTLCD/LCD into that area
		; Some of it needs to be in a certain page for the jump tables to work,
		; and this is a lot easier than calculating jump tables on the fly,and also
		; doesn't require the binary itself to be loaded at a certain address.
copy_high	dw	relocate
		lxi	h,vm_code	; the code is at the very end of the binary
		lxi	d,altlcd	; copy it into memory starting at ALTLCD
		lxi	b,640		; max. 640 bytes
		call	memcpy
		cma
		sta	funkey		; Set the function key row to FF.
		
		;;;; Initialize the random number generator
		lxi	h,timer 	; There are, at this location, subsequently in memory:
		lxi	d,rnddat	; two timer bytes, the power down counter, and the seconds
		lxi	b,4		; That's probably good enough as a seed.
		call	memcpy
		
		;;;; Zero out the system state (registers, DT, ST, etc.) 
		lxi	h,reg_V
		mvi	b,16h
		call	bzero
		
		; Push the ISR address onto the stack and jump to the non-relocatable part
		dw	relocate
		lxi	h,isr
		push	h
		jmp	altlcd
		
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		;;;; Relocation jump table
		;;;; The relocator adjusts these addresses, and afterwards this block of memory
		;;;; is copied into a known location. This allows the high memory part of the
		;;;; program to call into the relocatable area. 
		dw	relocate
rlc_jptbl	jmp	cls
		dw	relocate
		jmp	drawsprite
		dw	relocate
		jmp	xcab_rnd
		dw	relocate
		jmp	reg_C
		dw	relocate
		jmp	reg_B
		dw	relocate
		jmp	hl_I
rlc_jptbl_sz	equ	$ - rlc_jptbl
		
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		;;;; Subroutines in relocatable area
		
		;;;; Interrupt routine (will end up in HIMEM protected area while the program runs) 
isr		push	h
		push	d
		push	b
		push	psw
		;; Check if the program is still in memory and deregister if not
		;; (the program itself does not use the LCD routines in ROM; the lowermost 
		;; LCD RAM location is set to 0 (a value it will never have) to indicate no 
		;; other program has touched it yet. Any CLS (such as on "Menu" or reset)
		;; will overwrite it with a nonzero value. 
		lda	sentinel
		ana	a
		dw	relocate
		jz	isr_run
		;; The LCD RAM has been touched - deregister myself and stop
		mvi	a,0c9h			; RET
		sta	isrvec
isrdone		pop	psw			; Restore all registers
		pop	b
		pop	d
		pop	h
		ret
		
		dw	relocate
isr_run		lxi	h,isrdone		; so we can safely 'ret' in the rest of the routine
		push	h
		lxi	h,slow_delay		; Run the VM processor at ~ "vm_speed" Hz in slow mode.
		mvi	m,(vm_speed / 256)	
		mvi	l,low counter		; VM countdown (the rest only needs to run only every 4 cycles, 256/4=64 hz)
		dcr	m
		rnz		
		mvi	m,4			; Reset counter
		mvi	a,7Fh			; Check the keyboard for function keys
		out	0B9h
		in	0E8h
		sta	funkey		
		inr	l			; Look at delay timer
		xra	a
		ora	m		
		dw	relocate
		jz	isr_st			; If nonzero, decrease by 1
		dcr	m 
isr_st		inr	l			; Look at sound timer
		xra	a
		ora	m
		dw	relocate
		jz	isr_snd_off
		dcr	m
		ret
isr_snd_off	in	0bah			; If sound timer 0, turn off the speaker
		ori	4
		out 	0bah
		ret
		
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
		
		
hex_char        ;; Get hexadecimal character under the HL pointer.
                ;; A will be set to the hex value. Carry flag will be set if invalid.
                ;; A=234 means end of file!
                mov     a,m
                sui     48      ; subtract '0' to make number
                rc              ; <'0' = error
                cpi     10      ; still >=10?
                cmc             ; if not...
                rnc             ; ...then A already has the right value.
                sui     7       ; but if so, subtract 7 to correct for distance between '9' and 'A'
                cpi     10
                rc              ; >'9', but <'A'; error.
                cpi     16      ; signal error if A>16.
                cmc
                ret

                ;; In the buffer under the HL pointer, find the first valid
                ;; hexadecimal character. Carry flag will be set if end of file.
                ;; HL will point one byte past the hexadecimal character.
		dw	relocate 
hex_ch_next     call    hex_char
                inx     h
                rnc     ; carry flag not set = OK.
                cpi     234     ; end of file?
                cmc
                rz              ; yes.
		dw	relocate 
                jmp     hex_ch_next     ;no.

                ;; Read a hexadecimal byte from two hexadecimal characters under HL.
                ;; Carry flag will be set if end of file.
		dw	relocate 
hex_byte        call    hex_ch_next
                rc
                rlc
                rlc
                rlc
                rlc
                mov     b,a
		dw	relocate 
                call    hex_ch_next
                rc
                ora     b
                ret

		;; The algorithm used here is is (almost) the "X ABC" algorithm described on:
		;; https://www.electro-tech-online.com/threads/ultra-fast-pseudorandom-number-generator-for-8-bit.124249/
		;; "Beter goed gestolen dan slecht bedacht" 
		;; The 4 bytes of state are stored starting at rnddat in the order "X C A B". 
xcab_rnd	lxi	h,rnddat
		inr	m 	; X++
		mov	a,m	; X,
		inx	h       ;
		xra	m       ; ^ C,
                inx	h	;
		xra	m	; ^ A,
		mov	m,a	; -> A
		inx	h
		add	m	; + B,
		mov	m,a	; -> B
		rar		; >>1 (close enough here, it's not crypto, besides, 'stc cmc' _removes_ randomness right?) 
		dcx	h
		xra	m	; ^ A,
		dcx	h
		add	m	; + C
		mov	m,a	; -> C
		ret
		
		;;;;; Display subroutines ;;;;;
				
		;;;; Clear the screen.
		;
		; This routine does not touch (D,E), which is important. 
cls		di			; Screen updates w/o interrupts
		xra	a		; Select at least the first 8 drivers
		cma			; (the other 2 are unused and unimportant)
		out	0b9h		
		mvi	b,3		; Four banks
clear_bank	mov	a,b		; Select bank
		rrc
		rrc
		out	0feh
		mvi	c,50 		; 50 bytes per bank
		xra	a		; Zero A.
clear_byte	call	drvwait		; Wait for drivers to be ready
		out	0ffh		; Send a zero
		dcr	c		; Bank done yet?
		dw	relocate
		jnz	clear_byte	
		dcr	b		; Driver done yet?
		dw	relocate
		jp	clear_bank
		ei
		ret

		;;;; XOR the sprite under HL onto the screen, starting at (D,E), for B bytes.
		;
		; (D,E) are Chip-8 pixels. The registers are saved except for A. 
		; VF is set accordingly to the Chip-8 standard. 
		;
drawsprite 	xra	a		; Clear VF (drawbyte will set it if it needs to)
		sta	reg_VF
		ora	b		; If B=0, do nothing
		rz
		
		di			; Turn off interrupts and store the registers 
		push	h
		push	d
		push	b
		
		mov	a,d		; Starting pixel coordinates wrap around 
		ani	63	
		mov	d,a
		mov	a,e
		ani	31
		mov	e,a
		
		in	0bah		; Deselect the last 2 drivers 
		ani	252
		out	0bah
		
draw_loop	push 	b
		push	d
		push 	h
		dw	relocate
		call	drawbyte
		pop	h
		pop	d
		pop	b
		
		inx	h		; Next byte
		inr	e		; Goes onto next line 
		dcr	b 
		dw	relocate
		jnz	draw_loop
		
		jmp	isr_exit + 1	; Handy ROM routine that restores registers and reenables interrupts. 
		

		;;;; XOR the byte under HL onto the screen as (D,E), where (D,E) are Chip-8 coordinates.
		;
		; Chip-8 pixels are 2x2 LCD pixels in size. 
		;
		; Destroys all registers, and sets VF if a bit was cleared. 
		;
drawbyte	;; check if E is within bounds
		mvi	a,31
		ana	e
		cmp	e
allow_wrap_1	rnz			; This is rewritten to be "mov e,a" if pixel wrapping is turned on

		push	h		; we will need it later
		lxi	b,1980h		; B = driver width in Chip-8 coords, C = driver selector.
		
drv_sel_loop	;; Select horizontal driver and adjust D to be offset into it
		mov	a,c
		rlc
		mov	c,a 
		mov	a,d
		sub	b
		mov	d,a
		dw	relocate
		jnc	drv_sel_loop
		add	b
		mov	d,a		
		;; Move to bottom driver if pixel in bottom half of screen, adjust E to be offset
drv_vertical	mvi	a,15 		; 0..15 = top, 16..31 = bottom
		ana	e
		cmp	e
		mov	e,a
		dw	relocate
		jz	drv_control
		mov	a,c		; The bottom driver is 5 drivers onwards from the top one
		rrc
		rrc
		rrc
		mov	c,a
		
		;; Construct the control byte, which is BBPPPPP0, where B is the bank
		;; and P is the horizontal coordinate of the Chip-8 pixel.
drv_control	mov	a,e 		; Select the right bank. There are four Chip-8 pixels in each bank. 
		ani	00001100b
		rlc			; Rotate it almost into place
		rlc 
		rlc
		add	d		; Add the horizontal Chip-8 coordinate
		rlc			; One final rotate puts the bank bits in the right place, and
					; multiplies the Chip-8 coordinate by two to generate the LCD coordinate.
		mov	b,a		; B is the control byte.
		
		; Get the pixel mask, depending on the last 2 bytes of e. 
		mvi	a,00000011b
		ana	e
		mov	e,a
		mvi	a,11000000b
drv_pixmask	rlc
		rlc
		dcr	e
		dw	relocate
		jp	drv_pixmask
		mov	e,a

		; Set D to be the remaining amount of pixels in the driver, 
		; in case the sprite crosses a driver boundary.
		mvi	a,19h
		sub	d
		mov	d,a 
		
		; Retrieve the byte to draw
		pop	h
		mov	l,m		; the byte is stored in L. 
		
		
check_bounds	; If we're out of bounds, stop.
		mov	a,c
		ani 	10000100b	; are we on the driver that has pixel (63.Y) in it?
		dw	relocate
		jz	draw_bit
		mov	a,b
		ani	00111111b	; are we about to draw on pixel 28? (50 + 50 + 28 = 128)	
		xri	28	
		dw	relocate
		jnz	draw_bit	
		
allow_wrap_2	ret			; a NOP is written here if wrapping is turned on 
		mov	a,c		; Select the driver that's 2 bits to the right of the current one
		rrc
		rrc
		mov	c,a
		mov	a,b
		ani	11000000b	; And start at the first pixel in it (but keep the bank) 
		mov	b,a 
		
		
draw_bit	xra 	a		; mov a,l while setting flags
		ora	l
		rz			; If the bit is empty, stop. 
		ral			; The pixels are stored high-to-low
		mov	l,a		; the carry flag now contains the bit, and L has gained the 0 that was in the carry flag
		dw	relocate
		jnc 	advance		; since it's XOR, unset bits do nothing. 
		
		;; Flip the current pixel 
		push	h 
		push	d		; We need to reuse register E as well as the memory pointer.
		mov	a,c 
		out	0b9h		; Select the right driver, 
		mvi	e,1		; read one byte...
		lxi	h,lcdbuf
		call	lcdread
		dcx	h
		mov	a,m		; get it in A
		pop	d		; restore the pixel mask 
		xra	e		; XOR the byte with the pixel mask
		mov	m,a		; prepare two of them in the buffer
		inx	h
		mov	m,a
		dcx	h
		push	d		; we need to use E again for lcdwrite
		mvi	e,2
		call	lcdwrite
		pop	d 
		
		
		;; If this has resulted in turning the pixel off, we need to set VF
		;; If NOT ((new byte) AND (pixel mask)), then this is true
		dcx	h
		mov	a,m
		ana	e
		pop	h		; restore L (which holds our byte) 
		dw	relocate
		jnz	advance
		; set VF
		mvi	a,1
		sta	reg_VF	

advance		;; increment the control byte twice to tell the driver to look at the next pixel
		inr	b
		inr	b
		
		dcr	d		; have we crossed a driver boundary? 
		dw	relocate
		jnz	check_bounds	; if not, draw the next pixel 
		mov	a,c		; if yes, advance to the next driver...
		rlc
		mov	c,a
		mov	a,b		; clear the address part of the control byte...
		ani	11000000b	; (we're at pixel 0 of the next driver, obviously)
		mov	b,a
		dw	relocate
		jmp	check_bounds	; and only _then_ draw the next pixel. 
		
		
font            ;; Packed font data. 
		;; Each group of five nybbles is a hexdigit, in VM memory they should occupy five bytes each
		;; with the data in the high nybble. 
                db 0F9h,099h,0F2h,062h,027h ; 0 1
                db 0F1h,0F8h,0FFh,01Fh,01Fh ; 2 3
                db 099h,0F1h,01Fh,08Fh,01Fh ; 4 5
                db 0F8h,0F9h,0FFh,012h,044h ; 6 7
                db 0F9h,0F9h,0FFh,09Fh,01Fh ; 8 9
                db 0F9h,0F9h,09Eh,09Eh,09Eh ; A B
                db 0F8h,088h,0FEh,099h,09Eh ; C D
                db 0F8h,0F8h,0FFh,08Fh,088h ; E F
		
		
		
		
relocsize	equ	$-program		; Size of relocatable part of program. 
vm_code		; The binary for the ALTLCD part is appended.

