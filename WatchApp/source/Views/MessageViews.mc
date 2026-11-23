import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

module Messaging {

enum MessageState {
    MESSAGE_SENDING,
    MESSAGE_SENT,
    MESSAGE_FAILED
}

const messageSentDisplayMs = 1500;

// Designed for 176x176 (Instinct 3); y values are scaled for other screens.
// On the Instinct the sub-window takes the top right corner (x >= 113, y <= 62).
function scaledY(value as Lang.Number, h as Lang.Number) as Lang.Number {
    return value * h / 176;
}

// MARK: Confirmation

class ConfirmMessageView extends WatchUi.View {
    private var phone as Phone;
    private var text as Lang.String;

    function initialize(phone as Phone, text as Lang.String) {
        View.initialize();
        self.phone = phone;
        self.text = text;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Question, left of the sub-window.
        var title = Lang.format(loadIfResource(Rez.Strings.messageConfirmFormat), [getPhoneName(phone)]);
        var titleArea = Graphics.fitTextToArea(title, Graphics.FONT_XTINY, w * 100 / 176, scaledY(40, h), true);
        dc.drawText(w * 60 / 176, scaledY(38, h), Graphics.FONT_XTINY, titleArea, center);

        // Message body.
        dc.drawLine(14, scaledY(66, h), w - 14, scaledY(66, h));
        var body = Graphics.fitTextToArea(text, Graphics.FONT_SMALL, w - 24, scaledY(76, h), true);
        dc.drawText(cx, scaledY(106, h), Graphics.FONT_SMALL, body, center);
        dc.drawLine(14, scaledY(146, h), w - 14, scaledY(146, h));

        dc.drawText(cx, scaledY(160, h), Graphics.FONT_XTINY, loadIfResource(Rez.Strings.messageConfirmHint), center);
    }
}

class ConfirmMessageDelegate extends WatchUi.BehaviorDelegate {
    private var phone as Phone;
    private var text as Lang.String;

    function initialize(phone as Phone, text as Lang.String) {
        BehaviorDelegate.initialize();
        self.phone = phone;
        self.text = text;
    }

    function onSelect() as Lang.Boolean {
        sendMessage(phone, text);
        return true;
    }

    function onBack() as Lang.Boolean {
        VT.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// MARK: Status ("A enviar...", "SMS enviada", "Falha no envio")

class MessageStatusView extends WatchUi.View {
    private var state as MessageState = MESSAGE_SENDING;
    private var timer as Timer.Timer or Null;

    function initialize() {
        View.initialize();
    }

    function setState(newState as MessageState) as Void {
        state = newState;
        WatchUi.requestUpdate();
        if (newState == MESSAGE_SENT) {
            var t = new Timer.Timer();
            t.start(method(:leave), messageSentDisplayMs, false);
            timer = t;
        }
    }

    // Returns to the contact list, unless the user already left this screen.
    function leave() as Void {
        timer = null;
        if (VT.topView() == self) {
            VT.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    function onHide() as Void {
        var t = timer;
        if (t != null) {
            t.stop();
            timer = null;
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = scaledY(92, h);
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var message;
        switch (state) {
            case MESSAGE_SENT: {
                dc.setPenWidth(6);
                dc.drawLine(cx - 22, cy, cx - 6, cy + 16);
                dc.drawLine(cx - 6, cy + 16, cx + 24, cy - 16);
                dc.setPenWidth(1);
                message = Rez.Strings.messageSent;
                break;
            }
            case MESSAGE_FAILED: {
                dc.setPenWidth(6);
                dc.drawLine(cx - 18, cy - 18, cx + 18, cy + 18);
                dc.drawLine(cx - 18, cy + 18, cx + 18, cy - 18);
                dc.setPenWidth(1);
                message = Rez.Strings.messageFailed;
                dc.drawText(cx, scaledY(160, h), Graphics.FONT_XTINY, loadIfResource(Rez.Strings.messageFailedHint), center);
                break;
            }
            default: {
                dc.drawCircle(cx, cy, 20);
                message = Rez.Strings.messageSending;
                break;
            }
        }
        dc.drawText(cx, scaledY(132, h), Graphics.FONT_MEDIUM, loadIfResource(message), center);
    }
}

class MessageStatusDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        VT.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onSelect() as Lang.Boolean {
        VT.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

}
