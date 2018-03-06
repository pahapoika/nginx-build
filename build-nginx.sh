#!/usr/bin/env bash
# Run as root or with sudo

# Make script exit if a simple command fails and
# Make script print commands being executed
set -e -x

# Set names of latest versions of each package
export VERSION_PCRE=pcre-8.41
export VERSION_ZLIB=zlib-1.2.11
export VERSION_LIBRESSL=libressl-2.6.4
export VERSION_NGINX=nginx-1.13.9

# Set checksums of latest versions
export SHA256_PCRE=244838e1f1d14f7e2fa7681b857b3a8566b74215f28133f14a8f5e59241b682c
export SHA256_ZLIB=c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1
export SHA256_NGINX=5faea18857516fe68d30be39c3032bd22ed9cf85e1a6fdf32e3721d96ff7fa42
export SHA256_LIBRESSL=638a20c2f9e99ee283a841cd787ab4d846d1880e180c4e96904fc327d419d11f

# Set GPG keys used to sign downloads
export GPG_NGINX=B0F4253373F8F6F510D42178520A9993A1C052F8

# Set URLs to the source directories
export SOURCE_LIBRESSL=https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/
export SOURCE_PCRE=https://ftp.pcre.org/pub/pcre/
export SOURCE_ZLIB=https://zlib.net/
export SOURCE_NGINX=https://nginx.org/download/

# Set where OpenSSL and nginx will be built
export BPATH=$(pwd)/build

# Make a 'today' variable for use in back-up filenames later
today=$(date +"%Y-%m-%d")

# Clean out any files from previous runs of this script
rm -rf build
rm -rf /etc/nginx-default
mkdir $BPATH

# Ensure the required software to compile nginx is installed
yum -y groupinstall "Development Tools"
   
# Download the source files
curl -L $SOURCE_PCRE$VERSION_PCRE.tar.gz -o ./build/PCRE.tar.gz && \
  echo "${SHA256_PCRE} ./build/PCRE.tar.gz" | sha256sum -c -
curl -L $SOURCE_ZLIB$VERSION_ZLIB.tar.gz -o ./build/ZLIB.tar.gz && \
  echo "${SHA256_ZLIB} ./build/ZLIB.tar.gz" | sha256sum -c -
curl -L $SOURCE_NGINX$VERSION_NGINX.tar.gz -o ./build/NGINX.tar.gz && \
  echo "${SHA256_NGINX} ./build/NGINX.tar.gz" | sha256sum -c -
curl -L $SOURCE_LIBRESSL$VERSION_LIBRESSL.tar.gz -o ./build/LIBRESSL.tar.gz && \
  echo "${SHA256_LIBRESSL} ./build/LIBRESSL.tar.gz" | sha256sum -c -  


# Download the signature files
curl -L $SOURCE_NGINX$VERSION_NGINX.tar.gz.asc -o ./build/NGINX.tar.gz.asc

# Verify GPG signature of downloads
cd $BPATH
export GNUPGHOME="$(mktemp -d)"
gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_NGINX"
gpg --batch --verify NGINX.tar.gz.asc NGINX.tar.gz
rm -r "$GNUPGHOME" NGINX.tar.gz.asc

# Expand the source files
tar xzf PCRE.tar.gz
tar xzf ZLIB.tar.gz
tar xzf LIBRESSL.tar.gz
tar xzf NGINX.tar.gz
# Clean up
rm -r \
  PCRE.tar.gz \
  ZLIB.tar.gz \
  LIBRESSL.tar.gz \
  NGINX.tar.gz
cd ../

# Rename the existing /etc/nginx directory so it's saved as a back-up
if [ -d "/etc/nginx" ]; then
  mv /etc/nginx /etc/nginx-$today
fi

# Create NGINX cache directories if they do not already exist
if [ ! -d "/var/cache/nginx/" ]; then
    mkdir -p \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp
fi

# Add nginx group and user if they do not already exist
id -g nginx &>/dev/null || groupadd --system nginx
id -u nginx &>/dev/null || useradd --system -d /var/cache/nginx --shell /sbin/nologin -g nginx nginx

# Test to see if our version of gcc supports __SIZEOF_INT128__
if gcc -dM -E - </dev/null | grep -q __SIZEOF_INT128__
then
ECFLAG="enable-ec_nistp_64_gcc_128"
else
ECFLAG=""
fi

# Build nginx, with various modules included/excluded
cd $BPATH/$VERSION_NGINX
./configure \
--prefix=/etc/nginx \
--with-cc-opt='-O3 -fPIE -fstack-protector-strong -Wformat -Werror=format-security' \
--with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro' \
--with-pcre=$BPATH/$VERSION_PCRE \
--with-zlib=$BPATH/$VERSION_ZLIB \
--with-openssl-opt="no-shared $ECFLAG -fstack-protector-strong" \
--with-openssl=$BPATH/$VERSION_LIBRESSL \
--sbin-path=/usr/sbin/nginx \
--modules-path=/usr/lib/nginx/modules \
--conf-path=/etc/nginx/nginx.conf \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--pid-path=/var/run/nginx.pid \
--lock-path=/var/run/nginx.lock \
--http-client-body-temp-path=/var/cache/nginx/client_temp \
--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
--user=nginx \
--group=nginx \
--with-file-aio \
--with-http_auth_request_module \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_mp4_module \
--with-http_realip_module \
--with-http_secure_link_module \
--with-http_slice_module \
--with-http_ssl_module \
--with-http_stub_status_module \
--with-http_sub_module \
--with-http_v2_module \
--with-pcre-jit \
--with-stream \
--with-stream_ssl_module \
--with-threads \
--without-http_empty_gif_module \
--without-http_geo_module \
--without-http_split_clients_module \
--without-http_ssi_module \
--without-mail_imap_module \
--without-mail_pop3_module \
--without-mail_smtp_module
make
make install
make clean
strip -s /usr/sbin/nginx*

if [ -d "/etc/nginx-$today" ]; then
  # Rename the compiled 'default' /etc/nginx directory so its accessible as a reference to the new nginx defaults
  mv /etc/nginx /etc/nginx-default

  # Restore the previous version of /etc/nginx to /etc/nginx so the old settings are kept
  mv /etc/nginx-$today /etc/nginx
fi

# Create NGINX init service file if it does not already exist
if [ ! -e "/lib/systemd/system/nginx.service" ]; then
  # Control will enter here if $DIRECTORY doesn't exist.
  FILE="/lib/systemd/system/nginx.service"

  /bin/cat >$FILE <<'EOF'
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target
[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF
fi

echo "All done.";
echo "Start with systemctl start nginx"
echo "or with sudo nginx"
