.pragma library
// Смайлики для поиска и раздела: [символ, слова по-русски, слова по-английски]. Набор — частые, не весь Unicode.
var LIST = [
["😀", "улыбка радость смех", "grin smile happy"], ["😂", "смех слёзы ржу ахаха", "joy laugh lol tears"],
["🤣", "катаюсь смех ору", "rofl laugh rolling"], ["😊", "улыбка мило доволен", "blush smile happy"],
["😍", "влюблён любовь глаза сердечки", "heart eyes love"], ["😘", "поцелуй целую", "kiss blow"],
["😉", "подмигнуть подмигивание", "wink"], ["😎", "круто очки крутой", "cool sunglasses"],
["🤔", "думаю хм размышление", "thinking hmm"], ["🙄", "закатить глаза ну да", "eyeroll roll eyes"],
["😐", "нейтрально без эмоций", "neutral meh"], ["😴", "сон сплю спать", "sleep sleeping zzz"],
["😭", "плачу рыдаю слёзы", "sob cry crying"], ["😢", "грусть слеза печаль", "cry sad tear"],
["😡", "злость злой ярость", "angry rage mad"], ["😱", "ужас крик страх", "scream fear shock"],
["😳", "смущение покраснел", "flushed embarrassed"], ["🥺", "пожалуйста умоляю жалобно", "pleading please"],
["😅", "пот неловко фух", "sweat smile awkward"], ["🙂", "улыбка слегка", "slight smile"],
["🙃", "вверх ногами ирония", "upside down irony"], ["😇", "ангел невинный", "angel innocent halo"],
["🤯", "взрыв мозга шок", "mind blown exploding head"], ["🥳", "праздник вечеринка ура", "party celebrate"],
["🤩", "восторг звёзды", "star struck excited"], ["😋", "вкусно ням", "yum delicious"],
["🤤", "слюни хочу", "drool"], ["🤗", "обнимаю объятия", "hug hugging"],
["🤫", "тсс тихо секрет", "shush quiet secret"], ["🤭", "ой хихи", "oops giggle"],
["😬", "неловко гримаса", "grimace awkward"], ["🤐", "молчу рот на замке", "zipper mouth silent"],
["🤢", "тошнит фу", "nauseated sick"], ["🤒", "болею температура", "sick fever"],
["🥶", "холодно мёрзну", "cold freezing"], ["🥵", "жарко жара", "hot heat"],
["😈", "чертёнок дьявол", "devil smiling imp"], ["💀", "череп умер смерть", "skull dead"],
["👻", "призрак привидение", "ghost"], ["🤡", "клоун", "clown"], ["💩", "какашка", "poop"],
["🤖", "робот бот", "robot bot"], ["👽", "инопланетянин пришелец", "alien"],
["👍", "лайк класс да хорошо палец вверх", "like thumbs up yes ok"], ["👎", "дизлайк плохо нет", "dislike thumbs down no"],
["👌", "окей хорошо отлично", "ok okay perfect"], ["✌️", "мир победа", "peace victory"],
["🤞", "удачи скрестить пальцы", "fingers crossed luck"], ["👏", "аплодисменты браво хлопать", "clap applause bravo"],
["🙏", "спасибо пожалуйста молюсь", "pray thanks please"], ["🤝", "рукопожатие договорились", "handshake deal"],
["👋", "привет пока махать", "wave hello bye hi"], ["💪", "сила мышцы сильный", "muscle strong flex"],
["🫡", "есть так точно", "salute"], ["🤷", "не знаю пожимаю плечами", "shrug dunno"],
["🤦", "фейспалм рукалицо", "facepalm"], ["🙈", "не вижу стыдно", "see no evil monkey"],
["👀", "глаза смотрю", "eyes look"], ["🧠", "мозг ум", "brain smart"],
["❤️", "сердце любовь", "heart love red"], ["🧡", "оранжевое сердце", "orange heart"],
["💛", "жёлтое сердце", "yellow heart"], ["💚", "зелёное сердце", "green heart"],
["💙", "синее сердце", "blue heart"], ["💜", "фиолетовое сердце", "purple heart"],
["🖤", "чёрное сердце", "black heart"], ["🤍", "белое сердце", "white heart"],
["💔", "разбитое сердце", "broken heart"], ["💯", "сто сотка точно", "hundred 100"],
["🔥", "огонь огненно круто жара", "fire lit hot"], ["✨", "блёстки искры магия", "sparkles magic"],
["⭐", "звезда", "star"], ["🌟", "сияющая звезда", "glowing star"], ["⚡", "молния быстро", "zap lightning fast"],
["💥", "бум взрыв", "boom explosion"], ["🎉", "праздник ура хлопушка", "tada party celebration"],
["🎂", "торт день рождения", "cake birthday"], ["🎁", "подарок", "gift present"],
["🏆", "кубок победа приз", "trophy win"], ["🥇", "золото первое место", "gold medal first"],
["✅", "готово галочка да", "check done yes"], ["❌", "нет крестик ошибка", "cross no wrong"],
["⚠️", "внимание осторожно", "warning caution"], ["❓", "вопрос", "question"],
["❗", "восклицание важно", "exclamation important"], ["💡", "идея лампочка", "idea bulb"],
["📌", "закреп булавка", "pin pushpin"], ["📎", "скрепка вложение", "paperclip attachment"],
["📝", "заметка записать", "memo note"], ["📅", "календарь дата", "calendar date"],
["⏰", "будильник время", "alarm clock"], ["⌛", "песочные часы ждать", "hourglass wait"],
["🔒", "замок закрыто", "lock locked"], ["🔑", "ключ", "key"], ["🔍", "поиск лупа", "search magnifier"],
["⚙️", "настройки шестерёнка", "gear settings"], ["🛠️", "инструменты ремонт", "tools repair"],
["🐛", "баг жук", "bug"], ["🚀", "ракета запуск", "rocket launch"], ["💻", "ноутбук компьютер", "laptop computer"],
["🖥️", "монитор компьютер", "desktop computer"], ["📱", "телефон смартфон", "phone mobile"],
["⌨️", "клавиатура", "keyboard"], ["🎧", "наушники музыка", "headphones music"],
["🎵", "нота музыка", "music note"], ["🎮", "игра геймпад", "game controller"],
["📷", "фото камера", "camera photo"], ["🎬", "кино фильм", "movie clapper film"],
["📚", "книги учёба", "books study"], ["✏️", "карандаш", "pencil"], ["📧", "почта письмо", "email mail"],
["💬", "сообщение чат", "speech chat message"], ["🔔", "колокольчик уведомление", "bell notification"],
["💰", "деньги мешок", "money bag"], ["💸", "деньги улетают трата", "money wings spend"],
["📈", "рост график", "chart up growth"], ["📉", "падение график", "chart down"],
["☕", "кофе чай", "coffee tea"], ["🍕", "пицца", "pizza"], ["🍔", "бургер", "burger"],
["🍺", "пиво", "beer"], ["🍷", "вино", "wine"], ["🍰", "пирожное торт", "cake slice"],
["🍎", "яблоко", "apple"], ["🍌", "банан", "banana"], ["🍓", "клубника", "strawberry"],
["🐱", "кот кошка котик", "cat kitty"], ["🐶", "собака пёс", "dog puppy"], ["🦊", "лиса", "fox"],
["🐻", "медведь", "bear"], ["🐼", "панда", "panda"], ["🐸", "лягушка", "frog"], ["🦄", "единорог", "unicorn"],
["🌈", "радуга", "rainbow"], ["☀️", "солнце", "sun sunny"], ["🌙", "луна ночь", "moon night"],
["☁️", "облако", "cloud"], ["🌧️", "дождь", "rain"], ["❄️", "снег снежинка", "snow snowflake"],
["🌸", "цветок сакура", "flower blossom"], ["🌹", "роза", "rose"], ["🌲", "ёлка дерево", "tree evergreen"],
["🎄", "новогодняя ёлка новый год", "christmas tree"], ["🏠", "дом", "home house"],
["🚗", "машина авто", "car"], ["✈️", "самолёт полёт", "airplane plane flight"],
["🌍", "земля мир планета", "earth globe world"], ["🇷🇺", "россия флаг", "russia flag"],
["➡️", "стрелка вправо", "arrow right"], ["⬅️", "стрелка влево", "arrow left"],
["⬆️", "стрелка вверх", "arrow up"], ["⬇️", "стрелка вниз", "arrow down"],
["♻️", "переработка", "recycle"], ["🆗", "ок", "ok button"], ["🆕", "новое", "new"]
]

// поиск: все слова запроса — начала слов в описании (ru и en)
function find(q, limit) {
    var words = q.toLowerCase().replace(/ё/g, "е").split(/\s+/).filter(w => w)
    if (!words.length) return []
    var out = []
    for (var e of LIST) {
        var hay = (e[1] + " " + e[2]).toLowerCase().replace(/ё/g, "е").split(" ")
        if (words.every(w => hay.some(h => h.indexOf(w) === 0))) out.push(e)
        if (out.length >= (limit || 1000)) break
    }
    return out
}
// точное слово (без «:») — для общего поиска без шума
function exact(q) {
    var w = q.trim().toLowerCase().replace(/ё/g, "е")
    if (w.length < 3 || w.indexOf(" ") >= 0) return []
    return LIST.filter(e => (e[1] + " " + e[2]).toLowerCase().replace(/ё/g, "е").split(" ").indexOf(w) >= 0).slice(0, 3)
}
