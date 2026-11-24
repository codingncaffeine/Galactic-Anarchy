; Credits and the dock. Kills, cleared sectors, a destroyed Dreadnought and escorts earn
; credits; after every sector the dock opens on the panel (over the map) and sells shield
; repairs, shield cells (one more block, up to SHIELD_MOST) and gun upgrades:
;   gun 1: shots take two hit points; gun 2: and the gun fires again sooner.
; Up and down choose, fire buys; "leave the dock" goes on to the map.

SHIELD_MOST     = 7                     ; the panel has room for seven blocks
GUN_MOST        = 2
CR_KILL         = 1                     ; credits: a kill (two for a ship worth 250+)
CR_SECTOR       = 5                     ; a sector's quota met
CR_BOSS         = 20                    ; the Dreadnought destroyed
CR_ESCORT       = 15                    ; an escort won
CR_FREIGHTER    = 2                     ; a freighter escorted across
SHOP_ITEMS      = 4                     ; repair, cell, gun, leave
SHOP_LEAVE      = 3

        .segment "BSS"
credits:        .res 1
gun:            .res 1                  ; 0-GUN_MOST
shield_max:     .res 1
shop_sel:       .res 1

        .segment "RODATA"
shop_name_lo:   .byte <txt_repair, <txt_cell, <txt_gun, <txt_leave
shop_name_hi:   .byte >txt_repair, >txt_cell, >txt_gun, >txt_leave
txt_repair:     scr "REPAIR SHIELD   "
                .byte 0
txt_cell:       scr "SHIELD CELL     "
                .byte 0
txt_gun:        scr "GUN UPGRADE     "
                .byte 0
txt_leave:      scr "LEAVE THE DOCK  "
                .byte 0
txt_dock:       scr "DOCK"
                .byte 0
txt_cost:       scr "COST"
                .byte 0
txt_dash:       scr "--"
                .byte 0
txt_dock_help:  scr "UP DOWN  FIRE BUYS      "
                .byte 0
gun_repeat:     .byte 10, 10, 6         ; FIRE_REPEAT by gun level
gun_price:      .byte 30, 60
        .segment "CODE"

; shop_reset: a new game's ship.
shop_reset:
        lda     #0
        sta     credits
        sta     gun
        lda     #SHIELD_FULL
        sta     shield_max
        rts

; credit_add: credits += A, up to 255. Keeps X and Y.
credit_add:
        clc
        adc     credits
        bcc     :+
        lda     #255
:       sta     credits
        lda     #1
        sta     panel_dirty
        rts

; credit_kill: the player destroyed a ship of kind Y. Keeps X and Y.
credit_kill:
        lda     kind_score,y
        cmp     #25
        lda     #CR_KILL
        adc     #0                      ; one more for the big ones (carry from cmp)
        jmp     credit_add

; sector_won: the quota met: credits, and in an escort the convoy's thanks.
sector_won:
        lda     #CR_SECTOR
        jsr     credit_add
        lda     mission
        cmp     #MIS_ESCORT
        bne     :+
        lda     #CR_ESCORT
        jsr     credit_add
:       jmp     escort_won

; dock_start: the map, with the dock open on the panel.
dock_start:
        jsr     map_start
        lda     demo                    ; (the demo never stops here)
        beq     :+
        rts
:       lda     #STATE_SHOP
        sta     state
        lda     #0
        sta     cross_vis
        lda     #SHOP_LEAVE             ; repairs first when the shield needs them
        ldx     shield
        cpx     shield_max
        bcs     :+
        lda     #0
:       sta     shop_sel
        print_at PANEL_ROW+3, 1, txt_dock_help
        ; fall through

; shop_show: the chosen item and its price on the panel.
shop_show:
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 1, txt_dock
        ldx     shop_sel
        lda     shop_name_lo,x
        sta     str_ptr
        lda     shop_name_hi,x
        sta     str_ptr+1
        set_pos PANEL_ROW+2, 7
        jsr     print_str
        lda     shop_sel
        cmp     #SHOP_LEAVE
        beq     @done
        print_at PANEL_ROW+2, 25, txt_cost
        jsr     shop_price
        bcc     :+
        print_at PANEL_ROW+2, 30, txt_dash
        jmp     @done
:       pha
        set_pos PANEL_ROW+2, 30
        pla
        jsr     print_2digits
@done:  lda     #1
        sta     panel_dirty
        rts

; shop_price: A = the price of item shop_sel, carry clear; carry set when it cannot be
; bought (the shield full, no more cells or upgrades).
shop_price:
        ldx     shop_sel
        bne     :+
        lda     shield                  ; repair
        cmp     shield_max
        bcs     @no
        lda     #4
        rts
:       dex
        bne     :+
        lda     shield_max              ; a shield cell
        cmp     #SHIELD_MOST
        bcs     @no
        lda     #25
        rts
:       ldx     gun                     ; a gun upgrade
        cpx     #GUN_MOST
        bcs     @no
        lda     gun_price,x
        clc
        rts
@no:    sec
        rts

shop_tick:
.ifdef TEST_PLAY
        lda     #SHOP_LEAVE             ; the test builds leave at once
        sta     shop_sel
        lda     #1
        sta     fire_new
.endif
        lda     #2
        jsr     stars_tick
        jsr     joy_pressed             ; up / down, newly pressed: another item
        tax
        and     #%00001
        beq     :+
        dec     shop_sel
        bpl     @moved
        lda     #SHOP_ITEMS-1
        sta     shop_sel
        bpl     @moved
:       txa
        and     #%00010
        beq     @fire
        inc     shop_sel
        lda     shop_sel
        cmp     #SHOP_ITEMS
        bcc     @moved
        lda     #0
        sta     shop_sel
@moved: jmp     shop_show
@fire:  lda     fire_new
        beq     @done
        lda     #0
        sta     fire_new
        lda     shop_sel
        cmp     #SHOP_LEAVE
        beq     @leave
        jsr     shop_price
        bcs     @refuse
        sta     g_tmp
        lda     credits
        sec
        sbc     g_tmp
        bcc     @refuse
        sta     credits
        ldx     shop_sel                ; bought
        bne     :+
        inc     shield
        jmp     @bought
:       dex
        bne     :+
        inc     shield_max
        inc     shield
        jmp     @bought
:       inc     gun
@bought:
        jsr     sfx_charged
        jmp     shop_show
@refuse:
        jmp     sfx_shield
@leave: lda     #STATE_MAP
        sta     state
        lda     #1
        sta     cross_vis
        print_at PANEL_ROW+3, 1, txt_kills
        jmp     map_show_choice
@done:  rts
