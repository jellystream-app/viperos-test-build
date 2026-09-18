/* ViperOS - schwebende Topbar mit runden Ecken
 *
 * Zwei Dinge, die vorher falsch waren:
 *
 * 1. Die Rundung hing an einer CSS-Klasse (#panel.viperos-floating).
 *    Sie hat nicht gegriffen - die Ecken blieben spitz. Statt den Fehler
 *    im Selektor zu suchen, wird der Stil jetzt direkt am Actor gesetzt
 *    (set_style). Ein Inline-Stil hat in St die hoechste Prioritaet und
 *    kann von keiner Themenregel ueberschrieben werden.
 *
 * 2. Die Leiste wurde verschoben, ohne die Arbeitsflaeche neu zu
 *    berechnen. GNOME leitet aus der Position der panelBox ab, wo der
 *    nutzbare Bereich beginnt; ohne Neuberechnung legt "Desktop Icons"
 *    seine Symbole weiterhin ganz oben ab - sie lagen dann unter der
 *    Leiste. Deshalb wird nach dem Verschieben die Regionsberechnung
 *    angestossen.
 */

import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const MARGIN_SIDE = 10;   // Abstand links und rechts
const MARGIN_TOP = 6;     // Abstand nach oben
const RADIUS = 16;        // Eckenradius

const PANEL_STYLE = `
    border-radius: ${RADIUS}px;
    border: 1px solid rgba(106, 143, 216, 0.22);
    background-color: rgba(18, 21, 31, 0.88);
`;

export default class ViperPanelExtension {
    enable() {
        this._panelBox = Main.layoutManager.panelBox;
        this._timeoutId = 0;

        this._origX = this._panelBox.x;
        this._origY = this._panelBox.y;
        this._origWidth = this._panelBox.width;
        this._origStyle = Main.panel.get_style();

        // Die Shell setzt Position und Groesse neu, sobald sich die
        // Bildschirmgeometrie oder der Sitzungsmodus aendert.
        this._monitorsId = Main.layoutManager.connect(
            'monitors-changed', () => this._apply());
        this._sessionId = Main.sessionMode.connect(
            'updated', () => this._apply());

        this._apply();
    }

    _apply() {
        if (this._timeoutId)
            GLib.source_remove(this._timeoutId);

        // Kurz warten, bis die Shell ihre eigene Positionierung beendet hat.
        this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
            this._timeoutId = 0;
            this._position();
            return GLib.SOURCE_REMOVE;
        });
    }

    _position() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !this._panelBox)
            return;

        let scale = 1;
        try {
            scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        } catch (e) {
            // Ohne Skalierungsfaktor mit 1 weiterarbeiten.
        }

        const side = MARGIN_SIDE * scale;
        const top = MARGIN_TOP * scale;

        this._panelBox.set_position(monitor.x + side, monitor.y + top);
        this._panelBox.set_width(monitor.width - side * 2);

        // Rundung direkt am Actor - unabhaengig von jedem CSS-Selektor.
        Main.panel.set_style(PANEL_STYLE);

        // Arbeitsflaeche neu berechnen, damit Fenster und Schreibtisch-
        // symbole unterhalb der Leiste beginnen statt darunter zu liegen.
        this._updateRegions();
    }

    _updateRegions() {
        const lm = Main.layoutManager;
        // Je nach Shell-Version heisst die Methode anders; die erste
        // vorhandene wird benutzt. Schlaegt alles fehl, bleibt nur die
        // Ueberlappung - die Shell laeuft weiter.
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

        Main.panel.set_style(this._origStyle ?? null);

        if (this._panelBox) {
            this._panelBox.set_position(this._origX, this._origY);
            this._panelBox.set_width(this._origWidth);
            this._panelBox = null;
        }

        this._updateRegions();
    }
}
