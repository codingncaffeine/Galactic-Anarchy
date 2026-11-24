; Objects, vertex transformation and perspective projection, and drawing the edges.

        .segment "ZEROPAGE"
obj_count:      .res 1
vert_total:     .res 1
edge_total:     .res 1
cur_obj:        .res 1
cur_vert:       .res 1
vert_out:       .res 1                  ; index into the screen vertex arrays
vx:             .res 1
vy:             .res 1
vz:             .res 1
acc_lo:         .res 1
acc_hi:         .res 1
acc0:           .res 2                  ; the three rotated coordinates, times 128
acc1:           .res 2
acc2:           .res 2
t_hi:           .res 1
wx:             .res 2                  ; transformed point in world units
wy:             .res 2
wz:             .res 2
recip_val:      .res 1
off_lo:         .res 1
off_hi:         .res 1
neg_flag:       .res 1
model_ptr:      .res 2                  ; scratch while copying a model's edges
vmod_x:         .res 2                  ; current model's vertex arrays
vmod_y:         .res 2
vmod_z:         .res 2
vmod_count:     .res 1
anim_tick:      .res 1
px:             .res 1                  ; project_point's result
py:             .res 1
bb_minx:        .res 1                  ; screen bounding box of the object's vertices
bb_maxx:        .res 1
bb_miny:        .res 1
bb_maxy:        .res 1

        .segment "BSS"
obj_model:      .res MAX_OBJECTS
obj_x_lo:       .res MAX_OBJECTS
obj_x_hi:       .res MAX_OBJECTS
obj_y_lo:       .res MAX_OBJECTS
obj_y_hi:       .res MAX_OBJECTS
obj_z_lo:       .res MAX_OBJECTS
obj_z_hi:       .res MAX_OBJECTS
obj_yaw:        .res MAX_OBJECTS
obj_pitch:      .res MAX_OBJECTS
obj_roll:       .res MAX_OBJECTS
obj_dyaw:       .res MAX_OBJECTS
obj_dpitch:     .res MAX_OBJECTS
obj_droll:      .res MAX_OBJECTS
obj_active:     .res MAX_OBJECTS        ; 0 = the slot is empty (its vertices are not drawn)
obj_dot:        .res MAX_OBJECTS        ; 1 = far away, drawn as a dot at obj_bb_x0/obj_bb_y0
obj_bb_x0:      .res MAX_OBJECTS        ; screen bounding box after transform_all;
obj_bb_x1:      .res MAX_OBJECTS        ; x0 = $FF when nothing of it is on screen
obj_bb_y0:      .res MAX_OBJECTS
obj_bb_y1:      .res MAX_OBJECTS

scr_x:          .res MAX_VERTS
scr_y:          .res MAX_VERTS
scr_ok:         .res MAX_VERTS          ; 0 = on screen, else VS_NEVER or VS_OFF + outcode

; Out of the low 32 KB: transformed vertices in world units (for clipping) and the
; hidden-line state.
        .segment "HIBSS2"
edge_a:         .res MAX_EDGES
edge_b:         .res MAX_EDGES
        .segment "HIBSS"
vw_xl:          .res MAX_VERTS
vw_xh:          .res MAX_VERTS
vw_yl:          .res MAX_VERTS
vw_yh:          .res MAX_VERTS
vw_zl:          .res MAX_VERTS
vw_zh:          .res MAX_VERTS
edge_hide:      .res MAX_EDGES          ; 1 = both of the edge's hull faces turn away
obj_edge0:      .res MAX_OBJECTS        ; the object's first edge in edge_a/edge_b
face_vis:       .res 32                 ; 1 = the face is seen (NO_FACE always is)
hl_base:        .res 1                  ; scratch of the hidden-line pass
hl_fc:          .res 1
hl_ec:          .res 1
hl_e:           .res 1
hl_f:           .res 1
hl_i:           .res 3
hl_ax:          .res 1
hl_ay:          .res 1
hl_d:           .res 4                  ; dx1, dy1, dx2, dy2
hl_p:           .res 2
model_ptr_y:    .res 1
oc_t:           .res 2

