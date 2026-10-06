using Singularity.Apps.Usage;

void write_file (string path, int size) {
    var data = new uint8[size];
    for (int i = 0; i < size; i++) data[i] = (uint8) (i * 31);
    try {
        FileUtils.set_data (path, data);
    } catch (Error e) {
        error ("write: %s", e.message);
    }
}

void test_scan () {
    string root;
    try {
        root = DirUtils.make_tmp ("usage-test-XXXXXX");
    } catch (FileError e) {
        error ("tmp: %s", e.message);
    }
    DirUtils.create (root + "/big", 0755);
    DirUtils.create (root + "/small", 0755);
    DirUtils.create (root + "/big/deep", 0755);
    write_file (root + "/big/a.bin", 400000);
    write_file (root + "/big/deep/b.bin", 300000);
    write_file (root + "/small/c.bin", 5000);
    FileUtils.symlink (root + "/big/a.bin", root + "/link");
    Posix.link (root + "/big/a.bin", root + "/small/hard.bin");
    var node = DiskScanner.scan_sync (root);
    assert (node.children.length == 3);
    assert (node.children[0].name == "big");
    assert (node.children[0].files == 2);
    assert (node.files == 4);
    int64 big = node.children[0].size;
    assert (big >= 700000 && big < 760000);
    assert (node.size < 800000);
    var deep = node.children[0].children[0];
    assert (deep.is_dir || deep.name == "a.bin");
    assert (deep.parent == node.children[0]);
    assert (node.children[0].children[0].path ().has_prefix (root));
    Posix.system ("rm -rf '" + root + "'");
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/usage/scan", test_scan);
    return Test.run ();
}
