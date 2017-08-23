class Httpd24 < Formula
  desc "HTTP server"
  homepage "https://httpd.apache.org/"
  url "https://archive.apache.org/dist/httpd/httpd-2.4.27.tar.bz2"
  sha256 "71fcc128238a690515bd8174d5330a5309161ef314a326ae45c7c15ed139c13a"

  bottle do
    sha256 "d35e67ae745053cda23273a520ead6bde506ec8082057edcd3185c9e36eae483" => :sierra
    sha256 "4ea7056d6c08f9cf49507869aa8c78e3522c601d87b3347d31561ba05b33d41c" => :el_capitan
    sha256 "e6ae5c4d38b40bcf3d85877ac117a1ea048de774edec3c2b0ff714bc01a6d40a" => :yosemite
  end

  skip_clean :la

  option "with-mpm-worker", "Use the Worker Multi-Processing Module instead of Prefork"
  option "with-mpm-event", "Use the Event Multi-Processing Module instead of Prefork"
  option "with-privileged-ports", "Use the default ports 80 and 443 (which require root privileges), instead of 8080 and 8443"
  option "with-ldap", "Include support for LDAP"
  deprecated_option "with-http2" => "with-nghttp2"

  depends_on "openssl"
  depends_on "pcre"
  depends_on "zlib"
  depends_on "apr-util"
  depends_on "apr-util" => "with-openldap" if build.with? "ldap"
  depends_on "nghttp2" => :recommended

  conflicts_with "homebrew/apache/httpd22", :because => "different versions of the same software"

  if build.with?("mpm-worker") && build.with?("mpm-event")
    raise "Cannot build with both worker and event MPMs, choose one"
  end

  def install
    # point config files to opt_prefix instead of the version-specific prefix
    inreplace "Makefile.in",
      '#@@ServerRoot@@#$(prefix)#', '#@@ServerRoot@@'"##{opt_prefix}#"

    # fix non-executable files in sbin dir (for brew audit)
    inreplace "support/Makefile.in",
      "$(DESTDIR)$(sbindir)/envvars", "$(DESTDIR)$(sysconfdir)/envvars"
    inreplace "support/Makefile.in",
      "envvars-std $(DESTDIR)$(sbindir);", "envvars-std $(DESTDIR)$(sysconfdir);"
    inreplace "support/apachectl.in",
      "@exp_sbindir@/envvars", "#{etc}/apache2/2.4/envvars"

    # install custom layout
    File.open("config.layout", "w") { |f| f.write(httpd_layout) }

    args = %W[
      --enable-layout=Homebrew
      --enable-mods-shared=all
      --enable-unique-id
      --enable-ssl
      --enable-dav
      --enable-cache
      --enable-logio
      --enable-deflate
      --enable-cgi
      --enable-cgid
      --enable-suexec
      --enable-rewrite
      --with-apr=#{Formula["apr"].opt_prefix}
      --with-apr-util=#{Formula["apr-util"].opt_prefix}
      --with-pcre=#{Formula["pcre"].opt_prefix}
      --with-ssl=#{Formula["openssl"].opt_prefix}
      --with-z=#{Formula["zlib"].opt_prefix}
    ]

    if build.with? "mpm-worker"
      args << "--with-mpm=worker"
    elsif build.with? "mpm-event"
      args << "--with-mpm=event"
    else
      args << "--with-mpm=prefork"
    end

    if build.with? "privileged-ports"
      args << "--with-port=80" << "--with-sslport=443"
    else
      args << "--with-port=8080" << "--with-sslport=8443"
    end

    if build.with? "nghttp2"
      args << "--enable-http2" << "--with-nghttp2=#{Formula["nghttp2"].opt_prefix}"
    end

    if build.with? "ldap"
      args << "--with-ldap" << "--enable-ldap" << "--enable-authnz-ldap"
    end

    (etc/"apache2/2.4").mkpath

    system "./configure", *args

    system "make"
    system "make", "install"
    (var/"apache2/log").mkpath
    (var/"apache2/run").mkpath
    touch("#{var}/log/apache2/access_log") unless File.exist?("#{var}/log/apache2/access_log")
    touch("#{var}/log/apache2/error_log") unless File.exist?("#{var}/log/apache2/error_log")
  end

  plist_options :manual => "apachectl start"
  if build.with? "privileged-ports"
    plist_options :startup => true, :manual => "apachectl start"
  end

  def plist; <<-EOS.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>#{plist_name}</string>
      <key>ProgramArguments</key>
      <array>
        <string>#{opt_bin}/httpd</string>
        <string>-D</string>
        <string>FOREGROUND</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
    </dict>
    </plist>
    EOS
  end

  def httpd_layout
    <<-EOS.undent
      <Layout Homebrew>
          prefix:        #{prefix}
          exec_prefix:   ${prefix}
          bindir:        ${exec_prefix}/bin
          sbindir:       ${exec_prefix}/bin
          libdir:        ${exec_prefix}/lib
          libexecdir:    ${exec_prefix}/libexec
          mandir:        #{man}
          sysconfdir:    #{etc}/apache2/2.4
          datadir:       #{var}/www
          installbuilddir: ${prefix}/build
          errordir:      ${datadir}/error
          iconsdir:      ${datadir}/icons
          htdocsdir:     ${datadir}/htdocs
          manualdir:     ${datadir}/manual
          cgidir:        #{var}/apache2/cgi-bin
          includedir:    ${prefix}/include/httpd
          localstatedir: #{var}/apache2
          runtimedir:    #{var}/run/apache2
          logfiledir:    #{var}/log/apache2
          proxycachedir: ${localstatedir}/proxy
      </Layout>
    EOS
  end

  test do
    system bin/"httpd", "-v"
  end
end
