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

        .segment "BSS"
; For each 8-pixel column of each buffer, the first and last character row drawn into
; since the buffer was last cleared ($FF/0 = nothing).
dirty_min:      .res 64
dirty_max:      .res 64

        .segment "CODE"

; draw_line: from (lx0, ly0) to (lx1, ly1), viewport pixels, x 0-255, y 0-158.
; Bresenham, one loop per octant pair. The pointer addresses the line's current row
; (row_lo/row_hi), Y holds the column (x & $F8) and mask the pixel within the byte.
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
        jsr     mark_dirty
        lda     lx1
        sec
        sbc     lx0
        sta     dx
        ldx     ly0
        lda     row_lo,x
        sta     ptr
        lda     row_hi,x
        ora     bufhi
        sta     ptr+1
        lda     lx0
        and     #7
        tay
        lda     pixel_mask,y
        sta     mask
        lda     lx0
        and     #$F8
        tay
        lda     ly1
        sec
        sbc     ly0
        bcs     @down
        eor     #$FF                    ; carry is clear: A = -A
        adc     #1
        sta     dy
        cmp     dx
        bcs     :+
        jmp     xmajor_up
:       jmp     ymajor_up
@down:  sta     dy
        cmp     dx
        bcs     :+
        jmp     xmajor_down
:       jmp     ymajor_down

.macro  next_row_down
        inx
        lda     row_lo,x
        sta     ptr
        lda     row_hi,x
        ora     bufhi
        sta     ptr+1
.endmacro

.macro  next_row_up
        dex
        lda     row_lo,x
        sta     ptr
        lda     row_hi,x
        ora     bufhi
        sta     ptr+1
.endmacro

; One pixel right: the mask moves on, and past bit 0 the column moves 8 bytes on.
.macro  next_column
        .local  same
        lsr     mask
        bcc     same
        ror     mask                    ; carry was 1: mask = $80, carry now 0
        tya
        adc     #8
        tay
same:
.endmacro

.macro  plot
        lda     (ptr),y
        ora     mask
        sta     (ptr),y
.endmacro

.macro  xmajor  next_row
        .local  loop, no_step
        ldx     ly0
        lda     dx
        lsr
        sta     err
        lda     dx
        clc
        adc     #1
        sta     cnt                     ; dx + 1 pixels; 0 means 256
loop:   plot
        next_column
        lda     err
        sec
        sbc     dy
        bcs     no_step
        adc     dx                      ; carry is clear
        sta     err
        next_row
        dec     cnt
        bne     loop
        rts
no_step:
        sta     err
        dec     cnt
        bne     loop
        rts
.endmacro

.macro  ymajor  next_row
        .local  loop, no_step, next
        ldx     ly0
        lda     dy
        lsr
        sta     err
        lda     dy
        clc
        adc     #1
        sta     cnt
loop:   plot
        next_row
        lda     err
        sec
        sbc     dx
        bcs     no_step
        adc     dy
        sta     err
        next_column
        dec     cnt
        bne     loop
        rts
no_step:
        sta     err
        dec     cnt
        bne     loop
        rts
.endmacro

xmajor_down:    xmajor  next_row_down
xmajor_up:      xmajor  next_row_up
ymajor_down:    ymajor  next_row_down
ymajor_up:      ymajor  next_row_up

; mark_dirty: widens the back buffer's dirty rows over the line's bounding box.
; Expects lx0 <= lx1.
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
; empties the table.
clear_back:
        ldx     dirty_off
        lda     #0
        sta     clr_col
@col:   lda     dirty_min,x
        cmp     #$FF
        beq     @next
        sta     clr_row
        lda     clr_col
        asl
        asl
        asl
        sta     clr_y
@row:   lda     clr_row
        asl
        asl
        asl
        tay
        lda     row_lo,y
        sta     ptr
        lda     row_hi,y
        ora     bufhi
        sta     ptr+1
        ldy     clr_y
        lda     #0
        .repeat 7
        sta     (ptr),y
        iny
        .endrep
        sta     (ptr),y
        lda     clr_row
        cmp     dirty_max,x
        inc     clr_row
        bcc     @row
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
