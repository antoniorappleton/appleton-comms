import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module Messaging {

// Keyboard by letter groups, ordered by letter frequency in Portuguese (from AppletonSMS).
// Level 1: groups. Level 2: characters of the chosen group.
// UP/DOWN move (wrapping around), GPS/START selects.
// BACK: level 2 -> level 1; level 1 -> deletes the last character; empty text -> leaves.
// Hold UP (menu): leaves the keyboard; asks "Descartar?" if there is text.
// "Concluir" opens the confirmation screen; after sending, the app returns to the contact list.
class KeyboardView extends WatchUi.View {

    // Characters of each group, upper case (the case is decided on insertion).
    // "Apagar" and "Concluir" have no characters.
    const GROUPS = [" ", "AEO", "SRIN", "DMUT", "CLPV", "GQBFH", "JZXKWY", ".,?!", "0123456789", "", ""] as Lang.Array<Lang.String>;

    // Level 1 labels (same order as GROUPS). No special symbols: the font may lack them.
    const LABELS = ["Espaco", "A E O", "S R I N", "D M U T", "C L P V", "G Q B F H", "J Z X K W Y",
                    ". , ? !", "0-9", "Apagar", "Concluir"] as Lang.Array<Lang.String>;

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

    function initialize(phone as Phone or Null) {
        View.initialize();
        self.phone = phone;
        maxLen = phone == null ? SEARCH_MAX_LEN : MESSAGE_MAX_LEN;
        if (phone == null) {
            group = G_FIRST_LETTER; // searching starts with a letter, not a space
        }
    }

    // MARK: Actions (from KeyboardDelegate)

    function move(step as Lang.Number) as Void {
        if (mode == MODE_GROUPS) {
            group = wrap(group + step, LABELS.size());
        } else if (mode == MODE_CHARS) {
            char = wrap(char + step, GROUPS[group].length());
        } else {
            return;
        }
        WatchUi.requestUpdate();
    }

    function select() as Void {
        if (mode == MODE_DISCARD) {
            leave();
            return;
        }
        if (mode == MODE_CHARS) {
            addChar(GROUPS[group].substring(char, char + 1) as Lang.String);
            mode = MODE_GROUPS;
        } else if (group == G_DELETE) {
            deleteLast();
        } else if (group == G_DONE) {
            finish();
        } else if (GROUPS[group].length() == 1) {
            addChar(GROUPS[group]);
        } else {
            mode = MODE_CHARS;
            char = 0;
        }
        WatchUi.requestUpdate();
    }

    function back() as Void {
        if (mode != MODE_GROUPS) {
            mode = MODE_GROUPS;
        } else if (text.length() > 0) {
            deleteLast();
        } else {
            leave();
            return;
        }
        WatchUi.requestUpdate();
    }

    function requestExit() as Void {
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

    // MARK: Text rules

    private function addChar(ch as Lang.String) as Void {
        var n = text.length();
        // Leading or double space: ignored.
        if (ch.equals(" ") && (n == 0 || (text.substring(n - 1, n) as Lang.String).equals(" "))) {
            return;
        }
        if (n >= maxLen) {
            buzz();
            return;
        }
        text += applyCase(ch);
    }

    private function deleteLast() as Void {
        var n = text.length();
        if (n == 0) {
            buzz();
            return;
        }
        text = text.substring(0, n - 1) as Lang.String;
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
        return mode == MODE_CHARS ? GROUPS[group].length() : LABELS.size();
    }

    private function itemText(index as Lang.Number) as Lang.String {
        if (mode == MODE_CHARS) {
            return applyCase(GROUPS[group].substring(index, index + 1) as Lang.String);
        }
        if (index >= G_FIRST_LETTER && index <= G_LAST_LETTER) {
            return applyCase(LABELS[index]);
        }
        return LABELS[index];
    }

    private function focusIndex() as Lang.Number {
        return mode == MODE_CHARS ? char : group;
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

        // Recipient (or "Pesquisar"), left of the sub-window.
        var recipient = phone;
        var title = recipient == null ? loadIfResource(Rez.Strings.searchContacts) : getPhoneName(recipient);
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

        // Footer: counter.
        dc.drawText(cx, y(164, h), Graphics.FONT_XTINY, n.toString() + "/" + maxLen.toString(), center);
    }

    private function y(value as Lang.Number, h as Lang.Number) as Lang.Number {
        return value * h / 176;
    }
}

class KeyboardDelegate extends WatchUi.BehaviorDelegate {
    private var view as KeyboardView;

    function initialize(view as KeyboardView) {
        BehaviorDelegate.initialize();
        self.view = view;
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
