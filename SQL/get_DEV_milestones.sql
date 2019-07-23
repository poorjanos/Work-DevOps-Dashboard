/* Formatted on 2019. 07. 23. 14:50:07 (QP5 v5.115.810.9015) */
/* Get distinct tickets with descriptives */
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
                                      '^#01.*|^#29.*|^20.*|^22.*|^24.*|^H08.*|^H14.*|^H10.*|^H11.*|^H09.*|^H12.*|^H13.*'
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
    WHERE   class_short = 'DEV';

COMMIT;

DELETE FROM   t_dev_milestones
      WHERE   vip = 1 AND created < DATE '2019-07-05';

COMMIT;



ALTER TABLE t_dev_milestones
ADD
(
release_start date,
sat_start date,
uat_start date
);
COMMIT;


UPDATE t_dev_milestones a
set release_start = (select min(modifieddate) from KASPERSK.issuestatuslog b
where a.oid = b.issue
and issuestatenew = '#13 Projekt indítás');
COMMIT;

UPDATE t_dev_milestones a
set sat_start = (select min(modifieddate) from KASPERSK.issuestatuslog b
where a.oid = b.issue
and issuestatenew = '#20 A rendszer elfogadási tesztelés (SAT)');
COMMIT;


UPDATE t_dev_milestones a
set uat_start = (select min(modifieddate) from KASPERSK.issuestatuslog b
where a.oid = b.issue
and issuestatenew = '#27 UAT, és performancia  tesztelés');
COMMIT;
