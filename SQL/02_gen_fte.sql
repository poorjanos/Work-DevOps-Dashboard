/******************************************************************************/

/* Generate view of tickets with booked worksheettimes */

/* Includes open and closed tickets */

/* Includes all ticket types */

/* Includes tickets with no booked worksheettimes*/

/******************************************************************************/


DROP TABLE t_isd_worktimesheet;
COMMIT;

CREATE TABLE t_isd_worktimesheet
AS
     SELECT   *
       FROM      t_isd_tickets tickets
              INNER JOIN
                 (  SELECT   issue,
                             b.name AS user_worktimesheet,
                             c.name AS userorg_worktimesheet,
                             d.name AS actiontypegroup,
                             TRUNC (a.startdate, 'ddd') AS targetday,
                             SUM (hours) AS hours_worktimesheet
                      FROM            KASPERSK.worktimesheet a
                                   LEFT JOIN
                                      KASPERSK.permissionpolicyuser b
                                   ON a.owner = b.oid
                                LEFT JOIN
                                   KASPERSK.organization c
                                ON b.defaultorganization = c.oid
                             LEFT JOIN
                                KASPERSK.actiontypegroup d
                             ON A.ACTIONTYPEGROUP = D.OID
                     WHERE   a.timetype = 'WorkTime'
                  GROUP BY   issue,
                             b.name,
                             c.name,
                             d.name,
                             TRUNC (startdate, 'ddd')) fte
              ON tickets.oid = fte.issue
   ORDER BY   tickets.oid, fte.targetday;

COMMIT;




/******************************************************************************/

/* Flag booked worksheettimes by development lifecycle name */

/* Depends on t_dev_milestones */

/******************************************************************************/

ALTER TABLE t_isd_worktimesheet
ADD
(phase varchar2(10));
COMMIT;


UPDATE   t_isd_worktimesheet a
   SET   phase = 'Release'
 WHERE   EXISTS
            (SELECT   1
               FROM   t_dev_milestones b
              WHERE       a.oid = b.oid
                      AND b.release_start IS NOT NULL
                      AND a.targetday >= b.release_start);



UPDATE   t_isd_worktimesheet a
   SET   phase = 'Demand'
 WHERE   phase IS NULL
         AND EXISTS
               (SELECT   1
                  FROM   t_dev_milestones b
                 WHERE       a.oid = b.oid
                         AND b.demand_start IS NOT NULL
                         AND a.targetday >= b.demand_start);


UPDATE   t_isd_worktimesheet a
   SET   phase = 'Pre-demand'
 WHERE   phase IS NULL
         AND EXISTS
               (SELECT   1
                  FROM   t_dev_milestones b
                 WHERE       a.oid = b.oid
                         AND b.demand_start IS NOT NULL
                         AND a.targetday < b.demand_start);

COMMIT;