; The Dreadnought: three hull sections (slots 4-6, armoured) carrying four weak points
; (slots 0-3: two turrets on top, two engine pods at the stern). It sways across the view
; and fires often; destroy the four before its jump countdown ends. When they are gone
; the hull blows apart for a bonus; if the countdown ends, it jumps away and the shield
; takes two hits.

BOSS_Z          = 640
BOSS_TIME       = 50                    ; seconds to its jump
BOSS_PODS       = 4
BOSS_SLOTS      = 7
POD_HP          = 5
BOSS_BONUS      = 200                   ; x 10 points
DEATH_TICKS     = 90

        .segment "RODATA"
; Offsets from the ship's centre (the middle section): x, y (16 bit), for slots 0-6.
boss_off_x_lo:  .byte <-200, <60, <380, <380,  <-240, 0, <240
boss_off_x_hi:  .byte >-200, >60, >380, >380,  >-240, 0, >240
boss_off_y_lo:  .byte <40, <82, <26, <-26,  0, 0, 0
boss_off_y_hi:  .byte >40, >82, >26, >-26,  0, 0, 0
boss_model:     .byte MODEL_POD, MODEL_POD, MODEL_POD, MODEL_POD
                .byte MODEL_DREAD_BOW, MODEL_DREAD_MID, MODEL_DREAD_STERN
txt_jump:       scr "DREADNOUGHT   JUMP IN"
                .byte 0
txt_jumped:     scr "THE DREADNOUGHT JUMPED AWAY"
                .byte 0
txt_wrecked:    scr "DREADNOUGHT DESTROYED"
                .byte 0

        .segment "CODE"

boss_start:
        lda     #1
        sta     boss_fight
        jmp     ready_start             ; the usual pause first, then boss_begin

; boss_begin: called when the pause ends.
boss_begin:
        lda     #STATE_BOSS
        sta     state
        jsr     clear_slots
        lda     #BOSS_SLOTS
        sta     obj_count
        lda     #0
        sta     boss_x
        sta     boss_x+1
        sta     boss_phase
        sta     boss_dying
        lda     #BOSS_TIME
        sta     boss_secs
        lda     #50
        sta     boss_sub
        ldx     #BOSS_SLOTS-1
:       lda     boss_model,x
        sta     obj_model,x
        lda     #1
        sta     obj_active,x
        lda     #0
        sta     obj_yaw,x
        sta     obj_roll,x
        sta     obj_dyaw,x
        sta     obj_dpitch,x
        sta     obj_droll,x
        lda     #12                     ; seen a little from above
        sta     obj_pitch,x
        lda     #K_POD
        cpx     #BOSS_PODS
        bcc     :+
        lda     #K_HULL
:       sta     en_kind,x
        tay
        lda     kind_hp,y
        sta     en_hp,x
        dex
        bpl     :--
        jsr     build_edges
        jsr     boss_place
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 6, txt_jump
        jmp     boss_show_time

; boss_place: every part at the ship's position plus its offset.
boss_place:
        ldx     #BOSS_SLOTS-1
@p:     lda     boss_x
        clc
        adc     boss_off_x_lo,x
        sta     obj_x_lo,x
        lda     boss_x+1
        adc     boss_off_x_hi,x
        sta     obj_x_hi,x
        lda     boss_y
        clc
        adc     boss_off_y_lo,x
        sta     obj_y_lo,x
        lda     boss_y+1
        adc     boss_off_y_hi,x
        sta     obj_y_hi,x
        lda     #<BOSS_Z                ; weak points sit a little nearer: hit first
        cpx     #BOSS_PODS
        bcs     :+
        lda     #<(BOSS_Z-30)
:       sta     obj_z_lo,x
        lda     #>BOSS_Z
        sta     obj_z_hi,x
        dex
        bpl     @p
        rts

boss_tick:
.ifdef TEST_PLAY
        jsr     test_autoplay
.endif
        lda     #6
        jsr     stars_tick
        inc     boss_phase              ; sway: x follows a slow sine, +-127 units
        lda     boss_phase
        lsr
        tax
        lda     sine,x
        sta     boss_x
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       sty     boss_x+1
        lda     sine+64,x               ; and bobs a little
        cmp     #$80
        ror
        cmp     #$80
        ror
        sta     boss_y
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       sty     boss_y+1
        jsr     boss_place
        jsr     bolts_tick
        jsr     bursts_tick
        jsr     laser_tick
        lda     boss_dying
        beq     :+
        jmp     boss_death
:       jsr     player_fire
        ldx     #BOSS_PODS-1            ; the weak points fire
@fire:  lda     obj_active,x
        beq     @nofire
        jsr     rand
        cmp     #3
        bcs     @nofire
        jsr     bolt_spawn
@nofire:
        dex
        bpl     @fire
        lda     shield
        bne     :+
        jmp     over_start
:       ldx     #BOSS_PODS-1            ; all weak points gone?
:       lda     obj_active,x
        bne     @alive
        dex
        bpl     :-
        lda     #DEATH_TICKS
        sta     boss_dying
        lda     #BOSS_BONUS
        jsr     add_score_x10
        lda     #1
        sta     panel_dirty
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 9, txt_wrecked
        rts
@alive: dec     boss_sub                ; the countdown
        bne     @done
        lda     #50
        sta     boss_sub
        dec     boss_secs
        beq     @jumped
        jmp     boss_show_time
@jumped:
        jsr     player_hit
        jsr     player_hit
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 6, txt_jumped
        jsr     clear_slots
        lda     #ENEMY_SLOTS
        sta     obj_count
        lda     #0
        sta     boss_fight
        lda     shield
        bne     :+
        jmp     over_start
:       jmp     map_after_sector
@done:  rts

boss_show_time:
        set_pos PANEL_ROW+2, 28
        lda     boss_secs
        jmp     print_2digits

; boss_death: explosions along the hull, then the hull is gone and the sector is won.
boss_death:
        dec     boss_dying
        beq     @gone
        lda     boss_dying
        and     #7
        bne     @done
        ldx     #BOSS_SLOTS-1           ; a burst somewhere on a hull section
        jsr     rand
        and     #3
        cmp     #3
        bcc     :+
        lda     #1
:       clc
        adc     #BOSS_PODS
        tax
        lda     obj_bb_x0,x
        cmp     #$FF
        beq     @done
        jsr     rand
        and     #31
        clc
        adc     obj_bb_x0,x
        sta     g_tmp
        lda     obj_bb_y0,x
        clc
        adc     #6
        sta     g_tmp+1
        lda     #1
        jsr     burst_add
        jsr     sfx_explode
@done:  rts
@gone:  jsr     clear_slots
        lda     #ENEMY_SLOTS
        sta     obj_count
        lda     #0
        sta     boss_fight
        jmp     map_after_sector
