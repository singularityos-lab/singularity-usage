using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Usage {

    public class Location : Object {
        public string path;
        public string label;
        public string icon;
        public uint64 total;
        public uint64 free;

        public Location (string path, string label, string icon) {
            this.path = path;
            this.label = label;
            this.icon = icon;
            try {
                var info = File.new_for_path (path).query_filesystem_info ("filesystem::size,filesystem::free", null);
                total = info.get_attribute_uint64 (FileAttribute.FILESYSTEM_SIZE);
                free = info.get_attribute_uint64 (FileAttribute.FILESYSTEM_FREE);
            } catch (Error e) {
            }
        }
    }

    public class UsageWindow : Singularity.Widgets.Window {
        private UsageApp app;
        private AppSidebar sidebar;
        private Gee.ArrayList<Location> locations = new Gee.ArrayList<Location> ();
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow> ();
        private Stack stack;
        private WelcomePage start_page;
        private StatusPage scanning_page;
        private ProgressBar scan_bar;
        private Label scan_detail;
        private RingChart chart;
        private ListBox list;
        private Label list_title;
        private Label hover_label;
        private Button path_bubble;
        private Button up_bubble;
        private Button rescan_bubble;
        private DiskScanner? scanner = null;
        private Node? tree = null;
        private Node? current = null;
        private Location? location = null;

        public UsageWindow (UsageApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1100, 740);
            set_title (_("Disk Usage"));

            sidebar = new AppSidebar (240);
            set_sidebar (sidebar);
            set_sidebar_visible (true);
            load_locations ();

            up_bubble = add_bubble_icon ("go-up-symbolic", _("Up One Folder"), () => {
                if (current != null && current.parent != null) show_node (current.parent);
            });
            path_bubble = new Button.with_label ("");
            path_bubble.add_css_class ("flat");
            path_bubble.tooltip_text = _("Open in Files");
            path_bubble.clicked.connect (() => {
                if (current != null) open_in_files (current);
            });
            add_bubble_widget (path_bubble);
            rescan_bubble = add_bubble_icon ("view-refresh-symbolic", _("Scan Again"), () => {
                if (location != null) start_scan (location);
            });
            add_bubble_icon ("folder-open-symbolic", _("Scan a Folder"), () => choose_folder ());

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            start_page = new WelcomePage ();
            start_page.app_icon_name = "dev.sinty.usage";
            start_page.title = _("Disk Usage");
            start_page.subtitle = _("See what takes up space on your drives and in your folders.");
            start_page.add_action ("user-home", _("Scan Home"), _("Your personal files and folders"), () => start_scan (new Location (Environment.get_home_dir (), _("Home"), "user-home-symbolic")));
            start_page.add_action ("drive-harddisk-system", _("Scan the System"), _("Everything on the system drive"), () => start_scan (new Location ("/", _("System"), "drive-harddisk-system-symbolic")));
            start_page.add_action ("folder-open", _("Scan a Folder"), _("Pick any folder or drive"), () => choose_folder ());
            stack.add_named (start_page, "start");

            scanning_page = new StatusPage ();
            scanning_page.icon_name = "system-search";
            scanning_page.title = _("Scanning");
            var scan_box = new Box (Orientation.VERTICAL, 10);
            scan_box.halign = Align.CENTER;
            scan_box.set_size_request (360, -1);
            scan_bar = new ProgressBar ();
            scan_box.append (scan_bar);
            scan_detail = new Label ("");
            scan_detail.add_css_class ("dim-label");
            scan_detail.ellipsize = Pango.EllipsizeMode.MIDDLE;
            scan_detail.max_width_chars = 44;
            scan_box.append (scan_detail);
            var stop = new Button.with_label (_("Stop"));
            stop.add_css_class ("pill");
            stop.halign = Align.CENTER;
            stop.clicked.connect (() => {
                if (scanner != null) scanner.cancel ();
            });
            scan_box.append (stop);
            scanning_page.child = scan_box;
            stack.add_named (scanning_page, "scanning");

            var result = new Box (Orientation.HORIZONTAL, 18);
            result.margin_start = 20;
            result.margin_end = 20;
            result.margin_bottom = 20;
            var chart_box = new Box (Orientation.VERTICAL, 8);
            chart_box.hexpand = true;
            chart = new RingChart ();
            chart.node_activated.connect (show_node);
            chart.node_hovered.connect ((node) => {
                hover_label.label = node != null ? "%s · %s".printf (node.name, GLib.format_size ((uint64) node.size)) : _("Point at a ring for details, click a folder to open it");
            });
            chart_box.append (chart);
            hover_label = new Label (_("Point at a ring for details, click a folder to open it"));
            hover_label.add_css_class ("dim-label");
            hover_label.wrap = true;
            hover_label.justify = Justification.CENTER;
            hover_label.lines = 2;
            hover_label.ellipsize = Pango.EllipsizeMode.END;
            chart_box.append (hover_label);
            result.append (chart_box);

            var side = new Box (Orientation.VERTICAL, 10);
            side.set_size_request (380, -1);
            list_title = new Label ("");
            list_title.xalign = 0;
            list_title.add_css_class ("heading");
            side.append (list_title);
            list = new ListBox ();
            list.add_css_class ("usage-list");
            list.selection_mode = SelectionMode.NONE;
            list.row_activated.connect ((row) => {
                var node = row.get_data<Node*> ("node");
                if (node != null && ((Node) node).is_dir) show_node ((Node) node);
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = list;
            side.append (scroll);
            result.append (side);
            stack.add_named (result, "result");

            Singularity.Widgets.apply_view_edge (result);
            set_content (stack);
            set_result_bubbles (false);
            install_actions ();
            stack.notify["visible-child-name"].connect (sync_actions);
            sync_actions ();
        }

        private void install_actions () {
            var entries = new ActionEntry[] {
                { "scan-home", () => start_scan (new Location (Environment.get_home_dir (), _("Home"), "user-home-symbolic")) },
                { "scan-system", () => start_scan (new Location ("/", _("System"), "drive-harddisk-system-symbolic")) },
                { "scan-folder", () => choose_folder () },
                { "open-in-files", () => {
                    if (current != null) open_in_files (current);
                } },
                { "stop", () => {
                    if (scanner != null) scanner.cancel ();
                } },
                { "copy-path", () => {
                    if (current != null) get_clipboard ().set_text (current.path ());
                } },
                { "up", () => {
                    if (current != null && current.parent != null) show_node (current.parent);
                } },
                { "rescan", () => {
                    if (location != null) start_scan (location);
                } },
                { "close", () => close () }
            };
            add_action_entries (entries, this);
        }

        private void sync_actions () {
            var action = lookup_action ("stop") as SimpleAction;
            if (action == null) return;
            bool result = stack.visible_child_name == "result" && current != null;
            action.set_enabled (stack.visible_child_name == "scanning");
            ((SimpleAction) lookup_action ("open-in-files")).set_enabled (result);
            ((SimpleAction) lookup_action ("copy-path")).set_enabled (result);
            ((SimpleAction) lookup_action ("up")).set_enabled (result && current.parent != null);
            ((SimpleAction) lookup_action ("rescan")).set_enabled (result && location != null);
        }

        private void set_result_bubbles (bool on) {
            up_bubble.visible = on;
            path_bubble.visible = on;
            rescan_bubble.visible = on;
        }

        private void load_locations () {
            locations.clear ();
            locations.add (new Location (Environment.get_home_dir (), _("Home"), "user-home-symbolic"));
            locations.add (new Location ("/", _("System"), "drive-harddisk-system-symbolic"));
            var seen = new Gee.HashSet<string> ();
            seen.add ("/");
            seen.add (Environment.get_home_dir ());
            foreach (var mount in VolumeMonitor.get ().get_mounts ()) {
                var root = mount.get_root ();
                string? path = root.get_path ();
                if (path == null || seen.contains (path) || mount.is_shadowed ()) continue;
                seen.add (path);
                string icon = mount.can_eject () ? "drive-removable-media-symbolic" : "drive-harddisk-symbolic";
                locations.add (new Location (path, mount.get_name (), icon));
            }
            Widget? child;
            while ((child = sidebar.box.get_first_child ()) != null) sidebar.box.remove (child);
            rows.clear ();
            sidebar.box.append (new SidebarSectionLabel (_("Locations")));
            foreach (var loc in locations) {
                var row = new SidebarRow (loc.icon, loc.label);
                var cap = loc;
                row.clicked.connect (() => start_scan (cap));
                rows[loc.path] = row;
                sidebar.box.append (row);
                if (loc.total > 0) {
                    var meter = new Box (Orientation.VERTICAL, 3);
                    meter.margin_start = 40;
                    meter.margin_end = 12;
                    meter.margin_bottom = 6;
                    var bar = new LevelBar.for_interval (0, 1);
                    bar.value = (double) (loc.total - loc.free) / loc.total;
                    bar.add_css_class ("usage-meter");
                    meter.append (bar);
                    var text = new Label (_("%s free of %s").printf (GLib.format_size (loc.free), GLib.format_size (loc.total)));
                    text.xalign = 0;
                    text.add_css_class ("dim-label");
                    text.add_css_class ("caption");
                    meter.append (text);
                    sidebar.box.append (meter);
                }
            }
        }

        private void sync_rows () {
            foreach (var e in rows.entries) e.value.set_active (location != null && e.key == location.path);
        }

        public void scan_path (string path) {
            foreach (var loc in locations) {
                if (loc.path == path) {
                    start_scan (loc);
                    return;
                }
            }
            string label = path == "/" ? _("System") : Path.get_basename (path);
            start_scan (new Location (path, label, "folder-symbolic"));
        }

        private void choose_folder () {
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Folder to Scan");
            dialog.select_folder.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.select_folder.end (res);
                    if (file != null && file.get_path () != null) {
                        start_scan (new Location (file.get_path (), file.get_basename (), "folder-symbolic"));
                    }
                } catch (Error e) {
                }
            });
        }

        private void start_scan (Location loc) {
            if (scanner != null) scanner.cancel ();
            location = loc;
            sync_rows ();
            set_result_bubbles (false);
            scanning_page.title = _("Scanning %s").printf (loc.label);
            scanning_page.description = "";
            scan_bar.fraction = 0;
            scan_detail.label = "";
            stack.visible_child_name = "scanning";
            uint64 used = loc.total > loc.free ? loc.total - loc.free : 0;
            var s = new DiskScanner ();
            scanner = s;
            s.progress.connect ((bytes, files, path) => {
                if (s != scanner) return;
                if (used > 0 && loc.path == "/") scan_bar.fraction = double.min (1, (double) bytes / used);
                else scan_bar.pulse ();
                scanning_page.description = ngettext ("%s in %s file", "%s in %s files", (ulong) files).printf (GLib.format_size ((uint64) bytes), Format.group ((uint64) files));
                scan_detail.label = path;
            });
            s.finished.connect ((root, cancelled) => {
                if (s != scanner) return;
                scanner = null;
                if (cancelled || root == null) {
                    stack.visible_child_name = "start";
                    return;
                }
                tree = root;
                root.name = loc.path;
                show_node (root);
            });
            s.start (loc.path);
        }

        private void show_node (Node node) {
            current = node;
            chart.set_root (node);
            set_result_bubbles (true);
            up_bubble.sensitive = node.parent != null;
            string display = node.path ();
            string home = Environment.get_home_dir ();
            if (display == home) display = "~";
            else if (display.has_prefix (home + "/")) display = "~" + display.substring (home.length);
            path_bubble.label = display;
            list_title.label = ngettext ("%s in %s item", "%s in %s items", (ulong) node.files).printf (GLib.format_size ((uint64) node.size), Format.group ((uint64) node.files));
            Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            int shown = 0;
            foreach (unowned Node c in node.children) {
                if (shown >= 200) break;
                list.append (make_row (c, node.size));
                shown++;
            }
            stack.visible_child_name = "result";
            sync_actions ();
        }

        private ListBoxRow make_row (Node node, int64 parent_size) {
            var row = new ListBoxRow ();
            row.set_data<Node*> ("node", node);
            row.activatable = node.is_dir;
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 12;
            box.margin_end = 8;
            var icon = new Image.from_icon_name (node.is_dir ? "folder-symbolic" : "text-x-generic-symbolic");
            box.append (icon);
            var texts = new Box (Orientation.VERTICAL, 4);
            texts.hexpand = true;
            var top = new Box (Orientation.HORIZONTAL, 8);
            var name = new Label (node.name);
            name.xalign = 0;
            name.hexpand = true;
            name.ellipsize = Pango.EllipsizeMode.MIDDLE;
            top.append (name);
            var size = new Label (GLib.format_size ((uint64) node.size));
            size.add_css_class ("dim-label");
            size.add_css_class ("numeric");
            top.append (size);
            texts.append (top);
            var bar = new LevelBar.for_interval (0, 1);
            bar.value = parent_size > 0 ? (double) node.size / parent_size : 0;
            bar.add_css_class ("usage-share");
            texts.append (bar);
            box.append (texts);
            var more = new Button.from_icon_name ("view-more-symbolic");
            more.add_css_class ("flat");
            more.valign = Align.CENTER;
            more.tooltip_text = _("More");
            more.clicked.connect (() => item_menu (more, node));
            box.append (more);
            row.child = box;
            return row;
        }

        private void item_menu (Widget anchor, Node node) {
            var menu = new ContextMenu (anchor);
            if (node.is_dir) menu.add_item (_("Open in Chart"), "view-grid-symbolic", () => show_node (node));
            menu.add_item (_("Show in Files"), "folder-open-symbolic", () => open_in_files (node));
            menu.add_item (_("Copy Path"), "edit-copy-symbolic", () => get_clipboard ().set_text (node.path ()));
            menu.add_separator ();
            menu.add_item (_("Move to Trash"), "user-trash-symbolic", () => trash (node), "destructive-action");
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void open_in_files (Node node) {
            var file = File.new_for_path (node.path ());
            var launcher = new FileLauncher (file);
            if (node.is_dir) launcher.launch.begin (this, null);
            else launcher.open_containing_folder.begin (this, null);
        }

        private void trash (Node node) {
            var dlg = new ConfirmDialog (app, _("Move to Trash?"), "user-trash-symbolic",
                _("\"%s\" (%s) will be moved to the Trash.").printf (node.name, GLib.format_size ((uint64) node.size)),
                _("Move to Trash"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                File.new_for_path (node.path ()).trash_async.begin (Priority.DEFAULT, null, (obj, res) => {
                    try {
                        File.new_for_path (node.path ()).trash_async.end (res);
                        remove_node (node);
                    } catch (Error e) {
                        var err = new ConfirmDialog.message (app, _("Could Not Move to Trash"), "dialog-error-symbolic", e.message, _("Close"));
                        err.transient_for = this;
                        err.present ();
                    }
                });
            });
            dlg.present ();
        }

        private void remove_node (Node node) {
            unowned Node? parent = node.parent;
            if (parent == null) return;
            Node[] kept = {};
            foreach (var c in parent.children) if (c != node) kept += c;
            parent.children = kept;
            for (unowned Node? p = parent; p != null; p = p.parent) {
                p.size -= node.size;
                p.files -= node.files;
            }
            show_node (current);
            load_locations ();
            sync_rows ();
        }
    }

    public class Format {
        public static string group (uint64 value) {
            string digits = value.to_string ();
            var sb = new StringBuilder ();
            int count = 0;
            for (int i = digits.length - 1; i >= 0; i--) {
                sb.prepend_c (digits[i]);
                if (++count % 3 == 0 && i > 0) sb.prepend_c (',');
            }
            return sb.str;
        }
    }
}
