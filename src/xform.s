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
        lda     #0
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
        inc     cur_obj
        jmp     @obj

; row_dot ROW: acc = matrix[ROW*3..ROW*3+2] . (vx, vy, vz), signed 16 bit.
.macro  row_dot row
        lda     matrix+row*3
        ldy     vx
        jsr     smul
        lda     mul_lo
        sta     acc_lo
        lda     mul_hi
        sta     acc_hi
        lda     matrix+row*3+1
        ldy     vy
        jsr     smul
        lda     mul_lo
        clc
        adc     acc_lo
        sta     acc_lo
        lda     mul_hi
        adc     acc_hi
        sta     acc_hi
        lda     matrix+row*3+2
        ldy     vz
        jsr     smul
        lda     mul_lo
        clc
        adc     acc_lo
        sta     acc_lo
        lda     mul_hi
        adc     acc_hi
        sta     acc_hi
.endmacro

; to_world DEST, OBJ_LO, OBJ_HI: DEST = acc / 128 + the object's position (X = object).
.macro  to_world dest, pos_lo, pos_hi
        lda     acc_lo
        asl
        lda     acc_hi
        rol                             ; A = acc bits 14-7
        clc
        adc     pos_lo,x
        sta     dest
        lda     acc_hi                  ; high byte: the sign of acc / 128
        and     #$80
        beq     :+
        lda     #$FF
:       adc     pos_hi,x
        sta     dest+1
.endmacro

transform_vertex:
        row_dot 0
        ldx     cur_obj
        to_world wx, obj_x_lo, obj_x_hi
        row_dot 1
        ldx     cur_obj
        to_world wy, obj_y_lo, obj_y_hi
        row_dot 2
        ldx     cur_obj
        to_world wz, obj_z_lo, obj_z_hi

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
@out:   rts

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
