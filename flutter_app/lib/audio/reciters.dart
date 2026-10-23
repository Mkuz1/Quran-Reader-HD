import '../core/l10n.dart';

class Reciter {
  final String id; // EveryAyah folder name
  final String name;
  final String arabicName;
  const Reciter(this.id, this.name, this.arabicName);

  String get localizedName => Localizer.shared.language == AppLanguage.arabic ? arabicName : name;
}

/// Every reciter is an EveryAyah folder of one MP3 per ayah (SSSAAA.mp3). Keep in sync with
/// AudioController.reciters in the macOS app; CI checks each folder exists.
const reciters = <Reciter>[
  Reciter('Abdul_Basit_Murattal_192kbps', 'Abdul Basit — Murattal', 'عبد الباسط عبد الصمد — مرتل'),
  Reciter('Abdul_Basit_Mujawwad_128kbps', 'Abdul Basit — Mujawwad', 'عبد الباسط عبد الصمد — مجود'),
  Reciter('Husary_128kbps', 'Mahmoud Khalil Al-Husary', 'محمود خليل الحصري'),
  Reciter('Husary_Mujawwad_128kbps', 'Al-Husary — Mujawwad', 'محمود خليل الحصري — مجود'),
  Reciter('Husary_Muallim_128kbps', 'Al-Husary — Muallim (teaching)', 'محمود خليل الحصري — المعلم'),
  Reciter('Minshawy_Murattal_128kbps', 'Al-Minshawi — Murattal', 'محمد صديق المنشاوي — مرتل'),
  Reciter('Minshawy_Mujawwad_192kbps', 'Al-Minshawi — Mujawwad', 'محمد صديق المنشاوي — مجود'),
  Reciter('Alafasy_128kbps', 'Mishary Alafasy', 'مشاري راشد العفاسي'),
  Reciter('Salaah_AbdulRahman_Bukhatir_128kbps', 'Salah Bukhatir', 'صلاح بو خاطر'),
  Reciter('Abdurrahmaan_As-Sudais_192kbps', 'Abdur-Rahman As-Sudais', 'عبد الرحمن السديس'),
  Reciter('Saood_ash-Shuraym_128kbps', 'Saud Ash-Shuraim', 'سعود الشريم'),
  Reciter('MaherAlMuaiqly128kbps', 'Maher Al-Muaiqly', 'ماهر المعيقلي'),
  Reciter('Ghamadi_40kbps', 'Saad Al-Ghamdi', 'سعد الغامدي'),
  Reciter('Abu_Bakr_Ash-Shaatree_128kbps', 'Abu Bakr Ash-Shatri', 'أبو بكر الشاطري'),
  Reciter('Hudhaify_128kbps', 'Ali Al-Hudhaify', 'علي الحذيفي'),
  Reciter('Muhammad_Ayyoub_128kbps', 'Muhammad Ayyub', 'محمد أيوب'),
  Reciter('Muhammad_Jibreel_128kbps', 'Muhammad Jibreel', 'محمد جبريل'),
  Reciter('Nasser_Alqatami_128kbps', 'Nasser Al-Qatami', 'ناصر القطامي'),
  Reciter('Yasser_Ad-Dussary_128kbps', 'Yasser Ad-Dossari', 'ياسر الدوسري'),
  Reciter('Hani_Rifai_192kbps', 'Hani Ar-Rifai', 'هاني الرفاعي'),
  Reciter('Ahmed_ibn_Ali_al-Ajamy_128kbps_ketaballah.net', 'Ahmed Al-Ajmi', 'أحمد بن علي العجمي'),
  Reciter('Abdullah_Basfar_192kbps', 'Abdullah Basfar', 'عبد الله بصفر'),
  Reciter('Mohammad_al_Tablaway_128kbps', 'Muhammad At-Tablawi', 'محمد الطبلاوي'),
  Reciter('Fares_Abbad_64kbps', 'Fares Abbad', 'فارس عباد'),
  Reciter('Abdullaah_3awwaad_Al-Juhaynee_128kbps', 'Abdullah Al-Juhany', 'عبد الله عواد الجهني'),
  Reciter('Ali_Jaber_64kbps', 'Ali Jaber', 'علي جابر'),
];
