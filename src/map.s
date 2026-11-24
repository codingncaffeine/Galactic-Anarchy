; The sector map: 7 columns of up to 3 sectors, crossed left to right. From each sector
; one or two hyperlanes lead on to the next column; the player picks one with up/down and
; fire. Each sector belongs to a faction (its enemies, and the colour it is drawn in) or is
; an asteroid field; the middle of column 3 and the last column hold the Dreadnought.
; The danger of a sector is its column, plus one in the top lane, plus 7 for every time
; round the map. After every sector two sectors further on change hands.

MAP_COLS        = 7
MAP_ROWS        = 3
MAP_NODES       = MAP_COLS * MAP_ROWS

F_CONCORD       = 0
F_CORSAIR       = 1
F_SWARM         = 2
F_FIELD         = 3                     ; asteroid field, nobody's
F_BOSS          = 4                     ; the Dreadnought

        .segment "RODATA"
; Node centres in viewport pixels, by column and by row.
map_x:          .byte 18, 54, 90, 126, 162, 198, 236
map_y:          .byte 22, 78, 134
faction_pool_lo: .byte <pool_concord, <pool_corsair, <pool_swarm, <pool_field
faction_pool_hi: .byte >pool_concord, >pool_corsair, >pool_swarm, >pool_field
; Cell colours (foreground in the high nibble): cyan, light red, yellow, light grey, purple.
faction_color:  .byte $30, $A0, $70, $F0, $40
pool_concord:   .byte K_LANCER, K_LANCER, K_GUNSHIP, K_LANCER, K_MINE, K_LANCER, K_GUNSHIP, K_ROCK_M
pool_corsair:   .byte K_RAIDER, K_RAIDER, K_MAULER, K_RAIDER, K_ROCK_L, K_RAIDER, K_MAULER, K_MINE
pool_swarm:     .byte K_SKITTER, K_HORNET, K_MOTH, K_SKITTER, K_MANTIS, K_HORNET, K_CENTI, K_HIVE
pool_field:     .byte K_ROCK_L, K_ROCK_L, K_ROCK_M, K_ROCK_L, K_MINE, K_ROCK_M, K_RAIDER, K_ROCK_L
faction_name_lo: .byte <txt_concord, <txt_corsair, <txt_swarm, <txt_field, <txt_boss
faction_name_hi: .byte >txt_concord, >txt_corsair, >txt_swarm, >txt_field, >txt_boss
txt_concord:    scr "CONCORD SPACE "
                .byte 0
txt_corsair:    scr "CORSAIR SPACE "
                .byte 0
txt_swarm:      scr "SWARM SPACE   "
                .byte 0
txt_field:      scr "ASTEROID FIELD"
                .byte 0
txt_boss:       scr "DREADNOUGHT   "
                .byte 0
txt_route:      scr "NEXT"
                .byte 0
txt_danger:     scr "DANGER"
                .byte 0


        .segment "BSS"
node_faction:   .res MAP_NODES          ; index = column * 3 + row; $FF = no sector
node_links:     .res MAP_NODES          ; bit r: a lane to row r of the next column

        .segment "CODE"

; map_new: a fresh map.
map_new:
        ldx     #MAP_NODES-1
@node:  jsr     rand                    ; 1 in 4 an asteroid field, else a faction
        and     #3
        cmp     #F_FIELD
        beq     :+
        jsr     rand_faction
:       sta     node_faction,x
        jsr     rand                    ; lanes: the same row, one off, or both
        and     #3
        tay
        lda     lane_choice,y
        ldy     node_row_of,x
        jsr     lanes_for
        sta     node_links,x
        dex
        bpl     @node
        lda     #$FF                    ; the last column: the Dreadnought alone
        sta     node_faction+6*3+0
        sta     node_faction+6*3+2
        lda     #F_BOSS
        sta     node_faction+6*3+1
        sta     node_faction+3*3+1      ; and one in the middle of the map
        lda     #%010                   ; column 5's lanes all lead to it
        sta     node_links+5*3+0
        sta     node_links+5*3+1
        sta     node_links+5*3+2
        lda     #%111                   ; the middle one lets everyone through
        sta     node_links+3*3+1
        lda     #$FF
        sta     map_col
        rts

