; High scores: a top-10 table with initials, kept in the file "GA SCORES" on the disk the
; game was loaded from (device 8). The title shows it in turn with the turning ship; a
; score that makes the table asks for initials at the end of a game and saves the table.
;
; Disk access goes through the KERNAL: interrupts off, the KERNAL's own zero page (saved
; at start-up) swapped in for the game's, the KERNAL ROM switched in, and everything put
; back after. No drive or no disk: the panel says so and the table lives on in memory.

HS_COUNT        = 10
HS_SIZE         = 6                     ; name (3 screen codes), score (3 bytes)
NAME_LEN        = 3

KERNAL_SETLFS   = $FFBA
KERNAL_SETNAM   = $FFBD
KERNAL_OPEN     = $FFC0
KERNAL_CLOSE    = $FFC3
KERNAL_LOAD     = $FFD5
KERNAL_SAVE     = $FFD8
KERNAL_FREE_ZP  = $FB                   ; two bytes the KERNAL leaves to programs

        .segment "BSS"
game_zp:        .res 254                ; the game's, while the KERNAL works
hs_table:       .res HS_COUNT * HS_SIZE
hs_table_end:
name_buf:       .res NAME_LEN
disk_status:    .res 1                  ; 0 = the last load or save worked
hs_place:       .res 1
hs_off:         .res 1
hs_tmp:         .res 2
name_pos:       .res 1
bt_col:         .res 1                  ; draw_char's cell
bt_row:         .res 1

        .segment "RODATA"
fname_scores:   .byte "GA SCORES"
FNAME_LEN = * - fname_scores
fname_scratch:  .byte "S0:GA SCORES"
SCRATCH_LEN = * - fname_scratch
txt_hs_head:    scr "HIGH SCORES"
                .byte 0
txt_newhigh:    scr "NEW HIGH SCORE   NAME"
                .byte 0
txt_saving:     scr "SAVING"
                .byte 0
txt_saved:      scr "SCORES SAVED"
                .byte 0
txt_nodisk:     scr "NO DISK - SCORES KEPT IN MEMORY"
                .byte 0

        .segment "CODE"

        .segment "HIBSS2"               ; (written before BSS is free: see cfg/game.cfg)
kernal_zp:      .res 254                ; $02-$FF as the KERNAL left them at start-up
        .segment "CODE"

; keep_kernal_zp: the very first thing at start-up: the KERNAL's zero page, for disk use.
keep_kernal_zp:
        ldx     #253
:       lda     $02,x
        sta     kernal_zp,x
        dex
        cpx     #$FF
        bne     :-
        rts

; hs_boot: the default table, then the disk's if there is one.
hs_boot:
        jsr     hs_defaults
        jmp     hs_load

hs_defaults:
        ldx     #HS_COUNT*HS_SIZE-1
:       lda     hs_default,x
        sta     hs_table,x
        dex
        bpl     :-
        rts

; disk_begin / disk_end: around KERNAL calls.
disk_begin:
        sei
        lda     #0                      ; no raster interrupts while the KERNAL runs
        sta     VIC_IRQ_MASK
        lda     #$FF
        sta     VIC_IRQ_FLAGS
        ldx     #253                    ; the game's zero page out, the KERNAL's in
:       lda     $02,x
        sta     game_zp,x
        lda     kernal_zp,x
        sta     $02,x
        dex
        cpx     #$FF
        bne     :-
        lda     #$36                    ; the KERNAL ROM in, BASIC out
        sta     CPU_PORT
        rts

disk_end:
        sei
        lda     #$35                    ; back to RAM everywhere but I/O
        sta     CPU_PORT
        ldx     #253
:       lda     game_zp,x
        sta     $02,x
        dex
        cpx     #$FF
        bne     :-
        lda     #$7F                    ; the CIAs quiet again (the KERNAL may have woken them)
        sta     CIA1_ICR
        sta     CIA2_ICR
        lda     CIA1_ICR
        lda     CIA2_ICR
        lda     #0
        sta     $DC02                   ; port A: the joystick alone
        lda     #$01
        sta     VIC_IRQ_FLAGS
        sta     VIC_IRQ_MASK
        cli
        rts

