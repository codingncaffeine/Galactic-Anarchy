; Drawing the edges, with clipping: an edge with an end behind the near plane is cut
; there first (bisection in 3D on z), then both ends are projected to 16-bit screen
; coordinates and the edge is cut at the viewport's sides (bisection in 2D).
;
; Screen points here are 16 bits per axis, biased by $8000 so that they compare and
; average as unsigned numbers: the viewport is x $8000-$80FF, y $8000-$809E.

        .segment "HIBSS"
cl_v:           .res 2                  ; the edge's two vertices
cl_k:           .res 1
cl_n:           .res 1
cl_t:           .res 2
cl_c:           .res 1
cl_alt:         .res 1
cl_ol:          .res 1                  ; ext_coord's result
cl_oh:          .res 1
pw_xl:          .res 2                  ; the two ends in world units
pw_xh:          .res 2
pw_yl:          .res 2
pw_yh:          .res 2
pw_zl:          .res 2
pw_zh:          .res 2
np:             .res 6                  ; near_clip: behind, in front, middle
nq:             .res 6                  ; (x lo, x hi, y lo, y hi, z lo, z hi)
nm:             .res 6
; Screen points: 0-1 the edge's ends, 2-3 the bisection's inside and outside ends,
; 4 their middle, 5 and 7 a second search interval, 6 a found inside point.
qxl:            .res 8
qxh:            .res 8
qyl:            .res 8
qyh:            .res 8

VIEW_H          = VIEW_HALF_H*2+1       ; viewport rows 0-158

        .segment "CODE"

; draw_edges: every edge not marked hidden. Edges with both ends on the viewport are
; drawn as they are, the rest go through clip_edge unless their outcodes rule them out.
draw_edges:
        lda     #0
        sta     cur_vert                ; reused as the edge counter
@edge:  lda     cur_vert
        cmp     edge_total
        bcs     @done
        tax
        lda     edge_hide,x
        bne     @skip
        ldy     edge_a,x
        lda     edge_b,x
        tax
        lda     scr_ok,y
        ora     scr_ok,x
        bne     @clip
        lda     scr_x,y
        sta     lx0
        lda     scr_y,y
        sta     ly0
        lda     scr_x,x
        sta     lx1
        lda     scr_y,x
        sta     ly1
        jsr     draw_line
@skip:  inc     cur_vert
        jmp     @edge
@clip:
.ifdef NO_CLIP
        jmp     @skip                   ; control build: edges off the viewport dropped
.endif
        bmi     @skip                   ; VS_NEVER
        and     #OC_FAR
        bne     @skip
        lda     scr_ok,y                ; both ends beyond the same side
        and     scr_ok,x
        and     #$1F
        bne     @skip
        sty     cl_v
        stx     cl_v+1
        jsr     clip_edge
        jmp     @skip
@done:  rts

; clip_edge: draws the part of edge cl_v / cl_v+1 that is on the viewport, if any.
clip_edge:
        ldx     #1
:       ldy     cl_v,x
        lda     vw_xl,y
        sta     pw_xl,x
        lda     vw_xh,y
        sta     pw_xh,x
        lda     vw_yl,y
        sta     pw_yl,x
        lda     vw_yh,y
        sta     pw_yh,x
        lda     vw_zl,y
        sta     pw_zl,x
        lda     vw_zh,y
        sta     pw_zh,x
        dex
        bpl     :-
        ldy     cl_v                    ; at most one end is behind the near plane
        lda     scr_ok,y
        and     #OC_NEAR
        beq     :+
        ldx     #0
        jsr     near_clip
:       ldy     cl_v+1
        lda     scr_ok,y
        and     #OC_NEAR
        beq     :+
        ldx     #1
        jsr     near_clip
:       ldx     #1                      ; both ends to screen points 0 and 1
@scr:   ldy     cl_v,x
        lda     scr_ok,y
        bne     @ext
        lda     scr_x,y
        sta     qxl,x
        lda     scr_y,y
        sta     qyl,x
        lda     #$80
        sta     qxh,x
        sta     qyh,x
        jmp     @next
@ext:   stx     cl_k
        jsr     project_ext
        ldx     cl_k
@next:  dex
        bpl     @scr
        jmp     clip_2d

