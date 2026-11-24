; C64 hardware addresses used by the game.

CPU_PORT          = $01
PAL_FLAG          = $02A6               ; set by the KERNAL at boot: 1 = PAL, 0 = NTSC

SCREEN            = $0400
COLOR_RAM         = $D800

VIC_CTRL1         = $D011
VIC_RASTER        = $D012
VIC_MEM           = $D018
VIC_IRQ_FLAGS     = $D019
VIC_IRQ_MASK      = $D01A
VIC_BORDER        = $D020
VIC_BG0           = $D021

CIA1_PRA          = $DC00               ; joystick in port 2 (bits 0-4, active low)
CIA1_ICR          = $DC0D

CIA2_PRA          = $DD00               ; bits 0-1: VIC bank
CIA2_TA_LO        = $DD04
CIA2_TA_HI        = $DD05
CIA2_TB_LO        = $DD06
CIA2_TB_HI        = $DD07
CIA2_ICR          = $DD0D
CIA2_CRA          = $DD0E
CIA2_CRB          = $DD0F

JOY_FIRE          = %00010000

; The debug-cartridge result port: Kernal64's k64run --debugcart ends the run when a
; program writes here and exits with the value written (0 = passed).
DEBUGCART_RESULT  = $D7FF

NMI_VECTOR        = $FFFA
IRQ_VECTOR        = $FFFE

COLOR_BLACK       = 0
COLOR_WHITE       = 1
COLOR_CYAN        = 3