; scr_ok values. A vertex that failed projection keeps VS_OFF and the outcode bits of
; the half-spaces it is in; every one of them holds no point of the viewport, so an
; edge with both ends in the same one is not drawn.
VS_NEVER        = $80                   ; an empty slot, a dot or a culled object
VS_OFF          = $40                   ; transformed but not on the viewport
OC_NEAR         = $01                   ; z < NEAR_Z
OC_LEFT         = $02                   ; x < -z
OC_RIGHT        = $04                   ; x > z
OC_TOP          = $08                   ; y > 5z/8 (+2)
OC_BOTTOM       = $10                   ; -y > 5z/8 (+2)
OC_FAR          = $20                   ; z >= FAR: never clipped, the edge is dropped

        .segment "CODE"

; build_edges: fills edge_a/edge_b from the objects' models, with each object's vertices
; numbered after the previous object's. Sets vert_total and edge_total.
build_edges:
        lda     #0
        sta     vert_total
        sta     edge_total
        sta     cur_obj
@obj:   lda     cur_obj
        cmp     obj_count
        bcs     @done
        tax
        ldy     obj_model,x
        lda     model_ea_lo,y
        sta     model_ptr
        lda     model_ea_hi,y
        sta     model_ptr+1
        lda     model_ecount,y
        sta     cnt
        ldx     cur_obj
        lda     edge_total
        sta     obj_edge0,x
        ldx     edge_total
        ldy     #0
:       lda     #0
        sta     edge_hide,x
        lda     (model_ptr),y
        clc
        adc     vert_total
        sta     edge_a,x
        inx
        iny
        cpy     cnt
        bne     :-
        ldx     cur_obj
        ldy     obj_model,x
        lda     model_eb_lo,y
        sta     model_ptr
        lda     model_eb_hi,y
        sta     model_ptr+1
        ldx     edge_total
        ldy     #0
:       lda     (model_ptr),y
        clc
        adc     vert_total
        sta     edge_b,x
        inx
        iny
        cpy     cnt
        bne     :-
        stx     edge_total
        ldx     cur_obj
        ldy     obj_model,x
        lda     vert_total
        clc
        adc     model_vcount,y
        sta     vert_total
        inc     cur_obj
        jmp     @obj
@done:  rts

; spin_objects: advances every object's angles by its turn rates, and every fourth drawn
; frame moves animated models on to their next frame (model_next).
spin_objects:
        inc     anim_tick
        lda     anim_tick
        and     #3
        bne     :++
        ldx     obj_count
        dex
        bmi     :++
:       ldy     obj_model,x
        lda     model_next,y
        sta     obj_model,x
        dex
        bpl     :-
:       ldx     obj_count
        dex
        bmi     @done
:       lda     obj_yaw,x
        clc
        adc     obj_dyaw,x
        sta     obj_yaw,x
        lda     obj_pitch,x
        clc
        adc     obj_dpitch,x
        sta     obj_pitch,x
        lda     obj_roll,x
        clc
        adc     obj_droll,x
        sta     obj_roll,x
        dex
        bpl     :-
@done:  rts

; transform_all: every object's vertices to screen coordinates in scr_x/scr_y/scr_ok.
transform_all:
        lda     #0
        sta     cur_obj
        sta     vert_out
@obj:   lda     cur_obj
        cmp     obj_count
        bcc     :+
        rts
:       tax
        lda     #0
        sta     obj_dot,x
        lda     obj_active,x
        bne     :+
        jmp     @skip                   ; empty slot
:       lda     obj_z_hi,x
        cmp     #DOT_Z_HI
        bcc     :+
        jmp     @dot                    ; far away: one point
:       jsr     cull_object
        bcc     :+
        jmp     @skip                   ; nothing of it can be on screen
:       ldx     cur_obj
        lda     obj_yaw,x
        sta     rot_yaw
        lda     obj_pitch,x
        sta     rot_pitch
        lda     obj_roll,x
        sta     rot_roll
        jsr     build_matrix
        jsr     patch_matrix
        ldx     cur_obj
        ldy     obj_model,x
        lda     model_x_lo,y
        sta     vmod_x
        lda     model_x_hi,y
        sta     vmod_x+1
        lda     model_y_lo,y
        sta     vmod_y
        lda     model_y_hi,y
        sta     vmod_y+1
        lda     model_z_lo,y
        sta     vmod_z
        lda     model_z_hi,y
        sta     vmod_z+1
        lda     model_vcount,y
        sta     vmod_count
        lda     #$FF
        sta     bb_minx
        sta     bb_miny
        lda     #0
        sta     bb_maxx
        sta     bb_maxy
        sta     cur_vert
