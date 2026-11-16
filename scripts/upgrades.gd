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
	"meteor": {"name": "Gök Kıvılcımı", "icon": "☄", "color": Color(1.0, 0.65, 0.9),
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

## Offered when every slot is full and maxed, so a level-up is never empty.
const FILLER := {"name": "Kor Özü", "icon": "✧", "color": Color(1.0, 0.7, 0.35), "desc": "+%5 hasar ve +10 can"}

static func passive_cap(id: String) -> int:
	return 2 if id == "amount" else 5

## Which weapon a passive evolves, or "" if none.
static func evolves_weapon(passive_id: String) -> String:
	for w in EVOS.keys():
		if EVOS[w]["partner"] == passive_id:
			return w
	return ""

static func level_text(id: String, next_lv: int) -> String:
	if WEAPONS.has(id):
		if next_lv <= 1:
			return WEAPONS[id]["desc"]
		var arr: Array = WEAPONS[id]["lv"]
		var txt: String = arr[clampi(next_lv - 2, 0, arr.size() - 1)]
		if next_lv >= WEAPON_MAX:
			txt += ". Uyanır: +%40 hasar, sonra " + PASSIVES[EVOS[id]["partner"]]["name"] + " ile dönüşür"
		return txt
	var d: String = PASSIVES[id]["desc"]
	var w := evolves_weapon(id)
	if w != "":
		d += ". " + WEAPONS[w]["name"] + " silahını dönüştürür"
	return d
