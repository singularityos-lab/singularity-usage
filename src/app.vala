using Gtk;

namespace Singularity.Apps.Usage {

    public class UsageApp : Singularity.Application {

        public UsageApp () {
            Object (application_id: "dev.sinty.usage", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("home", 0, OptionFlags.NONE, OptionArg.NONE, _("Scan your home folder"), null);
            add_main_option ("system", 0, OptionFlags.NONE, OptionArg.NONE, _("Scan the system drive"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            string? path = null;
            if (options.contains ("home")) path = Environment.get_home_dir ();
            if (options.contains ("system")) path = "/";
            if (path == null) return -1;
            try {
                register ();
            } catch (Error e) {
                return 1;
            }
            activate_action ("scan", new Variant.string (path));
            return get_is_remote () ? 0 : -1;
        }

        private UsageWindow ensure_window () {
            var window = get_active_window () as UsageWindow;
            if (window == null) window = new UsageWindow (this);
            window.present ();
            return window;
        }

        protected override void startup () {
            base.startup ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("Scan Home"), "win.scan-home");
            f1.append (_("Scan the System"), "win.scan-system");
            f1.append (_("Scan a Folder…"), "win.scan-folder");
            file_menu.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Show in Files"), "win.open-in-files");
            f2.append (_("Stop Scanning"), "win.stop");
            file_menu.append_section (null, f2);
            var f3 = new GLib.Menu ();
            f3.append (_("Close Window"), "win.close");
            f3.append (_("Quit"), "app.quit");
            file_menu.append_section (null, f3);
            menu.append_submenu (_("File"), file_menu);
            var edit_menu = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Copy Path"), "win.copy-path");
            edit_menu.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Settings"), "app.settings");
            edit_menu.append_section (null, e2);
            menu.append_submenu (_("Edit"), edit_menu);
            var view_menu = new GLib.Menu ();
            view_menu.append (_("Up One Folder"), "win.up");
            view_menu.append (_("Scan Again"), "win.rescan");
            menu.append_submenu (_("View"), view_menu);
            set_menubar (menu);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.usage");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            var scan_action = new SimpleAction ("scan", VariantType.STRING);
            scan_action.activate.connect ((param) => ensure_window ().scan_path (param.get_string ()));
            add_action (scan_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.scan-folder", { "<Control>o" });
            set_accels_for_action ("win.copy-path", { "<Control><Shift>c" });
            set_accels_for_action ("win.up", { "<Alt>Up" });
            set_accels_for_action ("win.rescan", { "<Control>r", "F5" });
            set_accels_for_action ("win.close", { "<Control>w" });
        }

        public override void activate () {
            ensure_window ();
        }

        public override void open (File[] files, string hint) {
            var window = ensure_window ();
            foreach (var file in files) {
                string? path = file.get_path ();
                if (path != null && FileUtils.test (path, FileTest.IS_DIR)) {
                    window.scan_path (path);
                    break;
                }
            }
        }

        private const string CSS = """
.usage-list {
    background: transparent;
}

.usage-list > row {
    border-radius: 12px;
    margin-bottom: 2px;
}

.usage-list > row:hover {
    background-color: alpha(@window_fg_color, 0.05);
}

levelbar.usage-share trough,
levelbar.usage-meter trough {
    min-height: 5px;
    border-radius: 99px;
    background-color: alpha(@window_fg_color, 0.1);
    border: none;
    padding: 0;
}

levelbar.usage-share block.filled,
levelbar.usage-meter block.filled {
    min-height: 5px;
    border-radius: 99px;
    background-color: @accent_color;
}

levelbar.usage-meter block.empty,
levelbar.usage-share block.empty {
    background-color: transparent;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-usage", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-usage", "UTF-8");
        Intl.textdomain ("singularity-usage");
        return new UsageApp ().run (args);
    }
}