@vert:  ldy     cur_vert
        lda     (vmod_x),y
        sta     vx
        lda     (vmod_y),y
        sta     vy
        lda     (vmod_z),y
        sta     vz
        jsr     transform_vertex
        inc     vert_out
        inc     cur_vert
        lda     cur_vert
        cmp     vmod_count
        bne     @vert
        jsr     hidden_lines
@box:   ldx     cur_obj                 ; keep the box for hit tests
        lda     bb_minx
        sta     obj_bb_x0,x
        lda     bb_maxx
        sta     obj_bb_x1,x
        lda     bb_miny
        sta     obj_bb_y0,x
        lda     bb_maxy
        sta     obj_bb_y1,x
        lda     bb_maxx                 ; anything on screen: its box is drawn into
        cmp     bb_minx
        bcc     :+
        lda     bb_minx
        sta     lx0
        lda     bb_maxx
        sta     lx1
        lda     bb_miny
        sta     ly0
        lda     bb_maxy
        sta     ly1
        jsr     mark_dirty
:       inc     cur_obj
        jmp     @obj

; An empty slot or a dot: its vertices are marked not drawable.
@skip:  jsr     @hide_verts
        lda     #$FF
        sta     bb_minx
        lda     #0
        sta     bb_maxx
        jmp     @box
@dot:   jsr     @hide_verts
        ldx     cur_obj
        lda     obj_x_lo,x
        sta     wx
        lda     obj_x_hi,x
        sta     wx+1
        lda     obj_y_lo,x
        sta     wy
        lda     obj_y_hi,x
        sta     wy+1
        lda     obj_z_lo,x
        sta     wz
        lda     obj_z_hi,x
        sta     wz+1
        jsr     project_point
        lda     #$FF
        sta     bb_minx
        lda     #0
        sta     bb_maxx
        bcs     @box
        ldx     cur_obj
        lda     #1
        sta     obj_dot,x
        lda     px                      ; a 3x3 box around the dot (for hits and clearing)
        sta     bb_minx
        sta     bb_maxx
        lda     py
        sta     bb_miny
        sta     bb_maxy
        jmp     @box
@hide_verts:
        ldx     cur_obj
        ldy     obj_model,x
        lda     model_vcount,y
        sta     cnt
        ldx     vert_out
        lda     #VS_NEVER
:       sta     scr_ok,x
        inx
        dec     cnt
        bne     :-
        stx     vert_out
        rts

; The vertex transform multiplies by the matrix through the signed quarter-square table
; f (index n + 256): a*b = f(a+b) - f(b-a). With the vertex coordinate b held biased
; (b + 128) in Y, f(a+b) is at f + (128 + a) + Y and f(b-a) at f + (128 - a) + Y, so
; patch_matrix writes 128 + a and 128 - a into the operands' low bytes (the tables are
; page aligned, and |a| <= 127 keeps both in 1-255). Entry e = row * 3 + column.

.macro  patch_entry e
        lda     matrix+e
        eor     #$80                    ; 128 + a
        sta     .ident(.sprintf("xf%d_pa", e))+1
        sta     .ident(.sprintf("xf%d_pc", e))+1
        lda     #$80
        sec
        sbc     matrix+e                ; 128 - a
        sta     .ident(.sprintf("xf%d_pb", e))+1
        sta     .ident(.sprintf("xf%d_pd", e))+1
.endmacro

patch_matrix:
        .repeat 9, e
        patch_entry e
        .endrep
        rts

; prod E, FIRST, ACC: ACC (16 bit) = or += matrix entry E times the coordinate in Y.
.macro  prod e, first, acc
        sec
.ident(.sprintf("xf%d_pa", e)):
        lda     f_lo,y
.ident(.sprintf("xf%d_pb", e)):
        sbc     f_lo,y
  .if first
        sta     acc
  .else
        tax
  .endif
.ident(.sprintf("xf%d_pc", e)):
        lda     f_hi,y
