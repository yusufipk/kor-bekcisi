class_name Upgrades
extends RefCounted
## Upgrade catalogue. Weapons and passive stats; every pick stacks multiplicatively
## with the global stats in Game.stats so late builds snowball.
##
## Slots are limited (4 weapons, 4 passives) so every run ends in a different
## build. A weapon at WEAPON_MAX plus its partner passive can evolve from a chest.

const MAX_WEAPONS := 4
const MAX_PASSIVES := 4
const WEAPON_MAX := 7
const EVO_LEVEL := 8

const WEAPONS := {
	"bolt": {"name": "Kor Oku", "icon": "➶", "color": Color(1.0, 0.55, 0.15),
		"desc": "En yakın düşmana kor fırlatır.",
		"lv": ["+1 ok", "+%30 hasar", "Delip geçer +1", "+1 ok", "%20 daha hızlı", "+2 ok, delip geçer +1"]},
	"orbit": {"name": "Fener Halkası", "icon": "◎", "color": Color(1.0, 0.8, 0.3),
		"desc": "Etrafında dönen alevler.",
		"lv": ["+1 alev", "+%30 hasar", "Daha geniş ve hızlı", "+1 alev", "+%40 hasar", "+2 alev"]},
	"chain": {"name": "Kıvılcım Zinciri", "icon": "ϟ", "color": Color(0.55, 0.85, 1.0),
		"desc": "Düşmandan düşmana sekip yakan şimşek.",
		"lv": ["+2 sekme", "+%35 hasar", "Daha sık", "+1 şimşek", "+3 sekme", "+%50 hasar"]},
	"nova": {"name": "Kor Dalgası", "icon": "✺", "color": Color(1.0, 0.4, 0.3),
		"desc": "Düşmanları savuran halka dalga.",
		"lv": ["+%25 alan", "+%40 hasar", "Daha sık", "+%25 alan", "Çift dalga", "+%60 hasar"]},
	"blade": {"name": "Dönen Tırpan", "icon": "↺", "color": Color(0.85, 0.95, 1.0),
		"desc": "Gittiğin yöne fırlayıp geri dönen tırpan.",
		"lv": ["+1 tırpan", "+%30 hasar", "Daha uzağa", "+1 tırpan", "+%40 hasar", "+2 tırpan"]},
	"trail": {"name": "Alev İzi", "icon": "♨", "color": Color(1.0, 0.35, 0.1),
		"desc": "Koşarken arkanda yanan iz. Kayınca büyür.",
		"lv": ["+%40 hasar", "İz daha uzun kalır", "+%25 genişlik", "+%50 hasar", "İz daha uzun kalır", "+%60 hasar"]},
	"meteor": {"name": "Gök Kıvılcımı", "icon": "☄", "color": Color(1.0, 0.72, 0.4),
		"desc": "Kalabalığın ortasına düşen göktaşı.",
		"lv": ["+1 göktaşı", "+%35 alan", "Daha sık", "+1 göktaşı", "+%50 hasar", "+2 göktaşı"]},
}

## Evolutions: weapon at max level + partner passive, offered by a chest.
const EVOS := {
	"bolt": {"partner": "crit", "name": "Güneş Mızrağı", "icon": "☀", "color": Color(1.0, 0.86, 0.4),
		"desc": "Dev ışık mızrakları her şeyi deler, sonunda patlar."},
	"orbit": {"partner": "area", "name": "Fener Tacı", "icon": "❂", "color": Color(1.0, 0.9, 0.5),
		"desc": "İki halka ters yönde döner, düzenli olarak dışa nabız atar."},
	"chain": {"partner": "haste", "name": "Fırtına Gözü", "icon": "⚡", "color": Color(0.6, 0.85, 1.0),
		"desc": "Tepende bir bulut, gökten durmadan yıldırım indirir."},
	"nova": {"partner": "hp", "name": "Yanardağ Kalbi", "icon": "✹", "color": Color(1.0, 0.45, 0.2),
		"desc": "Sık ve dev dalgalar; vurduğu her düşman can verir."},
	"blade": {"partner": "speed", "name": "Kasırga", "icon": "❖", "color": Color(0.75, 0.95, 1.0),
		"desc": "Tırpanlar etrafında dönen üç kasırgaya dönüşür."},
	"trail": {"partner": "regen", "name": "Lav Nehri", "icon": "♨", "color": Color(1.0, 0.5, 0.15),
		"desc": "Geniş, uzun süren lav; içindekiler yavaşlar."},
	"meteor": {"partner": "amount", "name": "Yıldız Yağmuru", "icon": "✵", "color": Color(0.9, 0.75, 1.0),
		"desc": "Gökten durmadan yıldız yağar."},
}

