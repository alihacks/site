---
title: "Using a custom Extended Event Session to get faster results from sp_blitzLock"
date: 2020-11-22T14:26:15-05:00
draft: false
---
I'm pretty new to [sp_blitzLock](https://www.brentozar.com/archive/2017/12/introducing-sp_blitzlock-troubleshooting-sql-server-deadlocks/) which is a great utility stored procedure that's part of the [First Responder Kit](https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit) that makes analyzing deadlocks simpler by parsing out a lot of the information from the XML deadlock reports. Unfortunately, I have noticed that on some servers, runtime of the SP can take quite a while. My analysis has shown that this is not really an issue with `sp_blitzLock` but rather SQL Server's ability to work with XML.

When using `system_health` event session, below is the output:
```
Grab the initial set of XML to parse at Nov 22 2020 12:20:01:123PM
Parse process and input buffer XML Nov 22 2020 12:24:11:360PM
```
You can see that almost 4 minutes is spent grabbing the xml from the. This is because `sp_blitzLock` is going through the entire set of files and trying to filter for `xml_deadlock_report` records which involves parsing all the XML and filtering which is not something SQL Server is terribly good at.

Exploring further, based on the query used in `sp_blitzLock` we see that the  `system_health` files on this system have quite a bit of data:

```sql
SELECT COUNT(*) as num_records, SUM(DATALENGTH(event_data)) AS total_bytes
FROM   sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
```
![query results](/images/20201122_xefilesize.png)

That is 819,712 rows totalling 3,812,607,108, that's almost 4GB of data we need to sort through.

One way to deal with this is to create a custom event session that only records deadlocks which will make it easier to parse through and get the same information we're looking for. To test this theory, I created the following:

```sql
CREATE EVENT SESSION [deadlocks] ON SERVER 
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file(SET filename=N'deadlocks',max_file_size=(100),max_rollover_files=(3))
WITH (STARTUP_STATE=ON)
```

This will create a set of `xel` files that start with the prefix `deadlocks` that are up to 100MB each and up to a maximum of 3 files. Unlike `system_health`, these will only contain deadlocks - the information we're actually looking for. You may want to tune the file size and number of files based on your requirement of how much deadlock history you want to keep around. After making this change and waiting a while so we can get some deadlocks (or alternatively we can create a whole bunch), we can now run `sp_blitzLock` and use the parameter `@EventSessionPath` to tell it to use our files instead:

```sql
exec sp_blitzlock @EventSessionPath = 'deadlocks*.xel'
```

And the entire execution takes about 5 seconds, more importantly, the parsing of XML (in this instance for the same number of deadlocks since this change has been on this server for about 10 days) takes a mere ~3 seconds:

```
Grab the initial set of XML to parse at Nov 22 2020  12:39:36:017PM
Parse process and input buffer XML Nov 22 2020  12:39:36:100PM
```

Running the same query to see the size of data in the `xel` files returns 20 rows totaling 258,598 bytes - quite a difference. Going forward, I plan on setting up this extended event session on a few other severs where deadlocks are common and developers need to troubleshoot them.

