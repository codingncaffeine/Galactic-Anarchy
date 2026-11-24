; Zero-page variables of the game, the map and the sound, declared before any code
; uses them (ca65 only picks zero-page addressing for symbols it already knows).

        .segment "ZEROPAGE"
; from game.s
state:          .res 1
state_timer:    .res 1
ticks:          .res 1                  ; ticks to run this drawn frame
last_frame:     .res 1
rng:            .res 2
cross_x:        .res 1                  ; crosshair, viewport pixels (moved by the IRQ)
cross_y:        .res 1
joy:            .res 1                  ; port 2, 1 = pressed (bits: up down left right fire)
fire_new:       .res 1                  ; set by the IRQ when fire goes down
fire_wait:      .res 1
laser_t:        .res 1
score:          .res 3
hiscore:        .res 3
shield:         .res 1
sector:         .res 1                  ; 0-based
kills:          .res 1
quota:          .res 1
spawn_t:        .res 1
speed:          .res 1
active_max:     .res 1                  ; this sector: enemies on screen at once,
fire_rate:      .res 1                  ; chance to fire per tick (of 256),
spawn_delay:    .res 1                  ; ticks between arrivals
g_tmp:          .res 2
panel_dirty:    .res 1
hit_best:       .res 1
hit_z:          .res 2
game_on:        .res 1                  ; the raster interrupt runs irq_game
flash_t:        .res 1
burst_k:        .res 1
g_off:          .res 1
g_spy:          .res 1
g_on:           .res 1
g_big:          .res 1
ptr2:           .res 2
kills_total:    .res 1
t5_lo:          .res 1
t5_hi:          .res 1
t5_acc:         .res 1
irq_msb:        .res 1
spr_on:         .res 1                  ; sprites 1-3: on, doubled (bits 1-3)
spr_big:        .res 1
spr_xl:         .res 4                  ; sprite positions for the interrupt to apply
spr_xh:         .res 4
spr_y:          .res 4

; from map.s
map_col:        .res 1                  ; the player's column, $FF before the first jump
map_row:        .res 1
map_loop:       .res 1                  ; times round the map
map_sel:        .res 1                  ; index into map_cand
map_cand_n:     .res 1
map_cand:       .res 3                  ; rows the player may jump to
cross_lock:     .res 1                  ; 1: the interrupt leaves the crosshair alone
joy_last:       .res 1
faction:        .res 1                  ; of the sector being flown
danger:         .res 1
boss_fight:     .res 1
map_tmp:        .res 3
g_nx:           .res 1                  ; draw_diamond: centre, radius, the four points
g_ny:           .res 1
g_nr:           .res 1
g_dl:           .res 1
g_dr:           .res 1
g_dt:           .res 1
g_db:           .res 1

; from sound.s
snd_req:        .res 1
laser_snd:      .res 1                  ; frames of the laser sweep left
laser_freq:     .res 1                  ; its pitch, high byte
v2_gate:        .res 1                  ; frames until voice 2's gate goes off
v3_gate:        .res 1
        .segment "CODE"