const PASSIVES := {
	"hp": {"name": "Sağlam Yürek", "icon": "♥", "desc": "+25 can, canı doldurur"},
	"speed": {"name": "Rüzgâr Adım", "icon": "»", "desc": "+%8 hareket hızı"},
	"power": {"name": "Kızgın Kor", "icon": "▲", "desc": "+%15 hasar"},
	"haste": {"name": "Çabuk El", "icon": "◷", "desc": "-%8 bekleme süresi"},
	"area": {"name": "Geniş Işık", "icon": "◯", "desc": "+%12 alan"},
	"amount": {"name": "Çifte Kıvılcım", "icon": "✚", "desc": "Bütün silahlara +1 mermi"},
	"magnet": {"name": "Çekim Taşı", "icon": "◈", "desc": "+%40 toplama menzili"},
	"regen": {"name": "Yosun Kanı", "icon": "✿", "desc": "+0,8 can/sn yenilenme"},
	"wisdom": {"name": "Bilge Göz", "icon": "✦", "desc": "+%15 tecrübe"},
	"crit": {"name": "Keskin Bakış", "icon": "✸", "desc": "+%8 kritik şansı (2,2x)"},
}

## Base numbers of a weapon at level l, before passives and evolutions. Weapons
## fire from these and the level-up cards print them, so the two never disagree.
## n: projectiles, flames or waves; dmg: per hit; cd: seconds between shots;
## r: radius or reach in metres; plus pierce, hops, life and spin where used.
static func wstats(id: String, l: int) -> Dictionary:
	var aw := 1.4 if l >= WEAPON_MAX else 1.0   # awakening at max level
	var more := 1 + int(l >= 2) + int(l >= 5) + 2 * int(l >= 7)
	match id:
		"bolt":
			return {"n": more, "dmg": 11.0 * (1.3 if l >= 3 else 1.0) * aw,
				"pierce": int(l >= 4) + int(l >= 7), "cd": 0.78 * (0.8 if l >= 6 else 1.0)}
		"chain":
			return {"n": 1 + int(l >= 5), "hops": 3 + 2 * int(l >= 2) + 3 * int(l >= 6),
				"dmg": 16.0 * (1.35 if l >= 3 else 1.0) * (1.5 if l >= 7 else 1.0) * aw,
				"cd": 1.5 * (0.75 if l >= 4 else 1.0)}
		"nova":
			return {"n": 2 if l >= 6 else 1, "r": 5.5 * (1.25 if l >= 2 else 1.0) * (1.25 if l >= 5 else 1.0),
				"dmg": 22.0 * (1.4 if l >= 3 else 1.0) * (1.6 if l >= 7 else 1.0) * aw,
				"cd": 3.2 * (0.75 if l >= 4 else 1.0)}
		"blade":
			return {"n": more, "r": 9.0 * (1.35 if l >= 4 else 1.0),
				"dmg": 20.0 * (1.3 if l >= 3 else 1.0) * (1.4 if l >= 6 else 1.0) * aw, "cd": 1.9}
		"orbit":
			return {"n": 1 + more, "r": 3.0 * (1.3 if l >= 4 else 1.0), "spin": 3.2 * (1.35 if l >= 4 else 1.0),
				"dmg": 9.0 * (1.3 if l >= 3 else 1.0) * (1.4 if l >= 6 else 1.0) * aw}
		"trail":
			return {"r": 1.25 * (1.25 if l >= 4 else 1.0), "life": 2.2 * (1.4 if l >= 3 else 1.0) * (1.4 if l >= 6 else 1.0),
				"dmg": 7.0 * (1.4 if l >= 2 else 1.0) * (1.5 if l >= 5 else 1.0) * (1.6 if l >= 7 else 1.0) * aw}
		"meteor":
			return {"n": more, "r": 3.2 * (1.35 if l >= 3 else 1.0), "dmg": 42.0 * (1.5 if l >= 6 else 1.0) * aw,
				"cd": 2.6 * (0.75 if l >= 4 else 1.0)}
	return {}

