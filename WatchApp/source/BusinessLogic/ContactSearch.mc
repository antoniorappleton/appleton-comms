import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

const searchResultsMaxCount = 10;
const searchResultTimeoutMs = 15000;
const searchFieldMaxLength = 40;

// Searching all the phone's contacts: the watch sends the typed text, the phone searches its
// contacts and answers with up to 10 matches. Nothing is stored on the watch.
module Messaging {

// The list the search was opened from; the results replace the keyboard on top of it.
var searchParentTag as VT.ViewTag = V_phones;
var searchQuery as Lang.String or Null = null;
var searchResultsView as SearchResultsView or Null = null;

function openSearch() as Void {
    searchParentTag = VT.topViewStackEntry().tag;
    var keyboard = new KeyboardView(null);
    VT.pushView(V_keyboard, keyboard, new KeyboardDelegate(keyboard), WatchUi.SLIDE_LEFT);
}

function startSearch(query as Lang.String) as Void {
    endSearch(); // a retry replaces the previous search
    var view = new SearchResultsView(query);
    searchQuery = query;
    searchResultsView = view;
    var parentTag = searchParentTag;
    if (VT.viewStackEntryWithTag(parentTag) == null) {
        parentTag = V_phones;
    }
    VT.popToViewAndPushView(parentTag, V_searchResults, view, new SearchResultsDelegate(), WatchUi.SLIDE_LEFT);
    view.startTimeout();
    var msg = {
        cmdK => Cmd_searchContacts,
        SearchArgsK_query => query
    } as Lang.Dictionary<Communications.TransmitKeyType, Communications.TransmitType>;
    Req.transmitWithRetry("search", msg, new SearchListener(query));
}

function endSearch() as Void {
    var view = searchResultsView;
    if (view != null) {
        view.stopTimeout();
    }
    searchQuery = null;
    searchResultsView = null;
}

function isCurrentSearch(query as Lang.Object or Null) as Lang.Boolean {
    var current = searchQuery;
    return current != null && query instanceof Lang.String && current.equals(query);
}

// Results from the phone. Defensive: only results for the search on screen, only short strings.
function handleSearchResults(args as Lang.Object or Null) as Void {
    if (!(args instanceof Lang.Dictionary)) {
        return;
    }
    var dict = args as Lang.Dictionary;
    var view = searchResultsView;
    if (view == null || !isCurrentSearch(dict[SearchResultsArgs_query] as Lang.Object or Null)) {
        if (debug) { _2(L_MESSAGING, "staleSearchResults"); }
        return;
    }
    if (dict[SearchResultsArgs_error] != null) {
        view.showMessage(Rez.Strings.searchNoAccess, Rez.Strings.searchNoAccessHint, :noAccess);
        return;
    }
    var phones = [] as PhoneList;
    var list = dict[SearchResultsArgs_list];
    if (list instanceof Lang.Array) {
        var items = list as Lang.Array;
        for (var i = 0; i < items.size() && phones.size() < searchResultsMaxCount; i++) {
            var phone = validatedPhone(items[i] as Lang.Object or Null);
            if (phone != null) {
                phones.add(phone);
            }
        }
    }
    view.showPhones(phones);
}

function validatedPhone(item as Lang.Object or Null) as Phone or Null {
    if (!(item instanceof Lang.Dictionary)) {
        return null;
    }
    var dict = item as Lang.Dictionary;
    var name = dict[PhoneField_name];
    var number = dict[PhoneField_number];
    if (!(name instanceof Lang.String) || !(number instanceof Lang.String)) {
        return null;
    }
    var phone = {
        PhoneField_name => truncated(name as Lang.String),
        PhoneField_number => truncated(number as Lang.String)
    } as Phone;
    var id = dict[PhoneField_id];
    if (id instanceof Lang.Number) {
        phone[PhoneField_id] = id;
    }
    return phone;
}

function truncated(text as Lang.String) as Lang.String {
    if (text.length() > searchFieldMaxLength) {
        return text.substring(0, searchFieldMaxLength) as Lang.String;
    }
    return text;
}

class SearchListener extends Communications.ConnectionListener {
    private var query as Lang.String;

    function initialize(query as Lang.String) {
        ConnectionListener.initialize();
        self.query = query;
    }

    function onComplete() as Void {
        // The results come in a separate message from the phone.
    }

    function onError() as Void {
        var view = searchResultsView;
        if (view != null && isCurrentSearch(query)) {
            view.showMessage(Rez.Strings.searchFailed, Rez.Strings.searchRetryHint, :retry);
        }
    }
}

class SearchResultsView extends ExtendedMenu2 {
    private var timer as Timer.Timer or Null;
    private var waiting as Lang.Boolean = true;

    function initialize(query as Lang.String) {
        ExtendedMenu2.initialize();
        setTitle(query);
        addItem(new WatchUi.MenuItem(Rez.Strings.searchSearching, null, :searching, null));
    }

    function startTimeout() as Void {
        var t = new Timer.Timer();
        t.start(method(:timedOut), searchResultTimeoutMs, false);
        timer = t;
    }

    function stopTimeout() as Void {
        var t = timer;
        if (t != null) {
            t.stop();
            timer = null;
        }
    }

    function timedOut() as Void {
        timer = null;
        if (waiting) {
            showMessage(Rez.Strings.searchFailed, Rez.Strings.searchRetryHint, :retry);
        }
    }

    function showPhones(phones as PhoneList) as Void {
        if (phones.size() == 0) {
            showMessage(Rez.Strings.searchNoResults, null, :none);
            return;
        }
        waiting = false;
        stopTimeout();
        beginUpdate();
        deleteAllItems();
        for (var i = 0; i < phones.size(); i++) {
            var phone = phones[i];
            addItem(new WatchUi.MenuItem(getPhoneName(phone), getPhoneNumber(phone), phone, null));
        }
        endUpdate();
        setFocus(0);
        WatchUi.requestUpdate();
    }

    function showMessage(label as Lang.ResourceId or Lang.String, subLabel as Lang.ResourceId or Lang.String or Null, id as Lang.Symbol) as Void {
        waiting = false;
        stopTimeout();
        beginUpdate();
        deleteAllItems();
        addItem(new WatchUi.MenuItem(label, subLabel, id, null));
        endUpdate();
        WatchUi.requestUpdate();
    }
}

class SearchResultsDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Lang.Dictionary) {
            openContactActionsView(id as Phone);
            return;
        }
        if (id == :retry) {
            var query = searchQuery;
            if (query != null) {
                startSearch(query);
            }
        }
    }

    function onBack() as Void {
        endSearch();
        VT.popView(WatchUi.SLIDE_RIGHT);
    }
}

}
