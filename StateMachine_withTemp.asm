;VERSION 1: Implemented UI(Includes picking soak/reflow temp/time, make sure the states are automated)
;VERSION 1.1: Added off switch(SWA.0), Counter which counts from runtime of automated states
;VERSION 1.2: Changed the counter so it doesnt show ugly zeroes. YUCK
;VERSION 2.0: FINALLY GOT THE SHIT TO STORE INTO EACH TIME/TEMP
;VERSION 2.1: IMPLEMENTED BUZZER (ports 0.0, 0.1, 0.6) need to change later

;--------------------------------------------------------------------------------------------------
;GUIDE: SWA.0 used to select changing soak/reflow stuff
;		SWA.1 used to stop everything
;		KEY.1, KEY.2, KEY.3, used for various things like changing values, selection on UI, ect.
;--------------------------------------------------------------------------------------------------

$MODDE2
org 0000H
   	ljmp STATEZERO
org 000BH
	ljmp ISR_Timer0
org 001BH
	ljmp ISR_Timer1
   
;PUT DOWN EQUATIONS/CONSTANTS HERE
CLK 		   EQU 33333333 
FREQ_0 		   EQU 2000
FREQ           EQU 100
TIMER0_RELOAD  EQU 65536-(CLK/(12*2*FREQ_0))
TIMER1_RELOAD  EQU 65538-(CLK/(12*FREQ))
BAUD   		   EQU 115200
T2LOAD 		   EQU 65536-(CLK/(32*BAUD))

MISO   EQU  P0.0 
MOSI   EQU  P0.1 
SCLK   EQU  P0.2
CE_ADC EQU  P0.3

;---------------------------;
;---------------------------;
	DSEG at 30H
pwm:        ds 4
state:      ds 1
seconds:    ds 1
sec:        ds 4
minutes:    ds 1
z:          ds 1
soaktemp:   ds 2
soaktime:   ds 2
reflowtemp: ds 2
reflowtime: ds 2
HSB:		ds 1
MSB:		ds 1
LSB:		ds 1
x:			ds 4
y:			ds 4	
bcd:		ds 5
store:		ds 4 
ref_temp: 	ds 4
bcd_ref:	ds 4
op:     	ds 1
test:       ds 1
tot_avg:  	ds 16
;---------------------------;
;---------------------------;
	BSEG
mf:		  dbit 1
is_neg:	  dbit 1
STime:    dbit 1
STemp:    dbit 1
RTime:    dbit 1
RTemp:    dbit 1
Counter:  dbit 1

;---------------------------;
;---------------------------;
	CSEG
	
$include(math32.asm)
$include(LCD_Display.asm)

myLUT:
    DB 0C0H, 0F9H, 0A4H, 0B0H, 099H
    DB 092H, 082H, 0F8H, 080H, 090H
    DB 0FFH ; All segments off
  
ISR_timer0:
	cpl P3.4
    mov TH0, #high(TIMER0_RELOAD)
    mov TL0, #low(TIMER0_RELOAD)
	reti
	  
ISR_Timer1:
	mov TH1, #high(TIMER1_RELOAD) ;reloading the timer value
	mov TL1, #low(TIMER1_RELOAD)
	
	push psw
	push acc
	push dph
	push dpl
Count:
	inc z
	mov a, z
	cjne A, #100, ISR_Timer1_L0
	mov z, #0
	
	mov a, seconds
	add a, #1
	da a
	mov seconds, a
	cjne A, #60H, ISR_Timer1_L0
	mov seconds, #0
	
	mov a, minutes
	add a, #1
	da a
	mov minutes, a
	cjne A, #60H, ISR_Timer1_L0
	mov minutes, #0
ISR_Timer1_L0:
	mov dptr, #myLUT
	
	mov a, seconds
	anl a, #0fH
	movc a, @a+dptr
	mov HEX4, a
	mov a, seconds
	swap a
	anl a, #0fH
	movc a, @a+dptr
	mov HEX5, a

	mov a, minutes
	anl a, #0fH
	movc a, @a+dptr
	mov HEX6, a
	mov a, minutes
	swap a
	anl a, #0fH
	movc a, @a+dptr
	mov HEX7, a
ISR_Timer1_L1:
	; Restore used registers
	pop dpl
	pop dph
	pop acc
	pop psw    
	reti
	
Wait40us:
	mov R4, #149
X1: 
	nop
	nop
	nop
	nop
	nop
	nop
	djnz R4, X1 ; 9 machine cycles-> 9*30ns*149=40us
    ret

