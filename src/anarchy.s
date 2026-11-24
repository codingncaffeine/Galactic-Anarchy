; The anarchy: in a faction's sector some arrivals come from a rival faction, and rivals
; and the sector's owners shoot each other: every so often a rival and an owner trade
; fire (a line between them) and one of them is hit. Enemies destroyed that way count
; toward the sector's quota but give no score.
; Also the centipede: a head (K_CENTI) followed by CENTI_SEGS body segments (K_SEG), each
; on the head's path CENTI_GAP ticks behind the one before.

CENTI_SEGS      = 3
CENTI_GAP       = 4
HIST_LEN        = 32                    ; head positions kept (a power of two)
.ifdef NO_RIVALS
RIVAL_CHANCE    = 0                     ; (a test control: no rivals)
.else
RIVAL_CHANCE    = 64                    ; of 256 arrivals in a faction's sector
.endif

HEAT_KILL       = 3                     ; heat a kill adds to the ship's faction
HEAT_RIVAL      = 1                     ; and takes from each of the other two
HEAT_COOL       = 5                     ; every faction cools this much a sector
HEAT_MAX        = 99                    ; heat is 0-99; its level (0-9) is heat / 10

        .segment "BSS"
heat:           .res 3                  ; per faction (F_CONCORD, F_CORSAIR, F_SWARM)
heat_lv:        .res 1
heat_rival:     .res 1
heat_lx:        .res 1
heat_second:    .res 1
heat_end:       .res 1
en_side:        .res ENEMY_SLOTS        ; 0 = the sector's owners, 1 = a rival faction
spawn_side:     .res 1
duel_t:         .res 1                  ; ticks the duel line shows
duel_a:         .res 1
duel_b:         .res 1
duel_wait:      .res 1                  ; ticks to the next duel
by_other:       .res 1                  ; 1: destroy_enemy for a kill by another enemy
centi_head:     .res 1                  ; slot of the head, $FF = no centipede
centi_seg:      .res CENTI_SEGS
hist_pos:       .res 1
hist_x_lo:      .res HIST_LEN
hist_x_hi:      .res HIST_LEN
hist_y_lo:      .res HIST_LEN
hist_y_hi:      .res HIST_LEN
hist_z_lo:      .res HIST_LEN
hist_z_hi:      .res HIST_LEN
an_tmp:         .res 2
need_fire:      .res 1
events:         .res 1                  ; for tests: bit 0 a duel, bit 1 a centipede

        .segment "CODE"

; ---------------------------------------------------------------------------------------
; Heat: how much each faction wants the player dead. A kill heats the ship's faction and
; cools its two rivals; every sector cools all three a little. A hot faction sends more
; ships at once and sooner in its own sectors (heat_sector), more rivals into the
; others' (pick_spawn_kind), and takes over more of the map ahead (rand_faction_heat).

heat_reset:
        lda     #0
        sta     heat
        sta     heat+1
        sta     heat+2
        rts

; heat_kill: the player destroyed an enemy of kind Y (in a sector of `faction`).
heat_kill:
.ifdef NO_HEAT
        rts                             ; (a test control: heat changes nothing)
.endif
        lda     kind_faction,y
        cmp     #F_OWNER
        bne     :+
        lda     faction                 ; a freighter: the convoy's faction
:       cmp     #3
        bcs     @done
        tax
        lda     heat,x
        clc
        adc     #HEAT_KILL
        cmp     #HEAT_MAX+1
        bcc     :+
        lda     #HEAT_MAX
:       sta     heat,x
        ldy     #2                      ; the other two cool
@cool:  sty     an_tmp
        cpx     an_tmp
        beq     @same
        lda     heat,y
        sec
        sbc     #HEAT_RIVAL
        bcs     :+
        lda     #0
:       sta     heat,y
@same:  dey
        bpl     @cool
        lda     #1
        sta     panel_dirty
@done:  rts

; heat_cool: after a sector, every faction cools by HEAT_COOL.
heat_cool:
        ldx     #2
:       lda     heat,x
        sec
        sbc     #HEAT_COOL
        bcs     :+
        lda     #0
:       sta     heat,x
        dex
        bpl     :--
        rts

; heat_level: A = heat of faction X / 10 (0-9). Keeps X and Y.
heat_level:
        lda     heat,x
        stx     heat_lx
        ldx     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bne     :-
:       txa
        ldx     heat_lx
        rts

; heat_sector: in a faction's own sector, its heat level adds level / 3 ships on screen at
; once (up to ENEMY_SLOTS) and brings arrivals 2 ticks sooner per level (from 16 on).
heat_sector:
.ifdef NO_HEAT
        rts
