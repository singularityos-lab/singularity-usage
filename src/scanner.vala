namespace Singularity.Apps.Usage {

    public class Node {
        public string name;
        public unowned Node? parent;
        public Node[] children = {};
        public int64 size = 0;
        public int64 files = 0;
        public bool is_dir;
        public bool unreadable = false;

        public Node (string name, Node? parent, bool is_dir) {
            this.name = name;
            this.parent = parent;
            this.is_dir = is_dir;
        }

        public string path () {
            if (parent == null) return name;
            return Path.build_filename (parent.path (), name);
        }

        public void sort_children () {
            var list = new GenericArray<Node> ();
            foreach (var c in children) list.add (c);
            list.sort ((a, b) => a.size > b.size ? -1 : (a.size < b.size ? 1 : 0));
            Node[] sorted = {};
            for (uint i = 0; i < list.length; i++) sorted += list[i];
            children = sorted;
        }
    }

    public class DiskScanner : Object {
        public signal void progress (int64 bytes, int64 files, string current);
        public signal void finished (Node? root, bool cancelled);

        private Cancellable cancellable = new Cancellable ();
        private int64 bytes = 0;
        private int64 files = 0;
        private string current = "";
        private Gee.HashSet<string> seen_inodes = new Gee.HashSet<string> ();
        private uint64 root_dev = 0;
        private Node? result = null;

        public void cancel () {
            cancellable.cancel ();
        }

        public void start (string path) {
            var tick = Timeout.add (150, () => {
                progress (bytes, files, current);
                return Source.CONTINUE;
            });
            new Thread<void*> ("usage-scan", () => {
                Posix.Stat st;
                if (Posix.lstat (path, out st) == 0) root_dev = (uint64) st.st_dev;
                result = scan (path, null, path);
                Idle.add (() => {
                    Source.remove (tick);
                    progress (bytes, files, "");
                    finished (result, cancellable.is_cancelled ());
                    return Source.REMOVE;
                });
                return null;
            });
        }

        public static Node scan_sync (string path) {
            var s = new DiskScanner ();
            Posix.Stat st;
            if (Posix.lstat (path, out st) == 0) s.root_dev = (uint64) st.st_dev;
            return s.scan (path, null, path);
        }

        private Node scan (string path, Node? parent, string name) {
            var node = new Node (name, parent, true);
            if (cancellable.is_cancelled ()) return node;
            current = path;
            var dir = Posix.opendir (path);
            if (dir == null) {
                node.unreadable = true;
                return node;
            }
            unowned Posix.DirEnt? entry;
            var children = new GenericArray<Node> ();
            while ((entry = Posix.readdir (dir)) != null) {
                string child_name = (string) entry.d_name;
                if (child_name == "." || child_name == "..") continue;
                string child_path = path == "/" ? "/" + child_name : path + "/" + child_name;
                Posix.Stat st;
                if (Posix.lstat (child_path, out st) != 0) continue;
                if (Posix.S_ISDIR (st.st_mode)) {
                    if ((uint64) st.st_dev != root_dev) continue;
                    var sub = scan (child_path, node, child_name);
                    children.add (sub);
                    node.size += sub.size;
                    node.files += sub.files;
                } else {
                    if (st.st_nlink > 1) {
                        string key = "%llu:%llu".printf ((uint64) st.st_dev, (uint64) st.st_ino);
                        if (seen_inodes.contains (key)) continue;
                        seen_inodes.add (key);
                    }
                    int64 used = (int64) st.st_blocks * 512;
                    var leaf = new Node (child_name, node, false);
                    leaf.size = used;
                    leaf.files = 1;
                    children.add (leaf);
                    node.size += used;
                    node.files += 1;
                    bytes += used;
                    files += 1;
                }
                if (cancellable.is_cancelled ()) break;
            }
            Node[] arr = {};
            for (uint i = 0; i < children.length; i++) arr += children[i];
            node.children = arr;
            node.sort_children ();
            return node;
        }
    }
}
