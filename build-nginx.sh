#!/usr/bin/env bash
# Run as root or with sudo

# Make script exit if a simple command fails and
# Make script print commands being executed
set -e -x

# Set names of latest versions of each package
export VERSION_PCRE=pcre-8.42
export VERSION_ZLIB=zlib-1.2.11
export VERSION_LIBRESSL=libressl-2.7.4
export VERSION_NGINX=nginx-1.15.1

# Set checksums of latest versions
export SHA256_PCRE=69acbc2fbdefb955d42a4c606dfde800c2885711d2979e356c0636efde9ec3b5
export SHA256_ZLIB=c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1
export SHA256_NGINX=c7206858d7f832b8ef73a45c9b8f8e436bcb1ee88db2bc85b8e438ecec9d5460
export SHA256_LIBRESSL=1e3a9fada06c1c060011470ad0ff960de28f9a0515277d7336f7e09362517da6

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
#yum -y groupinstall "Development Tools"
apt-get update && apt-get -y install \
  binutils \
  build-essential \
  curl \
  dirmngr \
  libssl-dev
   
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
id -g nginx &>/dev/null || addgroup --system nginx
id -u nginx &>/dev/null || adduser --disabled-password --system --home /var/cache/nginx --shell /sbin/nologin --group nginx

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
make -j4
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
