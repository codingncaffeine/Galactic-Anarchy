; Sound effects on the SID. The game only raises requests (snd_req); the raster interrupt
; starts and steps the effects, so the SID is written from one place.
;   voice 1: the laser, a sawtooth falling in pitch
;   voice 2: shield hits and damage, a low pulse
;   voice 3: explosions, noise with a long decay

SID             = $D400
SID_VOLUME      = $D418

REQ_LASER       = $01
REQ_EXPLODE     = $02
REQ_HIT         = $04
REQ_SHIELD      = $08

        .segment "ZEROPAGE"
snd_req:        .res 1
laser_snd:      .res 1                  ; frames of the laser sweep left
laser_freq:     .res 1                  ; its pitch, high byte
v2_gate:        .res 1                  ; frames until voice 2's gate goes off
v3_gate:        .res 1

        .segment "CODE"

sound_init:
        ldx     #$18
        lda     #0
:       sta     SID,x
        dex
        bpl     :-
        sta     snd_req
        sta     laser_snd
        sta     v2_gate
        sta     v3_gate
        lda     #$0F                    ; full volume, no filter
        sta     SID_VOLUME
        lda     #$08                    ; pulse width 50% for voice 2
        sta     SID+$0A
        lda     #$09                    ; voice 1: fast attack, short decay
        sta     SID+$05
        lda     #$00
        sta     SID+$06
        lda     #$0A                    ; voice 2: attack 0, decay 10
        sta     SID+$0C
        lda     #$00
        sta     SID+$0D
        lda     #$0C                    ; voice 3: attack 0, long decay, release 10
        sta     SID+$13
        lda     #$0A
        sta     SID+$14
        rts

sfx_laser:
        lda     #REQ_LASER
        bne     sfx_request
sfx_explode:
        lda     #REQ_EXPLODE
        bne     sfx_request
sfx_hit:
        lda     #REQ_HIT
        bne     sfx_request
sfx_shield:
        lda     #REQ_SHIELD
sfx_request:
        php                             ; the interrupt clears snd_req: no interrupt
        sei                             ; between reading and writing it
        ora     snd_req
        sta     snd_req
        plp
        rts

; sfx_tick: in the raster interrupt.
sfx_tick:
        lda     snd_req
        beq     @step
        lsr                             ; laser
        bcc     :+
        pha
        lda     #$40
        sta     laser_freq
        lda     #8
        sta     laser_snd
        lda     #$20                    ; gate off, then on: restart the envelope
        sta     SID+$04
        lda     #$21
        sta     SID+$04
        pla
:       lsr                             ; explosion
        bcc     :+
        pha
        lda     #$06
        sta     SID+$0F
        lda     #$80
        sta     SID+$12
        lda     #$81
        sta     SID+$12
        lda     #3
        sta     v3_gate
        pla
:       lsr                             ; an enemy hit but not destroyed
        bcc     :+
        pha
        lda     #$18
        sta     SID+$08
        lda     #$40
        sta     SID+$0B
        lda     #$41
        sta     SID+$0B
        lda     #3
        sta     v2_gate
        pla
:       lsr                             ; the player's shield hit
        bcc     :+
        lda     #$05
        sta     SID+$08
        lda     #$40
        sta     SID+$0B
        lda     #$41
        sta     SID+$0B
        lda     #10
        sta     v2_gate
:       lda     #0
        sta     snd_req

@step:  lda     laser_snd               ; the laser falls in pitch
        beq     :+
        dec     laser_snd
        lda     laser_freq
        sta     SID+$01
        sec
        sbc     #5
        sta     laser_freq
        lda     laser_snd
        bne     :+
        lda     #$20
        sta     SID+$04
:       lda     v2_gate
        beq     :+
        dec     v2_gate
        bne     :+
        lda     #$40
        sta     SID+$0B
:       lda     v3_gate
        beq     :+
        dec     v3_gate
        bne     :+
        lda     #$80
        sta     SID+$12
:       rts