; near_clip: end X (behind the near plane) moves along the edge towards the other end
; until it is in front of the plane by less than 8 units.
near_clip:
        stx     cl_k
        txa
        eor     #1
        tay
        lda     pw_xl,x
        sta     np
        lda     pw_xh,x
        sta     np+1
        lda     pw_yl,x
        sta     np+2
        lda     pw_yh,x
        sta     np+3
        lda     pw_zl,x
        sta     np+4
        lda     pw_zh,x
        sta     np+5
        lda     pw_xl,y
        sta     nq
        lda     pw_xh,y
        sta     nq+1
        lda     pw_yl,y
        sta     nq+2
        lda     pw_yh,y
        sta     nq+3
        lda     pw_zl,y
        sta     nq+4
        lda     pw_zh,y
        sta     nq+5
        lda     #16
        sta     cl_n
@loop:  ldx     #4                      ; nm = (np + nq) / 2, signed, per axis
:       clc
        lda     np,x
        adc     nq,x
        sta     nm,x
        lda     np+1,x
        eor     #$80
        sta     cl_t
        lda     nq+1,x
        eor     #$80
        adc     cl_t
        ror
        eor     #$80
        sta     nm+1,x
        ror     nm,x
        dex
        dex
        bpl     :-
        ldx     #5
        lda     nm+5                    ; the middle in front: it becomes nq, else np
        bmi     @behind
        bne     @front
        lda     nm+4
        cmp     #NEAR_Z
        bcc     @behind
@front: lda     nm,x
        sta     nq,x
        dex
        bpl     @front
        jmp     @check
@behind:
        lda     nm,x
        sta     np,x
        dex
        bpl     @behind
@check: lda     nq+5
        bne     :+
        lda     nq+4
        cmp     #NEAR_Z+8
        bcc     @done
:       dec     cl_n
        bne     @loop
@done:  ldx     cl_k
        lda     nq
        sta     pw_xl,x
        lda     nq+1
        sta     pw_xh,x
        lda     nq+2
        sta     pw_yl,x
        lda     nq+3
        sta     pw_yh,x
        lda     nq+4
        sta     pw_zl,x
        lda     nq+5
        sta     pw_zh,x
        rts

; project_ext: end X in world units (NEAR_Z <= z < FAR) to screen point X, 16 bits per
; axis, by the same arithmetic as project_point.
project_ext:
        lda     pw_xl,x
        sta     wx
        lda     pw_xh,x
        sta     wx+1
        lda     pw_yl,x
        sta     wy
        lda     pw_yh,x
        sta     wy+1
        lda     pw_zl,x
        sta     wz
        lda     pw_zh,x
        sta     wz+1
        recip_from_wz
        lda     wx
        ldy     wx+1
        jsr     ext_coord
        ldx     cl_k
        lda     neg_flag
        bne     :+
        clc                             ; x = $8080 + off
        lda     #$80
        adc     cl_ol
        sta     qxl,x
        lda     #$80
        adc     cl_oh
        sta     qxh,x
        jmp     @y
:       sec                             ; x = $8080 - off
        lda     #$80
        sbc     cl_ol
        sta     qxl,x
        lda     #$80
        sbc     cl_oh
        sta     qxh,x
@y:     lda     wy
        ldy     wy+1
        jsr     ext_coord
        ldx     cl_k
        lda     neg_flag
        beq     :+
        clc                             ; below the centre: y = $8000 + 79 + off
        lda     #VIEW_CY
        adc     cl_ol
        sta     qyl,x
        lda     #$80
        adc     cl_oh
        sta     qyh,x
        rts
:       sec                             ; above: y = $8000 + 79 - off
        lda     #VIEW_CY
        sbc     cl_ol
        sta     qyl,x
        lda     #$80
        sbc     cl_oh
        sta     qyh,x
        rts

; ext_coord: A/Y = a signed coordinate (low/high). cl_ol/cl_oh = |c| * r / 256 (16 bits),
; neg_flag = 1 when c < 0; r is the factor recip_from_wz set.
ext_coord:
        sta     off_lo
        sty     off_hi
        lda     #0
        sta     neg_flag
        cpy     #$80
        bcc     :+
        inc     neg_flag
        sec
        lda     #0
        sbc     off_lo
        sta     off_lo
        lda     #0
        sbc     off_hi
        sta     off_hi
:       ldy     off_lo                  ; (low byte * r) / 256
        jsr     mul_r
        sta     cl_ol
        lda     off_hi                  ; + high byte * r
        ldy     recip_val
        jsr     umul8
        clc
        lda     mul_lo
        adc     cl_ol
        sta     cl_ol
        lda     mul_hi
        adc     #0
        sta     cl_oh
        rts

