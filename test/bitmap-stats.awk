# Reads k64run --dump lines of the two frame buffers' bitmaps ($A000 and $E000, 8000
# bytes each) and prints, summed over both: set pixels in the viewport's left column
# (x 0), its right column (x 255), its top row (y 0), and in the whole viewport.
# Plain POSIX awk (no gawk extensions).
# The viewport is character columns 4-35 and rows 0-19 of each bitmap.
function hex(s,   i, v) { s = tolower(s); v = 0
  for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
  return v }
function bits(b,   n) { n = 0; while (b) { n += b % 2; b = int(b / 2) } return n }
/^[0-9a-fA-F]+:/ {
  addr = hex(substr($1, 1, length($1) - 1))
  for (i = 2; i <= NF; i++) mem[addr + i - 2] = hex($i)
}
END {
  left = right = top = lit = 0
  for (base = 40960; base <= 57344; base += 16384)      # $A000, $E000
    for (row = 0; row < 20; row++)
      for (col = 4; col <= 35; col++)
        for (line = 0; line < 8; line++) {
          b = mem[base + row * 320 + col * 8 + line]
          if (row == 19 && line == 7) continue          # line 159 is never drawn
          lit += bits(b)
          if (col == 4 && b >= 128) left++
          if (col == 35 && b % 2 == 1) right++
          if (row == 0 && line == 0) top += bits(b)
        }
  print left, right, top, lit
}
