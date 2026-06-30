#define FORCE_INIT_OF_VARS 1

#include <ma_global.h>
#include <ma_sys.h>
#include <ma_common.h>
#include <ma_string.h>
#include <ma_pthread.h>

#include "errmsg.h"
#include <mysql/client_plugin.h>

#ifndef WIN32
#include <dlfcn.h>
#endif

const char *disabled_plugins= "";

extern struct st_mysql_client_plugin_AUTHENTICATION mysql_native_password_client_plugin;
extern struct st_mysql_client_plugin_AUTHENTICATION mysql_clear_password_client_plugin;
extern struct st_mysql_client_plugin_AUTHENTICATION dialog_client_plugin;
extern MARIADB_PVIO_PLUGIN pvio_socket_client_plugin;

struct st_mysql_client_plugin *mysql_client_builtins[]=
{
  (struct st_mysql_client_plugin *)&mysql_native_password_client_plugin,
  (struct st_mysql_client_plugin *)&mysql_clear_password_client_plugin,
  (struct st_mysql_client_plugin *)&dialog_client_plugin,
  (struct st_mysql_client_plugin *)&pvio_socket_client_plugin,
  0
};

struct st_client_plugin_int {
  struct st_client_plugin_int *next;
  void   *dlhandle;
  struct st_mysql_client_plugin *plugin;
};

static my_bool initialized= 0;
static MA_MEM_ROOT mem_root;

static uint valid_plugins[][2]= {
  {MYSQL_CLIENT_AUTHENTICATION_PLUGIN, MYSQL_CLIENT_AUTHENTICATION_PLUGIN_INTERFACE_VERSION},
  {MARIADB_CLIENT_PVIO_PLUGIN, MARIADB_CLIENT_PVIO_PLUGIN_INTERFACE_VERSION},
  {MARIADB_CLIENT_TRACE_PLUGIN, MARIADB_CLIENT_TRACE_PLUGIN_INTERFACE_VERSION},
  {MARIADB_CLIENT_REMOTEIO_PLUGIN, MARIADB_CLIENT_REMOTEIO_PLUGIN_INTERFACE_VERSION},
  {MARIADB_CLIENT_CONNECTION_PLUGIN, MARIADB_CLIENT_CONNECTION_PLUGIN_INTERFACE_VERSION},
  {MARIADB_CLIENT_COMPRESSION_PLUGIN, MARIADB_CLIENT_COMPRESSION_PLUGIN_INTERFACE_VERSION},
  {0, 0}
};

struct st_client_plugin_int *plugin_list[MYSQL_CLIENT_MAX_PLUGINS + MARIADB_CLIENT_MAX_PLUGINS];
static pthread_mutex_t LOCK_load_client_plugin;

static int get_plugin_nr(uint type)
{
  uint i= 0;
  for(; valid_plugins[i][1]; i++)
    if (valid_plugins[i][0] == type)
      return i;
  return -1;
}

static const char *check_plugin_version(struct st_mysql_client_plugin *plugin, unsigned int version)
{
  if (plugin->interface_version >> 8 != version >> 8)
    return "Incompatible client plugin interface";
  return 0;
}

static struct st_mysql_client_plugin *find_plugin(const char *name, int type)
{
  struct st_client_plugin_int *p;
  int plugin_nr= get_plugin_nr(type);

  if (initialized == 0)
    return 0;

  if (plugin_nr == -1)
    return 0;

  if (!name)
  {
    if (plugin_list[plugin_nr])
      return plugin_list[plugin_nr]->plugin;
    return NULL;
  }

  for (p= plugin_list[plugin_nr]; p; p= p->next)
  {
    if (strcmp(p->plugin->name, name) == 0)
      return p->plugin;
  }
  return NULL;
}

