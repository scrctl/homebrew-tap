class Xdb < Formula
  desc "Native iOS device bridge for pairing, control and media capture"
  homepage "https://github.com/scrctl/XDeviceBridge"
  url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "6e181fe696dd4dcd9004b8b688eecb7e9168691f6e50d6f4f57c7e81a385c2af"
  license "LGPL-3.0-only"

  bottle do
    root_url "https://github.com/scrctl/homebrew-tap/releases/download/xdb-1.1.0"
    sha256 cellar: :any, arm64_sequoia: "caa48407fa97e3ad9e294aa9afac69715e3830e2904beae54c60e6256a0e2380"
    sha256 cellar: :any, x86_64_linux:  "d3e57924f0eb342250740a61dfb9950c55d678ab411eeef0093b9d8f4c782ac5"
  end

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build
  depends_on "ffmpeg"
  depends_on "nlohmann-json"
  depends_on "openssl@3"
  depends_on "pugixml"

  on_linux do
    depends_on "curl"

    # Only headers are used at build time; xdb loads the system Avahi at runtime.
    resource "avahi-headers" do
      url "https://github.com/avahi/avahi/archive/refs/tags/v0.8.tar.gz"
      sha256 "c15e750ef7c6df595fb5f2ce10cac0fee2353649600e6919ad08ae8871e4945f"
    end
  end

  resource "mdns" do
    url "https://github.com/mjansson/mdns/archive/refs/tags/1.4.3.tar.gz"
    sha256 "be1fd8e35599cb7de179decbd0633c121d11a2dcb9cc193ff5c590bd0d480483"
  end

  resource "lwip" do
    url "https://github.com/lwip-tcpip/lwip/archive/refs/tags/STABLE-2_2_1_RELEASE.tar.gz"
    sha256 "ce0b7461c0ad9602c376f0bf07c5eb7253b48c7bf66f011c6bf3e2a96731c539"
  end

  def install
    resources.each { |r| r.stage buildpath/r.name }
    args = %W[
      -DXDB_BUILD_TESTS=OFF
      -DXDB_FETCH_DEPENDENCIES=OFF
      -DFETCHCONTENT_SOURCE_DIR_MDNS=#{buildpath}/mdns
      -DFETCHCONTENT_SOURCE_DIR_LWIP=#{buildpath}/lwip
    ]
    args << "-DXDB_AVAHI_INCLUDE_DIR=#{buildpath}/avahi-headers" if OS.linux?
    system "cmake", "-S", ".", "-B", "build", *std_cmake_args, *args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    pkgshare.install "README.md", "docs"
    (share/"licenses/xdb/lwip").install "lwip/COPYING"
    (share/"licenses/xdb/mdns").install "mdns/LICENSE"
    (share/"licenses/xdb/avahi").install "avahi-headers/LICENSE" if OS.linux?
  end

  def caveats
    <<~EOS
      xdb starts on demand and listens on loopback only.
      Pairing records and DDI caches are stored in your user data directory.
      After upgrading, run `xdb kill-server` so the next client starts the new version.
      On Linux, native discovery uses your system Avahi client library and daemon;
      xdb falls back to direct mDNS if they are unavailable.
      On Linux, USB connections require a running usbmuxd service and suitable
      device permissions; install/configure them with your system package manager.
    EOS
  end

  test do
    assert_match "XDeviceBridge #{version}", shell_output("#{bin}/xdb --help")
    log = testpath/"server.log"
    pid = spawn bin/"xdb", "server", "--port", "0", "--data-dir", testpath/"data",
                out: log.to_s, err: (testpath/"server.err").to_s
    begin
      port = nil
      100.times do
        text = log.exist? ? log.read : ""
        unless text.empty?
          port = JSON.parse(text.lines.first).fetch("port")
          break
        end
        sleep 0.1
      end
      refute_nil port, "xdb did not start its isolated test server"
      info = JSON.parse(shell_output("#{bin}/xdb --port #{port} rpc server.info"))
      assert info.fetch("ok")
      assert_equal version.to_s, info.fetch("result").fetch("version")
    ensure
      Process.kill "TERM", pid
      Process.wait pid
    end
  end
end
