; The game: title, sector intro, play and game over, on the vector engine.
;
; Every drawn frame runs the current state's tick once per video frame that passed since
; the last drawn frame (so the game moves at the same speed whatever the frame rate),
; then draws the objects, the stars, explosions and lasers into the back buffer.
; The crosshair is sprite 0, moved by the raster interrupt at 50 Hz (60 on NTSC); enemy
; shots are sprites 1-3.

ENEMY_SLOTS     = 6
STAR_COUNT      = 16
BOLT_COUNT      = 3
BURST_COUNT     = 4
BURST_AGE       = 12
SHIELD_FULL     = 6
FIRE_REPEAT     = 10                    ; ticks between shots while fire is held
LASER_TICKS     = 3
READY_TICKS     = 120
OVER_TICKS      = 200

STATE_TITLE     = 0
STATE_READY     = 1
STATE_PLAY      = 2
STATE_OVER      = 3
STATE_MAP       = 4
STATE_BOSS      = 5
STATE_NAME      = 6
TITLE_SHIP      = 400                   ; ticks of the turning ship, then of the table
TITLE_TABLE     = 300

; Kinds of enemy: model, hit points, score / 10, flags, weave mask, how it turns.
KF_FIRES        = $01                   ; flags
KF_SPLITS       = $02                   ; breaks into the next kind (rocks)
KF_ARMOR        = $04                   ; shots do it no harm (the Dreadnought's hull)
TURN_BANK       = 0                     ; faces the player, banks as it weaves
TURN_WOBBLE     = 1                     ; faces the player, sways
TURN_TUMBLE     = 2                     ; tumbles

K_LANCER  = 0
K_RAIDER  = 1
K_GUNSHIP = 2
K_MAULER  = 3
K_SKITTER = 4
K_HORNET  = 5
K_MOTH    = 6
K_MANTIS  = 7
K_HIVE    = 8
K_MINE    = 9
K_ROCK_L  = 10
K_ROCK_M  = 11
K_ROCK_S  = 12
K_POD     = 13
K_HULL    = 14

        .segment "RODATA"
kind_model:     .byte MODEL_LANCER, MODEL_RAIDER, MODEL_GUNSHIP, MODEL_MAULER
                .byte MODEL_SKITTER, MODEL_HORNET, MODEL_MOTH, MODEL_MANTIS
                .byte MODEL_HIVE, MODEL_MINE, MODEL_ROCK_L, MODEL_ROCK_M, MODEL_ROCK_S
                .byte MODEL_POD, MODEL_DREAD_MID
kind_hp:        .byte 1, 1, 3, 2,  1, 1, 1, 2,  4, 1, 2, 1, 1,  POD_HP, 255
kind_score:     .byte 10, 15, 30, 25,  12, 15, 10, 20,  50, 5, 5, 3, 2,  30, 0
kind_flags:     .byte KF_FIRES, KF_FIRES, KF_FIRES, KF_FIRES
                .byte KF_FIRES, KF_FIRES, 0, KF_FIRES
                .byte 0, 0, KF_SPLITS, KF_SPLITS, 0
                .byte KF_FIRES, KF_ARMOR
kind_weave:     .byte 31, 15, 63, 63,  15, 7, 15, 31,  0, 0, 0, 0, 0,  0, 0
kind_turn:      .byte TURN_BANK, TURN_BANK, TURN_BANK, TURN_BANK
                .byte TURN_WOBBLE, TURN_WOBBLE, TURN_WOBBLE, TURN_WOBBLE
                .byte TURN_TUMBLE, TURN_TUMBLE, TURN_TUMBLE, TURN_TUMBLE, TURN_TUMBLE
                .byte TURN_TUMBLE, TURN_TUMBLE


        .segment "BSS"
cross_vis:      .res 1                  ; 1: the crosshair (sprite 0) is shown
title_phase:    .res 1                  ; 0 = the ship, 1 = the high-score table
title_t:        .res 2
en_kind:        .res ENEMY_SLOTS
en_hp:          .res ENEMY_SLOTS
en_dx:          .res ENEMY_SLOTS        ; signed, per tick
en_dy:          .res ENEMY_SLOTS
en_dz:          .res ENEMY_SLOTS
en_t:           .res ENEMY_SLOTS
star_x:         .res STAR_COUNT         ; signed, times 4 = world units
star_y:         .res STAR_COUNT
star_z_lo:      .res STAR_COUNT
star_z_hi:      .res STAR_COUNT
bolt_on:        .res BOLT_COUNT
bolt_x_lo:      .res BOLT_COUNT
bolt_x_hi:      .res BOLT_COUNT
bolt_y_lo:      .res BOLT_COUNT
bolt_y_hi:      .res BOLT_COUNT
bolt_z_lo:      .res BOLT_COUNT
bolt_z_hi:      .res BOLT_COUNT
bolt_sx:        .res BOLT_COUNT         ; last screen position ($FF = not on screen)
bolt_sy:        .res BOLT_COUNT
burst_x:        .res BURST_COUNT
burst_y:        .res BURST_COUNT
burst_t:        .res BURST_COUNT        ; 0 = free, else age + 1
burst_big:      .res BURST_COUNT

        .segment "CODE"

; =======================================================================================
game_main:
        lda     #0
        sta     $DC02                   ; port A all inputs: $DC00 reads joystick 2 alone
        sta     laser_t
        sta     fire_wait
        sta     flash_t
        sta     cross_lock
        ldx     #BURST_COUNT-1
:       sta     burst_t,x
        dex
        bpl     :-
        sta     hiscore
        sta     hiscore+1
        sta     hiscore+2
        lda     #$5A
        sta     rng
        lda     #$C3
        sta     rng+1
        lda     #VIEW_CX
        sta     cross_x
        lda     #VIEW_CY
        sta     cross_y
        jsr     sprites_init
        jsr     sound_init
.ifdef TEST_DISK
        jmp     test_disk
.endif
        jsr     hs_boot
        jsr     stars_init
        lda     #ENEMY_SLOTS
        sta     obj_count
        jsr     clear_slots
        lda     #1
        sta     game_on
        lda     frame
        sta     last_frame
.ifdef TEST_PLAY
        lda     #0
        sta     kills_total
  .ifdef TEST_BOSS
        jsr     game_new                ; straight into a Dreadnought fight
        lda     #F_BOSS
        sta     faction
        lda     #3
        sta     danger
        lda     #0
        sta     map_col
        sta     map_row
        jsr     boss_start
        lda     #99                     ; this test is about winning the fight
        sta     shield
  .else
        jsr     game_new                ; the test plays at once
  .endif
.else
        jsr     title_start
.endif

game_loop:
        jsr     begin_frame
        lda     frame                   ; video frames since the last drawn frame
        sec
        sbc     last_frame
        beq     :+
        cmp     #7
        bcc     :++
        lda     #6
        bne     :++
:       lda     #1
:       sta     ticks
        lda     frame
        sta     last_frame
@tick:  jsr     state_tick
        dec     ticks
        bne     @tick

        lda     state
        cmp     #STATE_MAP
        bne     :+
        jsr     draw_map
:       lda     state                   ; the high-score table on the title
        bne     :+
        lda     title_phase
        beq     :+
        jsr     draw_scores
:       jsr     transform_all
        jsr     draw_dots
        jsr     draw_stars
        jsr     draw_edges
        jsr     draw_bursts
        jsr     draw_laser
        jsr     place_bolts
        jsr     panel_refresh
        jsr     end_frame
        jmp     game_loop

; begin_frame: waits until the last frame is on display, then clears the back buffer.
begin_frame:
:       lda     flip_pending
        bne     :-
        ldx     back
        lda     bufhi_of,x
        sta     bufhi
        lda     dirty_off_of,x
        sta     dirty_off
        jmp     clear_back

; end_frame: shows the back buffer at the next vertical blank.
end_frame:
        ldx     back
        lda     bank_bits_of,x
        sta     flip_bits
        lda     #1
        sta     flip_pending
        txa
        eor     #1
        sta     back
        rts

; JMP (g_tmp) reads both bytes from one page: g_tmp must not be at $FF.
        .assert <g_tmp <> $FF, error, "g_tmp at $FF"

state_tick:
        ldx     state
        lda     state_lo,x
        sta     g_tmp
        lda     state_hi,x
        sta     g_tmp+1
        jmp     (g_tmp)

        .segment "RODATA"
state_lo:       .byte <title_tick, <ready_tick, <play_tick, <over_tick, <map_tick, <boss_tick, <name_tick
state_hi:       .byte >title_tick, >ready_tick, >play_tick, >over_tick, >map_tick, >boss_tick, >name_tick
        .segment "CODE"

; rand: A = a pseudo-random byte (16-bit Galois LFSR). Keeps X and Y.
rand:
        lsr     rng+1
        ror     rng
        bcc     :+
        lda     rng+1
        eor     #$B4
        sta     rng+1
:       lda     rng
        rts

; =======================================================================================
; Title: a ship turning, the starfield, the name and the high score.
title_start:
        lda     #STATE_TITLE
        sta     state
        jsr     clear_slots
        jsr     bolts_clear
        lda     #MODEL_LANCER           ; slot 0: a lancer turning in the middle
        sta     obj_model
        lda     #1
        sta     obj_active
        lda     #0
        sta     obj_x_lo
        sta     obj_x_hi
        sta     obj_y_lo
        sta     obj_y_hi
        sta     obj_roll
        lda     #<420
        sta     obj_z_lo
        lda     #>420
        sta     obj_z_hi
        lda     #20
        sta     obj_pitch
        jsr     build_edges
        lda     #COLOR_WHITE<<4
        jsr     view_color
        lda     #0
        sta     cross_lock
        lda     #TRACK_TITLE
        jsr     music_play
        lda     #0
        sta     title_phase
        sta     cross_vis               ; no crosshair on the title
        lda     #<TITLE_SHIP
        sta     title_t
        lda     #>TITLE_SHIP
        sta     title_t+1
        jsr     panel_clear
        print_at PANEL_ROW+1, 12, txt_title
        print_at PANEL_ROW+2, 10, txt_press
        print_at PANEL_ROW+3, 12, txt_high
        set_pos PANEL_ROW+3, 18          ; the top of the table
        lda     hs_table+3
        sta     num
        lda     hs_table+4
        sta     num+1
        lda     hs_table+5
        sta     num+2
        jsr     to_decimal
        lda     #6
        jsr     put_digits
        lda     #0
        sta     fire_new
        rts

; title_scores: the title, starting with the high-score table.
title_scores:
        jsr     title_start
        jmp     title_flip

title_tick:
        lda     title_t                 ; ship and table take turns
        bne     :+
        lda     title_t+1
        bne     :++
        jsr     title_flip
        jmp     :+++
:       dec     title_t
        jmp     :++
:       dec     title_t+1
        dec     title_t
:       lda     #6
        jsr     stars_tick
        inc     obj_yaw
        lda     fire_new
        beq     :+
        lda     #0
        sta     fire_new
        jmp     game_new
:       rts

; =======================================================================================
game_new:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     sector                  ; sectors flown
        lda     #SHIELD_FULL
        sta     shield
        jsr     panel_clear
        print_at PANEL_ROW+1, 1, txt_score
        print_at PANEL_ROW+3, 1, txt_kills
        lda     #0
        sta     map_loop
        lda     #1
        sta     cross_vis
        jsr     map_new
        jmp     map_start

; The sector's settings from its danger and faction, then a pause with its number shown.
;   quota 6 + 2 * danger (up to 20), on screen 2 + danger / 2 (up to 6), closing speed
;   14 + 2 * danger (up to 40), firing 2 + danger (up to 16), arrivals every
;   64 - 4 * danger ticks (down to 24).
ready_start:
        lda     #STATE_READY
        sta     state
        lda     #READY_TICKS
        sta     state_timer
        jsr     clear_slots
        jsr     bolts_clear
        lda     #0
        sta     kills
        inc     sector
        lda     danger
        cmp     #7
        bcc     :+
        lda     #7
:       asl
        adc     #6
        sta     quota
        lda     danger
        lsr
        clc
        adc     #2
        cmp     #ENEMY_SLOTS+1
        bcc     :+
        lda     #ENEMY_SLOTS
:       sta     active_max
        lda     danger
        cmp     #13
        bcc     :+
        lda     #13
:       asl
        adc     #14
        sta     speed
        lda     danger
        clc
        adc     #2
        cmp     #17
        bcc     :+
        lda     #16
:       sta     fire_rate
        lda     danger
        cmp     #10
        bcc     :+
        lda     #10
:       asl
        asl
        eor     #$FF
        sec
        adc     #64
        sta     spawn_delay
        lda     #TRACK_FIGHT
        ldx     boss_fight
        beq     :+
        lda     #TRACK_BOSS
:       jsr     music_play
        ldx     faction                 ; the viewport in the faction's colour
        lda     faction_color,x
        jsr     view_color
        lda     #1
        sta     panel_dirty
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 15, txt_sector
        set_pos PANEL_ROW+2, 22
        lda     sector
        jsr     print_2digits
        rts

ready_tick:
        lda     speed
        jsr     stars_tick
        jsr     bursts_tick
        dec     state_timer
        bne     :+
        lda     boss_fight
        beq     @play
        jmp     boss_begin
@play:  lda     #STATE_PLAY
        sta     state
        lda     #20
        sta     spawn_t
        print_at PANEL_ROW+2, 1, txt_blank
:       rts

; =======================================================================================
play_tick:
.ifdef TEST_PLAY
        jsr     test_autoplay
.endif
        lda     speed
        jsr     stars_tick
        jsr     enemies_tick
        jsr     bolts_tick
        jsr     bursts_tick
        lda     laser_t
        beq     :+
        dec     laser_t
:       jsr     player_fire
        lda     shield                  ; out of shields: game over
        bne     :+
        jmp     over_start
:       lda     kills                   ; quota reached: back to the map
        cmp     quota
        bcc     :+
        jmp     map_after_sector
:       rts

; player_fire: a new press fires at once, a held button every FIRE_REPEAT ticks.
player_fire:
        lda     fire_wait
        beq     :+
        dec     fire_wait
:       lda     fire_new
        bne     @shoot
        lda     joy
        and     #JOY_FIRE
        beq     @no
        lda     fire_wait
        bne     @no
@shoot: lda     #0
        sta     fire_new
        lda     #FIRE_REPEAT
        sta     fire_wait
        lda     #LASER_TICKS
        sta     laser_t
        jsr     sfx_laser
        jsr     shoot_bolts
        jmp     shoot_enemies
@no:    rts

; shoot_enemies: the nearest enemy whose screen box (widened by 4) holds the crosshair.
shoot_enemies:
        lda     #$FF
        sta     hit_best
        sta     hit_z
        sta     hit_z+1
        ldx     obj_count
        dex
@slot:  lda     obj_active,x
        bne     :+
        jmp     @next
:       lda     obj_dot,x               ; out of range while only a dot
        beq     :+
        jmp     @next
:       lda     obj_bb_x0,x
        cmp     #$FF
        bne     :+
        jmp     @next
:       sec                             ; x0 - 4 <= cross_x (or x0 < 4)
        sbc     #4
        bcc     :+
        cmp     cross_x
        beq     :+
        bcs     @next
:       lda     obj_bb_x1,x             ; x1 + 4 >= cross_x (or past 255)
        clc
        adc     #4
        bcs     :+
        cmp     cross_x
        bcc     @next
:       lda     obj_bb_y0,x
        sec
        sbc     #4
        bcc     :+
        cmp     cross_y
        beq     :+
        bcs     @next
:       lda     obj_bb_y1,x
        clc
        adc     #4
        cmp     cross_y
        bcc     @next
        lda     obj_z_hi,x              ; the nearest so far?
        cmp     hit_z+1
        bcc     @take
        bne     @next
        lda     obj_z_lo,x
        cmp     hit_z
        bcs     @next
@take:  stx     hit_best
        lda     obj_z_lo,x
        sta     hit_z
        lda     obj_z_hi,x
        sta     hit_z+1
@next:  dex
        bpl     @slot
        ldx     hit_best
        bmi     @none
        ldy     en_kind,x               ; armour: the shot glances off
        lda     kind_flags,y
        and     #KF_ARMOR
        bne     @hurt
        dec     en_hp,x
        bne     @hurt
        jmp     destroy_enemy
@hurt:  jmp     sfx_hit
@none:  rts

; destroy_enemy: X = slot. Explosion, score, kill count; rocks split.
destroy_enemy:
        lda     obj_bb_x0,x             ; burst at the box centre
        clc
        adc     obj_bb_x1,x
        ror
        sta     g_tmp
        lda     obj_bb_y0,x
        clc
        adc     obj_bb_y1,x
        ror
        sta     g_tmp+1
        lda     obj_z_hi,x              ; near ones get the big burst
        cmp     #>800
        lda     #0
        rol
        eor     #1
        jsr     burst_add
        ldx     hit_best
        ldy     en_kind,x
        lda     kind_score,y            ; score += kind_score * 10
        jsr     add_score_x10
        inc     kills
        inc     kills_total
        lda     #1
        sta     panel_dirty
        jsr     sfx_explode
        ldx     hit_best
        lda     #0
        sta     obj_active,x
        ldy     en_kind,x
        lda     kind_flags,y
        and     #KF_SPLITS
        beq     :+
        iny                             ; rocks: two of the next size, drifting apart
        sty     g_tmp
        lda     #4
        jsr     spawn_split
        lda     #<-4
        jsr     spawn_split
:       rts

; spawn_split: a rock of kind g_tmp at slot hit_best's position, drifting A per tick in x.
spawn_split:
        pha
        jsr     free_slot
        bcs     @full
        ldy     hit_best
        lda     obj_x_lo,y
        sta     obj_x_lo,x
        lda     obj_x_hi,y
        sta     obj_x_hi,x
        lda     obj_y_lo,y
        sta     obj_y_lo,x
        lda     obj_y_hi,y
        sta     obj_y_hi,x
        lda     obj_z_lo,y
        sta     obj_z_lo,x
        lda     obj_z_hi,y
        sta     obj_z_hi,x
        lda     en_dz,y
        sta     en_dz,x
        lda     g_tmp
        jsr     setup_kind
        pla
        sta     en_dx,x
        rts
@full:  pla
        rts

; =======================================================================================
; Enemies.

clear_slots:
        ldx     #MAX_OBJECTS-1
:       lda     #0
        sta     obj_active,x
        lda     #MODEL_ROCK_S
        sta     obj_model,x
        dex
        bpl     :-
        jmp     build_edges

; free_slot: X = an empty enemy slot with carry clear, or carry set when all are busy.
free_slot:
        ldx     #ENEMY_SLOTS-1
:       lda     obj_active,x
        beq     :+
        dex
        bpl     :-
        sec
        rts
:       clc
        rts

; setup_kind: X = slot, A = kind: model, hit points, turning; the slot becomes active.
setup_kind:
        sta     en_kind,x
        tay
        lda     kind_model,y
        sta     obj_model,x
        lda     kind_hp,y
        sta     en_hp,x
        lda     #0
        sta     en_t,x
        sta     obj_dyaw,x
        sta     obj_dpitch,x
        sta     obj_droll,x
        sta     obj_roll,x
        sta     obj_pitch,x
        lda     #128                    ; facing the player
        sta     obj_yaw,x
        lda     kind_turn,y
        cmp     #TURN_TUMBLE
        bne     :+
        jsr     rand
        and     #3
        ora     #1
        sta     obj_dyaw,x
        jsr     rand
        and     #3
        sta     obj_dpitch,x
        jsr     rand
        and     #1
        sta     obj_droll,x
:       lda     #1
        sta     obj_active,x
        stx     g_tmp+1
        jsr     build_edges             ; the slot's model may have changed
        ldx     g_tmp+1
        rts

; spawn_enemy: a new arrival from the sector's pool, far ahead at a random spot.
spawn_enemy:
        jsr     free_slot
        bcs     @no
        stx     g_tmp+1
        ldy     faction
        lda     faction_pool_lo,y
        sta     ptr2
        lda     faction_pool_hi,y
        sta     ptr2+1
        jsr     rand
        and     #7
        tay
        lda     (ptr2),y
        ldx     g_tmp+1
        jsr     setup_kind
        jsr     rand                    ; x: -640..635
        jsr     times5
        sta     obj_x_lo,x
        tya
        sta     obj_x_hi,x
        jsr     rand                    ; y: -256..254 (the byte times 2)
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       sty     t5_hi
        asl
        sta     obj_y_lo,x
        rol     t5_hi
        lda     t5_hi
        sta     obj_y_hi,x
        lda     #<2900
        sta     obj_z_lo,x
        lda     #>2900
        sta     obj_z_hi,x
        jsr     rand                    ; closing speed: sector speed + 0-3
        and     #3
        clc
        adc     speed
        eor     #$FF
        clc
        adc     #1
        sta     en_dz,x
        jsr     rand                    ; drift: +-1 to 4, toward the middle
        and     #3
        clc
        adc     #1
        ldy     obj_x_hi,x
        bmi     :+
        eor     #$FF
        clc
        adc     #1
:       sta     en_dx,x
        lda     #0
        sta     en_dy,x
@no:    rts

; times5: A = signed byte -> A/Y = A * 5 (signed 16 bit, low/high). Keeps X.
times5:
        sta     t5_lo
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       sty     t5_hi
        sty     t5_acc
        asl                             ; * 4
        rol     t5_acc
        asl
        rol     t5_acc
        clc                             ; + the value
        adc     t5_lo
        pha
        lda     t5_acc
        adc     t5_hi
        tay
        pla
        rts

enemies_tick:
        dec     spawn_t
        bne     @move
        lda     spawn_delay
        sta     spawn_t
        lda     active_max              ; room for another?
        sta     g_tmp
        ldy     #0
        ldx     #ENEMY_SLOTS-1
:       lda     obj_active,x
        beq     :+
        iny
:       dex
        bpl     :--
        cpy     g_tmp
        bcs     @move
        jsr     spawn_enemy

@move:  ldx     #ENEMY_SLOTS-1
@slot:  lda     obj_active,x
        bne     :+
        jmp     @next
:       lda     en_dx,x                 ; x += dx
        jsr     add_x
        lda     en_dy,x                 ; y += dy
        jsr     add_y
        lda     en_dz,x                 ; z += dz
        ldy     #$FF
        cmp     #$80
        bcs     :+
        iny
:       clc
        adc     obj_z_lo,x
        sta     obj_z_lo,x
        tya
        adc     obj_z_hi,x
        sta     obj_z_hi,x
        lda     obj_yaw,x               ; turning
        clc
        adc     obj_dyaw,x
        sta     obj_yaw,x
        lda     obj_pitch,x
        clc
        adc     obj_dpitch,x
        sta     obj_pitch,x
        lda     obj_roll,x
        clc
        adc     obj_droll,x
        sta     obj_roll,x

        ldy     en_kind,x               ; close in: ships and insects veer off to the
        lda     kind_turn,y             ; side they are on; rocks keep coming
        cmp     #TURN_TUMBLE
        beq     @onward
        lda     obj_z_hi,x
        cmp     #3
        bcs     @onward
        lda     #6
        ldy     obj_x_hi,x
        bpl     :+
        lda     #<-6
:       sta     en_dx,x
        lda     #3
        ldy     obj_y_hi,x
        bpl     :+
        lda     #<-3
:       sta     en_dy,x
        lda     #0                      ; no more weaving
        sta     en_t,x
@onward:
        inc     en_t,x
        lda     en_t,x                  ; animated models: the next frame every 4 ticks
        and     #3
        bne     :+
        ldy     obj_model,x
        lda     model_next,y
        sta     obj_model,x
:       ldy     en_kind,x               ; weaving: dx flips every (mask + 1) ticks
        lda     obj_z_hi,x              ; (not once veering off)
        cmp     #3
        bcc     @noweave
        lda     kind_weave,y
        beq     @noweave
        and     en_t,x
        bne     @noweave
        lda     en_dx,x
        eor     #$FF
        clc
        adc     #1
        sta     en_dx,x
        lda     kind_turn,y             ; jets bank into the turn, insects sway
        cmp     #TURN_TUMBLE
        beq     @noweave
        lda     en_dx,x
        bmi     :+
        lda     #<-18
        bne     :++
:       lda     #18
:       sta     obj_roll,x
@noweave:
        lda     kind_flags,y            ; firing, from mid range
        and     #KF_FIRES
        beq     @nofire
        lda     obj_z_hi,x
        cmp     #2
        bcc     @nofire
        cmp     #6
        bcs     @nofire
        jsr     rand
        cmp     fire_rate
        bcs     @nofire
        jsr     bolt_spawn
@nofire:
        lda     obj_z_hi,x              ; past the player?
        bmi     @gone
        bne     @next
        lda     obj_z_lo,x
        cmp     #200
        bcs     @next
@gone:  lda     #0
        sta     obj_active,x
        lda     obj_x_hi,x              ; on a collision course: the shield takes it
        jsr     near_centre
        bcs     @next
        lda     obj_y_hi,x
        jsr     near_centre
        bcs     @next
        jsr     player_hit
@next:  dex
        bmi     :+
        jmp     @slot
:       rts

; near_centre: A = high byte of a coordinate. Carry clear when it is within -256..255.
near_centre:
        cmp     #0
        beq     :+
        cmp     #$FF
        beq     :+
        sec
        rts
:       clc
        rts

; add_x / add_y: obj_x/obj_y of slot X += the signed byte A.
add_x:
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       clc
        adc     obj_x_lo,x
        sta     obj_x_lo,x
        tya
        adc     obj_x_hi,x
        sta     obj_x_hi,x
        rts
add_y:
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       clc
        adc     obj_y_lo,x
        sta     obj_y_lo,x
        tya
        adc     obj_y_hi,x
        sta     obj_y_hi,x
        rts

player_hit:
        lda     shield
        beq     :+
        dec     shield
:       lda     #1
        sta     panel_dirty
        lda     #COLOR_WHITE            ; a flash of the border
        sta     VIC_BORDER
        lda     #6
        sta     flash_t
        jmp     sfx_shield

; =======================================================================================
; Enemy shots: they home on the player; shot down they are worth a little.

bolts_clear:
        lda     #0
        ldx     #BOLT_COUNT-1
:       sta     bolt_on,x
        dex
        bpl     :-
        rts

; bolt_spawn: from slot X's position, if a bolt is free. Keeps X.
bolt_spawn:
        ldy     #BOLT_COUNT-1
:       lda     bolt_on,y
        beq     :+
        dey
        bpl     :-
        rts
:       lda     #1
        sta     bolt_on,y
        lda     obj_x_lo,x
        sta     bolt_x_lo,y
        lda     obj_x_hi,x
        sta     bolt_x_hi,y
        lda     obj_y_lo,x
        sta     bolt_y_lo,y
        lda     obj_y_hi,x
        sta     bolt_y_hi,y
        lda     obj_z_lo,x
        sta     bolt_z_lo,y
        lda     obj_z_hi,x
        sta     bolt_z_hi,y
        rts

bolts_tick:
        ldx     #BOLT_COUNT-1
@b:     lda     bolt_on,x
        beq     @next
        lda     bolt_z_lo,x             ; z -= 28
        sec
        sbc     #28
        sta     bolt_z_lo,x
        bcs     :+
        dec     bolt_z_hi,x
:       lda     bolt_x_lo,x             ; x -= x / 16 (toward the player)
        sta     g_tmp
        lda     bolt_x_hi,x
        sta     g_tmp+1
        jsr     shift16_4
        lda     bolt_x_lo,x
        sec
        sbc     g_tmp
        sta     bolt_x_lo,x
        lda     bolt_x_hi,x
        sbc     g_tmp+1
        sta     bolt_x_hi,x
        lda     bolt_y_lo,x             ; y -= y / 16
        sta     g_tmp
        lda     bolt_y_hi,x
        sta     g_tmp+1
        jsr     shift16_4
        lda     bolt_y_lo,x
        sec
        sbc     g_tmp
        sta     bolt_y_lo,x
        lda     bolt_y_hi,x
        sbc     g_tmp+1
        sta     bolt_y_hi,x
        lda     bolt_z_hi,x             ; reached the player
        bne     @next
        lda     bolt_z_lo,x
        cmp     #160
        bcs     @next
        lda     #0
        sta     bolt_on,x
        txa
        pha
        jsr     player_hit
        pla
        tax
@next:  dex
        bpl     @b
        rts

; shift16_4: g_tmp (16 bit, signed) >>= 4, arithmetic. Keeps X and Y.
shift16_4:
        .repeat 4
        lda     g_tmp+1
        cmp     #$80
        ror     g_tmp+1
        ror     g_tmp
        .endrep
        rts

; place_bolts: sprites 1-3 follow the bolts; small far away, large and then doubled near.
place_bolts:
        lda     #0
        sta     g_on
        sta     g_big
        ldx     #BOLT_COUNT-1
@b:     lda     #$FF
        sta     bolt_sx,x
        lda     bolt_on,x
        bne     :+
        jmp     @next
:       lda     bolt_x_lo,x
        sta     wx
        lda     bolt_x_hi,x
        sta     wx+1
        lda     bolt_y_lo,x
        sta     wy
        lda     bolt_y_hi,x
        sta     wy+1
        lda     bolt_z_lo,x
        sta     wz
        lda     bolt_z_hi,x
        sta     wz+1
        stx     g_tmp
        jsr     project_point
        ldx     g_tmp
        bcs     @next
        lda     px
        sta     bolt_sx,x
        lda     py
        sta     bolt_sy,x
        sta     g_spy
        inx                             ; sprite = bolt + 1
        txa
        tay
        lda     px
        jsr     sprite_set
        ldx     g_tmp
        lda     g_on
        ora     sprite_bit+1,x
        sta     g_on
        lda     bolt_z_hi,x             ; the picture: small far away, large near
        cmp     #>700
        lda     #SPRITE_BOLT_SMALL
        bcs     :+
        lda     #SPRITE_BOLT_BIG
:       ldy     g_tmp
        iny
        jsr     sprite_frame
        ldx     g_tmp
        lda     bolt_z_hi,x             ; doubled when close
        cmp     #>350
        bcs     @next
        lda     g_big
        ora     sprite_bit+1,x
        sta     g_big
@next:  dex
        bmi     :+
        jmp     @b
:       lda     g_on                    ; hand the set to the interrupt in one go
        sta     spr_on
        lda     g_big
        sta     spr_big
        rts

; shoot_bolts: a bolt within 8 pixels of the crosshair is shot down.
shoot_bolts:
        ldx     #BOLT_COUNT-1
@b:     lda     bolt_on,x
        beq     @next
        lda     bolt_sx,x
        cmp     #$FF
        beq     @next
        sec
        sbc     cross_x
        bcs     :+
        eor     #$FF
        adc     #1
:       cmp     #9
        bcs     @next
        lda     bolt_sy,x
        sec
        sbc     cross_y
        bcs     :+
        eor     #$FF
        adc     #1
:       cmp     #9
        bcs     @next
        lda     #0
        sta     bolt_on,x
        lda     bolt_sx,x
        sta     g_tmp
        lda     bolt_sy,x
        sta     g_tmp+1
        txa
        pha
        lda     #0
        jsr     burst_add
        lda     #3                      ; 30 points
        jsr     add_score_x10
        lda     #1
        sta     panel_dirty
        pla
        tax
@next:  dex
        bpl     @b
        rts

; =======================================================================================
; Sprites. Blocks 0-SPRITE_COUNT at the start of each VIC bank; sprite 0 = crosshair.

sprites_init:
        ldx     #0
:       lda     sprite_data,x           ; the blocks, to the start of both banks
        sta     $8000,x
        sta     $C000,x
        inx
        cpx     #64*SPRITE_COUNT
        bne     :-
        lda     #SPRITE_CROSSHAIR
        ldy     #0
        jsr     sprite_frame
        lda     #5                      ; green crosshair, yellow shots
        sta     $D027
        lda     #7
        sta     $D028
        sta     $D029
        sta     $D02A
        lda     #0
        sta     $D01B                   ; sprites in front
        sta     $D01C                   ; hires sprites
        sta     spr_on
        sta     spr_big
        rts

; sprite_frame: sprite Y shows block A, in both screens' pointers.
sprite_frame:
        sta     BUF0_SCREEN+$3F8,y
        sta     BUF1_SCREEN+$3F8,y
        rts

; sprite_set: sprite Y's table entry = centred on viewport pixel (A = x, g_spy = y).
; The raster interrupt copies the table to the VIC (it alone writes those registers).
sprite_set:
        clc
        adc     #24+VIEW_LEFT_CELLS*8-11
        sta     spr_xl,y
        lda     #0
        rol
        sta     spr_xh,y
        lda     g_spy
        clc
        adc     #50-10
        sta     spr_y,y
        rts

        .segment "RODATA"
sprite_bit:     .byte 1, 2, 4, 8, 16, 32, 64, 128
        .segment "CODE"

; irq_game: in the raster interrupt, 50/60 times a second: joystick, crosshair, sound.
irq_game:
        lda     CIA1_PRA
        eor     #$FF
        and     #$1F
        tax
        eor     joy
        and     #JOY_FIRE
        beq     :+
        txa                             ; fire changed: newly down?
        and     #JOY_FIRE
        beq     :+
        sta     fire_new
:       stx     joy
        lda     cross_lock              ; on the map the game places the crosshair
        bne     @placed
        txa
        lsr                             ; up
        bcc     :+
        ldx     cross_y
        cpx     #6
        bcc     :+
        dec     cross_y
        dec     cross_y
        dec     cross_y
:       lsr                             ; down
        bcc     :+
        ldx     cross_y
        cpx     #150
        bcs     :+
        inc     cross_y
        inc     cross_y
        inc     cross_y
:       lsr                             ; left
        bcc     :+
        ldx     cross_x
        cpx     #6
        bcc     :+
        dec     cross_x
        dec     cross_x
        dec     cross_x
:       lsr                             ; right
        bcc     :+
        ldx     cross_x
        cpx     #248
        bcs     :+
        inc     cross_x
        inc     cross_x
        inc     cross_x
:                                       ; (the right-hand stop jumps here)
@placed:
        lda     cross_y                 ; sprite 0 = the crosshair
        clc
        adc     #50-10
        sta     $D001
        lda     cross_x
        clc
        adc     #24+VIEW_LEFT_CELLS*8-11
        sta     $D000
        lda     #0
        rol
        sta     irq_msb                 ; bit 0: the crosshair's x bit 8
        ldx     #3                      ; sprites 1-3 from the table
@spr:   txa
        asl
        tay
        lda     spr_xl,x
        sta     $D000,y
        lda     spr_y,x
        sta     $D001,y
        lda     spr_xh,x
        beq     :+
        lda     sprite_bit,x
        ora     irq_msb
        sta     irq_msb
:       dex
        bne     @spr
        lda     irq_msb
        sta     $D010
        lda     spr_on
        ora     cross_vis
        sta     $D015
        lda     spr_big
        sta     $D017
        sta     $D01D
        lda     flash_t                 ; the border flash fades
        beq     :+
        dec     flash_t
        bne     :+
        lda     #COLOR_BLACK
        sta     VIC_BORDER
:       jmp     sfx_tick

; =======================================================================================
; Stars: points rushing past.

stars_init:
        ldx     #STAR_COUNT-1
:       jsr     star_new
        jsr     rand                    ; spread over all depths at the start
        and     #$07
        sta     star_z_hi,x
        dex
        bpl     :-
        rts

; star_new: star X far ahead at a random spot.
star_new:
        jsr     rand
        sta     star_x,x
        jsr     rand
        sta     star_y,x
        jsr     rand
        sta     star_z_lo,x
        lda     #$07
        sta     star_z_hi,x
        rts

; stars_tick: every star comes A units closer.
stars_tick:
        sta     g_tmp
        ldx     #STAR_COUNT-1
@s:     lda     star_z_lo,x
        sec
        sbc     g_tmp
        sta     star_z_lo,x
        bcs     :+
        dec     star_z_hi,x
:       lda     star_z_hi,x
        bne     @next
        lda     star_z_lo,x
        cmp     #NEAR_Z+8
        bcs     @next
        jsr     star_new
@next:  dex
        bpl     @s
        rts

draw_stars:
        ldx     #STAR_COUNT-1
@s:     stx     g_tmp
        lda     star_x,x                ; world x, y = star * 4
        sta     wx
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       sty     wx+1
        asl     wx
        rol     wx+1
        asl     wx
        rol     wx+1
        lda     star_y,x
        sta     wy
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       sty     wy+1
        asl     wy
        rol     wy+1
        asl     wy
        rol     wy+1
        lda     star_z_lo,x
        sta     wz
        lda     star_z_hi,x
        sta     wz+1
        jsr     project_point
        bcs     :+
        jsr     plot_point
:       ldx     g_tmp
        dex
        bpl     @s
        rts

; draw_dots: far objects as 2x2 points.
draw_dots:
        ldx     #ENEMY_SLOTS-1
@d:     lda     obj_dot,x
        beq     @next
        stx     g_tmp
        lda     obj_bb_x0,x
        cmp     #VIEW_CX*2-1
        bcs     :+
        sta     px
        lda     obj_bb_y0,x
        cmp     #VIEW_CY*2-1
        bcs     :+
        sta     py
        jsr     plot_point
        inc     px
        jsr     plot_point
        inc     py
        jsr     plot_point
        dec     px
        jsr     plot_point
:       ldx     g_tmp
@next:  dex
        bpl     @d
        rts

; plot_point: sets pixel (px, py) in the back buffer and marks its cell dirty.
plot_point:
        lda     py
        and     #$F8
        tay
        lda     px
        and     #$F8
        clc
        adc     row_lo,y
        sta     ptr
        lda     row_hi,y
        adc     #0
        ora     bufhi
        sta     ptr+1
        lda     px
        and     #7
        tay
        lda     pixel_mask,y
        pha
        lda     py
        and     #7
        tay
        pla
        ora     (ptr),y
        sta     (ptr),y
        lda     px                      ; dirty: column px / 8, row py / 8
        lsr
        lsr
        lsr
        clc
        adc     dirty_off
        tay
        lda     py
        lsr
        lsr
        lsr
        cmp     dirty_min,y
        bcs     :+
        sta     dirty_min,y
:       cmp     dirty_max,y
        bcc     :+
        sta     dirty_max,y
:       rts

; =======================================================================================
; Explosions: sparks flying out from a point for BURST_AGE ticks.

; burst_add: at (g_tmp, g_tmp+1), A = 1 big / 0 small.
burst_add:
        ldy     #BURST_COUNT-1
:       ldx     burst_t,y
        beq     :+
        dey
        bpl     :-
        ldy     #0                      ; all busy: replace the first
:       sta     burst_big,y
        lda     g_tmp
        sta     burst_x,y
        lda     g_tmp+1
        sta     burst_y,y
        lda     #1
        sta     burst_t,y
        rts

bursts_tick:
        ldx     #BURST_COUNT-1
:       lda     burst_t,x
        beq     :+
        inc     burst_t,x
        lda     burst_t,x
        cmp     #BURST_AGE+1
        bcc     :+
        lda     #0
        sta     burst_t,x
:       dex
        bpl     :--
        rts

draw_bursts:
        ldx     #BURST_COUNT-1
@b:     lda     burst_t,x
        bne     :+
        jmp     @next
:       stx     g_tmp
        sec                             ; table index: (big * 12 + age) * 8
        sbc     #1
        ldy     burst_big,x
        beq     :+
        clc
        adc     #BURST_AGE
:       asl
        asl
        asl
        sta     g_tmp+1
        lda     #8
        sta     burst_k
@k:     ldy     g_tmp+1
        ldx     g_tmp
        lda     burst_x0,y
        sta     g_off
        lda     burst_x,x
        jsr     coord_x
        bcs     @skip
        sta     lx0
        lda     burst_x1,y
        sta     g_off
        lda     burst_x,x
        jsr     coord_x
        bcs     @skip
        sta     lx1
        lda     burst_y0,y
        sta     g_off
        lda     burst_y,x
        jsr     coord_y
        bcs     @skip
        sta     ly0
        lda     burst_y1,y
        sta     g_off
        lda     burst_y,x
        jsr     coord_y
        bcs     @skip
        sta     ly1
        jsr     draw_line_marked
@skip:  inc     g_tmp+1
        dec     burst_k
        bne     @k
        ldx     g_tmp
@next:  dex
        bmi     :+
        jmp     @b
:       rts

; coord_x: A = centre + the signed offset g_off, carry set when outside 0-255.
; coord_y: the same within the viewport's 0-158. Keep X and Y.
coord_x:
        clc
        adc     g_off
        bit     g_off
        bmi     :+
        rts                             ; positive offset: carry = past 255
:       bcs     :+                      ; negative offset: no carry = below 0
        sec
        rts
:       clc
        rts
coord_y:
        jsr     coord_x
        bcs     :+
        cmp     #VIEW_CY*2+1
:       rts

; draw_line_marked: draws (lx0, ly0)-(lx1, ly1) and marks its box dirty.
draw_line_marked:
        lda     lx0
        cmp     lx1
        bcc     :+
        ldx     lx1                     ; mark_dirty wants lx0 <= lx1
        sta     lx1
        stx     lx0
        lda     ly0
        ldx     ly1
        stx     ly0
        sta     ly1
:       jsr     mark_dirty
        jmp     draw_line

; draw_laser: two beams from the bottom corners to the crosshair while laser_t runs.
draw_laser:
        lda     laser_t
        beq     :+
        lda     #4
        sta     lx0
        lda     #158
        sta     ly0
        lda     cross_x
        sta     lx1
        lda     cross_y
        sta     ly1
        jsr     draw_line_marked
        lda     #251
        sta     lx0
        lda     #158
        sta     ly0
        lda     cross_x
        sta     lx1
        lda     cross_y
        sta     ly1
        jsr     draw_line_marked
:       rts

; =======================================================================================
; The panel.

panel_clear:
        print_at PANEL_ROW+1, 1, txt_blank
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+3, 1, txt_blank
        rts

panel_refresh:
        lda     panel_dirty
        beq     @done
        lda     #0
        sta     panel_dirty
        lda     state
        cmp     #STATE_TITLE
        beq     @done
        set_pos PANEL_ROW+1, 7
        ldx     #score
        jsr     print_score
        set_pos PANEL_ROW+1, 22          ; shield: one block per point
        ldy     #0
:       lda     #'-'
        cpy     shield
        bcs     :+
        lda     #'*' & $3F
:       jsr     put_char
        iny
        cpy     #SHIELD_FULL
        bne     :--
        set_pos PANEL_ROW+1, 37
        lda     sector
        jsr     print_2digits
        set_pos PANEL_ROW+3, 7
        lda     kills
        jsr     print_2digits
        set_pos PANEL_ROW+3, 13
        lda     quota
        jsr     print_2digits
@done:  rts

; print_score: the 24-bit number at zero page X as 6 digits.
print_score:
        lda     0,x
        sta     num
        lda     1,x
        sta     num+1
        lda     2,x
        sta     num+2
        jsr     to_decimal
        lda     #6
        jmp     put_digits

; print_2digits: A (0-99) as 2 digits.
print_2digits:
        sta     num
        lda     #0
        sta     num+1
        sta     num+2
        jsr     to_decimal
        lda     #2
        jmp     put_digits

; add_score_x10: score += A * 10.
add_score_x10:
        sta     g_tmp
        asl                             ; A * 10 = A * 8 + A * 2 (A <= 50)
        asl
        clc
        adc     g_tmp
        asl
        clc
        adc     score
        sta     score
        bcc     :+
        inc     score+1
        bne     :+
        inc     score+2
:       rts

; =======================================================================================
over_start:
        lda     #STATE_OVER
        sta     state
        lda     #OVER_TICKS
        sta     state_timer
        jsr     bolts_clear
        lda     #TRACK_OVER
        jsr     music_play
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 15, txt_over
        rts

over_tick:
        lda     #4
        jsr     stars_tick
        jsr     enemies_drift
        jsr     bursts_tick
        dec     state_timer
        bne     :+
        jsr     hs_rank                 ; into the table?
        cmp     #HS_COUNT
        bcs     @title
        jmp     name_start
@title: jmp     title_start
:       rts

; title_flip: from the ship to the table or back.
title_flip:
        lda     title_phase
        eor     #1
        sta     title_phase
        beq     @ship
        lda     #0                      ; the table: no ship
        sta     obj_active
        lda     #<TITLE_TABLE
        sta     title_t
        lda     #>TITLE_TABLE
        sta     title_t+1
        rts
@ship:  lda     #1
        sta     obj_active
        lda     #<TITLE_SHIP
        sta     title_t
        lda     #>TITLE_SHIP
        sta     title_t+1
        rts

; enemies_drift: after the end the enemies fly on past.
enemies_drift:
        ldx     #ENEMY_SLOTS-1
:       lda     obj_active,x
        beq     :+
        lda     obj_z_lo,x
        sec
        sbc     #20
        sta     obj_z_lo,x
        bcs     :+
        dec     obj_z_hi,x
        bpl     :+
        lda     #0
        sta     obj_active,x
:       dex
        bpl     :--
        rts

        .segment "RODATA"
txt_title:      scr "GALACTIC ANARCHY"
                .byte 0
txt_press:      scr "PRESS FIRE TO START"
                .byte 0
txt_high:       scr "HIGH"
                .byte 0
txt_score:      scr "SCORE 000000  SHIELD ------  SECTOR 00"
                .byte 0
txt_kills:      scr "KILLS 00 OF 00"
                .byte 0
txt_sector:     scr "SECTOR"
                .byte 0
txt_over:       scr "GAME  OVER"
                .byte 0

.ifdef TEST_PLAY
; test_autoplay: aims at the first enemy with a box on screen and fires whenever the gun is
; ready. Passes (0 to the debug port) after 5 kills; fails (2) if the shields run out.
; TEST_AIM_OFF = n aims n pixels to the right of the target (the control: no kills).
.ifndef TEST_AIM_OFF
TEST_AIM_OFF = 0
.endif
test_autoplay:
  .ifdef TEST_BOSS
        lda     boss_dying              ; the boss test passes when the hull blows
        beq     :+
  .else
        lda     kills_total
        cmp     #5
        bcc     :+
  .endif
        lda     #0
        sta     DEBUGCART_RESULT
:       lda     shield
        bne     :+
        lda     #2
        sta     DEBUGCART_RESULT
:       ldx     #ENEMY_SLOTS-1
@find:  lda     obj_active,x
        beq     @next
        lda     obj_dot,x
        bne     @next
        ldy     en_kind,x               ; never at armour
        lda     kind_flags,y
        and     #KF_ARMOR
        bne     @next
        lda     obj_bb_x0,x
        cmp     #$FF
        bne     @aim
@next:  dex
        bpl     @find
        rts
@aim:   clc
        adc     obj_bb_x1,x
        ror
        clc
        adc     #TEST_AIM_OFF
        bcc     :+
        lda     #255
:       sta     cross_x
        lda     obj_bb_y0,x
        clc
        adc     obj_bb_y1,x
        ror
        sta     cross_y
        lda     fire_wait
        bne     :+
        lda     #1
        sta     fire_new
:       rts
.endif
