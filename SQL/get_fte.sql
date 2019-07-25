/* Workhours per month NOT only for closed cases */
  SELECT   DISTINCT
           i.REGISTRATIONID AS CASE,
           i.CREATED AS CREATED,
           last_status_equals_case_closed.TIMESTAMP AS CLOSED,
           i.TITLE AS ISSUE_TITLE,
           i.APPLICATIONLIST AS application,
           UPPER (application_group.application_group_concat)
              AS application_group_concat,
           class.NAME AS CLASSIFICATION,
           CLASS.REGISTRATIONIDPREFIX AS CLASS_SHORT,
           i.vip,
           wts_total_hours.month_worktimesheet,
           UPPER (wts_total_hours.user_worktimesheet) AS user_worktimesheet,
           UPPER (wts_total_hours.userorg_worktimesheet)
              AS userorg_worktimesheet,
           wts_total_hours.hours_worktimesheet
    FROM               KASPERSK.issue i
                    LEFT JOIN
                       KASPERSK.CLASSIFICATION class
                    ON class.OID = i.CLASSIFICATION
                 LEFT JOIN
                    (  SELECT   issue,
                                b.name AS user_worktimesheet,
                                c.name AS userorg_worktimesheet,
                                TRUNC (created, 'mm') AS month_worktimesheet,
                                SUM (hours) AS hours_worktimesheet
                         FROM         KASPERSK.worktimesheet a
                                   LEFT JOIN
                                      KASPERSK.permissionpolicyuser b
                                   ON a.owner = b.oid
                                LEFT JOIN
                                   KASPERSK.organization c
                                ON b.defaultorganization = c.oid
                        WHERE   timetype = 'WorkTime'
                     GROUP BY   issue,
                                b.name,
                                c.name,
                                TRUNC (created, 'mm')) wts_total_hours
                 ON i.oid = wts_total_hours.issue
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
                             WITHIN GROUP (ORDER BY distappgroup.applicationgroup)
                             AS application_group_concat
                   FROM   (  SELECT   DISTINCT
                                      issueapp.issues, app.applicationgroup
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
             WHERE   UPPER (i.TITLE) NOT LIKE 'PRÓBA%'
ORDER BY   1, 7