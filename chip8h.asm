
;; RAM locations
altlcd		equ	0fcc0h

;; Variables used by the program itself
vm_mem_start	equ	0ff46h	; Start of VM memory

		org	altlcd			; Non-relocatable part that runs from ALTLCD.

		; As a test, output the file as ASCII
		lhld	vm_mem_start
		inr	h
		inr	h
loop		xra	a
		ora	m
		rst	4 
		inx	h
		jnz	loop
stop		jmp	stop