.ident(.sprintf("xf%d_pd", e)):
        sbc     f_hi,y
  .if first
        sta     acc+1
  .else
        sta     t_hi
        txa
        clc
        adc     acc
        sta     acc
        lda     t_hi
        adc     acc+1
        sta     acc+1
  .endif
.endmacro

; to_world DEST, ACC, OBJ_LO, OBJ_HI: DEST = ACC / 128 + the object's position (X = object).
.macro  to_world dest, acc, pos_lo, pos_hi
        lda     acc
        asl
        lda     acc+1
        rol                             ; A = ACC bits 14-7
        clc
        adc     pos_lo,x
        sta     dest
        lda     acc+1                   ; high byte: the sign of ACC / 128
        and     #$80
        beq     :+
        lda     #$FF
:       adc     pos_hi,x
        sta     dest+1
.endmacro

; transform_vertex: vx, vy, vz (biased) -> screen position of vertex vert_out.
transform_vertex:
        ldy     vx
        prod    0, 1, acc0
        prod    3, 1, acc1
        prod    6, 1, acc2
        ldy     vy
        prod    1, 0, acc0
        prod    4, 0, acc1
        prod    7, 0, acc2
        ldy     vz
        prod    2, 0, acc0
        prod    5, 0, acc1
        prod    8, 0, acc2
        ldx     cur_obj
        to_world wx, acc0, obj_x_lo, obj_x_hi
        to_world wy, acc1, obj_y_lo, obj_y_hi
        to_world wz, acc2, obj_z_lo, obj_z_hi

        ldx     vert_out                ; kept for clipping
        lda     wx
        sta     vw_xl,x
        lda     wx+1
        sta     vw_xh,x
        lda     wy
        sta     vw_yl,x
        lda     wy+1
        sta     vw_yh,x
        lda     wz
        sta     vw_zl,x
        lda     wz+1
        sta     vw_zh,x
        jsr     project_point
        bcs     @out
        ldx     vert_out
        lda     px
        sta     scr_x,x
        lda     py
        sta     scr_y,x
        lda     #0
        sta     scr_ok,x
        jmp     widen_bbox
@out:   jsr     outcode
        ldx     vert_out
        sta     scr_ok,x
        rts

; outcode: A = VS_OFF + the OC_ bits of the world point wx, wy, wz.
outcode:
        lda     #VS_OFF
        sta     oc_t+1                  ; the result builds up here
        lda     wz+1                    ; near: z < NEAR_Z
        bmi     @near
        bne     :+
        lda     wz
        cmp     #NEAR_Z
        bcs     :+
@near:  lda     #OC_NEAR
        jsr     @set
:       lda     wz+1                    ; far
        bmi     :+
        cmp     #FAR_Z_HI
        bcc     :+
        lda     #OC_FAR
        jsr     @set
:       clc                             ; left: x + z < 0
        lda     wx
        adc     wz
        lda     wx+1
        adc     wz+1
        bvc     :+
        eor     #$80
:       bpl     :+
        lda     #OC_LEFT
        jsr     @set
:       sec                             ; right: z - x < 0
        lda     wz
        sbc     wx
        lda     wz+1
        sbc     wx+1
        bvc     :+
        eor     #$80
:       bpl     :+
        lda     #OC_RIGHT
        jsr     @set
:       lda     wz+1                    ; oc_t = (z >> 1) + (z >> 3) + 2, arithmetic shifts
        cmp     #$80
        ror
        sta     oc_t
        lda     wz
        ror
        sta     hl_p                    ; z >> 1 (low byte)
        lda     oc_t
        sta     hl_p+1
        cmp     #$80
        ror
        tax
        lda     hl_p
        ror
        tay
        txa
        cmp     #$80
        ror
        tax
        tya
        ror                             ; X/A = z >> 3
        clc
        adc     hl_p
        sta     hl_p
        txa
        adc     hl_p+1
        sta     hl_p+1
        lda     hl_p
        clc
        adc     #2
        sta     hl_p
        bcc     :+
        inc     hl_p+1
:       sec                             ; top: t - y < 0
        lda     hl_p
        sbc     wy
        lda     hl_p+1
        sbc     wy+1
        bvc     :+
        eor     #$80
:       bpl     :+
        lda     #OC_TOP
        jsr     @set
:       clc                             ; bottom: t + y < 0
        lda     hl_p
        adc     wy
        lda     hl_p+1
        adc     wy+1
        bvc     :+
        eor     #$80
