#!/bin/bash
set -e

download_and_extract() {
  src=${1}
  dest=${2}
  tarball=$(basename ${src})

  if [[ ! -f ${NEXTCLOUD_BUILD_ASSETS_DIR}/${tarball} ]]; then
    echo "Downloading ${1}..."
    wget ${src} -O ${NEXTCLOUD_BUILD_ASSETS_DIR}/${tarball}
  fi

  echo "Extracting ${tarball}..."
  mkdir -p ${dest}
  tar xf ${NEXTCLOUD_BUILD_ASSETS_DIR}/${tarball} --strip=1 -C ${dest}
  rm -rf ${NEXTCLOUD_BUILD_ASSETS_DIR}/${tarball}
}

php_config_get() {
  local config=${1?config file not specified}
  local key=${2?key not specified}
  sed -n -e "s/^\(${key}=\)\(.*\)\(.*\)$/\2/p" ${config}
}

php_config_set() {
  local config=${1?config file not specified}
  local key=${2?key not specified}
  local value=${3?value not specified}
  local verbosity=${4:-verbose}

  if [[ ${verbosity} == verbose ]]; then
    echo "Setting ${config} parameter: ${key}=${value}"
  fi

  local current=$(php_config_get ${config} ${key})
  if [[ "${current}" != "${value}" ]]; then
    if [[ $(sed -n -e "s/^[;]*[ ]*\(${key}\)=.*/\1/p" ${config}) == ${key} ]]; then
      value="$(echo "${value}" | sed 's|[&]|\\&|g')"
      sed -i "s|^[;]*[ ]*${key}=.*|${key}=${value}|" ${config}
    else
      echo "${key}=${value}" | tee -a ${config} >/dev/null
    fi
  fi
}

apt-get update

DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
  wget ca-certificates sudo nginx mysql-client postgresql-client gettext-base \
  php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-gd \
  php${PHP_VERSION}-pgsql php${PHP_VERSION}-mysql php${PHP_VERSION}-curl \
  php${PHP_VERSION}-zip php${PHP_VERSION}-xml php${PHP_VERSION}-mbstring \
  php${PHP_VERSION}-intl php${PHP_VERSION}-ldap \
  php${PHP_VERSION}-gmp php${PHP_VERSION}-apcu php${PHP_VERSION}-imagick

# configure php.ini
mkdir -p /run/php/

php_config_set "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf" "listen" "0.0.0.0:9000"
php_config_set "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf" "env[PATH]" "/usr/local/bin:/usr/bin:/bin"

php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "always_populate_raw_post_data" "-1"

php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.enable" "1"
php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.enable_cli" "1"
php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.interned_strings_buffer" "8"
php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.max_accelerated_files" "10000"
php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.memory_consumption" "128"
php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.save_comments" "1"
php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "opcache.revalidate_freq" "1"

php_config_set "/etc/php/${PHP_VERSION}/fpm/php.ini" "memory_limit" "256M"

download_and_extract "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" "${NEXTCLOUD_INSTALL_DIR}"

find ${NEXTCLOUD_INSTALL_DIR}/ -type f -print0 | xargs -0 chmod 0640
find ${NEXTCLOUD_INSTALL_DIR}/ -type d -print0 | xargs -0 chmod 0750
chown -R root:${NEXTCLOUD_USER} ${NEXTCLOUD_INSTALL_DIR}/
chown -R ${NEXTCLOUD_USER}: ${NEXTCLOUD_INSTALL_DIR}/apps/
chown -R ${NEXTCLOUD_USER}: ${NEXTCLOUD_INSTALL_DIR}/config/
chown -R ${NEXTCLOUD_USER}: ${NEXTCLOUD_INSTALL_DIR}/themes/
chown root:${NEXTCLOUD_USER} ${NEXTCLOUD_INSTALL_DIR}/.htaccess
chmod 0644 ${NEXTCLOUD_INSTALL_DIR}/.htaccess
chown root:${NEXTCLOUD_USER} ${NEXTCLOUD_INSTALL_DIR}/.user.ini
chmod 0644 ${NEXTCLOUD_INSTALL_DIR}/.user.ini

# remove default vhost
rm -rf /etc/nginx/sites-enabled/default

# clean up
apt-get purge --auto-remove -y wget
rm -rf /var/lib/apt/lists/*
