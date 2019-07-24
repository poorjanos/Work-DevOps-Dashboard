/* Get distinct development tickets with descriptives */
DROP TABLE t_dev_milestones;
COMMIT;

CREATE TABLE t_dev_milestones
AS
   SELECT   *
     FROM   (SELECT   DISTINCT
                      i.oid,
                      i.REGISTRATIONID AS CASE,
                      i.CREATED AS CREATED,
                      last_status_equals_case_closed.TIMESTAMP AS CLOSED,
                      i.TITLE AS ISSUE_TITLE,
                      i.APPLICATIONLIST AS application,
                      UPPER (application_group.application_group_concat)
                         AS application_group_concat,
                      bu.NAME AS BUSINESSEVENT_UNIT,
                      co.NAME AS COMPANY,
                      org.NAME AS ORGANIZATION,
                      class.NAME AS CLASSIFICATION,
                      CLASS.REGISTRATIONIDPREFIX AS CLASS_SHORT,
                      i.vip
               FROM                     KASPERSK.ISSUE i
                                     LEFT JOIN
                                        KASPERSK.BUSINESSUNIT bu
                                     ON bu.OID = i.BUSINESSUNIT
                                  LEFT JOIN
                                     KASPERSK.COMPANY co
                                  ON co.OID = bu.COMPANY
                               LEFT JOIN
                                  KASPERSK.ORGANIZATION org
                               ON org.OID = i.ORGANIZATION
                            LEFT JOIN
                               KASPERSK.CLASSIFICATION class
                            ON class.OID = i.CLASSIFICATION
                         LEFT JOIN
                            (  SELECT   distappgroup.issues,
                                        LISTAGG (
                                           distappgroup.applicationgroup,
                                           '/'
                                        )
                                           WITHIN GROUP (ORDER BY
                                                            distappgroup.applicationgroup)
                                           AS application_group_concat
                                 FROM   (  SELECT   DISTINCT
                                                    issueapp.issues,
                                                    app.applicationgroup
                                             FROM      KASPERSK.ISSUEISSUES_APPLICATI_BF90650B issueapp
                                                    INNER JOIN
                                                       KASPERSK.application app
                                                    ON app.oid =
                                                          issueapp.applications
                                         ORDER BY   issueapp.issues)
                                        distappgroup
                             GROUP BY   distappgroup.issues)
                            application_group
                         ON application_group.issues = i.oid
                      LEFT JOIN
                         (SELECT   status.ISSUE,
                                   status.MODIFIEDDATE AS TIMESTAMP,
                                   status.ISSUESTATENEW AS ACTIVITY
                            FROM      KASPERSK.ISSUESTATUSLOG status
                                   INNER JOIN
                                      KASPERSK.ISSUESTATUSLOG case_closed
                                   ON case_closed.OID = status.OID
                           WHERE   REGEXP_LIKE (
                                      case_closed.ISSUESTATENEW,
                                      '^#01.*|^#29.*|^20.*|^21.*|^22.*|^23.*|^24.*|^H08.*|^H14.*|^H10.*|^H11.*|^H09.*|^H12.*|^H13.*|^S31.*'
                                   )
                                   AND status.MODIFIEDDATE =
                                         (        /* get date of end status */
                                          SELECT   MAX (
                                                      statusLast.MODIFIEDDATE
                                                   )
                                            FROM   KASPERSK.ISSUESTATUSLOG statusLast
                                           WHERE   statusLast.ISSUE =
                                                      status.ISSUE))
                         last_status_equals_case_closed
                      ON last_status_equals_case_closed.ISSUE = i.OID)
    WHERE   class_short in ('DEV', 'SDEV') or CLASSIFICATION = 'Fejleszt�si ig�ny (RFC)';

COMMIT;


/* Drop small development tickets */
DELETE FROM   t_dev_milestones
      WHERE   class_short = 'DEV' and vip = 1 AND created < DATE '2019-07-05';

COMMIT;



ALTER TABLE t_dev_milestones
ADD
(
release_start date,
total_steps number,
distinct_steps number,
aborted char(2)
);
COMMIT;


UPDATE t_dev_milestones a
set release_start = (select min(modifieddate) from KASPERSK.issuestatuslog b
where a.oid = b.issue
and REGEXP_LIKE (b.issuestatenew, '^#13.*|^10.*|^S15.*'));
COMMIT;


UPDATE t_dev_milestones a
set total_steps = (select count(issuestatenew) from KASPERSK.issuestatuslog b
where a.oid = b.issue);
COMMIT;


UPDATE t_dev_milestones a
set distinct_steps = (select count(distinct issuestatenew) from KASPERSK.issuestatuslog b
where a.oid = b.issue);
COMMIT;


UPDATE t_dev_milestones a
set aborted = 'I' where exists (select 1 from KASPERSK.issuestatuslog b
where a.oid = b.issue
and REGEXP_LIKE (b.issuestatenew, '^#01.*|^22.*|^23.*|^24.*|^M1.*|^M2.*'));
COMMIT;



/* Query FTE for development phases */
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