:       bpl     :+
        lda     #OC_BOTTOM
        jsr     @set
:       lda     oc_t+1
        rts
@set:   ora     oc_t+1
        sta     oc_t+1
        rts

; cull_object: carry set when the bounding sphere of object X (radius from its model)
; is wholly outside the view: behind the near plane, or beyond one of the four sides
; (tested with twice the radius against x = -z, x = z, y = 5z/8 and -y = 5z/8, which
; covers the slant of the planes). Expects 0 <= z < DOT_Z. Uses acc0-acc2.
cull_object:
        ldy     obj_model,x
        lda     model_radius,y
        sta     acc2
        clc                             ; near: z + r < NEAR_Z
        adc     obj_z_lo,x
        lda     obj_z_hi,x
        adc     #0
        bne     :+
        lda     acc2
        clc
        adc     obj_z_lo,x
        cmp     #NEAR_Z
        bcc     @cull0
:       asl     acc2                    ; acc2 = 2r
        lda     #0
        rol
        sta     acc2+1
        clc                             ; left: x + z + 2r < 0
        lda     obj_x_lo,x
        adc     obj_z_lo,x
        sta     acc0
        lda     obj_x_hi,x
        adc     obj_z_hi,x
        bvs     @cull0                   ; |x| that large is off to the side
        sta     acc0+1
        lda     acc0
        clc
        adc     acc2
        lda     acc0+1
        adc     acc2+1
        bvs     @cull0
        bmi     @cull0
        jmp     :+
@cull0: sec
        rts
:        clc                             ; acc0 = z + 2r
        lda     obj_z_lo,x
        adc     acc2
        sta     acc0
        lda     obj_z_hi,x
        adc     acc2+1
        sta     acc0+1
        sec                             ; right: z + 2r - x < 0
        lda     acc0
        sbc     obj_x_lo,x
        lda     acc0+1
        sbc     obj_x_hi,x
        bvs     @cull
        bmi     @cull
        lda     obj_z_hi,x              ; acc1 = z/2 + z/8 + 2r
        lsr
        sta     acc1+1
        lda     obj_z_lo,x
        ror
        sta     acc1                    ; z / 2
        lda     acc1+1
        lsr
        lsr
        sta     acc0+1
        lda     acc1
        ror
        sta     acc0
        lsr     acc0+1
        ror     acc0                    ; z / 8
        clc
        lda     acc1
        adc     acc0
        sta     acc1
        lda     acc1+1
        adc     acc0+1
        sta     acc1+1
        clc
        lda     acc1
        adc     acc2
        sta     acc1
        lda     acc1+1
        adc     acc2+1
        sta     acc1+1
        sec                             ; top: acc1 - y < 0
        lda     acc1
        sbc     obj_y_lo,x
        lda     acc1+1
        sbc     obj_y_hi,x
        bvs     @cull
        bmi     @cull
        clc                             ; bottom: acc1 + y < 0
        lda     acc1
        adc     obj_y_lo,x
        lda     acc1+1
        adc     obj_y_hi,x
        bvs     @cull
        bmi     @cull
        clc
        rts
@cull:  sec
        rts

; hidden_lines: for a solid model, marks which of the object's edges lie only on hull
; faces that turn away (edge_hide). A face is seen when its three corners, at half
; screen resolution, turn clockwise or not at all; a face with a corner off the
; viewport counts as seen. The object's vertices end at vert_out.
hidden_lines:
.ifdef NO_HIDDEN
        rts                             ; control build: every edge drawn
.endif
        ldx     cur_obj
        ldy     obj_model,x
        lda     model_fcount,y
        bne     :+
        rts
:       sta     hl_fc
        lda     model_ecount,y
        sta     hl_ec
        lda     obj_edge0,x
        sta     hl_e
        lda     model_hl_lo,y
        sta     model_ptr
        lda     model_hl_hi,y
        sta     model_ptr+1
        lda     vert_out
        sec
        sbc     vmod_count
        sta     hl_base
        lda     #1
        ldx     #NO_FACE
        sta     face_vis,x
        lda     #0
        sta     hl_f
        tay
