package com.gentin.connectiq.handsfree.globals

import android.content.Context
import androidx.core.content.edit
import androidx.preference.PreferenceManager

fun essentialsAreOn(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("essentials", false)
}

fun outgoingCallsShouldBeEnabled(context: Context): Boolean {
    return essentialsAreOn(context) && outgoingCallsAreOn(context)
}

fun outgoingCallsAreOn(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("outgoing_calls", false)
}

fun incomingCallsAreOn(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("incoming_calls", false)
}

fun recentsAreOn(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("recents", false)
}

fun starredContactsAreOn(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("starred_contacts", false)
}

fun messagesAreOn(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("messages", false)
}

const val quickMessagesPreferenceKey = "quick_messages"
const val quickMessagesLimit = 20
const val quickMessageMaxLength = 160

val defaultQuickMessages = listOf(
    "Estou a caminho 🚗",
    "Já te ligo 📞",
    "Estou numa reunião, falamos depois.",
    "Chego em 5 minutos ⏰",
    "Chego em 10 minutos ⏰",
    "Vou atrasar-me um pouco, desculpa 😅",
    "Está tudo bem 👍",
    "Combinado 👍",
    "Sim ✅",
    "Não, obrigado.",
    "Obrigado! 🙏",
    "Liga-me quando puderes 📞",
    "Estou a conduzir, ligo-te depois 🚗",
    "Estou a treinar 💪",
    "Já cheguei 🏠",
    "Onde estás? 📍",
    "Bom dia! ☀️",
    "Beijinhos 😘",
    "Amo-te ❤️",
    "Preciso de ajuda, liga-me já 🆘"
)

fun quickMessagesText(context: Context): String {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getString(quickMessagesPreferenceKey, null)
        ?: defaultQuickMessages.joinToString("\n")
}

// One message per line; blank lines are ignored.
fun quickMessages(context: Context): List<String> {
    return quickMessagesText(context)
        .lines()
        .map { takeCodePoints(it.trim(), quickMessageMaxLength) }
        .filter { it.isNotEmpty() }
        .take(quickMessagesLimit)
}

fun isInDebugMode(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("debug", false)
}

fun setIsInDebugMode(context: Context, value: Boolean) {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    sharedPreferences.edit {
        putBoolean("debug", value)
    }
}

fun isInEmulatorMode(context: Context): Boolean {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    return sharedPreferences.getBoolean("emulatorMode", false)
}

fun setIsInEmulatorMode(context: Context, value: Boolean) {
    val sharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    sharedPreferences.edit(commit = true) {
        putBoolean("emulatorMode", value)
    }
}