; hs_load: the table from the disk; disk_status = 0 when that worked.
hs_load:
        jsr     disk_begin
        lda     #1
        ldx     #8
        ldy     #0                      ; load to the table, wherever this build keeps it
        jsr     KERNAL_SETLFS
        lda     #FNAME_LEN
        ldx     #<fname_scores
        ldy     #>fname_scores
        jsr     KERNAL_SETNAM
        lda     #0
        ldx     #<hs_table
        ldy     #>hs_table
        jsr     KERNAL_LOAD
        lda     #0
        rol                             ; carry set = an error
        sta     disk_status
        jmp     disk_end

; hs_save: the table to the disk (the old file scratched first).
hs_save:
        jsr     disk_begin
        lda     #15                     ; OPEN 15,8,15,"S0:GA SCORES" : CLOSE 15
        ldx     #8
        ldy     #15
        jsr     KERNAL_SETLFS
        lda     #SCRATCH_LEN
        ldx     #<fname_scratch
        ldy     #>fname_scratch
        jsr     KERNAL_SETNAM
        jsr     KERNAL_OPEN
        lda     #1
        bcs     @fail
        lda     #15
        jsr     KERNAL_CLOSE
        lda     #1
        ldx     #8
        ldy     #0
        jsr     KERNAL_SETLFS
        lda     #FNAME_LEN
        ldx     #<fname_scores
        ldy     #>fname_scores
        jsr     KERNAL_SETNAM
        lda     #<hs_table
        sta     KERNAL_FREE_ZP
        lda     #>hs_table
        sta     KERNAL_FREE_ZP+1
        lda     #KERNAL_FREE_ZP
        ldx     #<hs_table_end
        ldy     #>hs_table_end
        jsr     KERNAL_SAVE
        lda     #0
        rol
@fail:  sta     disk_status
        jmp     disk_end

; hs_rank: A = the place (0-9) the current score takes in the table, or 10 if none.
hs_rank:
        ldx     #0
        ldy     #3                      ; Y = offset of entry X's score
@e:     lda     score+2
        cmp     hs_table+2,y
        bcc     @lower
        bne     @found
        lda     score+1
        cmp     hs_table+1,y
        bcc     @lower
        bne     @found
        lda     score
        cmp     hs_table,y
        bcc     @lower
        beq     @lower                  ; equal: the older score stays ahead
@found: txa
        rts
@lower: tya
        clc
        adc     #HS_SIZE
        tay
        inx
        cpx     #HS_COUNT
        bne     @e
        txa
        rts

; hs_insert: puts name_buf and the score at place A, moving the rest down.
hs_insert:
        sta     hs_place
        tax                             ; offset of the place
        lda     #0
:       cpx     #0
        beq     :+
        clc
        adc     #HS_SIZE
        dex
        bne     :-
:       sta     hs_off
        ldx     #(HS_COUNT-1)*HS_SIZE-1 ; move entries down from the end
:       cpx     hs_off
        bcc     :+
        lda     hs_table,x
        sta     hs_table+HS_SIZE,x
        dex
        cpx     #$FF
        bne     :-
:       ldx     hs_off
        lda     name_buf
        sta     hs_table,x
        lda     name_buf+1
        sta     hs_table+1,x
        lda     name_buf+2
        sta     hs_table+2,x
        lda     score
        sta     hs_table+3,x
        lda     score+1
        sta     hs_table+4,x
        lda     score+2
        sta     hs_table+5,x
        rts

; ---------------------------------------------------------------------------------------
; Initials: up and down change the letter, fire takes it.

