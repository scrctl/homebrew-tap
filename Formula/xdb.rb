class Xdb < Formula
  desc "Native iOS device bridge for pairing, control and media capture"
  homepage "https://github.com/scrctl/XDeviceBridge"
  url "https://github.com/scrctl/XDeviceBridge/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "ed56bd0f74be37c35368a0b12d7238d01d6fdea35cad58a5aa2cc9c428e4dbfb"
  license "LGPL-3.0-only"

  depends_on "cmake" => :build
  depends_on "pkgconf" => :build
  depends_on "ffmpeg"
  depends_on "nlohmann-json"
  depends_on "openssl@3"
  depends_on "pugixml"

  on_linux do
    depends_on "curl"
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
    system "cmake", "-S", ".", "-B", "build", *std_cmake_args,
                   "-DXDB_BUILD_TESTS=OFF", "-DXDB_FETCH_DEPENDENCIES=OFF",
                   "-DFETCHCONTENT_SOURCE_DIR_MDNS=#{buildpath}/mdns",
                   "-DFETCHCONTENT_SOURCE_DIR_LWIP=#{buildpath}/lwip"
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
    pkgshare.install "README.md", "docs"
    (share/"licenses/xdb/lwip").install "lwip/COPYING"
    (share/"licenses/xdb/mdns").install "mdns/LICENSE"
  end

  def caveats
    <<~EOS
      xdb starts on demand and listens on loopback only.
      Pairing records and DDI caches are stored in your user data directory.
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
