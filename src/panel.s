; The text panel below the viewport. Everything printed goes to the screens of both
; buffers, since the panel shows whichever bank is on display.

        .segment "ZEROPAGE"
str_ptr:        .res 2
scr_off:        .res 2
num:            .res 3                  ; number to print (24 bit)
digits:         .res 6

        .segment "CODE"

; Screen codes of a string: letters $01-$1A, space, digits and . : - as ASCII.
.macro  scr text
        .repeat .strlen(text), i
        .byte   .strat(text, i) & $3F
        .endrep
.endmacro

; print_at ROW, COL, LABEL: prints the zero-terminated screen-code string at LABEL.
.macro  print_at row, col, label
        lda     #<((row)*40+(col))
        sta     scr_off
        lda     #>((row)*40+(col))
        sta     scr_off+1
        lda     #<label
        sta     str_ptr
        lda     #>label
        sta     str_ptr+1
        jsr     print_str
.endmacro

; set_pos ROW, COL: where the next put_digits / put_char writes.
.macro  set_pos row, col
        lda     #<((row)*40+(col))
        sta     scr_off
        lda     #>((row)*40+(col))
        sta     scr_off+1
.endmacro

print_str:
        ldy     #0
:       lda     (str_ptr),y
        beq     :+
        jsr     put_char
        iny
        bne     :-
:       rts

; put_char: A at scr_off + Y on both screens. Keeps A, X and Y.
put_char:
        pha
        clc
        lda     scr_off
        sta     @w0+1
        sta     @w1+1
        lda     scr_off+1
        adc     #>BUF0_SCREEN
        sta     @w0+2
        clc
        lda     scr_off+1
        adc     #>BUF1_SCREEN
        sta     @w1+2
        pla
@w0:    sta     BUF0_SCREEN,y
@w1:    sta     BUF1_SCREEN,y
        rts

; to_decimal: num (24 bit, below 1,000,000) -> digits[0..5] as screen codes.
to_decimal:
        ldx     #0
@digit: lda     #'0'
        sta     digits,x
@sub:   sec
        lda     num
        sbc     pow10_0,x
        tay
        lda     num+1
        sbc     pow10_1,x
        sta     m_a
        lda     num+2
        sbc     pow10_2,x
        bcc     @next
        sta     num+2
        lda     m_a
        sta     num+1
        sty     num
        inc     digits,x
        bne     @sub
@next:  inx
        cpx     #6
        bne     @digit
        rts

; put_digits: the last A digits of digits[] at the current position.
put_digits:
        sta     cnt
        lda     #6
        sec
        sbc     cnt
        tax
        ldy     #0
:       lda     digits,x
        jsr     put_char
        inx
        iny
        cpy     cnt
        bne     :-
        rts

        .segment "RODATA"
pow10_0:        .byte <100000, <10000, <1000, <100, <10, <1
pow10_1:        .byte >100000, >10000, >1000, >100, >10, >1
pow10_2:        .byte ^100000, ^10000, ^1000, ^100, ^10, ^1
