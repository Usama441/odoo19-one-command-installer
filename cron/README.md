# Scheduled database query

`database-query.sql` is your local file where you paste the PostgreSQL query or
script that should run repeatedly. `run-database-query.sh` streams it directly
into the configured PostgreSQL container using the local configuration.

1. Copy `database-query.conf.example` to `database-query.conf` and set the
   Odoo database name and `community` or `enterprise` target.
2. Copy `database-query.sql.example` to `database-query.sql`, then paste the
   query into the local SQL file.
3. If your Odoo stack uses a different Docker engine than `docker ps`, set
   `DB_CRON_DOCKER_HOST` and `DB_CRON_CONTAINER` as shown in the configuration
   example.
4. Test it manually: `./cron/run-database-query.sh`.
5. Edit your user crontab with `crontab -e`, then paste the line from
   `odoo-database-query.crontab` after replacing `__PROJECT_DIR__` with this
   repository's absolute path. The supplied schedule runs on the 25th of every
   month at 12:00 AM.

The job writes both result rows and PostgreSQL errors to
`logs/database-query.log`.  It uses a lock so a slow run cannot overlap the
next scheduled run.

To run at another time, change the five cron timing fields. For example,
`30 2 25 * *` runs on the 25th of every month at 2:30 AM.
