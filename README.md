# Kor Bekçisi

Yüzen bir adada fener bekçisisin. Öğleden sonra başlayan tur gün batımına, geceye ve sonunda kızıl bir kül gecesine döner; 10 dakika dayan, fenerleri yak ve Kül Devi'ni devir. Silahlar kendiliğinden ateş eder, senin işin koşmak, kaçmak ve toplamak.

## Çalıştırma

Projeyi Godot 4.7 ile aç ve F5'e bas.

## Nasıl oynanır

| Tuş | İş |
|---|---|
| WASD | koş |
| Boşluk | zıpla (alçak düşmanların ve hücum şeritlerinin üstünden geçersin) |
| Shift veya sağ tık | kay (kayarken hasar almazsın) |
| Fare | kamerayı çevir |
| 1, 2, 3 | seviye kartı seç |
| R | seviye ekranında kartları yeniden çek |
| Esc | duraklat ve ayarlar (fare hassasiyeti, müzik, efekt, parlaklık) |

Ölen düşmanın bıraktığı kristaller tecrübe verir. Seviye atlayınca oyun durur, üç karttan biri seçilir: yeni silah, silah geliştirme ya da kalıcı özellik. Dört silah ve dört özellik yuvan var, o yüzden her tur başka bir build'le biter. En üst seviyeye çıkan silah eşi olan özellikle birleşince sandıkta yeni bir silaha dönüşür; tarifleri kartlarda ve Kor Sunağı'nda yazar. Beş feneri yak (✦ işaretli birinin yanında iki saniye dur; ilki başladığın yerin hemen önünde): her biri kalıcı bir güç verir, ışığında canın dolar. Kehribar kristalleri kırınca tecrübe, can ya da sandık çıkar. 5. dakikada Kor Yılanı gelir, 10. dakikada Kül Devi. Tur sonunda kazandığın korla başlık ekranındaki Kor Sunağı'ndan kalıcı yükseltmeler alırsın.

## Bu aşamada eklenenler

İlk sürümü gösteri moduyla baştan sona oynatıp ekran görüntülerine baktım. En zayıf yerler şunlardı: her tur aynı build'e çıkıyordu (bitişte 6 silah ve 10 özelliğin hepsi tam), son dört dakikada tehdit kalmıyordu, ada 0. dakikada neyse 10. dakikada da oydu, boss ekranda neredeyse hiç görünmüyordu ve turdan geriye bir rekor satırı dışında bir şey kalmıyordu. Eklediklerim bunlara cevap:

- **Yuvalar ve dönüşümler.** Seçimin anlam taşıması için 4+4 yuva; tura bir doruk anı vermek için yedi dönüşüm (ağır çekim, ışık sütunu, yeni görünüş ve davranış). Kötü bir elde yeniden çekme hakkı var.
- **Gün batımından geceye.** Tur zamanına bağlı gökyüzü, güneş ve ay; gece düşmanların kenarları ve kahramanın feneri parlar, yanan fenerler ışık havuzu olur. Boss gelince gök kızarır, boss düşünce şafak söker. Zamanın geçtiği artık görülüyor.
- **Stil karesindeki dünya.** Taş yollar, çiçekler, harabe kemerler ve sütunlar, şelaleli uzak adalar, bulut denizi. Kırılabilen kehribar kristaller keşfe sebep veriyor.
- **Yeni tehditler.** Patlayıp çevresindekileri de vuran Kor Kesesi (zincirleme patlamalar), yere şerit çizip hücum eden Kül Boynuzu, 5. dakikada Kor Yılanı ve 8. dakikada Gece Akını. Geç oyun dönüşümlerden sonra da baskı kursun diye düşman canı 5:30'dan sonra daha hızlı artıyor.
- **Boss'a sahne.** Yerden yükselen ağır çekim giriş, dövüş boyunca geri çekilen kamera, üç evre (kül yağmuru, yer yarıkları, öfke) ve kalabalığın ışığa dönüştüğü bir ölüm.
- **Bir tur daha.** Kor Sunağı'nda sekiz kalıcı yükseltme, başlangıç silahı seçimi ve dönüşüm koleksiyonu. Bitiş ekranında silah başına hasar ve kazanılan kor.
- **Okunurluk.** Aynı düşmana vuran hasar sayıları tek sayıda toplanıyor, kameranın dibindeki ağaçlar seyreliyor, can toplamak ekranın ortasına yazı basmıyor.

