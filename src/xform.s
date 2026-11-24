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

scr_x:          .res MAX_VERTS
scr_y:          .res MAX_VERTS
scr_ok:         .res MAX_VERTS          ; 0 = on screen, else not drawable
edge_a:         .res MAX_EDGES
edge_b:         .res MAX_EDGES

        .segment "RODATA"
; Per model number: vertex and edge arrays and counts.
model_vcount:   .byte MODEL_CUBE_VERTS, MODEL_ICO_VERTS
model_ecount:   .byte MODEL_CUBE_EDGES, MODEL_ICO_EDGES
model_x_lo:     .byte <model_cube_x, <model_ico_x
model_x_hi:     .byte >model_cube_x, >model_ico_x
model_y_lo:     .byte <model_cube_y, <model_ico_y
model_y_hi:     .byte >model_cube_y, >model_ico_y
model_z_lo:     .byte <model_cube_z, <model_ico_z
model_z_hi:     .byte >model_cube_z, >model_ico_z
model_ea_lo:    .byte <model_cube_ea, <model_ico_ea
model_ea_hi:    .byte >model_cube_ea, >model_ico_ea
model_eb_lo:    .byte <model_cube_eb, <model_ico_eb
model_eb_hi:    .byte >model_cube_eb, >model_ico_eb

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
        ldx     edge_total
        ldy     #0
:       lda     (model_ptr),y
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

; spin_objects: advances every object's angles by its turn rates.
spin_objects:
        ldx     obj_count
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

        ldx     vert_out
        lda     #1
        sta     scr_ok,x                ; not drawable until proven otherwise
        lda     wz+1                    ; near and far limits
        bmi     @out
        cmp     #FAR_Z_HI
        bcs     @out
        cmp     #0
        bne     :+
        lda     wz
        cmp     #NEAR_Z
        bcc     @out
:       lda     wz+1                    ; recip index = z >> 2 (10 bits): page and offset
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

        lda     wx                      ; x offset = |wx| * recip / 256
        ldy     wx+1
        jsr     project
        bcs     @out
        cmp     #128
        bcs     @out
        ldy     neg_flag
        beq     :+
        eor     #$FF                    ; x = 128 - off
        sec
        adc     #VIEW_CX
        jmp     :++
:       clc                             ; x = 128 + off
        adc     #VIEW_CX
:       ldx     vert_out
        sta     scr_x,x

        lda     wy
        ldy     wy+1
        jsr     project
        bcs     @out
        cmp     #VIEW_HALF_H+1
        bcs     @out
        ldy     neg_flag
        bne     :+
        eor     #$FF                    ; up is +y: screen y = 79 - off
        sec
        adc     #VIEW_CY
        jmp     :++
:       clc                             ; screen y = 79 + off
        adc     #VIEW_CY
:       ldx     vert_out
        sta     scr_y,x
        lda     #0
        sta     scr_ok,x
        jmp     widen_bbox
@out:   rts

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

; draw_edges: every edge whose two ends are on screen.
draw_edges:
        lda     #0
        sta     cur_vert                ; reused as the edge counter
@edge:  lda     cur_vert
        cmp     edge_total
        bcs     @done
        tax
        ldy     edge_a,x
        lda     edge_b,x
        tax
        lda     scr_ok,y
        ora     scr_ok,x
        bne     @skip
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
@done:  rts