@face:  clc                             ; the face's three corners
        lda     (model_ptr),y
        adc     hl_base
        sta     hl_i
        iny
        lda     (model_ptr),y
        adc     hl_base
        sta     hl_i+1
        iny
        lda     (model_ptr),y
        adc     hl_base
        sta     hl_i+2
        iny
        sty     model_ptr_y
        tax
        ldy     hl_i+1
        lda     scr_ok,x
        ora     scr_ok,y
        ldx     hl_i
        ora     scr_ok,x
        beq     :+
        jmp     @seen
:       lda     scr_x,x                 ; corner a at half resolution
        lsr
        sta     hl_ax
        lda     scr_y,x
        lsr
        sta     hl_ay
        lda     scr_x,y                 ; b - a
        lsr
        sec
        sbc     hl_ax
        sta     hl_d
        lda     scr_y,y
        lsr
        sec
        sbc     hl_ay
        sta     hl_d+1
        ldx     hl_i+2                  ; c - a
        lda     scr_x,x
        lsr
        sec
        sbc     hl_ax
        sta     hl_d+2
        lda     scr_y,x
        lsr
        sec
        sbc     hl_ay
        sta     hl_d+3
        ; Seen when P = dx1 * dy2 >= Q = dy1 * dx2, decided from the signs and, when
        ; they agree, from the logarithms of the magnitudes (hl_log: 16 steps an
        ; octave, so only faces within a few percent of edge-on can come out wrong).
        ldx     hl_d                    ; P
        beq     @p0
        ldy     hl_d+3
        beq     @p0
        lda     hl_log,x
        clc
        adc     hl_log,y
        sta     hl_p                    ; log |P|
        txa
        eor     hl_d+3
        sta     hl_p+1                  ; bit 7: P < 0
        ldx     hl_d+1                  ; Q
        beq     @q0
        ldy     hl_d+2
        beq     @q0
        txa
        eor     hl_d+2
        eor     hl_p+1
        bmi     @signs                  ; opposite signs: seen when P > 0
        lda     hl_log,x
        clc
        adc     hl_log,y                ; log |Q|
        bit     hl_p+1
        bmi     @neg
        cmp     hl_p                    ; both > 0: seen when |Q| <= |P|
        beq     @seen
        bcc     @seen
        bcs     @away
@neg:   cmp     hl_p                    ; both < 0: seen when |Q| >= |P|
        bcs     @seen
        bcc     @away
@q0:                                    ; Q = 0: seen when P > 0
@signs: bit     hl_p+1
        bpl     @seen
        bmi     @away
@p0:    ldx     hl_d+1                  ; P = 0: seen when Q <= 0
        beq     @seen
        ldy     hl_d+2
        beq     @seen
        txa
        eor     hl_d+2
        bmi     @seen
@away:  lda     #0
        .byte   $2C                     ; skip the next instruction
@seen:  lda     #1
        ldx     hl_f
        sta     face_vis,x
        ldy     model_ptr_y
        inc     hl_f
        lda     hl_f
        cmp     hl_fc
        beq     :+
        jmp     @face
:
        lda     hl_ec                   ; the edges: Y is at the first face list
        sta     hl_f                    ; (reused: edges left)
        ldx     hl_e
@edge:  lda     (model_ptr),y
        sty     model_ptr_y
        stx     hl_base                 ; (reused: the edge being marked)
        tax
        lda     face_vis,x
        sta     hl_ax
        tya
        clc
        adc     hl_ec
        tay
        lda     (model_ptr),y           ; the second face list
        tax
        lda     face_vis,x
        ora     hl_ax
        eor     #1
        ldx     hl_base
        sta     edge_hide,x
        inx
        ldy     model_ptr_y
        iny
        dec     hl_f
        bne     @edge
        rts

.macro  recip_from_wz
        lda     wz+1                    ; recip index = z >> 2 (10 bits): page and offset
        sta     acc_hi
        lda     wz
        lsr     acc_hi
        ror
        lsr     acc_hi
        ror
        tay
        lda     acc_hi                  ; 0-3: which page of the table
        clc
        adc     #>recip
        sta     @rd+2
@rd:    lda     recip,y
        sta     recip_val
        sta     mr_p1+1                 ; the factor into mul_r's operands
        sta     mr_p3+1
        eor     #$FF
        sta     mr_p2+1
        sta     mr_p4+1
.endmacro

