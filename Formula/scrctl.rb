class Scrctl < Formula
  desc "Mirror and control iOS devices from a native desktop window"
  homepage "https://github.com/scrctl/scrctl"
  url "https://github.com/scrctl/scrctl/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "277a60e5f72a406d4a5a4627bfb09447e51fcbe84f58719ebbbe17ed91c725d3"
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
    url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.0.0.tar.gz"
    sha256 "ed56bd0f74be37c35368a0b12d7238d01d6fdea35cad58a5aa2cc9c428e4dbfb"
  end

  def install
    resource("xdb-client").stage buildpath/"xdb"
    # The release archive has no .git directory. Record its exact client gitlink
    # rather than making provenance generation depend on a Git checkout.
    inreplace "cmake/SourceMaterials.cmake",
              /execute_process\(COMMAND git -C.*?COMMAND_ERROR_IS_FATAL ANY\)/m,
              'set(SCRCTL_XDB_REVISION "fea3f0f8fcefe1a468645e3891da650249d5f216")'
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
