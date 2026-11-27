import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Typing metric: total presses and characters of the messages written on the keyboard.
const KeyboardPresses_valueKey = "kbP";
const KeyboardChars_valueKey = "kbC";
const keyboardLongPressMs = 500;

module Messaging {

// Keyboard by letter groups, ordered by letter frequency in Portuguese (from AppletonSMS).
// Level 1: groups. Level 2: characters of the chosen group.
// UP/DOWN move (wrapping around), GPS/START selects.
// BACK: level 2 -> level 1; level 1 -> deletes the last character; empty text -> leaves
// (after deleting everything, only the second BACK leaves, so fast deleting can't leave the app).
// Hold DOWN: 3 positions down. Hold BACK: deletes the last word.
// (Holding GPS is not used: on the Instinct it opens the system GPS screen.)
// Hold UP (menu): leaves the keyboard; asks "Descartar?" if there is text.
// A suggested word ("> palavra") is the first item of the list, just above "Espaco", and gets
// the focus; GPS accepts it with a space. Otherwise, at the start of a word the focus is on
// "Espaco" (UP once: "Concluir"); inside a word it goes to the group of the most likely next
// letter (Portuguese), and inside a group to its most likely letter.
// "Concluir" opens the confirmation screen; after sending, the app returns to the contact list.
class KeyboardView extends WatchUi.View {

    // Characters of each group, upper case (the case is decided on insertion).
    // "Apagar" and "Concluir" have no characters.
    const GROUPS = [" ", "AEO", "SRIN", "DMUT", "CLPV", "GQBFH", "JZXKWY", ".,?!", "0123456789", "", ""] as Lang.Array<Lang.String>;

    // Level 1 labels (same order as GROUPS). No special symbols: the font may lack them.
    const LABELS = ["Espaco", "A E O", "S R I N", "D M U T", "C L P V", "G Q B F H", "J Z X K W Y",
                    ". , ? !", "0-9", "Apagar", "Concluir"] as Lang.Array<Lang.String>;

    // Most likely next characters after each letter a..z, in Portuguese ("_" is a space).
    const NEXT = ["_snrdmlt", "earoilu", "oaeihur", "eoai_u", "_srnmlti", "aioeur", "auoeri", "eoai",
                  "nsaotdcr_", "auoe", "_eai", "aeohiu_", "_eaoipu", "tdaoechs", "_srnmudl", "aoreilu",
                  "u", "aeo_itsr", "_eatosiu", "aeoiru_", "meianr_sl", "eiao", "aei_", "iae_", "_oa",
                  "_eaio"] as Lang.Array<Lang.String>;
    // ... at the start of a word.
    const NEXT_START = "deapcosqnmut";

    const G_SUGGESTION = -1; // the suggested word, shown before "Espaco"
    const G_FIRST_LETTER = 1;
    const G_LAST_LETTER = 6;
    const G_DELETE = 9;
    const G_DONE = 10;

    const MESSAGE_MAX_LEN = 160; // one SMS (GSM-7)
    const SEARCH_MAX_LEN = 30;
    const TAIL_LEN = 14;   // characters visible at the top

    enum {
        MODE_GROUPS,
        MODE_CHARS,
        MODE_DISCARD
    }

    // The recipient of the message, or null when the keyboard is used to search contacts.
    private var phone as Phone or Null;
    private var maxLen as Lang.Number;
    private var text as Lang.String = "";
    private var mode as Lang.Number = MODE_GROUPS;
    private var group as Lang.Number = 0;
    private var char as Lang.Number = 0;
    // Button presses for this text, and what of it was already added to the stored metric.
    private var presses as Lang.Number = 0;
    private var savedPresses as Lang.Number = 0;
    private var savedChars as Lang.Number = 0;
    // Word suggestions (messages only, not when searching contacts).
    private var history as WordHistory or Null = null;
    private var pairs as WordHistory or Null = null;
    private var cachedPrefix as Lang.String or Null = null;
    private var cachedEntry as Lang.String or Null = null;
    private var recordedText as Lang.String or Null = null;
    // The text was emptied by deleting: the next BACK doesn't leave yet.
    private var emptiedByDelete as Lang.Boolean = false;

    function initialize(phone as Phone or Null) {
        View.initialize();
        self.phone = phone;
        maxLen = phone == null ? SEARCH_MAX_LEN : MESSAGE_MAX_LEN;
        if (phone != null) {
            history = loadWordHistory();
            pairs = loadWordPairs();
        }
        focusAfterChange();
    }

    // MARK: Actions (from KeyboardDelegate)