; rand_faction: A = Concord, Corsair or Swarm at random. Keeps X.
rand_faction:
        jsr     rand
        and     #3
        cmp     #3
        bcc     :+
        lda     #F_CORSAIR
:       rts

; lanes_for: A = choice (bit 0: the same row, bit 1: a row off), Y = row -> A = lane bits.
; Keeps X.
lanes_for:
        sta     map_tmp
        lda     #0
        sta     map_tmp+1
        lsr     map_tmp
        bcc     :+
        lda     row_bit,y
        sta     map_tmp+1
:       lsr     map_tmp
        bcc     :+++
        jsr     rand
        and     #1
        beq     :+
        lda     row_up_bit,y
        bne     :++
:       lda     row_down_bit,y
:       ora     map_tmp+1
        sta     map_tmp+1
:       lda     map_tmp+1
        bne     :+
        lda     row_bit,y
:       rts

        .segment "RODATA"
lane_choice:    .byte 1, 1, 2, 3
row_bit:        .byte %001, %010, %100
row_up_bit:     .byte %001, %001, %010  ; the row above (row 0: itself)
row_down_bit:   .byte %010, %100, %100  ; the row below (row 2: itself)
node_col_of:
        .repeat MAP_NODES, i
        .byte   i / 3
        .endrep
node_row_of:
        .repeat MAP_NODES, i
        .byte   i .mod 3
        .endrep

; map_start: show the map and wait for the player's choice.
map_start:
        lda     #STATE_MAP
        sta     state
        jsr     clear_slots
        jsr     bolts_clear
        lda     #1
        sta     cross_lock
        lda     #0
        sta     spr_on
        sta     laser_t
        lda     #1
        sta     panel_dirty
        lda     joy
        sta     joy_last
        jsr     map_colors
        lda     #TRACK_MAP
        jsr     music_play
        jsr     map_candidates
        lda     #0
        sta     map_sel
        sta     fire_new
        jsr     map_show_choice
        rts

; map_candidates: the rows the player can jump to.
map_candidates:
        lda     #0
        sta     map_cand_n
        lda     map_col
        cmp     #$FF
        bne     :+
        lda     #%111                   ; before the first jump: any of column 0
        bne     @have
:       asl
        adc     map_col
        adc     map_row
        tax
        lda     node_links,x
@have:  sta     map_tmp
        ldy     #0
@r:     lsr     map_tmp
        bcc     :+
        tya
        ldx     map_cand_n
        sta     map_cand,x
        inc     map_cand_n
:       iny
        cpy     #MAP_ROWS
        bne     @r
        rts

; next_col: A = the column after the player's.
next_col:
        lda     map_col
        clc
        adc     #1
        rts

; map_show_choice: the crosshair on the selected sector, its name and danger on the panel.
map_show_choice:
        jsr     next_col
        tax
        lda     map_x,x
        sta     cross_x
        ldx     map_sel
        ldy     map_cand,x
        lda     map_y,y
        sta     cross_y
        jsr     sel_node
        lda     node_faction,x
        tax
        lda     faction_name_lo,x
        sta     str_ptr
        lda     faction_name_hi,x
        sta     str_ptr+1
        set_pos PANEL_ROW+2, 6
        jsr     print_str
        print_at PANEL_ROW+2, 1, txt_route
        print_at PANEL_ROW+2, 22, txt_danger
        jsr     sel_danger
        sta     danger
        set_pos PANEL_ROW+2, 29
        lda     danger
        clc
        adc     #1
        jmp     print_2digits

; sel_node: X = the node index of the selected candidate.
sel_node:
        jsr     next_col
        sta     map_tmp
        asl
        adc     map_tmp
        ldx     map_sel
        clc
        adc     map_cand,x
        tax
        rts

; sel_danger: A = the danger of the selected candidate.
sel_danger:
        jsr     next_col
        ldx     map_sel
        ldy     map_cand,x
        bne     :+
        clc                             ; the top lane is one harder
        adc     #1
:       sta     map_tmp
        lda     map_loop                ; + 7 per time round
        asl
        asl
        asl
        sec
        sbc     map_loop
        clc
        adc     map_tmp
        rts

map_tick:
.ifdef TEST_PLAY
        lda     #1                      ; the test build takes the first lane offered
        sta     fire_new