## Revizyon: ilk kez oynayan birinin raporu

Bağımsız bir inceleme ajanı oyunu ilk kez oynayan biri gibi oynadı. Üç turu 1:11 ile 2:44 arasında bitti, yılanı da boss'u da görmedi. Raporu sayıyla doğrulamak için gösteri moduna yeni oyuncuyu taklit eden üç bot ekledim. Biri körlemesine daire çiziyor, biri gördüğü kalabalıktan kaçıyor, biri ilk ipucuna uyup fenerin ışığında dolaşıyor. Eski sürümde ilk ikisi 1:44 ile 3:42 arasında öldü. Yenisinde dokuz turun yedisi yılanı (5:00) görüyor, ipucuna uyan bot üç turda da 7:00'ı geçiyor. Akıllı bot hâlâ 11. dakikada kazanıyor.

- **İlk üç dakika.** İlk fener başlangıçta kameranın önünde, ipucu ilk saniyede. Kalabalık ilk iki dakikada %40 az, düşman canı ve temas hasarı ilk dakikalarda yavaş artıyor. Güveler 1:15'ten, hantallar 2:50'den, seçkin hantallar ve boynuzlar yılandan sonra geliyor. Meyve ilk üç dakikada üç kat sık düşüyor ve oyuncuya çekiliyor. Isıran düşman geri sekiyor. Başlangıç canı 140, darbe sonrası dokunulmazlık 1 saniye. İkinci kapanan halka yılanla aynı ana denk gelmesin diye 5:45'e kaydı.
- **Renkle ayrım.** Kahramanda her ışıkta seçilen turkuaz bir dış çizgi ve ayak halkası var. Kalabalık soğuk mor, düşman mermileri kızıl-turuncu, yılan kor turuncusu, boss'ta lav çatlakları var. Boss savaşında kamera artık 14,5 m'ye çekilmiyor, bakış noktası boss'a kayıp ikisini birlikte çerçeveliyor. Boss ya da yılan ekran dışındaysa kenarda büyük bir ok çıkıyor, sandık sütunları sönüyor.
- **Kartlar ve ritim.** Kartlar ne değiştiğini sayıyla yazıyor ("Ok 1 → 2 · Hasar 11 → 14", "Hasar %115 → %132"). Silahlar aynı tablodan ateşlediği için kartta yazan sayı oyundakiyle aynı. Kart ekranı kapandıktan sonraki 6 saniyede gelen seviyeler bekleyip tek ekranda sırayla açılıyor.
- **Hatalar.** Boşluk artık menü düğmesine basmıyor, bitiş ekranı ilk 1,2 saniye tuş kabul etmiyor. Kenar işaretleri en yakın feneri ve en yakın iki sandığı gösteriyor, HUD'a girmeyen bir şeritte duruyor ve üst üste binmiyor. Kamera kolu engele çarpıp yere inmiyor; kamerayla kahraman arasına giren her şey zaten saydamlaşıyor.
- **Ses ve performans.** Tecrübe sesi 9,5 dB yükseldi (müziğin yaklaşık 8 dB altında) ve art arda toplandıkça pentatonik bir dizide tırmanıyor. Boss kükremesi müziğin yaklaşık 3 dB üstünde. Yerdeki kristallerin süzülmesi shader'da yapılıyor ve üst sınır 400, fazlası mevcut kristale ekleniyor. Toplama maliyeti aynı kalabalıkta 3-4 kat düştü.

