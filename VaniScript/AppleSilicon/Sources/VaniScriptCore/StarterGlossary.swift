import Foundation

public enum StarterGlossary {
    private struct StarterTerm {
        let source: String
        let translation: String
        let category: String
        let variants: [String]
    }

    private static let categoryLabels: [String: String] = [
        "Ачарьи / Учители": "Acharyas / Teachers",
        "Аватары / Господь": "Avataras / Lord",
        "Имена Бога": "Names of God",
        "Мантры": "Mantras",
        "Священные писания": "Scriptures",
        "Философские термины": "Philosophical terms",
        "Практики": "Practices",
        "Священные объекты": "Sacred objects",
        "Священные места": "Sacred places",
        "Священные личности": "Sacred personalities",
        "Организации": "Organizations",
        "Пользовательское": "Custom"
    ]

    private static func slug(_ value: String) -> String {
        let clean = stripDiacritics(value).lowercased()
        var result = ""
        var prevWasHyphen = false
        for char in clean {
            if char.isLetter || char.isNumber {
                result.append(char)
                prevWasHyphen = false
            } else {
                if !prevWasHyphen && !result.isEmpty {
                    result.append("-")
                    prevWasHyphen = true
                }
            }
        }
        if result.hasSuffix("-") {
            result.removeLast()
        }
        return result
    }

    private static func stripDiacritics(_ value: String) -> String {
        let mutableString = NSMutableString(string: value) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        var result = (mutableString as String)

        let replacements: [String: String] = [
            "ṛ": "r", "Ṛ": "r",
            "ṣ": "s", "Ṣ": "s",
            "ś": "s", "Ś": "s",
            "ṭ": "t", "Ṭ": "t",
            "ḍ": "d", "Ḍ": "d",
            "ṅ": "n", "Ṅ": "n",
            "ñ": "n", "Ñ": "n",
            "ṁ": "m", "Ṁ": "m", "ṃ": "m",
            "ī": "i", "Ī": "i",
            "ā": "a", "Ā": "a",
            "ū": "u", "Ū": "u"
        ]

        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
            result = result.replacingOccurrences(of: from.uppercased(), with: to.uppercased())
        }

