; Drawing into the back buffer: lines, the record of what was drawn, and clearing it.

        .segment "ZEROPAGE"
ptr:            .res 2
mask:           .res 1
cnt:            .res 1
err:            .res 1
dx:             .res 1
dy:             .res 1
lx0:            .res 1
ly0:            .res 1
lx1:            .res 1
ly1:            .res 1
bufhi:          .res 1                  ; bitmap page of the back buffer ($A0 or $E0)
dirty_off:      .res 1                  ; 0 or 32: the back buffer's half of the dirty tables
row_min:        .res 1
row_max:        .res 1
col_end:        .res 1
clr_col:        .res 1
clr_row:        .res 1
clr_y:          .res 1
entry_tab:      .res 2                  ; the line routine's table of entry points
line_vec:       .res 2                  ; the entry point jumped to

        .segment "BSS"
; For each 8-pixel column of each buffer, the first and last character row drawn into
; since the buffer was last cleared ($FF/0 = nothing).
dirty_min:      .res 64
dirty_max:      .res 64

        .segment "CODE"

; draw_line: from (lx0, ly0) to (lx1, ly1), viewport pixels, x 0-255, y 0-158.
; Bresenham with unrolled loops. ptr addresses the current character cell (cell row base
; + column * 8) and Y the line within it, so a step down is INY and only every eighth
; one moves ptr by 320. Mostly-horizontal lines are unrolled per pixel bit (the OR value
; is a constant); mostly-vertical ones per line of the cell (the bit is in mask).
; The error term is kept with the carry set between pixels.
draw_line:
        lda     lx1
        cmp     lx0
        bcs     @ordered
        ldx     lx0                     ; draw left to right
        sta     lx0
        stx     lx1
        lda     ly0
        ldx     ly1
        stx     ly0
        sta     ly1
@ordered:
        lda     lx1
        sec
        sbc     lx0
        sta     dx
        lda     ly0                     ; ptr = cell row base + x & $F8
        and     #$F8
        tax
        lda     lx0
        and     #$F8
        clc
        adc     row_lo,x
        sta     ptr
        lda     row_hi,x
        adc     #0
        ora     bufhi
        sta     ptr+1
        lda     ly1
        sec
        sbc     ly0
        bcs     @down
        eor     #$FF                    ; carry is clear: A = -A
        adc     #1
        sta     dy
        cmp     dx
        bcs     @y_up
        lda     #<xu_entry
        ldx     #>xu_entry
        bne     @xmajor                 ; always
@y_up:  lda     #<yu_entry
        ldx     #>yu_entry
        bne     @ymajor
@down:  sta     dy
        cmp     dx
        bcs     @y_down
        lda     #<xd_entry
        ldx     #>xd_entry
        bne     @xmajor
@y_down:
        lda     #<yd_entry
        ldx     #>yd_entry
        bne     @ymajor

@xmajor:                                ; entry by the starting pixel bit
        sta     entry_tab
        stx     entry_tab+1
        lda     lx0
        and     #7
        asl
        tay
        lda     (entry_tab),y
        sta     line_vec
        iny
        lda     (entry_tab),y
        sta     line_vec+1
        lda     dx
        lsr
        sta     err
        lda     dx
        clc
        adc     #1
        sta     cnt                     ; dx + 1 pixels; 0 means 256
        lda     ly0
        and     #7
        tay
        sec
        jmp     (line_vec)

@ymajor:                                ; entry by the starting line in the cell
        sta     entry_tab
        stx     entry_tab+1
        lda     lx0
        and     #7
        tay
        lda     pixel_mask,y
        sta     mask
        lda     ly0
        and     #7
        asl
        tay
        lda     (entry_tab),y
        sta     line_vec
        iny
        lda     (entry_tab),y
        sta     line_vec+1
        lda     dy
        lsr
        sta     err
        lda     dy
        clc
        adc     #1
        sta     cnt
        lda     ly0
        and     #7
        tay
        sec
        jmp     (line_vec)

; Moving to the cell below or above (ptr +- 320), Y to its first or last line.
; JMP (line_vec) reads its two bytes from the same page: the vector must not start at $FF.
        .assert <line_vec <> $FF, error, "line_vec at $FF"

