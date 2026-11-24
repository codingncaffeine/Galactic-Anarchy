; Galactic Anarchy: start-up and the engine benchmark.
;
; Takes over the machine (ROMs banked out, CIA interrupts off), sets up the two frame
; buffers and the raster interrupts that show the vector viewport above a text panel,
; then draws spinning test models and shows how long each stage of a frame takes.
;
; Build options (ca65 -D):
;   TEST_IRQ=1   pass (0 to $D7FF, Kernal64's debug-cartridge port) once the raster
;                interrupt has counted 50 frames
;   NO_IRQ=1     never start the raster interrupt (control for TEST_IRQ: must time out)
;   TEST_MUL=1   check the fast multiply against shift-and-add for all 65,536 pairs
;   BREAK_MUL=1  corrupt one multiply table entry first (control for TEST_MUL: must fail)
;   BENCH=n      run scene n for two measuring windows, store the second window's figures
;                at RESULTS and pass
;   NO_CLIP=1    drop edges with an end off the viewport (control for the clipping check)
;   NO_HIDDEN=1  draw hidden edges too (control for the hidden-line check)
; Without options it is the playable benchmark: the fire button cycles the scenes.

        .include "hw.inc"
        .include "engine.inc"

        .segment "STARTUP"              ; at 2061, where the BASIC line jumps
        jmp     start

        .include "math.s"
        .include "gfx.s"
        .include "xform.s"
        .include "clip.s"
        .include "panel.s"
        .include "vars.inc"

        .segment "LOADADDR"
        .word   $0801

        .segment "EXEHDR"
; 10 SYS 2061
        .word   @next
        .word   10
        .byte   $9E, "2061", 0
@next:  .word   0

WINDOW = 32                             ; drawn frames per measuring window

        .segment "ZEROPAGE"
frame:          .res 2                  ; counted by the raster interrupt
flip_pending:   .res 1
flip_bits:      .res 1
back:           .res 1                  ; buffer being drawn: 0 or 1
scene:          .res 1
fire_was:       .res 1
drawn:          .res 1
win_start:      .res 2
windows:        .res 1
tm:             .res 3                  ; timer reading (counts down)
tm_prev:        .res 3
sum_clear:      .res 3
sum_xform:      .res 3
sum_draw:       .res 3
div_n:          .res 2
div_d:          .res 2
div_r:          .res 2
roster_item:    .res 1
roster_timer:   .res 1

        .segment "CODE"
start:
        sei
        cld
        ldx     #$FF
        txs
.ifndef BENCH
        jsr     keep_kernal_zp          ; before anything uses zero page
.endif
        lda     #$35                    ; RAM everywhere except I/O at $D000
        sta     CPU_PORT
        lda     #$7F                    ; silence both CIAs' interrupts
        sta     CIA1_ICR
        sta     CIA2_ICR
        lda     CIA1_ICR
        lda     CIA2_ICR
        lda     #COLOR_BLACK
        sta     VIC_BORDER
        sta     VIC_BG0
        jsr     copy_tables
        jsr     start_timer
        jsr     init_display

        lda     CIA2_PRA                ; show buffer 0
        and     #$FC
        ora     #BUF0_BANK_BITS
        sta     CIA2_PRA
        lda     #D018_BITMAP
        sta     VIC_MEM
        lda     #D011_BITMAP
        sta     VIC_CTRL1

        lda     #<nmi_ignore
        sta     NMI_VECTOR
        lda     #>nmi_ignore
        sta     NMI_VECTOR+1
        lda     #0
        sta     frame
        sta     frame+1
        sta     flip_pending
.ifndef BENCH
        sta     game_on                 ; until the game has set itself up
.endif
        lda     #1
        sta     back

.ifndef NO_IRQ
        lda     #<irq_top               ; with the KERNAL banked out, the CPU takes
        sta     IRQ_VECTOR              ; its interrupt vector from RAM at $FFFE
        lda     #>irq_top
        sta     IRQ_VECTOR+1
        lda     #TOP_LINE
        sta     VIC_RASTER
        lda     #$01                    ; raster interrupt on
        sta     VIC_IRQ_MASK
        sta     VIC_IRQ_FLAGS
        cli
.endif

.ifdef TEST_IRQ
:       lda     frame
        cmp     #50
        bcc     :-
        lda     #0
        sta     DEBUGCART_RESULT
:       jmp     :-
.endif

.ifdef TEST_MUL
        jmp     mul_test
.endif

        lda     #0
        sta     roster_item
.ifdef BENCH
  .ifdef ROSTER_ITEM
        lda     #ROSTER_ITEM
        sta     roster_item
  .endif
        lda     #BENCH
        jsr     start_scene
.else
        jmp     game_main               ; the play build is the game
.endif

; ---------------------------------------------------------------------------------------
frame_loop:
:       lda     flip_pending            ; wait until the last frame is on display
        bne     :-

        ldx     back
        lda     bufhi_of,x
        sta     bufhi
        lda     dirty_off_of,x
        sta     dirty_off

        jsr     read_timer
        jsr     timer_to_prev
        jsr     clear_back
        jsr     read_timer
        ldx     #sum_clear
        jsr     add_elapsed
        jsr     spin_objects
        jsr     transform_all
        jsr     read_timer
        ldx     #sum_xform
        jsr     add_elapsed
        jsr     draw_edges
        jsr     read_timer
        ldx     #sum_draw
        jsr     add_elapsed

        ldx     back                    ; show it at the next vertical blank
        lda     bank_bits_of,x
        sta     flip_bits
        lda     #1
        sta     flip_pending
        txa
        eor     #1
        sta     back

        inc     drawn
        lda     drawn
        cmp     #WINDOW
        bne     @no_window
        jsr     end_window
@no_window:
.ifndef BENCH
        jsr     roster_tick
        lda     CIA1_PRA                ; fire, newly pressed: next scene
        and     #JOY_FIRE
        eor     #JOY_FIRE               ; 1 = pressed
        tax
        eor     fire_was
        and     #JOY_FIRE
        stx     fire_was
        beq     :+
        txa
        beq     :+
        ldx     scene
        inx
        cpx     #SCENE_COUNT+1
        bcc     @set
        ldx     #1
@set:   txa
        jsr     start_scene
:
.endif
        jmp     frame_loop

; end_window: the averages of the last WINDOW drawn frames go to the panel.
end_window:
        lda     #0
        sta     drawn
        sec                             ; frames elapsed over the window
        lda     frame
        sbc     win_start
        sta     num
        lda     frame+1
        sbc     win_start+1
        sta     num+1
        lda     frame
        sta     win_start
        lda     frame+1
        sta     win_start+1
.ifdef BENCH
        inc     windows
        lda     windows
        cmp     #2
        bne     :+
        jmp     bench_done
:
.endif
        jsr     show_fps
        set_pos PANEL_ROW+3, 7
        ldx     #sum_clear
        jsr     show_average
        set_pos PANEL_ROW+3, 19
        ldx     #sum_xform
        jsr     show_average
        set_pos PANEL_ROW+3, 32
        ldx     #sum_draw
        jsr     show_average
        jmp     clear_sums

; show_average: the 24-bit sum at zero page X, divided by WINDOW (32), as 6 digits.
show_average:
        lda     0,x
        sta     num
        lda     1,x
        sta     num+1
        lda     2,x
        sta     num+2
        ldy     #5
:       lsr     num+2
        ror     num+1
        ror     num
        dey
        bne     :-
        jsr     to_decimal
        lda     #6
        jmp     put_digits

; show_fps: num = frames elapsed over the window. Frames per second, times ten, is
; WINDOW * rate * 10 / elapsed with rate 50 (PAL) or 60 (NTSC).
show_fps:
        lda     num
        sta     div_d
        lda     num+1
        sta     div_d+1
        lda     #<(WINDOW*500)
        ldy     #>(WINDOW*500)
        ldx     PAL_FLAG
        bne     :+
        lda     #<(WINDOW*600)
        ldy     #>(WINDOW*600)
:       sta     div_n
        sty     div_n+1
        jsr     divide16
        lda     div_n
        sta     num
        lda     div_n+1
        sta     num+1
        lda     #0
        sta     num+2
        jsr     to_decimal
        set_pos PANEL_ROW+1, 25         ; tens and units, a point, tenths
        ldy     #0
        lda     digits+3
        jsr     put_char
        iny
        lda     digits+4
        jsr     put_char
        iny
        lda     #'.'
        jsr     put_char
        iny
        lda     digits+5
        jmp     put_char

; divide16: div_n = div_n / div_d (16 bit, unsigned), remainder discarded.
divide16:
        lda     #0
        sta     div_r
        sta     div_r+1
        ldx     #16
:       asl     div_n
        rol     div_n+1
        rol     div_r
        rol     div_r+1
        lda     div_r
        sec
        sbc     div_d
        tay
        lda     div_r+1
        sbc     div_d+1
        bcc     @skip
        sta     div_r+1
        sty     div_r
        inc     div_n
@skip:  dex
        bne     :-
        rts

clear_sums:
        lda     #0
        ldx     #8
:       sta     sum_clear,x
        dex
        bpl     :-
        rts

.ifdef BENCH
; bench_done: the second window's figures to RESULTS, then the test result.
bench_done:
        lda     scene
        sta     RESULTS+0
        lda     edge_total
        sta     RESULTS+1
        lda     num
        sta     RESULTS+2
        lda     num+1
        sta     RESULTS+3
        ldx     #8
:       lda     sum_clear,x
        sta     RESULTS+4,x
        dex
        bpl     :-
        lda     #0
        sta     DEBUGCART_RESULT
:       jmp     :-
.endif

; ---------------------------------------------------------------------------------------
; CIA 2's timers as one 24-bit cycle counter: timer A counts cycles down from $FFFF,
; timer B counts timer A's underflows.
start_timer:
        lda     #$FF
        sta     CIA2_TA_LO
        sta     CIA2_TA_HI
        sta     CIA2_TB_LO
        sta     CIA2_TB_HI
        lda     #%01010001              ; B: count A's underflows, load, start
        sta     CIA2_CRB
        lda     #%00010001              ; A: count cycles, continuous, load, start
        sta     CIA2_CRA
        rts

; read_timer: tm = the counter, read again if it moved between the bytes.
read_timer:
        lda     CIA2_TB_LO
        sta     tm+2
        lda     CIA2_TA_HI
        sta     tm+1
        lda     CIA2_TA_LO
        sta     tm
        lda     CIA2_TA_HI
        cmp     tm+1
        bne     read_timer
        lda     CIA2_TB_LO
        cmp     tm+2
        bne     read_timer
        rts

timer_to_prev:
        lda     tm
        sta     tm_prev
        lda     tm+1
        sta     tm_prev+1
        lda     tm+2
        sta     tm_prev+2
        rts

; add_elapsed: the sum at zero page X += tm_prev - tm (the counter counts down);
; then tm_prev = tm.
add_elapsed:
        sec
        lda     tm_prev
        sbc     tm
        sta     m_a
        lda     tm_prev+1
        sbc     tm+1
        sta     m_b
        lda     tm_prev+2
        sbc     tm+2
        tay
        clc
        lda     0,x
        adc     m_a
        sta     0,x
        lda     1,x
        adc     m_b
        sta     1,x
        tya
        adc     2,x
        sta     2,x
        jmp     timer_to_prev

; ---------------------------------------------------------------------------------------
irq_top:
        pha
        txa
        pha
        tya
        pha
        lda     #D011_BITMAP
        sta     VIC_CTRL1
        lda     #D018_BITMAP
        sta     VIC_MEM
        lda     flip_pending
        beq     :+
        lda     CIA2_PRA
        and     #$FC
        ora     flip_bits
        sta     CIA2_PRA
        lda     #0
        sta     flip_pending
:       inc     frame
        bne     :+
        inc     frame+1
:       lda     #SPLIT_LINE
        sta     VIC_RASTER
        lda     #<irq_split
        sta     IRQ_VECTOR
        lda     #>irq_split
        sta     IRQ_VECTOR+1
        lda     #$01
        sta     VIC_IRQ_FLAGS
.ifndef BENCH
        lda     game_on                 ; the game's 50/60 Hz work
        beq     :+
        cli                             ; (the split interrupt may come during it)
        jsr     irq_game
:
.endif
        pla
        tay
        pla
        tax
        pla
nmi_ignore:
        rti

irq_split:
        pha
        lda     #D011_TEXT
        sta     VIC_CTRL1
        lda     #D018_TEXT
        sta     VIC_MEM
        lda     #TOP_LINE
        sta     VIC_RASTER
        lda     #<irq_top
        sta     IRQ_VECTOR
        lda     #>irq_top
        sta     IRQ_VECTOR+1
        lda     #$01
        sta     VIC_IRQ_FLAGS
        pla
        rti

; ---------------------------------------------------------------------------------------
init_display:
        lda     #BUF0_BITMAP_HI         ; both bitmaps empty
        ldx     #32
        jsr     clear_pages
        lda     #BUF1_BITMAP_HI
        ldx     #32
        jsr     clear_pages
        jsr     reset_dirty

        ldx     #0                      ; panel rows 20-24 (200 bytes): spaces, cyan
:       lda     #$20
        sta     BUF0_SCREEN+PANEL_ROW*40,x
        sta     BUF1_SCREEN+PANEL_ROW*40,x
        lda     #COLOR_CYAN
        sta     COLOR_RAM+PANEL_ROW*40,x
        inx
        cpx     #200
        bne     :-

        lda     #0                      ; rows 0-19: white lines on black in the viewport
        sta     cnt
        lda     #<BUF0_SCREEN
        sta     ptr
        lda     #>BUF0_SCREEN
        sta     ptr+1
@row:   ldy     #39
:       lda     #$00
        cpy     #VIEW_LEFT_CELLS
        bcc     @set
        cpy     #VIEW_LEFT_CELLS+32
        bcs     @set
        lda     #COLOR_WHITE<<4
@set:   sta     (ptr),y
        pha
        lda     ptr+1                   ; the same cell of buffer 1's screen
        eor     #(>BUF0_SCREEN) ^ (>BUF1_SCREEN)
        sta     ptr+1
        pla
        sta     (ptr),y
        lda     ptr+1
        eor     #(>BUF0_SCREEN) ^ (>BUF1_SCREEN)
        sta     ptr+1
        dey
        bpl     :-
        lda     ptr
        clc
        adc     #40
        sta     ptr
        bcc     :+
        inc     ptr+1
:       inc     cnt
        lda     cnt
        cmp     #VIEW_ROWS
        bne     @row

        ldx     #0                      ; the font for the panel, in both banks
:       lda     font,x
        sta     BUF0_FONT,x
        sta     BUF1_FONT,x
        lda     font+256,x
        sta     BUF0_FONT+256,x
        sta     BUF1_FONT+256,x
        inx
        bne     :-
        rts

; copy_tables: the TABLES segment from where it was loaded to $9000.
        .import __TABLES_LOAD__, __TABLES_RUN__, __TABLES_SIZE__, __BSS_SIZE__
copy_tables:
        lda     #<__TABLES_LOAD__
        sta     str_ptr
        lda     #>__TABLES_LOAD__
        sta     str_ptr+1
        lda     #<__TABLES_RUN__
        sta     ptr
        lda     #>__TABLES_RUN__
        sta     ptr+1
        ldx     #>(__TABLES_SIZE__ + 255)
        ldy     #0
:       lda     (str_ptr),y
        sta     (ptr),y
        iny
        bne     :-
        inc     str_ptr+1
        inc     ptr+1
        dex
        bne     :-
        rts

; clear_pages: X pages of zeros from page A.
clear_pages:
        sta     ptr+1
        lda     #0
        sta     ptr
        tay
:       sta     (ptr),y
        iny
        bne     :-
        inc     ptr+1
        dex
        bne     :-
        rts

; ---------------------------------------------------------------------------------------
; start_scene: A = scene number (1-SCENE_COUNT). Loads its objects and the panel.
start_scene:
        sta     scene
        cmp     #SCENE_ROSTER
        bne     :+
        jsr     roster_setup
        jmp     @loaded
:       tax
        lda     scene_lo-1,x
        sta     str_ptr
        lda     scene_hi-1,x
        sta     str_ptr+1
        ldy     #0
        lda     (str_ptr),y
        sta     obj_count
        iny
        ldx     #0
@obj:   cpx     obj_count
        beq     @loaded
        lda     (str_ptr),y
        sta     obj_model,x
        iny
        lda     (str_ptr),y
        sta     obj_x_lo,x
        iny
        lda     (str_ptr),y
        sta     obj_x_hi,x
        iny
        lda     (str_ptr),y
        sta     obj_y_lo,x
        iny
        lda     (str_ptr),y
        sta     obj_y_hi,x
        iny
        lda     (str_ptr),y
        sta     obj_z_lo,x
        iny
        lda     (str_ptr),y
        sta     obj_z_hi,x
        iny
        lda     (str_ptr),y
        sta     obj_dyaw,x
        iny
        lda     (str_ptr),y
        sta     obj_dpitch,x
        iny
        lda     (str_ptr),y
        sta     obj_droll,x
        iny
        lda     #1
        sta     obj_active,x
        txa                             ; starting angles differ per object
        asl
        asl
        asl
        sta     obj_roll,x
        asl
        sta     obj_pitch,x
        asl
        sta     obj_yaw,x
        inx
        jmp     @obj
@loaded:
        jsr     build_edges
        print_at PANEL_ROW+2, 1, txt_blank
        lda     scene
        cmp     #SCENE_ROSTER
        bne     :+
        jsr     roster_title
:       lda     #0
        sta     drawn
        sta     windows
        lda     frame
        sta     win_start
        lda     frame+1
        sta     win_start+1
        jsr     clear_sums

        print_at PANEL_ROW+1, 1, txt_top
        print_at PANEL_ROW+3, 1, txt_bottom
        set_pos PANEL_ROW+1, 7
        lda     scene
        sta     num
        lda     #0
        sta     num+1
        sta     num+2
        jsr     to_decimal
        lda     #1
        jsr     put_digits
        set_pos PANEL_ROW+1, 16
        lda     edge_total
        sta     num
        lda     #0
        sta     num+1
        sta     num+2
        jsr     to_decimal
        lda     #3
        jmp     put_digits

; ---------------------------------------------------------------------------------------
; The roster: one enemy at a time at a distance where it fills the view, turning slowly,
; with its name on the panel. The play build moves on to the next every ROSTER_FRAMES
; drawn frames.
ROSTER_FRAMES = 96

roster_setup:
        ldx     roster_item
        ldy     roster_model,x
        sty     obj_model
        lda     #1
        sta     obj_count
        sta     obj_active
        lda     #0
        sta     obj_x_lo
        sta     obj_x_hi
        sta     obj_y_lo
        sta     obj_y_hi
        sta     obj_yaw
        sta     obj_roll
        sta     obj_dyaw
        sta     obj_dpitch
        sta     obj_droll
        sta     roster_timer
        lda     model_view_z_lo,y
        sta     obj_z_lo
        lda     model_view_z_hi,y
        sta     obj_z_hi
.ifdef BENCH
        lda     #128+24                 ; test builds: coming at the camera, turned a
        sta     obj_yaw                 ; little, seen slightly from above
        lda     #40
        sta     obj_pitch
.else
        lda     #20                     ; seen a little from above, turning
        sta     obj_pitch
        lda     #2
        sta     obj_dyaw
.endif
        rts

roster_title:
        ldy     obj_model
        lda     model_title_lo,y
        sta     str_ptr
        lda     model_title_hi,y
        sta     str_ptr+1
        set_pos PANEL_ROW+2, 1
        jmp     print_str

; roster_tick: in the roster scene, the next enemy after ROSTER_FRAMES drawn frames.
roster_tick:
        lda     scene
        cmp     #SCENE_ROSTER
        bne     @done
        inc     roster_timer
        lda     roster_timer
        cmp     #ROSTER_FRAMES
        bcc     @done
        ldx     roster_item
        inx
        cpx     #ROSTER_COUNT
        bcc     :+
        ldx     #0
:       stx     roster_item
        lda     #SCENE_ROSTER
        jmp     start_scene
@done:  rts

; ---------------------------------------------------------------------------------------
.ifdef TEST_MUL
mul_test:
.ifdef BREAK_MUL
        inc     sq1_lo+100
.endif
        lda     #0
        sta     t_1
@a:     lda     #0
        sta     t_2
@b:     lda     t_1
        ldy     t_2
        jsr     umul8
        lda     t_2                     ; shift and add: A = high byte, t_acc = low
        sta     t_acc
        lda     #0
        ldx     #8
        lsr     t_acc
@l:     bcc     :+
        clc
        adc     t_1
:       ror
        ror     t_acc
        dex
        bne     @l
        cmp     mul_hi
        bne     @fail
        lda     t_acc
        cmp     mul_lo
        bne     @fail
        inc     t_2
        bne     @b
        inc     t_1
        bne     @a
        lda     #0
        sta     DEBUGCART_RESULT
:       jmp     :-
@fail:  lda     #1
        sta     DEBUGCART_RESULT
:       jmp     :-
.endif

        .segment "RODATA"
bufhi_of:       .byte BUF0_BITMAP_HI, BUF1_BITMAP_HI
dirty_off_of:   .byte 0, 32
bank_bits_of:   .byte BUF0_BANK_BITS, BUF1_BANK_BITS

txt_top:        scr "SCENE    EDGES      FPS"
                .byte 0
txt_bottom:     scr "CLEAR        MATH        LINES"
                .byte 0

; Scenes: object count, then per object: model, x, y, z (16 bit each), turn rates.
; Scene 4 is the roster, built by roster_setup instead.
SCENE_COUNT = 6
SCENE_ROSTER = 4
scene_lo:       .byte <scene_1, <scene_2, <scene_3, 0, <scene_5, <scene_6
scene_hi:       .byte >scene_1, >scene_2, >scene_3, 0, >scene_5, >scene_6

.macro  object model, px, py, pz, dyaw, dpitch, droll
        .byte   model
        .word   (px) & $FFFF, (py) & $FFFF, (pz) & $FFFF
        .byte   dyaw, dpitch, droll
.endmacro


scene_1:        .byte 1                 ; one cube, 12 edges
                object MODEL_CUBE, 0, 0, 450, 2, 1, 3
scene_2:        .byte 2                 ; two icosahedra, 60 edges
                object MODEL_ICO, -110, 0, 520, 1, 2, 1
                object MODEL_ICO, 110, 0, 520, 2, 1, 2
scene_3:        .byte 8                 ; eight cubes, 96 edges
                object MODEL_CUBE, -480, -170, 900, 2, 1, 3
                object MODEL_CUBE, -160, -170, 900, 1, 3, 2
                object MODEL_CUBE, 160, -170, 900, 3, 2, 1
                object MODEL_CUBE, 480, -170, 900, 2, 3, 1
                object MODEL_CUBE, -480, 170, 900, 1, 2, 3
                object MODEL_CUBE, -160, 170, 900, 3, 1, 2
                object MODEL_CUBE, 160, 170, 900, 2, 2, 2
                object MODEL_CUBE, 480, 170, 900, 1, 1, 3
scene_5:        .byte 6                 ; a mixed enemy group at fighting distance
                object MODEL_LANCER, -260, 70, 650, 2, 0, 1
                object MODEL_RAIDER, 230, -60, 560, 1, 1, 2
                object MODEL_SKITTER, 30, 120, 800, 2, 1, 0
                object MODEL_MOTH, -330, -130, 900, 1, 0, 1
                object MODEL_ROCK_L, 400, 150, 1000, 1, 2, 1
                object MODEL_ROCK_M, 60, -150, 700, 2, 1, 3
scene_6:        .byte 3                 ; clipping: ships across the sides and the near plane
                object MODEL_DREAD_MID, -170, 10, 230, 1, 0, 0
                object MODEL_ROCK_L, 300, 110, 330, 1, 2, 1
                object MODEL_GUNSHIP, 40, -150, 280, 2, 0, 1

txt_blank:      scr "                                      "
                .byte 0

        .include "game.s"
        .include "map.s"
        .include "boss.s"
        .include "anarchy.s"
        .include "missions.s"
        .include "shop.s"
        .include "speech.s"
        .include "hiscore.s"
        .include "sound.s"
        .include "music.s"
        .include "tables.inc"
; The multiply and reciprocal code patch the low byte of a table address or index a
; whole page, so these tables must start on page boundaries.
        .assert <sq1_lo = 0, error, "sq1_lo is not page aligned"
        .assert <sq1_hi = 0, error, "sq1_hi is not page aligned"
        .assert <sq2_lo = 0, error, "sq2_lo is not page aligned"
        .assert <sq2_hi = 0, error, "sq2_hi is not page aligned"
        .assert <recip = 0, error, "recip is not page aligned"
        .include "font.inc"
        .include "models.inc"
        .assert NO_FACE < 32, error, "face_vis holds 32 faces"
        .assert __TABLES_LOAD__ = $0810 && __BSS_SIZE__ <= __TABLES_SIZE__, error, "BSS must lie over the tables' load image"
        .include "sprites.inc"
        .include "music.inc"
        .include "scores.inc"