name_start:
        lda     #STATE_NAME
        sta     state
        lda     #1                      ; "A" in the first place
        sta     name_buf
        lda     #$20
        sta     name_buf+1
        sta     name_buf+2
        lda     #0
        sta     name_pos
        sta     fire_new
        lda     joy
        sta     joy_last
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 6, txt_newhigh
        jmp     name_show

name_show:
        set_pos PANEL_ROW+2, 28
        ldy     #0
:       lda     name_buf,y
        jsr     put_char
        iny
        cpy     #NAME_LEN
        bne     :-
        rts

name_tick:
        lda     #2
        jsr     stars_tick
        lda     joy                     ; newly pressed directions
        tax
        eor     joy_last
        stx     joy_last
        and     joy
        sta     hs_tmp
        ldx     name_pos
        lda     hs_tmp
        and     #%00001                 ; up: the next letter
        beq     :+
        lda     name_buf,x
        cmp     #$20
        bne     @up
        lda     #0
@up:    clc
        adc     #1
        cmp     #27
        bcc     @set
        lda     #1
        bne     @set
:       lda     hs_tmp
        and     #%00010                 ; down: the one before
        beq     @fire
        lda     name_buf,x
        cmp     #$20
        bne     @down
        lda     #27
@down:  sec
        sbc     #1
        bne     @set
        lda     #26
@set:   sta     name_buf,x
        jsr     name_show
@fire:  lda     fire_new
        bne     :+
        rts
:       lda     #0
        sta     fire_new
        ldx     name_pos
        lda     name_buf,x
        cmp     #$20
        bne     :+
        lda     #1
        sta     name_buf,x
:       inc     name_pos
        ldx     name_pos
        cpx     #NAME_LEN
        bcs     @taken
        lda     #1
        sta     name_buf,x
        jmp     name_show
@taken: jsr     hs_rank
        jsr     hs_insert
        print_at PANEL_ROW+2, 1, txt_blank
        print_at PANEL_ROW+2, 17, txt_saving
        jsr     hs_save
        print_at PANEL_ROW+2, 1, txt_blank
        lda     disk_status
        bne     :+
        print_at PANEL_ROW+2, 14, txt_saved
        jmp     title_scores
:       print_at PANEL_ROW+2, 4, txt_nodisk
        jmp     title_scores

; ---------------------------------------------------------------------------------------
; The table on the title, drawn as text into the bitmap.

draw_scores:
        lda     #11
        sta     bt_col
        lda     #3
        sta     bt_row
        lda     #<txt_hs_head
        sta     str_ptr
        lda     #>txt_hs_head
        sta     str_ptr+1
        jsr     draw_text
        lda     #0
        sta     hs_place
@line:  lda     hs_place                ; "01 ACE 005000"
        clc
        adc     #5
        sta     bt_row
        lda     #9
        sta     bt_col
        lda     hs_place
        clc
        adc     #1
        sta     num
        lda     #0
        sta     num+1
        sta     num+2
        jsr     to_decimal
        lda     digits+4
        jsr     draw_char
        lda     digits+5
        jsr     draw_char
        inc     bt_col
        lda     hs_place                ; offset of the entry
        asl
        adc     hs_place
        asl
        sta     hs_off
        tax
        lda     hs_table,x
        jsr     draw_char
        ldx     hs_off
        lda     hs_table+1,x
        jsr     draw_char
        ldx     hs_off
        lda     hs_table+2,x
        jsr     draw_char
        inc     bt_col
        ldx     hs_off
        lda     hs_table+3,x
        sta     num
        lda     hs_table+4,x
        sta     num+1
        lda     hs_table+5,x
        sta     num+2
        jsr     to_decimal
        ldx     #0
:       lda     digits,x
        stx     hs_tmp
        jsr     draw_char
        ldx     hs_tmp
        inx
        cpx     #6
        bne     :-
        inc     hs_place
        lda     hs_place
        cmp     #HS_COUNT
        beq     :+
        jmp     @line
:       rts

