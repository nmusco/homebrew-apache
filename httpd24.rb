class Httpd24 < Formula
  desc "HTTP server"
  homepage "https://httpd.apache.org/"
  url "https://archive.apache.org/dist/httpd/httpd-2.4.27.tar.bz2"
  sha256 "71fcc128238a690515bd8174d5330a5309161ef314a326ae45c7c15ed139c13a"
  revision 1

  bottle do
    sha256 "d35e67ae745053cda23273a520ead6bde506ec8082057edcd3185c9e36eae483" => :sierra
    sha256 "4ea7056d6c08f9cf49507869aa8c78e3522c601d87b3347d31561ba05b33d41c" => :el_capitan
    sha256 "e6ae5c4d38b40bcf3d85877ac117a1ea048de774edec3c2b0ff714bc01a6d40a" => :yosemite
  end

  skip_clean :la

  deprecated_option "with-ldap" => "with-openldap"

  depends_on "brotli" => :optional
  depends_on "openldap" => :optional
  depends_on "openssl"
  depends_on "pcre"
  depends_on "zlib"
  depends_on "apr"
  depends_on "apr-util"
  depends_on "nghttp2" => :recommended

  conflicts_with "homebrew/apache/httpd22", :because => "different versions of the same software"

  def install
    # point config files to opt_prefix instead of the version-specific prefix
    inreplace "Makefile.in",
      '#@@ServerRoot@@#$(prefix)#', '#@@ServerRoot@@'"##{opt_prefix}#"
    inreplace "support/envvars-std.in",
      "@exp_libdir@", opt_lib.to_s

    # fix non-executable files in sbin dir (for brew audit)
    inreplace "support/Makefile.in",
      "$(DESTDIR)$(sbindir)/envvars", "$(DESTDIR)$(sysconfdir)/envvars"
    inreplace "support/Makefile.in",
      "envvars-std $(DESTDIR)$(sbindir);", "envvars-std $(DESTDIR)$(sysconfdir);"
    inreplace "support/apachectl.in",
      "@exp_sbindir@/envvars", "#{etc}/apache2/2.4/envvars"

    # install custom layout
    File.open("config.layout", "w") { |f| f.write(httpd_layout) }
    File.open("docs/conf/httpd.conf.in", "a") { |f| f.puts(welcome_conf) }
    File.open("noindex.html", "w") { |f| f.write(noindex) }
    orig_index = var/"www/htdocs/index.html"

    args = %W[
      --enable-layout=Homebrew
      --enable-mods-shared=all
      --enable-mpms-shared=all
      --with-mpm=prefork
      --with-port=8080
      --with-sslport=8443
      --enable-pie
      --enable-suexec
      --with-apr=#{Formula["apr"].opt_prefix}
      --with-pcre=#{Formula["pcre"].opt_prefix}
      --with-ssl=#{Formula["openssl"].opt_prefix}
      --with-z=#{Formula["zlib"].opt_prefix}
    ]
    args << "--with-nghttp2=#{Formula["nghttp2"].opt_prefix}" if build.with? "nghttp2"
    args << "--enable-http2=no" if build.without? "nghttp2"
    args << "--with-brotli=#{Formula["brotli"].opt_prefix}" if build.with? "brotli"

    if build.with?("openldap") && Tab.for_name("apr-util").without?("openldap")
      vendor_install_apr_util
      args << "--with-apr-util=#{libexec/"vendor"}"
    else
      args << "--with-apr-util=#{Formula["apr-util"].opt_prefix}"
    end

    config_dir.mkpath

    system "./configure", *args

    system "make"
    system "make", "install"

    %w[access_log error_log].each { |log| touch(log_dir/log) unless File.exist?(log_dir/log) }
    cp HOMEBREW_REPOSITORY/"docs/img/homebrew-256x256.png", var/"www/icons"
    (var/"www/error").install "noindex.html"
    orig_index.unlink if orig_index.exist? && identical?("docs/docroot/index.html", orig_index)
  end

  def vendor_install_apr_util
    Formula["apr-util"].stable.stage do
      args = %W[
        --prefix=#{libexec/"vendor"}
        --with-apr=#{Formula["apr"].opt_prefix}
        --with-openssl=#{Formula["openssl"].opt_prefix}
        --with-crypto
        --with-ldap
        --with-ldap-lib=#{Formula["openldap"].opt_lib}
        --with-ldap-include=#{Formula["openldap"].opt_include}
      ]

      system "./configure", *args
      system "make"
      system "make", "install"
    end
  end

  def post_install
    orig_index = var/"www/htdocs/index.html"
    orig_index.unlink if orig_index.exist? && orig_index.sha256 == "f2dcc96deec8bca2facba9ad0db55c89f3c4937cd6d2d28e5c4869216ffa81cf"
    # Check for previous install with old options
    keg = installed_kegs.sort_by(&:version).at(-2)
    tab = Tab.for_keg(keg) unless keg.nil?
    tab = Tab.for_formula(self) if keg.nil?
    found_mpm_config = false

    File.foreach(httpd_conf) do |line|
      found_mpm_config = line.include? "LoadModule mpm"
      break if found_mpm_config
    end

    unless found_mpm_config
      ohai "Fixing httpd.conf for shared mpms"
      insert_at_string = "LoadModule unixd_module"
      insert = ""
      insert << "#" unless tab.with? "mpm-event"
      insert << "LoadModule mpm_event_module libexec/mod_mpm_event.so\n"
      insert << "#" if tab.with?("mpm-event") || tab.with?("mpm-worker")
      insert << "LoadModule mpm_prefork_module libexec/mod_mpm_prefork.so\n"
      insert << "#" unless tab.with? "mpm-worker"
      insert << "LoadModule mpm_worker_module libexec/mod_mpm_worker.so\n"
      insert << insert_at_string
      inreplace httpd_conf, insert_at_string, insert
    end
  end

  def caveats
    <<-EOS.undent
      --with-privileged-ports option has been removed in favor of configuation instructions. Using port 80 and 443 require the use of root privileges to start.
      \t* Change the "Listen 8080" line in #{httpd_conf}
      \t* Change the "Listen 8443" line in #{ssl_conf}
    EOS
  end

  plist_options :startup => true, :manual => "apachectl start"

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

  def log_dir
    var/"log/apache2"
  end

  def config_dir
    etc/"apache2/2.4"
  end

  def httpd_conf
    config_dir/"httpd.conf"
  end

  def ssl_conf
    config_dir/"extra/httpd-ssl.conf"
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
          sysconfdir:    #{config_dir}
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
          logfiledir:    #{log_dir}
          proxycachedir: ${localstatedir}/proxy
      </Layout>
    EOS
  end

  def welcome_conf
    <<-EOS.undent
      #
      # This configuration section enables the default "Welcome" page if there
      # is no default index page present for the root URL.  To disable the
      # Welcome page, comment out all the lines below.
      #
      <LocationMatch "^/+$">
          Options -Indexes
          ErrorDocument 403 /error/noindex.html
      </LocationMatch>

      <Directory #{var}/www/error>
          AllowOverride None
          Require all granted
      </Directory>
      <Directory #{var}/www/icons>
          Options +FollowSymLinks
          AllowOverride None
          Require all granted
      </Directory>

      Alias /error/noindex.html #{var}/www/error/noindex.html
      Alias /icons/ #{var}/www/icons/

      # End Welcome
    EOS
  end

  def noindex
    <<-EOS.undent
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <title>Test Page for the Apache HTTP Server from Homebrew</title>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width">
          <style>
            html {
              margin: 0;
              padding: 0;
              font-size: 62.5%;
              font-family: "-apple-system", "BlinkMacSystemFont", "Helvetica Neue", "Roboto", "sans-serif";
              height: 100%;
              background: #2e2a24;
              color: #f9d094;
            }
            body {
              height: 100%;
              width: 57em;
              max-width: 100%;
              font-size: 150%;
              line-height: 1.4;
              position: relative;
              margin: 0 auto;
              padding: 15px 0 0;
            }
            :link {
              color: #ba832c;
              text-decoration: none;
            }
            :visited {
              color: #ba832c;
            }
            a:hover {
              color: #d3a459;
              text-decoration: underline;
            }
            h1, h2, h3 {
              font-size: 420%;
              margin: 0 0 0.1em;
              text-align: center;
              text-shadow: 1px 1px 10px rgba(0, 0, 0, 0.25);
            }
            h1, h2, h3, h4, h5, h6 {
              line-height: 1.1;
            }
            h1 img {
              border: 0;
              margin: 0;
              padding: 0;
            }
            h1 {
              margin: 0;
              font-weight: 900;
              padding: 0 30px 2rem;
              border-bottom: 1px solid rgba(0, 0, 0, 0.5);
            }
            h1 strong {
              font-weight: bold;
            }
            h2, h3 {
              font-weight: 800;
              margin-top: 0.5em;
              margin-bottom: 0.1em;
            }
            h2 {
              font-size: 300%;
            }
            h3 {
              font-size: 125%;
            }
            hr {
              display: none;
            }
            .content {
              padding: 1em 0;
              border-top: 1px solid rgba(255, 255, 255, 0.08);
            }
            .content-middle {
              padding: 0 20px 1em;
              border-bottom: 1px solid rgba(0, 0, 0, 0.5);
            }
            .content-columns {
              position: relative;
            }
            .content-column-left {
              border-top: 1px solid rgba(255, 255, 255, 0.08);
              border-bottom: 1px solid rgba(0, 0, 0, 0.5);
              padding: 1em 20px 2em;
            }
            .content-column-right {
              border-top: 1px solid rgba(255, 255, 255, 0.08);
              padding: 1em 20px 2em;
            }
            img {
              border: 2px solid #2e2a24;
              padding: 2px;
              margin: 2px;
            }
            a:hover img {
              border: 2px solid #d3a459;
            }
            @media screen and (max-width: 700px) {
                body { padding: 0; }
                h1 { font-size: 350%; }
                h2 { font-size: 250%; }
            }
          </style>
        </head>

        <body>

          <h1><img src="/icons/homebrew-256x256.png" alt="Homebrew logo" height="128" /><br />Homebrew <strong>Test Page</strong></h1>

          <div class="content">
            <div class="content-middle">
              <p>This page is used to test the proper operation of the Apache HTTP server after it has been installed. If you can read this page, it means that the web server installed at this site is working properly, but has not yet been configured.</p>
            </div>
            <hr />

            <div class="content-columns">
              <div class="content-column-left">
                <h2>If you are a member of the general public:</h2>

                <p>The fact that you are seeing this page indicates that the website you just visited is either experiencing problems, or is undergoing routine maintenance.</p>

                <p>If you would like to let the administrators of this website know that you've seen this page instead of the page you expected, you should send them e-mail. In general, mail sent to the name "webmaster" and directed to the website's domain should reach the appropriate person.</p>

                <p>For example, if you experienced problems while visiting www.example.com, you should send e-mail to "webmaster@example.com".</p>

                <p>Homebrew is a package manager for macOS. For more information about Homebrew, please visit the <a href="https://brew.sh/">Homebrew Project website</a>.</p>
                <hr />
              </div>

              <div class="content-column-right">
                <h2>If you are the website administrator:</h2>

                <p>You may now add content to the directory <code>#{var/"www/htdocs"}</code>. Note that until you do so, people visiting your website will see this page, and not your content. To prevent this page from ever being used, follow the instructions in the file <code>#{httpd_conf}</code>.</p>

                <div class="logos">
                  <p><a href="http://httpd.apache.org/"><img src="/icons/apache_pb2.png" alt="[ Powered by Apache ]"/></a> <a href="https://brew.sh/"><img src="/icons/homebrew-256x256.png" alt="[ Homebrew logo ]" height="30" /></a></p>
                </div>
              </div>
            </div>
          </div>
        </body>
      </html>
    EOS
  end

  test do
    system bin/"httpd", "-v"
  end
end
