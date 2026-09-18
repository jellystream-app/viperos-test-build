/* ViperOS - schwebende Topbar
 *
 * Warum eine Erweiterung noetig ist:
 * Die obere Leiste wird von GNOME selbst positioniert
 * (Main.layoutManager.panelBox). St, das Toolkit der Shell, wertet an
 * #panel WEDER margin NOCH eine Verschiebung per CSS aus - beides wird
 * stillschweigend verworfen. Ein "margin: 6px 8px" im Stylesheet bleibt
 * deshalb wirkungslos, die Leiste klebt am Rand, und ein border-radius
 * ist an einer randlosen Leiste nicht zu sehen: sie wirkt steif und eckig.
 *
 * Diese Erweiterung verschiebt die panelBox per JavaScript und verkleinert
 * sie um den doppelten Randabstand. Erst dadurch werden die abgerundeten
 * Ecken sichtbar.
 *
 * Beim Deaktivieren wird alles zurueckgesetzt.
 */

import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const MARGIN_SIDE = 10;   // Abstand links und rechts
const MARGIN_TOP  = 6;    // Abstand nach oben

export default class ViperPanelExtension {
    enable() {
        this._panelBox = Main.layoutManager.panelBox;
        this._timeoutId = 0;

        // Ausgangswerte merken, um sie beim Abschalten wiederherzustellen.
        this._origX = this._panelBox.x;
        this._origY = this._panelBox.y;
        this._origWidth = this._panelBox.width;

        // Die Shell setzt die Position bei jeder Aenderung der
        // Bildschirmgeometrie neu - also erneut anwenden, wenn das passiert.
        this._monitorsId = Main.layoutManager.connect(
            'monitors-changed', () => this._apply());
        this._sessionId = Main.sessionMode.connect(
            'updated', () => this._apply());

        // Marker fuer die CSS: nur wenn die Erweiterung laeuft, sollen die
        // abgerundeten Ecken gelten.
        Main.panel.add_style_class_name('viperos-floating');

        this._apply();
    }

    _apply() {
        // Verzoegern, bis die Shell ihre eigene Positionierung beendet hat.
        if (this._timeoutId)
            GLib.source_remove(this._timeoutId);

        this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 80, () => {
            this._timeoutId = 0;

            const monitor = Main.layoutManager.primaryMonitor;
            if (!monitor || !this._panelBox)
                return GLib.SOURCE_REMOVE;

            const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
            const side = MARGIN_SIDE * scale;
            const top = MARGIN_TOP * scale;

            this._panelBox.set_position(monitor.x + side, monitor.y + top);
            this._panelBox.set_width(monitor.width - (side * 2));

            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }

        if (this._monitorsId) {
            Main.layoutManager.disconnect(this._monitorsId);
            this._monitorsId = 0;
        }

        if (this._sessionId) {
            Main.sessionMode.disconnect(this._sessionId);
            this._sessionId = 0;
        }

        Main.panel.remove_style_class_name('viperos-floating');

        if (this._panelBox) {
            this._panelBox.set_position(this._origX, this._origY);
            this._panelBox.set_width(this._origWidth);
            this._panelBox = null;
        }
    }
}
