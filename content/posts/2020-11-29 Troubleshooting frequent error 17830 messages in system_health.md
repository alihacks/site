---
title: "Troubleshooting frequent error 17830 messages in system_health"
date: 2020-11-22T14:26:15-05:00
draft: false
---
While analyzing the [system_health](https://docs.microsoft.com/en-us/sql/relational-databases/extended-events/use-the-system-health-session?view=sql-server-ver15) on a few SQL Servers, I noticed that error 17830 is logged about 30 times every minute, and this behavior is consistent across a set of servers. After doing some googling, I came across [a very detailed writeup about this error on bobsql.com](https://bobsql.com/sql-mysteries-why-is-my-sql-server-experiencing-lots-of-17830-tcp-10054-errors/). This post saved me quite a bit of troubleshooting time as it explained the details behind what may cause this error and a potential fix.

Before proceeding further, I setup a custom extended event session so I can easily monitor for this error message, and see if I can make it go away.

```sql
CREATE EVENT SESSION [ali_testing] ON SERVER 
ADD EVENT sqlserver.error_reported(
    ACTION(
		sqlserver.client_app_name,
		sqlserver.client_hostname,
		sqlserver.context_info,
		sqlserver.database_id,
		sqlserver.session_id,
		sqlserver.sql_text,
		sqlserver.tsql_stack,
		sqlserver.username,
		sqlserver.plan_handle
	)
    WHERE (
		[error_number] = (17830)
	)
)
ADD TARGET package0.event_file(SET filename=N'ali_testing')

ALTER EVENT SESSION [ali_testing] ON SERVER STATE = START
```

With this monitoring in place, I was able to get some details about the clients (they all seemed to be coming from localhost) as well as a pattern in the error message, it was either:
```Network error code 0x2746 occurred while establishing a connection; the connection has been closed. This may have been caused by client or server login timeout expiration. Time spent during login: total 3 ms, enqueued 3 ms, network writes 0 ms, network reads 0 ms, establishing SSL 0 ms, network reads during SSL 0 ms, network writes during SSL 0 ms, secure calls during SSL 0 ms, enqueued during SSL 0 ms, negotiating SSPI 0 ms, network reads during SSPI 0 ms, network writes during SSPI 0 ms, secure calls during SSPI 0 ms, enqueued during SSPI 0 ms, validating login 0 ms, including user-defined login processing 0 ms. [CLIENT: ::1]```

Or:
```Network error code 0x2746 occurred while establishing a connection; the connection has been closed. This may have been caused by client or server login timeout expiration. Time spent during login: total 1 ms, enqueued 1 ms, network writes 0 ms, network reads 0 ms, establishing SSL 0 ms, network reads during SSL 0 ms, network writes during SSL 0 ms, secure calls during SSL 0 ms, enqueued during SSL 0 ms, negotiating SSPI 0 ms, network reads during SSPI 0 ms, network writes during SSPI 0 ms, secure calls during SSPI 0 ms, enqueued during SSPI 0 ms, validating login 0 ms, including user-defined login processing 0 ms. [CLIENT: 127.0.0.1]```

The the only difference between the repeated 2 messages was the client IP: `127.0.0.` or `::1`. Both these IPs are the loopback adapter (aka localhost) with the former being IPv4 and the latter IPv6. At this point, my guess was that a client was using `localhost` as the server name, and it was resolving to both `127.0.0.` and `::1`, trying to connect to both, and dropping the "loser". I was not able to get more details from the extended event - probably because a lot of this was happening before authentication took place, however I had narrowed down the search to what is running on the server itself. 

At this point I could have captured all logins and tried to see a pattern, but I took a guess and assumed this is caused by `Telegraf Data Collector` which we use on all the servers for gathering metrics (for more details on this, please see this [set of excellent blog posts by Tracy Boggiano](https://tracyboggiano.com/archive/series/collecting-performance-metrics/) or her [GitHub repo](https://github.com/tboggiano/grafana))

Sure enough, the connection string it was using turned out to be `Server=localhost;Port=1433;app name=telegraf;log=1;`. Changing this to use `127.0.0.1` instead to default to IPv6 as: `Server=127.0.0.1;Port=1433;app name=telegraf;log=1;` and restarting the service resolved the issue and the regular 17830 errors we no more.

Once done, I used the following code to clean up my testing XE Session:

```sql
DROP EVENT SESSION [ali_testing] ON SERVER 
```