; clip_2d: cuts screen points 0-1 to the viewport and draws what is left.
clip_2d:
        ldx     #0
        jsr     q_inside
        bcs     @out0
        ldx     #1
        jsr     q_inside
        bcc     @draw
        ldx     #2                      ; 0 in, 1 out
        ldy     #0
        jsr     q_copy
        ldx     #3
        ldy     #1
        jsr     q_copy
        jsr     bisect
        ldx     #1
        ldy     #2
        jsr     q_copy
        jmp     @draw
@out0:  ldx     #1
        jsr     q_inside
        bcs     @both
        ldx     #2                      ; 1 in, 0 out
        ldy     #1
        jsr     q_copy
        ldx     #3
        ldy     #0
        jsr     q_copy
        jsr     bisect
        ldx     #0
        ldy     #2
        jsr     q_copy
        jmp     @draw
@both:  jsr     find_inside             ; both out: a point between them on screen?
        bcc     :+
        rts
:       ldx     #6
        ldy     #4
        jsr     q_copy
        ldx     #2                      ; from it towards end 0
        ldy     #6
        jsr     q_copy
        ldx     #3
        ldy     #0
        jsr     q_copy
        jsr     bisect
        ldx     #0
        ldy     #2
        jsr     q_copy
        ldx     #2                      ; and towards end 1
        ldy     #6
        jsr     q_copy
        ldx     #3
        ldy     #1
        jsr     q_copy
        jsr     bisect
        ldx     #1
        ldy     #2
        jsr     q_copy
@draw:  lda     qxl                     ; ends ordered left to right for mark_dirty
        cmp     qxl+1
        bcc     :+
        ldx     qxl+1
        stx     lx0
        sta     lx1
        lda     qyl+1
        sta     ly0
        lda     qyl
        sta     ly1
        jmp     :++
:       sta     lx0
        lda     qxl+1
        sta     lx1
        lda     qyl
        sta     ly0
        lda     qyl+1
        sta     ly1
:       jsr     mark_dirty              ; the object's box may not cover a clipped end
        jmp     draw_line

; bisect: moves points 2 (on screen) and 3 (off it) together until they are next to
; each other; point 2 is then the last point of the edge on the viewport. Halving the
; interval as many times as its longer side has bits brings it down to one pixel.
bisect:
        sec                             ; the bit length of |dx| | |dy|
        lda     qxl+3
        sbc     qxl+2
        sta     cl_t
        lda     qxh+3
        sbc     qxh+2
        bcs     :+
        eor     #$FF                    ; one's complement is close enough for a bit count
        tax
        lda     cl_t
        eor     #$FF
        sta     cl_t
        txa
:       sta     cl_t+1
        sec
        lda     qyl+3
        sbc     qyl+2
        tax
        lda     qyh+3
        sbc     qyh+2
        bcs     :+
        eor     #$FF
        pha
        txa
        eor     #$FF
        tax
        pla
:       ora     cl_t+1
        sta     cl_t+1
        txa
        ora     cl_t
        sta     cl_t
        ldx     #1                      ; one extra halving covers the complement's rounding
:       inx
        lsr     cl_t+1
        ror     cl_t
        lda     cl_t
        ora     cl_t+1
        bne     :-
        stx     cl_n
@loop:  clc                             ; the middle, in qxl+4 ...
        lda     qxl+2
        adc     qxl+3
        tax
        lda     qxh+2
        adc     qxh+3
        ror
        sta     qxh+4
        txa
        ror
        sta     qxl+4
        clc
        lda     qyl+2
        adc     qyl+3
        tax
        lda     qyh+2
        adc     qyh+3
        ror
        sta     qyh+4
        txa
        ror
        sta     qyl+4
        lda     qxh+4                   ; on the viewport: it is the new inside end
        cmp     #$80
        bne     @out
        lda     qyh+4
        cmp     #$80
        bne     @out
        lda     qyl+4
        cmp     #VIEW_H
        bcs     @out
        lda     qxl+4
        sta     qxl+2
        lda     qxh+4
        sta     qxh+2
        lda     qyl+4
        sta     qyl+2
        lda     qyh+4
        sta     qyh+2
        dec     cl_n
        bne     @loop
        rts
@out:   lda     qxl+4
        sta     qxl+3
        lda     qxh+4
        sta     qxh+3
        lda     qyl+4
        sta     qyl+3
        lda     qyh+4
        sta     qyh+3
        dec     cl_n
        bne     @loop
        rts

