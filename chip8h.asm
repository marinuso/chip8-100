		include	"constants.asm"

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