Müziğin dinamik aralığının 3 LU olmasına katılmıyorum ve değiştirmedim. Sürekli efekt altında çalan oyun müziğinin düz olması bilinçli; sessiz pasajlar savaşta kaybolurdu ve bu oyunda müzik hiçbir an bastırılmamalı. Yoğunluk parça değişimiyle geliyor (erken tur, geç tur, boss) ve oyuncular artık geç tura ulaştığı için o parçaları duyuyor.

## Kredi dökümü

Higgsfield'da iki aşamada harcanan toplam: **403,79 kredi** (iki aşamanın tavanı 1.200). İlk aşamada başarısız dönen 5 görsel işi de ücretlendirildiyse en kötü durumda 415,04. Bütün iş kimlikleri ve tek tek maliyetler `art/kredi-kaydi.tsv` dosyasında; ikinci aşamanın satırları "A2" ile başlar.

| Kalem | İş | Kredi |
|---|---|---|
| Stil karesi ve 10 asset görseli (GPT Image 2.5, high, 2k) | 11 | 30,25 |
| Kahraman: iskeletli 3D ve koşma klibi | 1 | 38 |
| Kahraman: bekleme, zıplama, kayma klipleri | 3 | 24 |
| 4 düşman, boss, ağaç, kaya, fener, sandık (3D) | 9 | 126 |
| Müzik: erken tur, geç tur, boss | 3 | 61,04 |
| Efektler (Mirelo) | 11 | 4,50 |
| Başarısız işler (GPT Image 2.6 o sırada hiç görsel üretmedi) | 5 | 0 ile 11,25 arası |
| 2. aşama: 7 görsel (iki düşman, yılan başı ve gövdesi, kemer, sütun, kristal) | 7 | 19,25 |
| 2. aşama: aynı 7 varlığın 3D'si | 7 | 98 |
| 2. aşama: 6 efekt (ikisi neredeyse sessiz geldi, kodla üretilenler kullanılıyor) | 6 | 2,75 |

## Bilinen zayıf noktalar

- Denge botlarla ayarlandı, insanla test edilmedi. Yeni oyuncu botları gerçek bir insanın yaptığı hataların yalnızca bir kısmını taklit ediyor; kaçan bot hâlâ bazen 5:00'tan önce ölüyor. Kart şansı turdan tura çok fark yaratıyor; dönüşüm erken gelen turlar geç oyunda kolaylaşabiliyor. Kor Sunağı fiyatları hiç oynanarak denenmedi.
- Performans ağır yüklü bir makinede ölçüldü, FPS sayıları güvenilir değil. Düşman mantığı düşman başına yaklaşık 12 µs tutuyor; 300'ü aşan kalabalıkta zayıf bir makinede kare düşebilir.
- Kor Yılanı ile Kül Devi'nin canı ilk saniyelerde vurulan hasara göre ayarlanıyor; dövüş süresi yapıya göre oynuyor (bot turlarında boss 60 ile 80 saniye sürdü, bir turda 2 dakika).
- Kül gecesi bütün sahneyi kırmızıya boyuyor; düşmanlar kenar ışığıyla seçiliyor ama renk körlüğü olan biri için zorlaşabilir.
- Kayma klibi yere yatan bir kayış değil, çömelme. Kahramanın yüz ifadesi yok, fener modeli hafif eğik duruyor, Tükürgeç ile Hantal'ın silüetleri birbirine benziyor.
- Efektlerin çoğu çok sessiz üretildi ve 40 dB'e kadar yükseltildi; bazılarında hafif bir zemin gürültüsü duyulabilir. Seviye, kayma, dönüşüm ve kristal sesleri kodla üretiliyor. Geç tur müziğinin 70. saniyesinde kısa bir müzikal iniş var.
- Gamepad desteği yok.
- Depoda `addons/beckett` yok, bu yüzden temiz bir kopyada Godot açılışta eksik bir autoload için hata mesajı basar; oyun yine çalışır.