; find_inside: with points 0 and 1 both off the viewport, finds a point between them on
; it: carry clear and the point in 4, or carry set when there is none. Halves the
; interval, keeping the half that does not lie wholly beyond one side; when neither half
; can be ruled out, the second is kept (once) to search if the first comes up empty.
find_inside:
        lda     #0
        sta     cl_alt
        ldx     #2
        ldy     #0
        jsr     q_copy
        ldx     #3
        ldy     #1
        jsr     q_copy
@start: lda     #20
        sta     cl_n
@loop:  ldx     #2
        jsr     q_code
        sta     cl_c
        ldx     #3
        jsr     q_code
        and     cl_c
        bne     @fail
        ldx     #2
        ldy     #3
        jsr     q_near
        bcc     @fail
        ldx     #2
        ldy     #3
        jsr     q_mid
        ldx     #4
        jsr     q_inside
        bcs     :+
        rts                             ; found (carry clear)
:       ldx     #4
        jsr     q_code
        sta     cl_c
        ldx     #2
        jsr     q_code
        and     cl_c
        beq     :+
        ldx     #2                      ; the first half is out: keep the second
        ldy     #4
        jsr     q_copy
        jmp     @next
:       ldx     #3
        jsr     q_code
        and     cl_c
        bne     @first
        lda     cl_alt                  ; neither: remember the second half once
        bne     @first
        inc     cl_alt
        ldx     #5
        ldy     #4
        jsr     q_copy
        ldx     #7
        ldy     #3
        jsr     q_copy
@first: ldx     #3
        ldy     #4
        jsr     q_copy
@next:  dec     cl_n
        bne     @loop
@fail:  lda     cl_alt
        cmp     #1
        bne     @none
        inc     cl_alt
        ldx     #2
        ldy     #5
        jsr     q_copy
        ldx     #3
        ldy     #7
        jsr     q_copy
        jmp     @start
@none:  sec
        rts

; q_inside: carry clear when screen point X is on the viewport.
q_inside:
        lda     qxh,x
        cmp     #$80
        bne     @no
        lda     qyh,x
        cmp     #$80
        bne     @no
        lda     qyl,x
        cmp     #VIEW_H
        rts
@no:    sec
        rts

; q_code: A = the OC_ side bits of screen point X.
q_code:
        lda     #0
        sta     cl_t
        lda     qxh,x
        cmp     #$80
        beq     @y
        lda     #OC_LEFT
        bcc     :+
        lda     #OC_RIGHT
:       sta     cl_t
@y:     lda     qyh,x
        cmp     #$80
        beq     @row
        lda     #OC_TOP
        bcc     :+
        lda     #OC_BOTTOM
:       ora     cl_t
        rts
@row:   lda     qyl,x
        cmp     #VIEW_H
        lda     cl_t
        bcc     :+
        ora     #OC_BOTTOM
:       rts

; q_copy: screen point X = screen point Y.
q_copy:
        lda     qxl,y
        sta     qxl,x
        lda     qxh,y
        sta     qxh,x
        lda     qyl,y
        sta     qyl,x
        lda     qyh,y
        sta     qyh,x
        rts

; q_mid: screen point 4 = the middle of points X and Y.
q_mid:
        clc
        lda     qxl,x
        adc     qxl,y
        sta     qxl+4
        lda     qxh,x
        adc     qxh,y
        ror
        sta     qxh+4
        ror     qxl+4
        clc
        lda     qyl,x
        adc     qyl,y
        sta     qyl+4
        lda     qyh,x
        adc     qyh,y
        ror
        sta     qyh+4
        ror     qyl+4
        rts

; q_near: carry clear when screen points X and Y are at most one pixel apart on each axis.
q_near:
        sec
        lda     qxl,y
        sbc     qxl,x
        sta     cl_t
        lda     qxh,y
        sbc     qxh,x
        sta     cl_t+1
        jsr     @one
        bcs     @far
        sec
        lda     qyl,y
        sbc     qyl,x
        sta     cl_t
        lda     qyh,y
        sbc     qyh,x
        sta     cl_t+1
@one:   clc                             ; cl_t + 1 in 0-2?
        lda     cl_t
        adc     #1
        sta     cl_t
        lda     cl_t+1
        adc     #0
        bne     @far
        lda     cl_t
        cmp     #3
        rts
@far:   sec
        rts
