import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;

const L_MESSAGING as LogComponent = "messaging";

const QuickMessages_valueKey = quickMessagesSubject + valueKeySuffix;
const QuickMessagesField_list = "m";
const quickMessagesMaxCount = 20;
const quickMessageMaxLength = 160;

// Contact actions (call, quick message, write message), quick message list,
// confirmation and sending of text messages through the phone.
module Messaging {

// The list (favourites or recents) the contact was picked from: we return there once a message is sent.
var returnViewTag as VT.ViewTag = V_phones;

function openContactActionsView(phone as Phone) as Void {
    returnViewTag = VT.topViewStackEntry().tag;
    VT.pushView(V_contactActions, new ContactActionsView(phone), new ContactActionsDelegate(phone), WatchUi.SLIDE_LEFT);
}

function quickMessages() as Lang.Array<Lang.String> {
    var stored = Storage.getValue(QuickMessages_valueKey) as Lang.Dictionary<Lang.String, Lang.Object> or Null;
    if (stored == null) {
        return [] as Lang.Array<Lang.String>;
    }
    var list = stored[QuickMessagesField_list];
    var messages = [] as Lang.Array<Lang.String>;
    if (!(list instanceof Lang.Array)) {
        return messages;
    }
    // Defensive: accept only short strings, and not too many of them.
    var items = list as Lang.Array;
    for (var i = 0; i < items.size() && messages.size() < quickMessagesMaxCount; i++) {
        var item = items[i];
        if (item instanceof Lang.String) {
            var text = item as Lang.String;
            if (text.length() > quickMessageMaxLength) {
                text = text.substring(0, quickMessageMaxLength) as Lang.String;
            }
            messages.add(text);
        }
    }
    return messages;
}

(:noReadiness)
function preflightMessages() as Lang.Boolean {
    return true;
}

(:readiness)
function preflightMessages() as Lang.Boolean {
    var readiness = ReadinessInfoManip.readiness(ReadinessField_messages) as Lang.String or Null;
    if (readiness == null) {
        // The phone app predates messaging: let the request go through.
        return true;
    }
    if (readiness.equals(ReadinessValue_ready)) {
        return true;
    }
    return Req.preflightReadiness(ReadinessField_messages, Rez.Strings.readinessMessages);
}

// Shows the confirmation screen; GPS there sends the message.
// [quickIndex] identifies a quick message: the phone then sends its full text (with emojis).
function confirmAndSend(phone as Phone, text as Lang.String, quickIndex as Lang.Number or Null) as Void {
    VT.pushView(V_confirmMessage, new ConfirmMessageView(phone, text), new ConfirmMessageDelegate(phone, text, quickIndex), WatchUi.SLIDE_LEFT);
}

// Leaves the message screens for the list the contact came from, shows the status screen and sends.
function sendMessage(phone as Phone, text as Lang.String, quickIndex as Lang.Number or Null) as Void {
    var statusView = new MessageStatusView();
    var parentTag = returnViewTag;
    if (VT.viewStackEntryWithTag(parentTag) == null) {
        parentTag = V_contactActions;
    }
    VT.popToViewAndPushView(parentTag, V_messageStatus, statusView, new MessageStatusDelegate(), WatchUi.SLIDE_LEFT);

    var number = getPhoneNumber(phone);
    if (number == null) {
        statusView.setState(MESSAGE_FAILED);
        return;
    }
    if (debug) { _3(L_MESSAGING, "send", number); }
    var msg = {
        cmdK => Cmd_sendSms,
        SmsArgsK_number => number,
        SmsArgsK_text => text
    } as Lang.Dictionary<Communications.TransmitKeyType, Communications.TransmitType>;
    if (quickIndex != null) {
        msg[SmsArgsK_quickIndex] = quickIndex;
    }
    Req.transmitWithRetry("sms", msg, new SendMessageListener(statusView));
}

class SendMessageListener extends Communications.ConnectionListener {
    private var statusView as MessageStatusView;

    function initialize(statusView as MessageStatusView) {
        ConnectionListener.initialize();
        self.statusView = statusView;
    }

    function onComplete() as Void {
        if (debug) { _2(L_MESSAGING, "sent"); }
        statusView.setState(MESSAGE_SENT);
    }

    function onError() as Void {
        if (debug) { _2(L_MESSAGING, "failed"); }
        statusView.setState(MESSAGE_FAILED);
    }
}

// MARK: Contact actions

class ContactActionsView extends WatchUi.Menu2 {
    function initialize(phone as Phone) {
        Menu2.initialize({ :title => getPhoneName(phone) });
        addItem(new WatchUi.MenuItem(Rez.Strings.actionCall, getPhoneNumber(phone), :call, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.actionQuickMessage, null, :quick, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.actionWriteMessage, null, :write, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.actionSendLocation, null, :location, null));
    }
}

class ContactActionsDelegate extends WatchUi.Menu2InputDelegate {
    private var phone as Phone;

    function initialize(phone as Phone) {
        Menu2InputDelegate.initialize();
        self.phone = phone;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :call) {
            // Leave the actions so that the call returns to the list it was started from.
            VT.popView(WatchUi.SLIDE_IMMEDIATE);
            Req.scheduleCall(phone);
            return;
        }
        if (!preflightMessages()) {
            return;
        }
        if (id == :quick) {
            VT.pushView(V_quickMessages, new QuickMessagesView(), new QuickMessagesDelegate(phone), WatchUi.SLIDE_LEFT);
        } else if (id == :write) {
            var keyboard = new KeyboardView(phone);
            VT.pushView(V_keyboard, keyboard, new KeyboardDelegate(keyboard), WatchUi.SLIDE_LEFT);
        } else if (id == :location) {
            openSendLocation(phone);
        }
    }

    function onBack() as Void {
        VT.popView(WatchUi.SLIDE_RIGHT);
    }
}

// MARK: Quick messages

class QuickMessagesView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({ :title => Rez.Strings.actionQuickMessage });
        var messages = quickMessages();
        if (messages.size() == 0) {
            addItem(new WatchUi.MenuItem(Rez.Strings.noQuickMessages, Rez.Strings.noQuickMessagesHint, :none, null));
            return;
        }
        for (var i = 0; i < messages.size(); i++) {
            addItem(new WatchUi.MenuItem(messages[i], null, i, null));
        }
    }
}

class QuickMessagesDelegate extends WatchUi.Menu2InputDelegate {
    private var phone as Phone;

    function initialize(phone as Phone) {
        Menu2InputDelegate.initialize();
        self.phone = phone;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (!(id instanceof Lang.Number)) {
            return;
        }
        var messages = quickMessages();
        var index = id as Lang.Number;
        if (index >= messages.size()) {
            return;
        }
        confirmAndSend(phone, messages[index], index);
    }

    function onBack() as Void {
        VT.popView(WatchUi.SLIDE_RIGHT);
    }
}

}
