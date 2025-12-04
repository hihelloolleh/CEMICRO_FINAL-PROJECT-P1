; NOTE: NOT YET FINAL. NEED TO CHECK FOR WRITE

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
N_COUNT RMB  1        ; 'n' counter

; --------------------- SAMPLE DATA (25 BYTES) ---------------------
PATTERN:
        FCB  $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18

; --------------------- PROGRAM START ---------------------
        ORG  PROGRAM

START:
        SEI                     ; Disable interrupts
        LDS     #STACK
        LDX     #BASE           ; X = 1000h (I/O base)

        ; --- SERIAL SETUP ---
        LDAA    #$30            ; 9600 Baud (8MHz crystal)
        STAA    BAUD,X
        LDAA    #$08            ; Enable Transmitter (TE) - bit 3
        STAA    SCCR2,X

        ; --- PORT SETUP ---
        CLR     DDRC,X          ; Port C = INPUT
        BSET    PORTA,X $60     ; PA6(P) & PA5(G) HIGH (Disable EPROM)
        
        CLR     ADDR            ; Start address = 0
        
        ; --- STARTUP DELAY ---
        ; Wait here to let the PC connect properly
        JSR     DELAY_STARTUP

        CLI                     ; Enable interrupts
        BRA     MAIN_LOOP

; --------------------- MAIN PROGRAM ---------------------
MAIN_LOOP:
        JSR     WRITE
        JSR     READ            ; Read back and send to PC
HALT:
        SWI                     ; Stop program

; --------------------- WRITE SUBROUTINE ---------------------
WRITE:
        LDX     #BASE
        LDY     #PATTERN        ; Y points to data array
        LDAB    #25             ; Total bytes to write
        CLR     ADDR

WRITE_OUTER_LOOP:
        LDAA    #1              ; n = 1
        STAA    N_COUNT

ATTEMPT_LOOP:
        ; SETUP ADDRESS & DATA
        PSHB                    ; Save Loop Counter
        LDAA    ADDR
        STAA    PORTB,X         ; Address Bus Out

        BSET    DDRC,X $FF      ; Port C -> OUTPUT
        LDAA    0,Y             ; Load Pattern Data
        STAA    PORTC,X         ; Data Bus Out

        ; CONTROL SIGNALS (Program Mode)
        ; Program Pulse: CE' - LOW, OE' - HIGH, P' - LOW
        BSET    PORTA,X $20     ; G (PA5) -> HIGH (Disable Output)
        BSET    PORTA,X $40     ; P (PA6) -> HIGH (Idle)

        ; P = 1ms Pulse
        BCLR    PORTA,X $40     ; P -> LOW (Start Pulse)
        JSR     DELAY_1MS       ; Wait 1ms
        BSET    PORTA,X $40     ; P -> HIGH (End Pulse)

        ; Verification
        CLR     DDRC,X          ; Port C -> INPUT
        BCLR    PORTA,X $20     ; G -> LOW (Enable EPROM Output)
        
        ; Small delay for signal stabilization
        NOP
        NOP
        NOP
        NOP

        LDAA    PORTC,X         ; Read Data
        CMPA    0,Y             ; Compare with Desired Pattern
        BEQ     VERIFY_PASS

        ; Verify (Failed)
        BSET    PORTA,X $20     ; G -> HIGH (Disable EPROM)
        PULB                    ; Restore Stack

        INC     N_COUNT
        
        LDAA    N_COUNT
        CMPA    #26             ; compare if  > 25?
        BEQ     WRITE_FAILURE   ; If n=26, fail
        
        BRA     ATTEMPT_LOOP    ; Loop back to Pulse again

        ; Verify (Pass)
VERIFY_PASS:
        BSET    PORTA,X $20     ; G -> HIGH
        PULB                    ; Restore Stack

        ; P = 3ms * n Pulse
        ; We must Write again to apply the "Locking" pulse
        BSET    DDRC,X $FF      ; Port C -> OUTPUT
        LDAA    0,Y
        STAA    PORTC,X

        ; Start Pulse
        BCLR    PORTA,X $40     ; P -> LOW
        
        ; Wait loop: Call 3ms delay 'N_COUNT' times
        LDAA    N_COUNT         
OVERPROG_LOOP:
        JSR     DELAY_3MS       ; Wait 3ms
        DECA                    ; Decrement 'n' copy
        BNE     OVERPROG_LOOP   ; Repeat
        
        ; End Pulse
        BSET    PORTA,X $40     ; P -> HIGH

        INY                     ; Next Data Byte
        INC     ADDR            ; Next Address
        
        DECB                    ; Decrement Total Counter
        BNE     WRITE_OUTER_LOOP ; If not done, next byte

        ; Cleanup
        CLR     DDRC,X
        RTS

WRITE_FAILURE:
        PULB                    ; Clean stack
        SWI                     ; Stop execution (Error)

; --------------------- READ SUBROUTINE ---------------------
READ:
        LDX     #BASE
        LDAB    #25             
        CLR     ADDR
READ_LOOP:
        PSHB                    
        LDAA    ADDR
        STAA    PORTB,X

        ; Signals: P=High, G=Low
        BSET    PORTA,X $40     ; PA6(P) HIGH
        BCLR    PORTA,X $20     ; PA5(G) LOW (Enable Output)
        
        ; Wait for data
        NOP
        NOP
        NOP
        NOP

        CLR     DDRC,X          
        LDAA    PORTC,X         
        STAA    TMP             

        JSR     SEND_SERIAL

        BSET    PORTA,X $20     ; G -> High

        PULB                    
        INC     ADDR
        DECB
        BNE     READ_LOOP
        RTS

; --------------------- SERIAL SUBROUTINE ---------------------
SEND_SERIAL:
        LDX     #BASE
WAIT_TX:
        LDAA    SCSR,X
        ANDA    #$80            
        BEQ     WAIT_TX         
        LDAA    TMP             
        STAA    SCDR,X          
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
        LDY     #$03E8          ; Loop 1000 times
DS_LOOP:
        JSR     DELAY_1MS
        DEY
        BNE     DS_LOOP
        PULY
        RTS
