; C64 hardware addresses used by the game.

CPU_PORT          = $01

SCREEN            = $0400
COLOR_RAM         = $D800

VIC_CTRL1         = $D011
VIC_RASTER        = $D012
VIC_IRQ_FLAGS     = $D019
VIC_IRQ_MASK      = $D01A
VIC_BORDER        = $D020
VIC_BG0           = $D021

CIA1_ICR          = $DC0D
CIA2_ICR          = $DD0D

; The debug-cartridge result port: Kernal64's k64run --debugcart ends the run when a
; program writes here and exits with the value written (0 = passed).
DEBUGCART_RESULT  = $D7FF

NMI_VECTOR        = $FFFA
IRQ_VECTOR        = $FFFE

RASTER_IRQ_LINE   = 250

COLOR_BLACK       = 0
COLOR_CYAN        = 3
