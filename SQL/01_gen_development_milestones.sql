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
    WHERE   REGISTRATIONIDPREFIX IN ('DEV', 'SDEV')
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
aborted char(2),
start_close_days number,
pre_demand_days number,
demand_days number,
release_days number,
start_close_net_days number,
demand_net_days number,
release_net_days number
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

UPDATE   t_dev_milestones a
   SET   start_close_days = closed - created
 WHERE   closed IS NOT NULL;

COMMIT;

UPDATE   t_dev_milestones a
   SET   pre_demand_days = demand_start - created
 WHERE   created IS NOT NULL AND demand_start IS NOT NULL;

COMMIT;

UPDATE   t_dev_milestones a
   SET   demand_days = release_start - demand_start
 WHERE   release_start IS NOT NULL AND demand_start IS NOT NULL;

COMMIT;

UPDATE   t_dev_milestones a
   SET   release_days = closed - release_start
 WHERE   release_start IS NOT NULL AND closed IS NOT NULL;

COMMIT;


/******************************************************************************/

/* Generate table of pending days  due to voting for development tickets */

/* Depends on t_dev_milestones */

/* Includes open and closed tickets */

/******************************************************************************/
DROP TABLE t_dev_wait_time;
COMMIT;

CREATE TABLE t_dev_wait_time
AS
     SELECT                       /* Group wait times by phases for tickets */
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
                                OR (class_short = 'SDEV'
                                    AND step IN ('S09-S15'))
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
                                              REGEXP_SUBSTR (
                                                 status.ISSUESTATENEW,
                                                 '[#S]*\d{2}\w*'
                                              )
                                                 AS activity_code,
                                              LAG(REGEXP_SUBSTR (
                                                     status.ISSUESTATENEW,
                                                     '[#S]*\d{2}\w*'
                                                  ))
                                                 OVER (
                                                    PARTITION BY tickets.oid
                                                    ORDER BY status.MODIFIEDDATE
                                                 )
                                                 AS lag_activity_code,
                                              status.MODIFIEDDATE AS TIMESTAMP,
                                              LAG(status.MODIFIEDDATE)
                                                 OVER (
                                                    PARTITION BY tickets.oid
                                                    ORDER BY status.MODIFIEDDATE
                                                 )
                                                 AS lag_timestamp
                                       FROM      t_dev_milestones tickets
                                              LEFT JOIN
                                                 KASPERSK.ISSUESTATUSLOG status
                                              ON tickets.oid = status.issue
                                   ORDER BY   tickets.case_id,
                                              status.MODIFIEDDATE)
                          WHERE   (class_short = 'DEV'
                                   AND   lag_activity_code
                                      || '-'
                                      || activity_code IN
                                            ('#03-#04',               --demand
                                             '#05-#06',
                                             '#07-#08',
                                             '#09-#10',
                                             '#12-#13',
                                             '#16-#17',              --release
                                             '#18-#19',
                                             '#21-#22',
                                             '#24-#26',
                                             '#27A-#28',
                                             '#28-#29'))
                                  OR (class_short = 'VIP'
                                      AND   lag_activity_code
                                         || '-'
                                         || activity_code IN
                                               ('#05-#06',            --demand
                                                '#09-#10',
                                                '#16-#17',           --release
                                                '#18-#19',
                                                '#21-#22',
                                                '#24-#26',
                                                '#27A-#28',
                                                '#28-#29'))
                                  OR (class_short = 'SDEV'
                                      AND   lag_activity_code
                                         || '-'
                                         || activity_code IN
                                               ('S09-S15',            --demand
                                                'S16-S17',           --release
                                                'S27A-S28'))
                                  OR (class_short = 'RFC'
                                      AND   lag_activity_code
                                         || '-'
                                         || activity_code IN
                                               ('09-10',              --demand
                                                        '17-18'))    --release
                                                                 ))
   GROUP BY   oid,
              case_id,
              class_short,
              wait_phase
   ORDER BY   oid,
              case_id,
              class_short,
              wait_phase;

COMMIT;



/******************************************************************************/

/* Update t_dev_milestones with wait times */

/* Depends on t_dev_milestones and t_dev_wait_time*/

/* Includes open and closed tickets */

/******************************************************************************/
ALTER TABLE t_dev_milestones
ADD
(
demand_wait_days number,
release_wait_days number
);
COMMIT;

UPDATE   t_dev_milestones a
   SET   demand_wait_days =
            (SELECT   wait_time_day
               FROM   t_dev_wait_time b
              WHERE   a.oid = b.oid AND b.wait_phase = 'demand');

COMMIT;

UPDATE   t_dev_milestones a
   SET   demand_wait_days = 0
 WHERE   demand_wait_days IS NULL;

COMMIT;

UPDATE   t_dev_milestones a
   SET   release_wait_days =
            (SELECT   wait_time_day
               FROM   t_dev_wait_time b
              WHERE   a.oid = b.oid AND b.wait_phase = 'release');

COMMIT;

UPDATE   t_dev_milestones a
   SET   release_wait_days = 0
 WHERE   release_wait_days IS NULL;

COMMIT;

UPDATE   t_dev_milestones a
   SET   start_close_net_days =
            start_close_days - demand_wait_days - release_wait_days
 WHERE   start_close_days IS NOT NULL
         AND (demand_wait_days >= 0 OR release_wait_days >= 0);

COMMIT;

UPDATE   t_dev_milestones a
   SET   demand_net_days = demand_days - demand_wait_days
 WHERE   demand_days IS NOT NULL;

COMMIT;

UPDATE   t_dev_milestones a
   SET   release_net_days = release_days - release_wait_days
 WHERE   release_days IS NOT NULL;

COMMIT;