; draw_text: the zero-terminated string at str_ptr at cell (bt_col, bt_row).
draw_text:
        ldy     #0
:       lda     (str_ptr),y
        beq     :+
        sty     hs_tmp+1
        jsr     draw_char
        ldy     hs_tmp+1
        iny
        bne     :-
:       rts

; draw_char: screen code A into the back buffer's cell (bt_col, bt_row), then bt_col + 1.
draw_char:
        asl                             ; glyph = font + code * 8
        asl
        asl
        sta     bt_src
        lda     #0
        rol
        sta     bt_src+1
        lda     bt_src
        clc
        adc     #<font
        sta     bt_src
        lda     bt_src+1
        adc     #>font
        sta     bt_src+1
        lda     bt_row                  ; cell = row base + col * 8
        asl
        asl
        asl
        tay
        lda     bt_col
        asl
        asl
        asl
        clc
        adc     row_lo,y
        sta     ptr
        lda     row_hi,y
        adc     #0
        ora     bufhi
        sta     ptr+1
        ldy     #7
:       lda     (bt_src),y
        sta     (ptr),y
        dey
        bpl     :-
        lda     bt_col                  ; dirty
        clc
        adc     dirty_off
        tay
        lda     bt_row
        cmp     dirty_min,y
        bcs     :+
        sta     dirty_min,y
:       cmp     dirty_max,y
        bcc     :+
        sta     dirty_max,y
:       inc     bt_col
        rts

.ifdef TEST_DISK
; Disk tests, run with a disk in drive 8. TEST_DISK = 1 saves a table whose first entry is
; "TST" 12,345 (result 0 when the save worked); TEST_DISK = 2 loads the table and checks
; that entry (0 = found, 1 = a different table, 2 = the load failed).
test_disk:
  .if TEST_DISK = 3
        jsr     hs_defaults
        lda     #<4200                  ; rank and insert: 4,200 goes third
        sta     score
        lda     #>4200
        sta     score+1
        lda     #0
        sta     score+2
        jsr     hs_rank
        cmp     #2
        bne     @bad
        lda     #7                      ; "GAL"
        sta     name_buf
        lda     #1
        sta     name_buf+1
        lda     #12
        sta     name_buf+2
        lda     #2
        jsr     hs_insert
        ldx     #HS_SIZE*4-1            ; entries 0-3 = ACE VEX GAL ORB, entry 9 = ION
:       lda     hs_table,x
        cmp     @want3,x
        bne     @bad
        dex
        bpl     :-
        lda     hs_table+9*HS_SIZE
        cmp     #9                      ; "I"
        bne     @bad
        lda     #0
        sta     DEBUGCART_RESULT
@bad:   lda     #1
        sta     DEBUGCART_RESULT
@want3: .byte   1, 3, 5, <5000, >5000, 0
        .byte   22, 5, 24, <4500, >4500, 0
        .byte   7, 1, 12, <4200, >4200, 0
        .byte   15, 18, 2, <4000, >4000, 0
  .elseif TEST_DISK = 1
        lda     #<12345
        sta     hs_table+3
        lda     #>12345
        sta     hs_table+4
        lda     #0
        sta     hs_table+5
        lda     #20                     ; T S T
        sta     hs_table
        lda     #19
        sta     hs_table+1
        lda     #20
        sta     hs_table+2
        jsr     hs_save
        lda     disk_status
        sta     DEBUGCART_RESULT
  .else
        jsr     hs_load
        lda     disk_status
        beq     :+
        lda     #2
        sta     DEBUGCART_RESULT
:       ldx     #5
:       lda     hs_table,x
        cmp     @want,x
        bne     @wrong
        dex
        bpl     :-
        lda     #0
        sta     DEBUGCART_RESULT
@wrong: lda     #1
        sta     DEBUGCART_RESULT
@want:  .byte   20, 19, 20, <12345, >12345, 0
  .endif
:       jmp     :-
.endif
