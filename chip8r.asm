		include	"constants.asm"

		org	orgbase		
		
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		;;;;;; Self-relocator
		
		;;; Figure out where we are
start		lxi	h,0e9e1h	; POP H / PCHL 
		shld	getPC
		call	getPC	
		lxi	b,$ - start - orgbase
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
		lxi	b,(memsize + 384)	; 128 stack bytes, 256 extra bytes for page alignment
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
		dw	relocate
hex_load_loop	call	hex_byte	; Read a byte from the hexadecimal file
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

		
		;;;; Copy the code that's supposed to run from ALTLCD/LCD into that area
		; (Some of it needs to be in a certain page for the jump tables to work,
		; and this is a lot easier than calculating jump tables on the fly,and also
		; doesn't require the binary itself to be loaded at a certain address.)
		dw	relocate
		lxi	h,vm_code	; the code is at the very end of the binary
		lxi	d,altlcd	; copy it into memory starting at ALTLCD
		lxi	b,640		; max. 640 bytes
		call	memcpy
		
		jmp	altlcd
		
		;;;;;;;;;;;;;;;;;;;;;;;;;;;;
		;;;; Subroutines in relocatable area
		
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

