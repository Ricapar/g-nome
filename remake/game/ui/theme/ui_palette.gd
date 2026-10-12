class_name UIPalette
## Colour tokens from remake/UI-DESIGN.md (sampled from the original, cleaned up).
## Values above 1.0 are HDR and bloom through the 2D glow (UI screens set Viewport.use_hdr_2d).

const PHOSPHOR := Color(0.25, 1.9, 0.42)
const PHOSPHOR_DIM := Color(0.0, 0.62, 0.12)
const STATUS := Color(1.6, 1.5, 0.15)
const LED_ON := Color(0.3, 2.6, 0.5)
const LED_OFF := Color(0.03, 0.06, 0.04)

# [hi, base, lo] triples per material
const RED := [Color("#ad5f5b"), Color("#912f2b"), Color("#6e2622")]
const STEEL := [Color("#d4d0d2"), Color("#bbb8bb"), Color("#8d8b89")]
const IRON := [Color("#3c4238"), Color("#262522"), Color("#151612")]
const BEZEL := [Color("#8a92a8"), Color("#62736c"), Color("#465855")]
const BLUE := [Color("#4a51a8"), Color("#272d90"), Color("#12248f")]

const BACKGROUND := Color("#0b0c0a")
