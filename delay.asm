; --------------------- REGISTER DEFINITIONS ---------------------
PROGRAM EQU  $0000
BASE    EQU  $1000
STACK   EQU  $00FF

PORTA   EQU  $00      ; 1000h
PORTC   EQU  $03      ; 1003h
PORTB   EQU  $04      ; 1004h

DDRC    EQU  $07      ; 1007h
BAUD    EQU  $2B      ; 102Bh - Baud Rate Control
SCCR2   EQU  $2D      ; 102Dh - Serial Control Register 2
SCSR    EQU  $2E      ; 102Eh - Status
SCDR    EQU  $2F      ; 102Fh - Data

PATTERN DW  $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18

; --------------------- PROGRAM START ---------------------
        ORG  PROGRAM

START

; ------------ START HERE HEHE ------------
	; 1
	LDAA	PORTA, X
	ORAA	#%01110000	; B4(CE) = B5(P) = B6(OE) = HIGH
	STAA	PORTA, X

	JSR	DELAY_1MS

	; 2
	LDAA	PORTA, X
	ANDA	#%11101111	; B4(CE) = LOW
	STAA	PORTA, X

	JSR	DELAY_1MS

	;3
	LDAA	PORTA, X
	ANDA	#%10101111	; B4(CE) = B6(OE) = LOW
	ORAA	#%00100000	; B5(P) = HIGH
	STAA	PORTA, X

	JSR	DELAY_1MS

	; 4
	LDAA	PORTA, X
	ORAA	#%01110000	; B4(CE) = B5(P) = B6(OE) = HIGH
	STAA	PORTA, X

	JSR	DELAY_1MS
; ------------ END HERE HEHE ------------
	BRA  START
; --------------------- DELAY SUBROUTINES ---------------------
; 1ms Delay (Assuming 2MHz E-Clock)
DELAY_1MS:
        PSHX
        LDX     #$014D          ; ~333 loops
D1_LOOP: DEX
        BNE     D1_LOOP
        PULX
        RTS

; 3ms Delay (Calls 1ms x 3)
DELAY_3MS:
        JSR     DELAY_1MS
        JSR     DELAY_1MS
        JSR     DELAY_1MS
        RTS

; Startup Delay (~1 Second)
DELAY_STARTUP:
        PSHY
        LDY     #$03E8          
DS_LOOP:
        JSR     DELAY_1MS
        DEY
        BNE     DS_LOOP
        PULY
        RTS