        return result
    }

    private static func expandVariants(source: String, variants: [String]) -> [String] {
        let base = [source, stripDiacritics(source)] + variants
        var expanded = Set<String>()

        for variant in base {
            let clean = variant.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            expanded.insert(clean)

            expanded.insert(clean.replacingOccurrences(of: "/", with: " "))
            expanded.insert(clean.replacingOccurrences(of: " / ", with: " "))
            expanded.insert(clean.replacingOccurrences(of: "-", with: " "))
            expanded.insert(clean.replacingOccurrences(of: " ", with: "-"))

            if clean.contains("Sri") {
                expanded.insert(clean.replacingOccurrences(of: "Sri", with: "Shri"))
            }
            if clean.contains("Shri") {
                expanded.insert(clean.replacingOccurrences(of: "Shri", with: "Sri"))
            }
            if clean.contains("Thakur") {
                expanded.insert(clean.replacingOccurrences(of: "Thakur", with: "Takur"))
            }
            if clean.contains("Goswami") {
                expanded.insert(clean.replacingOccurrences(of: "Goswami", with: "Gosvami"))
            }
            if clean.contains("Maharaja") {
                expanded.insert(clean.replacingOccurrences(of: "Maharaja", with: "Maharaj"))
            }
        }

        expanded.remove(source)
        return Array(expanded).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    public static let entries: [GlossaryEntry] = {
        let rawTerms: [StarterTerm] = [
            StarterTerm(source: "Śrīla Prabhupāda", translation: "Шрила Прабхупада", category: "Ачарьи / Учители", variants: ["Srila Prabhupada", "Shila Prabhupada", "Shrila Prabhupada", "Srila Prabhupad", "Shri La Prabhupada"]),
            StarterTerm(source: "Bhaktivinoda Ṭhākura", translation: "Бхактивинода Тхакур", category: "Ачарьи / Учители", variants: ["Bhaktivinoda Thakur", "Bhakti Vinoda Thakur", "Bhakti Vinod Takur", "Bhaktivinoda Thakura"]),
            StarterTerm(source: "Śrī Caitanya Mahāprabhu", translation: "Шри Чайтанья Махапрабху", category: "Аватары / Господь", variants: ["Chaitanya Mahaprabhu", "Chitanya Mahaprabhu", "Chetanya Mahaprabhu", "Sri Chaitanya", "Chatanya"]),
            StarterTerm(source: "Matsya Avatāra", translation: "Матсья-аватара", category: "Аватары / Господь", variants: ["Matsya Avatar", "Matsyavatar", "Matsya Avatara", "Matsyaavatar", "Matsa Avatar", "Matsia Avatar", "Matsya avatār"]),
            StarterTerm(source: "Kūrma Avatāra", translation: "Курма-аватара", category: "Аватары / Господь", variants: ["Kurma Avatar", "Kurma Avatara", "Kurmavatar", "Koorma Avatar", "Kurma avatār"]),
            StarterTerm(source: "Varāha Avatāra", translation: "Вараха-аватара", category: "Аватары / Господь", variants: ["Varaha Avatar", "Varaha Avatara", "Varahavatar", "Varaha avatār"]),
            StarterTerm(source: "Nṛsiṁha Avatāra", translation: "Нрисимха-аватара", category: "Аватары / Господь", variants: ["Nrsimha Avatar", "Narasimha Avatar", "Nrisingha Avatar", "Nrisimha Avatara", "Narsingh Avatar", "Narasimhadev"]),
            StarterTerm(source: "Vāmana Avatāra", translation: "Вамана-аватара", category: "Аватары / Господь", variants: ["Vamana Avatar", "Vamana Avatara", "Vamanadev", "Vaman Avatar"]),
            StarterTerm(source: "Jayapatākā Swami", translation: "Джаяпатака Свами", category: "Ачарьи / Учители", variants: ["Jayapataka Swami", "Jayapataka Maharaj", "Jaipataka Maharaja", "Jipataka Maharaj"]),
            StarterTerm(source: "Kṛṣṇa", translation: "Кришна", category: "Имена Бога", variants: ["Krishna", "Krsna", "Krushna", "Krishnaa", "Krisna"]),
            StarterTerm(source: "Rādhā / Rādhārāṇī", translation: "Радха / Радхарани", category: "Имена Бога", variants: ["Radha", "Raadha", "Radhe", "Radharani", "Radha rani"]),
            StarterTerm(source: "Hare Kṛṣṇa", translation: "Харе Кришна", category: "Мантры", variants: ["Hari Krishna", "Harry Krishna", "Harekrishna"]),
            StarterTerm(source: "Mahā-mantra", translation: "Маха-мантра", category: "Мантры", variants: ["Mahamantra", "Maha mantra", "Maha-mantra"]),
            StarterTerm(source: "Bhagavad-gītā", translation: "Бхагавад-гита", category: "Священные писания", variants: ["Bhagavad Gita", "Bhagwad Gita", "Bhagavad-Gita", "Bhagwad Geeta"]),
            StarterTerm(source: "Śrīmad-Bhāgavatam", translation: "Шримад-Бхагаватам", category: "Священные писания", variants: ["Srimad Bhagavatam", "Shrimad Bhagavatam", "Srimad-Bhagavatam", "Bhagavatam"]),
            StarterTerm(source: "Caitanya-caritāmṛta", translation: "Чайтанья-чаритамрита", category: "Священные писания", variants: ["Chaitanya Charitamrita", "Chaitanya Charitramrita", "Caitanya Caritamrta"]),
            StarterTerm(source: "bhakti", translation: "бхакти", category: "Философские термины", variants: ["Bhakthee", "Bakhti", "Bhakhti"]),
            StarterTerm(source: "prema", translation: "према", category: "Философские термины", variants: ["Prema bhakti", "Prem", "Preema"]),
            StarterTerm(source: "Vaiṣṇava / Vaiṣṇavism", translation: "Вайшнав / Вайшнавизм", category: "Философские термины", variants: ["Vaishnavas", "Vaisnavism", "Vaishnavism", "Vaishnava"]),
            StarterTerm(source: "saṅkīrtana", translation: "санкиртана", category: "Практики", variants: ["Sankirtan", "Sankeertana", "Sankirtana"]),
            StarterTerm(source: "japa", translation: "джапа", category: "Практики", variants: ["Jappa", "Jap", "Jaapa"]),
            StarterTerm(source: "Tulasī", translation: "Туласи", category: "Священные объекты", variants: ["Tulsi", "Thulsi", "Toolasi", "Tulsii"]),
            StarterTerm(source: "Viṣṇu", translation: "Вишну", category: "Имена Бога", variants: ["Vishnu", "Visnu", "Vishno", "Visno"]),
            StarterTerm(source: "Nārāyaṇa", translation: "Нараяна", category: "Имена Бога", variants: ["Narayan", "Naarayana", "Narayana"]),
            StarterTerm(source: "guru", translation: "гуру", category: "Ачарьи / Учители", variants: ["Gurudev", "Guroo", "Guru dev"]),
            StarterTerm(source: "guru-paramparā", translation: "гуру-парампара", category: "Философские термины", variants: ["Guru Parampara", "Guru-parampara", "Parampara"]),
            StarterTerm(source: "Vṛndāvana", translation: "Вриндаван", category: "Священные места", variants: ["Vrindavan", "Vrindavana", "Vrindaban", "Brindavan"]),
            StarterTerm(source: "Māyāpur", translation: "Майяпур", category: "Священные места", variants: ["Mayapur", "Mayapura", "Maapur", "Maya pur"]),
            StarterTerm(source: "Navadvīpa", translation: "Навадвипа", category: "Священные места", variants: ["Navadwip", "Navadvipa", "Nabadwip", "Nabadweep"]),
            StarterTerm(source: "Jagannātha", translation: "Джаганнатха", category: "Имена Бога", variants: ["Jagannath", "Jaganath", "Jaganaath", "Jaggannatha"]),
            StarterTerm(source: "Balarāma", translation: "Баларама", category: "Имена Бога", variants: ["Balarama", "Balaram", "Balaraama", "Bal Ram"]),
            StarterTerm(source: "Subhadrā", translation: "Субхадра", category: "Имена Бога", variants: ["Subhadra", "Subhradra", "Subhadra devi"]),
            StarterTerm(source: "Nityānanda", translation: "Нитьянанда", category: "Аватары / Господь", variants: ["Nityananda", "Nityananda Prabhu", "Nityananada", "Nitaiyananda"]),
            StarterTerm(source: "Advaita Ācārya", translation: "Адвайта Ачарья", category: "Аватары / Господь", variants: ["Advaita Acharya", "Advaita Acarya", "Advaita acharyaa"]),
            StarterTerm(source: "Rūpa Gosvāmī", translation: "Рупа Госвами", category: "Ачарьи / Учители", variants: ["Rupa Goswami", "Rupa Gosvami", "Roopa Goswami"]),
            StarterTerm(source: "Sanātana Gosvāmī", translation: "Санатана Госвами", category: "Ачарьи / Учители", variants: ["Sanatana Goswami", "Sanatan Gosvami", "Sanatana Gosvami"]),
            StarterTerm(source: "Raghunātha Dāsa Gosvāmī", translation: "Рагхунатха Дас Госвами", category: "Ачарьи / Учители", variants: ["Raghunatha Dasa", "Ragunath Das", "Raghunath Das Goswami"]),
            StarterTerm(source: "Jīva Gosvāmī", translation: "Джива Госвами", category: "Ачарьи / Учители", variants: ["Jiva Goswami", "Jeeva Gosvami", "Jiva Gosvami"]),
            StarterTerm(source: "Bhaktisiddhānta Sarasvatī Ṭhākura", translation: "Бхактисиддханта Сарасвати Тхакур", category: "Ачарьи / Учители", variants: ["Bhaktisiddhanta Saraswati", "Bhaktisiddhanta Thakur", "Bhakti Siddhanta Saraswati"]),
            StarterTerm(source: "Mādhavendra Purī", translation: "Мадхавендра Пури", category: "Ачарьи / Учители", variants: ["Madhavendra Puri", "Madhav Puri", "Madhavendra"]),
            StarterTerm(source: "Īśvara Purī", translation: "Ишвара Пури", category: "Ачарьи / Учители", variants: ["Ishvara Puri", "Isvarapuri", "Ishwara Puri"]),
            StarterTerm(source: "Mahā-Viṣṇu", translation: "Маха-Вишну", category: "Имена Бога", variants: ["Maha Vishnu", "Maha-Vishnu", "Mahavishnu"]),
            StarterTerm(source: "Paramātmā", translation: "Параматма", category: "Философские термины", variants: ["Paramatma", "Paramatman", "Paramathma"]),
            StarterTerm(source: "Brahman", translation: "Брахман", category: "Философские термины", variants: ["Brahmaan", "Brahm", "Brahmana"]),
            StarterTerm(source: "māyā", translation: "майя", category: "Философские термины", variants: ["Maaya", "Maia", "Mayaa"]),
            StarterTerm(source: "līlā", translation: "лила", category: "Философские термины", variants: ["Lila", "Leela", "Liila", "Leelaa"]),
            StarterTerm(source: "dharma", translation: "дхарма", category: "Философские термины", variants: ["Dharm", "Dharma dharma", "Dharmaa"]),
            StarterTerm(source: "karma", translation: "карма", category: "Философские термины", variants: ["Karm", "Karmaa", "Karma karma"]),
            StarterTerm(source: "saṁsāra", translation: "самсара", category: "Философские термины", variants: ["Samsara", "Samsaara", "Sansar"]),
            StarterTerm(source: "mokṣa", translation: "мокша", category: "Философские термины", variants: ["Moksha", "Moksh", "Mooksha"]),
            StarterTerm(source: "mukti", translation: "мукти", category: "Философские термины", variants: ["Mukthi", "Mokti", "Muktee"]),
            StarterTerm(source: "ācārya", translation: "ачарья", category: "Ачарьи / Учители", variants: ["Acharya", "Acarya", "Acharyaa"]),
            StarterTerm(source: "Svāmī", translation: "Свами", category: "Ачарьи / Учители", variants: ["Swami", "Swamee", "Svami"]),
            StarterTerm(source: "Mahārāja", translation: "Махараджа", category: "Ачарьи / Учители", variants: ["Maharaj", "Mahaaraj", "Maharaaj"]),
            StarterTerm(source: "Prabhu", translation: "Прабху", category: "Ачарьи / Учители", variants: ["Prabho", "Praboo", "Prabhoo"]),
            StarterTerm(source: "Vaikuṇṭha", translation: "Вайкунтха", category: "Священные места", variants: ["Vaikuntha", "Vaikunta", "Vaikunth"]),
            StarterTerm(source: "Goloka Vṛndāvana", translation: "Голока Вриндавана", category: "Священные места", variants: ["Goloka", "Goloka Vrindavan", "Gauloka"]),
            StarterTerm(source: "Mathurā", translation: "Матхура", category: "Священные места", variants: ["Mathura", "Mathoora", "Mathuraa"]),
            StarterTerm(source: "Dvārakā", translation: "Дварака", category: "Священные места", variants: ["Dvaraka", "Dwarka", "Dwaraka"]),
            StarterTerm(source: "pūjā", translation: "пуджа", category: "Практики", variants: ["Puja", "Pooja", "Pujaa"]),
            StarterTerm(source: "āratī", translation: "арати", category: "Практики", variants: ["Arati", "Aarti", "Arthi", "Aarati"]),
            StarterTerm(source: "maṅgala-āratī", translation: "мангала-арати", category: "Практики", variants: ["Mangala arati", "Mangala-arati", "Mongal arati"]),
            StarterTerm(source: "prasādam", translation: "прасадам", category: "Священные объекты", variants: ["Prasad", "Prashad", "Prasaad", "Prasaadam"]),
            StarterTerm(source: "tilaka", translation: "тилака", category: "Священные объекты", variants: ["Tilak", "Tilaak", "Teelak"]),
            StarterTerm(source: "Śālagrāma", translation: "Шалаграма", category: "Священные объекты", variants: ["Shaligram", "Shalagrama", "Shalagram"]),
            StarterTerm(source: "mṛdaṅga", translation: "мриданга", category: "Священные объекты", variants: ["Mridanga", "Mridangam", "Mrudanga"]),
            StarterTerm(source: "kartāla", translation: "карталы", category: "Священные объекты", variants: ["Kartals", "Kartala", "Kartal"]),
            StarterTerm(source: "kīrtana", translation: "киртан", category: "Практики", variants: ["Kirtana", "Kirtan", "Kiirtan", "Keertana"]),
            StarterTerm(source: "sādhu", translation: "садху", category: "Философские термины", variants: ["Sadhu", "Saadhu", "Sadhu sanga"]),
            StarterTerm(source: "śāstra", translation: "шастра", category: "Священные писания", variants: ["Shastra", "Sastra", "Shaastras"]),
            StarterTerm(source: "Vedānta", translation: "Веданта", category: "Священные писания", variants: ["Vedanta", "Vedaanta", "Vedanta Sutra"]),
            StarterTerm(source: "Upaniṣad", translation: "Упанишада", category: "Священные писания", variants: ["Upanishad", "Upanishads", "Upnishad"]),
            StarterTerm(source: "Veda / Vedas", translation: "Веды", category: "Священные писания", variants: ["Vegas", "Veedas", "Vedaas"]),
            StarterTerm(source: "harināma", translation: "харинама", category: "Практики", variants: ["Harinama", "Harinam", "Hari nama"]),
            StarterTerm(source: "nāma-haṭṭa", translation: "нама-хатта", category: "Организации", variants: ["Nama hatta", "Nama-hatta", "Namahatta"]),
            StarterTerm(source: "ISKCON", translation: "ИСККОН", category: "Организации", variants: ["Iskon", "Iskcon", "Isckon"]),
            StarterTerm(source: "Gauḍīya Maṭha", translation: "Гаудия Матха", category: "Организации", variants: ["Gaudiya Math", "Gaudiya Matha", "Gaudia Math"]),
            StarterTerm(source: "Gauḍīya Vaiṣṇavism", translation: "Гаудия-вайшнавизм", category: "Философские термины", variants: ["Gaudiya Vaishnavism", "Gaudiya Vaishnavas", "Gaudia Vaishnavism"]),
            StarterTerm(source: "acintya-bhedābheda", translation: "ачинтья-бхедабхеда", category: "Философские термины", variants: ["Achintya Bhedabheda", "Achintya bhedabheda", "Acintya Bheda Abheda"]),
            StarterTerm(source: "pañca-tattva", translation: "панча-таттва", category: "Аватары / Господь", variants: ["Pancha tattva", "Pancha-tattva", "Panca tattva"]),
            StarterTerm(source: "Govinda", translation: "Говинда", category: "Имена Бога", variants: ["Govindaa", "Govind", "Goovinda"]),
            StarterTerm(source: "Gopāla", translation: "Гопала", category: "Имена Бога", variants: ["Gopala", "Gopal", "Goopal"]),
            StarterTerm(source: "gopī", translation: "гопи", category: "Философские термины", variants: ["Gopis", "Gopees", "Gopii"]),
            StarterTerm(source: "Nanda Mahārāja", translation: "Нанда Махараджа", category: "Священные личности", variants: ["Nanda Maharaja", "Nanda Maharaj", "Nand Maharaj"]),
            StarterTerm(source: "Yaśodā", translation: "Яшода", category: "Священные личности", variants: ["Yashoda", "Yasoda", "Yashoda maa"]),
            StarterTerm(source: "Devakī", translation: "Деваки", category: "Священные личности", variants: ["Devaki", "Devakee", "Devakii"]),
            StarterTerm(source: "sādhana", translation: "садхана", category: "Практики", variants: ["Sadhana", "Saadhanaa", "Sadhan"]),
            StarterTerm(source: "sādhana-bhakti", translation: "садхана-бхакти", category: "Практики", variants: ["Sadhana Bhakti", "Sadhana-bhakti", "Sadhanabhakti"]),
            StarterTerm(source: "vaidhī-bhakti", translation: "вайдхи-бхакти", category: "Практики", variants: ["Vaidhi Bhakti", "Vaidhi-bhakti", "Vaidhabhakti"]),
            StarterTerm(source: "rāgānugā-bhakti", translation: "раганугабхакти", category: "Практики", variants: ["Raganuga Bhakti", "Raganuga-bhakti", "Raganugabhakti"]),
            StarterTerm(source: "nava-vidha bhakti", translation: "нававидха-бхакти", category: "Практики", variants: ["Navavidha Bhakti", "Nine processes of bhakti", "Nava-vidha"]),
            StarterTerm(source: "śravaṇam", translation: "шраванам", category: "Практики", variants: ["Shravanam", "Shravana", "Sravanam"]),
            StarterTerm(source: "kīrtanam", translation: "киртанам", category: "Практики", variants: ["Kirtanam", "Kirtana", "Keertanam"]),
            StarterTerm(source: "smaraṇam", translation: "смаранам", category: "Практики", variants: ["Smaranam", "Smarana", "Smarnam"]),
            StarterTerm(source: "pāda-sevanam", translation: "пада-севанам", category: "Практики", variants: ["Pada sevanam", "Padasevana", "Pada-sevanam"]),
            StarterTerm(source: "arcanam", translation: "арчанам", category: "Практики", variants: ["Archanam", "Archana", "Arcanam"]),
            StarterTerm(source: "vandanam", translation: "ванданам", category: "Практики", variants: ["Vandanam", "Vandana", "Vandam"]),
            StarterTerm(source: "dāsyam", translation: "дасьям", category: "Практики", variants: ["Dasyam", "Dasya", "Dashyam"]),
            StarterTerm(source: "sakhyam", translation: "сакхьям", category: "Практики", variants: ["Sakhyam", "Sakhya", "Sakheeyam"]),
            StarterTerm(source: "ātma-nivedanam", translation: "атма-ниведанам", category: "Практики", variants: ["Atma nivedanam", "Atma-nivedanam", "Atmanivedanam"]),
            StarterTerm(source: "anarthas", translation: "анартхи", category: "Философские термины", variants: ["Anartha", "Anarthaas"]),
            StarterTerm(source: "arcana", translation: "арчана", category: "Практики", variants: ["Archana", "Archana puja", "Archanaa"]),
            StarterTerm(source: "Svarūpa Dāmodara", translation: "Сварупа Дамодара", category: "Ачарьи / Учители", variants: ["Svarupa Damodara", "Svarup Damodar", "Swarupa Damodar"]),
            StarterTerm(source: "Vāsudeva Datta", translation: "Васудева Датта", category: "Ачарьи / Учители", variants: ["Vasudeva Datta", "Vasudeva Datta Thakur", "Vasudev Datta"]),
            StarterTerm(source: "Śrīmatī", translation: "Шримати", category: "Имена Бога", variants: ["Srimati", "Srimathi", "Shrimati"])
        ]

        return rawTerms.map { term in
            let id = "starter-vaishnava-\(slug(term.source))"
            let categoryLabel = categoryLabels[term.category] ?? term.category
            let variantsList = expandVariants(source: term.source, variants: term.variants)
            return GlossaryEntry(
                id: id,
                variants: variantsList,
                source: term.source,
                translation: term.translation,
                category: categoryLabel,
                translations: ["Russian": term.translation, "Default": term.translation],
                remember: true,
                createdAt: "2026-05-08T00:00:00.000Z",
                updatedAt: "2026-05-08T00:00:00.000Z"
            )
        }
    }()

    public static func mergeStarterGlossary(_ entries: [GlossaryEntry]) -> [GlossaryEntry] {
        let existingIds = Set(entries.map { $0.id })
        let existingSources = Set(entries.map { $0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let missing = StarterGlossary.entries.filter { !existingIds.contains($0.id) && !existingSources.contains($0.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        return entries + missing
    }
}
