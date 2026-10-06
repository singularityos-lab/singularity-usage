using Gtk;
using Singularity;

namespace Singularity.Apps.Usage {

    public class FreeSpaceProvider : Object, OverviewWidgetProvider {
        public string id { get { return "usage.free-space"; } }
        public string provider_id { get { return "dev.sinty.usage"; } }
        public string display_name { get { return _("Free Space"); } }
        public string icon_name { get { return "drive-harddisk-symbolic"; } }
        private WidgetSize[] sizes = { WidgetSize (1, 1), WidgetSize (2, 1) };
        public WidgetSize[] supported_sizes { get { return sizes; } }

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            return new FreeSpaceWidget (size);
        }
    }

    public class Volume : Object {
        public string path;
        public string label;
        public uint64 total;
        public uint64 free;

        public double used_fraction () {
            return total > 0 ? (double) (total - free) / total : 0;
        }

        public static Volume? query (string path, string label, Gee.Set<string> seen) {
            try {
                var info = File.new_for_path (path).query_filesystem_info ("filesystem::size,filesystem::free", null);
                var id = File.new_for_path (path).query_info ("id::filesystem", FileQueryInfoFlags.NONE, null);
                string? fs = id.get_attribute_string (FileAttribute.ID_FILESYSTEM);
                if (fs != null && !seen.add (fs)) return null;
                var v = new Volume ();
                v.path = path;
                v.label = label;
                v.total = info.get_attribute_uint64 (FileAttribute.FILESYSTEM_SIZE);
                v.free = info.get_attribute_uint64 (FileAttribute.FILESYSTEM_FREE);
                return v.total > 0 ? v : null;
            } catch (Error e) {
                return null;
            }
        }

        public static Gee.List<Volume> all () {
            var list = new Gee.ArrayList<Volume> ();
            var seen = new Gee.HashSet<string> ();
            var root = query ("/", _("System"), seen);
            if (root != null) list.add (root);
            var home = query (Environment.get_home_dir (), _("Home"), seen);
            if (home != null) list.add (home);
            foreach (var mount in VolumeMonitor.get ().get_mounts ()) {
                string? path = mount.get_root ().get_path ();
                if (path == null || mount.is_shadowed ()) continue;
                var v = query (path, mount.get_name (), seen);
                if (v != null) list.add (v);
            }
            return list;
        }
    }

    public class SpaceRing : DrawingArea {
        public double fraction { get; set; }

        public SpaceRing () {
            set_draw_func (draw);
            notify["fraction"].connect (queue_draw);
            Singularity.Style.StyleManager.get_default ().notify["accent-hex"].connect (queue_draw);
        }

        private void draw (DrawingArea area, Cairo.Context cr, int width, int height) {
            double size = double.min (width, height);
            double line = double.max (5, size * 0.1);
            double r = (size - line) / 2 - 1;
            double cx = width / 2.0;
            double cy = height / 2.0;
            var fg = get_color ();
            cr.set_line_width (line);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.12);
            cr.arc (cx, cy, r, 0, 2 * Math.PI);
            cr.stroke ();
            var accent = Gdk.RGBA ();
            accent.parse (fraction >= 0.9 ? "#e01b24" : Singularity.Style.StyleManager.get_default ().accent_hex);
            Gdk.cairo_set_source_rgba (cr, accent);
            double start = -Math.PI / 2;
            if (fraction > 0.005) {
                cr.arc (cx, cy, r, start, start + 2 * Math.PI * double.min (1, fraction));
                cr.stroke ();
            }
        }
    }

    public class FreeSpaceWidget : Box {
        private WidgetSize size;
        private Box content;
        private uint timer = 0;

        public FreeSpaceWidget (WidgetSize size) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.size = size;
            add_css_class ("overview-widget-card");
            hexpand = true;
            vexpand = true;
            content = new Box (Orientation.HORIZONTAL, 6);
            content.hexpand = true;
            content.vexpand = true;
            content.margin_start = 8;
            content.margin_end = 8;
            content.margin_top = 8;
            content.margin_bottom = 8;
            content.homogeneous = true;
            append (content);
            map.connect (() => {
                refresh ();
                if (timer == 0) timer = Timeout.add_seconds (120, () => {
                    refresh ();
                    return Source.CONTINUE;
                });
            });
            unmap.connect (() => {
                if (timer != 0) Source.remove (timer);
                timer = 0;
            });
        }

        private void refresh () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            var volumes = Volume.all ();
            if (volumes.size == 0) return;
            int max = size.w >= 2 ? 3 * size.w / 2 : 1;
            for (int i = 0; i < volumes.size && i < max; i++) content.append (tile (volumes[i], size.w < 2));
        }

        private Widget tile (Volume v, bool single) {
            var button = new Button ();
            button.has_frame = false;
            button.add_css_class ("flat");
            button.tooltip_text = _("%s: %s free of %s").printf (v.label, GLib.format_size (v.free), GLib.format_size (v.total));
            var box = new Box (Orientation.VERTICAL, 2);
            var overlay = new Overlay ();
            overlay.vexpand = true;
            var ring = new SpaceRing ();
            ring.fraction = v.used_fraction ();
            ring.set_size_request (single ? 56 : 44, single ? 56 : 44);
            overlay.child = ring;
            var percent = new Label ("%d%%".printf ((int) Math.round (v.used_fraction () * 100)));
            percent.add_css_class (single ? "heading" : "caption-heading");
            percent.halign = Align.CENTER;
            percent.valign = Align.CENTER;
            overlay.add_overlay (percent);
            box.append (overlay);
            var name = new Label (single ? _("%s free").printf (GLib.format_size (v.free)) : v.label);
            name.add_css_class ("caption");
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 10;
            box.append (name);
            if (!single) {
                var free = new Label (_("%s free").printf (GLib.format_size (v.free)));
                free.add_css_class ("caption");
                free.add_css_class ("dim-label");
                free.ellipsize = Pango.EllipsizeMode.END;
                free.max_width_chars = 10;
                box.append (free);
            }
            button.child = box;
            string path = v.path;
            button.clicked.connect (() => open (path));
            return button;
        }

        private void open (string path) {
            var info = new DesktopAppInfo ("dev.sinty.usage.desktop");
            if (info == null) return;
            var uris = new List<string> ();
            uris.append (File.new_for_path (path).get_uri ());
            try {
                info.launch_uris (uris, get_display ().get_app_launch_context ());
            } catch (Error e) {
                warning ("Free space widget: %s", e.message);
            }
        }
    }

    [CCode (cname = "singularity_usage_widget_new")]
    public static Object singularity_usage_widget_new () {
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            Intl.bindtextdomain ("singularity-usage", Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale"));
            Intl.bind_textdomain_codeset ("singularity-usage", "UTF-8");
        } catch (Error e) {
        }
        return new FreeSpaceProvider ();
    }
}
