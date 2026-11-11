namespace Singularity.Apps.Usage {

    internal class UsageIntents : Object {

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static string resolve(string p) throws Error {
            string path = p == "" ? Environment.get_home_dir() : p;
            if (path.has_prefix("~/") || path == "~") path = Environment.get_home_dir() + path.substring(1);
            if (!Path.is_absolute(path)) throw new IOError.INVALID_ARGUMENT("path must be absolute");
            path = File.new_for_path(path).get_path();
            if (!FileUtils.test(path, FileTest.IS_DIR)) throw new IOError.NOT_FOUND("no folder %s", path);
            return path;
        }

        private static async Node scan(string path) {
            var s = new DiskScanner();
            Node? out_root = null;
            s.finished.connect((root, cancelled) => {
                out_root = root;
                scan.callback();
            });
            s.start(path);
            yield;
            return out_root ?? new Node(path, null, true);
        }

        private static void tree(Json.Builder b, Node n, int depth, int limit) {
            b.begin_object();
            b.set_member_name("path").add_string_value(n.path());
            b.set_member_name("size_bytes").add_int_value(n.size);
            b.set_member_name("size").add_string_value(format_size((uint64) n.size));
            if (n.is_dir) b.set_member_name("files").add_int_value(n.files);
            if (n.unreadable) b.set_member_name("unreadable").add_boolean_value(true);
            if (n.is_dir && depth > 0 && n.children.length > 0) {
                b.set_member_name("largest").begin_array();
                int i = 0;
                foreach (var c in n.children) {
                    if (i++ == limit) break;
                    tree(b, c, depth - 1, limit);
                }
                b.end_array();
            }
            b.end_object();
        }

        private static void leaves(Node n, Gee.ArrayList<Node> list) {
            foreach (var c in n.children) {
                if (c.is_dir) leaves(c, list);
                else list.add(c);
            }
        }

        private static async void run_scan(UsageApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                string path = resolve(text(args, "path"));
                int depth = args.has_member("depth") ? (int) args.get_int_member("depth").clamp(1, 4) : 2;
                int limit = args.has_member("limit") ? (int) args.get_int_member("limit").clamp(1, 50) : 8;
                var root = yield scan(path);
                var b = new Json.Builder();
                tree(b, root, depth, limit);
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void largest(UsageApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                string path = resolve(text(args, "path"));
                int limit = args.has_member("limit") ? (int) args.get_int_member("limit").clamp(1, 100) : 20;
                var root = yield scan(path);
                var list = new Gee.ArrayList<Node>();
                leaves(root, list);
                list.sort((a, c) => a.size > c.size ? -1 : (a.size < c.size ? 1 : 0));
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("folder").add_string_value(path);
                b.set_member_name("total").add_string_value(format_size((uint64) root.size));
                b.set_member_name("files").begin_array();
                int i = 0;
                foreach (var n in list) {
                    if (i++ == limit) break;
                    b.begin_object();
                    b.set_member_name("path").add_string_value(n.path());
                    b.set_member_name("size_bytes").add_int_value(n.size);
                    b.set_member_name("size").add_string_value(format_size((uint64) n.size));
                    b.end_object();
                }
                b.end_array();
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        private static async void trash(UsageApp app, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold();
            try {
                string raw = text(args, "path");
                if (raw == "") throw new IOError.INVALID_ARGUMENT("give the path to move to the Trash");
                if (raw.has_prefix("~/")) raw = Environment.get_home_dir() + raw.substring(1);
                var f = File.new_for_path(raw);
                string path = f.get_path();
                string home = Environment.get_home_dir();
                if (!path.has_prefix(home + "/")) throw new IOError.PERMISSION_DENIED("only files inside the home folder can be moved to the Trash here");
                string rel = path.substring(home.length + 1);
                if (rel == "" || rel.has_prefix(".local/share/Trash")) throw new IOError.PERMISSION_DENIED("%s cannot be moved to the Trash", path);
                if (!f.query_exists()) throw new IOError.NOT_FOUND("nothing at %s", path);
                int64 size = 0;
                if (FileUtils.test(path, FileTest.IS_DIR)) size = DiskScanner.scan_sync(path).size;
                else size = (int64) f.query_info(FileAttribute.STANDARD_ALLOCATED_SIZE, FileQueryInfoFlags.NOFOLLOW_SYMLINKS).get_attribute_uint64(FileAttribute.STANDARD_ALLOCATED_SIZE);
                yield f.trash_async(Priority.DEFAULT, null);
                if (f.query_exists()) throw new IOError.FAILED("%s is still there", path);
                var b = new Json.Builder();
                b.begin_object();
                b.set_member_name("moved_to_trash").add_string_value(path);
                b.set_member_name("size").add_string_value(format_size((uint64) size));
                b.set_member_name("note").add_string_value("the space comes back once the Trash is emptied");
                b.set_member_name("undo").add_string_value("restore it from the Trash");
                b.end_object();
                reply(b.get_root(), null);
            } catch (Error e) {
                reply(null, e);
            } finally {
                app.release();
            }
        }

        internal static void install(UsageApp app) {
            var agent = app.agent;
            agent.add_intent("usage_disks", "How full each mounted disk is: size, used and free space.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_array();
                    var seen = new Gee.HashSet<string>();
                    var roots = new Gee.ArrayList<string>();
                    roots.add("/");
                    roots.add(Environment.get_home_dir());
                    foreach (var m in VolumeMonitor.get().get_mounts()) {
                        var r = m.get_root().get_path();
                        if (r != null) roots.add(r);
                    }
                    foreach (string r in roots) {
                        try {
                            var info = File.new_for_path(r).query_filesystem_info("filesystem::size,filesystem::free,filesystem::id,filesystem::type", null);
                            string id = info.get_attribute_string("filesystem::id") ?? r;
                            if (!seen.add(id)) continue;
                            uint64 size = info.get_attribute_uint64("filesystem::size");
                            uint64 free = info.get_attribute_uint64("filesystem::free");
                            if (size == 0) continue;
                            b.begin_object();
                            b.set_member_name("mount").add_string_value(r);
                            if (info.has_attribute("filesystem::type")) b.set_member_name("type").add_string_value(info.get_attribute_string("filesystem::type"));
                            b.set_member_name("size").add_string_value(format_size(size));
                            b.set_member_name("free").add_string_value(format_size(free));
                            b.set_member_name("used_percent").add_int_value((int64) Math.round(100.0 * (size - free) / size));
                            b.end_object();
                        } catch (Error e) {
                        }
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_async_intent("usage_scan", "What takes the space in a folder (the home folder when path is left out): its biggest subfolders and files, a few levels deep.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"depth\":{\"type\":\"integer\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    run_scan.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("usage_largest_files", "The largest single files inside a folder and all its subfolders.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    largest.begin(app, args, (owned) reply);
                });
            agent.add_async_intent("usage_move_to_trash", "Move a file or folder inside the home folder to the Trash to free space once the Trash is emptied.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    trash.begin(app, args, (owned) reply);
                });
        }
    }
}
