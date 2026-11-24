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

        .segment "BSS"
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

; pick_spawn_kind: A = the kind of the next arrival, spawn_side = its side.
pick_spawn_kind:
        lda     #0
        sta     spawn_side
        ldy     faction
        cpy     #F_FIELD                ; rivals only in a faction's sector
        bcs     @pool
        lda     danger                  ; and not in the very first sectors
        beq     @pool
        jsr     rand
        cmp     #RIVAL_CHANCE
        bcs     @pool
        jsr     rand                    ; one of the other two factions
        and     #1
        clc
        adc     #1
        adc     faction
        cmp     #3
        bcc     :+
        sbc     #3
:       tay
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
        lda     duel_t
        beq     :+
        dec     duel_t
:       dec     duel_wait
        beq     :+
        rts
:       lda     #40
        sta     duel_wait
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
        jsr     rand                    ; who is hit
        and     #1
        tax
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
