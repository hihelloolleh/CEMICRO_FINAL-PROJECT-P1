; NOTE: NOT YET FINAL. NEED TO CHECK FOR WRITE

; --------------------- REGISTER DEFINITIONS ---------------------
PROGRAM EQU  $0000
BASE    EQU  $1000
STACK   EQU  $00FF

PORTA   EQU  $00      ; 1000h
PORTC   EQU  $03      ; 1003h
PORTB   EQU  $04      ; 1004h
DDRC    EQU  $07      ; 1007h
SCSR    EQU  $2E      ; 102Eh
SCDR    EQU  $2F      ; 102Fh

; --------------------- RAM VARIABLES ---------------------
ADDR    RMB  1        ; EPROM address counter (0 → 24)
TMP     RMB  1        ; storage for EPROM read byte

; --------------------- SAMPLE DATA (25 BYTES) ---------------------
PATTERN:
        FCB  $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18

; --------------------- PROGRAM START ---------------------
        ORG  PROGRAM

START:
        SEI                     ; disable interrupts
        LDS     #STACK          ; init stack pointer
        LDX     #BASE           ; X = 1000h (I/O base)

        ; PORT SETUP
        CLR     DDRC,X          ; Port C = INPUT (for READ)
        BSET    PORTA,X $40     ; PA6 HIGH (default: disable EPROM)
        CLR     ADDR            ; start address = 0

        CLI                     ; enable interrupts again
        BRA     MAIN_LOOP

; --------------------- MAIN PROGRAM ---------------------
MAIN_LOOP:
        JSR     WRITE           ; First write 25 bytes to chip
        JSR     READ            ; Then read 25 bytes back from chip
HALT:
        SWI                     ; Stop program

; --------------------- WRITE SUBROUTINE ---------------------
WRITE:
        LDX     #BASE
        LDAB    #25             ; Write 25 bytes
        LDAA    #0              ; pattern index

WRITE_LOOP:
        ; Send address to EPROM
        PSHB
        LDAA    ADDR
        STAA    PORTB,X         ; Address bus out
        PULA

        ; PORTC = OUTPUT for data bus
        BSET    DDRC,X $FF
        LDY     #$0200

DDRC_DELAY_W:
        DEY
        BNE     DDRC_DELAY_W

        ; Output data byte
        LDAA    PATTERN,X       ; simulation (can replace with real source)
        STAA    PORTC,X

        ; Pulse PA6 : LOW → HIGH → LOW
        BCLR    PORTA,X $40     ; LOW
        LDY     #$00FF

PULSE_LO_W:
        DEY
        BNE     PULSE_LO_W
        BSET    PORTA,X $40     ; HIGH
        LDY     #$00FF

PULSE_HI_W:
        DEY
        BNE     PULSE_HI_W
        BCLR    PORTA,X $40     ; LOW again

        ; Move to next address
        PULB
        INC     ADDR
        DECB
        BNE     WRITE_LOOP

        RTS

; --------------------- READ SUBROUTINE ---------------------
READ:
        LDX     #BASE
        LDAB    #25             ; Read 25 bytes
        CLRA                    ; pattern index reset

READ_LOOP:
        ; Send address to EPROM via PORTB
        PSHB
        LDAA    ADDR
        STAA    PORTB,X         ; Address bus out
        PULA

        ; Enable EPROM output (PA6 LOW)
        BCLR    PORTA,X $40
        LDY     #$00FF

PULSE_STABLE_R:
        DEY
        BNE     PULSE_STABLE_R

        ; Configure PORTC as INPUT for data read
        CLR     DDRC,X          ; back to input

        ; Small delay to stabilize data
        LDY     #$0200

DATA_STABLE_R:
        DEY
        BNE     DATA_STABLE_R

        ; Read data byte from PORTC
        LDAA    PORTC,X         ; Data bus in
        STAA    TMP             ; Store to RAM

        ; Send byte to Serial (UART)
        JSR     SEND_SERIAL

        ; Disable EPROM output (PA6 HIGH)
        BSET    PORTA,X $40

        ; Next address
        PULB
        INC     ADDR
        DECB
        BNE     READ_LOOP

        RTS

; --------------------- SEND SERIAL SUBROUTINE ---------------------
SEND_SERIAL:
        LDX     #BASE

WAIT_TX_EMPTY:
        LDAA    SCSR,X
        ANDA    #$80            ; check TDRE bit (transmit empty)
        BEQ     WAIT_TX_EMPTY
        LDAA    TMP
        STAA    SCDR,X
        RTS