    function move(step as Lang.Number) as Void {
        presses += 1;
        if (mode == MODE_GROUPS) {
            var offset = groupOffset();
            group = wrap(group + offset + step, LABELS.size() + offset) - offset;
        } else if (mode == MODE_CHARS) {
            char = wrap(char + step, GROUPS[group].length());
        } else {
            return;
        }
        WatchUi.requestUpdate();
    }

    function select() as Void {
        presses += 1;
        if (mode == MODE_DISCARD) {
            leave();
            return;
        }
        if (mode == MODE_CHARS) {
            addChar(focusedChar());
            mode = MODE_GROUPS;
            focusAfterChange();
        } else if (group == G_SUGGESTION) {
            var entry = currentSuggestion();
            if (entry != null) {
                acceptSuggestion(entry);
            }
            focusAfterChange();
        } else if (group == G_DELETE) {
            deleteLast();
            focusAfterChange();
        } else if (group == G_DONE) {
            finish();
        } else if (GROUPS[group].length() == 1) {
            addChar(GROUPS[group]);
            focusAfterChange();
        } else {
            mode = MODE_CHARS;
            // The first letter of a word is picked as before, from the start of the group.
            char = atWordStart() ? 0 : likelyChar(group);
        }
        WatchUi.requestUpdate();
    }

    // Hold BACK: deletes the last word (and the spaces after it).
    function backLong() as Void {
        presses += 1;
        if (mode == MODE_DISCARD) {
            mode = MODE_GROUPS;
            WatchUi.requestUpdate();
            return;
        }
        var end = text.length();
        if (end == 0) {
            buzz();
            return;
        }
        while (end > 0 && (text.substring(end - 1, end) as Lang.String).equals(" ")) {
            end -= 1;
        }
        while (end > 0 && !(text.substring(end - 1, end) as Lang.String).equals(" ")) {
            end -= 1;
        }
        text = text.substring(0, end) as Lang.String;
        emptiedByDelete = end == 0;
        mode = MODE_GROUPS;
        focusAfterChange();
        WatchUi.requestUpdate();
    }

    function back() as Void {
        presses += 1;
        if (mode != MODE_GROUPS) {
            mode = MODE_GROUPS;
        } else if (text.length() > 0) {
            deleteLast();
            focusAfterChange();
        } else if (emptiedByDelete) {
            // Everything was just deleted: stop here; BACK again leaves.
            emptiedByDelete = false;
            buzz();
            return;
        } else {
            leave();
            return;
        }
        WatchUi.requestUpdate();
    }

    function requestExit() as Void {
        presses += 1;
        if (mode == MODE_DISCARD) {
            return;
        }
        if (text.length() == 0) {
            leave();
            return;
        }
        mode = MODE_DISCARD;
        WatchUi.requestUpdate();
    }

    private function leave() as Void {
        VT.popView(WatchUi.SLIDE_RIGHT);
    }

    // MARK: Prediction

    private function focusedChar() as Lang.String {
        return GROUPS[group].substring(char, char + 1) as Lang.String;
    }

    // Most likely next characters, best first, after the text typed so far.
    private function nextRank() as Lang.String {
        var n = text.length();
        if (n == 0) {
            return NEXT_START;
        }
        var last = (text.substring(n - 1, n) as Lang.String).toLower();
        if (last.equals(" ")) {
            return NEXT_START;
        }
        var index = last.toCharArray()[0].toNumber() - 97; // 'a'
        if (index >= 0 && index < NEXT.size()) {
            return NEXT[index];
        }
        if ("0123456789".find(last) != null) {
            return "0_"; // numbers usually go on
        }
        return "_"; // after punctuation
    }

    private function focusLikelyGroup() as Void {
        var top = nextRank().substring(0, 1) as Lang.String;
        group = 0; // space
        if (top.equals("_")) {
            return;
        }
        var upper = top.toUpper();
        for (var g = G_FIRST_LETTER; g < GROUPS.size(); g++) {
            if (GROUPS[g].find(upper) != null) {
                group = g;
                return;
            }
        }
    }

    private function atWordStart() as Lang.Boolean {
        return wordStart() == text.length();
    }

    // Where the focus goes after the text changed: the suggestion if there is one; at the start
    // of a word "Espaco" as before (searching: the first letters); else the likely next group.
    private function focusAfterChange() as Void {
        if (currentSuggestion() != null) {
            group = G_SUGGESTION;
        } else if (atWordStart()) {
            group = phone == null ? G_FIRST_LETTER : 0;
        } else {
            focusLikelyGroup();
        }
    }

