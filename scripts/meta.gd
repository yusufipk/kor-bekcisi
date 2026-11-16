extends RefCounted
## Progress kept between runs: kor (currency earned per run), permanent altar
## upgrades, discovered evolutions and the chosen starting weapon.
## Demo runs never read or write it, so balance tests stay reproducible.

const PATH := "user://ilerleme.cfg"

const UPGRADES := [
	{"id": "hp", "name": "Sağlam Başlangıç", "icon": "♥", "desc": "+10 can", "cost": [15, 30, 50, 75, 100]},
	{"id": "dmg", "name": "Kor Gücü", "icon": "▲", "desc": "+%4 hasar", "cost": [20, 40, 65, 90, 120]},
	{"id": "speed", "name": "Hafif Adım", "icon": "»", "desc": "+%3 hareket hızı", "cost": [20, 45, 75]},
	{"id": "magnet", "name": "Çekim", "icon": "◈", "desc": "+%15 toplama menzili", "cost": [15, 30, 50]},
	{"id": "xp", "name": "Bilgelik", "icon": "✦", "desc": "+%5 tecrübe", "cost": [25, 50, 80]},
	{"id": "reroll", "name": "Yeniden Çek", "icon": "↻", "desc": "+1 yeniden çekme hakkı", "cost": [30, 60, 90]},
	{"id": "revive", "name": "İkinci Nefes", "icon": "✚", "desc": "Turda bir kez yarı canla kalkarsın", "cost": [120]},
	{"id": "start", "name": "Silah Seçimi", "icon": "➶", "desc": "Başlangıç silahını sen seçersin", "cost": [60]},
]

var kor := 0
var ranks := {}
var discovered: Array = []
var start_weapon := "bolt"
var runs := 0

func load_cfg() -> void:
	var c := ConfigFile.new()
	if Settings.load_plain(c, PATH) != OK:
		return
	# A hand-edited save must not crash the game or wipe the rest of the file.
	var v = c.get_value("m", "kor", 0)
	kor = maxi(0, int(v)) if (v is int or v is float) else 0
	v = c.get_value("m", "ranks", {})
	ranks = {}
	if v is Dictionary:
		for u in UPGRADES:
			var r = v.get(u["id"], 0)
			if r is int or r is float:
				ranks[u["id"]] = clampi(int(r), 0, (u["cost"] as Array).size())
	v = c.get_value("m", "discovered", [])
	discovered = []
	if v is Array:
		for id in v:
			if id is String and Upgrades.EVOS.has(id) and not discovered.has(id):
				discovered.append(id)
	v = c.get_value("m", "start_weapon", "bolt")
	start_weapon = v if v is String and Upgrades.WEAPONS.has(v) else "bolt"
	v = c.get_value("m", "runs", 0)
	runs = maxi(0, int(v)) if (v is int or v is float) else 0

func save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("m", "kor", kor)
	c.set_value("m", "ranks", ranks)
	c.set_value("m", "discovered", discovered)
	c.set_value("m", "start_weapon", start_weapon)
	c.set_value("m", "runs", runs)
	c.save(PATH)

func rank(id: String) -> int:
	var u := info(id)
	if u.is_empty():
		return 0
	return clampi(int(ranks.get(id, 0)), 0, (u["cost"] as Array).size())

static func info(id: String) -> Dictionary:
	for u in UPGRADES:
		if u["id"] == id:
			return u
	return {}

## Price of the next rank, or -1 when maxed.
func next_cost(id: String) -> int:
	var costs: Array = info(id)["cost"]
	var r := rank(id)
	return costs[r] if r < costs.size() else -1

func buy(id: String) -> bool:
	var c := next_cost(id)
	if c < 0 or kor < c:
		return false
	kor -= c
	ranks[id] = rank(id) + 1
	save_cfg()
	return true

## Kor earned by a run: a little for surviving, more for the milestones.
static func reward(s: Dictionary) -> int:
	var k := int(s["kills"] / 50) + int(s["time"] / 60.0) * 4 + int(s["shrines"]) * 3 + int(s["crystals"]) * 2 + int(s["evolutions"]) * 5
	if s["serpent"]:
		k += 15
	if s["victory"]:
		k += 40
	return k
