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

; --------------------- RAM VARIABLES ---------------------
ADDR    RMB  1        ; EPROM address counter
TMP     RMB  1        ; Storage for read byte
N_COUNT RMB  1        ; 'n' counter (1 to 25)

; --------------------- SAMPLE DATA ---------------------
PATTERN:
        FCB  $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18

; --------------------- PROGRAM START ---------------------
        ORG  PROGRAM

START:
        SEI                     ; Disable interrupts
        LDS     #STACK          ; Init stack pointer
        LDX     #BASE           ; X = 1000h

        ; --- SERIAL SETUP ---
        LDAA    #$30            ; 9600 Baud (for 8 MHz crystal)
        STAA    BAUD,X
        LDAA    #$08            ; Enable Transmitter (bit 3)
        STAA    SCCR2,X

        ; --- PORT SETUP ---
        CLR     DDRC,X          ; Port C = INPUT
        
        ; INITIAL STATE: H H H (Idle)
        ; PA6(OE)=1, PA5(P)=1, PA4(CE)=1
        ; PA3=0 (PSU Off)
        ; Binary: 0111 0000 = Hex $70
        LDAA    #$70
        STAA    PORTA,X     
        
        CLR     ADDR            
        
        JSR     DELAY_STARTUP   ; Wait for PC to connect
        CLI                     
        BRA     MAIN_LOOP

; --------------------- MAIN PROGRAM ---------------------
MAIN_LOOP:
        JSR     READ
        JSR     WRITE
        JSR     READ

END	BRA	END

; --------------------- WRITE SUBROUTINE ---------------------
WRITE:
        LDX     #BASE
        LDY     #PATTERN        
        LDAB    #25             ; Total bytes to write
        CLR     ADDR

RETRY:
        LDAA    #1
        STAA    N_COUNT		; RETRY COUNTER

        ; [PSU CONTROL] Turn on High Voltage (13V)
        ; Using PA3 ($08) now - No Config needed!
        BSET    PORTA,X $F8     

ATTEMPT_LOOP:
        ; Setup Address & Data
        PSHB                    
        LDAA    ADDR
        STAA    PORTB,X		; Address out       

        BSET    DDRC,X $FF      ; Port C -> OUTPUT
        LDAA    0,Y             
        STAA    PORTC,X		; Data out         

        ; OE(6)=H, P(5)=H, CE(4)=L
        BCLR    PORTA,X $10     ; PA4 -> LOW
        NOP

        ; OE(6)=H, P(5)=L, CE(4)=L
        ; Start Pulse
        BCLR    PORTA,X $20     ; PA5 -> LOW
        
        JSR     DELAY_1MS       ; 1ms Pulse
        
        ; OE(6)=H, P(5)=H, CE(4)=L
        ; End Pulse
        BSET    PORTA,X $20     ; PA5 -> HIGH
        NOP
        
        ; OE(6)=L, P(5)=H, CE(4)=L
        ; Switch to Input Mode first!
        CLR     DDRC,X          
        BCLR    PORTA,X $50     ; PA6 -> LOW
        
        NOP
        NOP
        
        ; READ DATA
        LDAA    PORTC,X         
        CMPA    0,Y             
        BEQ     VERIFY_PASS     

        ; -----------------------------
        ; VERIFY FAILED
        ; -----------------------------
        ; OE(6)=H, P(5)=H, CE(4)=L
        BSET    PORTA,X $40     ; PA6 -> HIGH
        
	NOP
	NOP
        
	; OE(6)=H, P(5)=H, CE(4)=H
        BSET    PORTA,X $10     ; PA4 -> HIGH (Reset)

        INC     N_COUNT         ; Increment n
        LDAA    N_COUNT
        CMPA    #25             ; Check limit
        BEQ     WRITE_FAILURE   

        BRA     ATTEMPT_LOOP    ; Retry

        ; -----------------------------
        ; VERIFY PASSED
        ; -----------------------------

VERIFY_PASS:
        ; OE(6)=H, P(5)=H, CE(4)=L
        BSET    PORTA,X $E0     ; PA6 -> HIGH
        
        ; Note: We keep CE Low ($10) because we need to pulse again!
        PULB                    

        ; OVERPROGRAM PULSE (3ms * n)
        BSET    DDRC,X $FF      ; Port C -> OUTPUT
        LDAA    0,Y
        STAA    PORTC,X

        ; OE(6)=H, P(5)=L, CE(4)=L
        BCLR    PORTA,X $20     ; PA5 -> LOW
        
        ; Wait loop: (3ms) * (n)
        
	LDAA    N_COUNT         
OVERPROG_LOOP:
        JSR     DELAY_3MS       
        DECA                    
        BNE     OVERPROG_LOOP   
        
        ; OE(6)=H, P(5)=H, CE(4)=L
        BSET    PORTA,X $20     ; PA5 -> HIGH

        ; OE(6)=H, P(5)=H, CE(4)=H
        ; Done with this byte
        BSET    PORTA,X $10     ; PA4 -> HIGH

          

        ; NEXT BYTE
        INY                     
        INC     ADDR            
        DECB                    
        BNE     RETRY 

	; [PSU CONTROL] Turn off High Voltage (5V Safe Mode)
        BCLR    PORTA,X $08   

        CLR     DDRC,X
        RTS

WRITE_FAILURE:
        BCLR    PORTA,X $08     ; Safety: Turn off HV
        PULB                    
END	BRA	END                     

; --------------------- READ SUBROUTINE ---------------------
READ:
        LDX     #BASE
        LDAB    #25             
        CLR     ADDR
READ_LOOP:
        PSHB                    
        LDAA    ADDR
        STAA    PORTB,X

        ; OE(6)=H, P(5)=H, CE(4)=H (idle)
        ; Also ensure PSU is Low (PA3=0)
        BCLR    PORTA,X $08
        BSET    PORTA,X $70     

        ; OE(6)=H, P(5)=H, CE(4)=L
        BCLR    PORTA,X $10     ; PA4 -> LOW

        ; OE(6)=L, P(5)=H, CE(4)=L
        BCLR    PORTA,X $40     ; PA6 -> LOW
        
        ; Delay for data access
        NOP
        NOP

        ; READ DATA
        CLR     DDRC,X          
        LDAA    PORTC,X         
        STAA    TMP             

        JSR     SEND_SERIAL

        ; OE(6)=H, P(5)=H, CE(4)=H
        LDAA    PORTA,X
        ORAA    #$50            ; Set Bit 6 ($40) and Bit 4 ($10)
        STAA    PORTA,X         

        PULB                    
        INC     ADDR
        DECB
        BNE     READ_LOOP
        RTS

; --------------------- SERIAL SUBROUTINE ---------------------
SEND_SERIAL:
        BRCLR   SCSR,X $80 SEND_SERIAL 	; Wait until TDRE (Transmit Data Reg Empty) bit is set
        STAA    SCDR,X          	; Send the byte in Acc A to Serial


        RTS

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