cell_down:
        clc
        lda     ptr
        adc     #<320
        sta     ptr
        lda     ptr+1
        adc     #>320
        sta     ptr+1
        ldy     #0
        sec
        rts
cell_up:
        sec
        lda     ptr
        sbc     #<320
        sta     ptr
        lda     ptr+1
        sbc     #>320
        sta     ptr+1
        ldy     #7
        sec
        rts

; One block per pixel bit N of a mostly-horizontal line; DOWN = 1 steps down.
.macro  xblock  n, down, next
        .local  keep, done
        lda     (ptr),y
        ora     #($80 >> n)
        sta     (ptr),y
        lda     err
        sbc     dy
        bcs     keep
        adc     dx                      ; carry was clear; it is set again after
        sta     err
  .if down
        iny
        cpy     #8
        bne     :+
        jsr     cell_down
:       sec
  .else
        dey
        bpl     :+
        jsr     cell_up
:
  .endif
        dec     cnt
        bne     next
done:   rts
keep:   sta     err
        dec     cnt
        beq     done
.endmacro

; Past bit 7: the next cell to the right.
.macro  xcolumn first
        lda     ptr
        clc
        adc     #8
        sta     ptr
        bcc     :+
        inc     ptr+1
:       sec
        jmp     first
.endmacro

.macro  xmajor_code prefix, down
        .repeat 8, n
.ident(.sprintf("%s%d", prefix, n)):
          .if n < 7
        xblock  n, down, .ident(.sprintf("%s%d", prefix, n+1))
          .else
        xblock  n, down, .ident(.sprintf("%s_col", prefix))
          .endif
        .endrep
.ident(.sprintf("%s_col", prefix)):
        xcolumn .ident(.sprintf("%s0", prefix))
.endmacro

        xmajor_code "xd", 1
        xmajor_code "xu", 0

; One block per line L of the cell for a mostly-vertical line. Blocks follow each other
; in drawing order (0-7 going down, 7-0 going up), so a block falls into the next line's.
.macro  yblock  l, down, next
        .local  keep, done, step
        lda     (ptr),y
        ora     mask
        sta     (ptr),y
        lda     err
        sbc     dx
        bcs     keep
        adc     dy
        sta     err
        lsr     mask                    ; one pixel right
        bcc     :+
        ror     mask                    ; past bit 0: mask = $80, carry clear
        lda     ptr
        adc     #8
        sta     ptr
        bcc     :+
        inc     ptr+1
:       sec
        dec     cnt
        bne     step
done:   rts
keep:   sta     err
        dec     cnt
        beq     done
step:
  .if down
    .if l < 7
        iny
    .else
        jsr     cell_down
        jmp     next
    .endif
  .else
    .if l > 0
        dey
    .else
        jsr     cell_up
        jmp     next
    .endif
  .endif
.endmacro

.macro  ymajor_code prefix, down
  .if down
        .repeat 8, l
.ident(.sprintf("%s%d", prefix, l)):
        yblock  l, 1, .ident(.sprintf("%s0", prefix))
        .endrep
  .else
        .repeat 8, i
.ident(.sprintf("%s%d", prefix, 7-i)):
        yblock  7-i, 0, .ident(.sprintf("%s7", prefix))
        .endrep
  .endif
.endmacro

        ymajor_code "yd", 1
        ymajor_code "yu", 0

        .segment "RODATA"
xd_entry:       .word xd0, xd1, xd2, xd3, xd4, xd5, xd6, xd7
xu_entry:       .word xu0, xu1, xu2, xu3, xu4, xu5, xu6, xu7
yd_entry:       .word yd0, yd1, yd2, yd3, yd4, yd5, yd6, yd7
yu_entry:       .word yu0, yu1, yu2, yu3, yu4, yu5, yu6, yu7

        .segment "CODE"

