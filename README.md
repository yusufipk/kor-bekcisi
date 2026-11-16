# Kor Bekçisi

Alacakaranlıkta yüzen bir adada fener bekçisisin. Kül yaratıkları adanın kenarlarından tırmanıyor; 10 dakika dayan, fenerleri yak ve sonunda gelen Kül Devi'ni devir. Silahlar kendiliğinden ateş eder, senin işin koşmak, kaçmak ve toplamak.

## Çalıştırma

Projeyi Godot 4.7 ile aç ve F5'e bas.

## Nasıl oynanır

| Tuş | İş |
|---|---|
| WASD | koş |
| Boşluk | zıpla (alçak düşmanların üstünden geçersin) |
| Shift veya sağ tık | kay (kayarken hasar almazsın) |
| Fare | kamerayı çevir |
| 1, 2, 3 | seviye kartı seç |
| Esc | duraklat ve ayarlar (fare hassasiyeti, müzik, efekt, parlaklık) |

Ölen düşmanın bıraktığı kristaller tecrübe verir. Seviye atlayınca oyun durur, üç karttan biri seçilir: yeni silah, silah geliştirme ya da kalıcı özellik. Yedi silah var; en üst seviyeye çıkan silah uyanır ve %40 daha sert vurur. Adada beş fener var: ✦ işaretli birinin yanında iki saniye durunca yanar, etrafı temizler ve kalıcı bir güç verir (ilki havada ikinci zıplama). Işık sütunlu sandıklar ve parlayan elit düşmanların bıraktığı sandıklar bedava bir kart seçimi açar. Dakikalar geçtikçe kalabalık artar, yeni düşman tipleri gelir, ara sıra bir halka seni çevreler. 10. dakikada Kül Devi gelir; yenince tur biter ve istatistikler görünür. Ölünce R ile baştan başlarsın.

## Kredi dökümü

Higgsfield'da harcanan toplam: **283,79 kredi** (tavan 1.200). Başarısız dönen 5 görsel işi de ücretlendirildiyse en kötü durumda 295,04. Bütün iş kimlikleri ve tek tek maliyetler `art/kredi-kaydi.tsv` dosyasında.

| Kalem | İş | Kredi |
|---|---|---|
| Stil karesi ve 10 asset görseli (GPT Image 2.5, high, 2k) | 11 | 30,25 |
| Kahraman: iskeletli 3D ve koşma klibi | 1 | 38 |
| Kahraman: bekleme, zıplama, kayma klipleri | 3 | 24 |
| 4 düşman, boss, ağaç, kaya, fener, sandık (3D) | 9 | 126 |
| Müzik: erken tur, geç tur, boss | 3 | 61,04 |
| Efektler (Mirelo) | 11 | 4,50 |
| Başarısız işler (GPT Image 2.6 o sırada hiç görsel üretmedi) | 5 | 0 ile 11,25 arası |

## Bilinen zayıf noktalar

- Denge yalnızca otomatik pilotla ayarlandı, insanla test edilmedi. Kart şansı turdan tura çok fark yaratıyor; bazı turlar 7. dakikadan sonra fazla kolaylaşıyor.
- Performans ağır yüklü bir makinede ölçüldü, o yüzden FPS sayıları güvenilir değil. Düşman mantığı düşman başına yaklaşık 12 µs tutuyor; 300'ü aşan kalabalıkta zayıf bir makinede kare düşebilir.
- Boss'un dört saldırısı ve %50'de tek bir öfke evresi var. Canı ilk saniyelerde vurulan hasara göre ayarlanıyor, bu yüzden dövüş süresi yapıya göre yaklaşık bir ile iki dakika arasında oynuyor.
- Kayma klibi yere yatan bir kayış değil, çömelme. Kahramanın yüz ifadesi yok, fener modeli hafif eğik duruyor, Tükürgeç ile Hantal'ın silüetleri birbirine benziyor.
- Efektlerin çoğu çok sessiz üretildi ve 40 dB'e kadar yükseltildi; bazılarında hafif bir zemin gürültüsü duyulabilir. Seviye ve kayma sesleri kodla üretiliyor. Geç tur müziğinin 70. saniyesinde kısa bir müzikal iniş var.
- Gamepad desteği yok.
- Depoda `addons/beckett` yok, bu yüzden temiz bir kopyada Godot açılışta eksik bir autoload için hata mesajı basar; oyun yine çalışır.