.endif
        ldx     faction
        cpx     #3
        bcs     @done
        jsr     heat_level
        sta     heat_lv
        ldx     #0                      ; level / 3
        sec
:       sbc     #3
        bcc     :+
        inx
        bcs     :-
:       txa
        clc
        adc     active_max
        cmp     #ENEMY_SLOTS+1
        bcc     :+
        lda     #ENEMY_SLOTS
:       sta     active_max
        lda     heat_lv
        asl
        sta     an_tmp
        lda     spawn_delay
        sec
        sbc     an_tmp
        bcc     :+
        cmp     #16
        bcs     :++
:       lda     #16
:       sta     spawn_delay
@done:  rts

; hotter_rival: of the two factions other than `faction`, heat_rival = the first and
; heat_second the second (faction + 1 and + 2, mod 3), heat_lv = the hotter one's level.
hotter_rival:
        ldx     faction
        inx
        cpx     #3
        bcc     :+
        ldx     #0
:       stx     heat_rival
        inx
        cpx     #3
        bcc     :+
        ldx     #0
:       stx     heat_second
        lda     heat,x
        ldy     heat_rival
        cmp     heat,y
        bcs     :+                      ; the second is at least as hot
        ldx     heat_rival
:       jsr     heat_level
        sta     heat_lv
        rts

; pick_rival: heat_rival = the hotter of the two (one of them at random when level).
; With no heat this draws one random number, as the rival pick always has.
pick_rival:
        jsr     hotter_rival
        ldx     heat_second
        lda     heat,x
        ldy     heat_rival
        cmp     heat,y
        beq     @even
        bcc     @done
        stx     heat_rival              ; the second is hotter
@done:  rts
@even:  jsr     rand
        and     #1
        beq     @done
        stx     heat_rival
        rts

; rand_faction_heat: A = a faction for a sector that changes hands, each with weight
; 1 + its heat level. Keeps X.
rand_faction_heat:
        stx     an_tmp+1
        lda     #3                      ; the total weight
        sta     an_tmp
        ldx     #2
:       jsr     heat_level
        clc
        adc     an_tmp
        sta     an_tmp
        dex
        bpl     :-
:       jsr     rand                    ; r in 0 .. total - 1 (total is at most 30)
        and     #31
        cmp     an_tmp
        bcs     :-
        ldx     #0
@walk:  sta     an_tmp
        jsr     heat_level
        sec                             ; r -= 1 + level
        adc     #0
        sta     heat_lv
        lda     an_tmp
        sec
        sbc     heat_lv
        bcc     @this
        inx
        cpx     #2
        bcc     @walk
@this:  txa
        ldx     an_tmp+1
        rts

; heat_show: the heat levels on the panel's bottom row, each faction in its colour.
heat_show:
        print_at PANEL_ROW+4, 1, txt_heat
        ldx     #2
@f:     ldy     heat_col,x              ; the digit
        jsr     heat_level
        ora     #'0'
        sta     an_tmp
        txa
        pha
        set_pos PANEL_ROW+4, 0
        lda     an_tmp
        jsr     put_char
        pla
        tax
        ldy     heat_col,x              ; the faction's name and level in its colour
        iny
        sty     heat_end
        ldy     heat_from,x
        lda     faction_color,x
        lsr
        lsr
        lsr
        lsr
:       sta     COLOR_RAM+(PANEL_ROW+4)*40,y
        iny
        cpy     heat_end
        bcc     :-
        dex
        bpl     @f
        rts

        .segment "RODATA"
txt_heat:       scr "HEAT  CONCORD -  CORSAIR -  SWARM -"
                .byte 0
heat_from:      .byte 7, 18, 29         ; panel columns of the names
heat_col:       .byte 15, 26, 35        ; of the digits
        .segment "CODE"

; anarchy_reset: at the start of a sector.
anarchy_reset:
        lda     #$FF
        sta     centi_head
        lda     #0
        sta     duel_t
        sta     by_other
        lda     #60
        sta     duel_wait
        rts

; pick_spawn_kind: A = the kind of the next arrival, spawn_side = its side. Rivals come
; from the hotter of the two other factions (either, when they are level), and the
; hotter it is the more of them: RIVAL_CHANCE + 12 per heat level in 256.
pick_spawn_kind:
        lda     #0
        sta     spawn_side
        ldy     faction
        cpy     #F_FIELD                ; rivals only in a faction's sector
        bcs     @pool
        lda     mission                 ; an escort: all of them, from the attackers
        cmp     #MIS_ESCORT
        bne     :+
        ldy     esc_foe
        lda     #1
        sta     spawn_side
        bne     @pool