.endif
        lda     #2
        jsr     stars_tick
        lda     joy                     ; up / down, newly pressed: the next choice
        tax
        eor     joy_last
        stx     joy_last
        and     joy
        sta     map_tmp
        and     #%00001                 ; up
        beq     :+
        dec     map_sel
        bpl     @moved
        ldx     map_cand_n
        dex
        stx     map_sel
        jmp     @moved
:       lda     map_tmp
        and     #%00010                 ; down
        beq     @fire
        inc     map_sel
        lda     map_sel
        cmp     map_cand_n
        bcc     @moved
        lda     #0
        sta     map_sel
@moved: jsr     map_show_choice
@fire:  lda     fire_new
        bne     :+
        rts
:       lda     #0
        sta     fire_new
        sta     cross_lock
        sta     boss_fight
        jsr     sel_node                ; the jump
        lda     node_faction,x
        sta     faction
        jsr     sel_danger
        sta     danger
        jsr     next_col
        sta     map_col
        ldx     map_sel
        lda     map_cand,x
        sta     map_row
        lda     #VIEW_CX
        sta     cross_x
        lda     #VIEW_CY
        sta     cross_y
        lda     faction
        cmp     #F_BOSS
        bne     :+
        jmp     boss_start
:       jmp     ready_start

; map_after_sector: shields repaired a little, two sectors ahead change hands, back to
; the map (or round again after the last column).
map_after_sector:
        lda     shield
        clc
        adc     #2
        cmp     #SHIELD_FULL+1
        bcc     :+
        lda     #SHIELD_FULL
:       sta     shield
        lda     #1
        sta     panel_dirty
        lda     map_col
        cmp     #MAP_COLS-1
        bcc     :+
        inc     map_loop
        jsr     map_new
        jmp     map_start
:       lda     #2
        sta     map_tmp+2
        lda     #40                     ; tries, in case few sectors are left ahead
        sta     map_tmp+1
@shift: dec     map_tmp+1
        beq     @done
        jsr     rand
        and     #31
        cmp     #MAP_NODES
        bcs     @shift
        tax
        lda     node_col_of,x           ; ahead of the player
        cmp     map_col
        beq     @shift
        bcc     @shift
        lda     node_faction,x          ; a faction's sector or a field, not a boss
        cmp     #F_BOSS
        bcs     @shift
        jsr     rand_faction
        sta     node_faction,x
        dec     map_tmp+2
        bne     @shift
@done:  jmp     map_start

; map_colors: the viewport white, each sector's cells in its owner's colour.
map_colors:
        lda     #COLOR_WHITE<<4
        jsr     view_color
        ldx     #MAP_NODES-1
@n:     lda     node_faction,x
        cmp     #$FF
        beq     @next
        tay
        lda     faction_color,y
        sta     map_tmp+2
        stx     map_tmp+1
        ldy     node_row_of,x
        lda     map_y,y                 ; cell row of the centre
        lsr
        lsr
        lsr
        sta     map_tmp
        ldy     node_col_of,x
        lda     map_x,y                 ; cell column of the centre
        lsr
        lsr
        lsr
        clc
        adc     #VIEW_LEFT_CELLS-1
        tay
        ldx     map_tmp                 ; 3 x 3 cells around it
        dex
        jsr     color_cells3
        inx
        jsr     color_cells3
        inx
        jsr     color_cells3
        ldx     map_tmp+1
@next:  dex
        bpl     @n
        rts

; color_cells3: cells (Y..Y+2, row X) of both screens get colour map_tmp+2. Keeps X, Y.
color_cells3:
        cpx     #VIEW_ROWS
        bcs     @out
        lda     screen_row_lo,x
        sta     ptr2
        lda     screen_row_hi,x
        sta     ptr2+1
        tya
        pha
        lda     map_tmp+2
        sta     (ptr2),y
        iny
        sta     (ptr2),y
        iny
        sta     (ptr2),y
        lda     ptr2+1                  ; the other screen
        eor     #(>BUF0_SCREEN) ^ (>BUF1_SCREEN)
        sta     ptr2+1
        pla
        tay
        lda     map_tmp+2
        sta     (ptr2),y
        iny
        sta     (ptr2),y
        iny
        sta     (ptr2),y
        dey
        dey
@out:   rts

; view_color: every viewport cell of both screens = A.
view_color:
        sta     map_tmp+2
        ldx     #VIEW_ROWS-1