const COUNT_NAME := {"bolt": "Ok", "chain": "Şimşek", "nova": "Dalga", "blade": "Tırpan", "orbit": "Alev", "meteor": "Göktaşı"}

static func _f(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 0.05 or v >= 20.0 else ("%.1f" % v).replace(".", ",")

## Card text with numbers: what the next level changes, "Ok 1 → 2 · Hasar 11 → 14".
static func weapon_card(id: String, next_lv: int) -> String:
	var b := wstats(id, next_lv)
	if next_lv <= 1:
		var parts: Array = []
		if b.has("n"):
			parts.append("%d %s" % [b["n"], COUNT_NAME[id].to_lower()])
		parts.append("%s hasar" % _f(b["dmg"]))
		if b.has("cd"):
			parts.append("%s sn" % _f(b["cd"]))
		return WEAPONS[id]["desc"] + "\n" + " · ".join(parts)
	var a := wstats(id, next_lv - 1)
	var names := {"n": COUNT_NAME.get(id, ""), "dmg": "Hasar", "pierce": "Delme", "hops": "Sekme",
		"r": "Alan", "cd": "Bekleme", "life": "Süre", "spin": "Dönüş"}
	var units := {"r": " m", "cd": " sn", "life": " sn"}
	var out: Array = []
	for k in ["n", "dmg", "pierce", "hops", "r", "cd", "life", "spin"]:
		if b.has(k) and absf(float(b[k]) - float(a[k])) > 0.001:
			out.append("%s %s → %s%s" % [names[k], _f(a[k]), _f(b[k]), units.get(k, "")])
	var txt := " · ".join(out)
	if next_lv >= WEAPON_MAX:
		txt += "\nUyanır; " + PASSIVES[EVOS[id]["partner"]]["name"] + " ile dönüşür"
	return txt

## Offered when every slot is full and maxed, so a level-up is never empty.
const FILLER := {"name": "Kor Özü", "icon": "✧", "color": Color(1.0, 0.7, 0.35), "desc": "+%4 hasar, +5 can ve biraz iyileşme"}

static func passive_cap(id: String) -> int:
	return 2 if id == "amount" else 5

## Which weapon a passive evolves, or "" if none.
static func evolves_weapon(passive_id: String) -> String:
	for w in EVOS.keys():
		if EVOS[w]["partner"] == passive_id:
			return w
	return ""

## Card text for a passive, from the current stats to the next level's.
static func passive_card(id: String, st) -> String:
	var t := ""
	match id:
		"hp": t = "Can +25, canı doldurur"
		"speed": t = "Hız %%%d → %%%d" % [roundi(st.speed * 100.0), roundi(st.speed * 108.0)]
		"power": t = "Hasar %%%d → %%%d" % [roundi(st.dmg * 100.0), roundi(st.dmg * 115.0)]
		"haste": t = "Bekleme %%%d → %%%d" % [roundi(st.cd * 100.0), roundi(st.cd * 92.0)]
		"area": t = "Alan %%%d → %%%d" % [roundi(st.area * 100.0), roundi(st.area * 112.0)]
		"amount": t = "Bütün silahlara mermi +%d → +%d" % [st.amount, st.amount + 1]
		"magnet": t = "Toplama %s → %s m" % [_f(st.magnet), _f(st.magnet * 1.4)]
		"regen": t = "Yenilenme %s → %s can/sn" % [_f(st.regen), _f(st.regen + 0.8)]
		"wisdom": t = "Tecrübe %%%d → %%%d" % [roundi(st.xp * 100.0), roundi(st.xp * 115.0)]
		"crit": t = "Kritik %%%d → %%%d (2,2x hasar)" % [roundi(st.crit * 100.0), roundi(st.crit * 100.0 + 8.0)]
		_: t = PASSIVES[id]["desc"]
	var w := evolves_weapon(id)
	if w != "":
		t += "\n" + WEAPONS[w]["name"] + " silahını dönüştürür"
	return t