LCD_command:
	mov	LCD_DATA, A
	clr	LCD_RS
	nop
	nop
	setb LCD_EN ; Enable pulse should be at least 230 ns
	nop
	nop
	nop
	nop
	nop
	nop
	clr	LCD_EN
	ljmp Wait40us

LCD_put:
	mov	LCD_DATA, A
	setb LCD_RS
	nop
	nop
	setb LCD_EN ; Enable pulse should be at least 230 ns
	nop
	nop
	nop
	nop
	nop
	nop
	clr	LCD_EN
	ljmp Wait40us

HideTimeDisplays:
	mov a, #0ffh
	mov HEX4, a
	mov HEX5, a
	mov HEX6, a
	mov HEX7, a
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
	push acc
	
	mov b, #1 ; read channel 1
	lcall Read_ADC_Channel
	
	mov x+0, R6
	mov x+1, R7
	mov x+2, #0
	mov x+3, #0
	
	load_y(500)
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

	mov bcd+3, #0
	mov bcd+2, #0
	mov bcd+1, #0
	mov bcd+0, #0
	
	pop acc
	pop AR7
	pop AR6
	pop psw
	ret

StateZero:
	clr STime
	clr STemp
	clr RTime
	clr RTemp
	mov SP, #7FH
	mov LEDRA, #0
	mov LEDG, #0
	mov LEDRC, #0
	mov LEDRB, #0

	orl P0MOD, #10011010b ; make all CEs outputs
	mov P3MOD, #00110000B
	
	mov seconds, #00H
	mov minutes, #00H
	
	clr A
	mov bcd+0, A
	mov bcd+1, A
	mov bcd+2, A
	mov bcd+3, A
	mov bcd+4, A
	mov bcd+5, A
	
	setb CE_ADC

	mov state, #0
	
	; Turn LCD on, and wait a bit.
    setb LCD_ON
    clr LCD_EN  ; Default state of enable must be zero
    lcall Wait40us
    
    mov LCD_MOD, #0xff ; Use LCD_DATA as output port
    clr LCD_RW ;  Only writing to the LCD in this code.
	
	mov a, #0ch ; Display on command
	lcall LCD_command
	mov a, #38H ; 8-bits interface, 2 lines, 5x7 characters
	lcall LCD_command
	mov a, #01H ; Clear screen (Warning, very slow command!)
	lcall LCD_command
    
    ; Delay loop needed for 'clear screen' command above (1.6ms at least!)
    mov R5, #40
	
	mov a, #0FFH
	mov HEX0, a
	mov HEX1, a
	mov HEX2, a
	mov HEX3, a
	mov SoakTemp, #0
	mov SoakTime, #0
	mov ReflowTemp, #0
	mov ReflowTime, #0
	
	lcall HideTimeDisplays
	lcall INITIALIZER
	;clear other things here
	sjmp INTERFACE

INITIALIZER:
	lcall TIMERONE_INIT
	lcall INIT_SPI
	lcall InitSerialPort
	ret
	
TIMERONE_INIT:
	mov TMOD, #00010001B ; 16-bit timer
	clr TR0
	clr TF0
    mov TH0, #high(TIMER0_RELOAD)
    mov TL0, #low(TIMER0_RELOAD)
    setb ET0 ; Enable timer 0 interrupt
	clr TR1 ; Disable timer 1
	clr TF1
    mov TH1, #high(TIMER1_RELOAD)
    mov TL1, #low(TIMER1_RELOAD)
    setb ET1 ; Enable timer 1 interrupt
    setb EA
    ret
    
INTERFACE:
;	mov a, #01H ; Clear screen (Warning, very slow command!)
	clr TR1
;	lcall LCD_command
;	lcall LCD_OvenController
	lcall ReadRef
	jb SWA.1, StateZeroExtend
	jb SWA.0, SelectStates
	jb SWA.3, DisplayTestExtend
	jb SWA.4, TestSoakTime
	jb SWA.5, TestSoakTemp
	jb SWA.6, TestReflowTime
	jb SWA.7, TestReflowTemp

	lcall Wait50ms
	jnb KEY.1, CheckModeSet
	ljmp INTERFACE
	
TestSoakTime:
	mov LEDG, SoakTime+0
	mov LEDRA, SoakTime+1
	ljmp INTERFACE
TestSoakTemp:
	mov LEDG, SoakTemp+0
	mov LEDRA, SoakTemp+1
	ljmp INTERFACE