static struct st_mysql_client_plugin *
add_plugin(MYSQL *mysql, struct st_mysql_client_plugin *plugin, void *dlhandle,
           int argc, va_list args)
{
  const char *errmsg;
  struct st_client_plugin_int plugin_int, *p;
  char errbuf[1024];
  int plugin_nr;

  if (initialized == 0)
    return 0;

  plugin_int.plugin= plugin;
  plugin_int.dlhandle= dlhandle;

  if ((plugin_nr= get_plugin_nr(plugin->type)) == -1)
  {
    errmsg= "Unknown client plugin type";
    goto err1;
  }
  if ((errmsg= check_plugin_version(plugin, valid_plugins[plugin_nr][1])))
    goto err1;

  if (plugin->init && plugin->init(errbuf, sizeof(errbuf), argc, args))
  {
    errmsg= errbuf;
    goto err1;
  }

  p= (struct st_client_plugin_int *)
    ma_memdup_root(&mem_root, (char *)&plugin_int, sizeof(plugin_int));

  if (!p)
  {
    errmsg= "Out of memory";
    goto err2;
  }

  p->next= plugin_list[plugin_nr];
  plugin_list[plugin_nr]= p;

  return plugin;

err2:
  if (plugin->deinit)
    plugin->deinit();
err1:
  my_set_error(mysql, CR_AUTH_PLUGIN_CANNOT_LOAD, SQLSTATE_UNKNOWN,
               ER(CR_AUTH_PLUGIN_CANNOT_LOAD), plugin->name, errmsg);
  if (dlhandle)
    (void)dlclose(dlhandle);
  return NULL;
}

int mysql_client_plugin_init()
{
  MYSQL mysql;
  struct st_mysql_client_plugin **builtin;
  va_list unused;

  if (initialized)
    return 0;

  memset(&mysql, 0, sizeof(mysql));

  pthread_mutex_init(&LOCK_load_client_plugin, NULL);
  ma_init_alloc_root(&mem_root, 128, 128);

  memset(&plugin_list, 0, sizeof(plugin_list));

  initialized= 1;

  pthread_mutex_lock(&LOCK_load_client_plugin);
  for (builtin= mysql_client_builtins; *builtin; builtin++)
    add_plugin(&mysql, *builtin, 0, 0, unused);

  pthread_mutex_unlock(&LOCK_load_client_plugin);

  return 0;
}

static int is_not_initialized(MYSQL *mysql, const char *name)
{
  if (initialized)
    return 0;
  if (name)
    my_set_error(mysql, CR_AUTH_PLUGIN_CANNOT_LOAD, SQLSTATE_UNKNOWN,
                 ER(CR_AUTH_PLUGIN_CANNOT_LOAD), name, "not initialized");
  return 1;
}

#define MARIADB_PLUGINDIR "/usr/local/lib/mariadb/plugin"
#define SO_EXT ".so"

struct st_mysql_client_plugin * STDCALL
mysql_load_plugin_v(MYSQL *mysql, const char *name, int type,
                    int argc, va_list args)
{
  (void)argc;
  (void)args;
  my_set_error(mysql, CR_AUTH_PLUGIN_CANNOT_LOAD, SQLSTATE_UNKNOWN,
               ER(CR_AUTH_PLUGIN_CANNOT_LOAD), name, "plugin not available in static build");
  return NULL;
}

struct st_mysql_client_plugin * STDCALL
mysql_load_plugin(MYSQL *mysql, const char *name, int type, int argc, ...)
{
  my_set_error(mysql, CR_AUTH_PLUGIN_CANNOT_LOAD, SQLSTATE_UNKNOWN,
               ER(CR_AUTH_PLUGIN_CANNOT_LOAD), name, "plugin not available in static build");
  return NULL;
}

struct st_mysql_client_plugin * STDCALL
mysql_client_find_plugin(MYSQL *mysql, const char *name, int type)
{
  struct st_mysql_client_plugin *p;
  int plugin_nr= get_plugin_nr(type);

  if (is_not_initialized(mysql, name))
    return NULL;

  if (plugin_nr == -1)
  {
    my_set_error(mysql, CR_AUTH_PLUGIN_CANNOT_LOAD, SQLSTATE_UNKNOWN,
                 ER(CR_AUTH_PLUGIN_CANNOT_LOAD), name, "invalid type");
  }

  if ((p= find_plugin(name, type)))
    return p;

  /* not found, load it */
  return mysql_load_plugin(mysql, name, type, 0);
}

void mysql_client_plugin_deinit()
{
  int i;
  struct st_client_plugin_int *p;

  if (!initialized)
    return;

  for (i=0; i < MYSQL_CLIENT_MAX_PLUGINS; i++)
    for (p= plugin_list[i]; p; p= p->next)
    {
      if (p->plugin->deinit)
        p->plugin->deinit();
      if (p->dlhandle)
        (void)dlclose(p->dlhandle);
    }

  memset(&plugin_list, 0, sizeof(plugin_list));
  initialized= 0;
  ma_free_root(&mem_root, MYF(0));
  pthread_mutex_destroy(&LOCK_load_client_plugin);
}
