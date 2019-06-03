		include	"constants.asm"

		org	altlcd			; Non-relocatable part that runs from ALTLCD.

		;;;; Machine initialization
		call	r_cls		; Clear the screen
		
		; As a test, try to draw the font.
		
restart		lhld	vm_mem_start
		inr	h		; Font is in page 1 of VM memory
		lxi	b,510h		; B=5 bytes, C=10h digits
		lxi	d,0		; Top left of screen
		
draw		call	drawsprite	; Draw the sprite
wait		push	b
		push	d
		push	h
		call	scan_key
		pop	h
		pop	d
		pop	b
		
		rc			; Special key = end 
		jz	wait		; No key = wait
		
		call	drawsprite	; Remove the sprite again 
		inx	h
		inx	h
		inx	h 
		inx 	h 
		inx 	h 
		
		dcr	c
		jz	restart
		jmp	draw


;;;;; Display subroutines ;;;;;

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
		ani	15
		mov	e,a
		
		in	0bah		; Deselect the last 2 drivers 
		ani	252
		out	0bah
		
draw_loop	push 	b
		push	d
		push 	h
		call	drawbyte
		pop	h
		pop	d
		pop	b
		
		inx	h		; Next byte
		inr	e		; Goes onto next line 
		dcr	b 
		jnz	draw_loop
		
		jmp	isr_exit + 1	; Handy ROM routine that restores registers and reenables interrupts. 
		

		;;;; XOR the byte under HL onto the screen as (D,E), where (D,E) are Chip-8 coordinates.
		;
		; Chip-8 pixels are 2x2 LCD pixels in size. 
		;
		; Destroys all registers, and sets VF if a bit was cleared. 
		;
drawbyte	push	h		; we will need it later
		lxi	b,1980h		; B = driver width in Chip-8 coords, C = driver selector.
		
		;; check if E is within bounds
		mvi	a,31
		ana	e
		cmp	e
		rnz
		
drv_sel_loop	;; Select horizontal driver and adjust D to be offset into it
		mov	a,c
		rlc
		mov	c,a 
		mov	a,d
		sub	b
		mov	d,a
		jnc	drv_sel_loop
		add	b
		mov	d,a		
		;; Move to bottom driver if pixel in bottom half of screen, adjust E to be offset
drv_vertical	mvi	a,15 		; 0..15 = top, 16..31 = bottom
		ana	e
		cmp	e
		mov	e,a
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
		jz	draw_bit
		mov	a,b
		ani	00111111b	; are we about to draw on pixel 28? (50 + 50 + 28 = 128)	
		xri	28	
		rz			; then stop, we shouldn't draw "offscreen" .
		
draw_bit	xra 	a		; mov a,l while setting flags
		ora	l
		rz			; If the bit is empty, stop. 
		ral			; The pixels are stored high-to-low
		mov	l,a		; the carry flag now contains the bit, and L has gained the 0 that was in the carry flag
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
		jnz	advance
		; set VF
		mvi	a,1
		sta	reg_VF	

advance		;; increment the control byte twice to tell the driver to look at the next pixel
		inr	b
		inr	b
		
		dcr	d		; have we crossed a driver boundary? 
		jnz	check_bounds	; if not, draw the next pixel 
		mov	a,c		; if yes, advance to the next driver...
		rlc
		mov	c,a
		mov	a,b		; clear the address part of the control byte...
		ani	11000000b	; (we're at pixel 0 of the next driver, obviously)
		mov	b,a
		jmp	check_bounds	; and only _then_ draw the next pixel. 