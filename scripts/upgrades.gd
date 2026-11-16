class_name Upgrades
extends RefCounted
## Upgrade catalogue. Weapons and passive stats; every pick stacks multiplicatively
## with the global stats in Game.stats so late builds snowball.

const MAX_WEAPONS := 6
const WEAPON_MAX := 7
const PASSIVE_MAX := 5

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
	"meteor": {"name": "Gök Kıvılcımı", "icon": "☄", "color": Color(1.0, 0.65, 0.9),
		"desc": "Kalabalığın ortasına düşen göktaşı.",
		"lv": ["+1 göktaşı", "+%35 alan", "Daha sık", "+1 göktaşı", "+%50 hasar", "+2 göktaşı"]},
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

static func level_text(id: String, next_lv: int) -> String:
	if WEAPONS.has(id):
		if next_lv <= 1:
			return WEAPONS[id]["desc"]
		var arr: Array = WEAPONS[id]["lv"]
		return arr[clampi(next_lv - 2, 0, arr.size() - 1)]
	return PASSIVES[id]["desc"]
