/* Workhours per month NOT only for closed cases */
  SELECT   DISTINCT
           i.REGISTRATIONID AS CASE,
           i.CREATED AS CREATED,
           i.TITLE AS ISSUE_TITLE,
           i.APPLICATIONLIST AS application,
           UPPER (application_group.application_group_concat)
              AS application_group_concat,
           class.NAME AS CLASSIFICATION,
           CLASS.REGISTRATIONIDPREFIX as CLASS_SHORT,
           i.vip,
           wts_total_hours.month_worktimesheet,
           UPPER(wts_total_hours.user_worktimesheet) as user_worktimesheet,
           UPPER(wts_total_hours.userorg_worktimesheet) as userorg_worktimesheet,
           wts_total_hours.hours_worktimesheet
    FROM               KASPERSK.issue i
                    LEFT JOIN
                       KASPERSK.CLASSIFICATION class
                    ON class.OID = i.CLASSIFICATION
                 LEFT JOIN
                    (  SELECT   issue,
                                b.name as user_worktimesheet,
                                c.name as userorg_worktimesheet,
                                TRUNC (created, 'mm') AS month_worktimesheet,
                                SUM (hours) AS hours_worktimesheet
                         FROM      KASPERSK.worktimesheet a
                                LEFT JOIN
                                   KASPERSK.permissionpolicyuser b
                                ON a.owner = b.oid
                                LEFT JOIN 
                                    KASPERSK.organization c
                                ON b.defaultorganization = c.oid
                        WHERE   timetype = 'WorkTime'
                     GROUP BY   issue, b.name, c.name, TRUNC (created, 'mm'))
                    wts_total_hours
                 ON i.oid = wts_total_hours.issue
              LEFT JOIN
                 KASPERSK.CLASSIFICATION class
              ON class.OID = i.CLASSIFICATION
           INNER JOIN
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
ORDER BY   1, 7