; mark_dirty: widens the back buffer's dirty rows over the box from (lx0, ly0) to
; (lx1, ly1). Expects lx0 <= lx1. Called once per object with its screen bounding box.
mark_dirty:
        lda     ly0
        ldx     ly1
        cmp     ly1
        bcc     :+
        stx     row_min                 ; ly1 is the smaller
        sta     row_max
        jmp     :++
:       sta     row_min
        stx     row_max
:       lda     row_min
        lsr
        lsr
        lsr
        sta     row_min
        lda     row_max
        lsr
        lsr
        lsr
        sta     row_max
        lda     lx1
        lsr
        lsr
        lsr
        clc
        adc     dirty_off
        sta     col_end
        lda     lx0
        lsr
        lsr
        lsr
        clc
        adc     dirty_off
        tax
@col:   lda     row_min
        cmp     dirty_min,x
        bcs     :+
        sta     dirty_min,x
:       lda     row_max
        cmp     dirty_max,x
        bcc     :+
        sta     dirty_max,x
:       cpx     col_end
        inx
        bcc     @col
        rts

; clear_back: clears every character cell the back buffer's dirty table names, then
; empties the table. Per dirty column it runs part of an unrolled clear: one block of
; eight `sta abs,y` per viewport row (Y = column * 8), entered at the first dirty row's
; block, with an RTS patched over the first store after the last dirty row's block.
clear_back:
        lda     dirty_off
        beq     :+
        lda     #VIEW_ROWS+1
:       sta     clr_y                   ; 0 or 21: which buffer's blocks
        ldx     dirty_off
        lda     #0
        sta     clr_col
@col:   lda     dirty_min,x
        cmp     #$FF
        beq     @next
        clc
        adc     clr_y
        tay                             ; entry: block of the first dirty row
        lda     block_lo,y
        sta     @call+1
        lda     block_hi,y
        sta     @call+2
        lda     dirty_max,x
        clc
        adc     clr_y
        tay                             ; stop: the block after the last dirty row
        lda     block_lo+1,y
        sta     @stop+1
        sta     @restore+1
        lda     block_hi+1,y
        sta     @stop+2
        sta     @restore+2
        lda     #$60                    ; RTS
@stop:  sta     $FFFF
        lda     clr_col
        asl
        asl
        asl
        tay
        lda     #0
@call:  jsr     $FFFF
        lda     #$99                    ; STA abs,Y again
@restore:
        sta     $FFFF
        lda     #$FF
        sta     dirty_min,x
        lda     #0
        sta     dirty_max,x
@next:  inx
        inc     clr_col
        lda     clr_col
        cmp     #32
        bne     @col
        rts

; The unrolled clears, one per buffer: VIEW_ROWS blocks of 8 stores, then an RTS.
.macro  clear_code bitmap
        .repeat VIEW_ROWS, r
        .repeat 8, k
        sta     bitmap + r*320 + VIEW_LEFT_CELLS*8 + k,y
        .endrep
        .endrep
        rts
.endmacro

clear_code_a:   clear_code BUF0_BITMAP_HI*256
clear_code_b:   clear_code BUF1_BITMAP_HI*256

        .segment "RODATA"
; Block addresses, VIEW_ROWS + 1 per buffer. The extra entry is where the RTS goes when
; the last dirty row is the bottom one: a spare byte, since the code ends in its own RTS.
block_lo:
        .repeat VIEW_ROWS, r
        .byte   <(clear_code_a + r*24)
        .endrep
        .byte   <clear_spare
        .repeat VIEW_ROWS, r
        .byte   <(clear_code_b + r*24)
        .endrep
        .byte   <clear_spare
block_hi:
        .repeat VIEW_ROWS, r
        .byte   >(clear_code_a + r*24)
        .endrep
        .byte   >clear_spare
        .repeat VIEW_ROWS, r
        .byte   >(clear_code_b + r*24)
        .endrep
        .byte   >clear_spare

        .segment "BSS"
clear_spare:    .res 1

        .segment "CODE"

; reset_dirty: both buffers' tables empty (after the bitmaps were cleared whole).
reset_dirty:
        ldx     #63
:       lda     #$FF
        sta     dirty_min,x
        lda     #0
        sta     dirty_max,x
        dex
        bpl     :-
        rts
