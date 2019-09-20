/* Formatted on 2019. 09. 20. 13:04:37 (QP5 v5.115.810.9015) */
  SELECT   tickets.oid,
           tickets.CASE,
           status.ISSUESTATENEW AS ACTIVITY,
           status.MODIFIEDDATE AS TIMESTAMP,
           lag (status.MODIFIEDDATE) over (partition by tickets.oid order by status.MODIFIEDDATE) as lag_timestamp
    FROM      t_dev_milestones tickets
           LEFT JOIN
              KASPERSK.ISSUESTATUSLOG status
           ON tickets.oid = status.issue
ORDER BY   tickets.CASE, status.MODIFIEDDATE