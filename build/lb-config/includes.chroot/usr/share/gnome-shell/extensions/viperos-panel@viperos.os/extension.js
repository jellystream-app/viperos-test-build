/* ViperOS - Desktop-Icons unter der Topbar platzieren
 *
 * Diese Extension aendert NICHT das Aussehen der Leiste (kein Floating,
 * kein Inline-Style). Das visuelle Styling uebernimmt komplett die CSS-
 * Datei viperos-overrides.css.
 *
 * Einzige Aufgabe: nach dem Laden die Arbeitsflaechen-Regionen neu
 * berechnen, damit "Desktop Icons" seine Symbole UNTERHALB der Leiste
 * platziert statt darunter zu verschwinden.
 */

import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export default class ViperPanelExtension {
    enable() {
        this._timeoutId = 0;

        // Auf Monitor- und Sessionaenderungen reagieren
        this._monitorsId = Main.layoutManager.connect(
            'monitors-changed', () => this._scheduleUpdate());
        this._sessionId = Main.sessionMode.connect(
            'updated', () => this._scheduleUpdate());

        this._scheduleUpdate();
    }

    _scheduleUpdate() {
        if (this._timeoutId)
            GLib.source_remove(this._timeoutId);

        // Kurz warten, bis die Shell ihre eigene Positionierung beendet hat.
        this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            this._timeoutId = 0;
            this._updateRegions();
            return GLib.SOURCE_REMOVE;
        });
    }

    _updateRegions() {
        const lm = Main.layoutManager;
        for (const name of ['_queueUpdateRegions', '_updateRegions',
                            'queueUpdateRegions']) {
            if (typeof lm[name] === 'function') {
                try {
                    lm[name]();
                    return;
                } catch (e) {
                    // naechste Variante versuchen
                }
            }
        }
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

        this._updateRegions();
    }
}
