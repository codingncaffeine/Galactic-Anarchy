; Spoken warnings: 4-bit samples played through the SID's volume register. The samples
; are the disk's GA SPEECH file (assets/ga-speech.prg, made by tools/speech.sh), loaded
; at start-up into the bitmap of buffer 1 and copied to the RAM under the I/O chips at
; $D000. Without the file (the program run on its own) the game is simply silent here.
; Playing takes the whole processor for about half a second, so it only happens as a
; sector starts, before its music: "warning" for the Dreadnought, "shields low" when
; two blocks or fewer are left, "jump" for the first sector of a game.
; For the 8580, whose volume register alone is nearly silent, the three voices are held
; at a steady level (test bit, pulse, gate, sustain 15) that the volume then scales.

SPEAK_WARNING   = 0                     ; the order of tools/speech.sh
SPEAK_SHIELDS   = 1
SPEAK_JUMP      = 2
SPEECH_RAM      = $D000
WAIT_HIGH       = 37                    ; delay loops for 5,000 samples a second (PAL)
WAIT_LOW        = 26

        .segment "BSS"
speech_ok:      .res 1
sp_len:         .res 2

        .segment "RODATA"
fname_speech:   .byte "GA SPEECH"
FNAME_SPEECH_LEN = * - fname_speech
        .segment "CODE"

; speech_boot: at start-up, after the high scores: the samples from the disk, if there.
speech_boot:
        lda     #0
        sta     speech_ok
        jsr     disk_begin
        lda     #1
        ldx     #8
        ldy     #0                      ; to the address given here
        jsr     KERNAL_SETLFS
        lda     #FNAME_SPEECH_LEN
        ldx     #<fname_speech
        ldy     #>fname_speech
        jsr     KERNAL_SETNAM
        lda     #0
        ldx     #<(BUF1_BITMAP_HI*256)
        ldy     #BUF1_BITMAP_HI
        jsr     KERNAL_LOAD
        lda     #0
        rol                             ; carry set = an error
        sta     speech_ok
        jsr     disk_end
        lda     speech_ok
        eor     #1
        sta     speech_ok
        beq     @done
        sei                             ; 16 pages to under the I/O chips
        lda     #$34
        sta     CPU_PORT
        ldy     #0
        ldx     #16
@copy:  lda     BUF1_BITMAP_HI*256,y
@to:    sta     SPEECH_RAM,y
        iny
        bne     @copy
        inc     @copy+2
        inc     @to+2
        dex
        bne     @copy
        lda     #BUF1_BITMAP_HI         ; (put back for the next start)
        sta     @copy+2
        lda     #>SPEECH_RAM
        sta     @to+2
        lda     #$35
        sta     CPU_PORT
        cli
        lda     #BUF1_BITMAP_HI         ; the bitmap blank again where it was loaded
        ldx     #16                     ; (not to $FFFF: the vectors live there)
        jmp     clear_pages
@done:  rts

; sector_speech: as a sector starts (ready_start, before its music).
sector_speech:
        lda     boss_fight
        beq     :+
        lda     #SPEAK_WARNING
        bne     speak
:       lda     shield
        cmp     #3
        bcs     :+
        lda     #SPEAK_SHIELDS
        bne     speak
:       lda     sector
        cmp     #1
        bne     :+
        lda     #SPEAK_JUMP
        bne     speak
:       rts

; speak: phrase A. The raster interrupt keeps the screen split but does no game work
; meanwhile; the SID is set up afresh afterwards (the caller starts the music).
speak:
        ldx     speech_ok
        bne     :+
        rts
:       ldx     demo
        beq     :+
        rts
:       asl
        asl
        tax
        sei                             ; the phrase's start and length
        lda     #$34
        sta     CPU_PORT
        lda     SPEECH_RAM+1,x
        sta     ptr2
        lda     SPEECH_RAM+2,x
        sta     ptr2+1
        lda     SPEECH_RAM+3,x
        sta     sp_len
        lda     SPEECH_RAM+4,x
        sta     sp_len+1
        lda     #$35
        sta     CPU_PORT
        cli
        lda     game_on
        pha
        lda     #0
        sta     game_on
        ldx     #14                     ; the voices at a steady level
:       lda     #$00
        sta     SID+5,x                 ; attack 0, decay 0
        lda     #$F0
        sta     SID+6,x                 ; sustain 15, release 0
        lda     #$49
        sta     SID+4,x                 ; pulse, test bit, gate
        txa
        sec
        sbc     #7
        tax
        bpl     :-
        ldy     #0
@byte:  sei                             ; (cycle counts in WAIT_HIGH / WAIT_LOW)
        lda     #$34
        sta     CPU_PORT
        lda     (ptr2),y
        ldx     #$35
        stx     CPU_PORT
        cli
        sta     g_tmp
        lsr
        lsr
        lsr
        lsr
        sta     SID_VOLUME
        ldx     #WAIT_HIGH
:       dex
        bne     :-
        lda     g_tmp
        and     #$0F
        sta     SID_VOLUME
        ldx     #WAIT_LOW
:       dex
        bne     :-
        iny
        bne     :+
        inc     ptr2+1
:       lda     sp_len
        bne     :+
        dec     sp_len+1
:       dec     sp_len
        lda     sp_len
        ora     sp_len+1
        bne     @byte
        jsr     sound_init
        pla
        sta     game_on
        rts
