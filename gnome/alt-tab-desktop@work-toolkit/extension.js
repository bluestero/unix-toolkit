// Alt+Tab normally selects the 2nd window in its list, because the 1st is the one
// you are on. After "show desktop" nothing is focused, so the 1st window is the one
// you just minimized: select that one instead.
import Meta from 'gi://Meta';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as AltTab from 'resource:///org/gnome/shell/ui/altTab.js';

export default class AltTabDesktop extends Extension {
    enable() {
        const proto = AltTab.WindowSwitcherPopup.prototype;
        this._own = Object.prototype.hasOwnProperty.call(proto, '_initialSelection');
        this._orig = proto._initialSelection;
        const orig = this._orig;
        proto._initialSelection = function (backward, binding) {
            const focus = global.display.focus_window;
            // Desktop icons (ding) are a focusable window on Wayland: anything the
            // switcher does not list (desktop, skip-taskbar) counts as "nothing focused".
            const nothingFocused = !focus || focus.get_window_type() === Meta.WindowType.DESKTOP ||
                !this._items.some(i => i.window === focus);
            if (!backward && nothingFocused && this._items.length > 0) {
                this._select(0);
                return;
            }
            orig.call(this, backward, binding);
        };
    }

    disable() {
        const proto = AltTab.WindowSwitcherPopup.prototype;
        if (this._own) proto._initialSelection = this._orig;
        else delete proto._initialSelection;
        this._orig = null;
    }
}