; project_point: the world point wx, wy, wz (16 bit) to the viewport: px, py with carry
; clear, or carry set when it is behind the near plane, too far or off the viewport.
project_point:
        lda     wz+1                    ; near and far limits
        bmi     @out
        cmp     #FAR_Z_HI
        bcs     @out
        cmp     #0
        bne     :+
        lda     wz
        cmp     #NEAR_Z
        bcc     @out
:       recip_from_wz

        lda     wx                      ; x offset = |wx| * recip / 256
        ldy     wx+1
        jsr     scale_coord
        bcs     @out
        cmp     #128
        bcs     @out
        ldy     neg_flag
        beq     :+
        eor     #$FF                    ; x = 128 - off
        sec
        adc     #VIEW_CX
        jmp     @xset
:       clc                             ; x = 128 + off
        adc     #VIEW_CX
@xset:  sta     px
        lda     wy                      ; y the same way; up is +y
        ldy     wy+1
        jsr     scale_coord
        bcs     @out
        cmp     #VIEW_HALF_H+1
        bcs     @out
        ldy     neg_flag
        bne     :+
        eor     #$FF                    ; above the centre: y = 79 - off
        sec
        adc     #VIEW_CY
        jmp     @yset
:       clc                             ; below: y = 79 + off
        adc     #VIEW_CY
@yset:  sta     py
        clc
        rts
@out:   sec
        rts

; scale_coord: A/Y = a signed 16-bit coordinate (low/high). A = |c| * r / 256 with carry
; clear, or carry set when that is 256 or more; neg_flag = 1 when c < 0. r is the factor
; project_point patched into mul_r. |c| up to 511 takes one short multiply.
scale_coord:
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
:       ldy     off_lo
        lda     off_hi
        bne     :+
        jsr     mul_r                   ; below 256
        clc
        rts
:       cmp     #1
        bne     @big
        jsr     mul_r                   ; 256-511: r + (low byte * r) / 256
        clc
        adc     recip_val
        rts
@big:   ldy     recip_val               ; 512 and up: high byte * r + (low byte * r) / 256
        jsr     umul8
        lda     mul_hi
        bne     @far
        lda     mul_lo
        sta     acc_lo
        ldy     off_lo
        jsr     mul_r
        clc
        adc     acc_lo
        rts
@far:   sec
        rts

; widen_bbox: the object's bounding box takes in vertex X.
widen_bbox:
        lda     scr_y,x
        cmp     bb_miny
        bcs     :+
        sta     bb_miny
:       cmp     bb_maxy
        bcc     :+
        sta     bb_maxy
:       lda     scr_x,x
        cmp     bb_minx
        bcs     :+
        sta     bb_minx
:       cmp     bb_maxx
        bcc     :+
        sta     bb_maxx
:       rts

; mul_r: A = (Y * the factor patched in by project_point) / 256, both unsigned bytes.
; The quarter-square tables as in umul8, with only the high byte kept.
mul_r:
        sec
mr_p1:  lda     sq1_lo,y
mr_p2:  sbc     sq2_lo,y
mr_p3:  lda     sq1_hi,y
mr_p4:  sbc     sq2_hi,y
        rts

; project: A/Y = a signed 16-bit coordinate (low/high). Returns A = |c| * recip_val / 256
; with carry clear, or carry set when that is 256 or more. neg_flag = 1 when c < 0.
project:
        sta     off_lo
        sty     off_hi
        lda     #0
        sta     neg_flag
        lda     off_hi
        bpl     :+
        inc     neg_flag
        sec
        lda     #0
        sbc     off_lo
        sta     off_lo
        lda     #0
        sbc     off_hi
        sta     off_hi
:       lda     off_hi                  ; |c| * r / 256 = hi * r + (lo * r) / 256
        beq     @low
        ldy     recip_val
        jsr     umul8
        lda     mul_hi
        bne     @big
        lda     mul_lo
        sta     acc_lo                  ; hi * r, below 256
        lda     off_lo
        ldy     recip_val
        jsr     umul8
        lda     mul_hi
        clc
        adc     acc_lo
        rts                             ; carry set when the sum passed 255
@low:   lda     off_lo
        ldy     recip_val
        jsr     umul8
        lda     mul_hi
        clc
        rts
@big:   sec
        rts