:       ldy     #VIEW_LEFT_CELLS
        lda     screen_row_lo,x
        sta     ptr2
        lda     screen_row_hi,x
        sta     ptr2+1
        lda     map_tmp+2
@c:     sta     (ptr2),y
        iny
        cpy     #VIEW_LEFT_CELLS+32
        bne     @c
        lda     ptr2+1
        eor     #(>BUF0_SCREEN) ^ (>BUF1_SCREEN)
        sta     ptr2+1
        ldy     #VIEW_LEFT_CELLS
        lda     map_tmp+2
@d:     sta     (ptr2),y
        iny
        cpy     #VIEW_LEFT_CELLS+32
        bne     @d
        dex
        bpl     :-
        rts

        .segment "RODATA"
screen_row_lo:
        .repeat VIEW_ROWS, r
        .byte   <(BUF0_SCREEN + r*40)
        .endrep
screen_row_hi:
        .repeat VIEW_ROWS, r
        .byte   >(BUF0_SCREEN + r*40)
        .endrep
        .segment "CODE"

; draw_map: the lanes, then the sectors, into the back buffer.
draw_map:
        ldx     #0                      ; lanes from columns 0-5
@lane:  lda     node_faction,x
        cmp     #$FF
        beq     @nolane
        lda     node_links,x
        sta     map_tmp
        stx     map_tmp+1
        jsr     node_xy                 ; from
        ldy     #0
@to:    lsr     map_tmp
        bcc     @nextto
        sty     map_tmp+2
        lda     g_nx
        sta     lx0
        lda     g_ny
        sta     ly0
        ldx     map_tmp+1
        ldy     node_col_of,x
        lda     map_x+1,y
        sta     lx1
        ldy     map_tmp+2
        lda     map_y,y
        sta     ly1
        jsr     draw_line_marked
        ldy     map_tmp+2
@nextto:
        iny
        cpy     #MAP_ROWS
        bne     @to
        ldx     map_tmp+1
@nolane:
        inx
        cpx     #(MAP_COLS-1)*3
        bne     @lane

        ldx     #MAP_NODES-1            ; the sectors
@node:  lda     node_faction,x
        cmp     #$FF
        beq     @nonode
        stx     map_tmp+1
        jsr     node_xy
        ldx     map_tmp+1
        lda     node_faction,x
        ldy     #5                      ; a diamond, bigger for the boss
        cmp     #F_BOSS
        bne     :+
        ldy     #9
:       sty     g_nr
        jsr     draw_diamond
        ldx     map_tmp+1               ; the player's sector: a second diamond inside
        lda     node_col_of,x
        cmp     map_col
        bne     :+
        lda     node_row_of,x
        cmp     map_row
        bne     :+
        lda     #2
        sta     g_nr
        jsr     draw_diamond
:       ldx     map_tmp+1
@nonode:
        dex
        bpl     @node
        rts

; node_xy: g_nx, g_ny = the centre of node X. Keeps X.
node_xy:
        ldy     node_row_of,x
        lda     map_y,y
        sta     g_ny
        ldy     node_col_of,x
        lda     map_x,y
        sta     g_nx
        rts

; draw_diamond: radius g_nr around (g_nx, g_ny).
draw_diamond:
        lda     g_nx                    ; left - top - right - bottom - left
        sec
        sbc     g_nr
        sta     g_dl
        lda     g_nx
        clc
        adc     g_nr
        sta     g_dr
        lda     g_ny
        sec
        sbc     g_nr
        sta     g_dt
        lda     g_ny
        clc
        adc     g_nr
        sta     g_db
        lda     g_dl
        ldx     g_ny
        ldy     g_nx
        jsr     @seg_top
        lda     g_dr
        ldx     g_ny
        jsr     @seg_top
        lda     g_dl
        ldx     g_ny
        jsr     @seg_bottom
        lda     g_dr
        ldx     g_ny
        jmp     @seg_bottom
@seg_top:                               ; (A, X) to the top point
        sta     lx0
        stx     ly0
        lda     g_nx
        sta     lx1
        lda     g_dt
        sta     ly1
        jmp     draw_line_marked
@seg_bottom:
        sta     lx0
        stx     ly0
        lda     g_nx
        sta     lx1
        lda     g_db
        sta     ly1
        jmp     draw_line_marked