:       lda     danger                  ; and not in the very first sectors
        beq     @pool
        jsr     hotter_rival            ; heat_lv: how hot the hotter rival is
        lda     heat_lv
        asl
        adc     heat_lv
        asl
        asl                             ; 12 per level (up to 108)
        adc     #RIVAL_CHANCE
        sta     an_tmp
        jsr     rand
        cmp     an_tmp
        bcs     @pool
        jsr     pick_rival              ; which of the two comes
        ldy     heat_rival
        lda     #1
        sta     spawn_side
@pool:  lda     faction_pool_lo,y
        sta     ptr2
        lda     faction_pool_hi,y
        sta     ptr2+1
        jsr     rand
        and     #7
        tay
        lda     (ptr2),y
        ldx     spawn_side              ; rivals come to fight: a gunless pick (a rock,
        beq     :+                      ; a mine) becomes the pool's first fighter
        tax
        lda     kind_flags,x
        and     #KF_FIRES
        bne     :+
        ldy     #0
        lda     (ptr2),y
        rts
:       lda     (ptr2),y
        cmp     #K_CENTI                ; a centipede needs room for its body
        bne     @done
        ldx     #0
        ldy     #ENEMY_SLOTS-1
:       lda     obj_active,y
        bne     :+
        inx
:       dey
        bpl     :--
        cpx     #CENTI_SEGS+1
        bcs     @ok
        lda     #K_HORNET
        rts
@ok:    lda     centi_head              ; and only one at a time
        cmp     #$FF
        beq     :+
        lda     #K_HORNET
        rts
:       lda     #K_CENTI
@done:  rts

; centi_spawn: X = the head's slot, already placed. Its body takes free slots.
centi_spawn:
        stx     centi_head
        lda     events
        ora     #2
        sta     events
        lda     #0
        sta     hist_pos
        ldy     #HIST_LEN-1             ; the whole path starts at the head
:       lda     obj_x_lo,x
        sta     hist_x_lo,y
        lda     obj_x_hi,x
        sta     hist_x_hi,y
        lda     obj_y_lo,x
        sta     hist_y_lo,y
        lda     obj_y_hi,x
        sta     hist_y_hi,y
        lda     obj_z_lo,x
        sta     hist_z_lo,y
        lda     obj_z_hi,x
        sta     hist_z_hi,y
        dey
        bpl     :-
        lda     #0
        sta     an_tmp
@seg:   jsr     free_slot
        bcs     @full
        lda     #K_SEG
        jsr     setup_kind
        lda     #0
        sta     en_side,x
        ldy     an_tmp
        txa
        sta     centi_seg,y
        ldy     centi_head
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
        inc     an_tmp
        lda     an_tmp
        cmp     #CENTI_SEGS
        bne     @seg
        ldx     centi_head
        rts
@full:  ldy     an_tmp                  ; (cannot happen: room was checked)
        lda     #$FF
        sta     centi_seg,y
        ldx     centi_head
        rts

; centi_tick: once per tick after the enemies moved: the body follows the head's path.
centi_tick:
        ldx     centi_head
        cpx     #$FF
        bne     :+
        rts
:       lda     obj_active,x
        bne     @alive
        lda     #CENTI_SEGS-1           ; the head is gone: so is the body, in flames
        sta     an_tmp
@burn:  ldx     an_tmp
        ldy     centi_seg,x
        tya
        tax
        lda     obj_active,x
        beq     @off
        jsr     box_centre
        lda     #0
        sta     obj_active,x
        bcs     @off
        lda     #0
        jsr     burst_add
@off:   dec     an_tmp
        bpl     @burn
        lda     #$FF
        sta     centi_head
        rts
@alive: ldy     hist_pos                ; record the head
        lda     obj_x_lo,x
        sta     hist_x_lo,y
        lda     obj_x_hi,x
        sta     hist_x_hi,y
        lda     obj_y_lo,x
        sta     hist_y_lo,y
        lda     obj_y_hi,x
        sta     hist_y_hi,y
        lda     obj_z_lo,x
        sta     hist_z_lo,y
        lda     obj_z_hi,x
        sta     hist_z_hi,y
        lda     obj_yaw,x
        sta     an_tmp+1
        lda     #0
        sta     an_tmp
