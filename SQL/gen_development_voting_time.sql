/* Compute pending days due to voting for development tickets */
  SELECT                          /* Group wait times by phases for tickets */
        oid,
           case_id,
           class_short,
           wait_phase,
           SUM (wait_time_day) AS wait_time_day
    FROM   (SELECT /* Flag waiting times for demand and release phases separately */
                  oid,
                     case_id,
                     class_short,
                     activity,
                     step,
                     timestamp,
                     lag_timestamp,
                     wait_time_day,
                     CASE
                        WHEN (class_short = 'DEV'
                              AND step IN
                                       ('#03-#04',
                                        '#05-#06',
                                        '#07-#08',
                                        '#09-#10',
                                        '#12-#13'))
                             OR (class_short = 'VIP'
                                 AND step IN ('#05-#06', '#09-#10'))
                             OR (class_short = 'SDEV' AND step IN ('S09-S15'))
                             OR (class_short = 'RFC' AND step IN ('09-10'))
                        THEN
                           'demand'
                        ELSE
                           'release'
                     END
                        AS wait_phase
              FROM   (SELECT /* Generate from-to phases for voting times for different ticket types */
                            oid,
                               case_id,
                               class_short,
                               activity,
                               lag_activity_code || '-' || activity_code
                                  AS step,
                               timestamp,
                               lag_timestamp,
                               timestamp - lag_timestamp AS wait_time_day
                        FROM   (  SELECT   tickets.oid,
                                           tickets.case_id,
                                           tickets.class_short,
                                           status.ISSUESTATENEW AS ACTIVITY,
                                           REGEXP_SUBSTR (status.ISSUESTATENEW,
                                                          '[#S]*\d{2}\w*')
                                              AS activity_code,
                                           LAG(REGEXP_SUBSTR (
                                                  status.ISSUESTATENEW,
                                                  '[#S]*\d{2}\w*'
                                               ))
                                              OVER (PARTITION BY tickets.oid
                                                    ORDER BY status.MODIFIEDDATE)
                                              AS lag_activity_code,
                                           status.MODIFIEDDATE AS TIMESTAMP,
                                           LAG(status.MODIFIEDDATE)
                                              OVER (PARTITION BY tickets.oid
                                                    ORDER BY status.MODIFIEDDATE)
                                              AS lag_timestamp
                                    FROM      t_dev_milestones tickets
                                           LEFT JOIN
                                              KASPERSK.ISSUESTATUSLOG status
                                           ON tickets.oid = status.issue
                                ORDER BY   tickets.case_id, status.MODIFIEDDATE)
                       WHERE   (class_short = 'DEV'
                                AND lag_activity_code || '-' || activity_code IN
                                         ('#03-#04',                  --demand
                                          '#05-#06',
                                          '#07-#08',
                                          '#09-#10',
                                          '#12-#13',
                                          '#16-#17',                 --release
                                          '#18-#19',
                                          '#21-#22',
                                          '#24-#26',
                                          '#27A-#28',
                                          '#28-#29'))
                               OR (class_short = 'VIP'
                                   AND   lag_activity_code
                                      || '-'
                                      || activity_code IN
                                            ('#05-#06',               --demand
                                             '#09-#10',
                                             '#16-#17',              --release
                                             '#18-#19',
                                             '#21-#22',
                                             '#24-#26',
                                             '#27A-#28',
                                             '#28-#29'))
                               OR (class_short = 'SDEV'
                                   AND   lag_activity_code
                                      || '-'
                                      || activity_code IN
                                            ('S09-S15',               --demand
                                                       'S16-S17',    --release
                                                                 'S27A-S28'))
                               OR (class_short = 'RFC'
                                   AND   lag_activity_code
                                      || '-'
                                      || activity_code IN
                                            ('09-10',                 --demand
                                                     '17-18'))       --release
                                                              ))
GROUP BY   oid,
           case_id,
           class_short,
           wait_phase
ORDER BY   oid,
           case_id,
           class_short,
           wait_phase;