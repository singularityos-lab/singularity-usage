using Gtk;

namespace Singularity.Apps.Usage {

    public class RingChart : DrawingArea {
        private const int DEPTH = 5;
        private const double MIN_ANGLE = 0.012;
        private const string[] PALETTE = { "#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#06b6d4", "#ec4899", "#84cc16" };

        private struct Segment {
            public unowned Node node;
            public int depth;
            public double start;
            public double end;
            public int hue;
        }

        private Node? root = null;
        private Segment[] segments = {};
        private int hovered = -1;
        private double cx;
        private double cy;
        private double inner;
        private double ring;

        public signal void node_activated (Node node);
        public signal void node_hovered (Node? node);

        public RingChart () {
            set_size_request (320, 320);
            hexpand = true;
            vexpand = true;
            set_draw_func (draw);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => update_hover (hit (x, y)));
            motion.leave.connect (() => update_hover (-1));
            add_controller (motion);
            var click = new GestureClick ();
            click.released.connect ((n, x, y) => {
                int i = hit (x, y);
                if (i >= 0) {
                    if (segments[i].node.is_dir) node_activated (segments[i].node);
                } else if (root != null && root.parent != null && Math.hypot (x - cx, y - cy) < inner) {
                    node_activated (root.parent);
                }
            });
            add_controller (click);
        }

        public void set_root (Node? node) {
            root = node;
            hovered = -1;
            layout ();
            queue_draw ();
        }

        private void layout () {
            segments = {};
            if (root == null || root.size <= 0) return;
            add_children (root, 0, 0, 2 * Math.PI, -1);
        }

        private void add_children (Node node, int depth, double start, double end, int hue) {
            if (depth >= DEPTH || node.size <= 0) return;
            double span = end - start;
            double at = start;
            int index = 0;
            foreach (var child in node.children) {
                double angle = span * child.size / (double) node.size;
                if (angle < MIN_ANGLE) break;
                Segment s = Segment ();
                s.node = child;
                s.depth = depth;
                s.start = at;
                s.end = at + angle;
                s.hue = hue < 0 ? index % PALETTE.length : hue;
                segments += s;
                if (child.is_dir) add_children (child, depth + 1, at, at + angle, s.hue);
                at += angle;
                index++;
            }
        }

        private int hit (double x, double y) {
            double dx = x - cx, dy = y - cy;
            double r = Math.hypot (dx, dy);
            if (r < inner || ring <= 0) return -1;
            int depth = (int) ((r - inner) / ring);
            double a = Math.atan2 (dy, dx) + Math.PI / 2;
            if (a < 0) a += 2 * Math.PI;
            for (int i = 0; i < segments.length; i++) {
                if (segments[i].depth == depth && a >= segments[i].start && a < segments[i].end) return i;
            }
            return -1;
        }

        private void update_hover (int index) {
            if (index == hovered) return;
            hovered = index;
            queue_draw ();
            node_hovered (index >= 0 ? segments[index].node : null);
        }

        private void draw (DrawingArea area, Cairo.Context cr, int width, int height) {
            cx = width / 2.0;
            cy = height / 2.0;
            double radius = double.min (width, height) / 2.0 - 8;
            inner = radius * 0.28;
            ring = (radius - inner) / DEPTH;
            var fg = get_color ();
            if (root == null) return;
            for (int i = 0; i < segments.length; i++) {
                var s = segments[i];
                var c = Gdk.RGBA ();
                c.parse (PALETTE[s.hue]);
                double fade = 1.0 - s.depth * 0.14;
                double r1 = inner + s.depth * ring + 1;
                double r2 = r1 + ring - 2;
                double a1 = s.start - Math.PI / 2, a2 = s.end - Math.PI / 2;
                double gap = double.min (0.004, (a2 - a1) / 4);
                cr.new_path ();
                cr.arc (cx, cy, r2, a1 + gap, a2 - gap);
                cr.arc_negative (cx, cy, r1, a2 - gap, a1 + gap);
                cr.close_path ();
                bool hot = i == hovered;
                double alpha = s.node.is_dir ? fade : fade * 0.55;
                cr.set_source_rgba (c.red, c.green, c.blue, hot ? 1 : alpha);
                cr.fill ();
                if (hot) {
                    cr.new_path ();
                    cr.arc (cx, cy, r2, a1 + gap, a2 - gap);
                    cr.arc_negative (cx, cy, r1, a2 - gap, a1 + gap);
                    cr.close_path ();
                    cr.set_source_rgba (1, 1, 1, 0.9);
                    cr.set_line_width (2);
                    cr.stroke ();
                }
            }
            cr.arc (cx, cy, inner - 4, 0, 2 * Math.PI);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.06);
            cr.fill ();
            var layout = create_pango_layout ("");
            string size = GLib.format_size ((uint64) root.size);
            string label = root.parent != null ? "%s\n<small>%s</small>".printf (Markup.escape_text (size), _("Click to go up")) : Markup.escape_text (size);
            layout.set_markup ("<b>%s</b>".printf (label), -1);
            layout.set_alignment (Pango.Alignment.CENTER);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            cr.move_to (cx - lw / 2.0, cy - lh / 2.0);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.9);
            Pango.cairo_show_layout (cr, layout);
        }
    }
}
