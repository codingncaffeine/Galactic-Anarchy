; Multiplication by quarter squares, and the rotation matrix.

        .segment "ZEROPAGE"
mul_lo:         .res 1
mul_hi:         .res 1
m_a:            .res 1
m_b:            .res 1
m_sign:         .res 1

        .segment "CODE"

; umul8: A * Y -> mul_lo/mul_hi, both unsigned. X is kept.
; a*b = sq1[a+b] - sq2[b-a+255]; the table operands' low bytes are patched with a and
; 255-a (the tables are page aligned), so the Y index adds b.
umul8:
        sta     @p1+1
        sta     @p3+1
        eor     #$FF
        sta     @p2+1
        sta     @p4+1
        sec
@p1:    lda     sq1_lo,y
@p2:    sbc     sq2_lo,y
        sta     mul_lo
@p3:    lda     sq1_hi,y
@p4:    sbc     sq2_hi,y
        sta     mul_hi
        rts

; smul: A * Y -> mul_lo/mul_hi, all signed. X is kept.
smul:
        sta     m_a
        sty     m_b
        eor     m_b
        sta     m_sign
        lda     m_b
        bpl     :+
        eor     #$FF
        clc
        adc     #1
:       tay
        lda     m_a
        bpl     :+
        eor     #$FF
        clc
        adc     #1
:       jsr     umul8
        bit     m_sign
        bpl     :+
        sec
        lda     #0
        sbc     mul_lo
        sta     mul_lo
        lda     #0
        sbc     mul_hi
        sta     mul_hi
:       rts

; smul7: A * Y >> 7 -> A, signed, for factors of magnitude up to 127 (the result then
; fits a signed byte). X is kept.
smul7:
        jsr     smul
        lda     mul_lo
        asl
        lda     mul_hi
        rol
        rts

; ---------------------------------------------------------------------------------------
; Rotation matrix from three angles (256 steps per turn), as signed bytes with 127 = 1:
;   R = Ry(yaw) * Rx(pitch) * Rz(roll)
; Inputs: rot_yaw, rot_pitch, rot_roll. Output: matrix[0..8], row major.

        .segment "ZEROPAGE"
rot_yaw:        .res 1
rot_pitch:      .res 1
rot_roll:       .res 1
s_a:            .res 1
c_a:            .res 1
s_b:            .res 1
c_b:            .res 1
s_c:            .res 1
c_c:            .res 1
t_1:            .res 1
t_2:            .res 1
t_acc:          .res 1
matrix:         .res 9

        .segment "CODE"

; Adds the signed byte in A to t_acc, clamping at +-127 instead of wrapping.
.macro  add_clamped
        clc
        adc     t_acc
        bvc     :+
        lda     t_acc                   ; overflow: the true sum has t_acc's sign
        bmi     @neg
        lda     #127
        bne     :+
@neg:   lda     #<-127
:
.endmacro

build_matrix:
        ldx     rot_yaw
        lda     sine,x
        sta     s_a
        lda     sine+64,x
        sta     c_a
        ldx     rot_pitch
        lda     sine,x
        sta     s_b
        lda     sine+64,x
        sta     c_b
        ldx     rot_roll
        lda     sine,x
        sta     s_c
        lda     sine+64,x
        sta     c_c

        lda     s_b                     ; t1 = sb*sc, t2 = sb*cc
        ldy     s_c
        jsr     smul7
        sta     t_1
        lda     s_b
        ldy     c_c
        jsr     smul7
        sta     t_2

        lda     c_a                     ; m00 = ca*cc + sa*t1
        ldy     c_c
        jsr     smul7
        sta     t_acc
        lda     s_a
        ldy     t_1
        jsr     smul7
        jsr     add_to_acc
        sta     matrix+0

        lda     s_a                     ; m01 = sa*t2 - ca*sc
        ldy     t_2
        jsr     smul7
        sta     t_acc
        lda     c_a
        ldy     s_c
        jsr     smul7
        eor     #$FF
        clc
        adc     #1
        jsr     add_to_acc
        sta     matrix+1

        lda     s_a                     ; m02 = sa*cb
        ldy     c_b
        jsr     smul7
        sta     matrix+2

        lda     c_b                     ; m10 = cb*sc
        ldy     s_c
        jsr     smul7
        sta     matrix+3

        lda     c_b                     ; m11 = cb*cc
        ldy     c_c
        jsr     smul7
        sta     matrix+4

        lda     s_b                     ; m12 = -sb
        eor     #$FF
        clc
        adc     #1
        sta     matrix+5

        lda     c_a                     ; m20 = ca*t1 - sa*cc
        ldy     t_1
        jsr     smul7
        sta     t_acc
        lda     s_a
        ldy     c_c
        jsr     smul7
        eor     #$FF
        clc
        adc     #1
        jsr     add_to_acc
        sta     matrix+6

        lda     s_a                     ; m21 = sa*sc + ca*t2
        ldy     s_c
        jsr     smul7
        sta     t_acc
        lda     c_a
        ldy     t_2
        jsr     smul7
        jsr     add_to_acc
        sta     matrix+7

        lda     c_a                     ; m22 = ca*cb
        ldy     c_b
        jsr     smul7
        sta     matrix+8
        rts

add_to_acc:
        add_clamped
        rts
