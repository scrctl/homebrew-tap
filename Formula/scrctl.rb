class Scrctl < Formula
  desc "Mirror and control iOS devices from a native desktop window"
  homepage "https://github.com/scrctl/scrctl"
  url "https://github.com/scrctl/scrctl/archive/refs/tags/v1.4.0.tar.gz"
  sha256 "6356ad209f9468aa3d4c5c71962cf9c276613fe5e49131d8af3fd7db467bd6f5"
  license "Apache-2.0"

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build
  depends_on "cli11"
  depends_on "ffmpeg"
  depends_on "gettext"
  depends_on "nlohmann-json"
  depends_on "scrctl/tap/xdb"
  depends_on "sdl2-compat"

  resource "xdb-client" do
    url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.7.0.tar.gz"
    sha256 "b83eb525f83e8727638aefadf08c8fd0aca483e34b23953c3941351dc4efc7cc"
  end

  def install
    resource("xdb-client").stage buildpath/"xdb"
    # The release archive has no .git directory. Record its exact client gitlink
    # rather than making provenance generation depend on a Git checkout.
    inreplace "cmake/SourceMaterials.cmake",
              /execute_process\(COMMAND git -C.*?COMMAND_ERROR_IS_FATAL ANY\)/m,
              'set(SCRCTL_XDB_REVISION "181c0cba0f70b5de36a20e686a26dcfd7d58ca34")'
    # Upstream's relocatable desktop layout keeps private libraries beside the tool.
    system "cmake", "-S", ".", "-B", "build", *std_cmake_args(install_prefix: libexec),
                   "-DSCRCTL_BUILD_TESTS=OFF", "-DSCRCTL_FETCH_DEPENDENCIES=OFF"
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    bin.install_symlink libexec/"bin/scrctl"
    pkgshare.install "README.md", "CHANGELOG.md"
  end

  test do
    assert_match "scrctl #{version}", shell_output("#{bin}/scrctl --version")
    assert_match "--audio-dup", shell_output("#{bin}/scrctl --lang en --help")
    assert_path_exists formula_opt_bin("scrctl/tap/xdb")/"xdb"
  end
end
