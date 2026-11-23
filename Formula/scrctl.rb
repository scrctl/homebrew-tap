class Scrctl < Formula
  desc "iOS screen mirroring and remote desktop control"
  homepage "https://github.com/scrctl/scrctl"
  url "https://github.com/scrctl/scrctl/archive/refs/tags/v2.0.0.tar.gz"
  sha256 "2f29e2a0a74bd0a5003549d44207e2423983426090c823ac08d57715513a01a7"
  license "Apache-2.0"

  depends_on "cmake" => :build
  depends_on "ninja" => :build
  depends_on "nlohmann-json" => :build
  depends_on "pkgconf" => :build
  depends_on "rust" => :build
  depends_on "scrctl/tap/xdb"
  depends_on "sdl3"

  resource "xdb-client" do
    url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.7.0.tar.gz"
    sha256 "b83eb525f83e8727638aefadf08c8fd0aca483e34b23953c3941351dc4efc7cc"
  end

  deny_network_access!

  def fetch
    system "cargo", "fetch", *std_cargo_fetch_args, "--manifest-path", "core/Cargo.toml"
  end

  def install
    ENV["CARGO_NET_OFFLINE"] = "true"
    resource("xdb-client").stage buildpath/"xdb"
    # The release archive has no .git directory. Record its exact client gitlink
    # rather than making provenance generation depend on a Git checkout.
    inreplace "cmake/SourceMaterials.cmake",
              /execute_process\(COMMAND git -C.*?COMMAND_ERROR_IS_FATAL ANY\)/m,
              'set(SCRCTL_XDB_REVISION "181c0cba0f70b5de36a20e686a26dcfd7d58ca34")'
    # Upstream's relocatable desktop layout keeps private libraries beside the tool.
    # The Homebrew Ninja shim strips jitterentropy's required per-file -O0.
    system "cmake", "-S", ".", "-B", "build", "-G", "Ninja", *std_cmake_args(install_prefix: libexec),
                   "-DCMAKE_MAKE_PROGRAM=#{Formula["ninja"].opt_bin/"ninja"}",
                   "-DXDB_FETCH_DEPENDENCIES=OFF"
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    bin.install_symlink libexec/"bin/scrctl"
    pkgshare.install "README.md", "CHANGELOG.md"
  end

  test do
    assert_equal "scrctl #{version}", shell_output("#{bin}/scrctl --version").strip
    assert_equal "scrctl #{version}", shell_output("#{bin}/scrctl --target-type ios --version").strip
    help = shell_output("#{bin}/scrctl --lang en --help")
    assert_match "--audio-dup", help
    assert_match "--record ", help
    refute_match(/--play\b/, help)
    assert_match "--view-only", shell_output("#{bin}/scrctl --target-type vnc --help")
    assert_path_exists formula_opt_bin("scrctl/tap/xdb")/"xdb"
  end
end
