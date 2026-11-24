; The other kinds of sector:
;   Ring Run (a derelict station): rings come at you; keep the crosshair inside a ring as
;     it passes to thread it. Missed rings cost a shield block, shots pass through them,
;     mines float between them, and the reactor gives you RING_TIME seconds to thread the
;     sector's quota.
;   Convoy: freighters cross the view side-on among the faction's fighters; each takes
;     several hits and scores well. Taken as a raid, that is all.
;   Escort (a convoy taken the other way, MIS_ESCORT): the same freighters, but every
;     fighter belongs to the convoy faction's hotter rival and keeps shooting at them.
;     The kill quota wins the contract (the convoy's faction cools by ESCORT_THANKS);
;     each freighter that gets across scores ESCORT_BONUS * 10; ESCORT_LOSS freighters
;     lost (to the attackers or to the player's own guns) lose it (the faction heats by
;     ESCORT_BLAME) and end the sector.

MIS_FIGHT       = 0
MIS_CONVOY      = 1
MIS_RING        = 2
MIS_ESCORT      = 3
RING_TIME       = 45
ESCORT_LOSS     = 3
ESCORT_BONUS    = 50
ESCORT_THANKS   = 20
ESCORT_BLAME    = 10
ESCORT_DUEL     = 50                    ; ticks between attacks on the freighters

        .segment "BSS"
mission:        .res 1
ring_secs:      .res 1
ring_sub:       .res 1
ring_allow:     .res 1
rings_threaded: .res 1                  ; for tests
conv_side:      .res 1                  ; the map's choice for a convoy: 0 raid, 1 escort
esc_foe:        .res 1                  ; an escort's attackers' faction
conv_safe:      .res 1
conv_lost:      .res 1

        .segment "RODATA"
txt_reactor:    scr "REACTOR BLOWS IN"
                .byte 0
txt_blew:       scr "THE REACTOR BLEW"
                .byte 0
txt_escort:     scr "ESCORT  SAFE 00  LOST 00"
                .byte 0
txt_lost:       scr "THE CONVOY IS LOST"
                .byte 0
        .segment "CODE"

; mission_start: from ready_start, after the usual settings.
mission_start:
        lda     mission
        cmp     #MIS_ESCORT
        bne     :+
        lda     #0
        sta     conv_safe
        sta     conv_lost
        jsr     pick_rival              ; the attackers: the hotter rival
        lda     heat_rival
        sta     esc_foe
        rts
:       cmp     #MIS_RING
        bne     @done
        lda     danger                  ; quota: 5 + danger / 2, up to 12
        lsr
        clc
        adc     #5
        cmp     #13
        bcc     :+
        lda     #12
:       sta     quota
        lda     #RING_TIME
        sta     ring_secs
        lda     #50
        sta     ring_sub
@done:  rts

; mission_spawn: carry clear when it placed this arrival itself (X = the slot).
mission_spawn:
        lda     mission
        cmp     #MIS_RING
        beq     ring_spawn
        cmp     #MIS_CONVOY             ; a convoy, raided or escorted
        beq     :+
        cmp     #MIS_ESCORT
        bne     @no
:       jsr     rand                    ; a convoy: a third of the arrivals are freighters
        cmp     #85
        bcc     convoy_spawn
@no:    sec
        rts

ring_spawn:
        jsr     free_slot
        bcs     @full
        jsr     rand                    ; mostly rings, now and then a mine
        and     #3
        beq     :+
        lda     #K_GATE
        bne     :++
:       lda     #K_MINE
:       jsr     setup_kind
        jsr     rand                    ; x: -254..254
        jsr     signed_x2
        sta     obj_x_lo,x
        tya
        sta     obj_x_hi,x
        jsr     rand                    ; y: -128..127
        sta     obj_y_lo,x
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       tya
        sta     obj_y_hi,x
        lda     #<2900
        sta     obj_z_lo,x
        lda     #>2900
        sta     obj_z_hi,x
        lda     speed
        eor     #$FF
        clc
        adc     #1
        sta     en_dz,x
        lda     #0
        sta     en_dx,x
        sta     en_dy,x
        sta     en_side,x
        sta     obj_yaw,x               ; the ring faces the player, turning slowly
        lda     #2
        sta     obj_droll,x
        clc
        rts
@full:  sec
        rts

convoy_spawn:
        jsr     free_slot
        bcs     @full
        lda     #K_FREIGHTER
        jsr     setup_kind
        lda     #<-1100                 ; from the left, side-on
        sta     obj_x_lo,x
        lda     #>-1100
        sta     obj_x_hi,x
        jsr     rand
        sta     obj_y_lo,x
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       tya
        sta     obj_y_hi,x
        jsr     rand                    ; z: 1000-1510
        sta     obj_z_lo,x
        lda     #0
        asl     obj_z_lo,x
        rol
        sta     obj_z_hi,x
        lda     obj_z_lo,x
        clc
        adc     #<1000
        sta     obj_z_lo,x
        lda     obj_z_hi,x
        adc     #>1000
        sta     obj_z_hi,x
        lda     #7
        sta     en_dx,x
        lda     #0
        sta     en_dy,x
        sta     en_dz,x
        sta     en_side,x
        lda     #64                     ; nose to the right
        sta     obj_yaw,x
        clc
        rts
@full:  sec
        rts

; signed_x2: A = signed byte -> A/Y = A * 2 (signed 16 bit). Keeps X.
signed_x2:
        ldy     #0
        cmp     #$80
        bcc     :+
        ldy     #$FF
:       sty     t5_hi
        asl
        rol     t5_hi
        ldy     t5_hi
        rts

; gate_pass: slot X, a ring, has reached the player: threaded if the crosshair is inside
; its middle (3/8 of its box's width from the centre each way), else a shield block lost.
gate_pass:
        lda     #0
        sta     obj_active,x
        stx     g_off
        lda     obj_x_lo,x              ; the ring's true centre on screen (off screen:
        sta     wx                      ; the player cannot be inside it)
        lda     obj_x_hi,x
        sta     wx+1
        lda     obj_y_lo,x
        sta     wy
        lda     obj_y_hi,x
        sta     wy+1
        lda     obj_z_lo,x
        sta     wz
        lda     obj_z_hi,x
        sta     wz+1
        jsr     project_point
        ldx     g_off
        bcs     @miss
        ldy     #84                     ; the allowance: the inner radius at that distance
        jsr     mul_r
        sta     ring_allow
        lda     px
        sta     g_tmp
        lda     py
        sta     g_tmp+1
        lda     g_tmp                   ; |cross_x - centre x|
        sec
        sbc     cross_x
        bcs     :+
        eor     #$FF
        adc     #1
:       cmp     ring_allow
        bcs     @miss
        lda     g_tmp+1
        sec
        sbc     cross_y
        bcs     :+
        eor     #$FF
        adc     #1
:       cmp     ring_allow
        bcs     @miss
        inc     kills                   ; threaded
        inc     rings_threaded
        lda     #10
        jsr     add_score_x10
        lda     #1
        sta     panel_dirty
        jsr     sfx_hit
        lda     events
        ora     #4
        sta     events
        rts
@miss:  jmp     player_hit

; ring_tick: in a Ring Run, the reactor's countdown; in an escort, the losses. Carry set
; when it ran out or the convoy is lost (the sector is over).
ring_tick:
        lda     mission
        cmp     #MIS_ESCORT
        bne     @ring
        lda     conv_lost
        cmp     #ESCORT_LOSS
        bcc     @ok
        ldx     faction                 ; lost: the convoy's faction blames the player
        lda     heat,x
        clc
        adc     #ESCORT_BLAME
        cmp     #HEAT_MAX+1
        bcc     @blame
        lda     #HEAT_MAX
@blame: sta     heat,x
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 11, txt_lost
        sec
        rts
@ring:  cmp     #MIS_RING
        bne     @ok
        dec     ring_sub
        bne     @ok
        lda     #50
        sta     ring_sub
        dec     ring_secs
        beq     @blew
        set_pos PANEL_ROW+2, 28
        lda     ring_secs
        jsr     print_2digits
@ok:    clc
        rts
@blew:  jsr     player_hit
        jsr     player_hit
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 12, txt_blew
        sec
        rts

; escort_won: the quota met in an escort: the convoy's faction cools.
escort_won:
        lda     mission
        cmp     #MIS_ESCORT
        bne     :++
        ldx     faction
        lda     heat,x
        sec
        sbc     #ESCORT_THANKS
        bcs     :+
        lda     #0
:       sta     heat,x
:       rts

; escort_count: the freighters safe and lost on the panel.
escort_count:
        set_pos PANEL_ROW+2, 21
        lda     conv_safe
        jsr     print_2digits
        set_pos PANEL_ROW+2, 30
        lda     conv_lost
        jmp     print_2digits

; ring_panel: the countdown's label (or an escort's count), when the sector starts.
ring_panel:
        lda     mission
        cmp     #MIS_ESCORT
        bne     :+
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 8, txt_escort
        rts
:       cmp     #MIS_RING
        bne     :+
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 11, txt_reactor
        set_pos PANEL_ROW+2, 28
        lda     ring_secs
        jmp     print_2digits
:       rts
