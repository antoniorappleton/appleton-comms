package com.gentin.connectiq.handsfree.globals

// Watch fonts (e.g. Instinct 3) have no emoji glyphs: quick messages are shown on the watch with
// emojis replaced by short text, while the SMS itself is sent with the original emojis.

private val emojiAliases = linkedMapOf(
    "❤️" to "<3", "❤" to "<3", "😘" to ":*", "😍" to "<3",
    "😀" to ":D", "😃" to ":D", "😄" to ":D", "😁" to ":D",
    "😂" to "XD", "🤣" to "XD", "😊" to ":)", "🙂" to ":)", "😅" to ":)",
    "😉" to ";)", "😢" to ":(", "😭" to ":(", "🙁" to ":(", "😞" to ":(",
    "👍" to "(ok)", "👎" to "(nao)", "✅" to "(ok)", "👌" to "(ok)",
    "🙏" to "(obg)", "👋" to "(ola)", "🤗" to "(abraco)", "🙌" to "(boa)",
    "💪" to "(forca)", "🏃" to "(corrida)", "🚗" to "(carro)", "🚶" to "(a pe)",
    "🏠" to "(casa)", "📍" to "(local)", "⏰" to "(hora)", "🕐" to "(hora)",
    "📞" to "(tel)", "📱" to "(tel)", "☀️" to "(sol)", "☀" to "(sol)",
    "🌙" to "(noite)", "😴" to "(zzz)", "☕" to "(cafe)", "🍽️" to "(jantar)",
    "🍽" to "(jantar)", "🎉" to "(festa)", "🎂" to "(parabens)", "🔋" to "(bateria)",
    "⚠️" to "(!)", "⚠" to "(!)", "🆘" to "(SOS)", "❗" to "!", "❓" to "?"
)

fun quickMessageForWatch(text: String): String {
    var result = text
    for ((emoji, alias) in emojiAliases) {
        result = result.replace(emoji, alias)
    }
    // Drop any other emoji or emoji modifier the watch can't display.
    val builder = StringBuilder()
    var i = 0
    while (i < result.length) {
        val codePoint = result.codePointAt(i)
        if (!isEmojiCodePoint(codePoint)) {
            builder.appendCodePoint(codePoint)
        }
        i += Character.charCount(codePoint)
    }
    return builder.toString().replace(Regex(" {2,}"), " ").trim()
}

private fun isEmojiCodePoint(codePoint: Int): Boolean {
    return codePoint >= 0x1F000 || // pictographs, emoticons, flags, skin tones
        codePoint in 0x2600..0x27BF || // misc symbols and dingbats
        codePoint in 0x2B00..0x2BFF || // arrows and stars used as emoji
        codePoint == 0xFE0F || codePoint == 0x200D // variation selector, zero width joiner
}

// Truncates without splitting a surrogate pair (emoji).
fun takeCodePoints(text: String, maxCodePoints: Int): String {
    if (text.codePointCount(0, text.length) <= maxCodePoints) {
        return text
    }
    return text.substring(0, text.offsetByCodePoints(0, maxCodePoints))
}