    // 1 while a suggestion is shown before "Espaco", else 0.
    private function groupOffset() as Lang.Number {
        return currentSuggestion() != null ? 1 : 0;
    }

    private function likelyChar(g as Lang.Number) as Lang.Number {
        var rank = nextRank();
        for (var i = 0; i < rank.length(); i++) {
            var index = GROUPS[g].find((rank.substring(i, i + 1) as Lang.String).toUpper());
            if (index != null) {
                return index;
            }
        }
        return 0;
    }

    // MARK: Word suggestions

    // Where the word being typed starts.
    private function wordStart() as Lang.Number {
        var i = text.length();
        while (i > 0 && !(text.substring(i - 1, i) as Lang.String).equals(" ")) {
            i -= 1;
        }
        return i;
    }

    // The word being typed, as typed on the keys (lower case, no accents).
    private function currentPrefix() as Lang.String {
        return plainWord(text.substring(wordStart(), text.length()) as Lang.String);
    }

    // The suggestion completing [prefix]; with no prefix yet, the word usually written next.
    private function suggestionFor(prefix as Lang.String) as Lang.String or Null {
        var h = history;
        var p = pairs;
        if (h == null || p == null) {
            return null;
        }
        var prev = prefix.length() == 0 ? previousWord() : null;
        if (prefix.length() == 0 && prev == null) {
            return null;
        }
        var cacheKey = prev != null ? "=" + prev : prefix;
        var cached = cachedPrefix;
        if (cached == null || !cached.equals(cacheKey)) {
            cachedPrefix = cacheKey;
            cachedEntry = prev != null ? suggestNextWord(prev, p) : suggestWord(prefix, h);
        }
        return cachedEntry;
    }

    // The word before the space being typed after (as typed on the keys), or null
    // at the start, after punctuation, or in the middle of a word.
    private function previousWord() as Lang.String or Null {
        var end = text.length() - 1; // the space
        if (end < 1 || !(text.substring(end, end + 1) as Lang.String).equals(" ")) {
            return null;
        }
        var start = end;
        while (start > 0 && !(text.substring(start - 1, start) as Lang.String).equals(" ")) {
            start -= 1;
        }
        var word = plainWord(text.substring(start, end) as Lang.String);
        return isPlainLetters(word) ? word : null;
    }

    // The suggestion for the text as it is (entry "key|word"), or null.
    private function currentSuggestion() as Lang.String or Null {
        return suggestionFor(currentPrefix());
    }

    // The word as it would be written: capital if the word typed so far starts with one,
    // or at the start of a sentence.
    private function suggestionText(entry as Lang.String) as Lang.String {
        var word = entryWord(entry);
        var start = wordStart();
        var capital;
        if (start < text.length()) {
            var first = text.substring(start, start + 1) as Lang.String;
            capital = !first.equals(first.toLower());
        } else {
            capital = upperNext();
        }
        return capital ? upperFirst(word) : word;
    }

    // Replaces the word being typed with the suggestion and adds a space.
    private function acceptSuggestion(entry as Lang.String) as Void {
        var start = wordStart();
        var completed = (text.substring(0, start) as Lang.String) + suggestionText(entry);
        if (completed.length() > maxLen) {
            buzz();
            return;
        }
        text = completed;
        addChar(" ");
    }

    // MARK: Metric

    // Adds this message to the stored totals (only what changed, if it is finished again).
    private function saveMetric(charCount as Lang.Number) as Void {
        var totalPresses = Storage.getValue(KeyboardPresses_valueKey) as Lang.Number or Null;
        var totalChars = Storage.getValue(KeyboardChars_valueKey) as Lang.Number or Null;
        Storage.setValue(KeyboardPresses_valueKey, (totalPresses == null ? 0 : totalPresses) + presses - savedPresses);
        Storage.setValue(KeyboardChars_valueKey, (totalChars == null ? 0 : totalChars) + charCount - savedChars);
        savedPresses = presses;
        savedChars = charCount;
    }

    // "3.4 t/c" for this text, or "med 3.4" (all messages) before typing.
    private function metricText() as Lang.String or Null {
        var n = text.length();
        if (n > 0) {
            return (presses.toFloat() / n).format("%.1f") + " t/c";
        }
        var totalPresses = Storage.getValue(KeyboardPresses_valueKey) as Lang.Number or Null;
        var totalChars = Storage.getValue(KeyboardChars_valueKey) as Lang.Number or Null;
        if (totalPresses == null || totalChars == null || totalChars == 0) {
            return null;
        }
        return "med " + (totalPresses.toFloat() / totalChars).format("%.1f");
    }

