/* Get distinct tickets with descriptives */
SELECT   DISTINCT
         i.REGISTRATIONID AS CASE,
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
         CLASS.REGISTRATIONIDPREFIX AS CLASS_SHORT,
         i.vip,
         adminstep.admin_step
  FROM                           KASPERSK.ISSUE i
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
                                             ON app.oid = issueapp.applications
                                  ORDER BY   issueapp.issues) distappgroup
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
                                  (               /* get date of end status */
                                   SELECT   MAX (statusLast.MODIFIEDDATE)
                                     FROM   KASPERSK.ISSUESTATUSLOG statusLast
                                    WHERE   statusLast.ISSUE = status.ISSUE))
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
 WHERE   UPPER (i.TITLE) NOT LIKE 'PRÓBA%'