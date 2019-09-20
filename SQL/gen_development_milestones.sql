/******************************************************************************/
/* Generate view of DEVELOPMENT tickets */
/* Depends on gen_tickets_base.sql */
/* Includes open and closed tickets */
/******************************************************************************/

DROP TABLE t_dev_milestones;
COMMIT;

CREATE TABLE t_dev_milestones
AS
   SELECT   *
     FROM   t_isd_tickets
    WHERE  REGISTRATIONIDPREFIX IN ('DEV', 'SDEV')
            OR CLASSIFICATION = 'Fejlesztési igény (RFC)';

COMMIT;


ALTER TABLE t_dev_milestones
ADD
(
demand_start date,
release_start date,
backlog_end date,
uat_start date,
uat_end date,
aborted char(2)
);
COMMIT;


UPDATE   t_dev_milestones a
   SET   demand_start =
            (SELECT   MIN (modifieddate)
               FROM   KASPERSK.issuestatuslog b
              WHERE   a.oid = b.issue
                      AND REGEXP_LIKE (b.issuestatenew,
                                       '^#02.*|^02.*|^S02.*'));
    
                                      
UPDATE   t_dev_milestones a
   SET   backlog_end =
            (SELECT   MIN (modifieddate)
               FROM   KASPERSK.issuestatuslog b
              WHERE   a.oid = b.issue
                      AND REGEXP_LIKE (b.issuestatenew,
                                       '^#17.*|^12.*|^S17.*'));
                                       

UPDATE   t_dev_milestones a
   SET   release_start =
            (SELECT   MIN (modifieddate)
               FROM   KASPERSK.issuestatuslog b
              WHERE   a.oid = b.issue
                      AND REGEXP_LIKE (b.issuestatenew,
                                       '^#13.*|^10.*|^S15.*'));
                                       
UPDATE   t_dev_milestones a
   SET   uat_start =
            (SELECT   MIN (modifieddate)
               FROM   KASPERSK.issuestatuslog b
              WHERE   a.oid = b.issue
                      AND REGEXP_LIKE (b.issuestatenew,
                                       '^#27.*|^17.*|^S27.*'));


UPDATE   t_dev_milestones a
   SET   uat_end =
            (SELECT   MIN (modifieddate)
               FROM   KASPERSK.issuestatuslog b
              WHERE   a.oid = b.issue
                      AND REGEXP_LIKE (b.issuestatenew,
                                       '^#28.*|^18.*|^S28.*'));
COMMIT;


UPDATE   t_dev_milestones a
   SET   aborted = 'I'
 WHERE   EXISTS
            (SELECT   1
               FROM   KASPERSK.issuestatuslog b
              WHERE   a.oid = b.issue
                      AND REGEXP_LIKE (
                            b.issuestatenew,
                            '^#01.*|^22.*|^23.*|^24.*|^M1.*|^M2.*'
                         ));

COMMIT;



/* Query FTE for development phases */
DROP TABLE t_dev_fte_phases;
COMMIT;

CREATE TABLE t_dev_fte_phases
AS
   SELECT   *
     FROM   (  SELECT   a.*,
                        wts_total_hours.user_worktimesheet,
                        wts_total_hours.userorg_worktimesheet,
                        wts_total_hours.created_worktimesheet,
                        wts_total_hours.hours_worktimesheet,
                        CASE
                           WHEN a.release_start IS NOT NULL
                                AND wts_total_hours.created_worktimesheet <
                                      a.release_start
                           THEN
                              'Demand'
                           WHEN a.release_start IS NOT NULL
                                AND wts_total_hours.created_worktimesheet >=
                                      a.release_start
                           THEN
                              'Release'
                        END
                           AS phase
                 FROM      t_dev_milestones a
                        LEFT JOIN
                           (SELECT   a.issue,
                                     b.name AS user_worktimesheet,
                                     c.name AS userorg_worktimesheet,
                                     a.created AS created_worktimesheet,
                                     a.hours AS hours_worktimesheet
                              FROM         KASPERSK.worktimesheet a
                                        LEFT JOIN
                                           KASPERSK.permissionpolicyuser b
                                        ON a.owner = b.oid
                                     LEFT JOIN
                                        KASPERSK.organization c
                                     ON b.defaultorganization = c.oid
                             WHERE   timetype = 'WorkTime') wts_total_hours
                        ON a.oid = wts_total_hours.issue
             ORDER BY   CASE, created, created_worktimesheet)
    WHERE   hours_worktimesheet IS NOT NULL;

COMMIT;