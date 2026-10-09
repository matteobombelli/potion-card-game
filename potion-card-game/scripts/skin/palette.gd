class_name Palette
extends RefCounted
## UI and table colours. Card colours live in CardArt; everything else is here,
## so a restyle doesn't mean hunting colour literals through the code.

# Text
const TEXT := Color(0.95, 0.92, 1.0)
const TEXT_DIM := Color(0.8, 0.75, 0.9)
const TEXT_OUTLINE := Color(0.06, 0.03, 0.1)
const TITLE := Color(1.0, 0.9, 0.5)          # banners, active player, turn title
const SCORE := Color(1.0, 0.86, 0.3)         # running totals
const POSITIVE := Color(0.7, 1.0, 0.75)
const NEGATIVE := Color(1.0, 0.5, 0.5)

# Highlights
const TARGET := Color(1.0, 0.85, 0.4)        # glow on things you can click
const SWAP := Color(0.8, 0.6, 1.0)           # black-card swap step
const ORDER_NEUTRAL := Color(1.0, 0.85, 0.4) # border of non-colour special orders

# Panels and buttons
const PANEL := Color(0.2, 0.13, 0.28)
const PANEL_HOVER := Color(0.27, 0.18, 0.38)
const PANEL_PRESSED := Color(0.14, 0.09, 0.2)
const PANEL_DISABLED := Color(0.12, 0.1, 0.15)
const PANEL_BORDER := Color(0.45, 0.35, 0.6)
const TAG_BG := Color(0.16, 0.1, 0.22, 0.95)
const OVERLAY := Color(0.03, 0.01, 0.06, 0.6)

# Table
const TABLE := Color(0.07, 0.045, 0.1)
const FELT_EDGE := Color(0.16, 0.1, 0.22)
const FELT_CENTER := Color(0.24, 0.16, 0.32)
const SEAT_FILL := Color(1, 1, 1, 0.04)
const SEAT_BORDER := Color(1, 1, 1, 0.12)
const SEAT_ACTIVE := Color(1.0, 0.9, 0.5)
const BUBBLES := [Color(1, 0.2, 0.3, 0.16), Color(0.2, 1, 0.4, 0.16), Color(0.3, 0.4, 1, 0.18), Color(1, 0.95, 0.3, 0.14)]

# Effects
const DUST := Color(0.85, 0.82, 0.95)
const SMOKE := Color(0.12, 0.08, 0.18, 0.8)
const BLACK_RING := Color(0.5, 0.3, 0.75)
const CONFETTI := [Color(1, 0, 0), Color(0, 1, 0), Color(0.2, 0.4, 1), Color(1, 1, 0), Color.WHITE]
