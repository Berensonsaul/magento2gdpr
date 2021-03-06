#!/bin/bash
. "$(dirname "$0")/common.sh"
if [ -d web ]
then
	rm -Rf web
fi
PHP=php
PHPVERSION=$(php -v | grep -E '^PHP [0-9]+\.[0-9]+' | sed -E 's/PHP ([0-9]+)\.([0-9]+).*/\1.\2/g')
PHPMAJOR=$(echo ${PHPVERSION} | sed -E 's/\.[0-9]+//g')
PHPMINOR=$(echo ${PHPVERSION} | sed -E 's/[0-9]+\.//g')
COMPOSER=composer
if [ "${PHPMAJOR}" -lt 7 -o "${PHPMINOR}" -gt 0 ] && command -v php7.0
then
	PHP=php7.0
	COMPOSER="${PHP} $(command -v composer)"
fi
if ! ${COMPOSER} config http-basic.repo.magento.com.username
then
	${COMPOSER} config --global http-basic.repo.magento.com "${MAGENTO_PACKAGIST_BASIC_AUTH_USERNAME}" "${MAGENTO_PACKAGIST_BASIC_AUTH_PASSWORD}"
fi
${COMPOSER} create-project --repository-url=https://repo.magento.com/ magento/project-community-edition web
cd web
${COMPOSER} require \
	fzaninotto/faker \
	magento/module-catalog-sample-data \
	magento/module-configurable-sample-data \
	magento/module-cms-sample-data \
	magento/module-sales-sample-data \
	sabas/edifact
cd ${DIR}
case "${DEPLOY_ENVIRONMENT}" in
	Continuous|Test|Production)
		;;
	*)
		DEPLOY_ENVIRONMENT=Build
		;;
esac
if [ -d secrets/${DEPLOY_ENVIRONMENT} ]
then
	rsync -arc secrets/${DEPLOY_ENVIRONMENT}/ web/
fi
if [ "${TRAVIS}" == "true" ]
then
	if command -v phpenv
	then
		echo "cgi.fix_pathinfo = 1" >> ~/.phpenv/versions/$(phpenv version-name)/etc/php.ini
		echo > ~/.phpenv/versions/$(phpenv version-name)/etc/conf.d/xdebug.ini
		phpenv config-rm xdebug.ini
		echo 'memory_limit = -1' >> ~/.phpenv/versions/$(phpenv version-name)/etc/conf.d/travis.ini
		phpenv rehash;
	fi
	DATABASE_NAME=$(grep "'dbname'" web/app/etc/env.php | sed -e "s/'/ /g" | awk '{print $3}')
	DATABASE_USER=$(grep "'username'" web/app/etc/env.php | sed -e "s/'/ /g" | awk '{print $3}')
	DATABASE_PASSWORD=$(grep "'password'" web/app/etc/env.php | sed -e "s/'/ /g" | awk '{print $3}')
	echo "CREATE USER '${DATABASE_USER}'@'localhost' IDENTIFIED BY '${DATABASE_PASSWORD}';
GRANT USAGE ON *.* TO '${DATABASE_USER}'@'localhost' IDENTIFIED BY '${DATABASE_PASSWORD}' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0 ;
CREATE DATABASE IF NOT EXISTS \`${DATABASE_NAME}\` ;
GRANT ALL PRIVILEGES ON \`${DATABASE_NAME}\`.* TO '${DATABASE_USER}'@'localhost' ;" | mysql -f
	cd web
	magento_install() {
		rm -Rf var/cache/* var/generation/* var/di/* var/page_cache/*
		${PHP} bin/magento setup:install -vvv \
			--admin-email=admin@example.com \
			--admin-firstname="Dev Team" \
			--admin-lastname=Adfab \
			--admin-password="${DATABASE_PASSWORD}" \
			--admin-user=admin \
			--admin-use-security-key=0 \
			--backend-frontname="admin" \
			--base-url=http://localhost \
			--base-url-secure=https://localhost \
			--cleanup-database \
			--currency=EUR \
			--db-host=localhost \
			--db-name="${DATABASE_NAME}" \
			--db-user="${DATABASE_USER}" \
			--db-password="${DATABASE_PASSWORD}" \
			--language=fr_FR \
			--session-save="files" \
			--timezone=Europe/Paris \
			--use-sample-data \
			--use-rewrites=1 \
			--no-interaction
	}
	magento_install || magento_install
	cd ..
fi
if [ ! -z "${SHARED_DIR}" ]
then
	for FILE in web/pub/media web/pub/static web/var
	do
		mkdir -p ${SHARED_DIR}/${FILE}
		if [ -e ${FILE} ]
		then
			rm -Rf ${FILE}
		fi
		ln -s ${SHARED_DIR}/${FILE} ${FILE}
	done
fi
cd web
mkdir -p app/code/Adfab/Gdpr
cd app/code/Adfab/Gdpr
for FILE in $(ls ../../../../../ | grep -v web | grep -v config)
do
	ln -s ../../../../../${FILE}
done
cd ${DIR}/web
${PHP} bin/magento cache:clean
rm -Rf \
	pub/static/* \
	var/cache/* \
	var/composer_home/* \
	var/generation/* \
	var/page_cache/* \
	var/view_preprocessed/*
${PHP} bin/magento setup:static-content:deploy -f
${PHP} bin/magento setup:upgrade
#${PHP} bin/magento setup:di:compile