TestReflowTime:
	mov LEDG, ReflowTime+0
	mov LEDRA, ReflowTime+1
	ljmp INTERFACE
TestReflowTemp:
	mov LEDG, ReflowTemp+0
	mov LEDRA, ReflowTemp+1
	ljmp INTERFACE
	
StateZeroExtend:
	ljmp StateZero
	
DisplayTestExtend:
	ljmp DisplayTest
	
CheckModeSet:
	mov state, #1
	mov seconds, #00H
	mov minutes, #00H
	setb TR1
	ljmp READYSETGO
		
;SelectStates - Select modifying the soaktime/temp or reflow time/temp
;TODO: make LCD describe what selection screen youre on ect.
SelectStates:
	lcall LCD_SelectState
	jnb KEY.3, SoakMode
	lcall Wait50ms
	jnb KEY.2, ReflowMode
	lcall Wait50ms
	sjmp SelectStates
SoakMode:
	lcall LCD_SelectTimeTemp
	lcall WaitHalfSec
	jnb KEY.1, SetSoakTemp
	lcall Wait50ms
	jnb KEY.2, SetSoakTime
	sjmp SoakMode
ReflowMode:
	lcall LCD_SelectTimeTemp
	lcall WaitHalfSec
	jnb KEY.1, SetReflowTemp
	lcall Wait50ms
	jnb KEY.3, SetReflowTime
	sjmp ReflowMode
SetSoakTemp:
	setb STemp
	lcall LCD_SoakTemp
	ljmp Select
StoreSoakTemp:
	mov SoakTemp+0, store+0
	mov SoakTemp+1, store+1
	clr STemp
	ljmp INTERFACE
SetSoakTime:
	setb STime
	lcall LCD_SoakTime
	ljmp Select
StoreSoakTime:
	mov SoakTime+0, store+0
	mov SoakTime+1, store+1
	clr STime
	jnb SWA.0, INTERFACE_EXTEND
	sjmp SetSoakTime
SetReflowTemp:
	setb RTemp
	lcall LCD_ReflowTemp
	ljmp Select
StoreReflowTemp:
	mov ReflowTemp+0, store+0
	mov ReflowTemp+1, store+1
	clr RTemp
	jnb SWA.0, INTERFACE_EXTEND
	sjmp SetReflowTemp
SetReflowTime:
	setb RTime
	lcall LCD_ReflowTime
	ljmp Select
StoreReflowTime:
	mov ReflowTime+0, store+0
	mov ReflowTime+1, store+1
	clr RTime
	jnb SWA.0, INTERFACE_EXTEND
	sjmp SetReflowTime

INTERFACE_EXTEND:
	ljmp INTERFACE
	
READYSETGO:
	mov a, state
	ljmp StateOne
	
StateOne:
	;lcall LCD_RampToSoak
	jb SWA.1, ExtensionToStateZero
	cjne a, #1, StateTwo
;	setb P0.7
;	lcall ReadTemp ;read the value, which is stored in x
;	lcall Beep
	mov state, #2
StateOne_Done:
	ljmp READYSETGO

StateTwo:
	jb SWA.1, ExtensionToStateZero
	cjne a, #2, StateThree
	setb LEDG.1
	lcall Beep
	mov state, #3
	;check if temp is higher than the original
StateTwo_Done:
	ljmp READYSETGO

StateThree:
	;lcall LCD_RampToPeak
	jb SWA.1, ExtensionToStateZero
	cjne a, #3, StateFour
	;insert pwm parameter here
	;do some stuff here
	lcall WaitHalfSec
	lcall WaitHalfSec
	setb LEDG.2
	lcall Beep
	mov state, #4
StateThree_Done:
	ljmp READYSETGO
	
StateFour:
	jb SWA.1, ExtensionToStateZero
	cjne a, #4, StateFive
	;insert pwm parameter here
	;do some stuff here
	lcall WaitHalfSec
	lcall WaitHalfSec
	setb LEDG.3
	lcall Beep
	mov state, #5
StateFour_Done:
	ljmp READYSETGO
	
StateFive:
	jb SWA.1, ExtensionToStateZero
	cjne a, #5, Done
	;insert pwm parameter here
	;do some stuff here
	lcall WaitHalfSec
	lcall WaitHalfSec
	setb LEDG.4
	lcall Beep
	mov state, #6
StateFive_Done:
	ljmp DONE

ExtensionToStateZero:
	ljmp StateZero
	
DONE:
	clr TR1
	ljmp INTERFACE

