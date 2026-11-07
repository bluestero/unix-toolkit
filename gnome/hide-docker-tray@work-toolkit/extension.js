// Docker Desktop on Linux registers a tray item with no icon and an empty menu: GNOME draws
// "..." and a click does nothing. This keeps tray items whose Id starts with a name in HIDE hidden.
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const HIDE = ['Docker Desktop'];

export default class HideDockerTray extends Extension {
    enable() {
        this._hidden = new Map();   // tray icon -> notify::visible handler id
        this._sync();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            try { this._sync(); } catch (e) { console.error(`hide-docker-tray: ${e}`); }
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._timer)
            GLib.source_remove(this._timer);
        this._timer = null;
        for (const [icon, id] of this._hidden) {
            try { icon.disconnect(id); icon.visible = true; } catch (e) { /* gone */ }
        }
        this._hidden = null;
    }

    _sync() {
        for (const [role, icon] of Object.entries(Main.panel.statusArea)) {
            if (!role.startsWith('appindicator-'))
                continue;
            try {
                if (!icon.get_stage() || !HIDE.some(p => (icon._indicator?.id ?? '').startsWith(p)))
                    continue;
                if (!this._hidden.has(icon)) {
                    this._hidden.set(icon, icon.connect('notify::visible', () => {
                        if (icon.visible)
                            icon.visible = false;
                    }));
                }
                icon.visible = false;
            } catch (e) { /* stale icon, already destroyed */ }
        }
    }
}
