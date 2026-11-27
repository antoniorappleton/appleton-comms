import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

const WordHistory_valueKey = "kbW";
// Pairs of consecutive words: "prev next" -> count.
const WordPairs_valueKey = "kbN";
const wordHistoryMaxCount = 100;
const wordHistoryMinLength = 3;

// Word suggestions for the keyboard: a small Portuguese dictionary plus the words of the
// messages sent from the watch. Words are matched without accents ("nao" -> "não").
module Messaging {

typedef WordHistory as Lang.Dictionary<Lang.String, Lang.Number>;

// Frequent words in text messages, by first letter (a..z), most frequent first.
// Each entry is "key|word" (key: typed, without accents) or just the word.
// Every string starts with a space, so " " + prefix finds the start of a word.
const SUGGESTION_WORDS = [
    " a ao as agora aqui ainda ate|até amanha|amanhã antes assim aula almoco|almoço almocar|almoçar atrasado atrasada acabei acabou acho abraco|abraço adoro amor amigo amiga aeroporto avisa aviso apanhar",
    " bom boa bem beijo beijos beijinhos bocado breve buscar boas",
    " com como casa chego chegar cheguei chegaste chegou carro caminho cedo comer combinado contigo comigo consigo cafe|café claro certo correu cansado cansada conta custa",
    " de do da dos das depois dia dias dizer diz disse daqui deixa demora desculpa dormir domingo dinheiro dentro",
    " e em eu estou esta|está estas|estás estamos estava estive ela ele eles elas entao|então espera esqueci escola estrada encontro",
    " fazer faz fica ficar fiz falar falamos falta fim feito festa feliz favor fora frio fui foi",
    " gosto gostei grande gente",
    " hoje hora horas ha|há",
    " ir isso isto ia indo",
    " ja|já jantar janta jantamos jogo junto",
    " ",
    " la|lá logo ligar ligo liga ligas lembra lembrei longe levar leva lugar",
    " me mais mas muito muita muitos minha meu mesmo mae|mãe momento mensagem manha|manhã melhor menos mar mim minutos",
    " nao|não no na nos nas nada noite nunca nem novo nova nosso nossa num numa",
    " o os ok obrigado obrigada onde ontem ou outra outro ola|olá",
    " para por pode podes posso pouco porque perto pai preciso precisas pois passar passo podemos primeiro praia pronto pronta pessoal",
    " que quando quem qual quero queres quase quanto",
    " reuniao|reunião resto receber recebi rapido|rápido rua",
    " se sim sei sou so|só sair saio saiu sabes semana sempre sexta sabado|sábado segunda seguir surf",
    " te tu tudo tem tens tenho tambem|também tarde trabalho tempo tive trazer tranquilo treino tomar",
    " um uma umas uns ultimo|último",
    " vou vais vai vamos vem vens ver vez vejo verdade volta voltar vemos",
    " ",
    " ",
    " ",
    " "
] as Lang.Array<Lang.String>;

// Usual next word, " prev=entry" (prev typed without accents). "boa" depends on the time of day.
const NEXT_WORDS = " bom=dia tudo=bem esta=bem estou=a daqui=a chego=em ate=logo muito=obrigado vou=para a=caminho em=casa sem=problema";

const ACCENTS_LOWER = "áàâãéêíóôõúç";
const ACCENTS_UPPER = "ÁÀÂÃÉÊÍÓÔÕÚÇ";
const ACCENTS_PLAIN = "aaaaeeiooouc";

function loadWordHistory() as WordHistory {
    return loadWordStore(WordHistory_valueKey);
}

function loadWordPairs() as WordHistory {
    return loadWordStore(WordPairs_valueKey);
}

function loadWordStore(key as Lang.String) as WordHistory {
    var stored = Storage.getValue(key);
    if (stored instanceof Lang.Dictionary) {
        return stored as WordHistory;
    }
    return {} as WordHistory;
}

// The entry for the word usually written after [prev] (lower case letters), or null:
// the user's own most frequent pair first, then the built-in pairs.
function suggestNextWord(prev as Lang.String, pairs as WordHistory) as Lang.String or Null {
    if (!isPlainLetters(prev)) {
        return null;
    }
    var start = prev + " ";
    var best = null as Lang.String or Null;
    var bestCount = 0;
    var keys = pairs.keys();
    for (var i = 0; i < keys.size(); i++) {
        var key = keys[i];
        var count = pairs[key] as Lang.Number;
        if (count > bestCount && startsWith(key, start)) {
            best = key.substring(start.length(), key.length()) as Lang.String;
            bestCount = count;
        }
    }
    if (best != null) {
        return best;
    }
    if (prev.equals("boa")) {
        var hour = Gregorian.info(Time.now(), Time.FORMAT_SHORT).hour;
        return hour >= 20 || hour < 5 ? "noite" : "tarde";
    }
    var at = NEXT_WORDS.find(" " + prev + "=");
    if (at == null) {
        return null;
    }
    var rest = NEXT_WORDS.substring(at + prev.length() + 2, NEXT_WORDS.length()) as Lang.String;
    var space = rest.find(" ");
    return space == null ? rest : rest.substring(0, space) as Lang.String;
}

// Keeps a word store within its size limit, forgetting the least used entries.
function trimWordStore(store as WordHistory) as Void {
    while (store.size() > wordHistoryMaxCount) {
        var keys = store.keys();
        var least = keys[0];
        for (var i = 1; i < keys.size(); i++) {
            if ((store[keys[i]] as Lang.Number) < (store[least] as Lang.Number)) {
                least = keys[i];
            }
        }
        store.remove(least);
    }
}

function entryKey(entry as Lang.String) as Lang.String {
    var bar = entry.find("|");
    return bar == null ? entry : entry.substring(0, bar) as Lang.String;
}

function entryWord(entry as Lang.String) as Lang.String {
    var bar = entry.find("|");
    return bar == null ? entry : entry.substring(bar + 1, entry.length()) as Lang.String;
}

function startsWith(s as Lang.String, prefix as Lang.String) as Lang.Boolean {
    return s.length() >= prefix.length() && (s.substring(0, prefix.length()) as Lang.String).equals(prefix);
}

// Lower case, accented capitals included (toLower may only know ASCII).
function lowerWord(word as Lang.String) as Lang.String {
    var chars = word.toCharArray();
    var result = "";
    for (var i = 0; i < chars.size(); i++) {
        var c = chars[i].toString();
        var index = ACCENTS_UPPER.find(c);
        result += index == null ? c.toLower() : ACCENTS_LOWER.substring(index, index + 1) as Lang.String;
    }
    return result;
}

function upperFirst(word as Lang.String) as Lang.String {
    if (word.length() == 0) {
        return word;
    }
    var first = word.substring(0, 1) as Lang.String;
    var index = ACCENTS_LOWER.find(first);
    first = index == null ? first.toUpper() : ACCENTS_UPPER.substring(index, index + 1) as Lang.String;
    return first + (word.substring(1, word.length()) as Lang.String);
}

// What is typed on the keyboard for [word]: lower case, without accents.
function plainWord(word as Lang.String) as Lang.String {
    var chars = lowerWord(word).toCharArray();
    var result = "";
    for (var i = 0; i < chars.size(); i++) {
        var c = chars[i].toString();
        var index = ACCENTS_LOWER.find(c);
        result += index == null ? c : ACCENTS_PLAIN.substring(index, index + 1) as Lang.String;
    }
    return result;
}

function isPlainLetters(s as Lang.String) as Lang.Boolean {
    var chars = s.toCharArray();
    for (var i = 0; i < chars.size(); i++) {
        var code = chars[i].toNumber();
        if (code < 97 || code > 122) {
            return false;
        }
    }
    return chars.size() > 0;
}

// The entry ("key|word") suggested to complete [prefix] (lower case letters), or null.
// A prefix that is itself a frequent word ("a", "de", "e") gets no suggestion,
// so that holding GPS still types just a space.
// Words already sent at least twice come first; then the dictionary; then words sent once.
function suggestWord(prefix as Lang.String, history as WordHistory) as Lang.String or Null {
    if (!isPlainLetters(prefix)) {
        return null;
    }
    var dictEntry = null as Lang.String or Null;
    var words = SUGGESTION_WORDS[prefix.toCharArray()[0].toNumber() - 97];
    var at = words.find(" " + prefix);
    if (at != null) {
        var rest = words.substring(at + 1, words.length()) as Lang.String;
        var space = rest.find(" ");
        var entry = space == null ? rest : rest.substring(0, space) as Lang.String;
        if (entryKey(entry).length() == prefix.length()) {
            return null;
        }
        dictEntry = entry;
    }
    var histEntry = null as Lang.String or Null;
    var histCount = 0;
    var exactCount = 0;
    var keys = history.keys();
    for (var i = 0; i < keys.size(); i++) {
        var entry = keys[i];
        var key = entryKey(entry);
        if (!startsWith(key, prefix)) {
            continue;
        }
        var count = history[entry] as Lang.Number;
        if (key.length() == prefix.length()) {
            exactCount = count > exactCount ? count : exactCount;
        } else if (count > histCount) {
            histEntry = entry;
            histCount = count;
        }
    }
    if (histEntry != null && histCount > exactCount && (histCount >= 2 || dictEntry == null)) {
        return histEntry;
    }
    if (exactCount > 0) {
        return null; // the user writes the prefix itself as a word
    }
    return dictEntry;
}

// Adds the words of a sent message to the history (3 letters or more, letters only),
// and each pair of consecutive words within a sentence to the pairs.
function recordWords(message as Lang.String) as Void {
    var history = loadWordHistory();
    var pairs = loadWordPairs();
    var prev = null as Lang.String or Null;
    var rest = message;
    while (rest.length() > 0) {
        var space = rest.find(" ");
        var word = space == null ? rest : rest.substring(0, space) as Lang.String;
        rest = space == null ? "" : rest.substring(space + 1, rest.length()) as Lang.String;
        var punctuated = false;
        while (word.length() > 0 && ".,?!".find(word.substring(word.length() - 1, word.length()) as Lang.String) != null) {
            word = word.substring(0, word.length() - 1) as Lang.String;
            punctuated = true;
        }
        var key = plainWord(word);
        if (!isPlainLetters(key)) {
            prev = null;
            continue;
        }
        var lower = lowerWord(word);
        var entry = key.equals(lower) ? key : key + "|" + lower;
        if (key.length() >= wordHistoryMinLength) {
            var count = history[entry];
            history[entry] = count == null ? 1 : count + 1;
        }
        if (prev != null) {
            var pair = prev + " " + entry;
            var pairCount = pairs[pair];
            pairs[pair] = pairCount == null ? 1 : pairCount + 1;
        }
        prev = punctuated ? null : key;
    }
    trimWordStore(history);
    trimWordStore(pairs);
    Storage.setValue(WordHistory_valueKey, history as Lang.Dictionary<Application.Storage.KeyType, Application.Storage.ValueType>);
    Storage.setValue(WordPairs_valueKey, pairs as Lang.Dictionary<Application.Storage.KeyType, Application.Storage.ValueType>);
}

}