Beep:
	setb TR0
	setb P3.5
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	clr TR0
	clr P3.5
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	setb TR0
	setb P3.5
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	clr TR0
	clr P3.5
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	setb TR0
	setb P3.5
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	lcall Wait50ms
	clr TR0
	clr P3.5
	ret
	
Wait50ms:
;33.33MHz, 1 clk per cycle: 0.03us
	mov R0, #30
K3: mov R1, #74
K2: mov R2, #250
K1: djnz R2, K1 ;3*250*0.03us=22.5us
    djnz R1, K2 ;74*22.5us=1.665ms
    djnz R0, K3 ;1.665ms*30=50ms
    ret
    
WaitHalfSec:
	mov R3, #90
L7: mov R4, #250
L6: mov R5, #250
L5: djnz R5, L5 ;3 machine cycles -> 3*30ns * 250 = 22.5
	djnz R4, L6 ;22.5us * 250 = 5.625ms
	djnz R3, L7 ; 5.625ms * 90 = ~0.5s
	ret
	
DisplayTest:
	mov dptr, #myLut
	mov a, store+0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX4, a
	
	mov a, store+0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX5, a
	
	mov a, store+1
	anl a, #0FH
	movc a, @a+dptr
	mov HEX6, a
	ljmp INTERFACE
	
Select:
	lcall Wait50ms
	lcall Wait50ms
Display:
	mov dptr, #myLut
	mov a, LSB
	anl a, #0FH
	movc a, @a+dptr
	mov HEX4, a
	
	mov a, MSB
	anl a, #0FH
	movc a, @a+dptr
	mov HEX5, a
	
	mov a, HSB
	anl a, #0FH
	movc a, @a+dptr
	mov HEX6, a
	jb SWA.0, Count1
StoreValue:
	clr a
	mov a, HSB
	anl a, #0FH
	mov store+1, a
	clr a
	mov a, MSB
	swap a
	anl a, #0f0H
	mov R0, a
	mov a, LSB
	anl a, #0fH
	orl a, R0
	mov store+0, a
ResetThings:
	mov LSB, #0
	mov MSB, #0
	mov HSB, #0
	mov HEX7, #0ffh
	mov HEX6, #0ffh
	mov HEX5, #0ffh
	mov HEX4, #0ffh
	jb STime, StoreSoakTime_E
	jb STemp, StoreSoakTemp_E
	jb RTime, StoreReflowTime_E
	jb RTemp, StoreReflowTemp_E
	
Count1:
	jb KEY.3, Count2
	jnb KEY.3, $
	mov a, HSB
	add a, #1
	lcall Compare
	da a
	mov HSB, a
	lcall Display
	
Count2:
	jb KEY.2, Count3
	jnb KEY.2, $
	mov a, MSB
	add a, #1
	lcall Compare
	da a
	mov MSB, a
	lcall Display

Count3:
	jb KEY.1, SelectExtend
	jnb KEY.1, $
	mov a, LSB
	add a, #1
	lcall Compare
	da a
	mov LSB, a
	ljmp Select
	
SelectExtend:
	ljmp Select
	
Compare:
	cjne a, #10H, Return ;if it's not 10 then it will return to count
	mov a, #0H
	ret
	
Return:
	ret

StoreSoakTime_E:
	ljmp StoreSoakTime
StoreSoakTemp_E:
	ljmp StoreSoakTemp
StoreReflowTime_E:
	ljmp StoreReflowTime
StoreReflowTemp_E:
	ljmp StoreReflowTemp
	
ReadTemp:
	clr is_neg
	clr mf
	
	lcall readRef; Get reference temp and store in 'ref_temp' 4-byte register
	
	mov b, #0 ; read channel 0
	lcall Read_ADC_Channel
	
	mov x+0, R6
	mov x+1, R7
	mov x+2, #0
	mov x+3, #0
	load_y(3125)
	lcall mul32	
	load_y(10496)
	lcall div32

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
	clr P3.7
	sjmp continue
ontag:
	setb P3.7
continue:	
	lcall hex2bcd
	lcall DisplayTemp
  	lcall send_voltage
   	lcall delay100us
   	ljmp ReadTemp

DisplayTemp:
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
    
        ; Display Digit 1
    mov A, bcd+4
    swap a
    anl a, #0fh
    movc A, @A+dptr
    mov HEX6, A
  	; Display Digit 1
    mov A, bcd+4
    anl a, #0fh
    movc A, @A+dptr
    mov HEX7, A
    ret
    
END