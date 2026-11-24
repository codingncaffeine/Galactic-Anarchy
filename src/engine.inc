; Engine constants. tools/GaTool/Program.cs (Tables) generates tables for the same
; viewport; keep the two in step.

; Viewport: 256 x 159 hires pixels, character columns 4-35, character rows 0-19.
; Line 159 (the last of row 19) is never drawn: the raster split switches to text mode
; during that line.
VIEW_CX           = 128
VIEW_CY           = 79
VIEW_HALF_H       = 79                  ; y offsets beyond this are off screen
VIEW_LEFT_CELLS   = 4
VIEW_ROWS         = 20

; Points nearer than this are behind the camera for drawing purposes.
NEAR_Z            = 128
FAR_Z_HI          = $10                 ; z >= $1000 is too far for the reciprocal table

MAX_VERTS         = 128
MAX_EDGES         = 255
MAX_OBJECTS       = 8
DOT_Z_HI          = $06                 ; objects from z = $0600 on are drawn as a dot

; The two frame buffers, one per VIC bank:
;   buffer 0: bank 2, screen $8400, font $8800, bitmap $A000
;   buffer 1: bank 3, screen $C400, font $C800, bitmap $E000
BUF0_SCREEN       = $8400
BUF1_SCREEN       = $C400
BUF0_FONT         = $8800
BUF1_FONT         = $C800
BUF0_BITMAP_HI    = $A0
BUF1_BITMAP_HI    = $E0
BUF0_BANK_BITS    = %01                 ; $DD00 bits 0-1 select the VIC bank (inverted)
BUF1_BANK_BITS    = %00

D011_BITMAP       = $3B                 ; bitmap mode, screen on, 25 rows, y scroll 3
D011_TEXT         = $1B
D018_BITMAP       = $18                 ; screen at +$0400, bitmap at +$2000
D018_TEXT         = $12                 ; screen at +$0400, font at +$0800

SPLIT_LINE        = 51 + 159            ; last viewport line: switch to text for the panel
TOP_LINE          = 255                 ; below the screen on PAL and NTSC: back to bitmap

PANEL_ROW         = 20

; Results of a benchmark run, read by test/run.sh through k64run --dump.
RESULTS           = $0340
