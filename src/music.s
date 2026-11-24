; The music player, stepped by the raster interrupt. Voices 1 and 2 play a track's two
; parts (music.inc from music/*.music); a track without a second part leaves voice 2 to
; the sound effects. The game asks for a track with music_play; the interrupt starts it.

        .segment "BSS"
mus_tmp:        .res 3
mus_ptr_lo:     .res 2                  ; per voice: where in its notes,
mus_ptr_hi:     .res 2
mus_start_lo:   .res 2                  ; where they start (for looping),
mus_start_hi:   .res 2
mus_dur:        .res 2                  ; frames left of the note,
mus_wave:       .res 2                  ; the waveform,
mus_on:         .res 2                  ; and whether it plays

        .segment "CODE"

; music_play: A = track. Takes effect at the next interrupt.
music_play:
        ldx     music_off
        beq     :+
        lda     #$FF                    ; music off: silence instead
        sta     mus_req
        rts
:       clc
        adc     #1
        sta     mus_req
        rts

; music_tick: in the raster interrupt.
music_tick:
        lda     mus_req
        bne     :+
        jmp     @step
:       cmp     #$FF
        bne     :+
        lda     #0                      ; stop: both voices quiet
        sta     mus_req
        sta     mus_on
        sta     mus_on+1
        lda     mus_wave
        sta     SID+4
        lda     mus_wave+1
        sta     SID+4+7
        rts
:       sec
        sbc     #1
        asl
        sta     mus_tmp                 ; track * 2: index of its voice 1
        lda     #0
        sta     mus_req
        ldx     #1
@start: txa
        clc
        adc     mus_tmp
        tay
        lda     track_lo,y
        sta     mus_ptr_lo,x
        sta     mus_start_lo,x
        lda     track_hi,y
        sta     mus_ptr_hi,x
        sta     mus_start_hi,x
        lda     track_wave,y
        sta     mus_wave,x
        sta     mus_on,x
        lda     #1
        sta     mus_dur,x
        lda     voice_reg,x
        sta     mus_tmp+1
        lda     track_wave,y            ; a part: its sound settings
        beq     :+
        stx     mus_tmp+2
        ldx     mus_tmp+1
        lda     #0
        sta     SID+4,x                 ; gate off
        lda     track_ad,y
        sta     SID+5,x
        lda     track_sr,y
        sta     SID+6,x
        lda     track_pw_lo,y
        sta     SID+2,x
        lda     track_pw_hi,y
        sta     SID+3,x
        ldx     mus_tmp+2
:       dex
        bpl     @start

@step:  ldx     #1
@voice: lda     mus_on,x
        beq     @next
        dec     mus_dur,x
        lda     mus_dur,x
        cmp     #1                      ; a frame before the next note: gate off
        bne     :+
        ldy     voice_reg,x
        lda     mus_wave,x
        sta     SID+4,y
        jmp     @next
:       cmp     #0
        bne     @next
        jsr     music_note
@next:  dex
        bpl     @voice
        rts

; music_note: voice X's next note.
music_note:
        lda     mus_ptr_lo,x
        sta     mus_p
        lda     mus_ptr_hi,x
        sta     mus_p+1
        ldy     #0
        lda     (mus_p),y
        cmp     #$FE
        bcc     @note
        bne     @loop
        lda     #0                      ; $FE: the end
        sta     mus_on,x
        ldy     voice_reg,x
        lda     mus_wave,x
        sta     SID+4,y
        rts
@loop:  lda     mus_start_lo,x          ; $FF: from the start
        sta     mus_ptr_lo,x
        lda     mus_start_hi,x
        sta     mus_ptr_hi,x
        jmp     music_note
@note:  sta     mus_tmp
        iny
        lda     (mus_p),y
        sta     mus_dur,x
        lda     mus_ptr_lo,x
        clc
        adc     #2
        sta     mus_ptr_lo,x
        bcc     :+
        inc     mus_ptr_hi,x
:       lda     mus_tmp                 ; 0 = a rest
        beq     @done
        tay
        dey
        lda     PAL_FLAG
        beq     :+
        lda     freq_pal_lo,y
        sta     mus_tmp+1
        lda     freq_pal_hi,y
        jmp     :++
:       lda     freq_ntsc_lo,y
        sta     mus_tmp+1
        lda     freq_ntsc_hi,y
:       ldy     voice_reg,x
        sta     SID+1,y
        lda     mus_tmp+1
        sta     SID+0,y
        lda     mus_wave,x              ; gate: off, then on (restarts the envelope)
        sta     SID+4,y
        ora     #1
        sta     SID+4,y
@done:  rts

        .segment "RODATA"
voice_reg:      .byte 0, 7              ; SID register offset of voices 1 and 2
        .segment "CODE"
