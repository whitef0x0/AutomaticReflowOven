$MODDE2

org 0000H
   ljmp MyProgram

FREQ   EQU 33333333h	
BAUD   EQU 115200
T2LOAD EQU 65536-(FREQ/(32*BAUD))


MISO   EQU  P0.0 
MOSI   EQU  P0.1 
SCLK   EQU  P0.2
CE_ADC EQU  P0.3


DSEG at 30H
	x:      		ds 4
	y:      		ds 4
	ref_temp: 		ds 4
	bcd:			ds 5
	bcd_ref:		ds 4
	tot_avg:     	ds 16
	test: ds 1
	BSEG
mf:     dbit 1
is_neg: dbit 1

	CSEG


$include(math32.asm)

; Look-up table for 7-seg displays
myLUT:
    DB 0C0H, 0F9H, 0A4H, 0B0H, 099H        ; 0 TO 4
    DB 092H, 082H, 0F8H, 080H, 090H        ; 4 TO 9

Display:
	mov dptr, #myLUT
	; Display Digit 0
    mov A, bcd+0
    anl a, #0fh
    movc A, @A+dptr
    mov HEX0, A
	; Display Digit 1
    mov A, bcd+0
    swap a
    anl a, #0fh
    movc A, @A+dptr
    mov HEX1, A
  	; Display Digit 1
    mov A, bcd+1
    anl a, #0fh
    movc A, @A+dptr
    mov HEX2, A
    
    ; Display Digit 1
    mov A, bcd+3
    swap a
    anl a, #0fh
    movc A, @A+dptr
    mov HEX4, A
  	; Display Digit 1
    mov A, bcd+3
    anl a, #0fh
    movc A, @A+dptr
    mov HEX5, A
    ret

INIT_SPI:
    orl P0MOD, #01000100b ; Set SCLK, MOSI as outputs
    anl P0MOD, #11011111b ; Set MISO as input
    clr SCLK              ; For mode (0,0) SCLK is zero
	ret

DO_SPI_G:
	push acc
    mov R1, #0            ; Received byte stored in R1
    mov R2, #8            ; Loop counter (8-bits)
DO_SPI_G_LOOP:
    mov a, R0             ; Byte to write is in R0
    rlc a                 ; Carry flag has bit to write
    mov R0, a
    mov MOSI, c
    setb SCLK             ; Transmit
    mov c, MISO           ; Read received bit
    mov a, R1             ; Save received bit in R1
    rlc a
    mov R1, a
    clr SCLK
    djnz R2, DO_SPI_G_LOOP
    pop acc
    ret

Delay:
	mov R3, #20
Delay_loop:
	djnz R3, Delay_loop
	ret


; Channel to read passed in register b
Read_ADC_Channel:
	clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	
	mov a, b
	swap a
	anl a, #0F0H
	setb acc.7 ; Single mode (bit 7).
	
	mov R0, a ;  Select channel
	lcall DO_SPI_G
	mov a, R1          ; R1 contains bits 8 and 9
	anl a, #03H
	mov R7, a
	
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov a, R1    ; R1 contains bits 0 to 7
	mov R6, a
	setb CE_ADC
	ret

;For a 33.33MHz clock, one cycle takes 30ns
WaitHalfSec:
	mov R2, #90
X3: mov R1, #250
X2: mov R0, #250
X1: djnz R0, X1
	djnz R1, X2
	djnz R2, X3
	ret
	
;delay100us
delay100us:
	push AR1
	push AR0
	push AR2
L3: mov R2, #90
L2:	mov R1, #250
L1: mov R0, #250
L0: djnz R0, L0 ; 111*30ns*3=10us
	djnz R1, L1 ; 10*10us=100us, approximately
	djnz R2, L2
	pop AR2
	pop AR0
	pop AR1
	ret

	; Configure the serial port and baud rate using timer 2
InitSerialPort:
	clr TR2 ; Disable timer 2
	mov T2CON, #30H ; RCLK=1, TCLK=1 
	mov RCAP2H, #high(T2LOAD)  
	mov RCAP2L, #low(T2LOAD)
	setb TR2 ; Enable timer 2
	mov SCON, #52H
	ret

; Send a character through the serial port
putchar:
    JNB TI, putchar
    CLR TI
    MOV SBUF, a
    RET
    
send_number:
	push acc
	swap a
	anl a, #0fh
	orl a, #30h
	lcall putchar
	pop acc
	anl a, #0fh
	orl a, #30h
	lcall putchar
	ret
	
send_voltage:
	mov a, bcd+0
	lcall send_number
	mov a, bcd+1
	lcall send_number
	mov a, #'\n'
	lcall putchar
	mov a, #'\r'
	lcall putchar
	ret

readRef:
	push psw
	push AR6
	push AR7
	
	mov b, #1 ; read channel 1
	lcall Read_ADC_Channel
	
	mov x+0, R6
	mov x+1, R7
	mov x+2, #0
	mov x+3, #0
	load_y(490)
	lcall mul32
	load_y(1024)
	lcall div32
	Load_y(273)
	lcall sub32
	mov ref_temp+0, x+0
	mov ref_temp+1, x+1
	mov ref_temp+2, x+2
	mov ref_temp+3, x+3
	lcall hex2bcd
	mov bcd_ref+0, bcd+0
	mov bcd_ref+1, bcd+1
	mov bcd_ref+2, bcd+2

	
	mov bcd+2, #0
	mov bcd+1, #0
	mov bcd+0, #0
	pop AR7
	pop AR6
	pop psw	
	ret
MyProgram:
	mov sp, #07FH
	clr a
	mov LEDG,  a
	mov LEDRA, a
	mov LEDRB, a
	mov LEDRC, a

	orl P0MOD, #10011010b ; make all CEs outputs
	
	setb CE_ADC



	lcall INIT_SPI
	 LCALL InitSerialPort
Forever:
	mov bcd+5, #0
	mov bcd+4, #0
	clr is_neg
	clr mf
	
	lcall readRef
	
	;lcall readRef; Get reference temp and store in 'ref_temp' 4-byte register
	
	mov b, #0 ; read channel 0
	lcall Read_ADC_Channel
	
	mov x+1, R7
	mov x+0, R6
	mov x+2, #0
	mov x+3, #0
	load_y(3125)
	lcall mul32	
	load_y(10496)
	lcall div32

	;Load_y(47)
	;lcall mul32
	
	;Load_y(100)
	;lcall div32
	
	
;	Load_y(ref_temp)
	mov y, ref_temp
	mov y+1, ref_temp+1
	mov y+2, ref_temp+3
	mov y+3, ref_temp+4
	lcall add32
;   Test for powering the oven (using the SSC)
	mov test, #70
	clr c
	mov a, x+0
	subb a, test
	jc ontag
	clr P0.7
	sjmp continue
ontag:
	setb P0.7
;	setb P0.6
continue:	
	lcall hex2bcd
	lcall Display
	
  	lcall send_voltage
   	lcall delay100us
   	
   	sjmp Forever
   	
   	
	
END
