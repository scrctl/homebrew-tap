class Scrctl < Formula
  desc "Mirror and control iOS devices from a native desktop window"
  homepage "https://github.com/scrctl/scrctl"
  url "https://github.com/scrctl/scrctl/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "6a3ba8faa69cfbfcea761b28a4c05589643abc49ce03deeb5dbd467926c906d1"
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
    url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.4.0.tar.gz"
    sha256 "78ab059c2a95d624f1849916b43ae62bde9a0b2762089ae3399998f7b6f71440"
  end

  def install
    resource("xdb-client").stage buildpath/"xdb"
    # The release archive has no .git directory. Record its exact client gitlink
    # rather than making provenance generation depend on a Git checkout.
    inreplace "cmake/SourceMaterials.cmake",
              /execute_process\(COMMAND git -C.*?COMMAND_ERROR_IS_FATAL ANY\)/m,
              'set(SCRCTL_XDB_REVISION "2ac3ae68335280aa80c1ab084a46e19da029fa10")'
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