    // MARK: Text rules

    private function addChar(ch as Lang.String) as Void {
        var n = text.length();
        // Punctuation goes right after the word: replaces the space a suggestion added.
        if (n > 0 && ".,?!".find(ch) != null && (text.substring(n - 1, n) as Lang.String).equals(" ")) {
            text = text.substring(0, n - 1) as Lang.String;
            n -= 1;
        }
        // Leading or double space: ignored.
        if (ch.equals(" ") && (n == 0 || (text.substring(n - 1, n) as Lang.String).equals(" "))) {
            return;
        }
        if (n >= maxLen) {
            buzz();
            return;
        }
        text += applyCase(ch);
        emptiedByDelete = false;
    }

    private function deleteLast() as Void {
        var n = text.length();
        if (n == 0) {
            buzz();
            return;
        }
        text = text.substring(0, n - 1) as Lang.String;
        emptiedByDelete = n == 1;
    }

    private function finish() as Void {
        var message = text;
        var n = message.length();
        if (n > 0 && (message.substring(n - 1, n) as Lang.String).equals(" ")) {
            message = message.substring(0, n - 1) as Lang.String;
        }
        if (message.length() == 0) {
            buzz();
            return;
        }
        var recipient = phone;
        if (recipient == null) {
            startSearch(message);
        } else {
            saveMetric(message.length());
            var recorded = recordedText;
            if (recorded == null || !recorded.equals(message)) {
                recordWords(message);
                recordedText = message;
            }
            confirmAndSend(recipient, message, null);
        }
    }

    // Upper case at the start and after ". ", "? " or "! ".
    private function upperNext() as Lang.Boolean {
        var n = text.length();
        if (n == 0) {
            return true;
        }
        if (n >= 2 && (text.substring(n - 1, n) as Lang.String).equals(" ")) {
            return ".?!".find(text.substring(n - 2, n - 1) as Lang.String) != null;
        }
        return false;
    }

    private function applyCase(s as Lang.String) as Lang.String {
        return upperNext() ? s : s.toLower();
    }

    private function wrap(index as Lang.Number, count as Lang.Number) as Lang.Number {
        return (index + count) % count;
    }

    private function buzz() as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 80)]);
        }
    }

    // MARK: Drawing

    private function itemCount() as Lang.Number {
        return mode == MODE_CHARS ? GROUPS[group].length() : LABELS.size() + groupOffset();
    }

    // [index] counts the suggestion, when there is one, as item 0.
    private function itemText(index as Lang.Number) as Lang.String {
        if (mode == MODE_CHARS) {
            return applyCase(GROUPS[group].substring(index, index + 1) as Lang.String);
        }
        var entry = currentSuggestion();
        if (entry != null) {
            if (index == 0) {
                return "> " + suggestionText(entry);
            }
            index -= 1;
        }
        if (index >= G_FIRST_LETTER && index <= G_LAST_LETTER) {
            return applyCase(LABELS[index]);
        }
        return LABELS[index];
    }

    private function focusIndex() as Lang.Number {
        return mode == MODE_CHARS ? char : group + groupOffset();
    }

    private function fitLeft(dc as Graphics.Dc, s as Lang.String, font as Graphics.FontType, maxWidth as Lang.Number) as Lang.String {
        while (s.length() > 1 && dc.getTextWidthInPixels(s, font) > maxWidth) {
            s = s.substring(1, s.length()) as Lang.String;
        }
        return s;
    }

    private function fitRight(dc as Graphics.Dc, s as Lang.String, font as Graphics.FontType, maxWidth as Lang.Number) as Lang.String {
        while (s.length() > 1 && dc.getTextWidthInPixels(s, font) > maxWidth) {
            s = s.substring(0, s.length() - 1) as Lang.String;
        }
        return s;
    }

    // Designed for 176x176 (Instinct 3); coordinates are scaled for other screens.
    // On the Instinct the sub-window takes the top right corner (x >= 113, y <= 62).
    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        if (mode == MODE_DISCARD) {
            dc.drawText(cx, y(80, h), Graphics.FONT_SMALL, "Descartar texto?", center);
            dc.drawText(cx, y(112, h), Graphics.FONT_XTINY, "GPS = Sim", center);
            dc.drawText(cx, y(134, h), Graphics.FONT_XTINY, "BACK = Nao", center);
            return;
        }

        // Recipient (or "Pesquisar"), left of the sub-window; while a word is suggested, the word
        // (it is also the first item of the list).
        var recipient = phone;
        var suggestion = mode == MODE_GROUPS ? currentSuggestion() : null;
        var title;
        if (suggestion != null) {
            title = "> " + suggestionText(suggestion);
        } else {
            title = recipient == null ? loadIfResource(Rez.Strings.searchContacts) : getPhoneName(recipient);
        }
        dc.drawText(w * 58 / 176, y(40, h), Graphics.FONT_XTINY,
            fitRight(dc, title, Graphics.FONT_XTINY, w * 90 / 176), center);

        // Top: end of the text and cursor.
        var n = text.length();
        var start = n > TAIL_LEN ? n - TAIL_LEN : 0;
        var tail = (text.substring(start, n) as Lang.String) + "_";
        dc.drawText(cx, y(72, h), Graphics.FONT_XTINY, fitLeft(dc, tail, Graphics.FONT_XTINY, w - 20), center);
        dc.drawLine(20, y(84, h), w - 20, y(84, h));

        // Centre: previous (small), current (large, highlighted), next (small).
        var count = itemCount();
        var i = focusIndex();
        dc.drawText(cx, y(97, h), Graphics.FONT_XTINY, itemText(wrap(i - 1, count)), center);

        dc.fillRectangle(12, y(107, h), w - 24, y(28, h));
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(cx, y(121, h), Graphics.FONT_LARGE,
            fitRight(dc, itemText(i), Graphics.FONT_LARGE, w - 28), center);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);

        dc.drawText(cx, y(146, h), Graphics.FONT_XTINY, itemText(wrap(i + 1, count)), center);

        // Footer: presses per character; the counter near the limit.
        var footer = metricText();
        if (footer == null || n > maxLen - 20) {
            footer = n.toString() + "/" + maxLen.toString();
        }
        dc.drawText(cx, y(164, h), Graphics.FONT_XTINY, footer, center);
    }

    private function y(value as Lang.Number, h as Lang.Number) as Lang.Number {
        return value * h / 176;
    }
}

