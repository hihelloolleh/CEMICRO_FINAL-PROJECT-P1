; HC11 Final Project Phase 1 - EPROM Reader (First 25 Bytes)
; Based on lecture hardware mapping:
; Port B -> EPROM Address (A0-A7)
; Port C -> EPROM Data (D0-D7)
; Port A -> EPROM Control (CE/OE) - Using PA6 (Bit 6) as Control

        ORG     $0000           ; RAM Start for Bootstrap Mode

BASE    EQU     $1000           ; Register Base Address
PORTA   EQU     $00             ; Port A
PORTC   EQU     $03             ; Port C
PORTB   EQU     $04             ; Port B
DDRC    EQU     $07             ; Data Direction Register C
SCSR    EQU     $2E             ; Serial Comm Status Register
SCDR    EQU     $2F             ; Serial Comm Data Register

START:
        LDS     #$00FF          ; Initialize Stack Pointer to top of RAM
        LDX     #BASE           ; Point Index Register X to Register Block

        ; 1. Configure Ports based on transcript
        CLR     DDRC,X          ; Set DDRC to 0 -> Port C becomes INPUT (Read EPROM Data)
                                ; Port B is Output-only by default (EPROM Address)
                                ; Port A Bit 6 is Output by default (Control)
        
        BSET    PORTA,X $40     ; Set PA6 HIGH (Disable EPROM Output initially)
                                ; Assuming Active Low logic for OE/CE

        CLRB                    ; Accumulator B will act as our Loop Counter & Address
                                ; (Counts 0 to 25)

READ_LOOP:
        CMPB    #25             ; Check if we have read 25 bytes
        BEQ     DONE            ; If B == 25, we are finished

        ; 2. Set Address
        STAB    PORTB,X         ; Output current count (B) to Port B (EPROM Address)

        ; 3. Control Signal (Pulse OE/CE Low)
        BCLR    PORTA,X $40     ; Clear PA6 -> Low (Enable EPROM Output)
        
        NOP                     ; Short delay for EPROM access time (tACC)
        NOP                     ; (HC11 is fast, EPROM might be slow)

        ; 4. Read Data
        LDAA    PORTC,X         ; Read EPROM data from Port C into Accumulator A

        ; 5. Disable EPROM
        BSET    PORTA,X $40     ; Set PA6 -> High (Disable EPROM Output)

        ; 6. Send Data to PC via Serial (SCI)
        ; Note: Baud rate is already set by the Bootloader process before this runs
TX_WAIT:
        BRCLR   SCSR,X $80 TX_WAIT ; Wait until TDRE (Transmit Data Reg Empty) bit is set
        STAA    SCDR,X          ; Send the byte in Acc A to Serial

        INCB                    ; Increment Loop Counter / Address
        BRA     READ_LOOP       ; Repeat

DONE:
        BRA     DONE            ; Infinite loop to stop execution