/* Formatted on 2019. 09. 30. 12:45:44 (QP5 v5.115.810.9015) */
/******************************************************************************/

/* Generate view of tickets with descriptive fields */

/* Includes open and closed tickets */

/* Includes all ticket types */

/******************************************************************************/
DROP TABLE t_isd_tickets;
COMMIT;

CREATE TABLE t_isd_tickets
AS
   SELECT   DISTINCT
            i.oid,
            i.REGISTRATIONID AS CASE_ID,
            i.CREATED AS CREATED,
            last_status_equals_case_closed.TIMESTAMP AS CLOSED,
            last_event.ACTIVITY AS LAST_EVENT,
            last_event.TIMESTAMP AS LAST_EVENT_DATE,
            i.TITLE AS ISSUE_TITLE,
            i.APPLICATIONLIST AS application,
            UPPER (application_group.application_group_concat)
               AS application_group_concat,
            bu.NAME AS BUSINESSEVENT_UNIT,
            co.NAME AS COMPANY,
            org.NAME AS ORGANIZATION,
            class.NAME AS CLASSIFICATION,
            CLASS.REGISTRATIONIDPREFIX,
            i.vip,
            CASE
               WHEN i.vip = 1 THEN 'VIP'
               ELSE CLASS.REGISTRATIONIDPREFIX
            END
               AS CLASS_SHORT,
            adminstep.admin_step,
            steps.total_steps,
            steps.distinct_steps,
            CASE
               --DEV conformance
            WHEN last_status_equals_case_closed.TIMESTAMP IS NOT NULL
                 AND CLASS.REGISTRATIONIDPREFIX = 'DEV'
                 AND ( (last_status_equals_case_closed.TIMESTAMP <
                           DATE '2019-03-14'
                        AND steps.distinct_steps >= 29)
                      OR (i.CREATED >= DATE '2019-03-14'
                          AND steps.distinct_steps >= 30)
                      OR (i.CREATED < DATE '2019-03-14'
                          AND last_status_equals_case_closed.TIMESTAMP >=
                                DATE '2019-03-14'
                          AND ( (EXISTS
                                    (SELECT   1
                                       FROM   KASPERSK.ISSUESTATUSLOG s
                                      WHERE   ISSUESTATENEW LIKE '#00%'
                                              AND i.oid = s.issue)
                                 AND steps.distinct_steps >= 30)
                               OR (NOT EXISTS
                                      (SELECT   1
                                         FROM   KASPERSK.ISSUESTATUSLOG s
                                        WHERE   ISSUESTATENEW LIKE '#00%'
                                                AND i.oid = s.issue)
                                   AND steps.distinct_steps >= 29))))
               THEN
                  'I'
               --VIP conformance
            WHEN last_status_equals_case_closed.TIMESTAMP IS NOT NULL
                 AND i.vip = 1
                 AND ( (last_status_equals_case_closed.TIMESTAMP <
                           DATE '2019-03-14'
                        AND steps.distinct_steps >= 26)
                      OR (i.CREATED >= DATE '2019-03-14'
                          AND steps.distinct_steps >= 27)
                      OR (i.CREATED < DATE '2019-03-14'
                          AND last_status_equals_case_closed.TIMESTAMP >=
                                DATE '2019-03-14'
                          AND ( (EXISTS
                                    (SELECT   1
                                       FROM   KASPERSK.ISSUESTATUSLOG s
                                      WHERE   ISSUESTATENEW LIKE '#00%'
                                              AND i.oid = s.issue)
                                 AND steps.distinct_steps >= 26)
                               OR (NOT EXISTS
                                      (SELECT   1
                                         FROM   KASPERSK.ISSUESTATUSLOG s
                                        WHERE   ISSUESTATENEW LIKE '#00%'
                                                AND i.oid = s.issue)
                                   AND steps.distinct_steps >= 27))))
               THEN
                  'I'
               --SDEV conformance
            WHEN     last_status_equals_case_closed.TIMESTAMP IS NOT NULL
                 AND CLASS.REGISTRATIONIDPREFIX = 'SDEV'
                 AND steps.distinct_steps >= 16
               THEN
                  'I'
            END
               AS conform
     FROM                              KASPERSK.ISSUE i
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
                        /* Add appgroup */
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
                            GROUP BY   distappgroup.issues) application_group
                        ON application_group.issues = i.oid
                     /* Add close date */
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
                                        (         /* get date of end status */
                                         SELECT   MAX (
                                                     statusLast.MODIFIEDDATE
                                                  )
                                           FROM   KASPERSK.ISSUESTATUSLOG statusLast
                                          WHERE   statusLast.ISSUE =
                                                     status.ISSUE))
                        last_status_equals_case_closed
                     ON last_status_equals_case_closed.ISSUE = i.OID
                  /* Add last event */
                  LEFT JOIN
                     (SELECT   DISTINCT
                               status.ISSUE,
                               FIRST_VALUE(status.MODIFIEDDATE)
                                  OVER (PARTITION BY status.ISSUE
                                        ORDER BY status.MODIFIEDDATE DESC)
                                  AS TIMESTAMP,
                               FIRST_VALUE(status.ISSUESTATENEW)
                                  OVER (PARTITION BY status.ISSUE
                                        ORDER BY status.MODIFIEDDATE DESC)
                                  AS ACTIVITY
                        FROM   KASPERSK.ISSUESTATUSLOG status) last_event
                  ON last_event.ISSUE = i.OID
               /* Add admin step flag */
               LEFT JOIN
                  (SELECT   DISTINCT status.issue, 'I' AS admin_step
                     FROM   KASPERSK.ISSUESTATUSLOG status,
                            KASPERSK.PERMISSIONPOLICYUSER isduser
                    WHERE   status."USER" = isduser.oid
                            AND NOT REGEXP_LIKE (
                                       status.ISSUESTATENEW,
                                       '^#01.*|^#29.*|^20.*|^21.*|^22.*|^23.*|^24.*|^H08.*|^H14.*|^H10.*|^H11.*|^H09.*|^H12.*|^H13.*|^S31.*'
                                    )
                            AND (isduser.name IN
                                       ('Szabó, Gyula Szilveszter',
                                        'Galavics, Zsuzsanna',
                                        'Kardos, Krisztián',
                                        'Dávid, Gábor Péter')
                                 OR (isduser.name = 'Biró, Bálint Sándor'
                                     AND TRUNC (status.modifieddate, 'ddd') =
                                           DATE '2019-05-16'))) adminstep
               ON adminstep.issue = i.oid
            /* Add step counts */
            LEFT JOIN
               (  SELECT   status.issue,
                           COUNT (status.issuestatenew) AS total_steps,
                           COUNT (DISTINCT status.issuestatenew)
                              AS distinct_steps
                    FROM   KASPERSK.issuestatuslog status
                GROUP BY   status.issue) steps
            ON steps.issue = i.oid
    WHERE   UPPER (i.TITLE) NOT LIKE 'PRÓBA%';

COMMIT;



UPDATE   t_isd_tickets
   SET   conform = 'N'
 WHERE   conform IS NULL AND closed IS NOT NULL and class_short in ('DEV', 'VIP', 'SDEV');
COMMIT;