#ifndef _mariadb_version_h_
#define _mariadb_version_h_

#define PROTOCOL_VERSION		10
#define MARIADB_CLIENT_VERSION_STR	"3.4.2"
#define MARIADB_BASE_VERSION		"mariadb-3.4.2"
#define MARIADB_VERSION_ID		30402
#define MARIADB_PORT	        	3306
#define MARIADB_UNIX_ADDR               "/tmp/mariadb.sock"
#ifndef MYSQL_UNIX_ADDR
#define MYSQL_UNIX_ADDR MARIADB_UNIX_ADDR
#endif
#ifndef MYSQL_PORT
#define MYSQL_PORT MARIADB_PORT
#endif

#define MYSQL_CONFIG_NAME               "my"
#define MYSQL_VERSION_ID                30402
#define MYSQL_SERVER_VERSION            "3.4.2-MariaDB"

#define MARIADB_PACKAGE_VERSION "3.4.2"
#define MARIADB_PACKAGE_VERSION_ID 30402
#define MARIADB_SYSTEM_TYPE "Linux"
#define MARIADB_MACHINE_TYPE "x86_64"

#ifndef MYSQL_CHARSET
#define MYSQL_CHARSET "utf8mb4"
#endif

#define CC_SOURCE_REVISION "vendored"

#endif
