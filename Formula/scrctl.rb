class Scrctl < Formula
  desc "Mirror and control iOS devices from a native desktop window"
  homepage "https://github.com/scrctl/scrctl"
  url "https://github.com/scrctl/scrctl/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "d3610d129c6bf468b95b16dd2e4d54894e248f2310182aa363e4a2f28370b4dd"
  license "Apache-2.0"

  bottle do
    root_url "https://github.com/scrctl/homebrew-tap/releases/download/scrctl-1.0.1"
    sha256               arm64_sequoia: "ae077bca58941964a7b542c9d96399904c9d98872d8014e13b2e753493e9faae"
    sha256 cellar: :any, x86_64_linux:  "ae2911d022fa962d17c3aeec9c005e0754772b6cfe4eaeec789842858615cd73"
  end

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build
  depends_on "cli11"
  depends_on "ffmpeg"
  depends_on "gettext"
  depends_on "nlohmann-json"
  depends_on "scrctl/tap/xdb"
  depends_on "sdl2-compat"

  resource "xdb-client" do
    url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.1.0.tar.gz"
    sha256 "6e181fe696dd4dcd9004b8b688eecb7e9168691f6e50d6f4f57c7e81a385c2af"
  end

  def install
    resource("xdb-client").stage buildpath/"xdb"
    # The release archive has no .git directory. Record its exact client gitlink
    # rather than making provenance generation depend on a Git checkout.
    inreplace "cmake/SourceMaterials.cmake",
              /execute_process\(COMMAND git -C.*?COMMAND_ERROR_IS_FATAL ANY\)/m,
              'set(SCRCTL_XDB_REVISION "efdae3b4cbaff5995538e4fe3c470c4e0ebe2064")'
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