@seg:   ldx     an_tmp                  ; segment i: CENTI_GAP * (i + 1) ticks back
        lda     centi_seg,x
        tax
        lda     obj_active,x
        beq     @next
        lda     an_tmp
        clc
        adc     #1
        asl
        asl                             ; * CENTI_GAP (4)
        eor     #$FF
        sec
        adc     hist_pos
        and     #HIST_LEN-1
        tay
        lda     hist_x_lo,y
        sta     obj_x_lo,x
        lda     hist_x_hi,y
        sta     obj_x_hi,x
        lda     hist_y_lo,y
        sta     obj_y_lo,x
        lda     hist_y_hi,y
        sta     obj_y_hi,x
        lda     hist_z_lo,y
        sta     obj_z_lo,x
        lda     hist_z_hi,y
        sta     obj_z_hi,x
        lda     an_tmp+1
        sta     obj_yaw,x
@next:  inc     an_tmp
        lda     an_tmp
        cmp     #CENTI_SEGS
        bne     @seg
        lda     hist_pos
        clc
        adc     #1
        and     #HIST_LEN-1
        sta     hist_pos
        rts

; duels_tick: once per tick in a sector.
duels_tick:
.ifdef NO_DUELS
        rts                             ; (a test control: nobody fights anybody)
.endif
        lda     duel_t
        beq     :+
        dec     duel_t
:       dec     duel_wait
        beq     :+
        rts
:       lda     #40
        ldx     mission                 ; an escort's attackers shoot more often
        cpx     #MIS_ESCORT
        bne     :+
        lda     #ESCORT_DUEL
:       sta     duel_wait
        jsr     duel_find_side          ; a rival that fires...
        bcs     @none
        lda     #1
        sta     need_fire
        jsr     duel_find               ; (side 1)
        bcs     @none
        stx     duel_a
        lda     #0
        sta     need_fire
        jsr     duel_find               ; ...and an owner in view
        bcs     @none
        stx     duel_b
        lda     #4
        sta     duel_t
        lda     events
        ora     #1
        sta     events
        jsr     sfx_hit
        jsr     rand                    ; who is hit (in an escort, the freighter)
        and     #1
        ldx     mission
        cpx     #MIS_ESCORT
        bne     :+
        lda     #1
:       tax
        lda     duel_a,x
        tax
        dec     en_hp,x
        bne     @none
        stx     hit_best
        lda     #1
        sta     by_other
        jsr     destroy_enemy
        lda     #0
        sta     by_other
@none:  rts

; duel_find_side: carry clear if any rival is about (a cheap check first).
duel_find_side:
        ldx     #ENEMY_SLOTS-1
:       lda     obj_active,x
        beq     :+
        lda     en_side,x
        bne     @yes
:       dex
        bpl     :--
        sec
        rts
@yes:   clc
        rts

; duel_find: X = a slot on side A that is on screen (and has guns if need_fire), carry
; clear; carry set when there is none. Starts at a random slot.
duel_find:
        sta     an_tmp
        jsr     rand
        and     #7
        cmp     #ENEMY_SLOTS
        bcc     :+
        lda     #0
:       tax
        lda     #ENEMY_SLOTS
        sta     an_tmp+1
@try:   lda     obj_active,x
        beq     @no
        lda     en_side,x
        cmp     an_tmp
        bne     @no
        lda     obj_bb_x0,x             ; on screen (a dot will do)
        cmp     #$FF
        beq     @no
        ldy     en_kind,x
        lda     kind_flags,y
        and     #KF_ARMOR
        bne     @no
        lda     need_fire               ; the one that fires must have guns
        beq     :+
        lda     kind_flags,y
        and     #KF_FIRES
        beq     @no
:       clc
        rts
@no:    inx
        cpx     #ENEMY_SLOTS
        bcc     :+
        ldx     #0
:       dec     an_tmp+1
        bne     @try
        sec
        rts

; draw_duel: the line between the two duellists while duel_t runs.
draw_duel:
        lda     duel_t
        beq     @no
        ldx     duel_a
        jsr     box_centre
        bcs     @no
        lda     g_tmp
        sta     lx0
        lda     g_tmp+1
        sta     ly0
        ldx     duel_b
        jsr     box_centre
        bcs     @no
        lda     g_tmp
        sta     lx1
        lda     g_tmp+1
        sta     ly1
        jmp     draw_line_marked
@no:    rts

; box_centre: g_tmp, g_tmp+1 = the centre of slot X's screen box; carry set if none.
box_centre:
        lda     obj_active,x
        beq     @none
        lda     obj_bb_x0,x
        cmp     #$FF
        beq     @none
        clc
        adc     obj_bb_x1,x
        ror
        sta     g_tmp
        lda     obj_bb_y0,x
        clc
        adc     obj_bb_y1,x
        ror
        sta     g_tmp+1
        clc
        rts
@none:  sec
        rts
