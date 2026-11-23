import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

const locationTimeoutMs = 60000;
const locationMaxAgeS = 120;

// "Enviar localização": gets a GPS position on the watch and sends an SMS with a Google Maps link.
module Messaging {

function openSendLocation(phone as Phone) as Void {
    var view = new LocationView(phone);
    VT.pushView(V_location, view, new LocationDelegate(), WatchUi.SLIDE_LEFT);
}

// "Estou aqui: https://maps.google.com/?q=38.72230,-9.13930"
function locationMessage(location as Position.Location) as Lang.String {
    var degrees = location.toDegrees();
    var lat = (degrees[0] as Lang.Double).format("%.5f");
    var lon = (degrees[1] as Lang.Double).format("%.5f");
    return loadIfResource(Rez.Strings.locationMessagePrefix) + " https://maps.google.com/?q=" + lat + "," + lon;
}

class LocationView extends WatchUi.View {
    private var phone as Phone;
    private var timer as Timer.Timer or Null;
    private var listening as Lang.Boolean = false;
    private var failed as Lang.Boolean = false;
    // Best position so far, used if the timeout comes before a good one.
    private var best as Position.Info or Null;

    function initialize(phone as Phone) {
        View.initialize();
        self.phone = phone;
    }

    function onShow() as Void {
        if (failed || listening) {
            return;
        }
        // A recent good position (e.g. from an activity) is used straight away.
        // (Finished from a timer: the view can't be replaced while it is being shown.)
        var info = Position.getInfo();
        if (isGood(info) && isRecent(info)) {
            best = info;
            var shortTimer = new Timer.Timer();
            shortTimer.start(method(:useBest), 100, false);
            timer = shortTimer;
            return;
        }
        listening = true;
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        var t = new Timer.Timer();
        t.start(method(:timedOut), locationTimeoutMs, false);
        timer = t;
    }

    function onHide() as Void {
        stop();
    }

    private function stop() as Void {
        if (listening) {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
            listening = false;
        }
        var t = timer;
        if (t != null) {
            t.stop();
            timer = null;
        }
    }

    function onPosition(info as Position.Info) as Void {
        if (!listening) {
            return;
        }
        if (info.position != null && (best == null || info.accuracy >= (best as Position.Info).accuracy)) {
            best = info;
        }
        if (isGood(info)) {
            done(info);
        }
    }

    function useBest() as Void {
        timer = null;
        var b = best;
        if (b != null) {
            done(b);
        }
    }

    function timedOut() as Void {
        timer = null;
        var b = best;
        if (b != null && b.accuracy >= Position.QUALITY_POOR) {
            done(b);
            return;
        }
        stop();
        failed = true;
        WatchUi.requestUpdate();
    }

    private function isGood(info as Position.Info) as Lang.Boolean {
        return info.position != null && info.accuracy >= Position.QUALITY_USABLE;
    }

    private function isRecent(info as Position.Info) as Lang.Boolean {
        var when = info.when;
        return when != null && Time.now().subtract(when).value() <= locationMaxAgeS;
    }

    private function done(info as Position.Info) as Void {
        stop();
        var location = info.position as Position.Location;
        // The location screen is replaced by the usual confirmation.
        VT.popView(WatchUi.SLIDE_IMMEDIATE);
        confirmAndSend(phone, locationMessage(location), null);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = scaledY(92, h);
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Map pin.
        dc.setPenWidth(4);
        dc.drawCircle(cx, cy - 8, 12);
        dc.drawLine(cx - 10, cy, cx, cy + 20);
        dc.drawLine(cx + 10, cy, cx, cy + 20);
        dc.setPenWidth(1);

        if (failed) {
            dc.drawText(cx, scaledY(132, h), Graphics.FONT_MEDIUM, loadIfResource(Rez.Strings.locationFailed), center);
            dc.drawText(cx, scaledY(160, h), Graphics.FONT_XTINY, loadIfResource(Rez.Strings.locationFailedHint), center);
        } else {
            dc.drawText(cx, scaledY(132, h), Graphics.FONT_SMALL, loadIfResource(Rez.Strings.locationSearching), center);
            dc.drawText(cx, scaledY(160, h), Graphics.FONT_XTINY, loadIfResource(Rez.Strings.locationSearchingHint), center);
        }
    }
}

class LocationDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Lang.Boolean {
        VT.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

}
