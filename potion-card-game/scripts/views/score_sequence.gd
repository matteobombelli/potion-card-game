class_name ScoreSequence
extends RefCounted
## Replays a Scoring.score_potion() breakdown on a PotionView, step by step:
## card values, modifier zaps, potion type, special order, round total.

const STEP := 0.24       # pause between card values
const ZAP_STEP := 0.3    # pause between modifier zaps


static func run(potion: PotionView, b: Dictionary) -> void:
	var tree := potion.get_tree()
	var running := 0
	var toward := potion.toward_center()
	var rise := 80.0 * -toward.y   # floating numbers drift toward the table centre, away from the cards
	var text_off := toward * (CardArt.SIZE.y / 2.0 + 38.0)
	potion.set_round_score(0)

	# 1. Card values, left to right.
	for i in potion.cards.size():
		var v := potion.cards[i]
		var value: int = b.base[i]
		running += value
		v.pop(0.5)
		var text := "%+d" % value if value != 0 else "0"
		Fx.float_text(v.global_position + text_off, text, Palette.NEGATIVE if value < 0 else Palette.TEXT, 46, rise)
		potion.set_round_score(running)
		await tree.create_timer(STEP).timeout

	# 2. Modifier icons zap the cards they reward.
	for hit in b.mod_hits:
		var src := potion.cards[hit.src]
		var dst := potion.cards[hit.dst]
		var col := CardArt.fx_color(src.card.modifier_color)
		Fx.zap(src.icon_global_position(), dst.global_position, col)
		dst.pop(0.6)
		running += hit.pts
		var jitter := Vector2(randf_range(-14, 14), 0)
		Fx.float_text(dst.global_position + text_off + jitter, "+%d" % hit.pts, col.lightened(0.3), 40, rise)
		potion.set_round_score(running)
		await tree.create_timer(ZAP_STEP).timeout

	# 3. Potion type bonus.
	if b.bonus.pts > 0:
		running += b.bonus.pts
		var colors: Array = potion.cards.map(func(v): return CardArt.fx_color(v.card.color))
		colors.append(Palette.SCORE)
		for v in potion.cards:
			v.pop(1.0)
		Fx.confetti(potion.global_position, colors, 70, 950.0)
		potion.set_round_score(running)
		var at := potion.get_viewport().get_canvas_transform() * (potion.global_position + toward * (CardArt.SIZE.y + 30.0))
		await Fx.banner("%s  +%d" % [b.bonus.name.to_upper(), b.bonus.pts], Palette.TITLE, 0.55, 72, at)

	# 4. Special order.
	if not b.order.is_empty():
		potion.show_order_result(b.order.met)
		if b.order.met:
			running += b.order.pts
			potion.set_round_score(running)
			Fx.float_text(potion.order_tag_global_position() + toward * 40, "ORDER +%d" % b.order.pts, Palette.POSITIVE, 36, rise * 0.6)
		await tree.create_timer(0.45).timeout

	# 5. Round total.
	Fx.float_text(potion.global_position + toward * CardArt.SIZE.y * 0.85, "= %d" % b.total,
		Palette.SCORE if b.total >= 0 else Palette.NEGATIVE, 56, rise * 0.5, 1.1)
	await tree.create_timer(0.35).timeout