// DOWN and BACK act on release, or once held for keyboardLongPressMs.
// UP and GPS keep the usual behaviours (holding UP is MENU; holding GPS belongs to the system).
class KeyboardDelegate extends WatchUi.BehaviorDelegate {
    private var view as KeyboardView;
    private var heldKey as Lang.Number or Null = null;
    private var holdTimer as Timer.Timer or Null = null;
    private var longDone as Lang.Boolean = false;

    function initialize(view as KeyboardView) {
        BehaviorDelegate.initialize();
        self.view = view;
    }

    private function isTimedKey(key as Lang.Number) as Lang.Boolean {
        return key == WatchUi.KEY_DOWN || key == WatchUi.KEY_ESC;
    }

    // These keys are handled on press/release, so they produce no behaviour.
    function onKey(evt as WatchUi.KeyEvent) as Lang.Boolean {
        if (isTimedKey(evt.getKey())) {
            return true;
        }
        return BehaviorDelegate.onKey(evt);
    }

    function onKeyPressed(evt as WatchUi.KeyEvent) as Lang.Boolean {
        var key = evt.getKey();
        if (!isTimedKey(key)) {
            return false;
        }
        stopHoldTimer();
        heldKey = key;
        longDone = false;
        var timer = new Timer.Timer();
        timer.start(method(:onKeyHeld), keyboardLongPressMs, false);
        holdTimer = timer;
        return true;
    }

    function onKeyReleased(evt as WatchUi.KeyEvent) as Lang.Boolean {
        var key = evt.getKey();
        if (heldKey == null || key != heldKey) {
            return isTimedKey(key);
        }
        stopHoldTimer();
        heldKey = null;
        if (longDone) {
            return true;
        }
        if (key == WatchUi.KEY_DOWN) {
            view.move(1);
        } else {
            view.back();
        }
        return true;
    }

    function onKeyHeld() as Void {
        holdTimer = null;
        var key = heldKey;
        if (key == null) {
            return;
        }
        longDone = true;
        if (key == WatchUi.KEY_DOWN) {
            view.move(3);
        } else {
            view.backLong();
        }
    }

    private function stopHoldTimer() as Void {
        var timer = holdTimer;
        if (timer != null) {
            timer.stop();
            holdTimer = null;
        }
    }

    function onNextPage() as Lang.Boolean {
        view.move(1);
        return true;
    }

    function onPreviousPage() as Lang.Boolean {
        view.move(-1);
        return true;
    }

    function onSelect() as Lang.Boolean {
        view.select();
        return true;
    }

    function onBack() as Lang.Boolean {
        view.back();
        return true;
    }

    function onMenu() as Lang.Boolean {
        view.requestExit();
        return true;
    }
}

}
