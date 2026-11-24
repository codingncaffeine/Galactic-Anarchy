; Galactic Anarchy: start-up.
;
; Takes over the machine from BASIC: interrupts off, KERNAL and BASIC ROMs banked out,
; CIA interrupts silenced, and a raster interrupt of our own that counts frames.
; For now it shows the title as text; the vector engine replaces this screen in phase 1.
;
; Build options (ca65 -D):
;   TEST=1    after 50 frames counted by the raster interrupt, writes 0 to $D7FF, the
;             debug-cartridge port Kernal64's k64run reads as the test result.
;   NO_IRQ=1  never starts the raster interrupt (the control: the TEST build must then
;             time out instead of passing).

        .include "hw.inc"

        .segment "LOADADDR"
        .word   $0801

        .segment "EXEHDR"
; 10 SYS 2061
        .word   @next
        .word   10
        .byte   $9E, "2061", 0
@next:  .word   0

        .segment "ZEROPAGE"
frame_count:    .res 1

        .segment "CODE"
start:
        sei
        cld
        ldx     #$FF
        txs

        lda     #$35                    ; RAM everywhere except I/O at $D000
        sta     CPU_PORT

        lda     #$7F                    ; silence both CIAs' interrupts
        sta     CIA1_ICR
        sta     CIA2_ICR
        lda     CIA1_ICR                ; and acknowledge any already pending
        lda     CIA2_ICR

        lda     #COLOR_BLACK
        sta     VIC_BORDER
        sta     VIC_BG0

        jsr     clear_screen
        jsr     show_title

        lda     #0
        sta     frame_count

.ifndef NO_IRQ
        lda     #<raster_irq            ; with the KERNAL banked out, the CPU takes
        sta     IRQ_VECTOR              ; its interrupt vector from RAM at $FFFE
        lda     #>raster_irq
        sta     IRQ_VECTOR+1
        lda     #<nmi_ignore
        sta     NMI_VECTOR
        lda     #>nmi_ignore
        sta     NMI_VECTOR+1

        lda     #RASTER_IRQ_LINE
        sta     VIC_RASTER
        lda     VIC_CTRL1
        and     #$7F                    ; raster compare bit 8 = 0
        sta     VIC_CTRL1
        lda     #$01                    ; raster interrupt on
        sta     VIC_IRQ_MASK
        sta     VIC_IRQ_FLAGS           ; acknowledge a stale one
        cli
.endif

main_loop:
.ifdef TEST
        lda     frame_count
        cmp     #50
        bcc     main_loop
        lda     #0
        sta     DEBUGCART_RESULT
.endif
        jmp     main_loop

; -----------------------------------------------------------------------------
raster_irq:
        pha
        inc     frame_count
        lda     #$01
        sta     VIC_IRQ_FLAGS           ; acknowledge
        pla
nmi_ignore:
        rti

; -----------------------------------------------------------------------------
clear_screen:
        ldx     #0
@loop:  lda     #$20                    ; screen code of a space
        sta     SCREEN,x
        sta     SCREEN+$100,x
        sta     SCREEN+$200,x
        sta     SCREEN+$2E8,x
        lda     #COLOR_CYAN
        sta     COLOR_RAM,x
        sta     COLOR_RAM+$100,x
        sta     COLOR_RAM+$200,x
        sta     COLOR_RAM+$2E8,x
        inx
        bne     @loop
        rts

show_title:
        ldx     #title_len-1
@loop:  lda     title,x
        sta     SCREEN + 12*40 + (40-title_len)/2,x
        dex
        bpl     @loop
        rts

        .segment "RODATA"
; Screen codes of the uppercase character set: letters $01-$1A, space and digits as ASCII.
.define TITLE_TEXT "GALACTIC ANARCHY"
title:
        .repeat .strlen(TITLE_TEXT), i
        .byte   .strat(TITLE_TEXT, i) & $3F
        .endrep
title_len = * - title
